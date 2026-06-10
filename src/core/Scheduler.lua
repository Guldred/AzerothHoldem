--[[ Scheduler.lua — the addon's single OnUpdate heartbeat (3.3.5a has no C_Timer).

  Drives three things every frame:
    * a token-bucket SEND queue that rate-limits outgoing addon messages to ~800
      cps (the client's throttle limit) — ChatThrottleLib-equivalent. If
      ChatThrottleLib IS bundled (libs/), we defer to it instead.
    * periodic tick() callbacks (the Transport's retransmit/dedupe timers).
    * coroutine WORKERS that frame-spread heavy pure-Lua crypto (SHA-256 over the
      52 commitments, Fisher-Yates, Tier-2 modexp) so the client never hitches —
      one bounded slice per frame.

  Only this file and Init touch the WoW OnUpdate/CreateFrame API; everything it
  drives is pure.
]]

local ADDON, ns = ...
local Scheduler = {}

local floor, min = math.floor, math.min

-- throttle (mirrors ChatThrottleLib's defaults)
local MAX_CPS = 800
local MSG_OVERHEAD = 40
local TICK_INTERVAL = 0.1          -- seconds between tick() rounds

local frame
local sendQueue = {}
local tickCallbacks = {}
local workers = {}
local bytesAvail = MAX_CPS
local sinceTick = 0

local function rawSend(m)
  -- already rate-limited here; send directly. (If CTL is present we never enqueue.)
  SendAddonMessage(ns.Const.PREFIX, m.wire, m.channel, m.target)
end

function Scheduler._onUpdate(elapsed)
  -- refill token bucket
  bytesAvail = min(MAX_CPS, bytesAvail + MAX_CPS * elapsed)
  -- drain send queue within budget (FIFO; ALERT-priority items jump the queue at enqueue)
  while sendQueue[1] do
    local m = sendQueue[1]
    local cost = #m.wire + #ns.Const.PREFIX + 1 + MSG_OVERHEAD
    if cost > bytesAvail then break end
    bytesAvail = bytesAvail - cost
    table.remove(sendQueue, 1)
    rawSend(m)
  end
  -- periodic ticks
  sinceTick = sinceTick + elapsed
  if sinceTick >= TICK_INTERVAL then
    sinceTick = 0
    for i = 1, #tickCallbacks do tickCallbacks[i]() end
  end
  -- one crypto worker slice per frame (keeps the main thread responsive)
  if workers[1] then
    local co = workers[1]
    local ok, err = coroutine.resume(co)
    if not ok then
      ns.Log.error("worker error: " .. tostring(err))
      table.remove(workers, 1)
    elseif coroutine.status(co) == "dead" then
      table.remove(workers, 1)
    end
  end
end

function Scheduler.init()
  frame = CreateFrame("Frame", "AzerothHoldemScheduler")
  frame:SetScript("OnUpdate", function(_, elapsed) Scheduler._onUpdate(elapsed) end)
  ns.schedulerFrame = frame
end

-- enqueue an outgoing message (Transport's send callback routes here)
function Scheduler.queueSend(wire, channel, target, prio)
  if ChatThrottleLib then
    ChatThrottleLib:SendAddonMessage(prio or "NORMAL", ns.Const.PREFIX, wire, channel, target)
    return
  end
  local item = { wire = wire, channel = channel, target = target }
  if prio == "ALERT" then table.insert(sendQueue, 1, item) else sendQueue[#sendQueue + 1] = item end
end

function Scheduler.onTick(fn) tickCallbacks[#tickCallbacks + 1] = fn end

-- co: a coroutine that yields periodically; resumed one slice per frame
function Scheduler.runWorker(co) workers[#workers + 1] = co end

function Scheduler.pendingSends() return #sendQueue end

ns.Scheduler = Scheduler
return Scheduler
