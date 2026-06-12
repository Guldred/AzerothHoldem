--[[ Init.lua — WoW wiring + slash-command interface (the only broad WoW-API file).

  Boots the addon, bridges the era-correct 3.3.5a API to the proven pure core, and
  exposes a text interface (a graphical UI lives in src/ui/). 3.3.5-specific notes:
    * No RegisterAddonMessagePrefix (that's 4.1+): we register CHAT_MSG_ADDON and
      filter by our own prefix in the handler.
    * No C_Timer: Scheduler's OnUpdate is the heartbeat.
    * Gold cannot be moved by API: TRADE_* events only let us VERIFY a manual
      buy-in amount and record it in the Ledger.
]]

local ADDON, ns = ...
local Log = ns.Log

-- ---------------------------------------------------------------------------
-- entropy (best-effort; 3.3.5 math.random is weak, so mix several sources)
-- ---------------------------------------------------------------------------
local entropyCounter = 0
local function mixed()
  entropyCounter = entropyCounter + 1
  return ns.Rng.mixEntropy(GetTime(), time(), UnitName("player") or "?", entropyCounter, math.random())
end
local function genEntropy() return { r = mixed(), salt = mixed() } end
local function genNonces()
  local g = ns.Rng.fromSeed(mixed() .. mixed())
  local n = {}
  for i = 1, 52 do n[i] = g.bytes(16) end
  return n
end

-- ---------------------------------------------------------------------------
-- group helpers (era-correct 3.3.5 roster API)
-- ---------------------------------------------------------------------------
local function groupChannel()
  if GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers() > 0 then return "PARTY" end
  return "PARTY"   -- solo: degrades gracefully (used for local testing)
end

-- The casino floor's channel follows the player's chosen mode (saved per account):
--   GUILD (default): play with your guild — every guildmate computes the same channel
--     no matter their party/raid status, so ads and seating always reach each other.
--   GROUP: play with your current raid/party (for cross-guild groups).
local function casinoChannel()
  local mode = ns.db and ns.db.casinoMode
  if mode ~= "GROUP" and IsInGuild and IsInGuild() then return "GUILD" end
  if GetNumRaidMembers() > 0 then return "RAID" end
  return "PARTY"
end

-- switch Guild/Group mode: persisted, and the floor is re-entered on the new channel.
-- Blocked while hosting/seated (finish or leave your table first).
function ns.setCasinoMode(mode)
  if mode ~= "GUILD" and mode ~= "GROUP" then return false, "unknown mode" end
  if ns.db then ns.db.casinoMode = mode end
  if ns.casino then
    if ns.casino.tableHost then return false, "close your table first (/azh close)" end
    if ns.casino.seatedAt then return false, "stand up first (/azh stand)" end
    ns.casino = nil                  -- recreated on the new channel by ensureCasino
  end
  return true
end
function ns.getCasinoMode() return (ns.db and ns.db.casinoMode) or "GUILD" end

local function groupMembers()
  local me = UnitName("player")
  local seats = { me }
  local nr = GetNumRaidMembers()
  if nr > 0 then
    seats = {}
    for i = 1, nr do seats[#seats + 1] = (UnitName("raid" .. i)) or ("raid" .. i) end
  else
    local np = GetNumPartyMembers()
    for i = 1, np do seats[#seats + 1] = (UnitName("party" .. i)) end
  end
  return seats
end

-- ---------------------------------------------------------------------------
-- player class lookup (for the seat-plate class icons) — best-effort and cheap:
-- party/raid units first, then the guild roster, via a name->classToken map
-- rebuilt at most every 10s. Unknown players simply get no icon.
-- ---------------------------------------------------------------------------
local classMap, classMapAt = {}, -1e9
local function rebuildClassMap()
  classMap = {}
  if type(UnitName) == "function" and type(UnitClass) == "function" then
    local function add(unit)
      local n = UnitName(unit)
      if n then local _, tok = UnitClass(unit); classMap[n] = tok end
    end
    add("player")
    for i = 1, (type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 0) do add("raid" .. i) end
    for i = 1, (type(GetNumPartyMembers) == "function" and GetNumPartyMembers() or 0) do add("party" .. i) end
  end
  if type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    for i = 1, (GetNumGuildMembers() or 0) do
      -- 3.3.5 returns: name, rank, rankIndex, level, class(localized), zone, note,
      -- officernote, online, status, classFileName
      local n, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
      if n and classFile and not classMap[n] then classMap[n] = classFile end
    end
  end
end

function ns.classOf(name)
  if not name then return nil end
  local now = (type(GetTime) == "function" and GetTime()) or 0
  if now - classMapAt > 10 then classMapAt = now; rebuildClassMap() end
  return classMap[name]
end

-- ---------------------------------------------------------------------------
-- cheat banner
-- ---------------------------------------------------------------------------
local function onCheat(code, detail)
  Log.cheat(tostring(code) .. " — " .. tostring(detail))
  if ns.UI and ns.UI.showCheat then ns.UI.showCheat(code, detail) end
end

-- the session currently being PLAYED: the single-table session, or (in casino mode)
-- the table we're hosting / seated at. The table/action/trust panels render this.
local function activeSession()
  if ns.session then return ns.session end
  local c = ns.casino
  if c then return (c.tableHost and c.tableHost.host) or c.client end
  return nil
end
ns.activeSession = activeSession

-- ---------------------------------------------------------------------------
-- session lifecycle
-- ---------------------------------------------------------------------------
local function ensureComm()
  if ns.comm then return end
  ns.Scheduler.init()
  -- per-login epoch so a relog's msgids cannot collide with the ones peers remember
  local epoch = ns.Util.toBase36(math.floor((GetTime() or 0) * 100) % 1000000)
  ns.comm = ns.Transport.new({
    selfName = UnitName("player"),
    epoch = epoch,
    onWrongVersion = function(sender)
      Log.error(sender .. " is running an incompatible Azeroth Hold'em version — " ..
        "everyone should install the same (latest) release.")
    end,
    send = function(wire, channel, target) ns.Scheduler.queueSend(wire, channel, target) end,
    deliver = function(sender, payload, channel)
      -- casino mode routes tagged traffic; single-table mode goes straight to the session
      if ns.casino then ns.casino:onWire(sender, payload, channel)
      elseif ns.session then ns.session:onMessage(sender, payload, channel) end
    end,
  })
  ns.Scheduler.onTick(function() ns.comm:tick() end)
  -- Scheduler ticks fire every 0.1s; the casino's clock (ad intervals, lobby TTL,
  -- turn timeouts) is in SECONDS — tick it once per real second, not 10x too fast.
  local casinoTickAcc = 0
  ns.Scheduler.onTick(function()
    if not ns.casino then casinoTickAcc = 0; return end
    casinoTickAcc = casinoTickAcc + 1
    if casinoTickAcc >= 10 then casinoTickAcc = 0; ns.casino:tick(1) end
  end)
  ns.Scheduler.onTick(function() if ns.UI and ns.UI.refresh then ns.UI.refresh(activeSession()) end end)
end

local function startHost(sb, bb)
  ensureComm()
  ns.casino = nil                     -- single-table mode (the untouched, first-to-test path)
  local seats = groupMembers()
  local me = UnitName("player")
  local stacks = {}
  for _, s in ipairs(seats) do stacks[s] = (ns.db and ns.db.defaultStack) or 1000 end
  ns.handNo = (ns.handNo or 0) + 1
  ns.session = ns.Host.new({
    transport = ns.comm, selfName = me, seats = seats, stacks = stacks,
    buttonSeat = ns.db.button or me, sb = sb, bb = bb, handNo = ns.handNo, human = true,
    entropy = genEntropy(), nonces = genNonces(), broadcast = groupChannel(), onCheat = onCheat,
  })
  Log.info("Hosting: " .. #seats .. " seats, blinds " .. sb .. "/" .. bb .. ". /azh start to deal.")
end

local function joinTable()
  ensureComm()
  ns.casino = nil
  ns.session = ns.Client.new({
    transport = ns.comm, selfName = UnitName("player"), human = true,
    entropy = genEntropy(), broadcast = groupChannel(), onCheat = onCheat,
  })
  Log.info("Joined — waiting for the host to deal.")
end

-- ---------------------------------------------------------------------------
-- sit&go announcements + per-character record (SavedVariablesPerCharacter)
-- ---------------------------------------------------------------------------
local function ordinal(n)
  local r = n % 100
  if r >= 11 and r <= 13 then return n .. "th" end
  local last = n % 10
  return n .. (last == 1 and "st" or last == 2 and "nd" or last == 3 and "rd" or "th")
end

local function recordFinish(place)
  local t = ns.cdb and ns.cdb.tourney
  if not t then t = { played = 0, won = 0, places = {} }; if ns.cdb then ns.cdb.tourney = t end end
  t.played = t.played + 1
  if place == 1 then t.won = t.won + 1 end
  t.places[place] = (t.places[place] or 0) + 1
end

local function onTourney(ev)
  local me = UnitName("player")
  -- only record results for a table we are actually at (the wire layer already
  -- requires sender == tableId; this also keeps OTHER tables' events off our book)
  local c = ns.casino
  local atTable = c and (c.seatedAt == ev.tableId or (c.tableHost and c.tableHost.id == ev.tableId))
  if ev.kind == "level" then
    Log.info("|cffffd95cBlinds up!|r Level " .. (ev.level or "?") .. ": " ..
      (ev.sb or "?") .. "/" .. (ev.bb or "?"))
  elseif ev.kind == "out" then
    Log.info(tostring(ev.player) .. " finishes " .. ordinal(ev.place or 0) .. ".")
    if atTable and ev.player == me then recordFinish(ev.place or 0) end
  elseif ev.kind == "end" then
    Log.info("|cffffd95c" .. tostring(ev.winner) .. " wins the Sit & Go!|r")
    if atTable and ev.winner == me then recordFinish(1) end
  end
end

-- ---------------------------------------------------------------------------
-- casino (multi-table) lifecycle
-- ---------------------------------------------------------------------------
local function ensureCasino()
  ensureComm()
  ns.session = nil                    -- casino mode (mutually exclusive with single-table)
  if not ns.casino then
    ns.casino = ns.Casino.new({
      transport = ns.comm, selfName = UnitName("player"), broadcast = casinoChannel(),
      entropy = genEntropy, nonces = genNonces,         -- pass the FUNCTIONS (fresh seed per hand)
      defaultStack = (ns.db and ns.db.defaultStack) or 1000, onCheat = onCheat,
      onNotice = function(msg) Log.error(msg) end,   -- join refusals, version mismatches
      onTourney = onTourney,                         -- sit&go level/elimination/winner lines
      -- comms budget: a host sends ONE small ad per minute; the PING-on-open path
      -- handles instant discovery, so the periodic ad is just a TTL keep-alive.
      adInterval = 60, lobbyTtl = 180, turnTimeout = 60, human = true,
    })
    ns.casino:announce()              -- ask hosts to re-advertise: instant table list
    if type(GuildRoster) == "function" then GuildRoster() end   -- fresh class data for seat icons
    Log.info("Entered the casino floor on " .. casinoChannel() .. ".")
  end
  return ns.casino
end

-- ---------------------------------------------------------------------------
-- slash interface
-- ---------------------------------------------------------------------------
local function describeTurn()
  local s = activeSession()
  if not s then
    if ns.casino then return "On the casino floor — /azh tables, /azh open, /azh sit <dealer>." end
    return "No active table. /azh host, /azh join, or /azh lobby."
  end
  if s.legalForMe then            -- host
    local la = s:legalForMe()
    if la then return "Your turn (host). toCall=" .. (la.toCall or 0) .. " minRaise=" .. (la.minRaiseTo or "-") end
  end
  if s.prompt then
    return "Your turn. toCall=" .. (s.prompt.toCall or 0) .. " minRaise=" .. (s.prompt.minRaise or "-")
  end
  return "Phase: " .. tostring(s.phase) .. (s.aborted and " (ABORTED: " .. (s.cheat and s.cheat.code or "?") .. ")" or "")
end

local function doAct(action, amount)
  local s = ns.casino or ns.session
  if not s or not s.humanAct then return Log.error("No table / not your turn.") end
  local ok, err = s:humanAct(action, amount)
  if not ok then Log.error("Can't " .. action .. ": " .. tostring(err)) end
end

local A = ns.Const.ACTION
local handlers = {
  host = function(a) startHost(tonumber(a[2]) or (ns.db.sb or 5), tonumber(a[3]) or (ns.db.bb or 10)) end,
  join = function() joinTable() end,
  start = function()
    if ns.session and ns.session.start then return ns.session:start() end
    if ns.casino and ns.casino.tableHost then
      local ok, err = ns.casino:startGame()
      if ok then Log.info("Game on — dealing the first hand!")
      else Log.error("Can't start: " .. tostring(err)) end
      return
    end
    Log.error("Host a table first.")
  end,
  fold = function() doAct(A.FOLD) end,
  check = function() doAct(A.CHECK) end,
  call = function() doAct(A.CALL) end,
  raise = function(a) doAct(A.RAISE, tonumber(a[2])) end,
  bet = function(a) doAct(A.BET, tonumber(a[2])) end,
  status = function() Log.info(describeTurn()) end,
  log = function(a) ns.Log.level = tonumber(a[2]) or 2; Log.info("log level " .. ns.Log.level) end,

  -- multi-table casino
  lobby = function()
    ensureCasino():announce()                  -- refresh the table list right away
    if ns.UI and ns.UI.showLobby then ns.UI.showLobby() end
    Log.info("Casino floor open. /azh tables to list, /azh open to deal, /azh sit <dealer> to play.")
  end,
  open = function(a)
    -- "-" = explicit "use the default name" (the lobby UI passes it so blinds can
    -- follow positionally); the default identifies the host: "<Name>'s Table"
    local name = a[2]
    if not name or name == "-" then name = UnitName("player") .. "'s Table" end
    ensureCasino():host({
      name = name,
      sb = tonumber(a[3]) or (ns.db.sb or 5), bb = tonumber(a[4]) or (ns.db.bb or 10),
      seatMax = tonumber(a[5]) or 9,
      restTicks = 6,                           -- a 6s pause between hands to read the result
    })
    Log.info("Opened a table on the floor — players can /azh sit " .. UnitName("player"))
  end,
  -- /azh sng [stack] [sb] [bb] — host a Sit & Go: equal stacks, blinds double
  -- every few hands, busted players are out, last one standing wins.
  sng = function(a)
    ensureCasino():host({
      name = UnitName("player") .. "'s Sit & Go",
      sb = tonumber(a[3]) or (ns.db.sb or 5), bb = tonumber(a[4]) or (ns.db.bb or 10),
      restTicks = 6,
      tourney = { stack = tonumber(a[2]) or (ns.db.defaultStack or 1000), handsPerLevel = 8 },
    })
    Log.info("Sit & Go opened — players /azh sit " .. UnitName("player")
      .. ", then Start Game locks the field and deals.")
  end,
  record = function()
    local t = ns.cdb and ns.cdb.tourney
    if not t or t.played == 0 then return Log.info("No Sit & Go results yet — host one with /azh sng!") end
    Log.info(string.format("Sit & Go record: %d played, %d won.", t.played, t.won))
    local parts = {}
    for place = 1, 9 do
      if t.places[place] then parts[#parts + 1] = ordinal(place) .. " x" .. t.places[place] end
    end
    if #parts > 0 then Log.info("  finishes: " .. table.concat(parts, ", ")) end
  end,
  sit = function(a)
    if not a[2] then return Log.error("/azh sit <dealer name>") end
    ensureCasino():join(a[2])
    Log.info("Sitting down at " .. a[2] .. "'s table.")
  end,
  stand = function()
    if not ns.casino then return end
    if ns.casino.tableHost then return Log.info("You are hosting — /azh close to close your table.") end
    if not ns.casino.seatedAt then return Log.info("You are not seated at a table.") end
    ns.casino:leave(); Log.info("Stood up from the table.")
  end,
  close = function()
    if not (ns.casino and ns.casino.tableHost) then return Log.info("You are not hosting a table.") end
    ns.casino:closeTable()
    Log.info("Table closed" .. (ns.casino and ns.casino._closing and " — current hand finishes first." or "."))
  end,
  pause = function()
    if not (ns.casino and ns.casino.tableHost) then return Log.info("You are not hosting a table.") end
    local _, nowPaused = ns.casino:pauseTable()
    if nowPaused then Log.info("Table paused — break time! (Turn clock stopped; the current hand can be finished at leisure.)")
    else Log.info("Break over — the clock is back on and dealing continues.") end
  end,
  sitout = function()
    if not ns.casino then return end
    local ok, res = ns.casino:sitOut()
    if not ok then return Log.error("Can't sit out: " .. tostring(res)) end
    if res then Log.info("Sitting out — you keep your seat and chips; hands skip you until you return.")
    else Log.info("You're back in — dealt from the next hand.") end
  end,
  fair = function()
    if ns.UI and ns.UI.showFairness then ns.UI.showFairness() end
  end,
  scale = function(a)
    local s = tonumber(a[2])
    if not s or s < 0.5 or s > 2 then return Log.info("/azh scale 0.5 – 2.0 (current " .. tostring(ns.db.uiScale or 1) .. ")") end
    ns.db.uiScale = s
    if ns.UI then
      for _, f in ipairs({ ns.UI.tableFrame, ns.UI.lobbyPanel, ns.UI.fairnessPanel }) do
        if f and f.SetScale then f:SetScale(s) end
      end
    end
    Log.info("UI scale " .. s)
  end,
  frames = function()
    -- stray-frame triage: name every visual this addon owns and whether it is on
    -- screen right now. If some on-screen artifact is NOT listed as SHOWN here,
    -- it is not from Azeroth Hold'em — hover it and use Blizzard's /framestack
    -- (Blizzard_DebugTools) to identify its owner.
    local list = {
      { "table window", ns.UI and ns.UI.tableFrame },
      { "lobby window", ns.UI and ns.UI.lobbyPanel },
      { "fairness report", ns.UI and ns.UI.fairnessPanel },
      { "minimap button", ns.minimapButton },
    }
    Log.info("Frames owned by Azeroth Hold'em:")
    for _, e in ipairs(list) do
      local f = e[2]
      if f then
        local shown = (f.IsShown and f:IsShown()) and "|cff66ff66SHOWN|r" or "hidden"
        Log.info("  " .. e[1] .. " — " .. shown)
      end
    end
    Log.info("Anything else on screen is not ours — hover it and run /framestack to name it.")
  end,
  mode = function(a)
    local m = (a[2] or ""):upper()
    if m ~= "GUILD" and m ~= "GROUP" then return Log.info("/azh mode guild  or  /azh mode group") end
    local ok, err = ns.setCasinoMode(m)
    if ok then Log.info("Casino mode: " .. m .. ".") else Log.error("Can't switch mode: " .. tostring(err)) end
  end,
  tables = function()
    ensureCasino():announce()                  -- refresh the table list right away
    local list = ns.casino:tables()
    if #list == 0 then return Log.info("No tables advertised yet — wait a moment, or /azh open one.") end
    Log.info("Tables on the floor:")
    for _, t in ipairs(list) do
      Log.info(string.format("  %s — %s  (%d/%d)  blinds %d/%d", t.tableId, t.name or "?", t.taken, t.seatMax, t.sb, t.bb))
    end
  end,
}

local function onSlash(msg)
  local a = {}
  for word in string.gmatch(msg or "", "%S+") do a[#a + 1] = word end
  if not a[1] then                                  -- bare /azh: open/close the casino window
    if ns.session then return Log.info(describeTurn()) end   -- manual table in progress: don't disturb it
    ensureCasino():announce()
    if ns.UI and ns.UI.toggleLobby then ns.UI.toggleLobby() end
    return
  end
  local cmd = a[1]:lower()
  local h = handlers[cmd]
  if h then h(a) else
    Log.info("/azh — open the casino window. Also: open | sit <host> | stand | close | mode guild/group | tables | status")
    Log.info("manual play: host [sb] [bb] | join | start | fold | check | call | raise N | bet N | log N")
  end
end

-- ---------------------------------------------------------------------------
-- minimap button: one click to the casino; flashes (and pings once) on your turn
-- ---------------------------------------------------------------------------
local function makeMinimapButton()
  if not Minimap or ns.minimapButton then return end
  local b = CreateFrame("Button", "AzerothHoldemMinimapButton", Minimap)
  b:SetWidth(31); b:SetHeight(31)
  if b.SetFrameStrata then b:SetFrameStrata("MEDIUM") end
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture("Interface\\AddOns\\AzerothHoldem\\art\\dealer.tga")
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetWidth(53); ring:SetHeight(53); ring:SetPoint("TOPLEFT")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.glow = b:CreateTexture(nil, "ARTWORK")                 -- your-turn flash
  b.glow:SetWidth(31); b.glow:SetHeight(31); b.glow:SetPoint("CENTER", 0, 1)
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
  b.glow:Hide()

  local function place()
    local angle = math.rad(ns.db.minimapAngle or 200)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
  end
  place()
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function() b._drag = true end)
  b:SetScript("OnDragStop", function() b._drag = false end)
  b:SetScript("OnUpdate", function(self, e)
    if self._drag and type(GetCursorPosition) == "function" then
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      -- divide the PHYSICAL cursor coords by the MINIMAP's effective scale (the
      -- LibDBIcon idiom) — UIParent's scale is wrong whenever the minimap is scaled
      local s = (Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()) or 1
      if mx and my then
        ns.db.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
        place()
      end
    end
    if self.glow:IsShown() then
      self._t = (self._t or 0) + (e or 0)
      self.glow:SetAlpha(0.55 + 0.45 * math.sin(self._t * 5))
    end
  end)
  b:SetScript("OnClick", function() onSlash("") end)
  ns.minimapButton = b
end

-- the UI tells us when it's (not) the player's turn: flash the minimap button
function ns.setTurnAlert(on)
  local b = ns.minimapButton
  if b then
    if on then b.glow:Show() else b.glow:Hide() end
  end
end

-- ---------------------------------------------------------------------------
-- trade-based buy-in verification (gold is NEVER moved by API — we only read)
-- ---------------------------------------------------------------------------
local pendingTrade = { theirs = 0, mine = 0 }
local function onTradeEvent(event)
  if event == "TRADE_SHOW" then
    pendingTrade.theirs, pendingTrade.mine = 0, 0
  elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
    pendingTrade.theirs = GetTargetTradeMoney() or 0   -- copper the other party offers
    pendingTrade.mine = GetPlayerTradeMoney() or 0
  elseif event == "TRADE_CLOSED" then
    -- the host records a completed buy-in here against the Ledger (the actual
    -- amounts are confirmed by Ledger.verifyTrade before seating). Hooked up by the
    -- host-control UI; left as a recorded event in the text interface.
    if ns.onTradeClosed then ns.onTradeClosed(pendingTrade.theirs, pendingTrade.mine) end
  end
end

-- ---------------------------------------------------------------------------
-- boot
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame", "AzerothHoldemFrame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_MONEY_CHANGED")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("TRADE_CLOSED")

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    AzerothHoldemDB = AzerothHoldemDB or { sb = 5, bb = 10, defaultStack = 1000 }
    ns.db = AzerothHoldemDB
    AzerothHoldemCharDB = AzerothHoldemCharDB or {}
    ns.cdb = AzerothHoldemCharDB
  elseif event == "PLAYER_LOGIN" then
    ensureComm()
    SLASH_AZEROTHHOLDEM1 = "/azh"
    SLASH_AZEROTHHOLDEM2 = "/azerothholdem"
    SlashCmdList["AZEROTHHOLDEM"] = onSlash
    if ns.db.uiScale and ns.UI then                  -- saved UI scale (/azh scale N)
      for _, fr in ipairs({ ns.UI.tableFrame, ns.UI.lobbyPanel, ns.UI.fairnessPanel }) do
        if fr and fr.SetScale then fr:SetScale(ns.db.uiScale) end
      end
    end
    makeMinimapButton()
    Log.info("loaded — type /azh to open the casino.")
  elseif event == "CHAT_MSG_ADDON" then
    -- arg1=prefix, arg2=message, arg3=channel, arg4=sender. No RegisterAddonMessagePrefix
    -- in 3.3.5, so we filter by our own prefix here.
    if arg1 == ns.Const.PREFIX and ns.comm and arg4 ~= UnitName("player") then
      ns.comm:onFrame(arg4, arg2, arg3)
    end
  else
    onTradeEvent(event)
  end
end)

ns.onSlash = onSlash         -- exposed for tests / UI
ns.Init = { startHost = startHost, joinTable = joinTable }
return ns.Init
