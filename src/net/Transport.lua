--[[ Transport.lua — reliable delivery over an unreliable frame channel (pure core).

  Pure and testable: the actual WoW calls are INJECTED. The thin in-game shell
  provides `send(wire, channel, target)` (-> ChatThrottleLib:SendAddonMessage with
  the addon prefix), filters CHAT_MSG_ADDON by prefix and calls onFrame(sender,
  wire, channel), and drives tick() from an OnUpdate. Everything below — chunking,
  ACK, retransmit-until-acked, duplicate suppression, reassembly — is unit-tested
  against a simulated drop/reorder/duplicate channel in test/test_transport.lua.

  Reliability model:
    * send()         fire-and-forget (broadcasts + non-critical msgs).
    * sendReliable() point-to-point WHISPER, retransmitted every `retransmitTicks`
                     until the target ACKs, or `maxRetries` -> onFailure().
    * The receiver auto-ACKs WHISPERed data messages (the point-to-point reliable
      path); broadcast reliability is layered above by the Session (per-client ACK
      tracking + targeted reliable resend), so Transport never floods ACKs.
    * Every data message is delivered to the app at most once (dedupe by
      (sender,msgid)); duplicates are re-ACKed but not re-delivered.
  Transport-level control ops (ACK) are handled internally, never delivered.
]]

local ADDON, ns = ...
local Protocol, Util, Const = ns.Protocol, ns.Util, ns.Const
local OP = Const.OP

local Transport = {}
Transport.__index = Transport

-- cfg = {
--   selfName, protoVer (default Const.PROTO_VER), maxText (default Protocol.maxText(Const.PREFIX)),
--   send = function(wire, channel, target) end,         -- REQUIRED (injected)
--   deliver = function(sender, payload, channel) end,    -- app callback for data msgs
--   onFailure = function(msgid, target) end,             -- reliable msg gave up
--   retransmitTicks (default 4), maxRetries (default 6), retentionTicks (default 300),
-- }
function Transport.new(cfg)
  if type(cfg.send) ~= "function" then error("Transport.new: cfg.send is required") end
  return setmetatable({
    selfName = cfg.selfName or "self",
    -- Unique per-connection epoch prefix for msgids. After a relog a fresh Transport
    -- must NOT reuse msgids the peer still remembers (it would dedupe them away), so
    -- the in-game shell sets this from a per-session value (GetTime()/login nonce).
    epoch = cfg.epoch or "",
    protoVer = cfg.protoVer or Const.PROTO_VER,
    maxText = cfg.maxText or Protocol.maxText(Const.PREFIX),
    send = cfg.send,
    deliver = cfg.deliver,
    onFailure = cfg.onFailure,
    onWrongVersion = cfg.onWrongVersion,   -- fn(sender, theirProtoVer): mismatch notice
    retransmitTicks = cfg.retransmitTicks or 4,
    maxRetries = cfg.maxRetries or 6,
    retentionTicks = cfg.retentionTicks or 300,
    nextId = 1,
    reasm = Protocol.newReassembler(),
    outbound = {},     -- msgid -> { frames, target, retries, sinceSend, acked }
    completed = {},    -- sender -> { msgid -> ageTicks }  (dedupe + re-ACK)
  }, Transport)
end

function Transport:_msgid()
  local id = Util.toBase36(self.nextId)
  self.nextId = self.nextId + 1
  if self.epoch ~= "" then return self.epoch .. "." .. id end
  return id
end

function Transport:_emit(payload, channel, target)
  local msgid = self:_msgid()
  local frames = Protocol.buildMessages(self.protoVer, msgid, payload, self.maxText)
  for i = 1, #frames do self.send(frames[i], channel, target) end
  return msgid, frames
end

-- fire-and-forget (broadcast or whisper); no retransmit, no ACK expected
function Transport:post(payload, channel, target)
  return (self:_emit(payload, channel, target))
end

-- point-to-point reliable: WHISPER `target`, retransmit until ACKed
function Transport:sendReliable(payload, target)
  local msgid, frames = self:_emit(payload, "WHISPER", target)
  self.outbound[msgid] = { frames = frames, target = target, retries = 0, sinceSend = 0, acked = false }
  return msgid
end

function Transport:_sendAck(sender, dataMsgid)
  local payload = Protocol.encode(OP.ACK, { dataMsgid })
  local frames = Protocol.buildMessages(self.protoVer, self:_msgid(), payload, self.maxText)
  self.send(frames[1], "WHISPER", sender)   -- ACK is small -> single frame
end

function Transport:_handleAck(payload)
  local _, fields = Protocol.decode(payload)
  local acked = Protocol.leaf(fields[1])
  self.outbound[acked] = nil
end

-- called by the in-game shell for each inbound CHAT_MSG_ADDON frame (prefix-filtered)
function Transport:onFrame(sender, wire, channel)
  local fr = Protocol.parseFrame(wire)
  if not fr then return end
  if fr.protoVer ~= self.protoVer then
    -- incompatible build: drop — but TELL the user once per sender (a silent drop
    -- reads as "the addon is broken" when versions drift inside a guild)
    if self.onWrongVersion then
      self.warnedVer = self.warnedVer or {}
      if not self.warnedVer[sender] then
        self.warnedVer[sender] = true
        self.onWrongVersion(sender, fr.protoVer)
      end
    end
    return
  end

  -- duplicate of an already-delivered data message: re-ACK (in case our ACK was
  -- lost) and drop without re-delivering.
  local comp = self.completed[sender]
  if comp and comp[fr.msgid] ~= nil then
    if channel == "WHISPER" then self:_sendAck(sender, fr.msgid) end
    return
  end

  local status, val = self.reasm:accept(sender, fr.msgid, fr.seq, fr.total, fr.payload)
  if status ~= "complete" then return end

  local op = Protocol.decode(val)
  if op == OP.ACK then
    self:_handleAck(val)
    return
  end
  -- data message: dedupe-record, ACK (whispered/reliable path), deliver once
  comp = self.completed[sender]
  if not comp then comp = {}; self.completed[sender] = comp end
  comp[fr.msgid] = 0
  if channel == "WHISPER" then self:_sendAck(sender, fr.msgid) end
  if self.deliver then self.deliver(sender, val, channel) end
end

-- advance the clock: retransmit unacked reliable messages, age dedupe records
function Transport:tick()
  for msgid, o in pairs(self.outbound) do
    o.sinceSend = o.sinceSend + 1
    if o.sinceSend >= self.retransmitTicks then
      if o.retries >= self.maxRetries then
        self.outbound[msgid] = nil
        if self.onFailure then self.onFailure(msgid, o.target) end
      else
        for i = 1, #o.frames do self.send(o.frames[i], "WHISPER", o.target) end
        o.retries = o.retries + 1
        o.sinceSend = 0
      end
    end
  end
  -- age + evict dedupe records
  for sender, msgs in pairs(self.completed) do
    for msgid, age in pairs(msgs) do
      local a = age + 1
      if a > self.retentionTicks then msgs[msgid] = nil else msgs[msgid] = a end
    end
  end
end

-- number of reliable messages still awaiting ACK (for tests / UI)
function Transport:pendingReliable()
  local n = 0
  for _ in pairs(self.outbound) do n = n + 1 end
  return n
end

ns.Transport = Transport
return Transport
