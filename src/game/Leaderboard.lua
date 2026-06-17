--[[ Leaderboard.lua — a guild Sit&Go leaderboard built PASSIVELY from witnessed,
  sender-authenticated TOURNEY events (pure; the store is the caller's to persist).

  HOW IT STAYS HONEST (and adds ZERO wire traffic):
    * Every tournament already announces its progress on the floor — level-ups,
      eliminations ("out"), and the winner ("end") — and Casino only surfaces a
      TOURNEY event when sender == the dealer (tableId). This module just LISTENS
      to those events the client already hears; it never sends anything.
    * Each tournament carries a tourneyId (host entropy), so (tableId, tourneyId)
      dedups a tournament no matter how many times its events are re-heard.
    * A result is COUNTED only when the full arc was witnessed: the "end" plus at
      least one "out" (i.e. >= 2 real participants). This is the cheap anti-forgery
      bar — a lone troll can't pad wins by spamming a bare "end" for an empty table.

  WHAT IT IS / ISN'T: a record of tournament results SEEN ON THIS FLOOR, naturally
  scoped to the guild/group channel the player frequents. It is NOT a cryptographic
  ranking — a determined modified client could still fabricate a coherent multi-event
  tournament under its own name; the UI labels the board "results seen on the floor"
  in the same spirit as the README's documented residuals. Personal, trustworthy
  stats live in /azh stats (your own witnessed play).
]]

local ADDON, ns = ...

local Leaderboard = {}
Leaderboard.__index = Leaderboard

local MAX_SEEN = 5000        -- bound the dedup set (one key per tournament witnessed)
local MAX_OPEN = 64          -- bound in-flight tournaments tracked before their "end"

function Leaderboard.new(store)
  store = store or {}
  store.wins = store.wins or {}        -- name -> tournaments won
  store.cashes = store.cashes or {}    -- name -> top-3 finishes
  store.played = store.played or {}    -- name -> tournaments entered (that we saw)
  -- dedup set as a bounded FIFO RING: `seen[key]=true` for O(1) lookup, `ring`
  -- holds the keys in insertion order, `head` is the next slot to (over)write.
  -- The ring must EVICT, never stop recording — a cap that quietly stopped
  -- recording keys would re-open and re-count every re-heard tournament past
  -- the cap (retransmits, relays), inflating the board forever.
  store.seen = store.seen or {}
  store.ring = store.ring or {}
  store.head = store.head or 1
  -- migrate a pre-ring store (defensive; no shipped install has one): seed the
  -- ring from whatever keys were recorded so dedup stays continuous
  if store.seenN and not store.ringInit then
    for k in pairs(store.seen) do store.ring[#store.ring + 1] = k end
    store.head = (#store.ring % MAX_SEEN) + 1
  end
  store.ringInit, store.seenN = true, nil
  return setmetatable({ s = store, open = {}, openSeq = 0 }, Leaderboard)
end

local function key(ev)
  return tostring(ev.tableId or "?") .. ":" .. tostring(ev.tourneyId or "?")
end

-- record a committed tournament key in the bounded ring, evicting the oldest if
-- full. Counting is ALWAYS paired with this, so a tournament can never be
-- counted without also being deduped (the review's double-count hole).
function Leaderboard:_remember(k)
  local s = self.s
  local old = s.ring[s.head]
  if old then s.seen[old] = nil end                   -- evict the oldest key
  s.ring[s.head] = k
  s.seen[k] = true
  s.head = (s.head % MAX_SEEN) + 1
end

-- feed one TOURNEY event (already sender-authenticated by Casino). Returns true
-- if an "end" was committed to the board (for the caller to react to), else nil.
function Leaderboard:onEvent(ev)
  if not ev or not ev.tourneyId then return end       -- pre-v1.7 hosts: can't dedup, skip
  if ev.kind ~= "out" and ev.kind ~= "end" then return end
  local k = key(ev)
  if self.s.seen[k] then return end                   -- already counted this tournament

  local rec = self.open[k]
  if not rec then
    -- in-flight tracking is bounded; at the cap EVICT the oldest still-open
    -- (never-ended) tournament rather than dropping this new one — else a run
    -- of host-crash "zombies" would block all real tournaments for the session
    local n = 0
    for _ in pairs(self.open) do n = n + 1 end
    if n >= MAX_OPEN then
      local oldestKey, oldestSeq
      for ok, orec in pairs(self.open) do
        if not oldestSeq or orec.seq < oldestSeq then oldestKey, oldestSeq = ok, orec.seq end
      end
      if oldestKey then self.open[oldestKey] = nil end
    end
    self.openSeq = self.openSeq + 1
    rec = { players = {}, placeOf = {}, seq = self.openSeq }
    self.open[k] = rec
  end

  if ev.kind == "out" and ev.player then
    if not rec.players[ev.player] then rec.players[ev.player] = true end
    rec.placeOf[ev.player] = ev.place
  elseif ev.kind == "end" and ev.winner then
    rec.winner = ev.winner
    rec.players[ev.winner] = true
    rec.placeOf[ev.winner] = 1

    -- COUNT only a witnessed, multi-participant tournament
    local nseen = 0
    for _ in pairs(rec.players) do nseen = nseen + 1 end
    self.open[k] = nil
    if nseen < 2 then return end                      -- bare/forged singleton: ignore

    self:_remember(k)                                 -- dedup + count are atomic
    for name in pairs(rec.players) do
      self.s.played[name] = (self.s.played[name] or 0) + 1
      local pl = rec.placeOf[name]
      if pl == 1 then self.s.wins[name] = (self.s.wins[name] or 0) + 1 end
      if pl and pl >= 1 and pl <= 3 then self.s.cashes[name] = (self.s.cashes[name] or 0) + 1 end
    end
    return true
  end
end

-- a sorted view for the UI: by wins, then cashes, then fewest-played (efficiency),
-- then name. Returns an array of { name, wins, cashes, played }.
function Leaderboard:ranking()
  local out = {}
  for name, played in pairs(self.s.played) do
    out[#out + 1] = {
      name = name, played = played,
      wins = self.s.wins[name] or 0, cashes = self.s.cashes[name] or 0,
    }
  end
  table.sort(out, function(a, b)
    if a.wins ~= b.wins then return a.wins > b.wins end
    if a.cashes ~= b.cashes then return a.cashes > b.cashes end
    if a.played ~= b.played then return a.played < b.played end
    return a.name < b.name
  end)
  return out
end

function Leaderboard:reset()
  self.s.wins, self.s.cashes, self.s.played = {}, {}, {}
  self.s.seen, self.s.ring, self.s.head = {}, {}, 1
  self.open, self.openSeq = {}, 0
end

ns.Leaderboard = Leaderboard
return Leaderboard
