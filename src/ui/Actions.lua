--[[ Actions.lua — the action bar: Fold / Check / Call (with amount) / Bet|Raise-to,
  an amount box with Min / Pot / All-in quick-fills on their own row (no overlap with
  the main buttons). Appears only on your turn with a gold "YOUR TURN" header.

  Amounts are bet/raise-TO totals (what the Rules engine validates). The amount is
  clamped to the legal [min,max] range before sending, so a typo can't produce an
  illegal intent; if the host still refuses an action, the reason is surfaced in chat
  and the bar re-appears with the host's re-prompt. ]]

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
  bar = W.panel(UIParent, 430, 96)
  bar:SetPoint("BOTTOM", 0, 150)
  bar.header = W.label(bar, "YOUR TURN", "GameFontNormal"); bar.header:SetPoint("TOP", 0, -6)
  bar.header:SetTextColor(rgba(COL.turn))

  -- main row (bottom): Fold | Check/Call | Bet/Raise | amount
  bar.fold = W.button(bar, "Fold", function() act(A.FOLD) end)
  bar.fold:SetWidth(64); bar.fold:SetPoint("BOTTOMLEFT", 10, 10)
  bar.check = W.button(bar, "Check", function() act(A.CHECK) end)
  bar.check:SetWidth(96); bar.check:SetPoint("LEFT", bar.fold, "RIGHT", 4, 0)
  bar.call = W.button(bar, "Call", function() act(A.CALL) end)
  bar.call:SetWidth(96); bar.call:SetPoint("LEFT", bar.fold, "RIGHT", 4, 0)
  bar.raise = W.button(bar, "Raise to", function()
    act((bar._opener and A.BET) or A.RAISE, amountVal())
  end)
  bar.raise:SetWidth(84); bar.raise:SetPoint("LEFT", bar.check, "RIGHT", 4, 0)
  bar.amount = W.editbox(bar, 64); bar.amount:SetPoint("LEFT", bar.raise, "RIGHT", 8, 0)

  -- quick-fill row (above the main row): Min / Pot / All-in
  local function quick(label, fn)
    return W.button(bar, label, function()
      local v = fn()
      if v and bar.amount.SetText then bar.amount:SetText(tostring(v)) end
    end)
  end
  bar.qMin = quick("Min", function() return bar._min end)
  bar.qMin:SetWidth(52); bar.qMin:SetHeight(18)
  bar.qMin:SetPoint("BOTTOMLEFT", bar.fold, "TOPLEFT", 0, 4)
  bar.qPot = quick("Pot", function()
    local v = bar._pot
    if v and bar._min and v < bar._min then v = bar._min end
    if v and bar._max and v > bar._max then v = bar._max end
    return v
  end)
  bar.qPot:SetWidth(52); bar.qPot:SetHeight(18)
  bar.qPot:SetPoint("LEFT", bar.qMin, "RIGHT", 4, 0)
  bar.qMax = quick("All-in", function() return bar._max end)
  bar.qMax:SetWidth(52); bar.qMax:SetHeight(18)
  bar.qMax:SetPoint("LEFT", bar.qPot, "RIGHT", 4, 0)

  bar:Hide()
  ns.UI.actionBar = bar
end

local function refresh(v)
  if not bar then return end

  -- surface a host refusal exactly once (the prompt itself comes back via re-BET_TURN)
  if v and v.refused and v.refused ~= bar._shownRefuse then
    bar._shownRefuse = v.refused
    if ns.Log then ns.Log.error("Action refused: " .. tostring(v.refused) .. " — try again.") end
  end

  if not (v and v.myTurn and not v.aborted) then bar:Hide(); bar._lastTurn = false; return end
  bar:Show()
  local opener = (v.toCall or 0) == 0
  bar._opener = opener
  bar._min = opener and v.minBet or v.minRaise
  bar._max = opener and v.maxBet or v.maxRaise
  bar._pot = v.pot

  if v.canCheck then bar.check:Show(); bar.call:Hide()
  else bar.check:Hide(); bar.call:Show(); bar.call:SetText("Call " .. W.commas(v.toCall or 0)) end
  -- no legal bet/raise range (e.g. facing an all-in): hide the raise controls entirely
  if bar._min then bar.raise:Show(); bar.amount:Show() else bar.raise:Hide(); bar.amount:Hide() end
  bar.raise:SetText(opener and "Bet" or "Raise to")

  -- show only the quick-fills whose value we know
  if bar._min then bar.qMin:Show() else bar.qMin:Hide() end
  if bar._pot then bar.qPot:Show() else bar.qPot:Hide() end
  if bar._max then bar.qMax:Show() else bar.qMax:Hide() end

  -- prime the amount box once per turn with the minimum
  if not bar._lastTurn and bar._min and bar.amount.SetText then bar.amount:SetText(tostring(bar._min)) end
  bar._lastTurn = true
end

build()
ns.UI.register(refresh)
return ns.UI.actionBar
