--[[ LobbyPanel.lua — THE casino window (the addon's single entry point, /azh).

  Built for average players: pick who you play with (Guild / Group), see every open
  table with seats + blinds, click Join (greyed "Full" when there's no space), or
  create your own with two blind boxes and one button. Leave / Close where relevant.
  Everything else (the felt table, the action bar) appears on its own during play. ]]

local ADDON, ns = ...
local W = ns.W
local COL = W.COL
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local panel, rows
local ROWS = 6

local function casino() return ns.casino end

local function setMode(m)
  if not ns.setCasinoMode then return end
  local ok, err = ns.setCasinoMode(m)
  if not ok then if ns.Log then ns.Log.error("Can't switch: " .. tostring(err)) end return end
  if ns.onSlash then ns.onSlash("lobby") end          -- re-enter the floor on the new channel
end

local function build()
  panel = W.panel(UIParent, 380, 470, "Azeroth Hold'em — Casino", true)
  panel:SetPoint("CENTER", 330, 0)    -- clear of the table window (560 wide at CENTER)

  -- who you play with
  panel.modeL = W.label(panel, "Play with:", "GameFontNormal")
  panel.modeL:SetPoint("TOPLEFT", 14, -32)
  panel.modeGuild = W.button(panel, "Guild", function() setMode("GUILD") end)
  panel.modeGuild:SetWidth(74); panel.modeGuild:SetPoint("LEFT", panel.modeL, "RIGHT", 10, 0)
  panel.modeGroup = W.button(panel, "Group", function() setMode("GROUP") end)
  panel.modeGroup:SetWidth(74); panel.modeGroup:SetPoint("LEFT", panel.modeGuild, "RIGHT", 6, 0)
  panel.refresh = W.button(panel, "Refresh", function()
    if casino() then casino():announce() end          -- cooldown-limited PING
  end)
  panel.refresh:SetWidth(70); panel.refresh:SetPoint("TOPRIGHT", -12, -32)

  -- the table list
  panel.listHead = W.label(panel, "Tables", "GameFontNormal")
  panel.listHead:SetPoint("TOPLEFT", 14, -64)
  rows = {}
  for i = 1, ROWS do
    local rf = CreateFrame("Frame", nil, panel)
    rf:SetWidth(352); rf:SetHeight(42); rf:SetPoint("TOPLEFT", 12, -82 - (i - 1) * 46)
    rf.stripe = rf:CreateTexture(nil, "BACKGROUND")
    rf.stripe:SetAllPoints(rf); rf.stripe:SetTexture(rgba(COL.feltLt, (i % 2 == 0) and 0.12 or 0.05))
    rf.label = W.label(rf, "", "GameFontHighlightSmall", "LEFT")
    rf.label:SetPoint("TOPLEFT", 6, -5); rf.label:SetWidth(250)
    rf.players = W.label(rf, "", "GameFontDisableSmall", "LEFT")   -- who's seated
    rf.players:SetPoint("BOTTOMLEFT", 6, 5); rf.players:SetWidth(280)
    rf.btn = W.button(rf, "Join"); rf.btn:SetWidth(56); rf.btn:SetHeight(20); rf.btn:SetPoint("RIGHT", -2, 0)
    rf:Hide()
    rows[i] = rf
  end
  panel.empty = W.label(panel, "", "GameFontDisableSmall")
  panel.empty:SetPoint("TOPLEFT", 16, -86)

  -- your standing + actions
  panel.status = W.label(panel, "", "GameFontNormalSmall", "LEFT")
  panel.status:SetPoint("BOTTOMLEFT", 14, 76); panel.status:SetTextColor(rgba(COL.gold))
  panel.leave = W.button(panel, "Leave Table", function() if ns.onSlash then ns.onSlash("stand") end end)
  panel.leave:SetWidth(100); panel.leave:SetPoint("BOTTOMRIGHT", -12, 70); panel.leave:Hide()
  panel.closeT = W.button(panel, "Close Table", function() if ns.onSlash then ns.onSlash("close") end end)
  panel.closeT:SetWidth(100); panel.closeT:SetPoint("BOTTOMRIGHT", -12, 70); panel.closeT:Hide()

  -- create your own
  panel.createL = W.label(panel, "Create a table — blinds:", "GameFontNormal")
  panel.createL:SetPoint("BOTTOMLEFT", 14, 42)
  panel.sb = W.editbox(panel, 30); panel.sb:SetPoint("LEFT", panel.createL, "RIGHT", 10, 0); panel.sb:SetText("5")
  if panel.sb.SetJustifyH then panel.sb:SetJustifyH("CENTER") end
  panel.slash = W.label(panel, "/"); panel.slash:SetPoint("LEFT", panel.sb, "RIGHT", 4, 0)
  panel.bb = W.editbox(panel, 30); panel.bb:SetPoint("LEFT", panel.slash, "RIGHT", 8, 0); panel.bb:SetText("10")
  if panel.bb.SetJustifyH then panel.bb:SetJustifyH("CENTER") end
  panel.create = W.button(panel, "Create Table", function()
    local sb = tonumber(panel.sb:GetText()) or 5
    local bb = tonumber(panel.bb:GetText()) or (sb * 2)
    -- "-" = default name ("<You>'s Table"), so players can identify the host
    if ns.onSlash then ns.onSlash(string.format("open - %d %d", sb, bb)) end
    panel:Hide()                                    -- get out of the table window's way
  end)
  panel.create:SetWidth(110); panel.create:SetPoint("BOTTOMRIGHT", -12, 12)
  panel.hint = W.label(panel, "Tables deal automatically once 2+ players sit.", "GameFontDisableSmall")
  panel.hint:SetPoint("BOTTOMLEFT", 14, 16)

  panel:Hide()
  ns.UI.lobbyPanel = panel
end

function ns.UI.showLobby() if panel then panel:Show() end end
function ns.UI.toggleLobby()
  if not panel then return end
  if panel.IsShown and panel:IsShown() then panel:Hide() else panel:Show() end
end

local function refresh()
  if not panel then return end
  if panel.IsShown and not panel:IsShown() then return end
  local c = casino()
  local mode = (ns.getCasinoMode and ns.getCasinoMode()) or "GUILD"

  -- the active mode's button is "pressed" (disabled); the other is clickable
  if panel.modeGuild.SetText then
    panel.modeGuild:SetText(mode == "GUILD" and "[ Guild ]" or "Guild")
    panel.modeGroup:SetText(mode == "GROUP" and "[ Group ]" or "Group")
  end
  if panel.modeGuild.Enable then
    if mode == "GUILD" then panel.modeGuild:Disable(); panel.modeGroup:Enable()
    else panel.modeGuild:Enable(); panel.modeGroup:Disable() end
  end

  -- table list
  local list = (c and c:tables()) or {}
  panel.empty:SetText(#list == 0 and "No tables found — create one below, or Refresh." or "")
  local mySeat, hosting = c and c.seatedAt, c and c.tableHost ~= nil
  for i = 1, ROWS do
    local rf, t = rows[i], list[i]
    if t then
      rf:Show()
      rf.label:SetText(string.format("|cffffd966%s|r   %d/%d seats   blinds %s/%s",
        t.name or t.tableId, t.taken, t.seatMax, W.commas(t.sb), W.commas(t.bb)))
      -- who's at the table: from the ad (fresh) or the last SEAT broadcast we heard
      local names = t.players or (c and c.seats and c.seats[t.tableId])
      if names and #names > 0 then
        local shown = {}
        for k = 1, math.min(#names, 4) do shown[k] = names[k] end
        local line = table.concat(shown, ", ")
        if #names > 4 then line = line .. " +" .. (#names - 4) end
        rf.players:SetText("Playing: " .. line)
      else
        rf.players:SetText("Host: " .. t.tableId)
      end
      local full = (t.taken or 0) >= (t.seatMax or 9)
      local verMismatch = c and t.ver ~= c.ver      -- exact-release gate (nil = old host)
      if t.tableId == mySeat or (hosting and c.tableHost.id == t.tableId) then
        rf.btn:SetText("Here"); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
      elseif verMismatch then
        rf.btn:SetText("Update"); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
        rf.players:SetText("Different addon version (" .. (t.ver and ("v" .. t.ver) or "older")
          .. " vs your v" .. c.ver .. ") — install the same release.")
      elseif full then
        rf.btn:SetText("Full"); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
      else
        rf.btn:SetText("Join"); if rf.btn.Enable then rf.btn:Enable() end; rf.btn:Show()
        rf.btn:SetScript("OnClick", function()
          if ns.onSlash then ns.onSlash("sit " .. t.tableId) end
          panel:Hide()                              -- get out of the table window's way
        end)
      end
    else
      rf:Hide()
    end
  end

  -- standing + contextual buttons
  if hosting then
    panel.status:SetText("You are hosting (" .. #c.tableHost.order .. " seated).")
    panel.closeT:Show(); panel.leave:Hide()
    if panel.create.Disable then panel.create:Disable() end
  elseif mySeat then
    panel.status:SetText("Seated at " .. tostring(mySeat) .. "'s table.")
    panel.leave:Show(); panel.closeT:Hide()
    if panel.create.Disable then panel.create:Disable() end
  else
    panel.status:SetText("")
    panel.leave:Hide(); panel.closeT:Hide()
    if panel.create.Enable then panel.create:Enable() end
  end
end

build()
ns.UI.register(refresh)
return ns.UI.lobbyPanel
