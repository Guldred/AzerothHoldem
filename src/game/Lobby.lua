--[[ Lobby.lua — the casino table directory (pure). Collects TABLE advertisements
  broadcast over the shared guild/raid channel and exposes a live, sorted list for
  the UI. Entries expire if a host stops advertising (TTL >= 2-3x the ad interval so
  tables don't flicker out between ads under message loss). Time is injected via
  tick(dt) so it stays pure/testable. ]]

local ADDON, ns = ...
local Lobby = {}
Lobby.__index = Lobby

function Lobby.new(ttl)
  return setmetatable({ tables = {}, ttl = ttl or 30, now = 0 }, Lobby)
end

-- record/refresh a table from a decoded TABLE ad (host = the advertiser's name)
function Lobby:onAd(d)
  self.tables[d.tableId] = {
    tableId = d.tableId, host = d.tableId, name = d.name, sb = d.sb, bb = d.bb,
    variant = d.variant, taken = d.taken, seatMax = d.seatMax, open = d.open,
    lastSeen = self.now,
  }
end

-- drop a table immediately (host closed it / left)
function Lobby:remove(tableId) self.tables[tableId] = nil end

-- advance time and expire stale tables
function Lobby:tick(dt)
  self.now = self.now + (dt or 1)
  for id, t in pairs(self.tables) do
    if self.now - t.lastSeen > self.ttl then self.tables[id] = nil end
  end
end

function Lobby:get(tableId) return self.tables[tableId] end

-- sorted list (by table id) for display
function Lobby:list()
  local out = {}
  for _, t in pairs(self.tables) do out[#out + 1] = t end
  table.sort(out, function(a, b) return a.tableId < b.tableId end)
  return out
end

function Lobby:count()
  local n = 0
  for _ in pairs(self.tables) do n = n + 1 end
  return n
end

ns.Lobby = Lobby
return Lobby
