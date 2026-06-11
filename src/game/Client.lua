--[[ Client.lua — pure client-side session participant + verifier.

  Never trusts the host. Drives its half of the Tier-1 protocol as a message-driven
  phase machine (no WoW API; Transport + entropy injected):

    HANDSTART -> generate r_i, broadcast SEEDCMT
    collect ALL commits -> broadcast SEEDREVEAL          (commit-before-reveal)
    collect ALL reveals (verify each vs its commit) -> compute S
    DECKCMT  -> store commitments, compute H, broadcast STATEHASH
    collect ALL peers' STATEHASH -> if any differ, CHEAT+abort BEFORE any deal
    HOLE (whisper) -> verify own cards open their commitments
    REVEAL         -> verify community cards open their commitments
    BET_TURN -> INTENT (policy); ACTED/HANDEND mirror public state
    ENDREVEAL      -> Verify.endOfHand on the real transcript

  DISCONNECT/RESUME: after a relog (all state lost) the client calls resume(host),
  sending RESYNC; the host replies with a SNAPSHOT (+ re-sent DECKCMT and re-whispered
  hole) from which the client bootstraps and continues. A reconnecting client gets a
  REDUCED guarantee for that hand (it relies on host-provided commit data and missed
  the live STATEHASH gate); full verification resumes next hand. Message handling is
  order-tolerant (context-free data is buffered until it can be verified).
]]

local ADDON, ns = ...
local Codec, Commit, Verify = ns.Codec, ns.Commit, ns.Verify
local OP, CC = ns.Const.OP, ns.Const

local Client = {}
Client.__index = Client

local PHASE = {
  IDLE = "idle", COMMIT = "commit", REVEAL = "reveal", DECK = "deck",
  STATEHASH = "statehash", DEAL = "deal", DONE = "done", ABORT = "abort",
}
Client.PHASE = PHASE

local function defaultClientPolicy(toCall, minRaise)
  if toCall == 0 then return CC.ACTION.CHECK end
  return CC.ACTION.CALL
end

function Client.new(cfg)
  return setmetatable({
    tp = cfg.transport, me = cfg.selfName, entropy = cfg.entropy,
    broadcast = cfg.broadcast or "RAID", onCheat = cfg.onCheat,
    policy = cfg.policy or defaultClientPolicy,
    human = cfg.human, prompt = nil,   -- human-driven client: wait for humanAct() on its turn
    hostName = nil, deltas = nil, folded = {},
    phase = PHASE.IDLE,
    seats = nil, order = nil, handNo = nil,
    commits = {}, reveals = {}, sentReveal = false,
    S = nil, H = nil, deckCommits = nil, sentStateHash = false, stateHashes = {},
    pendingHole = nil, pendingReveals = {}, pendingBetTurn = nil, resumed = false,
    hole = nil, holeVerified = false, board = {}, boardVerified = true,
    auditPassed = false, aborted = false, cheat = nil,
  }, Client)
end

local function canonical(seats)
  local c = {}
  for i = 1, #seats do c[i] = seats[i] end
  table.sort(c)
  return c
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function Client:_abort(code, detail)
  if self.aborted then return end
  self.aborted = true
  self.phase = PHASE.ABORT
  self.cheat = { code = code, detail = detail }
  if self.onCheat then self.onCheat(code, detail) end
  self.tp:post(Codec.encode(OP.CHEAT, { handNo = self.handNo or 0, code = code, detail = detail or "" }),
    self.broadcast, nil)
end

function Client:_bcast(op, data) self.tp:post(Codec.encode(op, data), self.broadcast, nil) end

-- after a relog: ask the host to bring us current
function Client:resume(hostName)
  self.hostName = hostName
  self.tp:sendReliable(Codec.encode(OP.RESYNC, { handNo = self.handNo or 0, seat = self.me }), hostName)
end

