--[[ SRA.lua — commutative encryption for Tier-2 mental poker (Shamir–Rivest–Adleman).

  Encryption is m^e mod p with e odd and coprime to p-1, so E_a(E_b(m)) = E_b(E_a(m)).
  p is a SAFE prime (p = 2q+1) so p-1 = 2q and a random odd e is almost always coprime.

  THE LEGENDRE TRAP (handled): odd-exponent encryption preserves the quadratic-residue
  class, so an observer could read each card's QR-class without decrypting and track the
  deck. We defeat this by encoding all 52 cards as QUADRATIC RESIDUES (small squares mod
  p) — every ciphertext is then a QR and the Legendre symbol leaks nothing.

  Context-parameterised by the prime so tests can use a small safe prime (fast) while
  production uses RFC 3526's 1536-bit MODP group. COST: a 1536-bit modexp is ~1.3s in
  WoW's Lua 5.1 interpreter; a full blind shuffle is minutes (see DESIGN.md / README).
]]

local ADDON, ns = ...
local Big = ns.BigInt
local SRA = {}
SRA.__index = SRA

-- RFC 3526 Group 5 (1536-bit) MODP safe prime
SRA.P1536_HEX = [[
FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1
29024E08 8A67CC74 020BBEA6 3B139B22 514A0879 8E3404DD
EF9519B3 CD3A431B 302B0A6D F25F1437 4FE1356D 6D51C245
E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D
C2007CB8 A163BF05 98DA4836 1C55D39A 69163FA8 FD24CF5F
83655D23 DCA3AD96 1C62F356 208552BB 9ED52907 7096966D
670C354E 4ABC9804 F1746C08 CA237327 FFFFFFFF FFFFFFFF]]

function SRA.new(P)
  local self = setmetatable({}, SRA)
  self.P = P
  self.Pm1 = P:sub(Big.one())
  self.half = (self.Pm1:divmod(Big.fromInt(2)))    -- (p-1)/2, for the Legendre symbol
  return self
end

function SRA.default() return SRA.new(Big.fromHex(SRA.P1536_HEX)) end

-- 52 distinct quadratic residues: card k -> (k+1)^2 mod p  (squares ARE residues)
function SRA:cardTable()
  local t = {}
  for k = 1, 52 do
    local m = Big.fromInt(k + 1)
    t[k] = m:mul(m):mod(self.P)
  end
  return t
end

-- key = { e, d=e^-1 mod (p-1) }. randBig() returns a Big used as raw key material.
function SRA:genKey(randBig)
  while true do
    local e = randBig():mod(self.Pm1)
    if e:isZero() or e:cmp(Big.one()) == 0 then e = Big.fromInt(3) end
    if e.mag[1] % 2 == 0 then e = e:add(Big.one()) end       -- force odd (coprime to the 2 in 2q)
    local ok, d = pcall(function() return e:invmod(self.Pm1) end)
    if ok then return { e = e, d = d } end                   -- invmod succeeds iff gcd(e,p-1)=1
  end
end

function SRA:encrypt(m, key) return m:powmod(key.e, self.P) end
function SRA:decrypt(c, key) return c:powmod(key.d, self.P) end

-- Legendre symbol a^((p-1)/2) mod p: 1 for a quadratic residue
function SRA:legendre(a) return a:powmod(self.half, self.P) end

ns.SRA = SRA
return SRA
