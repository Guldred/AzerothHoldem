--[[ HandEval.lua — pure 5-from-7 Texas Hold'em hand evaluator.

  Pure module (no WoW API). Given 5, 6, or 7 distinct card ids, returns the BEST
  5-card hand as a comparable score table { category, t1..t5 }, where category is
  a ns.Const.HAND value and t1..t5 are tiebreak rank VALUES (2..14) most-
  significant first, unused slots padded with 0 (so split-pot ties compare equal).

  Strategy: brute-force every C(n,5) subset, classify each into a score, keep the
  max. Best-5-of-7, playing the board, >5 suited cards, and 3+ pairs all fall out
  of taking the global best — only the 5-card classifier and compare carry logic.
]]

local ADDON, ns = ...
local Const = ns.Const
local HAND = Const.HAND
local cardRankValue, cardSuit = Const.cardRankValue, Const.cardSuit

local HandEval = {}

-- ---------------------------------------------------------------------------
-- compare(a, b): category first, then t1..t5 lexicographically. -1 / 0 / 1.
-- ---------------------------------------------------------------------------
function HandEval.compare(a, b)
  if a.category ~= b.category then
    return a.category < b.category and -1 or 1
  end
  if a.t1 ~= b.t1 then return a.t1 < b.t1 and -1 or 1 end
  if a.t2 ~= b.t2 then return a.t2 < b.t2 and -1 or 1 end
  if a.t3 ~= b.t3 then return a.t3 < b.t3 and -1 or 1 end
  if a.t4 ~= b.t4 then return a.t4 < b.t4 and -1 or 1 end
  if a.t5 ~= b.t5 then return a.t5 < b.t5 and -1 or 1 end
  return 0
end

-- always emit numeric t1..t5 (never nil) so compare never hits nil < number.
local function score(cat, t1, t2, t3, t4, t5)
  return { category = cat, t1 = t1 or 0, t2 = t2 or 0,
           t3 = t3 or 0, t4 = t4 or 0, t5 = t5 or 0 }
end

