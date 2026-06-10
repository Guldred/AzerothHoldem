--[[ BigInt.lua — pure-Lua 5.1 big integers for Tier-2 mental poker (modexp/modinv).

  Magnitude limbs are little-endian base 2^24 (limb*limb + carry stays < 2^53, the
  exact double mantissa, so products never lose precision — same discipline as the
  SHA-256 `% 2^32`). Schoolbook multiply + Knuth Algorithm D long division +
  square-and-multiply modexp + extended-Euclid modinv. Every operation is
  cross-checked against Python's arbitrary-precision ints in test/bigint_test.lua.

  Heavy: a full-size modexp is millions of limb ops. The Tier-2 layer frame-spreads
  it via the Scheduler's coroutine workers and shows progress (see DESIGN/README).
]]

local ADDON, ns = ...
local floor = math.floor
local B = 16777216          -- 2^24
local BigInt = {}

-- ---- magnitude helpers (arrays of limbs, a[1] = least significant) --------
local function trim(a)
  local n = #a
  while n > 1 and a[n] == 0 do a[n] = nil; n = n - 1 end
  return a
end

local function cmp(a, b)             -- compare magnitudes: -1/0/1
  if #a ~= #b then return #a < #b and -1 or 1 end
  for i = #a, 1, -1 do
    if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
  end
  return 0
end

