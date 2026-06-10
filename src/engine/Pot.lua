--[[ Pot.lua — pure pot / side-pot math (no WoW API, no HandEval dependency).

  Side pots are built by the standard "layer by ascending all-in depth" method:
  each distinct positive contribution level peels off one layer; a short all-in
  can only win the layers up to its own contribution. Folded players' chips are
  DEAD MONEY — counted in the pot amounts but never eligible to win.

  award() is decoupled from hand strength via a caller-supplied comparator, so
  this file stays a pure arithmetic core (see DESIGN.md "Pot & side-pot math").
]]

local ADDON, ns = ...

local Pot = {}

local floor = math.floor
local sort = table.sort

-- ---------------------------------------------------------------------------
-- sidePots(contribs) -> { pots = {...}, uncalled = nil | {player, amount} }
--   contribs: array of { player=<id>, amount=<int>=0>, folded=<bool> }.
--   amount = TOTAL chips that player put in this hand (folded chips included).
-- ---------------------------------------------------------------------------
function Pot.sidePots(contribs)
  -- Working copy of effective amounts (we may cap a unique over-bet below).
  local n = #contribs
  local amt, folded, player = {}, {}, {}
  for i = 1, n do
    local c = contribs[i]
    amt[i] = c.amount or 0
    folded[i] = c.folded and true or false
    player[i] = c.player
  end

  -- Uncalled bet: if exactly ONE player holds the unique maximum amount and it
  -- strictly exceeds the 2nd-highest amount (over ALL players, folded included),
  -- the excess is returned, not contested. Capping that player to secondHighest
  -- before layering is equivalent to "don't form the lone top layer".
  local uncalled = nil
  local maxI, maxV, secondV = nil, -1, 0
  for i = 1, n do
    local v = amt[i]
    if v > maxV then
      secondV = maxV >= 0 and maxV or 0
      maxV, maxI = v, i
    elseif v > secondV then
      secondV = v
    end
  end
  if secondV < 0 then secondV = 0 end
  if maxI and maxV > secondV then
    -- Confirm the max is unique (loop above only tracks one max-holder, but a tie
    -- would have left secondV == maxV, so maxV > secondV already implies unique).
    uncalled = { player = player[maxI], amount = maxV - secondV }
    amt[maxI] = secondV
  end

  -- Distinct positive levels in ascending order.
  local levelSet = {}
  for i = 1, n do
    local v = amt[i]
    if v > 0 then levelSet[v] = true end
  end
  local levels = {}
  for v in pairs(levelSet) do levels[#levels + 1] = v end
  sort(levels)

  -- Layer between consecutive levels. Contributors at a level are players whose
  -- amount >= that level (folded included as dead money); eligible are the
  -- non-folded subset, kept in input order for deterministic odd-chip splits.
  local pots = {}
  local deadChips = 0
  local prev = 0
  for _, L in ipairs(levels) do
    local contributors = 0
    local eligible = {}
    for i = 1, n do
      if amt[i] >= L then
        contributors = contributors + 1
        if not folded[i] then eligible[#eligible + 1] = player[i] end
      end
    end
    local layerChips = (L - prev) * contributors
    if layerChips > 0 then
      if #eligible > 0 then
        pots[#pots + 1] = { amount = layerChips, eligible = eligible }
      else
        -- "Dead" layer: every contributor to it folded (e.g. two big stacks raise,
        -- then both fold while short stacks are all-in below them). No live player
        -- is eligible. These chips cannot vanish; fold them into the MAIN pot, where
        -- the best remaining live hand wins them. Dead layers are always ABOVE live
        -- ones, since live all-in players sit at lower contribution levels.
        deadChips = deadChips + layerChips
      end
    end
    prev = L
  end
  if deadChips > 0 then
    if #pots > 0 then
      pots[1].amount = pots[1].amount + deadChips
    else
      -- Degenerate: no contested pot at all (every contributor folded). The caller's
      -- uncontested path owns this case; emit a single dead pot so nothing is lost.
      pots[1] = { amount = deadChips, eligible = {} }
    end
  end

  return { pots = pots, uncalled = uncalled }
end

-- ---------------------------------------------------------------------------
-- award(pots, cmp, oddChipOrder) -> { [playerId] = chipsWon }
--   cmp(a, b) -> -1/0/1 by HAND STRENGTH (stronger -> 1).
--   oddChipOrder: playerIds giving priority for leftover odd chips (first active
--     seat left of the button first). Winners absent from it come last, stable.
--   Total awarded equals the sum of all pot amounts (uncalled is the caller's
--   concern). No chips are lost or created.
-- ---------------------------------------------------------------------------
function Pot.award(pots, cmp, oddChipOrder)
  -- Priority rank for odd chips: lower = earlier. Absent players sort after all
  -- listed ones; ties among absent players keep their eligible (input) order.
  local rank = {}
  if oddChipOrder then
    for i = 1, #oddChipOrder do
      if rank[oddChipOrder[i]] == nil then rank[oddChipOrder[i]] = i end
    end
  end
  local LAST = (oddChipOrder and #oddChipOrder or 0) + 1

  local awards = {}
  for _, pot in ipairs(pots) do
    local elig = pot.eligible
    if #elig == 0 then
      -- A pot with no eligible winner has no legal owner. This never arises from
      -- sidePots() under legal betting; refuse to silently drop the chips — a
      -- verifiable money ledger must fail loud, not vanish chips. The caller
      -- resolves such a (dead) pot explicitly if it ever constructs one.
      error("Pot.award: pot of " .. pot.amount .. " chips has no eligible winners")
    end
    -- winners = eligible players maximal under cmp (all tied at the top).
    local winners = { elig[1] }
    for i = 2, #elig do
      local p = elig[i]
      local d = cmp(p, winners[1])
      if d > 0 then
        winners = { p }            -- strictly stronger: new sole leader
      elseif d == 0 then
        winners[#winners + 1] = p  -- tied at the top
      end
    end

    local w = #winners
    local base = floor(pot.amount / w)
    for i = 1, w do
      awards[winners[i]] = (awards[winners[i]] or 0) + base
    end
    -- Distribute the remainder one chip at a time, by oddChipOrder priority
    -- (each winner takes at most one chip since remainder < #winners).
    local remainder = pot.amount - base * w
    if remainder > 0 then
      -- order winners by (rank, original index) without mutating `winners`.
      local order = {}
      for i = 1, w do order[i] = i end
      sort(order, function(a, b)
        local ra = rank[winners[a]] or LAST
        local rb = rank[winners[b]] or LAST
        if ra ~= rb then return ra < rb end
        return a < b                -- stable on input order for ties
      end)
      for k = 1, remainder do
        local p = winners[order[k]]
        awards[p] = awards[p] + 1
      end
    end
  end

  return awards
end

ns.Pot = Pot
return Pot
