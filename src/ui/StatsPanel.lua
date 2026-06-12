--[[ StatsPanel.lua — your lifetime poker record + achievements (/azh stats or the
  lobby's Stats button). Pure display over ns.stats' store; refreshed on open. ]]

local ADDON, ns = ...
local W = ns.W
local L = ns.L
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local panel, rows

local function build()
  local nAch = #ns.Stats.ACHIEVEMENTS
  panel = W.panel(UIParent, 360, 240 + nAch * 17, L["Your Poker Record"], true)
  panel:SetPoint("CENTER", -200, 0)

  local function line(y, font)
    local fs = W.label(panel, "", font or "GameFontHighlightSmall", "LEFT")
    fs:SetPoint("TOPLEFT", 16, y); fs:SetWidth(330); fs:SetHeight(12)
    return fs
  end
  panel.hands  = line(-32)
  panel.net    = line(-50)
  panel.big    = line(-68)
  panel.best   = line(-86)
  panel.bluff  = line(-104)
  panel.sng    = line(-122)
  panel.meta   = line(-140)

  panel.achHead = W.label(panel, L["Achievements"], "GameFontNormal", "LEFT")
  panel.achHead:SetPoint("TOPLEFT", 16, -166)
  rows = {}
  for i = 1, nAch do
    local r = {}
    r.icon = W.tex(panel, "ARTWORK", W.ICON.waiting)
    r.icon:SetWidth(13); r.icon:SetHeight(13)
    r.icon:SetPoint("TOPLEFT", 16, -188 - (i - 1) * 17)
    r.text = W.label(panel, "", "GameFontHighlightSmall", "LEFT")
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.text:SetWidth(310); r.text:SetHeight(12)
    rows[i] = r
  end

  ns.UI.onRelabel(function()                       -- language switch: static labels
    if panel.titleText then panel.titleText:SetText(L["Your Poker Record"]) end
    panel.achHead:SetText(L["Achievements"])
  end)

  panel:Hide()
  ns.UI.statsPanel = panel
end

function ns.UI.showStats()
  if not panel then return end
  local s = (ns.stats and ns.stats.s) or {}
  local hands, wins = s.hands or 0, s.wins or 0
  local rate = hands > 0 and math.floor(wins * 100 / hands + 0.5) or 0
  panel.hands:SetText(L["Hands: %s played, %s won (%d%%) — best streak %s"]:format(
    W.commas(hands), W.commas(wins), rate, W.commas(s.bestStreak or 0)))
  local net = s.net or 0
  panel.net:SetText(L["Net chips: "] .. (net >= 0 and ("|cff40d940+" .. W.commas(net) .. "|r")
    or ("|cffff5555-" .. W.commas(-net) .. "|r")))
  panel.big:SetText(L["Biggest single-hand win: %s"]:format(W.commas(s.biggestWin or 0)))
  panel.best:SetText(L["Best hand made: %s"]:format(s.bestHandName or "—"))
  panel.bluff:SetText(L["Showdowns won: %s   ·   uncontested (bluff) wins: %s"]:format(
    W.commas(s.showdownWins or 0), W.commas(s.bluffWins or 0)))
  panel.sng:SetText(L["Sit & Gos: %s played, %s won%s"]:format(
    W.commas(s.sngPlayed or 0), W.commas(s.sngWon or 0),
    s.sngBest and L["  (best finish: %d)"]:format(s.sngBest) or ""))
  panel.meta:SetText(L["Hands dealt as host: %s   ·   hands verified clean: %s"]:format(
    W.commas(s.hosted or 0), W.commas(s.audited or 0)))

  local unlocked = s.unlocked or {}
  for i, a in ipairs(ns.Stats.ACHIEVEMENTS) do
    local r = rows[i]
    local got = unlocked[a.id]
    r.icon:SetTexture(got and W.ICON.ready or W.ICON.waiting)
    r.text:SetText(got and ("|cffffd95c" .. a.name .. "|r — " .. a.desc)
      or ("|cff888888" .. a.name .. " — " .. a.desc .. "|r"))
  end
  panel:Show()
end

build()
return ns.UI.statsPanel
