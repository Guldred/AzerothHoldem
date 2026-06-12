--[[ Spectator.lua — watch a table without sitting (pure, 100% passive).

  Every gameplay message already rides the shared guild/raid channel at
  tag = tableId, so a spectator simply LISTENS: it mirrors the public state
  (seats, stacks, bets, board, pot, whose turn) for the table window, and —
  because the fairness protocol is public by construction — it independently
  VERIFIES the hand too: community/showdown cards against the deck commitments,
  the players' STATEHASH cross-check against its OWN recomputed hash, and the
  full end-of-hand audit. The only thing a spectator can't see is live holes.

  TRUST MODEL (the channel is hostile): host-authoritative ops are accepted only
  from the dealer (sender == hostName, known at construction), per-seat barrier
  ops only from their own seat — forged frames are DROPPED, never flagged, so a
  troll can neither puppet a counterfeit game nor paint a false CHEAT banner.
  Lost frames (fire-and-forget broadcasts; the repair whispers go to seats only)
  degrade to an explicit "couldn't verify this hand" state — never to a cheat
  accusation, and never silently.

  A spectator NEVER SENDS — not even a CHEAT report (enforcement belongs to the
  seated players; their broadcast reports are mirrored locally). Joining
  mid-hand waits for the next HANDSTART (at most one hand).

  Field names deliberately mirror Client's public state so ns.UI.viewOf renders
  a spectator with the same code path as a seated player.
]]

local ADDON, ns = ...
local Codec, Commit, Verify = ns.Codec, ns.Commit, ns.Verify
local OP, CC = ns.Const.OP, ns.Const

local Spectator = {}
Spectator.__index = Spectator

function Spectator.new(cfg)
  return setmetatable({
    me = cfg.selfName, hostName = cfg.hostName,
    seats = nil, handNo = nil, order = nil,
    board = {}, folded = {}, pot = 0,
    commits = {}, reveals = {}, stateHashes = {}, deckCommits = nil,
    pendingReveals = {}, early = nil,
    S = nil, H = nil, auditPassed = false, aborted = false, cheat = nil,
    spectating = true,                 -- the UI renders a "watching" treatment
  }, Spectator)
end

local function canonical(seats)
  local c = {}
  for i = 1, #seats do c[i] = seats[i] end
  table.sort(c)
  return c
end

