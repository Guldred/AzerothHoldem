--[[ HostPanel.lua — quick controls: set blinds, host/join a single table, or open
  the casino floor. ]]

local ADDON, ns = ...
local W = ns.W
local panel

local function num(box, default) return tonumber(box:GetText()) or default end

local function build()
  panel = W.panel(UIParent, 250, 132, "Azeroth Hold'em", true)
  panel:SetPoint("TOPLEFT", 20, -20)

  panel.sbL = W.label(panel, "Blinds", "GameFontNormal")
  panel.sbL:SetPoint("TOPLEFT", 14, -30)
  panel.sb = W.editbox(panel, 38); panel.sb:SetPoint("LEFT", panel.sbL, "RIGHT", 8, 0); panel.sb:SetText("5")
  panel.slash = W.label(panel, "/"); panel.slash:SetPoint("LEFT", panel.sb, "RIGHT", 4, 0)
  panel.bb = W.editbox(panel, 38); panel.bb:SetPoint("LEFT", panel.slash, "RIGHT", 4, 0); panel.bb:SetText("10")

  panel.host = W.button(panel, "Host", function() if ns.onSlash then ns.onSlash("host " .. num(panel.sb, 5) .. " " .. num(panel.bb, 10)) end end)
  panel.host:SetPoint("TOPLEFT", 12, -58); panel.host:SetWidth(70)
  panel.join = W.button(panel, "Join", function() if ns.onSlash then ns.onSlash("join") end end)
  panel.join:SetPoint("LEFT", panel.host, "RIGHT", 4, 0); panel.join:SetWidth(70)
  panel.deal = W.button(panel, "Deal", function() if ns.onSlash then ns.onSlash("start") end end)
  panel.deal:SetPoint("LEFT", panel.join, "RIGHT", 4, 0); panel.deal:SetWidth(70)

  panel.lobby = W.button(panel, "Casino Lobby", function() if ns.onSlash then ns.onSlash("lobby") end end)
  panel.lobby:SetPoint("BOTTOM", 0, 12); panel.lobby:SetWidth(150)

  ns.UI.hostPanel = panel
end

build()
return ns.UI.hostPanel
