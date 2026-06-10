--[[ Verify.lua — Tier-1 client-side audit (this IS the anti-cheat guarantee).

  Pure module. Given the end-of-hand reveal (S's openings + every per-card
  opening) plus what the client stored during the hand (the seed commitments and
  the published per-card commitments), recompute everything and confirm the host
  could neither STACK nor REORDER the deck:

    1. each seat's revealed (r_i, salt_i) matches its committed C_i
    2. S = SHA256(r_1 || ... || r_n)  over the canonical seat order
    3. deck = FisherYates(CSPRNG(S))  is reproduced
    4. for every position: the published commitment opens to (val, pos, nonce)
       AND that val equals the FY-derived card  (binds commitments to the shuffle)
    5. the deck is exactly one of each card (no dup/missing)
    6. (optional) the stored STATEHASH matches  (cross-client equivocation tie-in)

  Any failure yields a structured, position-pinned result usable as the proof in
  a CHEAT message (DESIGN.md: proof-carrying CHEAT).
]]

local ADDON, ns = ...
local Commit, Deck = ns.Commit, ns.Deck

local Verify = {}

Verify.CODE = {
  INPUT = "BAD_INPUT",
  SEED = "SEED_MISMATCH",         -- a revealed seed doesn't open its commitment / S differs
  COMMIT = "COMMIT_MISMATCH",     -- a per-card commitment doesn't open to (val,pos,nonce)
  ORDER = "ORDER_MISMATCH",       -- a revealed card != the Fisher-Yates(S) card for that position
  DUP = "DUP_OR_MISSING",         -- the revealed deck isn't a permutation of 0..51
  STATE = "STATEHASH_MISMATCH",   -- recomputed H != the H stored at DECKCMT time
}

-- single-card / single-seed convenience wrappers (live verification mid-hand)
function Verify.seed(commitC, r, salt) return Commit.verifySeed(commitC, r, salt) end
function Verify.card(commit, val, pos, nonce) return Commit.verifyCard(commit, val, pos, nonce) end

-- Full end-of-hand audit.
-- t = {
--   handNo,
--   seatOrder       = { seatId, ... }  canonical ascending order used for S
--   reveals         = { [seatId] = { r=16B, salt=16B } }
--   seedCommits     = { [seatId] = C_i (raw 32B) }
--   deckCommits     = array[1..52] of raw 32B commitments (position 0..51)
--   cardOpenings    = array[1..52] of { val=cardId, nonce=16B }
--   S               = (optional) the host-revealed S, cross-checked against recompute
--   stateHashStored = (optional) the H the client computed at DECKCMT time
-- }
-- returns { ok=bool, failures={ {code, detail, pos?} , ... }, S=, deck= }
function Verify.endOfHand(t)
  local fails = {}
  local function fail(code, detail, pos)
    fails[#fails + 1] = { code = code, detail = detail, pos = pos }
  end

  if type(t) ~= "table" or type(t.seatOrder) ~= "table"
     or type(t.cardOpenings) ~= "table" or type(t.deckCommits) ~= "table" then
    return { ok = false, failures = { { code = Verify.CODE.INPUT, detail = "missing fields" } } }
  end

  -- 1. seed openings -> rList
  local rList = {}
  for i = 1, #t.seatOrder do
    local seat = t.seatOrder[i]
    local rev = t.reveals and t.reveals[seat]
    local C = t.seedCommits and t.seedCommits[seat]
    if not rev or not C then
      fail(Verify.CODE.INPUT, "missing reveal/commit for seat " .. tostring(seat))
    elseif not Commit.verifySeed(C, rev.r, rev.salt) then
      fail(Verify.CODE.SEED, "seat " .. tostring(seat) .. " seed does not open its commitment")
    end
    rList[i] = (rev and rev.r) or ""
  end

  -- 2. combined seed S (guarded — combineSeed errors on bad sizes)
  local okS, S = pcall(Commit.combineSeed, rList)
  if not okS then
    fail(Verify.CODE.SEED, "cannot combine seeds: " .. tostring(S))
    return { ok = false, failures = fails }
  end
  if t.S and t.S ~= S then
    fail(Verify.CODE.SEED, "host-revealed S != recomputed S")
  end

  -- 3. reproduce the shuffle
  local deck = Deck.shuffle(S)

  -- 4. per-position commitment + order binding
  for i = 1, 52 do
    local pos = i - 1
    local op = t.cardOpenings[i]
    local commit = t.deckCommits[i]
    if type(op) ~= "table" or commit == nil then
      fail(Verify.CODE.COMMIT, "missing opening/commitment", pos)
    else
      if not Commit.verifyCard(commit, op.val, pos, op.nonce) then
        fail(Verify.CODE.COMMIT, "commitment does not open to (val,pos,nonce)", pos)
      end
      if op.val ~= deck[i] then
        fail(Verify.CODE.ORDER, "revealed card " .. tostring(op.val)
          .. " != Fisher-Yates card " .. tostring(deck[i]), pos)
      end
    end
  end

  -- 5. exactly one of each card 0..51
  local seen, bad = {}, false
  for i = 1, 52 do
    local op = t.cardOpenings[i]
    local v = op and op.val
    if v == nil or seen[v] then bad = true else seen[v] = true end
  end
  for c = 0, 51 do if not seen[c] then bad = true end end
  if bad then fail(Verify.CODE.DUP, "revealed deck is not a permutation of 0..51") end

  -- 6. optional state-hash tie-in (must match the H pinned at DECKCMT time)
  if t.stateHashStored then
    local okH, H = pcall(Commit.stateHash, t.handNo or 0, S, t.deckCommits)
    if not okH or H ~= t.stateHashStored then
      fail(Verify.CODE.STATE, "recomputed STATEHASH != stored")
    end
  end

  return { ok = (#fails == 0), failures = fails, S = S, deck = deck }
end

-- first failure, shaped as a CHEAT proof payload (nil if the audit passed)
function Verify.proof(result)
  if result.ok or not result.failures[1] then return nil end
  return result.failures[1]
end

ns.Verify = Verify
return Verify
