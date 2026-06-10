--[[ Rules.lua — pure Texas Hold'em betting state machine (variant-driven).

  No WoW API; fully unit-testable. Manages blinds/antes, button-relative action
  order (incl. the heads-up special case), betting rounds, min-raise and the
  short-all-in "no reopen" rule, all-in side-pot integration (via ns.Pot), street
  progression, and showdown settlement (via the variant's bestHand + ns.Pot).

  Cards are NOT dealt here — the host/Deck layer supplies hole cards + board at
  settle(). Chip amounts in actions are "TO" totals for the current street:
  bet/raise `amount` is the player's target committed-this-street total.

  Action model (the subtle bits):
    needsAction(s) = not folded and not all-in and
                     (committed < currentBet  OR  not hasActed)
      -> "committed < currentBet" forces a call after a raise; "not hasActed"
         gives the BB its option and makes a checked-around street close.
    A betting round closes when no seat needsAction.
    mayRaise(s): a full bet/raise reopens raising for everyone; a short all-in
         (raise increment < minRaiseSize) only lets players whose action was still
         open re-raise — players who had already closed may only call/fold.
]]

local ADDON, ns = ...
local STREET = ns.Const.STREET
local A = ns.Const.ACTION
local min = math.min

local Rules = {}

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------
local function nextPos(pos, n) return (pos % n) + 1 end

local function posOfSeat(state, id)
  for i = 1, #state.order do if state.order[i] == id then return i end end
end

-- put up to `amount` chips from a seat into the pot; mark all-in when busted.
local function postChips(state, id, amount, toCommitted)
  local s = state.seats[id]
  local pay = amount
  if pay > s.stack then pay = s.stack end
  if pay < 0 then pay = 0 end
  s.stack = s.stack - pay
  s.total = s.total + pay
  if toCommitted then s.committed = s.committed + pay end
  if s.stack == 0 then s.allIn = true end
  return pay
end

local function maxCommitted(state)
  local m = 0
  for i = 1, #state.order do
    local c = state.seats[state.order[i]].committed
    if c > m then m = c end
  end
  return m
end

local function needsAction(state, s)
  if s.folded or s.allIn then return false end
  return s.committed < state.currentBet or not s.hasActed
end

-- next seat that still needs to act, scanning clockwise from startPos (inclusive)
local function findNextActor(state, startPos)
  local n = #state.order
  for k = 0, n - 1 do
    local pos = ((startPos - 1 + k) % n) + 1
    if needsAction(state, state.seats[state.order[pos]]) then return pos end
  end
  return nil
end

-- Reopen the action after an aggressive bet/raise. A FULL bet/raise gives every
-- other live player a fresh action (clear hasActed) -> they may call OR raise. A
-- SHORT all-in (increment < min-raise) reopens for NOBODY: players who already
-- acted may only call/fold, and players who have not yet acted keep their pending
-- action (hasActed already false). "may raise" is therefore exactly "not hasActed"
-- (see legalActions) — no fragile comparison against the moving current bet.
local function reopen(state, raiserId, fullAggression)
  if not fullAggression then return end
  for i = 1, #state.order do
    local id = state.order[i]
    local s = state.seats[id]
    if id ~= raiserId and not s.folded and not s.allIn then
      s.hasActed = false
    end
  end
end

local function record(state, id, action, amount)
  state.history[#state.history + 1] =
    { seat = id, action = action, amount = amount, street = state.street }
end

local function oddChipOrder(state)
  local n, out = #state.order, {}
  for k = 1, n do
    local pos = ((state.buttonPos - 1 + k) % n) + 1   -- start at SB (left of button)
    local s = state.seats[state.order[pos]]
    if not s.folded then out[#out + 1] = s.id end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- street transitions
-- ---------------------------------------------------------------------------
local function advanceStreet(state)
  state.street = state.street + 1
  for i = 1, #state.order do
    local s = state.seats[state.order[i]]
    s.committed = 0
    s.hasActed = false
  end
  state.currentBet = 0
  state.minRaiseSize = state.bb
  local startPos = (#state.order == 2) and state.bbPos or state.sbPos
  local p = findNextActor(state, startPos)
  state.toAct = p and state.order[p] or nil
end

local function closeBettingRound(state)
  local nonFolded = {}
  for i = 1, #state.order do
    local s = state.seats[state.order[i]]
    if not s.folded then nonFolded[#nonFolded + 1] = s end
  end

  if #nonFolded <= 1 then
    state.complete = true
    state.endReason = "uncontested"
    state.winners = { nonFolded[1] and nonFolded[1].id or nil }
    state.toAct = nil
    return
  end

  local withChips = 0
  for i = 1, #nonFolded do
    if not nonFolded[i].allIn and nonFolded[i].stack > 0 then withChips = withChips + 1 end
  end

  if withChips <= 1 then
    -- no further betting possible: run the board out and go to showdown
    state.street = STREET.RIVER
    state.complete = true
    state.endReason = "showdown"
    state.toAct = nil
  elseif state.street < STREET.RIVER then
    advanceStreet(state)
  else
    state.complete = true
    state.endReason = "showdown"
    state.toAct = nil
  end
end

-- ---------------------------------------------------------------------------
-- startHand(cfg) -> state
--   cfg = { variant=<impl|name>, order={seatId,...} (seating order, clockwise),
--           stacks={[seatId]=chips}, buttonSeat=seatId, sb=, bb=, ante= (opt 0) }
-- ---------------------------------------------------------------------------
function Rules.startHand(cfg)
  local variant = type(cfg.variant) == "string" and ns.Variant.get(cfg.variant) or cfg.variant
  if not variant then error("Rules.startHand: unknown variant") end
  local order = cfg.order
  local n = #order
  if n < 2 then error("Rules.startHand: need >= 2 players") end

  local state = {
    variant = variant,
    sb = cfg.sb, bb = cfg.bb, ante = cfg.ante or 0,
    order = order,
    street = STREET.PREFLOP,
    currentBet = 0,
    minRaiseSize = cfg.bb,
    seats = {},
    history = {},
    complete = false,
  }

  local buttonPos
  for i = 1, n do if order[i] == cfg.buttonSeat then buttonPos = i end end
  if not buttonPos then error("Rules.startHand: buttonSeat not in order") end
  state.buttonPos = buttonPos

  for i = 1, n do
    local id = order[i]
    state.seats[id] = {
      id = id, stack = cfg.stacks[id], committed = 0, total = 0,
      folded = false, allIn = false, hasActed = false,
    }
  end

  -- antes (dead money: into the pot/total, NOT toward currentBet)
  if state.ante > 0 then
    for i = 1, n do postChips(state, order[i], state.ante, false) end
  end

  -- blinds + first-to-act (heads-up: button is SB and acts first preflop)
  local sbPos, bbPos, firstPos
  if n == 2 then
    sbPos, bbPos, firstPos = buttonPos, nextPos(buttonPos, n), buttonPos
  else
    sbPos = nextPos(buttonPos, n)
    bbPos = nextPos(sbPos, n)
    firstPos = nextPos(bbPos, n)
  end
  state.sbPos, state.bbPos = sbPos, bbPos
  postChips(state, order[sbPos], state.sb, true)
  postChips(state, order[bbPos], state.bb, true)
  state.currentBet = maxCommitted(state)
  state.minRaiseSize = state.bb

  local p = findNextActor(state, firstPos)
  if p then
    state.toAct = state.order[p]
  else
    -- everyone already all-in from blinds/antes
    closeBettingRound(state)
  end
  return state
end

-- ---------------------------------------------------------------------------
-- legalActions(state, id) -> table of booleans + amounts (empty if not to act)
-- ---------------------------------------------------------------------------
function Rules.legalActions(state, id)
  local s = state.seats[id]
  if state.complete or state.toAct ~= id or not s or s.folded or s.allIn then
    return {}
  end
  local toCall = state.currentBet - s.committed
  if toCall < 0 then toCall = 0 end

  local la = { canFold = true, toCall = toCall }
  la.canCheck = (toCall == 0)
  la.canCall = (toCall > 0)
  la.callAmount = min(toCall, s.stack)

  if state.currentBet == 0 then
    if s.stack > 0 then
      la.canBet = true
      la.minBetTo = min(state.bb, s.stack)   -- all-in for < bb is allowed
      la.maxBetTo = s.stack
    end
  else
    -- may raise iff the action was reopened to this seat (no full raise has closed
    -- their action since) -> exactly "not hasActed". A short all-in never reopens.
    if (not s.hasActed) and s.stack > toCall then
      la.canRaise = true
      la.minRaiseTo = state.currentBet + state.minRaiseSize
      la.maxRaiseTo = s.committed + s.stack  -- all-in cap
      if la.minRaiseTo > la.maxRaiseTo then
        la.minRaiseTo = la.maxRaiseTo         -- only a short all-in raise remains
      end
    end
  end
  return la
end

-- ---------------------------------------------------------------------------
-- applyAction(state, id, action, amount) -> ok, err
-- ---------------------------------------------------------------------------
function Rules.applyAction(state, id, action, amount)
  if state.complete then return false, "hand complete" end
  if state.toAct ~= id then return false, "not your turn" end
  local s = state.seats[id]
  local la = Rules.legalActions(state, id)
  local actorPos = posOfSeat(state, id)

  if action == A.FOLD then
    s.folded = true
    s.hasActed = true

  elseif action == A.CHECK then
    if not la.canCheck then return false, "cannot check; must call " .. la.toCall end
    s.hasActed = true

  elseif action == A.CALL then
    if not la.canCall then return false, "nothing to call" end
    postChips(state, id, state.currentBet - s.committed, true)
    s.hasActed = true

  elseif action == A.BET then
    if not la.canBet then return false, "cannot bet" end
    if type(amount) ~= "number" then return false, "bet needs an amount" end
    if amount < la.minBetTo or amount > la.maxBetTo then return false, "bet out of range" end
    postChips(state, id, amount - s.committed, true)
    state.currentBet = s.committed
    local fullBet = state.currentBet >= state.bb
    if fullBet then state.minRaiseSize = state.currentBet end
    reopen(state, id, fullBet)
    s.hasActed = true

  elseif action == A.RAISE then
    if not la.canRaise then return false, "cannot raise" end
    if type(amount) ~= "number" then return false, "raise needs an amount" end
    if amount > la.maxRaiseTo then return false, "raise exceeds stack" end
    if amount <= state.currentBet then return false, "raise must exceed current bet" end
    local isAllIn = (amount == s.committed + s.stack)
    if amount < la.minRaiseTo and not isAllIn then return false, "raise too small" end
    local oldBet = state.currentBet
    postChips(state, id, amount - s.committed, true)
    state.currentBet = s.committed
    local increment = state.currentBet - oldBet
    local fullRaise = increment >= state.minRaiseSize
    if fullRaise then state.minRaiseSize = increment end
    reopen(state, id, fullRaise)
    s.hasActed = true

  else
    return false, "unknown action: " .. tostring(action)
  end

  record(state, id, action, amount)

  -- Uncontested: the moment only one non-folded player remains, the hand is over
  -- and that player is never asked to act. (Must be checked here, immediately on a
  -- fold, not deferred to round-close — otherwise the lone survivor could be given
  -- a turn and fold too, leaving zero players.)
  local alive, lastAlive = 0, nil
  for i = 1, #state.order do
    local s = state.seats[state.order[i]]
    if not s.folded then alive = alive + 1; lastAlive = s.id end
  end
  if alive <= 1 then
    state.complete = true
    state.endReason = "uncontested"
    state.winners = { lastAlive }
    state.toAct = nil
    return true
  end

  local nextP = findNextActor(state, nextPos(actorPos, #state.order))
  if nextP then
    state.toAct = state.order[nextP]
  else
    state.toAct = nil
    closeBettingRound(state)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- queries + settlement
-- ---------------------------------------------------------------------------
function Rules.contribs(state)
  local c = {}
  for i = 1, #state.order do
    local s = state.seats[state.order[i]]
    c[#c + 1] = { player = s.id, amount = s.total, folded = s.folded }
  end
  return c
end

function Rules.potTotal(state)
  local t = 0
  for i = 1, #state.order do t = t + state.seats[state.order[i]].total end
  return t
end

-- how many community cards should be visible at the current street
function Rules.boardCount(state)
  return state.variant.boardSchedule[state.street]
end

-- settle a completed hand. holeBySeat: { [seatId] = {cardId, ...} } for non-folded
-- seats; board: array of community card ids (5 at showdown). Returns awards map,
-- applies winnings to stacks, and stashes state.awards / state.sidePots.
function Rules.settle(state, holeBySeat, board)
  if not state.complete then error("Rules.settle: hand not complete") end
  local awards = {}

  if state.endReason == "uncontested" then
    local winner = state.winners[1]
    awards[winner] = Rules.potTotal(state)
  else
    local side = ns.Pot.sidePots(Rules.contribs(state))
    local scores = {}
    for i = 1, #state.order do
      local s = state.seats[state.order[i]]
      if not s.folded then
        scores[s.id] = state.variant:bestHand(holeBySeat[s.id], board)
      end
    end
    local cmp = function(a, b) return ns.HandEval.compare(scores[a], scores[b]) end
    awards = ns.Pot.award(side.pots, cmp, oddChipOrder(state))
    if side.uncalled then
      awards[side.uncalled.player] = (awards[side.uncalled.player] or 0) + side.uncalled.amount
    end
    state.sidePots = side
  end

  for id, amt in pairs(awards) do
    state.seats[id].stack = state.seats[id].stack + amt
  end
  state.awards = awards
  return awards
end

ns.Rules = Rules
return Rules
