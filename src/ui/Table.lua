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
  if W.artOK(W.ART.plates) then                    -- soft gold halo, pulsed when active
    b.glow:SetPoint("TOPLEFT", -8, 8); b.glow:SetPoint("BOTTOMRIGHT", 8, -8)
    b.glow:SetTexture(W.ART.plates); b.glow:SetTexCoord(0, 1, 0.5, 1)
  else
    b.glow:SetPoint("TOPLEFT", -3, 3); b.glow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.glow:SetTexture(rgba(COL.turn))
  end
  b.glow:Hide()
  b.bg = b:CreateTexture(nil, "BORDER"); b.bg:SetAllPoints(b)
  if W.artOK(W.ART.plates) then                    -- rounded seat plate (atlas top half)
    b.bg:SetTexture(W.ART.plates); b.bg:SetTexCoord(0, 1, 0, 0.5)
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
  -- showdown: the seat's revealed hole cards, shown under the plate at hand end
  b.sd = {}
  for i = 1, 2 do
    b.sd[i] = W.card(b, 26, 36)
    b.sd[i]:SetPoint("TOP", b, "BOTTOM", (i == 1) and -15 or 15, 2)
    b.sd[i]:Hide()
  end
  b:Hide()
  return b
end

local function build()
  -- one window during play: the felt up top + a control strip along the bottom
  -- (the action bar embeds itself there — see Actions.lua / ns.UI.controlStrip)
  frame = W.panel(UIParent, 560, 430, "Azeroth Hold'em")
  frame:SetPoint("CENTER")

  -- leave/close without slash commands: back to the lobby window in one click
  frame.leave = W.button(frame, "Leave Table", function()
    if not ns.onSlash then return end
    if ns.casino and ns.casino.tableHost then ns.onSlash("close") else ns.onSlash("stand") end
    if ns.UI.showLobby then ns.UI.showLobby() end
  end)
  frame.leave:SetWidth(92); frame.leave:SetHeight(18)
  frame.leave:SetPoint("TOPRIGHT", -6, -4)

  -- the table itself: a stadium poker table (wood rail + felt + board inlay).
  -- Cards/pot/seats anchor to frame.felt's CENTER; the art's inlay/stencil were
  -- drawn for this 544x292 mapping (see art/build_ui.sh) — move them together.
  -- BORDER layer: the panel backdrop's cloth lives on BACKGROUND — same-layer
  -- sublevel ordering is not guaranteed, and on some clients the cloth drew OVER
  -- the table art (a grey film). One layer up removes the ambiguity.
  frame.felt = frame:CreateTexture(nil, "BORDER")
  if W.artOK(W.ART.table) then
    frame.felt:SetPoint("TOPLEFT", 8, -24); frame.felt:SetPoint("BOTTOMRIGHT", -8, 114)
    frame.felt:SetTexture(W.ART.table)
    frame.felt:SetTexCoord(0, 1, 0, 0.5)            -- the art lives in the atlas top half
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

  -- end-of-hand result, across the felt center ("Thrall wins +240 — Full House")
  frame.winText = W.label(frame, "", "GameFontNormalLarge")
  frame.winText:SetPoint("CENTER", frame.felt, "CENTER", 0, -4)
  frame.winText:SetTextColor(rgba(COL.gold))

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

  -- contextual: the host CLOSES the table, a player LEAVES it (manual single-table
  -- mode has neither — hide the button there)
  if ns.casino then
    frame.leave:SetText(ns.casino.tableHost and "Close Table" or "Leave Table")
    frame.leave:Show()
  else
    frame.leave:Hide()
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

  -- end-of-hand: name the winner(s) + what they won (and their combo at showdown)
  local winners
  if v.deltas then
    for seat, dlt in pairs(v.deltas) do
      if dlt > 0 then winners = winners or {}; winners[#winners + 1] = { seat = seat, amt = dlt } end
    end
    if winners then table.sort(winners, function(a, b) return a.amt > b.amt end) end
  end
  local winLine
  if winners and #winners == 1 then
    local wn = winners[1]
    local combo = v.showdown and v.showdown[wn.seat] and v.showdown[wn.seat].handName
    winLine = wn.seat .. " wins +" .. W.commas(wn.amt) .. (combo and ("  —  " .. combo) or "")
  elseif winners then
    local parts = {}
    for i = 1, #winners do parts[i] = winners[i].seat .. " +" .. W.commas(winners[i].amt) end
    winLine = "Split pot:  " .. table.concat(parts, ",  ")
  end
  frame._winLine = winLine
  frame.winText:SetText(winLine and ("|cffffd95c" .. winLine .. "|r") or "")

  local STREET = { [0] = "pre-flop", [1] = "flop", [2] = "turn", [3] = "river" }
  local statusText
  if v.aborted then statusText = "|cffff4444HALTED|r"
  elseif winLine then statusText = "Hand complete — next deal in a moment…"
  elseif v.myTurn then statusText = "|cffffd95cYour turn!|r"
  elseif v.toAct then statusText = "Waiting for " .. tostring(v.toAct) .. "…"
  else statusText = "" end
  if not winLine and STREET[v.street] then statusText = statusText .. "  (" .. STREET[v.street] .. ")" end
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
      local px = AX * cos(theta)
      if s.id == v.me then px = -118 end              -- your plate sits LEFT of your hole
      box:ClearAllPoints()                            -- cards so your chips stay visible
      box:SetPoint("CENTER", frame.felt, "CENTER", px, AY * sin(theta))
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
      -- showdown: everyone's revealed cards under their plate (yours are already big)
      local sd = v.showdown and v.showdown[s.id]
      if sd and sd.cards and s.id ~= v.me then
        box.sd[1]:setCard(sd.cards[1]); box.sd[2]:setCard(sd.cards[2])
      else
        box.sd[1]:Hide(); box.sd[2]:Hide()
      end
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
