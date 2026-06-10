--[[ LobbyPanel.lua — the casino floor: a live list of tables (name, seats, blinds)
  with a Sit button each, plus Open Table / Stand. Shown via /azh lobby. ]]

local ADDON, ns = ...
local W = ns.W
local COL = W.COL
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local panel, rows
local ROWS = 8

local function build()
  panel = W.panel(UIParent, 330, 290, "Casino — Tables", true)
  panel:SetPoint("CENTER", 240, 0)

  rows = {}
  for i = 1, ROWS do
    local rf = CreateFrame("Frame", nil, panel)
    rf:SetWidth(300); rf:SetHeight(24); rf:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 26)
    rf.stripe = rf:CreateTexture(nil, "BACKGROUND")
    rf.stripe:SetAllPoints(rf); rf.stripe:SetTexture(rgba(COL.feltLt, (i % 2 == 0) and 0.12 or 0.04))
    rf.label = W.label(rf, "", "GameFontHighlightSmall", "LEFT"); rf.label:SetPoint("LEFT", 6, 0); rf.label:SetWidth(220)
    rf.btn = W.button(rf, "Sit"); rf.btn:SetWidth(44); rf.btn:SetHeight(20); rf.btn:SetPoint("RIGHT", -2, 0); rf.btn:Hide()
    rf:Hide()
    rows[i] = rf
  end

  panel.empty = W.label(panel, "No tables yet — open one!", "GameFontDisableSmall")
  panel.empty:SetPoint("TOP", 0, -40)

  panel.open = W.button(panel, "Open Table", function() if ns.onSlash then ns.onSlash("open") end end)
  panel.open:SetPoint("BOTTOMLEFT", 10, 10); panel.open:SetWidth(100)
  panel.stand = W.button(panel, "Stand", function() if ns.onSlash then ns.onSlash("stand") end end)
  panel.stand:SetPoint("LEFT", panel.open, "RIGHT", 6, 0); panel.stand:SetWidth(70)

  panel:Hide()
  ns.UI.lobbyPanel = panel
end

function ns.UI.showLobby() if panel then panel:Show() end end

local function refresh()
  if not panel then return end
  if panel.IsShown and not panel:IsShown() then return end
  local list = (ns.casino and ns.casino:tables()) or {}
  panel.empty:SetText(#list == 0 and "No tables yet — open one!" or "")
  for i = 1, ROWS do
    local rf, t = rows[i], list[i]
    if t then
      rf:Show()
      rf.label:SetText(string.format("|cffffd966%s|r   %d/%d   blinds %s/%s",
        t.name or t.tableId, t.taken, t.seatMax, W.commas(t.sb), W.commas(t.bb)))
      rf.btn:Show()
      rf.btn:SetScript("OnClick", function() if ns.onSlash then ns.onSlash("sit " .. t.tableId) end end)
    else
      rf:Hide()
    end
  end
end

build()
ns.UI.register(refresh)
return ns.UI.lobbyPanel
