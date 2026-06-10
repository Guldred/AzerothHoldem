--[[ Commit.lua — canonical commitments for Tier-1 (joint seed + per-card).

  Pure module. Every preimage uses FIXED-WIDTH fields so there is no field-boundary
  ambiguity (an opening cannot be re-parsed as a different opening). Sizes are
  normative: r_i, salt_i, nonce_p are each exactly 16 bytes. All operate on RAW
  bytes; the wire hex-encodes around these. See DESIGN.md "Canonical hash preimages".
]]

local ADDON, ns = ...
local Sha256, Util = ns.Sha256, ns.Util
local char = string.char

local Commit = {}

local R_LEN = 16        -- seed secret r_i
local SALT_LEN = 16     -- seed salt
local NONCE_LEN = 16    -- per-card nonce

local function need(cond, msg) if not cond then error("Commit: " .. msg) end end

-- ---- Joint seed ----------------------------------------------------------
-- C_i = SHA256( r_i[16] || salt_i[16] )
function Commit.seedCommit(r, salt)
  need(type(r) == "string" and #r == R_LEN, "r must be 16 bytes")
  need(type(salt) == "string" and #salt == SALT_LEN, "salt must be 16 bytes")
  return Sha256.bytes(r .. salt)
end

function Commit.verifySeed(commit, r, salt)
  if type(r) ~= "string" or #r ~= R_LEN then return false end
  if type(salt) ~= "string" or #salt ~= SALT_LEN then return false end
  return commit == Commit.seedCommit(r, salt)
end

-- S = SHA256( r_[seat1] || r_[seat2] || ... )  (caller passes r_i in canonical
-- ascending-seatId order). Order-sensitive by construction.
function Commit.combineSeed(rList)
  for i = 1, #rList do
    need(type(rList[i]) == "string" and #rList[i] == R_LEN, "rList[" .. i .. "] must be 16 bytes")
  end
  return Sha256.bytes(table.concat(rList))
end

-- ---- Per-card commitment -------------------------------------------------
-- commit_p = SHA256( char(val) || char(pos) || nonce[16] )
function Commit.cardCommit(val, pos, nonce)
  need(type(val) == "number" and val >= 0 and val <= 51 and val % 1 == 0, "val must be int 0..51")
  need(type(pos) == "number" and pos >= 0 and pos <= 51 and pos % 1 == 0, "pos must be int 0..51")
  need(type(nonce) == "string" and #nonce == NONCE_LEN, "nonce must be 16 bytes")
  return Sha256.bytes(char(val) .. char(pos) .. nonce)
end

function Commit.verifyCard(commit, val, pos, nonce)
  if type(val) ~= "number" or type(pos) ~= "number" then return false end
  if type(nonce) ~= "string" or #nonce ~= NONCE_LEN then return false end
  return commit == Commit.cardCommit(val, pos, nonce)
end

-- ---- State hash (cross-client equivocation gate) -------------------------
-- H = SHA256( u32be(handNo) || S[32] || commit_0[32] || ... || commit_51[32] )
-- commitList: array of 52 raw 32-byte commitments in position (0..51) order.
function Commit.stateHash(handNo, S, commitList)
  need(type(handNo) == "number" and handNo >= 0 and handNo % 1 == 0, "handNo must be a non-neg int")
  need(type(S) == "string" and #S == 32, "S must be 32 bytes")
  need(#commitList == 52, "commitList must have 52 entries")
  for i = 1, 52 do
    need(type(commitList[i]) == "string" and #commitList[i] == 32, "commit[" .. i .. "] must be 32 bytes")
  end
  return Sha256.bytes(Util.u32be(handNo) .. S .. table.concat(commitList))
end

-- ---- Host-side deck commitment construction -----------------------------
-- Given a shuffled deck (array[1..52] of card ids) and an array of 52 nonces
-- (each 16 bytes, independently CSPRNG-drawn), produce the per-position
-- commitments and their openings. Pure; the host injects the nonces.
-- Returns commits[1..52] (raw 32B, position 0..51 -> index 1..52) and
-- openings[1..52] = { val = cardId, nonce = nonce }.
function Commit.commitDeck(deck, nonces)
  need(#deck == 52, "deck must have 52 cards")
  need(#nonces == 52, "need 52 nonces")
  local commits, openings = {}, {}
  for i = 1, 52 do
    local pos = i - 1
    local val = deck[i]
    commits[i] = Commit.cardCommit(val, pos, nonces[i])
    openings[i] = { val = val, nonce = nonces[i] }
  end
  return commits, openings
end

-- field sizes exposed for callers / tests
Commit.R_LEN, Commit.SALT_LEN, Commit.NONCE_LEN = R_LEN, SALT_LEN, NONCE_LEN

ns.Commit = Commit
return Commit
