--[[ Host.lua — authoritative session controller (pure; Transport + entropy injected).

  Drives a full Tier-1 hand as a phase machine with "collect-all" barriers. The host
  is itself a seated player (contributes r_host to the joint seed):

    HANDSTART + COMMITSEED -> collect all SEEDCMT -> SEEDREVEAL -> collect all
    -> S = combineSeed -> Dealer.shuffle + commitDeck -> broadcast DECKCMT
    -> collect clients' STATEHASH -> WHISPER HOLE to each client
    -> BETTING: BET_TURN -> (client INTENT | host policy) -> validate via Rules
       -> broadcast ACTED, reveal community as streets advance
    -> settle via Dealer/Rules/Pot -> broadcast HANDEND -> broadcast ENDREVEAL.

  Validation of every client intent is done by the proven Rules engine; the host
  never trusts a client. Broadcast-reliability resend (tick-driven) covers a
  dropped DECKCMT to a straggler.
]]

local ADDON, ns = ...
local Codec, Commit, Dealer, Rules = ns.Codec, ns.Commit, ns.Dealer, ns.Rules
local OP, STREET, ACTION = ns.Const.OP, ns.Const.STREET, ns.Const.ACTION

local Host = {}
Host.__index = Host

local PHASE = {
  COMMIT = "commit", REVEAL = "reveal", STATEHASH = "statehash",
  BETTING = "betting", DONE = "done", ABORT = "abort",
}
Host.PHASE = PHASE

-- default "call station" policy (check, else call, else fold) — enough to reach showdown
local function defaultPolicy(seat, la)
  if la.canCheck then return ACTION.CHECK end
  if la.canCall then return ACTION.CALL, la.callAmount end
  return ACTION.FOLD
end

-- cfg = { transport, selfName, seats={ids incl host}, stacks, buttonSeat, sb, bb,
--         ante, handNo, entropy={r,salt}, nonces=array[52], broadcast="RAID",
--         deadlineTicks (default 20), policy = function(seat, legalActions) -> action, amount,
--         equivocate = { seat=true } (TEST/ATTACK seam) }
function Host.new(cfg)
  return setmetatable({
    tp = cfg.transport, me = cfg.selfName, cfg = cfg,
    seats = cfg.seats, handNo = cfg.handNo or 1,
    broadcast = cfg.broadcast or "RAID",
    deadlineTicks = cfg.deadlineTicks or 20,
    policy = cfg.policy or defaultPolicy,
    human = cfg.human,                 -- human-driven host: wait for humanAct() on its turn
    phase = PHASE.COMMIT,
    commits = {}, reveals = {}, sentReveal = false,
    S = nil, dealer = nil, deckCommits = nil,
    stateHashes = {}, ticks = 0,
    actionNo = 0, revealedStreet = STREET.PREFLOP,
    turnTimeout = cfg.turnTimeout or 25, turnTicks = 0,
  }, Host)
end

local function canonical(seats)
  local c = {}
  for i = 1, #seats do c[i] = seats[i] end
  table.sort(c)
  return c
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function Host:_bcast(op, data) self.tp:post(Codec.encode(op, data), self.broadcast, nil) end

function Host:start()
  self.order = canonical(self.seats)
  self:_bcast(OP.HANDSTART, {
    handNo = self.handNo, button = self.cfg.buttonSeat, sb = self.cfg.sb,
    bb = self.cfg.bb, ante = self.cfg.ante or 0, seats = self.seats,
    stacks = self.cfg.stacks,                       -- chip counts for everyone's display
  })
  self:_bcast(OP.COMMITSEED, { handNo = self.handNo })
  local r, salt = self.cfg.entropy.r, self.cfg.entropy.salt
  self.myR, self.mySalt = r, salt
  self.commits[self.me] = Commit.seedCommit(r, salt)
  self.reveals[self.me] = { r = r, salt = salt }
  self:_bcast(OP.SEEDCMT, { handNo = self.handNo, seat = self.me, commit = self.commits[self.me] })
end

