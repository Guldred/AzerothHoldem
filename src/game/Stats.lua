--[[ Stats.lua — per-character poker record + achievements (pure).

  Owns the lifetime tally (hands, wins, streaks, biggest win, best hand made,
  hosting/audit counters, Sit&Go finishes) and the achievement definitions, all
  computed from per-hand events the sessions emit. Persistence is the CALLER's
  problem: new() takes the store table (in-game: AzerothHoldemCharDB.stats) and
  mutates it in place, so SavedVariables pick it up for free.

  Everything here is LOCAL bookkeeping — no wire traffic, no trust implications.
  Achievements are deliberately verifiable-by-the-owner only (your own record);
  a shared guild leaderboard would need signed claims and is out of scope.
]]

local ADDON, ns = ...
local HAND = ns.Const.HAND

local Stats = {}
Stats.__index = Stats

-- ordered, data-driven definitions: test(s) reads the store. Names are flavor;
-- ids are persisted (never rename an id).
Stats.ACHIEVEMENTS = {
  { id = "first_win",   name = "First Blood",          desc = "Win your first hand",
    test = function(s) return (s.wins or 0) >= 1 end },
  { id = "wins_10",     name = "On a Roll",            desc = "Win 10 hands",
    test = function(s) return (s.wins or 0) >= 10 end },
  { id = "wins_100",    name = "Card Shark",           desc = "Win 100 hands",
    test = function(s) return (s.wins or 0) >= 100 end },
  { id = "hands_100",   name = "Table Regular",        desc = "Play 100 hands",
    test = function(s) return (s.hands or 0) >= 100 end },
  { id = "hands_1000",  name = "The Grinder",          desc = "Play 1,000 hands",
    test = function(s) return (s.hands or 0) >= 1000 end },
  { id = "streak_5",    name = "Heater",               desc = "Win 5 hands in a row",
    test = function(s) return (s.bestStreak or 0) >= 5 end },
  { id = "big_win",     name = "Monster Pot",          desc = "Win 500+ chips in one hand",
    test = function(s) return (s.biggestWin or 0) >= 500 end },
  { id = "boat",        name = "Boat Builder",         desc = "Make a Full House",
    test = function(s) return (s.bestHandCat or 0) >= HAND.FULL_HOUSE end },
  { id = "quads",       name = "Quad Damage",          desc = "Make Four of a Kind",
    test = function(s) return (s.bestHandCat or 0) >= HAND.QUADS end },
  { id = "steel_wheel", name = "Royal Line",           desc = "Make a Straight Flush",
    test = function(s) return (s.bestHandCat or 0) >= HAND.STRAIGHT_FLUSH end },
  { id = "allin_win",   name = "All-In, All Win",      desc = "Win a hand after going all-in",
    test = function(s) return (s.allInWins or 0) >= 1 end },
  { id = "bluff_25",    name = "Stone Cold Bluffer",   desc = "Win 25 hands without a showdown",
    test = function(s) return (s.bluffWins or 0) >= 25 end },
  { id = "sng_win",     name = "Closer",               desc = "Win a Sit & Go",
    test = function(s) return (s.sngWon or 0) >= 1 end },
  { id = "sng_3",       name = "Dynasty",              desc = "Win 3 Sit & Gos",
    test = function(s) return (s.sngWon or 0) >= 3 end },
  { id = "host_50",     name = "House Dealer",         desc = "Deal 50 hands as the host",
    test = function(s) return (s.hosted or 0) >= 50 end },
  { id = "audit_100",   name = "Trust, but Verify",    desc = "100 hands verified clean",
    test = function(s) return (s.audited or 0) >= 100 end },
}

function Stats.new(store)
  store = store or {}
  store.unlocked = store.unlocked or {}     -- id -> true
  return setmetatable({ s = store }, Stats)
end

-- check every achievement against the current tally; returns the NEWLY unlocked
-- definitions (the caller announces them)
function Stats:_check()
  local fresh = {}
  for _, a in ipairs(Stats.ACHIEVEMENTS) do
    if not self.s.unlocked[a.id] and a.test(self.s) then
      self.s.unlocked[a.id] = true
      fresh[#fresh + 1] = a
    end
  end
  return fresh
end

-- one completed hand, from MY point of view.
-- ev = { delta (number|nil: nil = not dealt in), showdown (table had one),
--        folded, allIn, hosting (I dealt it), hole = {c1,c2}, board = {c...} }
-- Returns newly unlocked achievements.
function Stats:onHand(ev)
  local s = self.s
  if ev.hosting then s.hosted = (s.hosted or 0) + 1 end
  if ev.delta == nil then return self:_check() end   -- dealt by me, not played by me

  s.hands = (s.hands or 0) + 1
  s.net = (s.net or 0) + ev.delta
  if ev.delta > 0 then
    s.wins = (s.wins or 0) + 1
    s.streak = (s.streak or 0) + 1
    if s.streak > (s.bestStreak or 0) then s.bestStreak = s.streak end
    if ev.delta > (s.biggestWin or 0) then s.biggestWin = ev.delta end
    if ev.showdown then s.showdownWins = (s.showdownWins or 0) + 1
    else s.bluffWins = (s.bluffWins or 0) + 1 end
    if ev.allIn then s.allInWins = (s.allInWins or 0) + 1 end
  else
    s.streak = 0
  end

  -- best hand MADE (only when we saw it through — a folded hand wasn't made)
  if not ev.folded and ev.hole and #ev.hole >= 2 and ev.board
      and (#ev.hole + #ev.board) >= 5 and ns.HandEval then
    local all = {}
    for i = 1, #ev.hole do all[#all + 1] = ev.hole[i] end
    for i = 1, #ev.board do all[#all + 1] = ev.board[i] end
    local ok, score = pcall(ns.HandEval.evaluate, all)
    if ok and score and score.category > (s.bestHandCat or 0) then
      s.bestHandCat = score.category
      local ok2, name = pcall(ns.HandEval.describe, score)
      if ok2 then s.bestHandName = name end
    end
  end
  return self:_check()
end

-- a hand's end-of-hand audit passed (client-side full verification)
function Stats:onAudit()
  self.s.audited = (self.s.audited or 0) + 1
  return self:_check()
end

-- my Sit&Go finish (place 1 = won it)
function Stats:onTourneyFinish(place)
  local s = self.s
  s.sngPlayed = (s.sngPlayed or 0) + 1
  if place == 1 then s.sngWon = (s.sngWon or 0) + 1 end
  if place and ((s.sngBest or 99) > place) then s.sngBest = place end
  return self:_check()
end

ns.Stats = Stats
return Stats
