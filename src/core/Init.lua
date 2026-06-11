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

-- The multi-table casino lives on the GUILD channel whenever you have a guild: every
-- guildmate computes the same channel no matter their party/raid status, so ads and
-- seating always reach each other (a RAID-first rule made a raiding host invisible to
-- non-raid guildmates). Guildless characters fall back to their raid/party.
local function casinoChannel()
  if IsInGuild and IsInGuild() then return "GUILD" end
  if GetNumRaidMembers() > 0 then return "RAID" end
  return "PARTY"
end

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
      adInterval = 30, lobbyTtl = 120, turnTimeout = 60, human = true,
    })
    ns.casino:announce()              -- ask hosts to re-advertise: instant table list
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
  start = function() if ns.session and ns.session.start then ns.session:start() else Log.error("Host a table first.") end end,
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
    ensureCasino():host({
      name = a[2] or (UnitName("player") .. "'s Table"),
      sb = tonumber(a[3]) or (ns.db.sb or 5), bb = tonumber(a[4]) or (ns.db.bb or 10),
      seatMax = tonumber(a[5]) or 9,
      restTicks = 6,                           -- a 6s pause between hands to read the result
    })
    Log.info("Opened a table on the floor — players can /azh sit " .. UnitName("player"))
  end,
  sit = function(a)
    if not a[2] then return Log.error("/azh sit <dealer name>") end
    ensureCasino():join(a[2])
    Log.info("Sitting down at " .. a[2] .. "'s table.")
  end,
  stand = function()
    if not ns.casino then return end
    if ns.casino.tableHost then return Log.info("You are hosting this table — it stays open while you play.") end
    if not ns.casino.seatedAt then return Log.info("You are not seated at a table.") end
    ns.casino:leave(); Log.info("Stood up from the table.")
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
  local cmd = (a[1] or "status"):lower()
  local h = handlers[cmd]
  if h then h(a) else
    Log.info("commands: host [sb] [bb] | join | start | fold | check | call | raise N | bet N | status | log N")
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
  elseif event == "PLAYER_LOGIN" then
    ensureComm()
    SLASH_AZEROTHHOLDEM1 = "/azh"
    SLASH_AZEROTHHOLDEM2 = "/azerothholdem"
    SlashCmdList["AZEROTHHOLDEM"] = onSlash
    Log.info("loaded. /azh for commands.")
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
