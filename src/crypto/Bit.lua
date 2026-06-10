--[[ Bit.lua — pure-Lua 32-bit bitwise ops for Lua 5.1 (no native bit/LuaJIT).

  WoW 3.3.5a has no guaranteed `bit` library, so SHA-256 needs its own. Values are
  Lua numbers in [0, 2^32). and/or/xor use 4-bit (nibble) lookup tables; shifts,
  rotate, and not use exact double arithmetic. Doubles hold integers < 2^53
  exactly, so every result is masked back under 2^32 before it can grow.
]]

local ADDON, ns = ...
local Bit = {}

local floor = math.floor
local TWO32 = 4294967296

-- Build nibble (0..15) lookup tables for xor/and/or.
local XOR4, AND4, OR4 = {}, {}, {}
for a = 0, 15 do
  XOR4[a], AND4[a], OR4[a] = {}, {}, {}
  for b = 0, 15 do
    local x, an, o = 0, 0, 0
    for bit = 0, 3 do
      local mask = 2 ^ bit
      local pa = floor(a / mask) % 2
      local pb = floor(b / mask) % 2
      if pa ~= pb then x = x + mask end
      if pa == 1 and pb == 1 then an = an + mask end
      if pa == 1 or pb == 1 then o = o + mask end
    end
    XOR4[a][b], AND4[a][b], OR4[a][b] = x, an, o
  end
end

-- generic 2-arg nibble-table op over 32 bits (8 nibbles)
local function nibbleOp(tbl, a, b)
  local res, p = 0, 1
  for _ = 1, 8 do
    local na = a % 16; a = floor(a / 16)
    local nb = b % 16; b = floor(b / 16)
    res = res + tbl[na][nb] * p
    p = p * 16
  end
  return res
end

function Bit.bxor(a, b) return nibbleOp(XOR4, a, b) end
function Bit.band(a, b) return nibbleOp(AND4, a, b) end
function Bit.bor(a, b) return nibbleOp(OR4, a, b) end

-- xor of three / two-arg helpers used by SHA-256 round functions
function Bit.bxor3(a, b, c) return nibbleOp(XOR4, nibbleOp(XOR4, a, b), c) end

function Bit.bnot(a) return 4294967295 - (a % TWO32) end

-- logical left shift, masked to 32 bits
function Bit.lshift(a, n)
  return (a * (2 ^ n)) % TWO32
end

-- logical right shift
function Bit.rshift(a, n)
  return floor(a / (2 ^ n))
end

-- right rotate by n (0 < n < 32). The wrapped low n bits move to the top; since
-- the high and low parts are disjoint, addition equals bitwise-or here.
function Bit.rrotate(a, n)
  local mod = 2 ^ n
  local low = a % mod
  local high = floor(a / mod)
  return high + low * (2 ^ (32 - n))
end

-- add modulo 2^32 (SHA-256's 32-bit addition)
function Bit.add32(a, b)
  return (a + b) % TWO32
end

ns.Bit = Bit
return Bit