function Host:onMessage(sender, payload, channel)
  if self.phase == PHASE.DONE or self.phase == PHASE.ABORT then return end
  local op, d = Codec.decode(payload)
  if d == nil then return end

  -- only seats in THIS hand may contribute to its barriers or pull its state (a
  -- just-(re)joined spectator's stray commit must not trip the collect-all counts
  -- early, and RESYNC snapshots are for participants only)
  if op == OP.SEEDCMT or op == OP.SEEDREVEAL or op == OP.STATEHASH or op == OP.INTENT
      or op == OP.RESYNC then
    local member = false
    for i = 1, #self.seats do if self.seats[i] == d.seat then member = true break end end
    if not member then return end
  end

  if op == OP.SEEDCMT then
    self.commits[d.seat] = d.commit
  elseif op == OP.SEEDREVEAL then
    if self.commits[d.seat] and not Commit.verifySeed(self.commits[d.seat], d.r, d.salt) then
      self.phase = PHASE.ABORT; self.abortReason = "bad seed reveal from " .. d.seat; return
    end
    self.reveals[d.seat] = { r = d.r, salt = d.salt }
  elseif op == OP.STATEHASH then
    self.stateHashes[d.seat] = d.H
  elseif op == OP.INTENT then
    if self.phase == PHASE.BETTING then self:_applyAction(d.seat, d.action, d.amount) end
    return
  elseif op == OP.RESYNC then
    self:_resync(d.seat); return
  elseif op == OP.CHEAT then
    self.phase = PHASE.ABORT; self.abortReason = "client cheat: " .. (d.detail or ""); return
  end
  self:_advance()
end

function Host:_advance()
  local n = #self.seats
  if not self.sentReveal and count(self.commits) >= n then
    self.sentReveal = true
    self.phase = PHASE.REVEAL
    self:_bcast(OP.SEEDREVEAL, { handNo = self.handNo, seat = self.me, r = self.myR, salt = self.mySalt })
  end

  if not self.S and self.sentReveal and count(self.reveals) >= n then
    local rList = {}
    for i = 1, #self.order do
      local rv = self.reveals[self.order[i]]
      if not rv then return end
      rList[i] = rv.r
    end
    self.S = Commit.combineSeed(rList)
    self.dealer = Dealer.start({
      variant = "texas", order = self.seats, stacks = self.cfg.stacks,
      buttonSeat = self.cfg.buttonSeat, sb = self.cfg.sb, bb = self.cfg.bb,
      ante = self.cfg.ante or 0, handNo = self.handNo, seed = self.S, nonces = self.cfg.nonces,
    })
    self.deckCommits = self.dealer.commits
    self.phase = PHASE.STATEHASH
    if self.cfg.equivocate then self:_sendEquivocatedDeck()
    else self:_bcast(OP.DECKCMT, { handNo = self.handNo, commits = self.deckCommits }) end
    local H = self.dealer:stateHash()
    self.stateHashes[self.me] = H
    self:_bcast(OP.STATEHASH, { handNo = self.handNo, seat = self.me, H = H })
  end

  if self.S and self.phase == PHASE.STATEHASH and count(self.stateHashes) >= n then
    self:_deal()
    self:_startBetting()
  end
end

function Host:_deal()
  for i = 1, #self.seats do
    local seat = self.seats[i]
    if seat ~= self.me then
      self.tp:sendReliable(Codec.encode(OP.HOLE,
        { handNo = self.handNo, seat = seat, reveals = self.dealer:holeReveal(seat) }), seat)
    end
  end
end

-- reveal community cards for any street newly entered (up to river when complete)
function Host:_syncBoard()
  local rules = self.dealer.rules
  local target = rules.complete and STREET.RIVER or rules.street
  while self.revealedStreet < target do
    self.revealedStreet = self.revealedStreet + 1
    local st = self.revealedStreet
    local rv = (st == STREET.FLOP and self.dealer:flopReveal())
      or (st == STREET.TURN and self.dealer:turnReveal())
      or (st == STREET.RIVER and self.dealer:riverReveal())
    if rv then
      self:_bcast(OP.REVEAL, { handNo = self.handNo, street = st, reveals = rv })
      local cards = {}
      for i = 1, #rv do cards[i] = rv[i].val end
      self:_bcast(OP.BOARD, { handNo = self.handNo, street = st, cards = cards })
    end
  end
end

function Host:_startBetting()
  self.phase = PHASE.BETTING
  self:_promptTurn()
end

-- the BET_TURN payload for a seat's turn: includes the full bet/raise-TO range so a
-- client can submit a VALID raise-to amount (minRaiseSize alone is just the increment
-- and led clients to send illegal raises).
function Host:_betTurnPayload(seat, la)
  local minTo, maxTo
  if la.canRaise then minTo, maxTo = la.minRaiseTo, la.maxRaiseTo
  elseif la.canBet then minTo, maxTo = la.minBetTo, la.maxBetTo end
  local rules, pot = self.dealer.rules, 0
  for i = 1, #self.seats do pot = pot + rules.seats[self.seats[i]].total end
  return {
    handNo = self.handNo, actionNo = self.actionNo, seat = seat,
    toCall = la.toCall or 0, minRaise = rules.minRaiseSize,
    minTo = minTo, maxTo = maxTo, canCheck = la.canCheck, pot = pot,
  }
