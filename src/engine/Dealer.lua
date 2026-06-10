--[[ Dealer.lua — pure hand-lifecycle controller (the composition keystone).

  Ties the verified pieces into one hand WITHOUT any WoW API, so the host/network
  layer becomes thin wiring rather than logic:

    seed S (from the joint commit-reveal) + host nonces
      -> Deck.shuffle(S)                       the concrete deck
      -> Commit.commitDeck(deck, nonces)       the 52 published commitments
      -> Deck.dealPlan(n) + canonical deal order (SB first)
      -> Rules betting                          (Dealer:act / :legalActions / :toAct)
      -> hole/board reveals bound to commitments
      -> Rules.settle                           showdown / uncontested
      -> end-of-hand reveal transcript          (for Verify.endOfHand)

  The deal map is a deterministic function of seat count + button (via Rules), so
  the host cannot route favorable committed positions to itself — every reveal
  this Dealer emits opens the exact commitment a client stored.
]]

local ADDON, ns = ...
local Deck, Commit, Rules = ns.Deck, ns.Commit, ns.Rules

local Dealer = {}
Dealer.__index = Dealer

-- cfg = { variant, order, stacks, buttonSeat, sb, bb, ante, handNo, seed=S(32B),
--         nonces = array[1..52] of 16B }   (S and nonces come from the host)
function Dealer.start(cfg)
  local rules = Rules.startHand(cfg)            -- also fixes sbPos/bbPos
  local n = #cfg.order
  local deck = Deck.shuffle(cfg.seed)
  local commits, openings = Commit.commitDeck(deck, cfg.nonces)
  local plan = Deck.dealPlan(n)

  -- canonical dealing order: first card to the small blind (seat left of button),
  -- then clockwise. dealOrder[k] receives plan.holes[k].
  local dealOrder, indexOf = {}, {}
  for k = 1, n do
    local seat = cfg.order[((rules.sbPos - 1) + (k - 1)) % n + 1]
    dealOrder[k] = seat
    indexOf[seat] = k
  end

  return setmetatable({
    rules = rules, variant = rules.variant, n = n, handNo = cfg.handNo or 0,
    seed = cfg.seed, order = cfg.order, deck = deck, commits = commits,
    openings = openings, plan = plan, dealOrder = dealOrder, indexOf = indexOf,
  }, Dealer)
end

-- ---- betting passthrough --------------------------------------------------
function Dealer:legalActions(seatId) return Rules.legalActions(self.rules, seatId) end
function Dealer:act(seatId, action, amount) return Rules.applyAction(self.rules, seatId, action, amount) end
function Dealer:toAct() return self.rules.toAct end
function Dealer:isComplete() return self.rules.complete end
function Dealer:street() return self.rules.street end

-- ---- card geometry (0-based deck positions) -------------------------------
-- deck index k holds the card committed at position k-1
local function reveal(self, deckIdx)
  local pos = deckIdx - 1
  return { pos = pos, val = self.deck[deckIdx], nonce = self.openings[deckIdx].nonce }
end

-- the two hole-card reveals for a seat (host WHISPERs these to its owner)
function Dealer:holeReveal(seatId)
  local k = self.indexOf[seatId]
  if not k then error("Dealer:holeReveal: unknown seat " .. tostring(seatId)) end
  local h = self.plan.holes[k]
  return { reveal(self, h[1]), reveal(self, h[2]) }
end

function Dealer:flopReveal()
  local f = self.plan.flop
  return { reveal(self, f[1]), reveal(self, f[2]), reveal(self, f[3]) }
end
function Dealer:turnReveal() return { reveal(self, self.plan.turn) } end
function Dealer:riverReveal() return { reveal(self, self.plan.river) } end

-- community card ids visible at a given board-card count (for board state)
function Dealer:boardCards(count)
  local b, p = {}, self.plan
  local idxs = { p.flop[1], p.flop[2], p.flop[3], p.turn, p.river }
  for i = 1, (count or 0) do b[i] = self.deck[idxs[i]] end
  return b
end

-- ---- showdown -------------------------------------------------------------
function Dealer:settle()
  local p = self.plan
  local board = {
    self.deck[p.flop[1]], self.deck[p.flop[2]], self.deck[p.flop[3]],
    self.deck[p.turn], self.deck[p.river],
  }
  local holeBySeat = {}
  for k = 1, self.n do
    local seat = self.dealOrder[k]
    if not self.rules.seats[seat].folded then
      holeBySeat[seat] = { self.deck[p.holes[k][1]], self.deck[p.holes[k][2]] }
    end
  end
  return Rules.settle(self.rules, holeBySeat, board), board, holeBySeat
end

-- ---- commitment / audit data ---------------------------------------------
function Dealer:stateHash()
  return Commit.stateHash(self.handNo, self.seed, self.commits)
end

-- the full end-of-hand reveal a client feeds to Verify.endOfHand (the host also
-- broadcasts S + every (val,nonce); seatOrder/reveals/seedCommits come from the
-- pre-hand joint-seed phase, supplied by the caller).
function Dealer:endRevealOpenings()
  return self.openings           -- array[1..52] of { val, nonce }
end

ns.Dealer = Dealer
return Dealer
