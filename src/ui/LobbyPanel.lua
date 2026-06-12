--[[ LobbyPanel.lua — THE casino window (the addon's single entry point, /azh).

  Built for average players: pick who you play with (Guild / Group), see every open
  table with seats + blinds, click Join (greyed "Full" when there's no space), or
  create your own with two blind boxes and one button. Leave / Close where relevant.
  Everything else (the felt table, the action bar) appears on its own during play. ]]

local ADDON, ns = ...
local W = ns.W
local L = ns.L
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
  panel = W.panel(UIParent, 380, 470, "Azeroth Hold'em — Casino  v" .. ns.Const.ADDON_VER, true)
  panel:SetPoint("CENTER", 330, 0)    -- clear of the table window (560 wide at CENTER)

  -- who you play with
  panel.modeL = W.label(panel, L["Play with:"], "GameFontNormal")
  panel.modeL:SetPoint("TOPLEFT", 14, -32)
  panel.modeGuild = W.button(panel, L["Guild"], function() setMode("GUILD") end)
  panel.modeGuild:SetWidth(74); panel.modeGuild:SetPoint("LEFT", panel.modeL, "RIGHT", 10, 0)
  panel.modeGroup = W.button(panel, L["Group"], function() setMode("GROUP") end)
  panel.modeGroup:SetWidth(74); panel.modeGroup:SetPoint("LEFT", panel.modeGuild, "RIGHT", 6, 0)
  panel.refresh = W.button(panel, L["Refresh"], function()
    if casino() then casino():announce() end          -- cooldown-limited PING
  end)
  panel.refresh:SetWidth(56); panel.refresh:SetPoint("TOPRIGHT", -12, -32)
  panel.stats = W.button(panel, L["Stats"], function()
    if ns.UI.showStats then ns.UI.showStats() end
  end)
  panel.stats:SetWidth(50); panel.stats:SetPoint("TOPRIGHT", -70, -32)

  -- the table list
  panel.listHead = W.label(panel, L["Tables"], "GameFontNormal")
  panel.listHead:SetPoint("TOPLEFT", 14, -64)
  rows = {}
  for i = 1, ROWS do
    local rf = CreateFrame("Frame", nil, panel)
    rf:SetWidth(352); rf:SetHeight(42); rf:SetPoint("TOPLEFT", 12, -82 - (i - 1) * 46)
    rf.stripe = rf:CreateTexture(nil, "BACKGROUND")
    rf.stripe:SetAllPoints(rf); rf.stripe:SetTexture(rgba(COL.feltLt, (i % 2 == 0) and 0.12 or 0.05))
    rf.label = W.label(rf, "", "GameFontHighlightSmall", "LEFT")
    rf.label:SetPoint("TOPLEFT", 6, -5); rf.label:SetWidth(250)
    rf.label:SetHeight(12)                       -- one line: clip, never wrap onto rf.players
    rf.players = W.label(rf, "", "GameFontDisableSmall", "LEFT")   -- who's seated
    rf.players:SetPoint("BOTTOMLEFT", 6, 5); rf.players:SetWidth(280)
    rf.btn = W.button(rf, L["Join"]); rf.btn:SetWidth(56); rf.btn:SetHeight(20); rf.btn:SetPoint("RIGHT", -2, 0)
    rf:Hide()
    rows[i] = rf
  end
  panel.empty = W.label(panel, "", "GameFontDisableSmall")
  panel.empty:SetPoint("TOPLEFT", 16, -86)

  -- your standing + actions. The status gets its OWN full-width row above the
  -- buttons — anchored next to them it overlapped "Need 2+"/"Close Table" the
  -- moment the text grew ("Waiting for players — 1 seated…", screenshot bug).
  -- Width + height are clamped so a long line clips instead of wandering.
  panel.status = W.label(panel, "", "GameFontNormalSmall", "LEFT")
  panel.status:SetPoint("BOTTOMLEFT", 14, 96)
  panel.status:SetWidth(352); panel.status:SetHeight(13)
  panel.status:SetTextColor(rgba(COL.gold))
  panel.leave = W.button(panel, L["Leave Table"], function() if ns.onSlash then ns.onSlash("stand") end end)
  panel.leave:SetWidth(100); panel.leave:SetPoint("BOTTOMRIGHT", -12, 70); panel.leave:Hide()
  panel.closeT = W.button(panel, L["Close Table"], function() if ns.onSlash then ns.onSlash("close") end end)
  panel.closeT:SetWidth(100); panel.closeT:SetPoint("BOTTOMRIGHT", -12, 70); panel.closeT:Hide()

  -- create your own
  panel.createL = W.label(panel, L["Create a table — blinds:"], "GameFontNormal")
  panel.createL:SetPoint("BOTTOMLEFT", 14, 42)
  panel.sb = W.editbox(panel, 30); panel.sb:SetPoint("LEFT", panel.createL, "RIGHT", 10, 0); panel.sb:SetText("5")
  if panel.sb.SetJustifyH then panel.sb:SetJustifyH("CENTER") end
  panel.slash = W.label(panel, "/"); panel.slash:SetPoint("LEFT", panel.sb, "RIGHT", 4, 0)
  panel.bb = W.editbox(panel, 30); panel.bb:SetPoint("LEFT", panel.slash, "RIGHT", 8, 0); panel.bb:SetText("10")
  if panel.bb.SetJustifyH then panel.bb:SetJustifyH("CENTER") end
  -- Sit & Go: equal stacks, blinds double every few hands, last one standing wins
  panel.sng = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  panel.sng:SetWidth(18); panel.sng:SetHeight(18)
  panel.sng:SetPoint("LEFT", panel.bb, "RIGHT", 12, 0)
  panel.sng._on = false
  panel.sng:SetScript("OnClick", function()
    panel.sng._on = not panel.sng._on
    if panel.sng.SetChecked then panel.sng:SetChecked(panel.sng._on) end
  end)
  panel.sngL = W.label(panel, "Sit&Go", "GameFontNormalSmall", "LEFT")
  panel.sngL:SetPoint("LEFT", panel.sng, "RIGHT", 1, 0)
  panel.create = W.button(panel, L["Create Table"], function()
    local sb = tonumber(panel.sb:GetText()) or 5
    local bb = tonumber(panel.bb:GetText()) or (sb * 2)
    if not ns.onSlash then return end
    -- "-" = default name ("<You>'s Table"), so players can identify the host.
    -- The lobby stays open: it is the waiting room until the host starts the game.
    if panel.sng._on then
      ns.onSlash(string.format("sng %d %d %d", (ns.db and ns.db.defaultStack) or 1000, sb, bb))
    else ns.onSlash(string.format("open - %d %d", sb, bb)) end
  end)
  panel.start = W.button(panel, L["Start Game"], function()
    if ns.onSlash then ns.onSlash("start") end
  end)
  panel.start:SetWidth(100); panel.start:SetPoint("BOTTOMRIGHT", -120, 70); panel.start:Hide()
  panel.create:SetWidth(110); panel.create:SetPoint("BOTTOMRIGHT", -12, 12)
  panel.hint = W.label(panel, L["Tables deal automatically once 2+ players sit."], "GameFontDisableSmall")
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
  local c = casino()
  -- track "a game is active for us" even while hidden, so reopening the lobby
  -- mid-game (via /azh) is not instantly re-hidden by the rising-edge check below
  local inGame = (c and ((c.client and c.client.seats) or
    (c.tableHost and c.tableHost.host and c.tableHost.host.phase ~= "done"))) and true or false
  if panel.IsShown and not panel:IsShown() then panel._inGame = inGame; return end
  local mode = (ns.getCasinoMode and ns.getCasinoMode()) or "GUILD"

  -- the active mode's button is "pressed" (disabled); the other is clickable
  if panel.modeGuild.SetText then
    panel.modeGuild:SetText(mode == "GUILD" and ("[ " .. L["Guild"] .. " ]") or L["Guild"])
    panel.modeGroup:SetText(mode == "GROUP" and ("[ " .. L["Group"] .. " ]") or L["Group"])
  end
  if panel.modeGuild.Enable then
    if mode == "GUILD" then panel.modeGuild:Disable(); panel.modeGroup:Enable()
    else panel.modeGuild:Enable(); panel.modeGroup:Disable() end
  end

  -- table list
  local list = (c and c:tables()) or {}
  panel.empty:SetText(#list == 0 and L["No tables found — create one below, or Refresh."] or "")
  local mySeat, hosting = c and c.seatedAt, c and c.tableHost ~= nil
  for i = 1, ROWS do
    local rf, t = rows[i], list[i]
    if t then
      rf:Show()
      rf.label:SetText(string.format("%s|cffffd966%s|r   %d/%d seats   blinds %s/%s",
        t.tourney and "|cff9ad0ff[S&G]|r " or "",
        t.name or t.tableId, t.taken, t.seatMax, W.commas(t.sb), W.commas(t.bb)))
      -- who's at the table: from the ad (fresh) or the last SEAT broadcast we heard
      local names = t.players or (c and c.seats and c.seats[t.tableId])
      if names and #names > 0 then
        local shown = {}
        for k = 1, math.min(#names, 4) do shown[k] = names[k] end
        local line = table.concat(shown, ", ")
        if #names > 4 then line = line .. " +" .. (#names - 4) end
        rf.players:SetText(L["Playing: "] .. line)
      else
        rf.players:SetText(L["Host: %s"]:format(t.tableId))
      end
      local full = (t.taken or 0) >= (t.seatMax or 9)
      local verMismatch = c and t.ver ~= c.ver      -- exact-release gate (nil = old host)
      if t.tableId == mySeat or (hosting and c.tableHost.id == t.tableId) then
        rf.btn:SetText(L["Here"]); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
      elseif verMismatch then
        rf.btn:SetText("Update"); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
        rf.players:SetText("Different addon version (" .. (t.ver and ("v" .. t.ver) or "older")
          .. " vs your v" .. c.ver .. ") — install the same release.")
      elseif c and c.watching == t.tableId then
        rf.btn:SetText(L["Watching"]); if rf.btn.Disable then rf.btn:Disable() end; rf.btn:Show()
      elseif (t.tourney and t.started) or full then
        -- can't sit (running Sit&Go / full table)? you can WATCH — unless you
        -- are busy hosting or sitting somewhere yourself
        rf.btn:SetText(L["Watch"]); rf.btn:Show()
        if hosting or mySeat then
          if rf.btn.Disable then rf.btn:Disable() end
        else
          if rf.btn.Enable then rf.btn:Enable() end
          rf.btn:SetScript("OnClick", function()
            if ns.onSlash then ns.onSlash("watch " .. t.tableId) end
          end)
        end
      else
        rf.btn:SetText(L["Join"]); if rf.btn.Enable then rf.btn:Enable() end; rf.btn:Show()
        rf.btn:SetScript("OnClick", function()
          if ns.onSlash then ns.onSlash("sit " .. t.tableId) end
          -- the lobby stays open as the waiting room; it tucks itself away when
          -- the game actually starts (see the rising-edge hide in refresh)
        end)
      end
    else
      rf:Hide()
    end
  end

  -- standing + contextual buttons
  if hosting then
    local th = c.tableHost
    if th.started then
      panel.status:SetText(L["You are hosting (%d seated)."]:format(#th.order))
      panel.start:Hide()
    else
      panel.status:SetText(L["Waiting for players — %d seated. Start when ready!"]:format(#th.order))
      panel.start:Show()
      if #th.order >= 2 then
        panel.start:SetText(L["Start Game"]); if panel.start.Enable then panel.start:Enable() end
      else
        panel.start:SetText(L["Need 2+"]); if panel.start.Disable then panel.start:Disable() end
      end
    end
    panel.closeT:Show(); panel.leave:Hide()
    if panel.create.Disable then panel.create:Disable() end
  elseif mySeat then
    local t = c.lobby:get(mySeat)
    if c.client and c.client.seats then
      panel.status:SetText(L["Seated at %s's table."]:format(tostring(mySeat)))
    else
      panel.status:SetText(L["Seated at %s — waiting for the host to start…"]
        :format(tostring((t and t.name) or mySeat)))
    end
    panel.start:Hide(); panel.leave:Show(); panel.closeT:Hide()
    if panel.create.Disable then panel.create:Disable() end
  elseif c and c.watching then
    local t = c.lobby:get(c.watching)
    panel.status:SetText(L["Watching %s — every hand is checked as you watch."]
      :format(tostring((t and t.name) or c.watching)))
    panel.start:Hide(); panel.leave:Hide(); panel.closeT:Hide()
    if panel.create.Enable then panel.create:Enable() end
  else
    panel.status:SetText("")
    panel.start:Hide(); panel.leave:Hide(); panel.closeT:Hide()
    if panel.create.Enable then panel.create:Enable() end
  end

  -- tuck the lobby away exactly when a game becomes active for us (rising edge
  -- only — reopening with /azh during play stays possible)
  if inGame and not panel._inGame then panel:Hide() end
  panel._inGame = inGame
end

build()
ns.UI.register(refresh)
return ns.UI.lobbyPanel