end

function Host:_promptTurn()
  local rules = self.dealer.rules
  if rules.complete then return self:_finishHand() end
  local seat = rules.toAct
  if not seat then return self:_finishHand() end
  if self.absent and self.absent[seat] then           -- player left the table: auto-fold
    self.actionNo = self.actionNo + 1
    return self:_applyAction(seat, ACTION.FOLD)
  end
  self.turnTicks = 0                                  -- (re)start the turn clock
  self.actionNo = self.actionNo + 1
  local la = Rules.legalActions(rules, seat)
  self:_bcast(OP.BET_TURN, self:_betTurnPayload(seat, la))
  if seat == self.me then
    if self.human then
      self.awaitingAction = la         -- wait for humanAct() (slash command / UI)
    else
      local action, amount = self.policy(seat, la)
      self:_applyAction(seat, action, amount)
    end
  end
end

-- a seat stood up / went silent for good: fold them now (or as soon as it's their
-- turn) so the hand can never hang waiting on someone who is gone.
function Host:markAbsent(seat)
  if seat == self.me then return end
  self.absent = self.absent or {}
  self.absent[seat] = true
  if self.phase == PHASE.BETTING and self.dealer and self.dealer.rules.toAct == seat then
    self:_applyAction(seat, ACTION.FOLD)
  end
end

-- legal actions for the (human) host on its own turn, or nil
function Host:legalForMe()
  if self.dealer and self.phase == PHASE.BETTING and self.dealer.rules.toAct == self.me then
    return Rules.legalActions(self.dealer.rules, self.me)
  end
end

-- the human host commits an action on its turn
function Host:humanAct(action, amount)
  if self.phase ~= PHASE.BETTING or not self.dealer or self.dealer.rules.toAct ~= self.me then
    return false, "not your turn"
  end
  -- clear BEFORE applying: _applyAction can advance play right back to our own next
  -- turn (heads-up street change) and set a fresh awaitingAction we must not clobber.
  local pending = self.awaitingAction
  self.awaitingAction = nil
  local ok, err = self:_applyAction(self.me, action, amount)
  if not ok then self.awaitingAction = pending end  -- illegal: still our turn, keep waiting
  return ok, err
end

function Host:_applyAction(seat, action, amount)
  local rules = self.dealer.rules
  if rules.toAct ~= seat then return false, "not your turn" end   -- stale / out of turn
  local ok, err = Rules.applyAction(rules, seat, action, amount)
  if not ok then
    -- an illegal intent must NEVER wedge the hand: tell the actor why and re-prompt
    -- them (their client clears its prompt when it sends an intent, so without this
    -- re-BET_TURN both sides would wait on each other forever).
    if seat ~= self.me then
      self.tp:sendReliable(Codec.encode(OP.REFUSE,
        { handNo = self.handNo, actionNo = self.actionNo, reason = err or "illegal action" }), seat)
      self:_bcast(OP.BET_TURN, self:_betTurnPayload(seat, Rules.legalActions(rules, seat)))
    end
    return false, err
  end
  local s = rules.seats[seat]
  self:_bcast(OP.ACTED, {
    handNo = self.handNo, actionNo = self.actionNo, seat = seat,
    action = action, amount = amount or 0, allin = s.allIn,
  })
  self:_syncBoard()
  if rules.complete then self:_finishHand() else self:_promptTurn() end
  return true
end

function Host:_finishHand()
  if self.phase == PHASE.DONE then return end
  self:_syncBoard()                                 -- reveal any remaining board (all-in runout)
  local awards, board, holeBySeat = self.dealer:settle()   -- settles via Rules/Pot
  self.awards = awards
  local deltas = {}
  for i = 1, #self.seats do
    local seat = self.seats[i]
    deltas[seat] = self.dealer.rules.seats[seat].stack - self.cfg.stacks[seat]
  end
  self.deltas = deltas                              -- kept for the end-of-hand view

  -- showdown: open every unfolded player's hole cards (commitment-verifiable) with
  -- their hand name. Never on a fold-win — in poker an uncalled hand isn't shown.
  self.showdown = nil
  local unfolded = 0
  for _ in pairs(holeBySeat) do unfolded = unfolded + 1 end
  if unfolded >= 2 then
    self.showdown = {}
    for seat, hole in pairs(holeBySeat) do
      local all = { hole[1], hole[2], board[1], board[2], board[3], board[4], board[5] }
      local name
      local ok, score = pcall(ns.HandEval.evaluate, all)
      if ok then local ok2, n = pcall(ns.HandEval.describe, score); if ok2 then name = n end end
      self.showdown[seat] = { cards = { hole[1], hole[2] }, handName = name }
      self:_bcast(OP.SHOWDOWN, {
        handNo = self.handNo, seat = seat,
        reveals = self.dealer:holeReveal(seat), handName = name or "",
      })
    end
  end

  self:_bcast(OP.HANDEND, { handNo = self.handNo, deltas = deltas })
  self:_bcast(OP.ENDREVEAL, {
    handNo = self.handNo, S = self.S, seedReveals = self.reveals,
    openings = self.dealer:endRevealOpenings(),
  })
  self.phase = PHASE.DONE
  if self.cfg.onComplete then self.cfg.onComplete(self) end   -- TableHost: carry stacks, next hand
