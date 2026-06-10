--[[ MentalPoker.lua — Tier-2 two-party blind shuffle over SRA (optional, flagged).

  host encrypts the 52 (QR-encoded) cards under its key  -> 52 opaque ciphertexts
  shuffler PERMUTES them with secret randomness AND RE-ENCRYPTS each under its key.
  After re-encryption the host can no longer link a ciphertext to a card (it would
  need the shuffler's key), and the shuffler never learned the card values (it would
  need the host's key). => neither party alone knows the deck order, so unlike Tier 1
  the host has NO read access during the hand.

  Reveal:
    * community card  -> both parties strip their layer publicly (jointDecrypt).
    * Hole cards kept secret from BOTH dealers require the cards to also be encrypted
      under the receiving PLAYER's key — i.e. the full N-party scheme (every player a
      crypto party). The two-party version here proves the unbiased blind shuffle and
      public reveal; the per-player private reveal is the documented degradation point
      (see DESIGN.md). Combine with Tier-1 per-card commitments for end-of-hand audit.
]]

local ADDON, ns = ...
local MP = {}

-- host's first encryption layer over the canonical card table
function MP.hostEncrypt(sra, cards, hostKey)
  local out = {}
  for i = 1, #cards do out[i] = sra:encrypt(cards[i], hostKey) end
  return out
end

-- shuffler permutes (perm[j] = which host-ciphertext lands at position j) + re-encrypts
function MP.shufflerReencrypt(sra, hostCards, perm, shufKey)
  local out = {}
  for j = 1, #perm do out[j] = sra:encrypt(hostCards[perm[j]], shufKey) end
  return out
end

-- strip both layers (commutative, so order doesn't matter) -> the card value
function MP.jointDecrypt(sra, c, hostKey, shufKey)
  return sra:decrypt(sra:decrypt(c, shufKey), hostKey)
end

-- map a decrypted value back to its card index 1..52 (nil if not a card)
function MP.cardIndex(value, cards)
  for k = 1, #cards do if value:cmp(cards[k]) == 0 then return k end end
  return nil
end

-- reveal the whole shuffled deck as card indices (audit / community runout)
function MP.revealAll(sra, deck, hostKey, shufKey, cards)
  local out = {}
  for j = 1, #deck do
    out[j] = MP.cardIndex(MP.jointDecrypt(sra, deck[j], hostKey, shufKey), cards)
  end
  return out
end

ns.MentalPoker = MP
return MP