-- a PROVEN fairness violation: halt OUR display only (spectators don't
-- broadcast — enforcement is the seated players' job; they run the same checks)
function Spectator:_flag(code, detail)
  if self.aborted then return end
  self.aborted = true
  self.cheat = { code = code, detail = detail }
  if self.onCheat then self.onCheat(code, detail) end
end

function Spectator:_verifyReveals()
  if not self.deckCommits then return end
  while #self.pendingReveals > 0 do
    local reveals = table.remove(self.pendingReveals, 1)
    for i = 1, #reveals do
      local rv = reveals[i]
      if not Verify.card(self.deckCommits[rv.pos + 1], rv.val, rv.pos, rv.nonce) then
        return self:_flag(Verify.CODE.COMMIT,
          "community card at pos " .. rv.pos .. " does not open its commitment")
      end
      self.board[#self.board + 1] = { pos = rv.pos, val = rv.val }
      self.boardVerified = true
    end
  end
end

-- once every seat's seed reveal is witnessed, pin S and H EARLY (like a seated
-- client does) — the STATEHASH cross-check below then ties the players' hashes
-- to the deck WE audit, and the end-of-hand audit leg actually checks something
function Spectator:_tryPin()
  if not self.S and self.order then
    local rList = {}
    for i = 1, #self.order do
      local rv = self.reveals[self.order[i]]
      if not rv then return end
      rList[i] = rv.r
    end
    local ok, S = pcall(Commit.combineSeed, rList)
    if ok then self.S = S end
  end
  if self.S and self.deckCommits and not self.H then
    local ok, H = pcall(Commit.stateHash, self.handNo, self.S, self.deckCommits)
    if ok then
      self.H = H
      self.phase = "deal"                      -- viewOf: the cross-check gate passed…
      for seat, h in pairs(self.stateHashes) do
        if h ~= self.H then
          return self:_flag(Verify.CODE.STATE,
            "player " .. seat .. " attested a different deck than the one dealt")
        end
      end
    end
  end
end

-- per-seat barrier contribution (only ever from its own seat — see onMessage —
-- and only for a seat actually in this hand, the replay path included)
function Spectator:_barrierOp(op, d)
  if self.seats then
    local member = false
    for i = 1, #self.seats do if self.seats[i] == d.seat then member = true break end end
    if not member then return end
  end
  if op == OP.SEEDCMT then
    self.commits[d.seat] = d.commit
  elseif op == OP.SEEDREVEAL then
    if self.commits[d.seat] and not Commit.verifySeed(self.commits[d.seat], d.r, d.salt) then
      return self:_flag(Verify.CODE.SEED, "seat " .. d.seat .. " seed does not open its commitment")
    end
    self.reveals[d.seat] = { r = d.r, salt = d.salt }
    self:_tryPin()
  elseif op == OP.STATEHASH then
    self.stateHashes[d.seat] = d.H
    if self.H and d.H ~= self.H then
      return self:_flag(Verify.CODE.STATE,
        "player " .. d.seat .. " attested a different deck than the one dealt")
    end
  end
end

function Spectator:onMessage(sender, payload, channel)
  if self.aborted then return end
  local op, d = Codec.decode(payload)
  if d == nil then return end

  -- a seated player's violation report covers what only participants can see
  -- (e.g. a hole card failing its commitment): mirror it locally, send nothing.
  -- Exempt from every gate below — it may carry any handNo, incl. 0.
  if op == OP.CHEAT then
    return self:_flag(d.code or "CHEAT", "reported by " .. tostring(sender) .. ": " .. (d.detail or ""))
  end

  -- the hostile-channel gates: host-authoritative ops only from the dealer;
  -- per-seat barrier ops only from their own seat. Forged frames are DROPPED
  -- (never flagged — a troll must not be able to paint a false CHEAT banner).
  local barrier = (op == OP.SEEDCMT or op == OP.SEEDREVEAL or op == OP.STATEHASH)
  if barrier then
    if sender ~= d.seat then return end
  elseif sender ~= self.hostName then
    return
  end

  -- mid-hand arrivals wait for the next hand; per-hand hygiene mirrors Client:
  -- stale-hand frames are dropped, next-hand barrier frames racing ahead of the
  -- HANDSTART are buffered and replayed (dropping them caused false audit
  -- failures — a missing commit is indistinguishable from a withheld one)
  if op ~= OP.HANDSTART and (not self.seats
      or (self.handNo and d.handNo and d.handNo ~= self.handNo)) then
    if d.handNo and (not self.handNo or d.handNo > self.handNo) and barrier then
      self.early = self.early or {}
      if #self.early < 32 then self.early[#self.early + 1] = { op = op, d = d } end
    end
    return
  end

  if op == OP.HANDSTART then
    if self.seats and self.handNo == d.handNo then return end
    if self.handNo and d.handNo and d.handNo < self.handNo then return end
    self.handNo, self.seats, self.order = d.handNo, d.seats, canonical(d.seats)
    self.sb, self.bb = d.sb, d.bb
    self.stacks = d.stacks
    self.board, self.folded, self.pot, self.bets = {}, {}, 0, nil
    self.commits, self.reveals, self.stateHashes = {}, {}, {}
    self.deckCommits, self.pendingReveals = nil, {}
    self.S, self.H, self.auditPassed, self.unverified = nil, nil, false, nil
    self.deltas, self.showdown, self.toActSeat = nil, nil, nil
    self.boardVerified, self.phase = false, "commit"
    -- replay this hand's barrier frames that raced ahead of the HANDSTART
    local early = self.early
    self.early = nil
    if early then
      for i = 1, #early do
        if early[i].d.handNo == self.handNo then self:_barrierOp(early[i].op, early[i].d) end
      end
    end

  elseif barrier then
    self:_barrierOp(op, d)        -- membership of THIS hand enforced inside

  elseif op == OP.DECKCMT then
    self.deckCommits = d.commits
    self:_tryPin()
    self:_verifyReveals()

  elseif op == OP.REVEAL then
    self.pendingReveals[#self.pendingReveals + 1] = d.reveals
    self:_verifyReveals()

  elseif op == OP.BOARD then
    -- display fallback: plain card values ride alongside every REVEAL — if the
    -- (large, fire-and-forget) DECKCMT broadcast was lost, the watcher still
    -- SEES the game; it just can't certify it (-> "unverified" below)
    if not self.deckCommits and d.cards then
      for i = 1, #d.cards do
        self.board[#self.board + 1] = { pos = -1, val = d.cards[i] }
      end
    end

  elseif op == OP.BET_TURN then
    self.toActSeat = d.seat
    if d.pot then self.pot = d.pot end
    if d.timeout then self.turnTimeout = d.timeout end
    if d.stacks and self.seats then
      self.stacks, self.bets = self.stacks or {}, {}
      for i = 1, #self.seats do
        if d.stacks[i] then self.stacks[self.seats[i]] = d.stacks[i] end
        self.bets[self.seats[i]] = d.bets and d.bets[i] or 0
      end
    end

  elseif op == OP.ACTED then
    if d.action == CC.ACTION.FOLD then self.folded[d.seat] = true end

  elseif op == OP.SHOWDOWN then
    if self.deckCommits then
      for i = 1, #d.reveals do
        local rv = d.reveals[i]
        if not Verify.card(self.deckCommits[rv.pos + 1], rv.val, rv.pos, rv.nonce) then
          return self:_flag(Verify.CODE.COMMIT,
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
    self.toActSeat = nil
    if self.stacks then
      for seat, dlt in pairs(d.deltas) do self.stacks[seat] = (self.stacks[seat] or 0) + dlt end
    end

  elseif op == OP.ENDREVEAL then
    -- the full public audit, exactly as a player runs it. Missing INPUTS (a lost
    -- commit/deck broadcast we passively can't re-request) mean "couldn't verify
    -- this hand" — an explicit, visible state. Only a genuine MISMATCH is cheat.
    self.phase = "done"
    local reveals, complete = {}, true
    for i = 1, #self.order do
      local seat = self.order[i]
      reveals[seat] = self.reveals[seat] or (d.seedReveals and d.seedReveals[seat])
      if not (reveals[seat] and self.commits[seat]) then complete = false end
    end
    self:_tryPin()
    if complete and self.S and self.deckCommits then
      local res = Verify.endOfHand({
        handNo = self.handNo, seatOrder = self.order, reveals = reveals,
        seedCommits = self.commits, deckCommits = self.deckCommits,
        cardOpenings = d.openings, S = d.S, stateHashStored = self.H,
      })
      if res.ok then
        self.auditPassed = true
        self.auditCount = (self.auditCount or 0) + 1
      else
        local f = res.failures[1]
        if f.code == Verify.CODE.INPUT then self.unverified = true
        else return self:_flag(f.code, f.detail) end
      end
    else
      self.unverified = true       -- missed a broadcast: visible, never accusatory
    end
    if self.unverified then        -- runs of these are themselves worth noticing
      self.unverifiedCount = (self.unverifiedCount or 0) + 1
    end
  end
end

function Spectator:tick() end

ns.Spectator = Spectator
return Spectator