end

-- Disconnect/resume: rebuild a returning player's view. Sends the current public
-- state (SNAPSHOT), re-sends the deck commitment, and re-whispers their hole. A
-- mid-hand reconnecting client gets a REDUCED guarantee for that hand (it relies on
-- host-provided commit data and missed the live STATEHASH gate); full independent
-- verification resumes next hand. See DESIGN.md / README.
function Host:_resync(seat)
  if not self.dealer or self.phase == PHASE.DONE or self.phase == PHASE.ABORT then return end
  local rules = self.dealer.rules
  local seatInfo = {}
  for i = 1, #self.seats do
    local s = rules.seats[self.seats[i]]
    seatInfo[self.seats[i]] = {
      stack = s.stack, committed = s.committed, total = s.total, folded = s.folded, allIn = s.allIn,
    }
  end
  local boardCount = self.dealer.variant.boardSchedule[self.revealedStreet] or 0
  self.tp:sendReliable(Codec.encode(OP.SNAPSHOT, {
    handNo = self.handNo, button = self.cfg.buttonSeat, sb = self.cfg.sb, bb = self.cfg.bb,
    street = rules.street, currentBet = rules.currentBet, minRaise = rules.minRaiseSize,
    toAct = rules.toAct, S = self.S, seats = self.seats, seatInfo = seatInfo,
    board = self.dealer:boardCards(boardCount), commits = self.commits,
  }), seat)
  self.tp:sendReliable(Codec.encode(OP.DECKCMT, { handNo = self.handNo, commits = self.deckCommits }), seat)
  if seat ~= self.me then
    self.tp:sendReliable(Codec.encode(OP.HOLE,
      { handNo = self.handNo, seat = seat, reveals = self.dealer:holeReveal(seat) }), seat)
  end
end

-- TEST / ATTACK SEAM: send a DIFFERENT (stacked) deck commitment to cfg.equivocate
-- seats than to everyone else. The cross-client STATEHASH check must catch it.
function Host:_sendEquivocatedDeck()
  local alt = {}
  for i = 1, 52 do alt[i] = self.dealer.deck[53 - i] end
  local altCommits = Commit.commitDeck(alt, self.cfg.nonces)
  for i = 1, #self.seats do
    local seat = self.seats[i]
    if seat ~= self.me then
      local commits = self.cfg.equivocate[seat] and altCommits or self.deckCommits
      self.tp:sendReliable(Codec.encode(OP.DECKCMT, { handNo = self.handNo, commits = commits }), seat)
    end
  end
end

function Host:tick()
  self.ticks = self.ticks + 1
  if self.phase == PHASE.STATEHASH and self.S and self.ticks % self.deadlineTicks == 0 then
    for i = 1, #self.seats do
      local seat = self.seats[i]
      if seat ~= self.me and not self.stateHashes[seat] then
        self.tp:sendReliable(Codec.encode(OP.DECKCMT,
          { handNo = self.handNo, commits = self.deckCommits }), seat)
      end
    end
  end
  -- turn timeout (online-poker convention): an unresponsive player auto-CHECKS
  -- when checking is free, otherwise folds — applies to every human seat, the
  -- (human) dealer included, so nobody can hold the table hostage.
  if self.phase == PHASE.BETTING and self.dealer then
    local seat = self.dealer.rules.toAct
    if seat and (seat ~= self.me or self.human) then
      self.turnTicks = self.turnTicks + 1
      if self.turnTicks >= self.turnTimeout then
        self.turnTicks = 0
        local la = Rules.legalActions(self.dealer.rules, seat)
        if seat == self.me then self.awaitingAction = nil end
        self:_applyAction(seat, (la and la.canCheck) and ACTION.CHECK or ACTION.FOLD)
      end
    end
  end
end

ns.Host = Host
return Host
