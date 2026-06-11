--[[ Codec.lua — per-opcode wire encode/decode, defined ONCE (pure, testable).

  Host encodes and clients decode the same opcodes; defining each in one place
  removes a whole class of host/client drift bugs. Built on Protocol's primitives
  (escaped leaves, ';'-lists, ':'-pairs). Commitments/nonces/seeds travel as hex.

  A card "opening" (val,nonce) is packed as hex(char(val) .. nonce) -> 34 hex chars
  (1 value byte + 16 nonce bytes). A seed opening (r,salt) is hex(r .. salt).

  Codec.encode(op, data) -> payload string
  Codec.decode(payload)  -> op, data   (data fields already parsed to numbers/bytes)
]]

local ADDON, ns = ...
local Protocol, Util, Const = ns.Protocol, ns.Util, ns.Const
local OP = Const.OP
local hx, unhx = Util.toHex, Util.fromHex
local leaf, list, pairs_ = Protocol.leaf, Protocol.list, Protocol.pairs
local char, byte, sub = string.char, string.byte, string.sub
local tn = tonumber

local Codec = {}

-- pack/unpack a card opening (val 0..51, nonce 16B)
local function packOpen(val, nonce) return hx(char(val) .. nonce) end
local function unpackOpen(h) local raw = unhx(h); return byte(raw, 1), sub(raw, 2) end

-- a list of {pos,val,nonce} reveals -> a pairs token { {pos, openHex}, ... }
local function revealPairs(reveals)
  local p = {}
  for i = 1, #reveals do p[i] = { reveals[i].pos, packOpen(reveals[i].val, reveals[i].nonce) } end
  return { pairs = p }
end
local function parseReveals(field)
  local raw, out = pairs_(field), {}
  for i = 1, #raw do
    local val, nonce = unpackOpen(raw[i][2])
    out[i] = { pos = tn(raw[i][1]), val = val, nonce = nonce }
  end
  return out
end

-- ---- encoders (op -> payload) ---------------------------------------------
local ENC = {}
ENC[OP.HANDSTART] = function(d)
  -- stacks: chip counts parallel to the seat list (clients display them; absent
  -- from older hosts — decoders tolerate)
  local stacks = {}
  if d.stacks then for i = 1, #d.seats do stacks[i] = d.stacks[d.seats[i]] or 0 end end
  return Protocol.encode(OP.HANDSTART,
    { d.handNo, d.button, d.sb, d.bb, d.ante or 0, { list = d.seats }, { list = stacks } })
end
ENC[OP.COMMITSEED] = function(d) return Protocol.encode(OP.COMMITSEED, { d.handNo }) end
ENC[OP.SEEDCMT] = function(d) return Protocol.encode(OP.SEEDCMT, { d.handNo, d.seat, hx(d.commit) }) end
ENC[OP.SEEDREVEAL] = function(d)
  return Protocol.encode(OP.SEEDREVEAL, { d.handNo, d.seat, hx(d.r), hx(d.salt) })
end
ENC[OP.DECKCMT] = function(d)
  local hexes = {}
  for i = 1, #d.commits do hexes[i] = hx(d.commits[i]) end
  return Protocol.encode(OP.DECKCMT, { d.handNo, { list = hexes } })
end
ENC[OP.STATEHASH] = function(d) return Protocol.encode(OP.STATEHASH, { d.handNo, d.seat, hx(d.H) }) end
ENC[OP.HOLE] = function(d)
  return Protocol.encode(OP.HOLE, { d.handNo, d.seat, revealPairs(d.reveals) })
end
ENC[OP.REVEAL] = function(d)
  return Protocol.encode(OP.REVEAL, { d.handNo, d.street, revealPairs(d.reveals) })
end
ENC[OP.BET_TURN] = function(d)
  -- minTo/maxTo: the actor's full bet-or-raise-TO range (so a client can submit a
  -- valid raise-to amount); canCheck saves the client guessing from toCall; pot is
  -- the current total so every client can display it.
  return Protocol.encode(OP.BET_TURN, { d.handNo, d.actionNo, d.seat, d.toCall, d.minRaise,
    d.minTo or 0, d.maxTo or 0, d.canCheck and 1 or 0, d.pot or 0 })
