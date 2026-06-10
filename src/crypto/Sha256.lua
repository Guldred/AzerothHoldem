--[[ Sha256.lua — pure-Lua SHA-256 (FIPS 180-4) for Lua 5.1.

  Operates on RAW byte strings. Sha256.bytes(msg) -> 32-byte raw digest;
  Sha256.hex(msg) -> 64-char lowercase hex. Validated against NIST CAVP vectors
  in test/test_sha256.lua, including the 55/56/64-byte padding boundaries.

  Depends on ns.Bit (pure bitops) and ns.Util (byte packing). All arithmetic is
  masked under 2^32 promptly so doubles stay exact.
]]

local ADDON, ns = ...
local Bit, Util = ns.Bit, ns.Util

local bxor, band, bnot = Bit.bxor, Bit.band, Bit.bnot
local rrotate, rshift, add32 = Bit.rrotate, Bit.rshift, Bit.add32
local readU32be = Util.readU32be
local char, byte, rep, sub = string.char, string.byte, string.rep, string.sub
local floor = math.floor
local TWO32 = 4294967296

-- round constants (first 32 bits of fractional parts of cube roots of first 64 primes)
local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local Sha256 = {}

-- pad message per FIPS 180-4: append 0x80, zero-pad to 56 mod 64, then 64-bit
-- big-endian bit-length.
local function pad(msg)
  local len = #msg
  local bitlenHi = floor(len / 536870912)        -- high 32 bits of len*8 (= len/2^29)
  local bitlenLo = (len * 8) % TWO32             -- low 32 bits
  local padLen = (56 - (len + 1) % 64) % 64
  return msg .. char(0x80) .. rep("\0", padLen) .. Util.u32be(bitlenHi) .. Util.u32be(bitlenLo)
end

function Sha256.bytes(msg)
  local data = pad(msg)

  local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
  local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

  local w = {}
  for chunk = 0, #data - 1, 64 do
    -- message schedule
    for i = 1, 16 do
      w[i] = readU32be(data, chunk + (i - 1) * 4)
    end
    for i = 17, 64 do
      local w15 = w[i - 15]
      local w2 = w[i - 2]
      local s0 = bxor(bxor(rrotate(w15, 7), rrotate(w15, 18)), rshift(w15, 3))
      local s1 = bxor(bxor(rrotate(w2, 17), rrotate(w2, 19)), rshift(w2, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % TWO32
    end

    local a, b, c, d = h0, h1, h2, h3
    local e, f, g, h = h4, h5, h6, h7

    for i = 1, 64 do
      local S1 = bxor(bxor(rrotate(e, 6), rrotate(e, 11)), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local temp1 = (h + S1 + ch + K[i] + w[i]) % TWO32
      local S0 = bxor(bxor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
      local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
      local temp2 = (S0 + maj) % TWO32

      h = g
      g = f
      f = e
      e = (d + temp1) % TWO32
      d = c
      c = b
      b = a
      a = (temp1 + temp2) % TWO32
    end

    h0 = (h0 + a) % TWO32
    h1 = (h1 + b) % TWO32
    h2 = (h2 + c) % TWO32
    h3 = (h3 + d) % TWO32
    h4 = (h4 + e) % TWO32
    h5 = (h5 + f) % TWO32
    h6 = (h6 + g) % TWO32
    h7 = (h7 + h) % TWO32
  end

  return Util.u32be(h0) .. Util.u32be(h1) .. Util.u32be(h2) .. Util.u32be(h3)
      .. Util.u32be(h4) .. Util.u32be(h5) .. Util.u32be(h6) .. Util.u32be(h7)
end

function Sha256.hex(msg)
  return Util.toHex(Sha256.bytes(msg))
end

ns.Sha256 = Sha256
return Sha256
