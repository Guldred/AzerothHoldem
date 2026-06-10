--[[ Const.lua — protocol version, card encoding, opcode/action enums.

  Pure module (no WoW API). Card encoding is the canonical contract shared by
  Deck, HandEval, and Commit (see DESIGN.md "Card encoding").
]]

local ADDON, ns = ...
local Const = {}

-- Protocol version: bump on ANY wire-incompatible change. Mismatched versions
-- must refuse to play together (see net/Protocol, net/Session).
Const.PROTO_VER = 1
Const.ADDON_VER = "0.1.0-dev"

-- Addon-message prefix. 4 bytes, leaving 254 - 4 = 250 usable text bytes/message.
Const.PREFIX = "AzHE"

-- ---------------------------------------------------------------------------
-- Card encoding: id c in 0..51.  rank0 = floor(c/4) (0=Two..12=Ace), suit = c%4.
-- ---------------------------------------------------------------------------
Const.DECK_SIZE = 52

Const.RANK_NAMES = { [0]="2","3","4","5","6","7","8","9","T","J","Q","K","A" }
-- suit: 0=clubs, 1=diamonds, 2=hearts, 3=spades
Const.SUIT_NAMES = { [0]="c","d","h","s" }

-- rank0 in 0..12 (Two=0 .. Ace=12)
function Const.cardRank0(c)
  return math.floor(c / 4)
end

-- high-rank value in 2..14 (Ace high = 14); used by HandEval
function Const.cardRankValue(c)
  return math.floor(c / 4) + 2
end

-- suit in 0..3
function Const.cardSuit(c)
  return c % 4
end

-- "As", "Td", "2c" ...
function Const.cardName(c)
  return Const.RANK_NAMES[math.floor(c / 4)] .. Const.SUIT_NAMES[c % 4]
end

-- parse "As" -> card id (inverse of cardName); returns nil on bad input.
function Const.cardFromName(name)
  if type(name) ~= "string" or #name ~= 2 then return nil end
  local r, s = name:sub(1, 1):upper(), name:sub(2, 2):lower()
  local rank0
  for i = 0, 12 do if Const.RANK_NAMES[i] == r then rank0 = i break end end
  local suit
  for i = 0, 3 do if Const.SUIT_NAMES[i] == s then suit = i break end end
  if not rank0 or not suit then return nil end
  return rank0 * 4 + suit
end

-- ---------------------------------------------------------------------------
-- Hand ranking categories (higher = stronger). Used by HandEval.
-- ---------------------------------------------------------------------------
Const.HAND = {
  HIGH_CARD = 1,
  PAIR = 2,
  TWO_PAIR = 3,
  TRIPS = 4,
  STRAIGHT = 5,
  FLUSH = 6,
  FULL_HOUSE = 7,
  QUADS = 8,
  STRAIGHT_FLUSH = 9,
}
Const.HAND_NAMES = {
  "High Card", "Pair", "Two Pair", "Three of a Kind", "Straight",
  "Flush", "Full House", "Four of a Kind", "Straight Flush",
}

-- ---------------------------------------------------------------------------
-- Wire opcodes (string tags). Kept here so engine/net/ui share one source.
-- ---------------------------------------------------------------------------
Const.OP = {
  -- session
  HELLO = "HI", TABLE = "TBL", JOIN = "JN", SEAT = "ST", LEAVE = "LV", REFUSE = "RF",
  -- ledger
  BUYIN_REQ = "BQ", BUYIN_OK = "BK", SETTLE = "SE",
  -- hand setup
  HANDSTART = "HS",
  -- commit-reveal (Tier 1)
  COMMITSEED = "CS", SEEDCMT = "SC", SEEDCMTSET = "SCS", SEEDREVEAL = "SR",
  SEEDSET = "SS", DECKCMT = "DC", STATEHASH = "SH", DEAL = "DL", HOLE = "HL",
  REVEAL = "RV", ENDREVEAL = "ER",
  -- betting / showdown
  BET_TURN = "BT", INTENT = "IN", ACTED = "AC", BOARD = "BD", SHOWREQ = "SQ",
  SHOWDOWN = "SD", POT = "PT", HANDEND = "HE",
  -- control / transport
  ACK = "AK", RESEND = "RS", RESYNC = "RY", SNAPSHOT = "SN", PAUSE = "PA",
  RESUME = "RM", CHEAT = "CH", PING = "PI", PONG = "PO",
}

-- Betting actions.
Const.ACTION = {
  POST_SB = "psb", POST_BB = "pbb", POST_ANTE = "pan",
  CHECK = "chk", CALL = "cal", BET = "bet", RAISE = "rai",
  FOLD = "fld", MUCK = "mck", ALLIN = "ain",
}

-- Streets.
Const.STREET = { PREFLOP = 0, FLOP = 1, TURN = 2, RIVER = 3 }

ns.Const = Const
return Const