end
ENC[OP.REFUSE] = function(d)
  return Protocol.encode(OP.REFUSE, { d.handNo, d.actionNo or 0, d.reason or "" })
end
ENC[OP.PING] = function(d) return Protocol.encode(OP.PING, { d.kind or "lobby" }) end
ENC[OP.INTENT] = function(d)
  return Protocol.encode(OP.INTENT, { d.handNo, d.actionNo, d.seat, d.action, d.amount or 0 })
end
ENC[OP.ACTED] = function(d)
  return Protocol.encode(OP.ACTED, { d.handNo, d.actionNo, d.seat, d.action, d.amount or 0, d.allin and 1 or 0 })
end
ENC[OP.BOARD] = function(d)
  return Protocol.encode(OP.BOARD, { d.handNo, d.street, { list = d.cards } })
end
ENC[OP.HANDEND] = function(d)
  local p = {}
  for seat, amt in pairs(d.deltas) do p[#p + 1] = { seat, amt } end
  return Protocol.encode(OP.HANDEND, { d.handNo, { pairs = p } })
end
ENC[OP.ENDREVEAL] = function(d)
  local seedP = {}
  for seat, sr in pairs(d.seedReveals) do seedP[#seedP + 1] = { seat, hx(sr.r .. sr.salt) } end
  local openL = {}
  for i = 1, #d.openings do openL[i] = packOpen(d.openings[i].val, d.openings[i].nonce) end
  return Protocol.encode(OP.ENDREVEAL, { d.handNo, hx(d.S), { pairs = seedP }, { list = openL } })
end
ENC[OP.CHEAT] = function(d)
  return Protocol.encode(OP.CHEAT, { d.handNo, d.code, d.detail or "" })
end
-- showdown: a seat's hole cards opened (commitment-verifiable) + its hand name
ENC[OP.SHOWDOWN] = function(d)
  return Protocol.encode(OP.SHOWDOWN, { d.handNo, d.seat, revealPairs(d.reveals), d.handName or "" })
end
-- ---- lobby / seating (multi-table casino; ride at routing tag "0") ----------
ENC[OP.TABLE] = function(d)
  return Protocol.encode(OP.TABLE, { d.tableId, d.name or "", d.sb, d.bb, d.variant or "texas",
    d.taken or 0, d.seatMax or 9, d.open and 1 or 0, { list = d.players or {} }, d.ver or "" })
end
ENC[OP.JOIN] = function(d) return Protocol.encode(OP.JOIN, { d.table, d.seat or "", d.ver or "" }) end
ENC[OP.SEAT] = function(d) return Protocol.encode(OP.SEAT, { d.tableId, { list = d.players } }) end
ENC[OP.LEAVE] = function(d) return Protocol.encode(OP.LEAVE, { d.table, d.player or "" }) end
ENC[OP.RESYNC] = function(d) return Protocol.encode(OP.RESYNC, { d.handNo or 0, d.seat }) end
-- SNAPSHOT: column-oriented per-seat arrays (parallel to the seat list) so it fits
-- Protocol's list primitive. Carries enough to resume play + (degraded) audit.
ENC[OP.SNAPSHOT] = function(d)
  local stacks, committed, totals, status, commitsHex = {}, {}, {}, {}, {}
  for i = 1, #d.seats do
    local s = d.seatInfo[d.seats[i]]
    stacks[i], committed[i], totals[i] = s.stack, s.committed, s.total
    status[i] = s.folded and "f" or (s.allIn and "i" or "o")
    commitsHex[i] = hx(d.commits[d.seats[i]])
  end
  return Protocol.encode(OP.SNAPSHOT, {
    d.handNo, d.button, d.sb, d.bb, d.street, d.currentBet, d.minRaise, d.toAct or "",
    hx(d.S), { list = d.seats }, { list = stacks }, { list = committed }, { list = totals },
    { list = status }, { list = d.board or {} }, { list = commitsHex },
  })
end

-- ---- decoders (payload -> data) -------------------------------------------
local DEC = {}
DEC[OP.HANDSTART] = function(f)
  local d = { handNo = tn(leaf(f[1])), button = leaf(f[2]), sb = tn(leaf(f[3])),
              bb = tn(leaf(f[4])), ante = tn(leaf(f[5])), seats = list(f[6]) }
  if f[7] then                                   -- appended stacks (older hosts omit)
    local raw = list(f[7]); d.stacks = {}
    for i = 1, #raw do d.stacks[d.seats[i]] = tn(raw[i]) end
  end
  return d
end
DEC[OP.COMMITSEED] = function(f) return { handNo = tn(leaf(f[1])) } end
DEC[OP.SEEDCMT] = function(f)
  return { handNo = tn(leaf(f[1])), seat = leaf(f[2]), commit = unhx(leaf(f[3])) }
end
DEC[OP.SEEDREVEAL] = function(f)
  return { handNo = tn(leaf(f[1])), seat = leaf(f[2]), r = unhx(leaf(f[3])), salt = unhx(leaf(f[4])) }
end
DEC[OP.DECKCMT] = function(f)
  local hexes, commits = list(f[2]), {}
  for i = 1, #hexes do commits[i] = unhx(hexes[i]) end
  return { handNo = tn(leaf(f[1])), commits = commits }
end
DEC[OP.STATEHASH] = function(f)
  return { handNo = tn(leaf(f[1])), seat = leaf(f[2]), H = unhx(leaf(f[3])) }
end
DEC[OP.HOLE] = function(f)
  return { handNo = tn(leaf(f[1])), seat = leaf(f[2]), reveals = parseReveals(f[3]) }
end
DEC[OP.REVEAL] = function(f)
  return { handNo = tn(leaf(f[1])), street = tn(leaf(f[2])), reveals = parseReveals(f[3]) }
end
DEC[OP.BET_TURN] = function(f)
  local d = { handNo = tn(leaf(f[1])), actionNo = tn(leaf(f[2])), seat = leaf(f[3]),
              toCall = tn(leaf(f[4])), minRaise = tn(leaf(f[5])) }
  -- appended fields (absent from older senders): tolerate their absence
  if f[6] then local v = tn(leaf(f[6])); if v and v > 0 then d.minTo = v end end
  if f[7] then local v = tn(leaf(f[7])); if v and v > 0 then d.maxTo = v end end
  if f[8] then d.canCheck = leaf(f[8]) == "1" end
  if f[9] then d.pot = tn(leaf(f[9])) end
  return d
end
DEC[OP.REFUSE] = function(f)
  return { handNo = tn(leaf(f[1])), actionNo = tn(leaf(f[2])), reason = leaf(f[3]) }
end
DEC[OP.PING] = function(f) return { kind = leaf(f[1]) } end
DEC[OP.INTENT] = function(f)
  return { handNo = tn(leaf(f[1])), actionNo = tn(leaf(f[2])), seat = leaf(f[3]),
           action = leaf(f[4]), amount = tn(leaf(f[5])) }
end
DEC[OP.ACTED] = function(f)
  return { handNo = tn(leaf(f[1])), actionNo = tn(leaf(f[2])), seat = leaf(f[3]),
           action = leaf(f[4]), amount = tn(leaf(f[5])), allin = leaf(f[6]) == "1" }
end
DEC[OP.BOARD] = function(f)
  local raw, cards = list(f[3]), {}     -- fields: handNo, street, cards(int list)
  for i = 1, #raw do cards[i] = tn(raw[i]) end
  return { handNo = tn(leaf(f[1])), street = tn(leaf(f[2])), cards = cards }
end
DEC[OP.HANDEND] = function(f)
  local raw, deltas = pairs_(f[2]), {}
  for i = 1, #raw do deltas[raw[i][1]] = tn(raw[i][2]) end
  return { handNo = tn(leaf(f[1])), deltas = deltas }
end
DEC[OP.ENDREVEAL] = function(f)
  local seedRaw, seedReveals = pairs_(f[3]), {}
  for i = 1, #seedRaw do
    local both = unhx(seedRaw[i][2])
    seedReveals[seedRaw[i][1]] = { r = sub(both, 1, 16), salt = sub(both, 17, 32) }
  end
  local openL, openings = list(f[4]), {}
  for i = 1, #openL do
    local val, nonce = unpackOpen(openL[i])
    openings[i] = { val = val, nonce = nonce }
  end
  return { handNo = tn(leaf(f[1])), S = unhx(leaf(f[2])), seedReveals = seedReveals, openings = openings }
end
DEC[OP.CHEAT] = function(f)
  return { handNo = tn(leaf(f[1])), code = leaf(f[2]), detail = leaf(f[3]) }
end
DEC[OP.SHOWDOWN] = function(f)
  return { handNo = tn(leaf(f[1])), seat = leaf(f[2]), reveals = parseReveals(f[3]), handName = leaf(f[4]) }
end
DEC[OP.TABLE] = function(f)
  local d = { tableId = leaf(f[1]), name = leaf(f[2]), sb = tn(leaf(f[3])), bb = tn(leaf(f[4])),
    variant = leaf(f[5]), taken = tn(leaf(f[6])), seatMax = tn(leaf(f[7])), open = leaf(f[8]) == "1" }
  if f[9] then d.players = list(f[9]) end        -- appended seated-player names (older hosts omit)
  if f[10] then local v = leaf(f[10]); if v ~= "" then d.ver = v end end   -- host's addon version
  return d
end
DEC[OP.JOIN] = function(f)
  local s = leaf(f[2])
  local v = f[3] and leaf(f[3]) or ""
  return { table = leaf(f[1]), seat = s ~= "" and s or nil, ver = v ~= "" and v or nil }
end
DEC[OP.SEAT] = function(f) return { tableId = leaf(f[1]), players = list(f[2]) } end
DEC[OP.LEAVE] = function(f) return { table = leaf(f[1]), player = leaf(f[2]) } end
DEC[OP.RESYNC] = function(f) return { handNo = tn(leaf(f[1])), seat = leaf(f[2]) } end
DEC[OP.SNAPSHOT] = function(f)
  local seats, stacks, committed = list(f[10]), list(f[11]), list(f[12])
  local totals, status, board, commitsHex = list(f[13]), list(f[14]), list(f[15]), list(f[16])
  local seatInfo, commits = {}, {}
  for i = 1, #seats do
    seatInfo[seats[i]] = {
      stack = tn(stacks[i]), committed = tn(committed[i]), total = tn(totals[i]),
      folded = status[i] == "f", allIn = status[i] == "i",
    }
    commits[seats[i]] = unhx(commitsHex[i])
  end
  local boardVals = {}
  for i = 1, #board do boardVals[i] = tn(board[i]) end
  local toAct = leaf(f[8]); if toAct == "" then toAct = nil end
  return {
    handNo = tn(leaf(f[1])), button = leaf(f[2]), sb = tn(leaf(f[3])), bb = tn(leaf(f[4])),
    street = tn(leaf(f[5])), currentBet = tn(leaf(f[6])), minRaise = tn(leaf(f[7])), toAct = toAct,
    S = unhx(leaf(f[9])), seats = seats, seatInfo = seatInfo, board = boardVals, commits = commits,
  }
end

-- ---- public API -----------------------------------------------------------
function Codec.encode(op, data)
  local enc = ENC[op]
  if not enc then error("Codec.encode: no encoder for op " .. tostring(op)) end
  return enc(data)
end

function Codec.decode(payload)
  local op, fields = Protocol.decode(payload)
  local dec = DEC[op]
  if not dec then return op, nil end       -- unknown/unsupported op: caller decides
  return op, dec(fields)
end

ns.Codec = Codec
return Codec
