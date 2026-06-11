--[[ Table.lua — the felt poker table: community + hole cards, pot, seats arranged
  around an oval (you at the bottom), dealer button, and an active-turn highlight. ]]

local ADDON, ns = ...
local W = ns.W
local COL = W.COL
local sin, cos, rad, floor = math.sin, math.cos, math.rad, math.floor
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local frame, seatBoxes
local MAXSEATS = 9
local AX, AY = 215, 118   -- seat-oval radii

local function makeSeatBox(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetWidth(104); b:SetHeight(42)
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  if W.artOK(W.ART.glow) then                      -- soft gold halo, pulsed when active
    b.glow:SetPoint("TOPLEFT", -8, 8); b.glow:SetPoint("BOTTOMRIGHT", 8, -8)
    b.glow:SetTexture(W.ART.glow)
  else
    b.glow:SetPoint("TOPLEFT", -3, 3); b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetTexture(rgba(COL.turn))
  end
  b.glow:Hide()
  b.bg = b:CreateTexture(nil, "BORDER"); b.bg:SetAllPoints(b)
  if W.artOK(W.ART.plate) then b.bg:SetTexture(W.ART.plate)   -- rounded seat plate
  else b.bg:SetTexture(0, 0, 0, 0.6) end
  -- class icon (resolved best-effort from your party/raid or the guild roster)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetWidth(22); b.icon:SetHeight(22); b.icon:SetPoint("LEFT", 5, 0)
  b.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  b.icon:Hide()
  b.name = W.label(b, "", "GameFontNormalSmall"); b.name:SetPoint("TOP", 0, -3)
  b.stack = W.label(b, "", "GameFontHighlightSmall"); b.stack:SetPoint("TOP", b.name, "BOTTOM", 0, -1)
  b.bet = W.label(b, "", "GameFontNormalSmall"); b.bet:SetPoint("BOTTOM", 0, 2); b.bet:SetTextColor(rgba(COL.gold))
  b.dealer = W.label(b, "D", "GameFontNormalSmall"); b.dealer:SetPoint("TOPRIGHT", -3, -2)
  b.dealer:SetTextColor(rgba(COL.gold)); b.dealer:Hide()
  b.dealerTex = b:CreateTexture(nil, "OVERLAY")           -- dealer-button art (over the "D")
  b.dealerTex:SetWidth(18); b.dealerTex:SetHeight(18); b.dealerTex:SetPoint("TOPRIGHT", -2, -1)
  if W.artOK(W.ART.dealer) then b.dealerTex:SetTexture(W.ART.dealer) end
  b.dealerTex:Hide()
  b:Hide()
  return b
end

local function build()
  -- one window during play: the felt up top + a control strip along the bottom
  -- (the action bar embeds itself there — see Actions.lua / ns.UI.controlStrip)
  frame = W.panel(UIParent, 560, 430, "Azeroth Hold'em")
  frame:SetPoint("CENTER")

  -- the table itself: a stadium poker table (wood rail + felt + board inlay).
  -- Cards/pot/seats anchor to frame.felt's CENTER; the art's inlay/stencil were
  -- drawn for this 544x292 mapping (see art/build_ui.sh) — move them together.
  frame.felt = frame:CreateTexture(nil, "BACKGROUND")
  if W.artOK(W.ART.table) then
    frame.felt:SetPoint("TOPLEFT", 8, -24); frame.felt:SetPoint("BOTTOMRIGHT", -8, 114)
    frame.felt:SetTexture(W.ART.table)
  else
    frame.felt:SetPoint("TOPLEFT", 16, -28); frame.felt:SetPoint("BOTTOMRIGHT", -16, 120)
    if W.artOK(W.ART.felt) then frame.felt:SetTexture(W.ART.felt)  -- flat felt
    else frame.felt:SetTexture(rgba(COL.felt)) end                 -- solid green
  end

  -- the control strip the action bar lives in (subtle darker band)
  frame.strip = CreateFrame("Frame", nil, frame)
  frame.strip:SetPoint("BOTTOMLEFT", 8, 6); frame.strip:SetPoint("BOTTOMRIGHT", -8, 6)
  frame.strip:SetHeight(44)
  frame.stripBg = frame.strip:CreateTexture(nil, "BACKGROUND")
  frame.stripBg:SetAllPoints(frame.strip); frame.stripBg:SetTexture(0, 0, 0, 0.30)
  ns.UI.controlStrip = frame.strip

  -- pot (a chip stack if we have the art, else the built-in gold coin)
  frame.potChip = W.tex(frame, "ARTWORK")
  if W.artOK(W.ART.chips) then
    frame._potChipBase = 30; frame.potChip:SetTexture(W.ART.chips)
  else
    frame._potChipBase = 16; frame.potChip:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
  end
  frame.potChip:SetWidth(frame._potChipBase); frame.potChip:SetHeight(frame._potChipBase)
  frame.potChip:SetPoint("CENTER", frame.felt, "CENTER", -34, 74)
  frame.pot = W.label(frame, "", "GameFontNormalLarge"); frame.pot:SetPoint("LEFT", frame.potChip, "RIGHT", 4, 0)
  frame.pot:SetTextColor(rgba(COL.gold))

  -- community cards
  frame.board = {}
  for i = 1, 5 do
    local cd = W.card(frame, 38, 54)
    cd:SetPoint("CENTER", frame.felt, "CENTER", (i - 3) * 44, 28)
    frame.board[i] = cd
  end

  -- your hole cards + hand name (just above the control strip). flipReveal =>
  -- dealt face-down, then turned up.
  frame.hole = {}
  for i = 1, 2 do
    local cd = W.card(frame, 46, 66)
    cd:SetPoint("BOTTOM", frame, "BOTTOM", (i == 1) and -28 or 28, 84)
    cd.flipReveal = true
    frame.hole[i] = cd
  end
  frame.handName = W.label(frame, "", "GameFontNormal"); frame.handName:SetPoint("BOTTOM", frame, "BOTTOM", 0, 64)
  frame.handName:SetTextColor(rgba(COL.gold))

  frame.status = W.label(frame, "", "GameFontDisableSmall"); frame.status:SetPoint("BOTTOMRIGHT", -12, 56)

  seatBoxes = {}
  for i = 1, MAXSEATS do seatBoxes[i] = makeSeatBox(frame) end
  -- your hole cards render ABOVE the bottom seat plate (it peeks out behind them)
  local lvl = frame.GetFrameLevel and frame:GetFrameLevel()
  if type(lvl) == "number" then
    for i = 1, 2 do frame.hole[i]:SetFrameLevel(lvl + 5) end
  end

  -- gentle pulse on the active seat's glow + a brief "swell" of the pot chip when it grows
  frame:SetScript("OnUpdate", function(self, e)
    self._t = (self._t or 0) + (e or 0)
    if self.activeGlow then self.activeGlow:SetAlpha(0.45 + 0.35 * sin(self._t * 4)) end
    if self._potPulse and self._potPulse > 0 then
      self._potPulse = self._potPulse - (e or 0) * 3.2
      if self._potPulse < 0 then self._potPulse = 0 end
      if self.potChip and self.potChip.SetWidth then
        local s = (self._potChipBase or 30) * (1 + 0.40 * self._potPulse)
        self.potChip:SetWidth(s); self.potChip:SetHeight(s)
      end
    end
  end)

  frame:Hide()
  ns.UI.tableFrame = frame
end

local function refresh(v)
  if not frame then return end
  if not v then frame:Hide(); frame._fadedIn = false; return end
  frame:Show()
  if not frame._fadedIn then                                   -- fade the whole table in on open
    frame._fadedIn = true
    W.tween(frame, { dur = 0.28, ease = W.easing.outCubic, fromAlpha = 0, toAlpha = 1 })
  end

  frame.pot:SetText(W.commas(v.pot or 0))
  if v.pot and frame._lastPot and v.pot > frame._lastPot then frame._potPulse = 1 end
  frame._lastPot = v.pot or 0

  -- community cards: deal left-to-right, staggered as each street turns over
  local di = 0
  for i = 1, 5 do
    if v.board[i] then
      local isNew = (frame.board[i]._shownKey ~= v.board[i])
      frame.board[i]:setCard(v.board[i], isNew and di * W.ANIM.stagger or 0)
      if isNew then di = di + 1 end
    else
      frame.board[i]:setEmpty()
    end
  end
  -- your hole cards
  local hi = 0
  for i = 1, 2 do
    if v.hole[i] then
      local isNew = (frame.hole[i]._shownKey ~= v.hole[i])
      frame.hole[i]:setCard(v.hole[i], isNew and hi * W.ANIM.stagger or 0)
      if isNew then hi = hi + 1 end
    else
      frame.hole[i]:setEmpty()
    end
  end
  frame.handName:SetText(v.handName or "")
  local STREET = { [0] = "pre-flop", [1] = "flop", [2] = "turn", [3] = "river" }
  local statusText
  if v.aborted then statusText = "|cffff4444HALTED|r"
  elseif v.myTurn then statusText = "|cffffd95cYour turn!|r"
  elseif v.toAct then statusText = "Waiting for " .. tostring(v.toAct) .. "…"
  else statusText = "" end
  if STREET[v.street] then statusText = statusText .. "  (" .. STREET[v.street] .. ")" end
  frame.status:SetText(statusText)

  -- seats around the oval, rotated so "me" sits at the bottom
  frame.activeGlow = nil
  local seats = v.seats or {}
  local n = #seats
  local meIdx = 1
  for i = 1, n do if seats[i].id == v.me then meIdx = i end end
  for i = 1, MAXSEATS do
    local box = seatBoxes[i]
    local s = seats[i]
    if s then
      local k = (i - meIdx) % n                       -- 0 = me (bottom), then around
      local theta = rad(270 + k * (360 / n))
      box:ClearAllPoints()
      box:SetPoint("CENTER", frame.felt, "CENTER", AX * cos(theta), AY * sin(theta))
      box.name:SetText(s.id == v.me and (s.id .. " (you)") or s.id)
      -- class icon: best-effort lookup (party/raid, then guild roster); when the
      -- class is unknown the plate simply renders without an icon
      local tok = ns.classOf and ns.classOf(s.id)
      local tc = tok and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[tok]
      box.name:ClearAllPoints()
      if tc then
        box.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); box.icon:Show()
        box.name:SetPoint("TOPLEFT", 29, -4)
      else
        box.icon:Hide()
        box.name:SetPoint("TOP", 0, -3)
      end
      box.stack:SetText(s.stack and W.commas(s.stack) or "")
      box.bet:SetText((s.bet and s.bet > 0) and ("bet " .. W.commas(s.bet)) or "")
      box:SetAlpha(s.folded and 0.4 or 1.0)
      if s.allIn then box.bet:SetText("ALL-IN") end
      if v.button and s.id == v.button then
        if box.dealerTex and W.artOK(W.ART.dealer) then box.dealerTex:Show(); box.dealer:Hide()
        else box.dealer:Show() end
      else box.dealer:Hide(); if box.dealerTex then box.dealerTex:Hide() end end
      if s.id == v.toAct and not s.folded then box.glow:Show(); frame.activeGlow = box.glow else box.glow:Hide() end
      box:Show()
    else
      box:Hide()
    end
  end
end

build()
ns.UI.register(refresh)
ns.UI.Table = { get = function() return frame end }
return ns.UI.Table
