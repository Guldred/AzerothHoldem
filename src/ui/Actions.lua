--[[ Actions.lua — the play controls, embedded in the table window's bottom strip
  (one window during play): Fold / Check / Call (with amount) / Bet|Raise-to, the
  amount box, and Min / Pot / All-in quick-fills, all in one row.

  The controls are ALWAYS visible with the table but inactive (disabled + dimmed)
  when it isn't your turn — nothing pops in and out. Amounts are bet/raise-TO
  totals (what the Rules engine validates), clamped to the legal [min,max] before
  sending; a host refusal is surfaced in chat and the prompt comes back via the
  host's re-sent BET_TURN. ]]

local ADDON, ns = ...
local W = ns.W
local COL = W.COL
local A = ns.Const.ACTION
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local bar

local function session() return ns.casino or ns.session end

local function act(action, amount)
  local s = session()
  if not s or not s.humanAct then return end
  local ok, err = s:humanAct(action, amount)
  if not ok and ns.Log then ns.Log.error("Can't " .. action .. ": " .. tostring(err)) end
end

-- the raise/bet amount: the box's number, defaulted to the minimum and clamped to
-- the legal range (so empty boxes and typos can't send an illegal amount)
local function amountVal()
  local v = tonumber(bar.amount:GetText())
  if not v then v = bar._min end
  if bar._min and v and v < bar._min then v = bar._min end
  if bar._max and v and v > bar._max then v = bar._max end
  return v
end

local function build()
  -- live inside the table window's control strip; fall back to a floating panel
  -- only if the strip is unavailable (keeps the file order-independent)
  local host = ns.UI.controlStrip
  if host then
    bar = CreateFrame("Frame", nil, host)
    bar:SetAllPoints(host)
  else
    bar = W.panel(UIParent, 430, 96)
    bar:SetPoint("BOTTOM", 0, 150)
  end

  bar.fold = W.button(bar, "Fold", function() act(A.FOLD) end)
  bar.fold:SetWidth(64); bar.fold:SetHeight(24); bar.fold:SetPoint("BOTTOMLEFT", 6, 10)
  bar.check = W.button(bar, "Check", function() act(A.CHECK) end)
  bar.check:SetWidth(92); bar.check:SetHeight(24); bar.check:SetPoint("LEFT", bar.fold, "RIGHT", 4, 0)
  bar.call = W.button(bar, "Call", function() act(A.CALL) end)
  bar.call:SetWidth(92); bar.call:SetHeight(24); bar.call:SetPoint("LEFT", bar.fold, "RIGHT", 4, 0)
  bar.raise = W.button(bar, "Raise to", function()
    act((bar._opener and A.BET) or A.RAISE, amountVal())
  end)
  bar.raise:SetWidth(80); bar.raise:SetHeight(24); bar.raise:SetPoint("LEFT", bar.check, "RIGHT", 4, 0)
  bar.amount = W.editbox(bar, 56); bar.amount:SetPoint("LEFT", bar.raise, "RIGHT", 8, 0)

  local function quick(label, fn)
    return W.button(bar, label, function()
      local v = fn()
      if v and bar.amount.SetText then bar.amount:SetText(tostring(v)) end
    end)
  end
  bar.qMin = quick("Min", function() return bar._min end)
  bar.qMin:SetWidth(40); bar.qMin:SetHeight(20); bar.qMin:SetPoint("LEFT", bar.amount, "RIGHT", 10, 0)
  bar.qPot = quick("Pot", function()
    local v = bar._pot
    if v and bar._min and v < bar._min then v = bar._min end
    if v and bar._max and v > bar._max then v = bar._max end
    return v
  end)
  bar.qPot:SetWidth(40); bar.qPot:SetHeight(20); bar.qPot:SetPoint("LEFT", bar.qMin, "RIGHT", 3, 0)
  bar.qMax = quick("All-in", function() return bar._max end)
  bar.qMax:SetWidth(44); bar.qMax:SetHeight(20); bar.qMax:SetPoint("LEFT", bar.qPot, "RIGHT", 3, 0)

  bar._buttons = { bar.fold, bar.check, bar.call, bar.raise, bar.qMin, bar.qPot, bar.qMax }
  ns.UI.actionBar = bar
end

-- the controls stay visible with the table; this flips them between active
-- (your turn: clickable, full brightness) and inactive (disabled + dimmed)
local function setActive(on)
  bar._active = on
  if bar.SetAlpha then bar:SetAlpha(on and 1 or 0.4) end
  for i = 1, #bar._buttons do
    local b = bar._buttons[i]
    if on then if b.Enable then b:Enable() end
    else if b.Disable then b:Disable() end end
  end
  if bar.amount.EnableMouse then bar.amount:EnableMouse(on) end
  if not on and bar.amount.ClearFocus then bar.amount:ClearFocus() end
end

local function refresh(v)
  if not bar then return end

  -- surface a host refusal exactly once (the prompt itself comes back via re-BET_TURN)
  if v and v.refused and v.refused ~= bar._shownRefuse then
    bar._shownRefuse = v.refused
    if ns.Log then ns.Log.error("Action refused: " .. tostring(v.refused) .. " — try again.") end
  end

  if not (v and v.myTurn and not v.aborted) then setActive(false); bar._lastTurn = false; return end
  setActive(true)
  local opener = (v.toCall or 0) == 0
  bar._opener = opener
  bar._min = opener and v.minBet or v.minRaise
  bar._max = opener and v.maxBet or v.maxRaise
  bar._pot = v.pot

  if v.canCheck then bar.check:Show(); bar.call:Hide()
  else bar.check:Hide(); bar.call:Show(); bar.call:SetText("Call " .. W.commas(v.toCall or 0)) end
  -- no legal bet/raise range (e.g. facing an all-in): grey the raise controls
  if bar._min then
    if bar.raise.Enable then bar.raise:Enable() end
  else
    if bar.raise.Disable then bar.raise:Disable() end
  end
  bar.raise:SetText(opener and "Bet" or "Raise to")

  -- quick-fills only make sense with a known value
  if not bar._min and bar.qMin.Disable then bar.qMin:Disable() end
  if not bar._pot and bar.qPot.Disable then bar.qPot:Disable() end
  if not bar._max and bar.qMax.Disable then bar.qMax:Disable() end

  -- prime the amount box once per turn with the minimum
  if not bar._lastTurn and bar._min and bar.amount.SetText then bar.amount:SetText(tostring(bar._min)) end
  bar._lastTurn = true
end

build()
setActive(false)
ns.UI.register(refresh)
return ns.UI.actionBar
