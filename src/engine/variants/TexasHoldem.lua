--[[ TexasHoldem.lua — the Texas Hold'em variant (first implementation).

  2 hole cards; flop(3)/turn(1)/river(1) community cards; best 5 of the 7 available
  cards. Pure (no WoW API). Registers itself with ns.Variant under "texas".
]]

local ADDON, ns = ...
local Variant = ns.Variant
local HandEval = ns.HandEval
local STREET = ns.Const.STREET

local Texas = {
  name = "texas",
  deckSize = 52,
  holeCount = 2,
  minPlayers = 2,
  maxPlayers = 10,                 -- 2*10 + 8 = 28 cards <= 52
  -- cumulative community cards visible by the START of each street's betting
  boardSchedule = {
    [STREET.PREFLOP] = 0,
    [STREET.FLOP] = 3,
    [STREET.TURN] = 4,
    [STREET.RIVER] = 5,
  },
  streets = { STREET.PREFLOP, STREET.FLOP, STREET.TURN, STREET.RIVER },
}

-- best 5-card hand from 2 hole + up to 5 board cards (any combination).
function Texas:bestHand(hole, board)
  local all = {}
  for i = 1, #hole do all[#all + 1] = hole[i] end
  for i = 1, #board do all[#all + 1] = board[i] end
  return HandEval.evaluate(all)
end

Variant.register(Texas)

ns.TexasHoldem = Texas
return Texas
