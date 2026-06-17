--[[ LeaderboardPanel.lua — the guild Sit&Go leaderboard (/azh top, or the Stats
  panel's "Guild Leaderboard" button). Pure display over ns.leaderboard's ranking.

  Columns are SEPARATE anchored FontStrings (rank+name left, three right-justified
  number columns) — WoW's default font is proportional, so space-padded columns
  would never line up. ]]

local ADDON, ns = ...
local W = ns.W
local L = ns.L
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local panel, rows
local ROWS = 12
-- right edges of the three number columns (x from the panel's left)
local COL_WON, COL_CASH, COL_PLAYED = 224, 274, 324

local function build()
  panel = W.panel(UIParent, 340, 132 + ROWS * 18, L["Guild Leaderboard"], true)
  panel:SetPoint("CENTER", -120, 0)

  panel.sub = W.label(panel, "", "GameFontDisableSmall", "LEFT")
  panel.sub:SetPoint("TOPLEFT", 16, -30); panel.sub:SetWidth(308)

  -- column headers (gold), aligned to the same right edges as the rows
  local function head(text, justify, x, rightEdge)
    local fs = W.label(panel, "", "GameFontNormalSmall", justify)
    if rightEdge then fs:SetPoint("TOPRIGHT", panel, "TOPLEFT", rightEdge, -50)
    else fs:SetPoint("TOPLEFT", x, -50) end
    fs:SetTextColor(rgba(W.COL.gold))
    return fs
  end
  panel.hPlayer = head(nil, "LEFT", 16)
  panel.hWon    = head(nil, "RIGHT", nil, COL_WON)
  panel.hCash   = head(nil, "RIGHT", nil, COL_CASH)
  panel.hPlayed = head(nil, "RIGHT", nil, COL_PLAYED)

  rows = {}
  for i = 1, ROWS do
    local y = -68 - (i - 1) * 18
    local r = {}
    r.name = W.label(panel, "", "GameFontHighlightSmall", "LEFT")
    r.name:SetPoint("TOPLEFT", 16, y); r.name:SetWidth(190); r.name:SetHeight(14)
    r.won = W.label(panel, "", "GameFontHighlightSmall", "RIGHT")
    r.won:SetPoint("TOPRIGHT", panel, "TOPLEFT", COL_WON, y); r.won:SetWidth(46)
    r.cash = W.label(panel, "", "GameFontHighlightSmall", "RIGHT")
    r.cash:SetPoint("TOPRIGHT", panel, "TOPLEFT", COL_CASH, y); r.cash:SetWidth(46)
    r.played = W.label(panel, "", "GameFontHighlightSmall", "RIGHT")
    r.played:SetPoint("TOPRIGHT", panel, "TOPLEFT", COL_PLAYED, y); r.played:SetWidth(46)
    rows[i] = r
  end

  panel.empty = W.label(panel, "", "GameFontDisableSmall", "LEFT")
  panel.empty:SetPoint("TOPLEFT", 16, -72); panel.empty:SetWidth(308)

  panel.foot = W.label(panel, "", "GameFontDisableSmall", "LEFT")
  panel.foot:SetPoint("BOTTOMLEFT", 16, 12); panel.foot:SetWidth(308)

  ns.UI.onRelabel(function()                       -- language switch: static labels
    if panel.titleText then panel.titleText:SetText(L["Guild Leaderboard"]) end
    panel.sub:SetText(L["Sit & Go results seen on this floor."])
    panel.hPlayer:SetText(L["Player"])
    panel.hWon:SetText(L["Won"]); panel.hCash:SetText(L["Cashed"]); panel.hPlayed:SetText(L["Played"])
    panel.foot:SetText(L["Observed live — not a verified ranking. /azh top reset to clear."])
  end)

  panel:Hide()
  ns.UI.leaderboardPanel = panel
end

function ns.UI.showLeaderboard()
  if not panel then return end
  local rank = (ns.leaderboard and ns.leaderboard:ranking()) or {}
  panel.empty:SetText(#rank == 0 and L["No tournaments seen yet — host or watch a Sit & Go!"] or "")
  local me = (type(UnitName) == "function" and UnitName("player")) or nil
  for i = 1, ROWS do
    local r, e = rows[i], rank[i]
    if e then
      local nm = e.name
      if #nm > 22 then nm = nm:sub(1, 21) .. "…" end
      local mine = (e.name == me)
      local g = mine and "|cffffd95c" or ""
      local gz = mine and "|r" or ""
      r.name:SetText(g .. i .. ". " .. nm .. gz)
      r.won:SetText(g .. W.commas(e.wins) .. gz)
      r.cash:SetText(g .. W.commas(e.cashes) .. gz)
      r.played:SetText(g .. W.commas(e.played) .. gz)
    else
      r.name:SetText(""); r.won:SetText(""); r.cash:SetText(""); r.played:SetText("")
    end
  end
  panel:Show()
end

build()
return ns.UI.leaderboardPanel
