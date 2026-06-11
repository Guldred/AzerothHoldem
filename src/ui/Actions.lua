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
  -- the controls live inside the table window's control strip — never as a
  -- floating window (one window during play; a stray panel confused players)
  local host = ns.UI.controlStrip
  if not host then return end                       -- Table.lua builds the strip first (.toc order)
  bar = CreateFrame("Frame", nil, host)
  bar:SetAllPoints(host)

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

  -- pre-actions (armed while WAITING for your turn; fire instantly when it comes):
  -- "Check/Fold" = check if free else fold; "Call any" = call whatever (check if free).
  -- Mutually exclusive; cleared after firing. Checked state lives in our own _on
  -- field (the template's GetChecked is unreliable under the test stub).
  local function mkPre(label, x, y)
    local cb = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    cb:SetWidth(18); cb:SetHeight(18); cb:SetPoint("BOTTOMLEFT", x, y)
    cb._on = false
    cb.label = W.label(bar, label, "GameFontNormalSmall", "LEFT")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    return cb
  end
  bar.preCF = mkPre("Check/Fold", 462, 22)
  bar.preCall = mkPre("Call any", 462, 3)
  local function setPre(cb, on)
    cb._on = on and true or false
    if cb.SetChecked then cb:SetChecked(cb._on) end
  end
  bar.preCF:SetScript("OnClick", function()
    setPre(bar.preCF, not bar.preCF._on); if bar.preCF._on then setPre(bar.preCall, false) end
  end)
  bar.preCall:SetScript("OnClick", function()
    setPre(bar.preCall, not bar.preCall._on); if bar.preCall._on then setPre(bar.preCF, false) end
  end)
  bar._setPre = setPre

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

  -- pre-action boxes show while a hand is live and it's NOT your turn
  local inHand = v and v.toAct and not v.aborted and not v.deltas
  if inHand and not v.myTurn then
    bar.preCF:Show(); bar.preCall:Show()
    bar.preCF.label:Show(); bar.preCall.label:Show()
  else
    bar.preCF:Hide(); bar.preCall:Hide()
    bar.preCF.label:Hide(); bar.preCall.label:Hide()
  end
  if v and v.deltas then                            -- hand over: disarm leftovers
    bar._setPre(bar.preCF, false); bar._setPre(bar.preCall, false)
  end

  if not (v and v.myTurn and not v.aborted) then
    setActive(false); bar._lastTurn = false
    if ns.setTurnAlert then ns.setTurnAlert(false) end
    return
  end

  -- your turn: armed pre-action fires instantly (then disarms)
  if not bar._lastTurn then
    if bar.preCF._on then
      bar._setPre(bar.preCF, false); bar._setPre(bar.preCall, false)
      bar._lastTurn = true
      act(v.canCheck and A.CHECK or A.FOLD)
      return
    elseif bar.preCall._on then
      bar._setPre(bar.preCF, false); bar._setPre(bar.preCall, false)
      bar._lastTurn = true
      act((v.toCall or 0) > 0 and A.CALL or A.CHECK)
      return
    end
    -- no pre-action: ping the player (sound + minimap flash) once per turn
    if type(PlaySound) == "function" then PlaySound("ReadyCheck") end
    if ns.setTurnAlert then ns.setTurnAlert(true) end
  end

  -- the host's EXACT legal actions decide everything — never inferred from toCall
  -- (a big blind facing callers has toCall=0 but must RAISE, not BET)
  local canAggro = v.canBet or v.canRaise

  -- check is the ONLY meaningful action (e.g. all-in runouts): act for the player
  -- instead of making them click a button with no alternative
  if v.canCheck and not canAggro and not bar._lastTurn then
    bar._lastTurn = true
    if ns.Log then ns.Log.info("Checked automatically — no other action was possible.") end
    act(A.CHECK)
    return
  end

  setActive(true)
  bar._opener = v.canBet                       -- send BET vs RAISE per the host's flags
  bar._min = v.canBet and v.minBet or v.minRaise
  bar._max = v.canBet and v.maxBet or v.maxRaise
  bar._pot = v.pot

  if v.canCheck then bar.check:Show(); bar.call:Hide()
  else bar.check:Hide(); bar.call:Show(); bar.call:SetText("Call " .. W.commas(v.toCall or 0)) end
  -- no legal bet/raise (or unknown range): grey the aggressive controls
  if canAggro and bar._min then
    if bar.raise.Enable then bar.raise:Enable() end
  else
    if bar.raise.Disable then bar.raise:Disable() end
  end
  bar.raise:SetText(v.canBet and "Bet" or "Raise to")

  -- quick-fills only make sense with a known value
  if not bar._min and bar.qMin.Disable then bar.qMin:Disable() end
  if not bar._pot and bar.qPot.Disable then bar.qPot:Disable() end
  if not bar._max and bar.qMax.Disable then bar.qMax:Disable() end

  -- prime the amount box once per turn with the minimum
  if not bar._lastTurn and bar._min and bar.amount.SetText then bar.amount:SetText(tostring(bar._min)) end
  bar._lastTurn = true
end

build()
if bar then setActive(false) end
ns.UI.register(refresh)
return ns.UI.actionBar
