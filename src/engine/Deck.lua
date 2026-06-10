--[[ Deck.lua — 52-card deck, deterministic Fisher-Yates shuffle, canonical deal-map.

  Pure module. The shuffle is fully determined by the 32-byte seed S (so every
  party reproduces it at ENDREVEAL). The deal-map is a fixed function of the seat
  count, so the host cannot route favorable committed positions to itself — clients
  verify the actual deal matched it (see DESIGN.md "Canonical deal-map").

  Card ids are 0..51 (see Const "Card encoding"). Deck arrays are 1-based; the
  committed position of d[k] is `k-1` (0-based).
]]

local ADDON, ns = ...
local Rng = ns.Rng
local DECK_SIZE = ns.Const.DECK_SIZE

local Deck = {}

-- fresh ordered deck: d[i] = i-1, card ids 0..51
function Deck.fresh()
  local d = {}
  for i = 1, DECK_SIZE do d[i] = i - 1 end
  return d
end

-- deterministic Fisher-Yates from seed S; returns d[1..52], a permutation of 0..51
function Deck.shuffle(S)
  local d = Deck.fresh()
  local g = Rng.fromSeed(S)
  for i = DECK_SIZE, 2, -1 do
    local j = g.uniform(i) + 1        -- uniform in [1, i]
    d[i], d[j] = d[j], d[i]
  end
  return d
end

-- 0-based committed position of deck index k
function Deck.posOf(k)
  return k - 1
end

-- Canonical Texas Hold'em deal-map for n seats in dealing order seat[1..n]
-- (seat[1] = first to receive = small blind / left of button). Returns deck
-- INDICES (1-based) so callers can fetch card ids via the shuffled deck and
-- 0-based positions via posOf().
function Deck.dealPlan(n)
  if type(n) ~= "number" or n < 2 or n % 1 ~= 0 then
    error("Deck.dealPlan: n must be an integer >= 2")
  end
  local used = 2 * n + 8
  if used > DECK_SIZE then
    error("Deck.dealPlan: too many seats (" .. n .. ") for a 52-card deck")
  end

  local plan = { holes = {}, burns = {}, flop = {}, turn = nil, river = nil }
  for s = 1, n do
    plan.holes[s] = { s, n + s }     -- round 1: d[1..n]; round 2: d[n+1..2n]
  end
  local idx = 2 * n
  plan.burns[1] = idx + 1
  plan.flop = { idx + 2, idx + 3, idx + 4 }
  plan.burns[2] = idx + 5
  plan.turn = idx + 6
  plan.burns[3] = idx + 7
  plan.river = idx + 8
  return plan
end

-- convenience accessors (return card ids from a shuffled deck d)
function Deck.holeCards(d, plan, s)
  local h = plan.holes[s]
  return d[h[1]], d[h[2]]
end
function Deck.flopCards(d, plan)
  return d[plan.flop[1]], d[plan.flop[2]], d[plan.flop[3]]
end
function Deck.turnCard(d, plan) return d[plan.turn] end
function Deck.riverCard(d, plan) return d[plan.river] end

ns.Deck = Deck
return Deck
