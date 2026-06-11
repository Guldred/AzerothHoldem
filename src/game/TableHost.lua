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
    pendingSeat = {}, pendingLeave = {},
  }, TableHost)
  self:_seat(cfg.tableId)                       -- the dealer plays too
  return self
end

function TableHost:_seat(player)
  if self.ledger:isSeated(player) or #self.order >= self.seatMax then return false end
  self.ledger:seat(player)
  self.ledger:buyIn(player, self.cfg.defaultStack or 1000)
  self.order[#self.order + 1] = player
  return true
end

function TableHost:_unseat(player)
  if not self.ledger:isSeated(player) then return end
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
  self.cfg.postControl(Codec.encode(OP.SEAT, { tableId = self.id, players = self:_seatList() }), self.broadcast)
  self:advertise(true)    -- keep the lobby's seat counts + player names fresh (rate-limited)
end

-- onDemand: a floor PING / seating change asked for an immediate ad (rate-limited
-- so a burst can't make the host spam the channel).
function TableHost:advertise(onDemand)
  if onDemand and self._lastAdTick and (self.ticks - self._lastAdTick) < 2 then return end
  self._lastAdTick = self.ticks
  self.cfg.postControl(Codec.encode(OP.TABLE, {
    tableId = self.id, name = self.name, sb = self.cfg.sb, bb = self.cfg.bb,
    variant = self.cfg.variant or "texas", taken = #self.order, seatMax = self.seatMax, open = self.open,
    players = self:_seatList(),                    -- who is seated (shown in the lobby)
    ver = self.cfg.version,                        -- exact-release gate for joiners
  }), self.broadcast)
end

-- ---- seating requests (routed here by the Casino from tag-0 control) -------
function TableHost:onJoin(player)
  if not self.open then return end
  self.pendingLeave[player] = nil   -- a rejoin cancels a not-yet-processed leave (else
                                    -- the stale flag would kick them at the next hand)
  if self.host then self.pendingSeat[player] = true     -- mid-hand: seat for next hand
  else self:_seat(player) end
  self:_broadcastSeats()
end

function TableHost:onLeave(player)
  self.pendingSeat[player] = nil    -- leaving cancels a not-yet-processed join
  if not self.ledger:isSeated(player) then return end
  if self.host then
    self.pendingLeave[player] = true               -- remove from the table next hand
    local ph = self.host.phase
    if ph == "commit" or ph == "reveal" or ph == "statehash" then
      -- left during the pre-deal handshake: the joint seed assumed this seat, so
      -- abandon the in-progress hand and restart without them.
      self.host = nil
      self.cfg.registerHost(self.id, nil)
      self:_unseat(player)
      self.restTicks = 0
    else
      -- left during betting/showdown: fold them out immediately (now, or the moment
      -- their turn comes) so the table never freezes waiting on an empty chair.
      self.host:markAbsent(player)
    end
  else
    self:_unseat(player)
  end
  self:_broadcastSeats()
end

-- ---- the hand loop ---------------------------------------------------------
function TableHost:startHand()
  -- a DONE host is kept around so the table keeps showing the result (winner,
  -- showdown cards) through the rest period; it doesn't block the next hand
  if self.host and self.host.phase ~= Host.PHASE.DONE then return false, "hand in progress" end
  for p in pairs(self.pendingLeave) do self:_unseat(p) end; self.pendingLeave = {}
  for p in pairs(self.pendingSeat) do self:_seat(p) end; self.pendingSeat = {}
  for i = #self.order, 1, -1 do                            -- bust out anyone at 0 chips
    if self.ledger:stack(self.order[i]) == 0 then self:_unseat(self.order[i]) end
  end
  if #self.order < 2 then return false, "need 2+ players" end
  self:_broadcastSeats()                            -- announce final seating so new joiners spawn their client

  if self.buttonIdx > #self.order then self.buttonIdx = 1 end
  local button = self.order[self.buttonIdx]
  local stacks, startStacks = {}, {}
  for _, p in ipairs(self.order) do stacks[p] = self.ledger:stack(p); startStacks[p] = stacks[p] end
  self.startStacks = startStacks
  self.handSeats = self:_seatList()
  self.handNo = self.handNo + 1

  self.host = Host.new({
    transport = self.cfg.sessionTransport(), selfName = self.id,
    seats = self.handSeats, stacks = stacks, buttonSeat = button,
    sb = self.cfg.sb, bb = self.cfg.bb, handNo = self.handNo,
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

function TableHost:tick(dt)
  self.ticks = self.ticks + (dt or 1)
  if self.host then self.host:tick() end            -- drive the live hand's deadlines/timeouts
  if self.open and self.ticks % self.adInterval == 0 then self:advertise() end
  if self.restTicks > 0 then self.restTicks = self.restTicks - 1 end
  if self.open and (not self.host or self.host.phase == Host.PHASE.DONE)
      and self.restTicks == 0 and #self.order >= 2 then
    self:startHand()
  end
end

ns.TableHost = TableHost
return TableHost
