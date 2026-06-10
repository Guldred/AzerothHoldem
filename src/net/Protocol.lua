--[[ Protocol.lua — pure message codec + transport framing (no WoW API).

  Two layers (see DESIGN.md "Message protocol"):
    * Application message: op|field|field|...   (fields may be leaves, ';'-lists,
      or ':'-keyed ';'-pair lists). Leaves are backslash-escaped so the reserved
      separators | ; : never appear literally inside a value — framing stays
      unambiguous.
    * Transport frame: protoVer|msgid|seq|total|payload   (payload is an app
      message and itself contains '|', so parseFrame keeps everything after the
      4th '|' as the payload).

  buildMessages() chunks a payload so every emitted wire string fits the 3.3.5a
  limit (#prefix + #text <= 254). The Reassembler reorders chunks, detects
  duplicates, and reports missing seqs for RESEND. All pure / unit-testable; the
  WoW-coupled Transport layer wires this to SendAddonMessage + ChatThrottleLib.
]]

local ADDON, ns = ...
local Util = ns.Util
local escape, unescape, split = Util.escape, Util.unescape, Util.split
local concat = table.concat

local Protocol = {}

-- ---------------------------------------------------------------------------
-- Application message encode/decode
-- ---------------------------------------------------------------------------
-- encode(op, tokens): tokens is an array; each element is one of:
--   leaf  : a string or number                     -> escaped scalar
--   list  : { list = { v1, v2, ... } }             -> "v1;v2;..."
--   pairs : { pairs = { {k1,v1}, {k2,v2}, ... } }  -> "k1:v1;k2:v2;..."
local function encodeToken(tok)
  if type(tok) == "table" then
    if tok.list then
      local out = {}
      for i = 1, #tok.list do out[i] = escape(tostring(tok.list[i])) end
      return concat(out, ";")
    elseif tok.pairs then
      local out = {}
      for i = 1, #tok.pairs do
        local kv = tok.pairs[i]
        out[i] = escape(tostring(kv[1])) .. ":" .. escape(tostring(kv[2]))
      end
      return concat(out, ";")
    else
      error("Protocol.encode: token table must have .list or .pairs")
    end
  end
  return escape(tostring(tok))
end

function Protocol.encode(op, tokens)
  local parts = { escape(tostring(op)) }
  if tokens then
    for i = 1, #tokens do parts[#parts + 1] = encodeToken(tokens[i]) end
  end
  return concat(parts, "|")
end

-- decode(payload) -> op, fields  (fields are RAW field strings; interpret each
-- with leaf()/list()/pairs() since a field may itself be a list or pair-list).
function Protocol.decode(payload)
  local fields = split(payload, "|")
  local op = unescape(fields[1] or "")
  local rest = {}
  for i = 2, #fields do rest[i - 1] = fields[i] end
  return op, rest
end

function Protocol.leaf(field)
  return unescape(field or "")
end

function Protocol.list(field)
  if field == nil or field == "" then return {} end
  local raw = split(field, ";")
  local out = {}
  for i = 1, #raw do out[i] = unescape(raw[i]) end
  return out
end

function Protocol.pairs(field)
  if field == nil or field == "" then return {} end
  local raw = split(field, ";")
  local out = {}
  for i = 1, #raw do
    local item = raw[i]
    local c = item:find(":", 1, true)         -- first literal ':' (leaves escape theirs)
    if c then
      out[i] = { unescape(item:sub(1, c - 1)), unescape(item:sub(c + 1)) }
    else
      out[i] = { unescape(item), "" }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Transport frame
-- ---------------------------------------------------------------------------
function Protocol.frame(protoVer, msgid, seq, total, payload)
  return concat({ protoVer, msgid, seq, total, payload }, "|")
end

-- split into 5 parts; the 5th (payload) keeps any embedded '|'.
function Protocol.parseFrame(s)
  local p = {}
  local start = 1
  for _ = 1, 4 do
    local i = s:find("|", start, true)
    if not i then return nil, "malformed frame" end
    p[#p + 1] = s:sub(start, i - 1)
    start = i + 1
  end
  return {
    protoVer = tonumber(p[1]),
    msgid = p[2],
    seq = tonumber(p[3]),
    total = tonumber(p[4]),
    payload = s:sub(start),
  }
end

-- ---------------------------------------------------------------------------
-- Chunking: split `payload` so every emitted wire frame has length <= maxText
-- (caller passes maxText = 254 - #prefix). Returns an array of wire strings.
-- ---------------------------------------------------------------------------
function Protocol.buildMessages(protoVer, msgid, payload, maxText)
  local verS = tostring(protoVer)
  local plen = #payload
  local total = 1
  while true do
    local w = #tostring(total)                       -- max width of seq/total digits
    -- header = verS | msgid | seq | total |  (seq width bounded by total width)
    local headerLen = #verS + 1 + #msgid + 1 + w + 1 + w + 1
    local cap = maxText - headerLen
    if cap < 1 then error("Protocol.buildMessages: maxText too small for header") end
    if total * cap >= plen then
      local out = {}
      if plen == 0 then
        out[1] = Protocol.frame(protoVer, msgid, 1, total, "")
      else
        for seq = 1, total do
          local chunk = payload:sub((seq - 1) * cap + 1, seq * cap)
          out[seq] = Protocol.frame(protoVer, msgid, seq, total, chunk)
        end
      end
      return out
    end
    total = total + 1
  end
end

-- max usable text bytes for a given addon-message prefix (3.3.5a: prefix+text<=254)
function Protocol.maxText(prefix)
  return 254 - #prefix
end

-- ---------------------------------------------------------------------------
-- Reassembler — pure, stateful buffer keyed by (sender, msgid).
-- ---------------------------------------------------------------------------
local Reassembler = {}
Reassembler.__index = Reassembler

function Protocol.newReassembler()
  return setmetatable({ buf = {}, pending = 0 }, Reassembler)
end

-- accept a parsed frame's chunk. Returns:
--   "complete", payload      when all `total` chunks have arrived
--   "partial",  missingSeqs  (array) otherwise
--   "duplicate", nil         if this seq was already stored
function Reassembler:accept(sender, msgid, seq, total, chunk)
  local bySender = self.buf[sender]
  if not bySender then bySender = {}; self.buf[sender] = bySender end
  local e = bySender[msgid]
  if e and e.total ~= total then
    -- total changed (stale/reused msgid): start fresh
    if not e.done then self.pending = self.pending - 1 end
    e = nil
  end
  if not e then
    e = { total = total, parts = {}, count = 0, done = false }
    bySender[msgid] = e
    self.pending = self.pending + 1
  end

  if e.parts[seq] ~= nil then
    return "duplicate", nil
  end
  e.parts[seq] = chunk
  e.count = e.count + 1

  if e.count >= e.total then
    local pieces = {}
    for i = 1, e.total do pieces[i] = e.parts[i] end
    bySender[msgid] = nil
    e.done = true
    self.pending = self.pending - 1
    return "complete", concat(pieces)
  end

  -- report missing seqs (for a RESEND request)
  local missing = {}
  for i = 1, total do if e.parts[i] == nil then missing[#missing + 1] = i end end
  return "partial", missing
end

-- seqs still missing for an in-flight message, or nil if unknown/complete
function Reassembler:missing(sender, msgid)
  local bySender = self.buf[sender]
  local e = bySender and bySender[msgid]
  if not e then return nil end
  local missing = {}
  for i = 1, e.total do if e.parts[i] == nil then missing[#missing + 1] = i end end
  return missing
end

-- drop an in-flight reassembly (TTL/eviction is the caller's policy)
function Reassembler:drop(sender, msgid)
  local bySender = self.buf[sender]
  if bySender and bySender[msgid] then
    bySender[msgid] = nil
    self.pending = self.pending - 1
  end
end

ns.Protocol = Protocol
return Protocol