local function add(a, b)             -- magnitude add
  local r, carry, n = {}, 0, math.max(#a, #b)
  for i = 1, n do
    local s = (a[i] or 0) + (b[i] or 0) + carry
    if s >= B then r[i] = s - B; carry = 1 else r[i] = s; carry = 0 end
  end
  if carry > 0 then r[n + 1] = carry end
  return r
end

local function sub(a, b)             -- magnitude subtract, assumes a >= b
  local r, borrow = {}, 0
  for i = 1, #a do
    local s = a[i] - (b[i] or 0) - borrow
    if s < 0 then r[i] = s + B; borrow = 1 else r[i] = s; borrow = 0 end
  end
  return trim(r)
end

local function mul(a, b)             -- schoolbook magnitude multiply
  local r = {}
  for i = 1, #a + #b do r[i] = 0 end
  for i = 1, #a do
    local carry, ai = 0, a[i]
    if ai ~= 0 then
      for j = 1, #b do
        local t = r[i + j - 1] + ai * b[j] + carry
        r[i + j - 1] = t % B
        carry = floor(t / B)
      end
      r[i + #b] = r[i + #b] + carry
    end
  end
  return trim(r)
end

local function mulsmall(a, s)        -- magnitude * single limb (s < B)
  local r, carry = {}, 0
  for i = 1, #a do
    local t = a[i] * s + carry
    r[i] = t % B
    carry = floor(t / B)
  end
  if carry > 0 then r[#a + 1] = carry end
  return trim(r)
end

local function isZero(a) return #a == 1 and a[1] == 0 end

-- Knuth Algorithm D: divmod of magnitudes u / v -> quotient q, remainder rem.
local function divmod(u, v)
  if isZero(v) then error("BigInt: division by zero") end
  if cmp(u, v) < 0 then return { 0 }, { unpack(u) } end
  local n = #v
  if n == 1 then                      -- fast path: single-limb divisor
    local d, q, rem = v[1], {}, 0
    for i = #u, 1, -1 do
      local cur = rem * B + u[i]
      q[i] = floor(cur / d)
      rem = cur - q[i] * d
    end
    return trim(q), { rem }
  end

  -- normalize so v[n] >= B/2
  local shift = floor(B / (v[n] + 1))
  local un = (shift == 1) and { unpack(u) } or mulsmall(u, shift)
  local vn = (shift == 1) and v or mulsmall(v, shift)
  un[#u + 1] = un[#u + 1] or 0        -- ensure an extra high limb
  local m = #un - n - 1
  local q = {}

  for j = m, 0, -1 do
    local num = un[j + n + 1] * B + (un[j + n] or 0)
    local qhat = floor(num / vn[n])
    local rhat = num - qhat * vn[n]
    while qhat >= B or (qhat * (vn[n - 1] or 0) > rhat * B + (un[j + n - 1] or 0)) do
      qhat = qhat - 1
      rhat = rhat + vn[n]
      if rhat >= B then break end
    end
    -- multiply and subtract qhat*vn from un[j+1 .. j+n+1]
    local borrow, carry = 0, 0
    for i = 1, n do
      local p = qhat * vn[i] + carry
      carry = floor(p / B)
      local t = (un[j + i] or 0) - (p % B) - borrow
      if t < 0 then t = t + B; borrow = 1 else borrow = 0 end
      un[j + i] = t
    end
    local t = (un[j + n + 1] or 0) - carry - borrow
    if t < 0 then                     -- qhat was one too big: add vn back
      t = t + B
      qhat = qhat - 1
      local c = 0
      for i = 1, n do
        local s = un[j + i] + vn[i] + c
        if s >= B then un[j + i] = s - B; c = 1 else un[j + i] = s; c = 0 end
      end
      t = t + c - B                   -- absorb the final carry into the top limb
      if t < 0 then t = t + B end
    end
    un[j + n + 1] = t
    q[j + 1] = qhat
  end

  -- remainder = un[1..n] / shift (unnormalize)
  local rem = {}
  for i = 1, n do rem[i] = un[i] end
  trim(rem)
  if shift > 1 then rem = (divmod(rem, { shift })) end
  return trim(q), rem
end

-- ---- public Big objects: { mag = {...}, neg = bool } ----------------------
local function wrap(mag, neg) return { mag = trim(mag), neg = neg or false } end
local mt = { __index = BigInt }
local function big(mag, neg) return setmetatable(wrap(mag, neg), mt) end

function BigInt.fromInt(n)
  local neg = n < 0
  n = math.abs(n)
  local mag = {}
  if n == 0 then mag = { 0 } else
    while n > 0 do mag[#mag + 1] = n % B; n = floor(n / B) end
  end
  return big(mag, neg)
end

-- hex string -> Big (used to parse RFC-3526 primes)
function BigInt.fromHex(h)
  h = h:gsub("%s", ""):gsub("^0[xX]", "")
  local mag = { 0 }
  for i = 1, #h do
    local d = tonumber(h:sub(i, i), 16)
    if not d then error("BigInt.fromHex: bad digit") end
    mag = add(mulsmall(mag, 16), { d })
  end
  return big(mag, false)
end

function BigInt:toHex()
  local a, out = { unpack(self.mag) }, {}
  if isZero(a) then return "0" end
  while not isZero(a) do
    local q, r = divmod(a, { 16 })
    out[#out + 1] = ("0123456789abcdef"):sub(r[1] + 1, r[1] + 1)
    a = q
  end
  local s = {}
  for i = #out, 1, -1 do s[#s + 1] = out[i] end
  return (self.neg and "-" or "") .. table.concat(s)
end

function BigInt.zero() return big({ 0 }, false) end
function BigInt.one() return big({ 1 }, false) end
function BigInt:isZero() return isZero(self.mag) end
function BigInt:cmpAbs(b) return cmp(self.mag, b.mag) end

-- signed compare
function BigInt:cmp(b)
  if self.neg ~= b.neg then return self.neg and -1 or 1 end
  local c = cmp(self.mag, b.mag)
  return self.neg and -c or c
end

-- signed add/sub
function BigInt:add(b)
  if self.neg == b.neg then return big(add(self.mag, b.mag), self.neg) end
  local c = cmp(self.mag, b.mag)
  if c == 0 then return BigInt.zero() end
  if c > 0 then return big(sub(self.mag, b.mag), self.neg) end
  return big(sub(b.mag, self.mag), b.neg)
end
function BigInt:sub(b) return self:add(big({ unpack(b.mag) }, not b.neg)) end
function BigInt:mul(b)
  if isZero(self.mag) or isZero(b.mag) then return BigInt.zero() end
  return big(mul(self.mag, b.mag), self.neg ~= b.neg)
end

-- floor-division divmod for NON-NEGATIVE self,b (sufficient for our use)
function BigInt:divmod(b)
  local q, r = divmod(self.mag, b.mag)
  return big(q, false), big(r, false)
end

-- self mod m, result in [0, m)
function BigInt:mod(m)
  local _, r = divmod(self.mag, m.mag)
  local rb = big(r, false)
  if self.neg and not isZero(r) then rb = m:sub(rb) end
  return rb
end

-- modular multiply
function BigInt:mulmod(b, m) return self:mul(b):mod(m) end

-- modular exponentiation: self^e mod m  (e non-negative)
function BigInt:powmod(e, m)
  local result = BigInt.one():mod(m)
  local base = self:mod(m)
  local exp = { unpack(e.mag) }
  while not isZero(exp) do
    if exp[1] % 2 == 1 then result = result:mulmod(base, m) end
    -- exp = exp >> 1
    local carry = 0
    for i = #exp, 1, -1 do
      local cur = carry * B + exp[i]
      exp[i] = floor(cur / 2)
      carry = cur % 2
    end
    trim(exp)
    if not isZero(exp) then base = base:mulmod(base, m) end
  end
  return result
end

-- modular inverse: self^-1 mod m via extended Euclid (gcd must be 1)
function BigInt:invmod(m)
  local t, newt = BigInt.zero(), BigInt.one()
  local r, newr = m, self:mod(m)
  while not newr:isZero() do
    local q = (r:divmod(newr))
    t, newt = newt, t:sub(q:mul(newt))
    r, newr = newr, r:sub(q:mul(newr))
  end
  if not (r:cmp(BigInt.one()) == 0) then error("BigInt.invmod: not invertible") end
  if t.neg then t = t:add(m) end
  return t
end

BigInt.B = B
ns.BigInt = BigInt
return BigInt
