--[[ TableHost.lua — a dealer running ONE table across many hands (pure).

  This is the multi-hand substructure a casino needs (the lobby is the easy part):
    * persistent seating across hands (the host is itself a seated player),
    * a Ledger so stacks CARRY OVER hand-to-hand (this is what makes even dummy
      currency meaningful — each hand isn't reset to a flat stack),
    * button rotation between hands,
    * players joining/leaving BETWEEN hands, and busting out at 0 chips,
    * each hand run by the proven per-hand Host engine, seeded with current seats.

  Control messages (TABLE ad, SEAT list) are sent at routing tag 0 (everyone hears);
  the per-hand Host's gameplay rides at tag = this table's id (the host's name),
  routed only to that table's participants. Transport/clock are injected.
]]

local ADDON, ns = ...
local Codec, Ledger, Host = ns.Codec, ns.Ledger, ns.Host
local OP = ns.Const.OP

local TableHost = {}
TableHost.__index = TableHost

-- cfg = { tableId(=host name), name, sb, bb, variant, seatMax, defaultStack, broadcast,
--   postControl=fn(payload,channel), sessionTransport=fn()->tagged transport,
--   registerHost=fn(tableId, host|nil), entropy=fn()->{r,salt}, nonces=fn()->{52},
--   onCheat, policy, human, adInterval, restTicks }
function TableHost.new(cfg)
  local self = setmetatable({
    id = cfg.tableId, cfg = cfg, name = cfg.name or cfg.tableId,
    broadcast = cfg.broadcast or "RAID", seatMax = cfg.seatMax or 9,
    ledger = Ledger.new(), order = {}, open = true,
    ticks = 0, adInterval = cfg.adInterval or 5, restTicks = 0, restDelay = cfg.restTicks or 2,
    buttonIdx = 1, host = nil, handNo = 0,
    -- the FIRST hand is dealt when the host says so (startGame) — they may want to
    -- wait for more players; afterwards hands continue automatically. Tests pass
    -- autoStart=true to keep driving tables without UI interaction.
    started = cfg.autoStart or false,
    pendingSeat = {}, pendingLeave = {}, lastStack = {}, sitOut = {},
    -- sit&go tournament: equal starting stacks, blinds escalate per level, busted
    -- players are ELIMINATED with a placing, last one standing wins, no late joins.
    tourney = cfg.tourney, level = 0, placings = cfg.tourney and {} or nil,
  }, TableHost)
  self:_seat(cfg.tableId)                       -- the dealer plays too
  return self
end

function TableHost:_seat(player)
  if self.ledger:isSeated(player) or #self.order >= self.seatMax then return false end
  self.ledger:seat(player)
  -- a RETURNING player gets the stack they left with, not a fresh buy-in — leaving
  -- and re-sitting must never reset chips (no "refill to default" by standing up).
  -- Busted players (left at 0) do buy in fresh, or they could never play again.
  local back = self.lastStack[player]
  if self.tourney then back = nil end           -- sit&go: everyone starts EQUAL, always
  self.ledger:buyIn(player, (back and back > 0) and back
    or (self.tourney and self.tourney.stack) or (self.cfg.defaultStack or 1000))
  self.order[#self.order + 1] = player
  return true
end

function TableHost:_unseat(player)
  if not self.ledger:isSeated(player) then return end
  self.sitOut[player] = nil
  self.lastStack[player] = self.ledger:stack(player)   -- remembered for a re-sit
  self.ledger:cashOut(player)
  for i = #self.order, 1, -1 do if self.order[i] == player then table.remove(self.order, i) end end
  if self.buttonIdx > #self.order then self.buttonIdx = 1 end
end

function TableHost:_seatList()
  local s = {}
  for i = 1, #self.order do s[i] = self.order[i] end
  return s
end

function TableHost:_broadcastSeats()
  self.cfg.postControl(Codec.encode(OP.SEAT, {
    tableId = self.id, players = self:_seatList(), sitout = self.sitOut,
  }), self.broadcast)
  self:advertise(true)    -- keep the lobby's seat counts + player names fresh (rate-limited)
end

-- a seated player toggles sitting out: they keep their seat and stack but are not
-- dealt into hands (takes effect at the next deal; a live hand plays out normally).
-- Mid-hand joiners (still in pendingSeat) count too — dropping their request after
-- the UI already said "sitting out" dealt them in against their will.
-- The dealer cannot sit out — the protocol needs its seed contribution; hosts Pause.
function TableHost:onSitOut(player, away)
  if self.tourney then                        -- a tournament seat is play-or-forfeit;
    self:_broadcastSeats()                    -- the SEAT echo resets the client's
    return                                    -- optimistic "sitting out" flag
  end
  if player == self.id then return end
  if not (self.ledger:isSeated(player) or self.pendingSeat[player]) then return end
  self.sitOut[player] = away and true or nil
  self:_broadcastSeats()
end

-- onDemand: a floor PING / seating change asked for an immediate ad (rate-limited
-- so a burst can't make the host spam the channel).
function TableHost:advertise(onDemand)
  if onDemand and self._lastAdTick and (self.ticks - self._lastAdTick) < 2 then return end
  self._lastAdTick = self.ticks
  local sb, bb = self:currentBlinds()
  self.cfg.postControl(Codec.encode(OP.TABLE, {
    tableId = self.id, name = self.name, sb = sb, bb = bb,
    variant = self.cfg.variant or "texas", taken = #self.order, seatMax = self.seatMax, open = self.open,
    players = self:_seatList(),                    -- who is seated (shown in the lobby)
    ver = self.cfg.version,                        -- exact-release gate for joiners
    paused = self.paused,                          -- break status (shown to everyone)
    tourney = self.tourney and true or false,      -- sit&go listing
    started = self.started,                        -- a running sit&go seats nobody new
  }), self.broadcast)
end

-- can this table seat a newcomer right now? (a RUNNING sit&go cannot — players
-- who busted out of it must not re-enter with a fresh stack)
function TableHost:joinable()
  if not self.open then return false, "table closed" end
  -- a Sit&Go locks its field once it is truly underway (auto-start tables waiting
  -- for their first opponent are still open)
  if self.tourney and self.started and (self.handNo > 0 or #self.order >= 2) then
    return false, "that Sit & Go is already running"
  end
  return true
end

-- ---- seating requests (routed here by the Casino from tag-0 control) -------
function TableHost:onJoin(player)
  if not self:joinable() then return end
  self.pendingLeave[player] = nil   -- a rejoin cancels a not-yet-processed leave (else
                                    -- the stale flag would kick them at the next hand)
  if self.host then self.pendingSeat[player] = true     -- mid-hand: seat for next hand
  else self:_seat(player) end
  self:_broadcastSeats()
end

function TableHost:onLeave(player)
  self.pendingSeat[player] = nil    -- leaving cancels a not-yet-processed join
  self.sitOut[player] = nil         -- (incl. a sit-out flag noted while still pending)
  if not self.ledger:isSeated(player) then return end
  -- a live hand only matters if the leaver is actually IN it — a sitting-out
  -- player (seated, not dealt) walking away must not tear down everyone else's
  -- in-flight handshake or get folded into a hand they were never part of.
  local inHand = false
  if self.host then
    for i = 1, #self.host.seats do
      if self.host.seats[i] == player then inHand = true break end
    end
  end
  if inHand and self.host.phase ~= Host.PHASE.DONE then
    self.pendingLeave[player] = true               -- remove from the table next hand
    local ph = self.host.phase
    if ph == "commit" or ph == "reveal" or ph == "statehash" then
      -- left during the pre-deal handshake: the joint seed assumed this seat, so
      -- abandon the in-progress hand and restart without them.
      self.host = nil
      self.cfg.registerHost(self.id, nil)
      self:_tourneyForfeit(player)
      self:_unseat(player)
      self.restTicks = 0
    else
      -- left during betting/showdown: fold them out immediately (now, or the moment
      -- their turn comes) so the table never freezes waiting on an empty chair.
      self.host:markAbsent(player)
    end
  else
    self:_tourneyForfeit(player)
    self:_unseat(player)
  end
  self:_tourneyCheckEnd()
  self:_broadcastSeats()
end

-- ---- the hand loop ---------------------------------------------------------
function TableHost:startHand()
  -- a DONE host is kept around so the table keeps showing the result (winner,
  -- showdown cards) through the rest period; it doesn't block the next hand
  if self.host and self.host.phase ~= Host.PHASE.DONE then return false, "hand in progress" end
  for p in pairs(self.pendingLeave) do self:_tourneyForfeit(p); self:_unseat(p) end
  self.pendingLeave = {}
  for p in pairs(self.pendingSeat) do self:_seat(p) end; self.pendingSeat = {}
  for i = #self.order, 1, -1 do                            -- bust out anyone at 0 chips
    if self.ledger:stack(self.order[i]) == 0 then self:_unseat(self.order[i]) end
  end
  -- sitting-out players keep their seats/stacks but are not dealt in
  local active = {}
  for i = 1, #self.order do
    local p = self.order[i]
    if not self.sitOut[p] then active[#active + 1] = p end
  end
  if #active < 2 then return false, "need 2+ players" end
  self:_broadcastSeats()                            -- announce final seating so new joiners spawn their client

  if self.buttonIdx > #self.order then self.buttonIdx = 1 end
  for _ = 1, #self.order do                         -- the button skips sitting-out seats
    if not self.sitOut[self.order[self.buttonIdx]] then break end
    self.buttonIdx = (self.buttonIdx % #self.order) + 1
  end
  local button = self.order[self.buttonIdx]
  local stacks, startStacks = {}, {}
  for _, p in ipairs(active) do stacks[p] = self.ledger:stack(p); startStacks[p] = stacks[p] end
  self.startStacks = startStacks
  self.handSeats = active
  self.handNo = self.handNo + 1

  local sb, bb = self:currentBlinds()
  if self.tourney then
    local lvl = math.floor((self.completedHands or 0) / (self.tourney.handsPerLevel or 8))
    if lvl > 12 then lvl = 12 end               -- 2^12: blinds dwarf any stack long before
    if lvl ~= self.level then
      self.level = lvl
      sb, bb = self:currentBlinds()
      self:_tourneyEvent({ kind = "level", level = lvl + 1, sb = sb, bb = bb })
    end
  end

  self.host = Host.new({
    transport = self.cfg.sessionTransport(), selfName = self.id,
    seats = self.handSeats, stacks = stacks, buttonSeat = button,
    sb = sb, bb = bb, handNo = self.handNo,
    entropy = self.cfg.entropy(), nonces = self.cfg.nonces(),
    broadcast = self.broadcast, onCheat = self.cfg.onCheat,
    policy = self.cfg.policy, human = self.cfg.human, turnTimeout = self.cfg.turnTimeout,
    onComplete = function(h) self:_onHandComplete(h) end,
  })
  self.cfg.registerHost(self.id, self.host)                -- route tag=id gameplay to this hand
  self.host:start()
  return true
end

function TableHost:_onHandComplete(h)
  local deltas = {}
  for _, p in ipairs(self.handSeats) do
    deltas[p] = h.dealer.rules.seats[p].stack - self.startStacks[p]
  end
  self.ledger:applyHandResult(deltas)                      -- carry stacks to next hand
  self.completedHands = (self.completedHands or 0) + 1
  if self.tourney then self:_tourneyEliminations() end
  self.buttonIdx = self.buttonIdx + 1                      -- rotate the button
  -- keep self.host (phase DONE, fully inert) so the host's table window keeps
  -- showing the finished hand through the rest period instead of vanishing;
  -- startHand replaces it. Inbound routing for the dead hand is cleared though.
  self.cfg.registerHost(self.id, nil)
  self.restTicks = self.restDelay
  self:_broadcastSeats()
end

-- the human/host commits an action on the dealer's own turn (slash/UI)
function TableHost:humanAct(action, amount)
  if self.host then return self.host:humanAct(action, amount) end
  return false, "no hand in progress"
end

function TableHost:stack(player) return self.ledger:isSeated(player) and self.ledger:stack(player) or nil end

-- stop the table: no more ads, joins, or new hands (a live hand finishes first).
-- The final open=false ad makes every lobby drop the listing immediately.
function TableHost:close()
  self.open = false
  self:advertise()
end

-- after close(), once no hand is live: release every seat (the empty SEAT broadcast
-- frees the seated players' clients back to the lobby)
function TableHost:disband()
  for i = #self.order, 1, -1 do self:_unseat(self.order[i]) end
  self:_broadcastSeats()
end

-- the host opens play: deals the first hand now (if 2+ are seated) and lets
-- subsequent hands continue automatically
function TableHost:startGame()
  -- a solo start ARMS the table (it deals the moment an opponent sits); a Sit&Go
  -- armed this way stays joinable — joinable() only locks once a field exists,
  -- so a premature click can never brick the tournament.
  self.started = true
  if #self.order < 2 then return false, "need 2+ players" end
  if self.host and self.host.phase ~= Host.PHASE.DONE then return false, "hand in progress" end
  return self:startHand()
end

-- current blinds: base for cash tables; base * 2^level for a running sit&go
function TableHost:currentBlinds()
  if not self.tourney then return self.cfg.sb, self.cfg.bb end
  local m = 2 ^ (self.level or 0)
  return math.floor(self.cfg.sb * m), math.floor(self.cfg.bb * m)
end

-- announce sit&go progress to the floor AND to the host's own screen (a host
-- never hears its own broadcasts)
function TableHost:_tourneyEvent(ev)
  ev.tableId = self.id
  self.cfg.postControl(Codec.encode(OP.TOURNEY, ev), self.broadcast)
  if self.cfg.onTourney then self.cfg.onTourney(ev) end
end

-- a runner LEAVING (or being watchdog-removed from) a running Sit&Go forfeits:
-- they get the next placing and an "out" announcement before the unseat. Their
-- remaining chips leave play (a tournament settles by PLACINGS, never cashouts).
function TableHost:_tourneyForfeit(player)
  if not (self.tourney and self.started) or self.tourneyOver then return end
  if not self.ledger:isSeated(player) then return end
  local place = #self.order
  self.placings[place] = player
  self.lastStack[player] = nil
  self:_tourneyEvent({ kind = "out", player = player, place = place })
end

-- one survivor (however the others left: busted, forfeited, or timed out) ends it
function TableHost:_tourneyCheckEnd()
  if not (self.tourney and self.started) or self.tourneyOver then return end
  if #self.order == 1 then
    local w = self.order[1]
    self.placings[1] = w
    self.tourneyOver = true
    self:_tourneyEvent({ kind = "end", winner = w })
  end
end

-- after a hand: bust-outs become ELIMINATIONS (placing = players still in when
-- they fell; the shorter start-of-hand stack busts first on a double knockout),
-- and one survivor means the Sit & Go is over.
function TableHost:_tourneyEliminations()
  local busted = {}
  for _, p in ipairs(self.handSeats) do
    if self.ledger:isSeated(p) and self.ledger:stack(p) == 0 then busted[#busted + 1] = p end
  end
  local ss = self.startStacks
  table.sort(busted, function(a, b) return (ss[a] or 0) < (ss[b] or 0) end)
  for _, p in ipairs(busted) do
    local place = #self.order
    self.placings[place] = p
    self:_unseat(p)
    self.lastStack[p] = nil                     -- eliminated: no buy-back stack memory
    self:_tourneyEvent({ kind = "out", player = p, place = place })
  end
  self:_tourneyCheckEnd()
end

-- break time: while paused no NEW hand is dealt, and the live hand's turn CLOCK
-- stops (a break means no time pressure — nobody gets auto-folded during it; the
-- hand can still be played out by willing players). Resuming restarts the clock
-- fresh for whoever is to act. The state rides the table ad so every player and
-- the lobby see the break immediately.
function TableHost:setPaused(p)
  self.paused = p and true or false
  if not self.paused then
    if self.host and self.host.phase == Host.PHASE.BETTING then
      self.host.turnTicks = 0     -- back from the break: full time to decide
    end
    self.handshakeTicks = 0       -- the handshake watchdog restarts fresh too
  end
  self:advertise()
  return self.paused
end

-- pre-deal handshake watchdog: the commit/reveal/statehash barriers are collect-ALL,
-- so one player missing the HANDSTART (loading screen, brief dc — typically right
-- after a break) used to wedge the table forever. No money has moved pre-deal, so
-- after `handshakeTimeout` ticks the hand is abandoned and redealt; a seat that
-- stalls the handshake twice in a row is unseated (they re-sit when they're back).
-- The timeout must leave room for the in-protocol repairs to land first (the
-- host's statehash-deadline resend fires at tick 20, the RESYNC heal needs a
-- round trip) — hence the 45-tick default, NOT 20. Frozen while paused: a break
-- means no pressure on the handshake either, and pausing is the host's natural
-- reaction to a visibly stalled deal.
function TableHost:_handshakeWatchdog()
  local ph = self.host and self.host.phase
  if not (ph == "commit" or ph == "reveal" or ph == "statehash") then
    self.handshakeTicks = 0
    -- a handshake genuinely completed (not our own abandon parked at DONE): clean slate
    if ph and not self.host.abandonedHandshake then self.handshakeStrikes = nil end
    return
  end
  if self.paused then return end
  self.handshakeTicks = (self.handshakeTicks or 0) + 1
  if self.handshakeTicks < (self.cfg.handshakeTimeout or 45) then return end
  self.handshakeTicks = 0
  local h = self.host
  local strikes = self.handshakeStrikes or {}
  self.handshakeStrikes = {}
  for i = 1, #h.seats do
    local seat = h.seats[i]
    if not (h.commits[seat] and (ph == "commit" or h.reveals[seat])
        and (ph ~= "statehash" or h.stateHashes[seat])) then
      if strikes[seat] then                            -- second stall in a row: let them go
        self:_tourneyForfeit(seat)
        self:_unseat(seat)
      else self.handshakeStrikes[seat] = true end
    end
  end
  -- abandon: no stacks changed pre-deal. The dead Host object is kept (inert at
  -- DONE) so the dealer's table window survives until the redeal — clearing it
  -- made activeSession() nil and the whole window (Pause button included) vanish.
  h.abandonedHandshake = true
  h.phase = Host.PHASE.DONE
  self.cfg.registerHost(self.id, nil)
  self.restTicks = self.restDelay
  self:_tourneyCheckEnd()
  self:_broadcastSeats()
end

-- a cheat report that arrives BETWEEN hands: the end-of-hand audit runs on the
-- clients after HANDEND/ENDREVEAL, when the per-hand host is already unregistered
-- — without this hook the dealer would never see it and the table would happily
-- keep dealing while every honest client sits halted.
function TableHost:onCheatReport(sender, d)
  self.halted = true
  if self.host then                  -- the retained host: flag it so the UI shows HALTED
    self.host.aborted = true
    self.host.cheat = { code = d.code, detail = d.detail }
    self.host.phase = Host.PHASE.ABORT
  end
  if self.cfg.onCheat then
    self.cfg.onCheat(d.code, "reported by " .. tostring(sender) .. ": " .. (d.detail or ""))
  end
end

function TableHost:tick(dt)
  self.ticks = self.ticks + (dt or 1)
  if self.host then self.host:tick(self.paused) end  -- paused = the turn clock is frozen
  self:_handshakeWatchdog()
  if self.open and self.ticks % self.adInterval == 0 then self:advertise() end
  if self.restTicks > 0 then self.restTicks = self.restTicks - 1 end
  if self.tourneyOver then
    if not self.halted then                                -- a halted table stays up
      self.tourneyLinger = (self.tourneyLinger or 10) - 1  -- let the result sink in
    end
    return
  end
  if self.open and self.started and not self.paused and not self.halted
      and (not self.host or self.host.phase == Host.PHASE.DONE)
      and self.restTicks == 0 and #self.order >= 2 then
    self:startHand()
  end
end

ns.TableHost = TableHost
return TableHost
