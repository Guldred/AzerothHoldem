--[[ Casino.lua — the multi-table router + lifecycle (pure; Transport/clock injected).

  Owns one Transport over the shared guild/raid channel and multiplexes many tables
  onto it by TAGGING each app payload with a routing prefix, ABOVE the Transport
  layer — so chunking, ACK/retransmit, dedupe, and the STATEHASH anti-equivocation
  security are all untouched:
    tag "0"        -> lobby/control (TABLE ads, JOIN, SEAT, LEAVE): everyone hears.
    tag = tableId  -> a table's gameplay: routed only to that table's participants.
  (tableId = the host's character name — naturally unique within a guild/raid.)

  A player is, at most, hosting one table (a TableHost) OR seated at one (a Client),
  while seeing lobby ads for all. Strictly additive: the existing single-table path
  is unaffected.
]]

local ADDON, ns = ...
local Codec = ns.Codec
local OP = ns.Const.OP

local Casino = {}
Casino.__index = Casino

local SEP = "|"
local LOBBY = "0"

-- cfg = { transport, selfName, broadcast, entropy=fn()->{r,salt}, nonces=fn()->{52},
--   onCheat, defaultStack, policy, human, lobbyTtl, adInterval }
function Casino.new(cfg)
  return setmetatable({
    tp = cfg.transport, me = cfg.selfName, broadcast = cfg.broadcast or "RAID", cfg = cfg,
    -- exact-release gate: a table only seats players on the SAME addon version
    -- (mixed releases degrade subtly — "everyone updates together" is the rule).
    -- Injectable for tests; defaults to this build's version.
    ver = cfg.version or ns.Const.ADDON_VER,
    lobby = ns.Lobby.new(cfg.lobbyTtl or 30),
    sessions = {},        -- tableId -> session (our Host engine if hosting it, our Client if seated)
    seats = {},           -- tableId -> seated player list (last SEAT seen, for the UI)
    tableHost = nil, client = nil, seatedAt = nil,
  }, Casino)
end

function Casino:_send(tag, payload, channel, target)
  self.tp:post(tag .. SEP .. payload, channel, target)
end
function Casino:_sendReliable(tag, payload, target)
  self.tp:sendReliable(tag .. SEP .. payload, target)
end

-- a tagged transport handed to a per-hand Host / a Client (their post/sendReliable
-- transparently carry the table tag; the session code is otherwise unchanged)
function Casino:_tagged(tag)
  local cas = self
  return {
    post = function(_, payload, channel, target) cas:_send(tag, payload, channel, target) end,
    sendReliable = function(_, payload, target) cas:_sendReliable(tag, payload, target) end,
  }
end

-- inbound reassembled payloads from the real Transport: "tag|appPayload"
function Casino:onWire(sender, wire, channel)
  local i = wire:find(SEP, 1, true)
  if not i then return end
  local tag, payload = wire:sub(1, i - 1), wire:sub(i + 1)
  if tag == LOBBY then return self:_control(sender, payload, channel) end
  local s = self.sessions[tag]
  if s then s:onMessage(sender, payload, channel) end       -- only participants hold a session
end

-- entering the floor (or refreshing the list): ask every host to re-advertise NOW,
-- instead of waiting up to adInterval for the next periodic ad. Cooldown-limited so
-- repeatedly opening the lobby window can't spam the channel.
function Casino:announce()
  local now = self._ticks or 0
  if self._lastAnnounce and (now - self._lastAnnounce) < 5 then return end
  self._lastAnnounce = now
  self:_send(LOBBY, Codec.encode(OP.PING, { kind = "lobby" }), self.broadcast, nil)
end

function Casino:_control(sender, payload, channel)
  local op, d = Codec.decode(payload)
  if d == nil then return end
  if op == OP.TABLE then
    self.lobby:onAd(d)
  elseif op == OP.PING then
    if self.tableHost then self.tableHost:advertise(true) end   -- rate-limited
  elseif op == OP.JOIN then
    if self.tableHost and d.table == self.me then
      if d.ver ~= self.ver then               -- exact-release gate (nil ver = pre-gate build)
        self:_send(LOBBY, Codec.encode(OP.REFUSE, { handNo = 0, actionNo = 0,
          reason = "This table runs Azeroth Hold'em v" .. self.ver .. " but you have "
            .. (d.ver and ("v" .. d.ver) or "an older version")
            .. " — please install the same (latest) release." }), "WHISPER", sender)
        return
      end
      self.tableHost:onJoin(sender)
    end
  elseif op == OP.REFUSE then
    -- our join was refused (version mismatch): release the pending seat + tell the user
    if not self.client then self.seatedAt = nil end
    if self.cfg.onNotice then self.cfg.onNotice(d.reason) end
  elseif op == OP.LEAVE then
    if self.tableHost and d.table == self.me then
      self.tableHost:onLeave((d.player ~= "" and d.player) or sender)
    end
  elseif op == OP.SEAT then
    self.seats[d.tableId] = d.players
    if self.seatedAt == d.tableId then
      local mine = false
      for k = 1, #d.players do if d.players[k] == self.me then mine = true; break end end
      if mine and not self.client then
        self:_spawnClient(d.tableId)
      elseif not mine and self.client then
        -- the table no longer seats us (closed / busted out): release back to the lobby
        self.sessions[d.tableId] = nil
        self.client, self.seatedAt = nil, nil
      end
    end
  end
end

-- ---- lifecycle -------------------------------------------------------------
function Casino:host(opts)
  if self.tableHost then return end
  self.tableHost = ns.TableHost.new({
    tableId = self.me, name = opts.name, sb = opts.sb, bb = opts.bb, variant = opts.variant,
    version = self.ver,                       -- advertised so joiners can self-gate
    seatMax = opts.seatMax, defaultStack = self.cfg.defaultStack, broadcast = self.broadcast,
    adInterval = self.cfg.adInterval, restTicks = opts.restTicks, turnTimeout = self.cfg.turnTimeout,
    postControl = function(p, ch) self:_send(LOBBY, p, ch, nil) end,
    sessionTransport = function() return self:_tagged(self.me) end,
    registerHost = function(tableId, host) self.sessions[tableId] = host end,
    entropy = self.cfg.entropy, nonces = self.cfg.nonces, onCheat = self.cfg.onCheat,
    policy = opts.policy or self.cfg.policy, human = self.cfg.human,
  })
  self.tableHost:advertise()
end

function Casino:join(tableId)
  if self.seatedAt == tableId then return end
  -- joiner-side version gate: an OLD host has no gate of its own, so we must also
  -- refuse from our side when the advertised version differs from ours
  local t = self.lobby:get(tableId)
  if t and t.ver ~= self.ver then
    if self.cfg.onNotice then
      self.cfg.onNotice("Can't join: that table runs "
        .. (t.ver and ("v" .. t.ver) or "an older version") .. " but you have v" .. self.ver
        .. " — everyone should install the same (latest) release.")
    end
    return false, "version mismatch"
  end
  if self.seatedAt then self:leave() end
  self.seatedAt = tableId
  self:_send(LOBBY, Codec.encode(OP.JOIN, { table = tableId, ver = self.ver }), self.broadcast, nil)
  return true
end

function Casino:_spawnClient(tableId)
  self.client = ns.Client.new({
    transport = self:_tagged(tableId), selfName = self.me, entropy = self.cfg.entropy,
    broadcast = self.broadcast, onCheat = self.cfg.onCheat, policy = self.cfg.policy, human = self.cfg.human,
  })
  self.sessions[tableId] = self.client
  -- if a hand is live and WE are in it (e.g. we relogged mid-hand and just re-sat),
  -- ask the host to bring us current: it answers with a SNAPSHOT + our hole cards.
  -- Harmless otherwise — the host ignores RESYNC from seats not in the hand.
  self.client:resume(tableId)
end

function Casino:leave()
  if not self.seatedAt then return end
  self:_send(LOBBY, Codec.encode(OP.LEAVE, { table = self.seatedAt, player = self.me }), self.broadcast, nil)
  self.sessions[self.seatedAt] = nil
  self.client, self.seatedAt = nil, nil
end

function Casino:changeTable(tableId) self:leave(); self:join(tableId) end

-- the host closes their table: no more ads/joins/hands. If a hand is live it
-- finishes first; the table then disbands (all seats released) on a later tick.
local function handLive(th)
  local h = th and th.host
  return h and h.phase ~= "done" and h.phase ~= "abort"
end

function Casino:closeTable()
  local th = self.tableHost
  if not th then return false, "not hosting a table" end
  th:close()
  if handLive(th) then self._closing = true
  else th:disband(); self.tableHost = nil end
  return true
end

function Casino:humanAct(action, amount)
  if self.tableHost then return self.tableHost:humanAct(action, amount) end
  if self.client then return self.client:humanAct(action, amount) end
  return false, "not at a table"
end

function Casino:tables() return self.lobby:list() end

function Casino:tick(dt)
  self._ticks = (self._ticks or 0) + (dt or 1)
  self.lobby:tick(dt)
  if self.tableHost then self.tableHost:tick(dt) end
  if self._closing and self.tableHost and not handLive(self.tableHost) then
    self.tableHost:disband(); self.tableHost = nil; self._closing = nil
  end
end

ns.Casino = Casino
return Casino
