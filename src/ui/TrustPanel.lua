--[[ TrustPanel.lua — the fair-play indicator, embedded in the table window (one
  window during play): a small status icon + line at the bottom-left summarizing
  the verification pipeline (seed sealed -> deck committed -> cards verified ->
  end-of-hand audit), and a big red on-table banner the moment a cheat is detected.
  The detailed per-check readout lives in the tooltip-free summary text. ]]

local ADDON, ns = ...
local W = ns.W
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local cluster, banner, report

-- ---- the Fairness Report: WHY this game can't cheat, per hand, in plain words --
local function buildReport()
  report = W.panel(UIParent, 360, 290, "Fairness Report", true)
  report:SetPoint("CENTER", -250, 60)
  local function line(y, text, font)
    local fs = W.label(report, text, font or "GameFontHighlightSmall", "LEFT")
    fs:SetPoint("TOPLEFT", 16, y); fs:SetWidth(330)
    return fs
  end
  report.hand   = line(-32, "", "GameFontNormal")
  report.checks = {}
  local items = {
    { key = "seed",  label = "Shuffle seed sealed by ALL players' secrets" },
    { key = "deck",  label = "All 52 cards locked (hashed) before any betting" },
    { key = "same",  label = "Every player saw the SAME deck (cross-check)" },
    { key = "cards", label = "Each revealed card matched its sealed hash" },
    { key = "audit", label = "Full deck re-derived & audited at hand end" },
  }
  for i, it in ipairs(items) do
    local r = {}
    r.icon = W.tex(report, "ARTWORK", W.ICON.waiting)
    r.icon:SetWidth(14); r.icon:SetHeight(14); r.icon:SetPoint("TOPLEFT", 16, -56 - (i - 1) * 22)
    r.label = W.label(report, it.label, "GameFontHighlightSmall", "LEFT")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.label:SetWidth(310)
    report.checks[it.key] = r
  end
  report.tally = line(-176, "", "GameFontNormalSmall")
  report.foot = line(-200,
    "No one — the dealer included — can know or change the order of the cards. " ..
    "Any tampering trips an instant CHEAT alert for everyone at the table.",
    "GameFontDisableSmall")
  report:Hide()
  ns.UI.fairnessPanel = report
end

local function setCheck(key, state)
  local r = report.checks[key]
  if not r then return end
  r.icon:SetTexture(state == true and W.ICON.ready or (state == "bad" and W.ICON.notready or W.ICON.waiting))
end

function ns.UI.showFairness()
  if not report then return end
  local s = ns.activeSession and ns.activeSession()
  local v = s and ns.UI.viewOf and ns.UI.viewOf(s)
  if v then
    report.hand:SetText("Hand #" .. tostring(s.handNo or "—") ..
      (v.isHost and "  (you are the dealer — others verify your deal)" or ""))
    -- each row lights up only when its check actually PASSED (never from an
    -- earlier gate alone); a detected cheat flips everything to the red X
    local bad = v.aborted and "bad" or nil
    setCheck("seed", bad or v.sealed)
    setCheck("deck", bad or (v.deckCommitted or nil))
    setCheck("same", bad or (v.crossChecked or nil))
    -- the dealer doesn't verify its own deal — its cards/audit rows complete when
    -- the hand does and no client raised a CHEAT (which now reaches the dealer)
    setCheck("cards", bad or (v.isHost and (v.deltas and true or nil) or v.holeVerified))
    setCheck("audit", bad or (v.isHost and (v.deltas and true or nil) or v.auditPassed))
    local n = (not v.isHost and s.auditCount) or nil
    if not v.isHost and v.resumed then
      report.tally:SetText("Rejoined mid-hand — reduced checks this hand; full checks resume next hand.")
    else
      report.tally:SetText(n and ("Hands fully verified this session: " .. n)
        or (v.isHost and "Clients verify every hand you deal." or "Verification runs during each hand."))
    end
  else
    report.hand:SetText("No hand in progress — play one and check back!")
    for k in pairs(report.checks) do setCheck(k, nil) end
    report.tally:SetText("")
  end
  report:Show()
end

local function build()
  local host = ns.UI.tableFrame
  if not host then return end                       -- table window is built first (.toc order)
  buildReport()

  -- the fair-play line is a BUTTON: click it for the full report
  cluster = CreateFrame("Button", nil, host)
  cluster:SetWidth(220); cluster:SetHeight(16)
  cluster:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 12, 56)
  cluster:SetScript("OnClick", function() ns.UI.showFairness() end)
  cluster.icon = cluster:CreateTexture(nil, "ARTWORK")
  cluster.icon:SetWidth(14); cluster.icon:SetHeight(14); cluster.icon:SetPoint("LEFT", 0, 0)
  cluster.icon:SetTexture(W.ICON.waiting)
  cluster.text = W.label(cluster, "", "GameFontDisableSmall", "LEFT")
  cluster.text:SetPoint("LEFT", cluster.icon, "RIGHT", 4, 0)

  -- the unmissable cheat banner, across the middle of the felt
  banner = W.label(host, "", "GameFontNormalLarge")
  banner:SetPoint("CENTER", host, "CENTER", 0, 40)
  banner:SetText("")

  ns.UI.trustPanel = cluster
end

local function setState(icon, text)
  if not cluster then return end
  cluster.icon:SetTexture(icon)
  cluster.text:SetText(text)
end

local function refresh(v)
  if not cluster then return end
  -- the fairness report is live while open (it's a status panel, not a snapshot)
  if report and report.IsShown and report:IsShown() then ns.UI.showFairness() end
  if not v then banner:SetText(""); return end
  if v.aborted then
    setState(W.ICON.notready, "fair play: FAILED")
    banner:SetText("|cffff2222>>> CHEAT: " .. (v.cheat and v.cheat.code or "?") .. " <<<|r")
    return
  end
  banner:SetText("")
  if v.auditPassed then setState(W.ICON.ready, "fair play: hand verified")
  elseif v.holeVerified then setState(W.ICON.ready, "fair play: cards verified")
  elseif v.sealed then setState(W.ICON.waiting, "fair play: deck sealed, verifying…")
  else setState(W.ICON.waiting, "fair play: preparing…") end
end

-- fired straight from the cheat callback (independent of the refresh loop)
function ns.UI.showCheat(code, detail)
  if not cluster then return end
  setState(W.ICON.notready, "fair play: FAILED")
  if banner then banner:SetText("|cffff2222>>> CHEAT: " .. tostring(code) .. " <<<|r") end
end

build()
ns.UI.register(refresh)
return ns.UI.trustPanel