-- ---------------------------------------------------------------------------
-- classify5: rank EXACTLY 5 card ids into a score table.
-- ---------------------------------------------------------------------------
local function classify5(a, b, c, d, e)
  -- rank values 2..14 and the per-rank count
  local count = {}            -- count[v] = how many of rank v (v in 2..14)
  for v = 2, 14 do count[v] = 0 end
  local sa, sb = cardSuit(a), cardSuit(b)
  local sc, sd, se = cardSuit(c), cardSuit(d), cardSuit(e)
  count[cardRankValue(a)] = count[cardRankValue(a)] + 1
  count[cardRankValue(b)] = count[cardRankValue(b)] + 1
  count[cardRankValue(c)] = count[cardRankValue(c)] + 1
  count[cardRankValue(d)] = count[cardRankValue(d)] + 1
  count[cardRankValue(e)] = count[cardRankValue(e)] + 1

  local isFlush = (sa == sb and sb == sc and sc == sd and sd == se)

  -- straight detection over presence[1..14]; Ace(14) also doubles as low 1.
  local present = {}
  for i = 1, 14 do present[i] = false end
  for v = 2, 14 do if count[v] > 0 then present[v] = true end end
  if present[14] then present[1] = true end    -- wheel: A plays low
  local straightHigh = 0
  for high = 14, 5, -1 do
    if present[high] and present[high-1] and present[high-2]
       and present[high-3] and present[high-4] then
      straightHigh = high
      break
    end
  end

  -- group ranks by multiplicity, each list sorted high->low (ranks are distinct
  -- within a multiplicity, and we iterate 14->2 so order is naturally desc).
  local quad, trips, pairList, singles = nil, nil, {}, {}
  for v = 14, 2, -1 do
    local n = count[v]
    if n == 4 then quad = v
    elseif n == 3 then trips = v
    elseif n == 2 then pairList[#pairList + 1] = v
    elseif n == 1 then singles[#singles + 1] = v
    end
  end

  if isFlush and straightHigh > 0 then
    return score(HAND.STRAIGHT_FLUSH, straightHigh)
  end
  if quad then
    return score(HAND.QUADS, quad, singles[1])
  end
  if trips and #pairList >= 1 then
    return score(HAND.FULL_HOUSE, trips, pairList[1])
  end
  if isFlush then
    return score(HAND.FLUSH, singles[1], singles[2], singles[3], singles[4], singles[5])
  end
  if straightHigh > 0 then
    return score(HAND.STRAIGHT, straightHigh)
  end
  if trips then
    return score(HAND.TRIPS, trips, singles[1], singles[2])
  end
  if #pairList >= 2 then
    return score(HAND.TWO_PAIR, pairList[1], pairList[2], singles[1])
  end
  if #pairList == 1 then
    return score(HAND.PAIR, pairList[1], singles[1], singles[2], singles[3])
  end
  return score(HAND.HIGH_CARD, singles[1], singles[2], singles[3], singles[4], singles[5])
end

-- ---------------------------------------------------------------------------
-- evaluate(cards): best 5-card score over every C(n,5) subset of 5..7 cards.
-- ---------------------------------------------------------------------------
function HandEval.evaluate(cards)
  local n = #cards
  if n < 5 or n > 7 then
    error("HandEval.evaluate: need 5, 6, or 7 cards (got " .. tostring(n) .. ")")
  end
  local best = nil
  -- enumerate the 5-card subsets by choosing 5 of the n indices
  for i1 = 1, n - 4 do
    for i2 = i1 + 1, n - 3 do
      for i3 = i2 + 1, n - 2 do
        for i4 = i3 + 1, n - 1 do
          for i5 = i4 + 1, n do
            local s = classify5(cards[i1], cards[i2], cards[i3], cards[i4], cards[i5])
            if not best or HandEval.compare(s, best) > 0 then
              best = s
            end
          end
        end
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- describe(score): human-readable string (optional convenience).
-- ---------------------------------------------------------------------------
local RANK_WORD = {
  [2]="Twos", [3]="Threes", [4]="Fours", [5]="Fives", [6]="Sixes", [7]="Sevens",
  [8]="Eights", [9]="Nines", [10]="Tens", [11]="Jacks", [12]="Queens",
  [13]="Kings", [14]="Aces",
}
local RANK_ONE = {
  [2]="Two", [3]="Three", [4]="Four", [5]="Five", [6]="Six", [7]="Seven",
  [8]="Eight", [9]="Nine", [10]="Ten", [11]="Jack", [12]="Queen",
  [13]="King", [14]="Ace",
}

function HandEval.describe(score)
  local cat = score.category
  if cat == HAND.STRAIGHT_FLUSH then
    return "Straight Flush, " .. RANK_ONE[score.t1] .. " high"
  elseif cat == HAND.QUADS then
    return "Four of a Kind, " .. RANK_WORD[score.t1]
  elseif cat == HAND.FULL_HOUSE then
    return "Full House, " .. RANK_WORD[score.t1] .. " full of " .. RANK_WORD[score.t2]
  elseif cat == HAND.FLUSH then
    return "Flush, " .. RANK_ONE[score.t1] .. " high"
  elseif cat == HAND.STRAIGHT then
    return "Straight, " .. RANK_ONE[score.t1] .. " high"
  elseif cat == HAND.TRIPS then
    return "Three of a Kind, " .. RANK_WORD[score.t1]
  elseif cat == HAND.TWO_PAIR then
    return "Two Pair, " .. RANK_WORD[score.t1] .. " and " .. RANK_WORD[score.t2]
  elseif cat == HAND.PAIR then
    return "Pair of " .. RANK_WORD[score.t1]
  end
  return "High Card, " .. RANK_ONE[score.t1]
end

ns.HandEval = HandEval
return HandEval
