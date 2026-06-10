--[[ Actions.lua — the action bar: Fold / Check / Call (with amount) / Bet|Raise,
  a raise amount box with Min / Pot / All-in quick-fills. Appears only on your turn
  with a gold "YOUR TURN" header. ]]

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
  if not ok and ns.Log then ns.Log.error("can't " .. action .. ": " .. tostring(err)) end
end

local function amountVal() return tonumber(bar.amount:GetText()) end

local function build()
  bar = W.panel(UIParent, 430, 78)
  bar:SetPoint("BOTTOM", 0, 150)
  bar.header = W.label(bar, "YOUR TURN", "GameFontNormal"); bar.header:SetPoint("TOP", 0, -6)
  bar.header:SetTextColor(rgba(COL.turn))

  bar.fold = W.button(bar, "Fold", function() act(A.FOLD) end); bar.fold:SetPoint("BOTTOMLEFT", 10, 10)
  bar.check = W.button(bar, "Check", function() act(A.CHECK) end); bar.check:SetPoint("LEFT", bar.fold, "RIGHT", 4, 0)
  bar.call = W.button(bar, "Call", function() act(A.CALL) end); bar.call:SetPoint("LEFT", bar.check, "RIGHT", 4, 0)
  bar.raise = W.button(bar, "Raise", function()
    act((bar._opener and A.BET) or A.RAISE, amountVal())
  end); bar.raise:SetPoint("LEFT", bar.call, "RIGHT", 4, 0)
  bar.amount = W.editbox(bar, 56); bar.amount:SetPoint("LEFT", bar.raise, "RIGHT", 6, 0)

  -- quick-fill chips for the amount box
  local function quick(label, fn, anchor)
    local q = W.button(bar, label, function() if bar.amount.SetText then bar.amount:SetText(tostring(fn() or "")) end end)
    q:SetWidth(46); q:SetHeight(18); q:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    return q
  end
  bar.qMin = quick("Min", function() return bar._min end, bar.raise)
  bar.qPot = quick("Pot", function() return bar._pot end, bar.qMin)
  bar.qMax = quick("All-in", function() return bar._max end, bar.qPot)
  -- relocate quick row under the main buttons
  bar.qMin:ClearAllPoints(); bar.qMin:SetPoint("TOPLEFT", bar.fold, "TOPRIGHT", 0, 0)

  bar:Hide()
  ns.UI.actionBar = bar
end

local function refresh(v)
  if not bar then return end
  if not (v and v.myTurn and not v.aborted) then bar:Hide(); bar._lastTurn = false; return end
  bar:Show()
  local opener = (v.toCall or 0) == 0
  bar._opener = opener
  bar._min = opener and v.minBet or v.minRaise
  bar._max = opener and v.maxBet or v.maxRaise
  bar._pot = v.pot

  if opener then bar.check:Show(); bar.call:Hide()
  else bar.check:Hide(); bar.call:Show(); bar.call:SetText("Call " .. W.commas(v.toCall or 0)) end
  bar.raise:SetText(opener and "Bet" or "Raise")

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
