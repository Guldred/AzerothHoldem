--[[ Rng.lua — CSPRNG (counter-mode over SHA-256) + best-effort entropy mixing.

  Pure module. The CSPRNG MUST be byte-identical across all parties for a given
  seed S, or the cross-client STATEHASH gate would false-fire on every hand (see
  DESIGN.md "CSPRNG"). Uniform sampling uses rejection (NOT modulo) to avoid the
  small Fisher-Yates bias that a casual statistical test would miss.

  Stream:  block(k) = SHA256( seed || u32be(k) ),  k = 0,1,2,...
           bytes = block(0) || block(1) || ...
]]

local ADDON, ns = ...
local Sha256, Util = ns.Sha256, ns.Util
local floor = math.floor
local TWO32 = 4294967296

local Rng = {}

-- Deterministic CSPRNG generator keyed from `seed` (raw bytes; canonical seed is
-- the 32-byte S, but any length is accepted).
function Rng.fromSeed(seed)
  local counter = 0
  local buf = ""
  local pos = 1            -- index of next unread byte in buf

  local g = {}

  local function refill()
    buf = Sha256.bytes(seed .. Util.u32be(counter))
    counter = counter + 1
    pos = 1
  end

  function g.nextByte()
    if pos > #buf then refill() end
    local b = buf:byte(pos)
    pos = pos + 1
    return b
  end

  function g.nextUint32()
    local b1 = g.nextByte()
    local b2 = g.nextByte()
    local b3 = g.nextByte()
    local b4 = g.nextByte()
    return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
  end

  -- uniform integer in [0, n-1] via rejection sampling (no modulo bias)
  function g.uniform(n)
    if n < 1 then error("Rng.uniform: n must be >= 1") end
    if n == 1 then return 0 end
    local limit = floor(TWO32 / n) * n
    while true do
      local x = g.nextUint32()
      if x < limit then return x % n end
    end
  end

  -- k raw random bytes
  function g.bytes(k)
    local out = {}
    for i = 1, k do out[i] = string.char(g.nextByte()) end
    return table.concat(out)
  end

  return g
end

-- Best-effort entropy mix → 16-byte secret. The WoW layer supplies multiple
-- weak sources (GetTime() sub-second, time(), player/host names, a frame
-- counter, math.random()) since 3.3.5 math.random is weak. Documented as
-- best-effort. Pure: deterministic for identical inputs (so it is testable).
function Rng.mixEntropy(...)
  local n = select("#", ...)
  local parts = {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  return Sha256.bytes(table.concat(parts, "\30")):sub(1, 16)   -- 0x1e record-sep
end

ns.Rng = Rng
return Rng