function Client:onMessage(sender, payload, channel)
  if self.aborted then return end          -- a detected cheat halts permanently
  local op, d = Codec.decode(payload)
  if d == nil then return end

  -- pre-bootstrap (fresh / relogged): only HANDSTART or SNAPSHOT start us. Store
  -- context-free DECKCMT/HOLE and buffer our BET_TURN until we've bootstrapped.
  if not self.seats then
    if op == OP.SNAPSHOT then return self:_bootstrap(d, sender) end
    if op ~= OP.HANDSTART then
      if op == OP.DECKCMT then self.deckCommits = d.commits
      elseif op == OP.HOLE and d.seat == self.me then self.pendingHole = d.reveals
      elseif op == OP.BET_TURN and d.seat == self.me then self.pendingBetTurn = d end
      return
    end
  end

  if op == OP.HANDSTART then
    -- only play hands we are actually seated in: a freshly (re)joined client can see
    -- the table's current hand before its own seat takes effect next hand — joining
    -- that handshake as a phantom would corrupt the table's commit barriers.
    local seated = false
    for i = 1, #d.seats do if d.seats[i] == self.me then seated = true break end end
    if not seated then
      self.seats, self.phase, self.prompt, self.toActSeat = nil, PHASE.IDLE, nil, nil
      self.pendingHole, self.pendingBetTurn, self.deckCommits = nil, nil, nil
      return
    end
    -- reset per-hand state so one Client plays an unbounded series of hands
    self.commits, self.reveals, self.sentReveal = {}, {}, false
    self.S, self.H, self.deckCommits, self.sentStateHash, self.stateHashes = nil, nil, nil, false, {}
    self.pendingHole, self.pendingReveals, self.pendingBetTurn, self.resumed = nil, {}, nil, false
    self.hole, self.holeVerified, self.board, self.boardVerified = nil, false, {}, true
    self.auditPassed, self.deltas, self.folded = false, nil, {}
    self.toActSeat, self.prompt, self.lastActed, self.showdown = nil, nil, nil, nil
    self.handNo = d.handNo
    self.seats = d.seats
    self.order = canonical(d.seats)
    self.hostName = sender
    self.phase = PHASE.COMMIT
    -- entropy may be a fixed table (single-hand tests) or a per-hand function (a
    -- persistent client across many hands MUST draw fresh r_i each hand)
    local e = type(self.entropy) == "function" and self.entropy() or self.entropy
    local r, salt = e.r, e.salt
    self.myR, self.mySalt = r, salt
    self.commits[self.me] = Commit.seedCommit(r, salt)
    self.reveals[self.me] = { r = r, salt = salt }
    self:_bcast(OP.SEEDCMT, { handNo = self.handNo, seat = self.me, commit = self.commits[self.me] })

  elseif op == OP.SNAPSHOT then
    -- already running on our own witnessed state; ignore a late snapshot

  elseif op == OP.SEEDCMT then
    self.commits[d.seat] = d.commit

  elseif op == OP.SEEDREVEAL then
    if self.commits[d.seat] and not Commit.verifySeed(self.commits[d.seat], d.r, d.salt) then
      return self:_abort(Verify.CODE.SEED, "seat " .. d.seat .. " seed does not open its commitment")
    end
    self.reveals[d.seat] = { r = d.r, salt = d.salt }

  elseif op == OP.DECKCMT then
    self.deckCommits = d.commits
    self:_tryVerifyHole()
    self:_tryVerifyReveals()

  elseif op == OP.STATEHASH then
    self.stateHashes[d.seat] = d.H

  elseif op == OP.HOLE then
    if d.seat == self.me then self.pendingHole = d.reveals; self:_tryVerifyHole() end

  elseif op == OP.REVEAL then
    self.pendingReveals[#self.pendingReveals + 1] = d.reveals
    self:_tryVerifyReveals()

  elseif op == OP.BET_TURN then
    self.toActSeat = d.seat                      -- public: whose turn it is (for the UI)
    if d.seat == self.me and self.phase == PHASE.DEAL then
      if self.human then
        -- minTo/maxTo: the legal bet/raise-TO range from the host (raise amounts are
        -- raise-TO totals). A re-sent BET_TURN after a refused intent lands here too,
        -- restoring the prompt so the player can try again.
        self.prompt = { toCall = d.toCall, minRaise = d.minRaise, actionNo = d.actionNo,
                        minTo = d.minTo, maxTo = d.maxTo, canCheck = d.canCheck }
      else
        self:_act(d.toCall, d.minRaise, d.actionNo)
      end
    end

  elseif op == OP.REFUSE then
    -- host rejected our intent (e.g. raise too small); surface why. The prompt comes
    -- back via the host's re-sent BET_TURN.
    self.lastRefuse = d.reason ~= "" and d.reason or "action refused"

  elseif op == OP.ACTED then
    if d.action == CC.ACTION.FOLD then self.folded[d.seat] = true end
    self.lastActed = d

  elseif op == OP.SHOWDOWN then
    -- a seat's hole cards opened at showdown: verify them against the same deck
    -- commitments as every other card before trusting what the host claims
    if self.deckCommits then
      for i = 1, #d.reveals do
        local rv = d.reveals[i]
        if not Verify.card(self.deckCommits[rv.pos + 1], rv.val, rv.pos, rv.nonce) then
          return self:_abort(Verify.CODE.COMMIT,
            "showdown card at pos " .. rv.pos .. " does not open its commitment")
        end
      end
    end
    local cards = {}
    for i = 1, #d.reveals do cards[i] = d.reveals[i].val end
    self.showdown = self.showdown or {}
    self.showdown[d.seat] = { cards = cards, handName = d.handName ~= "" and d.handName or nil }

  elseif op == OP.HANDEND then
    self.deltas = d.deltas

  elseif op == OP.ENDREVEAL then
    self:_audit(d)

  elseif op == OP.CHEAT then
    self:_abort(d.code, "peer-reported: " .. (d.detail or ""))
  end

  self:_advance()
end

function Client:_act(toCall, minRaise, actionNo)
  if toCall < 0 then toCall = 0 end
  local action, amount = self.policy(toCall, minRaise or 0)
  self.tp:sendReliable(Codec.encode(OP.INTENT, {
    handNo = self.handNo, actionNo = actionNo or 0, seat = self.me,
    action = action, amount = amount or 0,
  }), self.hostName)
end

function Client:_bootstrap(d, sender)
  if self.seats then return end
  self.handNo = d.handNo
  self.seats = d.seats
  self.order = canonical(d.seats)
  self.hostName = sender
  self.S = d.S
  self.commits = d.commits           -- host-provided seedCommits (reduced trust this hand)
  self.currentBet, self.minRaise = d.currentBet, d.minRaise
  self.mySeatInfo = d.seatInfo[self.me]
  -- mark the handshake as already-passed so _advance is a no-op for us
  self.sentReveal, self.sentStateHash, self.resumed = true, true, true
  self.phase = PHASE.DEAL
  self:_tryVerifyHole()
  self:_tryVerifyReveals()
  -- act if it is (or, per a buffered prompt, was) our turn
  local toCall
  if d.toAct == self.me then
    toCall = (d.currentBet or 0) - ((self.mySeatInfo and self.mySeatInfo.committed) or 0)
  elseif self.pendingBetTurn and self.pendingBetTurn.seat == self.me then
    toCall = self.pendingBetTurn.toCall
  end
  if toCall ~= nil then
    if self.human then self.prompt = { toCall = toCall, minRaise = d.minRaise, actionNo = 0 }
    else self:_act(toCall, d.minRaise, 0) end
  end
end

-- the human player commits an action when prompted (slash command / UI)
function Client:humanAct(action, amount)
  if not self.prompt then return false, "not your turn" end
  local p = self.prompt; self.prompt = nil
  self.tp:sendReliable(Codec.encode(OP.INTENT, {
    handNo = self.handNo, actionNo = p.actionNo, seat = self.me, action = action, amount = amount or 0,
  }), self.hostName)
  return true
end

function Client:_advance()
  if self.aborted or not self.seats or self.resumed then return end
  local nSeats = #self.seats

  if not self.sentReveal and count(self.commits) >= nSeats then
    self.sentReveal = true
    self.phase = PHASE.REVEAL
    self:_bcast(OP.SEEDREVEAL, { handNo = self.handNo, seat = self.me, r = self.myR, salt = self.mySalt })
  end

  if not self.S and self.sentReveal and count(self.reveals) >= nSeats then
    local rList = {}
    for i = 1, #self.order do
      local rv = self.reveals[self.order[i]]
      if not rv then return end
      rList[i] = rv.r
    end
    self.S = Commit.combineSeed(rList)
    self.phase = PHASE.DECK
  end

  if self.S and self.deckCommits and not self.sentStateHash then
    self.H = Commit.stateHash(self.handNo, self.S, self.deckCommits)
    self.stateHashes[self.me] = self.H
    self.sentStateHash = true
    self.phase = PHASE.STATEHASH
    self:_bcast(OP.STATEHASH, { handNo = self.handNo, seat = self.me, H = self.H })
  end

  if self.sentStateHash and self.phase == PHASE.STATEHASH then
    for seat, h in pairs(self.stateHashes) do
      if h ~= self.H then
        return self:_abort(Verify.CODE.STATE, "STATEHASH mismatch with " .. seat .. " (host equivocation)")
      end
    end
    if count(self.stateHashes) >= nSeats then
      self.phase = PHASE.DEAL
      self:_tryVerifyHole()
    end
  end
end

function Client:_tryVerifyHole()
  if self.holeVerified or not self.deckCommits or not self.pendingHole then return end
  for i = 1, #self.pendingHole do
    local rv = self.pendingHole[i]
    if not Verify.card(self.deckCommits[rv.pos + 1], rv.val, rv.pos, rv.nonce) then
      return self:_abort(Verify.CODE.COMMIT, "hole card at pos " .. rv.pos .. " does not open its commitment")
    end
  end
  self.hole = self.pendingHole
  self.holeVerified = true
end

function Client:_tryVerifyReveals()
  if not self.deckCommits then return end
  while #self.pendingReveals > 0 do
    local reveals = table.remove(self.pendingReveals, 1)
    for i = 1, #reveals do
      local rv = reveals[i]
      if not Verify.card(self.deckCommits[rv.pos + 1], rv.val, rv.pos, rv.nonce) then
        self.boardVerified = false
        return self:_abort(Verify.CODE.COMMIT, "community card at pos " .. rv.pos .. " does not open its commitment")
      end
      self.board[#self.board + 1] = { pos = rv.pos, val = rv.val }
    end
  end
end

function Client:_audit(d)
  -- use our witnessed reveals where we have them; fall back to the host's end-of-hand
  -- reveals for any we missed (e.g. a mid-hand reconnect).
  local reveals = {}
  for i = 1, #self.order do
    local seat = self.order[i]
    reveals[seat] = self.reveals[seat] or (d.seedReveals and d.seedReveals[seat])
  end
  local res = Verify.endOfHand({
    handNo = self.handNo, seatOrder = self.order, reveals = reveals,
    seedCommits = self.commits, deckCommits = self.deckCommits,
    cardOpenings = d.openings, S = d.S, stateHashStored = self.H,
  })
  self.auditPassed = res.ok
  if not res.ok then
    local f = res.failures[1]
    return self:_abort(f.code, f.detail)
  end
  self.auditCount = (self.auditCount or 0) + 1     -- hands verified this session
  self.phase = PHASE.DONE
end

function Client:tick() end

ns.Client = Client
return Client
