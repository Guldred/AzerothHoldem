--[[ Ledger.lua — verifiable chip accounting over MANUAL gold trades (pure logic).

  Gold cannot be moved by any 3.3.5a API, so this is NOT a transfer system. It is
  an authoritative record: the host reads a trade window (TRADE_* events,
  GetTargetTradeMoney) in the WoW-coupled layer, calls verifyTrade() to confirm
  the amount matches the requested buy-in, then buyIn() to seat the player. Stacks
  move only via applyHandResult() (which must net to zero — chips are conserved).
  At cash-out the host is instructed to trade the owed amount; cashOut() logs it.
  Final payout remains a documented social-trust assumption (see DESIGN.md).

  Amounts are in copper (WoW's base money unit); 1 chip == 1 copper.
  This module is pure (no WoW API) so the accounting is unit-testable.
]]

local ADDON, ns = ...
local Ledger = {}
Ledger.__index = Ledger

function Ledger.new()
  return setmetatable({ players = {}, order = {}, cashedTotal = 0 }, Ledger)
end

function Ledger:seat(id, name)
  if self.players[id] then error("Ledger:seat: duplicate player " .. tostring(id)) end
  self.players[id] = { id = id, name = name, stack = 0, bought = 0, cashedOut = false, history = {} }
  self.order[#self.order + 1] = id
end

function Ledger:isSeated(id)
  return self.players[id] ~= nil and not self.players[id].cashedOut
end

-- Pure trade check: does the amount actually traded match what was requested?
-- The host calls this with GetTargetTradeMoney() before accepting the buy-in.
function Ledger.verifyTrade(expectedCopper, actualCopper)
  return type(actualCopper) == "number" and type(expectedCopper) == "number"
    and actualCopper == expectedCopper
end

-- Record a verified buy-in trade: the player handed `copper` to the host and
-- receives an equal chip stack.
function Ledger:buyIn(id, copper)
  local p = self.players[id]
  if not p then error("Ledger:buyIn: unknown player " .. tostring(id)) end
  if p.cashedOut then error("Ledger:buyIn: player already cashed out") end
  if type(copper) ~= "number" or copper <= 0 or copper % 1 ~= 0 then
    error("Ledger:buyIn: amount must be a positive integer")
  end
  p.stack = p.stack + copper
  p.bought = p.bought + copper
  p.history[#p.history + 1] = { kind = "buyin", amount = copper }
  return p.stack
end

-- Apply a hand's net per-player chip deltas (winnings minus contributions). The
-- deltas MUST net to zero across the table — a non-zero sum means a chip accounting
-- bug upstream, so we fail loud rather than silently mint or burn chips.
function Ledger:applyHandResult(deltas)
  local sum = 0
  for id, d in pairs(deltas) do
    if not self.players[id] then error("Ledger:applyHandResult: unknown player " .. tostring(id)) end
    if type(d) ~= "number" then error("Ledger:applyHandResult: non-number delta") end
    sum = sum + d
  end
  if sum ~= 0 then
    error("Ledger:applyHandResult: deltas must net to zero (got " .. sum .. ")")
  end
  -- Validate fully BEFORE mutating anything, so a rejected result leaves every
  -- stack untouched (atomic — pairs() order is undefined, so a mid-loop error
  -- must never leave a partially-applied result).
  for id, d in pairs(deltas) do
    if self.players[id].stack + d < 0 then
      error("Ledger:applyHandResult: negative stack for " .. tostring(id))
    end
  end
  for id, d in pairs(deltas) do
    local p = self.players[id]
    p.stack = p.stack + d
    if d ~= 0 then p.history[#p.history + 1] = { kind = "hand", amount = d } end
  end
end

function Ledger:stack(id) return self.players[id].stack end
function Ledger:bought(id) return self.players[id].bought end
function Ledger:net(id) local p = self.players[id]; return p.stack - p.bought end

-- Amount the host owes the player at cash-out (= current stack). Logs it and zeroes
-- the player's stack. The host is then instructed to TRADE this amount (manual).
function Ledger:cashOut(id)
  local p = self.players[id]
  if not p then error("Ledger:cashOut: unknown player " .. tostring(id)) end
  if p.cashedOut then error("Ledger:cashOut: already cashed out") end
  local owed = p.stack
  p.stack = 0
  p.cashedOut = true
  self.cashedTotal = self.cashedTotal + owed
  p.history[#p.history + 1] = { kind = "cashout", amount = owed }
  return owed
end

function Ledger:totalInPlay()
  local t = 0
  for i = 1, #self.order do
    local p = self.players[self.order[i]]
    if not p.cashedOut then t = t + p.stack end
  end
  return t
end

function Ledger:totalBought()
  local t = 0
  for i = 1, #self.order do t = t + self.players[self.order[i]].bought end
  return t
end

-- House invariant: every copper bought in is either still in play or has been
-- cashed out — none created, none destroyed. Returns ok, detail.
function Ledger:reconcile()
  local bought = self:totalBought()
  local accounted = self:totalInPlay() + self.cashedTotal
  if bought == accounted then return true end
  return false, "bought=" .. bought .. " accounted=" .. accounted
end

ns.Ledger = Ledger
return Ledger
