--[[ Widgets.lua — visual toolkit + the ns.UI aggregator (FrameXML, no XML templates).

  Casino styling built from era-correct 3.3.5a primitives only: Texture:SetTexture(r,g,b,a)
  for solid fills (felt, card faces, chips), built-in textures for icons, GameFont*
  font objects. Cards are drawn as framed faces with a big rank + colored suit.
]]

local ADDON, ns = ...
local Const = ns.Const
local W = {}

-- palette
W.COL = {
  felt   = { 0.06, 0.30, 0.16 },   -- table felt green
  feltLt = { 0.10, 0.40, 0.22 },
  panel  = { 0.05, 0.05, 0.07, 0.92 },
  rail   = { 0.20, 0.14, 0.06 },   -- wood rail / borders
  gold   = { 0.95, 0.82, 0.35 },
  cream  = { 0.97, 0.96, 0.92 },
  red    = { 0.85, 0.12, 0.12 },
  black  = { 0.12, 0.12, 0.14 },
  dim    = { 0.55, 0.55, 0.58 },
  green  = { 0.40, 0.85, 0.40 },
  turn   = { 1.0, 0.85, 0.30 },    -- active-seat glow
}

local function c4(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

-- a solid-color texture filling its parent (or anchored by the caller)
function W.fill(parent, layer, col, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(c4(col, a))
  t:SetAllPoints(parent)
  return t
end

function W.tex(parent, layer, file)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if file then t:SetTexture(file) end
  return t
end

function W.label(parent, text, font, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetText(text or "")
  if justify and fs.SetJustifyH then fs:SetJustifyH(justify) end
  return fs
end

-- a framed panel with a dark fill + gold-ish border, an optional draggable title bar
function W.panel(parent, w, h, title, closable)
  local f = CreateFrame("Frame", nil, parent or UIParent)
  f:SetWidth(w or 120); f:SetHeight(h or 120)
  if f.SetBackdrop then
    local cloth = W.artOK(W.ART.panelbg)
    -- the cloth is STRETCHED, not tiled: its noise isn't seamless, so tiling drew
    -- visible seam lines across larger panels (every 256px)
    f:SetBackdrop({
      bgFile = cloth and W.ART.panelbg or "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = not cloth, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    -- the cloth texture carries its own tone; only tint the plain fallback dark
    if cloth then f:SetBackdropColor(1, 1, 1, 0.97) else f:SetBackdropColor(c4(W.COL.panel)) end
    f:SetBackdropBorderColor(c4(W.COL.gold, 0.6))
  end
  if f.SetFrameStrata then f:SetFrameStrata("MEDIUM") end
  if title then
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(c4(W.COL.rail, 0.9))
    bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("TOPRIGHT", -4, -4); bar:SetHeight(20)
    f.titleText = W.label(f, title, "GameFontNormal"); f.titleText:SetPoint("TOP", 0, -7)
    f.titleText:SetTextColor(c4(W.COL.gold))
    if closable then
      f.close = W.button(f, "X", function() f:Hide() end); f.close:SetWidth(20); f.close:SetHeight(18)
      f.close:SetPoint("TOPRIGHT", -5, -5)
    end
  end
  W.makeMovable(f)
  return f
end

function W.button(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetWidth(78); b:SetHeight(22); b:SetText(text or "")
  b:SetScript("OnClick", onClick)
  -- casino skin: replace the template's stock textures with the gold-trimmed set
  -- (template behavior — text, click handling, enable/disable — is unchanged).
  -- The hover row is ADDITIVE: WoW draws highlights ABOVE the button text, so an
  -- opaque hover would blank the label; an ADD overlay only brightens it.
  if W.artOK(W.ART.btns) then
    local function state(setter, getter, v0, v1, blend)
      if blend then b[setter](b, W.ART.btns, blend) else b[setter](b, W.ART.btns) end
      local t = b[getter] and b[getter](b)
      if t and t.SetTexCoord then t:SetTexCoord(0, 1, v0, v1) end
    end
    state("SetNormalTexture",   "GetNormalTexture",   0,    0.25)
    state("SetHighlightTexture","GetHighlightTexture",0.25, 0.5, "ADD")
    state("SetPushedTexture",   "GetPushedTexture",   0.5,  0.75)
    state("SetDisabledTexture", "GetDisabledTexture", 0.75, 1)
  end
  return b
end

function W.editbox(parent, width)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetWidth(width or 60); e:SetHeight(20)
  e:SetAutoFocus(false); e:SetNumeric(true)
  return e
end

function W.makeMovable(f)
  if not f.SetMovable then return end
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
end

-- ready-check icons for the trust panel (these textures ship with 3.3.5a)
W.ICON = {
  ready = "Interface\\RaidFrame\\ReadyCheck-Ready",        -- green check
  notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",  -- red X
  waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",    -- yellow ?
}

-- 1,234,567 grouping
function W.commas(n)
  local s = tostring(math.floor(n or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- ---- art assets -----------------------------------------------------------
-- Real poker art lives in art/ as power-of-two, 32-bit uncompressed .tga (the only
-- image format WoW 3.3.5a can load). It is referenced by in-game path; the installed
-- AddOns folder is named after the .toc ("AzerothHoldem"), NOT the repo directory.
local ART = "Interface\\AddOns\\AzerothHoldem\\art\\"
W.ART = {
  cards  = ART .. "cards.tga",   -- 1024x1024 atlas: 13 cols (rank) x 4 rows (suit) + back
  felt   = ART .. "felt.tga",    -- 512x512 green felt (fallback fill behind the table art)
  chips  = ART .. "chips.tga",   -- 128x128 chip stack (pot)
  dealer = ART .. "dealer.tga",  -- 64x64 dealer button
  -- NOTE: all UI textures are SQUARE — in-client testing showed 3.3.5a renders
  -- non-square TGAs black. Content lives in atlas regions addressed by texcoords.
  table  = ART .. "table.tga",   -- 1024x1024; the stadium table is the TOP HALF (v 0..0.5)
  btns   = ART .. "btns.tga",    -- 128x128; 32px rows: normal/hover(ADD)/pushed/disabled
  plates = ART .. "plates.tga",  -- 128x128; seat plate top half, active-glow halo bottom half
  panelbg = ART .. "panelbg.tga",-- 256x256 dark cloth for panel backdrops
  -- card-atlas cell geometry — MUST stay in sync with art/build_cards.sh.
  cell = { w = 78, h = 114, atlas = 1024 },
  -- master switch for ALL art (cards, felt, chips, dealer): set false to force every
  -- visual back to its built-in/text fallback, deterministically (no probe involved).
  enabled = true,
  -- narrower switch: set false to force the original vector/text card rendering only.
  useCardArt = true,
  -- TGA vertical-origin toggle. ImageMagick can emit a bottom-up .tga; if the cards
  -- (or back) look upside-down / row-reversed in-client, set this true — it samples
  -- each cell vertically mirrored, correcting a bottom-up atlas without a rebuild.
  -- (The permanent fix is to re-export the atlas flipped: see art/build_cards.sh.)
  flipV = false,
}

-- Is a texture usable? (cached per path.) The addon SHIPS its .tga files, so the probe's
-- job is to avoid a hard failure on a broken install, NOT to second-guess a normal one:
-- it returns true unless it gets a *definitive* negative. Two signals, best-effort because
-- their exact 3.3.5a semantics can only be confirmed in-client:
--   * SetTexture(path) returns false on some clients when the file can't be loaded.
--   * GetTexture() nils out after a failed load on some clients (but echoes the path on
--     others, since file loading is deferred to first render) — so a nil is treated as a
--     negative, a non-nil as "present".
-- For a guaranteed, deterministic fallback regardless of these semantics, flip
-- W.ART.enabled = false (forces every visual to its built-in/text rendering).
-- Under the test stub every method is a truthy no-op, so this returns true and the art
-- path is exercised harmlessly; the tests stay green.
local _probe, _ok = nil, {}
function W.artOK(path)
  if not W.ART.enabled then return false end
  if _ok[path] ~= nil then return _ok[path] end
  if not _probe then _probe = CreateFrame("Frame", nil, UIParent); _probe:Hide() end
  local t = _probe:CreateTexture()
  local ret = t:SetTexture(path)
  local present
  if ret == false then
    present = false                                   -- definitive: client reported load failure
  elseif t.GetTexture then
    present = (t:GetTexture() ~= nil)                 -- nil => failed load (on clients that nil it)
  else
    present = true
  end
  if t.SetTexture then t:SetTexture(nil) end
  _ok[path] = present and true or false
  return _ok[path]
end

-- ---- animation -------------------------------------------------------------
-- A tiny tween engine. Era-correct (3.3.5a OnUpdate, no AnimationGroups), driven by ONE
-- hidden frame so it never hijacks a widget's own OnUpdate (e.g. the table's glow pulse).
-- Interpolates alpha / scale / width / a point-offset slide over `dur` seconds after an
-- optional `delay`, with easing + an onDone hook. Set W.ANIM.enabled = false to make every
-- transition instant. Under the test stub the setters are no-ops, so tweens still run and
-- clear harmlessly; their lifecycle is asserted via frame._tw.
W.ANIM = {
  enabled = true,
  deal    = 0.22,   -- card deal-in duration (s)
  stagger = 0.07,   -- gap between successive dealt cards (s)
  flip    = 0.30,   -- back->face reveal flip duration (s)
  slide   = 16,     -- how far (px) a dealt card slides into its seat
}

local easing = {
  linear   = function(p) return p end,
  outCubic = function(p) local f = 1 - p; return 1 - f * f * f end,
  inQuad   = function(p) return p * p end,
  outQuad  = function(p) return 1 - (1 - p) * (1 - p) end,
  -- a small overshoot so a dealt card "settles" with a touch of bounce
  outBack  = function(p) local s = 1.70158; local f = p - 1; return 1 + (s + 1) * f * f * f + s * f * f end,
}
W.easing = easing

local animator, active = nil, {}

local function applyAt(tw, e)
  local f = tw.frame
  if tw.a0 and f.SetAlpha then f:SetAlpha(tw.a0 + (tw.a1 - tw.a0) * e) end
  if tw.s0 and f.SetScale then f:SetScale(tw.s0 + (tw.s1 - tw.s0) * e) end
  if tw.w0 and f.SetWidth then f:SetWidth(tw.w0 + (tw.w1 - tw.w0) * e) end
  if tw.pt and f.SetPoint then
    f:SetPoint(tw.pt.p, tw.pt.rel, tw.pt.rp, tw.pt.x, tw.pt.y + tw.slide * (1 - e))
  end
end

local function stepAnimator(_, elapsed)
  for i = #active, 1, -1 do                          -- reverse: safe to remove / append (onDone)
    local tw = active[i]
    tw.t = tw.t + (elapsed or 0)
    if tw.t >= 0 then
      local p = (tw.dur > 0) and (tw.t / tw.dur) or 1
      if p > 1 then p = 1 end
      applyAt(tw, tw.ease and tw.ease(p) or p)
      if p >= 1 then
        table.remove(active, i)
        if tw.frame then tw.frame._tw = nil end
        if tw.onDone then tw.onDone(tw.frame) end
      end
    end
  end
  if #active == 0 and animator and animator.Hide then animator:Hide() end
end

-- cancel any in-flight tween on a frame (and drop it from the driver)
function W.stopTween(frame)
  if not frame then return end
  for i = #active, 1, -1 do if active[i].frame == frame then table.remove(active, i) end end
  frame._tw = nil
end

function W.tween(frame, o)
  if not frame then return end
  o = o or {}
  if not W.ANIM.enabled then                         -- instant: jump to end state, fire onDone
    if o.toAlpha and frame.SetAlpha then frame:SetAlpha(o.toAlpha) end
    if o.toScale and frame.SetScale then frame:SetScale(o.toScale) end
    if o.toWidth and frame.SetWidth then frame:SetWidth(o.toWidth) end
    if o.onDone then o.onDone(frame) end
    return
  end
  if not animator then
    animator = CreateFrame("Frame", nil, UIParent)
    -- real geometry so the driver's OnUpdate ticks unambiguously: with animations on, the
    -- table + dealt cards prime to alpha 0 and rely on this tick to become visible.
    if animator.SetSize then animator:SetSize(1, 1) end
    if animator.SetPoint then animator:SetPoint("CENTER") end
    animator:SetScript("OnUpdate", stepAnimator)
  end
  W.stopTween(frame)
  local tw = {
    frame = frame, t = -(o.delay or 0), dur = o.dur or 0.2, ease = o.ease, onDone = o.onDone,
    a0 = o.fromAlpha, a1 = o.toAlpha, s0 = o.fromScale, s1 = o.toScale,
    w0 = o.fromWidth, w1 = o.toWidth,
  }
  if o.slide and frame.GetPoint and frame.SetPoint then
    if not frame._homePt then                              -- cache the resting point ONCE (Table
      local p, rel, rp, x, y = frame:GetPoint(1)           -- anchors each card exactly once) so an
      if type(x) == "number" and type(y) == "number" then  -- interrupted slide can't drift "home"
        frame._homePt = { p = p, rel = rel, rp = rp, x = x, y = y }
      end
    end
    if frame._homePt then tw.pt = frame._homePt; tw.slide = o.slide end
  end
  frame._tw = tw
  applyAt(tw, 0)                                      -- prime the start state (no end-frame flash)
  active[#active + 1] = tw
  if animator.Show then animator:Show() end
end

-- ---- card widget ----------------------------------------------------------
-- W.useSuitGlyphs: try Unicode pips (♠♥♦♣); falls back to letters if the client
-- font can't render them. Default to letters for guaranteed legibility on 3.3.5a.
W.useSuitGlyphs = false
local SUIT_GLYPH = { [0] = "\226\153\163", "\226\153\166", "\226\153\165", "\226\153\160" } -- c d h s
local function suitMark(suit) return W.useSuitGlyphs and SUIT_GLYPH[suit] or Const.SUIT_NAMES[suit]:upper() end
local function suitCol(suit) return (suit == 1 or suit == 2) and W.COL.red or W.COL.black end

-- Atlas texcoords for grid cell (col, row): col = rank0 (0=Two..12=Ace), row = suit
-- (0=clubs,1=diamonds,2=hearts,3=spades); the back is at col 0, row 4. A half-texel
-- inset stops neighbouring cells bleeding in under bilinear filtering.
local function cellCoords(col, row)
  local cw, ch, a = W.ART.cell.w, W.ART.cell.h, W.ART.cell.atlas
  local ins = 0.5 / a
  local l, r = (col * cw) / a + ins, (col * cw + cw) / a - ins
  local t, b = (row * ch) / a + ins, (row * ch + ch) / a - ins
  if W.ART.flipV then return l, r, 1 - t, 1 - b end
  return l, r, t, b
end

local function cardArtOn() return W.ART.useCardArt and W.artOK(W.ART.cards) end

function W.card(parent, w, h)
  w, h = w or 36, h or 50
  local card = CreateFrame("Frame", nil, parent)
  card:SetWidth(w); card:SetHeight(h)
  card._w = w
  card.border = W.fill(card, "BACKGROUND", { 0, 0, 0 }, 1)
  card.face = card:CreateTexture(nil, "BORDER")
  card.face:SetPoint("TOPLEFT", 1, -1); card.face:SetPoint("BOTTOMRIGHT", -1, 1)
  card.corner = W.label(card, "", "GameFontNormalSmall"); card.corner:SetPoint("TOPLEFT", 3, -2)
  card.big = W.label(card, "", "GameFontNormalLarge"); card.big:SetPoint("CENTER", 0, -2)

  -- the text/colored-box fallback overlay: shown only when sprite art is unavailable
  local function showText(self, rank, col)
    self.corner:SetText(rank .. suitMark(self._suit)); self.corner:SetTextColor(c4(col))
    self.big:SetText(rank); self.big:SetTextColor(c4(col))
    self.corner:Show(); self.big:Show()
  end
  local function hideText(self)
    self.corner:SetText(""); self.big:SetText("")
    if self.corner.Hide then self.corner:Hide() end
    if self.big.Hide then self.big:Hide() end
  end

  -- draw the face for a key (a card id, "back", or "empty"); no animation, idempotent.
  local function render(self, key)
    if type(key) == "number" then
      local rank0 = math.floor(key / 4); self._suit = key % 4
      if cardArtOn() then
        self.face:SetTexture(W.ART.cards)
        if self.face.SetVertexColor then self.face:SetVertexColor(1, 1, 1) end
        self.face:SetTexCoord(cellCoords(rank0, self._suit)); hideText(self)
      else
        self.face:SetTexCoord(0, 1, 0, 1); self.face:SetTexture(c4(W.COL.cream))
        showText(self, Const.RANK_NAMES[rank0], suitCol(self._suit))
      end
    elseif key == "back" then
      if cardArtOn() then
        self.face:SetTexture(W.ART.cards)
        if self.face.SetVertexColor then self.face:SetVertexColor(1, 1, 1) end
        self.face:SetTexCoord(cellCoords(0, 4)); hideText(self)         -- back: col 0, row 4
      else
        self.face:SetTexCoord(0, 1, 0, 1); self.face:SetTexture(0.13, 0.20, 0.52, 1); hideText(self)
      end
    else                                                                 -- "empty"
      -- a faint slot marker, not a black box (it sits on the felt's board inlay)
      self.face:SetTexCoord(0, 1, 0, 1); self.face:SetTexture(0, 0, 0, 0.14); hideText(self)
    end
    if self.border.SetAlpha then self.border:SetAlpha(key == "empty" and 0.25 or 1) end
  end

  -- cancel any running tween and return to the resting transform (incl. the slide point,
  -- so a deal interrupted mid-slide snaps home instead of leaving the card offset)
  local function resetTransform(self)
    W.stopTween(self)
    if self.SetAlpha then self:SetAlpha(1) end
    if self.SetScale then self:SetScale(1) end
    if self.SetWidth then self:SetWidth(self._w) end
    if self._homePt and self.SetPoint then
      local h = self._homePt; self:SetPoint(h.p, h.rel, h.rp, h.x, h.y)
    end
  end

  function card:_dealIn(delay, onDone)
    W.tween(self, {
      delay = delay or 0, dur = W.ANIM.deal, ease = easing.outBack,
      fromAlpha = 0, toAlpha = 1, fromScale = 0.6, toScale = 1, slide = W.ANIM.slide, onDone = onDone,
    })
  end

  -- width squash with a face swap at the midpoint => a card turning over
  function card:_flip(swapFn)
    local half = W.ANIM.flip * 0.5
    W.tween(self, {
      dur = half, ease = easing.inQuad, fromWidth = self._w, toWidth = 2,
      onDone = function(s)
        if swapFn then swapFn() end
        W.tween(s, { dur = half, ease = easing.outQuad, fromWidth = 2, toWidth = s._w })
      end,
    })
  end

  -- show `key`, animating only on an actual change. `delay` staggers a fresh deal.
  function card:_show(key, delay)
    if self._shownKey == key then self:Show(); return end   -- unchanged: nothing to redraw/animate
    local prev = self._shownKey
    self._shownKey = key
    if not W.ANIM.enabled then render(self, key); resetTransform(self); self:Show(); return end
    if prev == "back" and type(key) == "number" then         -- reveal a face-down card: flip it
      self:_flip(function() render(self, key) end)
    elseif self.flipReveal and type(key) == "number" then     -- your hole cards: deal face-down, turn up
      render(self, "back")
      self:_dealIn(delay, function() self:_flip(function() render(self, key) end) end)
    else                                                      -- community card / placement: slide in
      render(self, key); self:_dealIn(delay)
    end
    self:Show()
  end

  function card:setCard(id, delay) self:_show(id, delay) end
  function card:setBack(delay)     self:_show("back", delay) end
  function card:setEmpty()
    self._shownKey = "empty"
    render(self, "empty")
    resetTransform(self)
    self:Show()
  end

  card:setEmpty()
  return card
end

ns.W = W

-- ---- aggregator -----------------------------------------------------------
ns.UI = ns.UI or { panels = {} }
function ns.UI.register(fn) ns.UI.panels[#ns.UI.panels + 1] = fn end
-- static labels (set once at build) re-apply here when the language changes;
-- everything painted in a refresh() picks the new language up automatically
ns.UI.relabelFns = ns.UI.relabelFns or {}
function ns.UI.onRelabel(fn) ns.UI.relabelFns[#ns.UI.relabelFns + 1] = fn; fn() end
function ns.UI.relabel()
  for i = 1, #ns.UI.relabelFns do pcall(ns.UI.relabelFns[i]) end
end
function ns.UI.refresh(session)
  local view = ns.UI.viewOf(session)
  for i = 1, #ns.UI.panels do
    local ok, err = pcall(ns.UI.panels[i], view, session)
    if not ok and ns.Log then ns.Log.debug("UI panel error: " .. tostring(err)) end
  end
end

-- a render-friendly view of a Host (full table) or Client (public mirror)
function ns.UI.viewOf(s)
  if not s then return nil end
  local v = {
    me = s.me, phase = s.phase, aborted = s.aborted, cheat = s.cheat,
    holeVerified = s.holeVerified, auditPassed = s.auditPassed, sealed = s.S ~= nil,
    -- fairness-report states: each gate only counts once it actually PASSED —
    -- "sealed" alone used to light rows whose checks hadn't run yet
    deckCommitted = s.deckCommits ~= nil,
    resumed = s.resumed or nil,           -- mid-hand rejoin: reduced guarantee this hand
    board = {}, hole = {},
  }
  -- the cross-client same-deck gate has passed once the session moved beyond the
  -- statehash barrier (host: dealt+betting; client: deal phase) on witnessed state
  v.crossChecked = (not s.resumed)
    and (s.phase == "betting" or s.phase == "deal" or s.phase == "done") or false
  if s.dealer then
    v.isHost = true
    local r = s.dealer.rules
    v.toAct, v.street, v.pot, v.seats = r.toAct, r.street, 0, {}
    v.button = r.order and r.buttonPos and r.order[r.buttonPos] or nil
    for i = 1, #s.seats do
      local p = r.seats[s.seats[i]]
      v.pot = v.pot + p.total
      v.seats[i] = { id = s.seats[i], stack = p.stack, bet = p.committed, folded = p.folded, allIn = p.allIn }
    end
    local bc = s.dealer.variant.boardSchedule[s.revealedStreet] or 0
    v.board = s.dealer:boardCards(bc)
    if s.playing ~= false then                     -- an eliminated dealer has no cards
      local hr = s.dealer:holeReveal(s.me)
      for i = 1, #hr do v.hole[i] = hr[i].val end
    end
    v.deltas, v.showdown = s.deltas, s.showdown    -- end-of-hand result (phase "done")
    if r.toAct and not r.complete then             -- live countdown (host has exact ticks)
      v.turnLeft = math.max(0, (s.turnTimeout or 0) - (s.turnTicks or 0))
    end
    v.myTurn = (r.toAct == s.me)
    if v.myTurn and s.legalForMe then
      local la = s:legalForMe()
      if la then
        v.toCall, v.canCheck = la.toCall, la.canCheck
        v.canBet, v.minBet, v.maxBet = la.canBet, la.minBetTo, la.maxBetTo
        v.canRaise, v.minRaise, v.maxRaise = la.canRaise, la.minRaiseTo, la.maxRaiseTo
      end
    end
  else
    v.toAct = s.toActSeat
    v.pot = s.pot or 0                    -- live pot total (from BET_TURN / SNAPSHOT)
    v.turnTimeout = s.turnTimeout         -- countdown base (UI tracks elapsed locally)
    if s.seats then
      v.seats = {}
      for i = 1, #s.seats do
        local id = s.seats[i]
        v.seats[i] = { id = id, folded = s.folded and s.folded[id] or false,
                       stack = s.stacks and s.stacks[id],    -- live (refreshed every turn)
                       bet = s.bets and s.bets[id] }         -- current street commitment
      end
    end
    if s.board then for i = 1, #s.board do v.board[i] = s.board[i].val end end
    if s.hole then for i = 1, #s.hole do v.hole[i] = s.hole[i].val end end
    -- clients aren't told the street explicitly; the board size implies it
    v.street = (#v.board >= 5 and 3) or (#v.board == 4 and 2) or (#v.board == 3 and 1) or 0
    v.myTurn = s.prompt ~= nil
    if s.prompt then
      local p = s.prompt
      v.toCall = p.toCall
      v.canCheck = (p.canCheck ~= nil) and p.canCheck or (v.toCall == 0)
      -- the host's EXACT flags (a BB facing callers has toCall=0 but must RAISE,
      -- not BET); fall back to the old toCall inference only for pre-flag hosts
      if p.canBet ~= nil or p.canRaise ~= nil then
        v.canBet, v.canRaise = p.canBet or false, p.canRaise or false
      else
        v.canBet, v.canRaise = (v.toCall == 0), (v.toCall > 0)
      end
      v.minBet, v.maxBet = p.minTo or p.minRaise, p.maxTo
      v.minRaise, v.maxRaise = p.minTo, p.maxTo
    end
    v.refused = s.lastRefuse              -- why the host rejected our last action (if it did)
    v.deltas, v.showdown = s.deltas, s.showdown
    v.spectating = s.spectating           -- watching, not seated (no controls)
    v.boardVerified = s.boardVerified     -- spectator: revealed cards checked OK
    v.unverified = s.unverified           -- spectator: missed a broadcast this hand
  end
  -- best-hand name once we can make 5 (nice "Pair of Kings" readout)
  if #v.hole >= 2 and (#v.hole + #v.board) >= 5 and ns.HandEval then
    local all = {}
    for i = 1, #v.hole do all[#all + 1] = v.hole[i] end
    for i = 1, #v.board do all[#all + 1] = v.board[i] end
    local ok, score = pcall(ns.HandEval.evaluate, all)
    if ok then local ok2, name = pcall(ns.HandEval.describe, score); if ok2 then v.handName = name end end
  end
  return v
end

return W
