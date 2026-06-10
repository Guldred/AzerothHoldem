--[[ Util.lua — pure helpers: hex, byte packing, string split/escape.

  No WoW API. Hashing always operates on RAW bytes; hex is only a wire/display
  encoding around the raw byte preimages (see DESIGN.md "Canonical hash preimages").
]]

local ADDON, ns = ...
local Util = {}

local byte, char, format = string.byte, string.char, string.format
local floor = math.floor

-- ---------------------------------------------------------------------------
-- Hex
-- ---------------------------------------------------------------------------
local HEXCHARS = "0123456789abcdef"
-- precompute byte -> 2-char hex
local BYTE2HEX = {}
for b = 0, 255 do
  BYTE2HEX[b] = HEXCHARS:sub(floor(b / 16) + 1, floor(b / 16) + 1)
                .. HEXCHARS:sub((b % 16) + 1, (b % 16) + 1)
end

-- raw byte string -> lowercase hex string
function Util.toHex(s)
  local out = {}
  for i = 1, #s do out[i] = BYTE2HEX[byte(s, i)] end
  return table.concat(out)
end

-- hex string -> raw byte string (errors on bad input)
function Util.fromHex(h)
  if #h % 2 ~= 0 then error("fromHex: odd length") end
  local out = {}
  for i = 1, #h, 2 do
    local n = tonumber(h:sub(i, i + 1), 16)
    if not n then error("fromHex: bad hex at " .. i) end
    out[#out + 1] = char(n)
  end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Big-endian integer packing (for canonical preimages: u32be(handNo), CSPRNG counter)
-- ---------------------------------------------------------------------------
-- 32-bit unsigned big-endian -> 4-byte string
function Util.u32be(n)
  n = n % 4294967296
  local b1 = floor(n / 16777216) % 256
  local b2 = floor(n / 65536) % 256
  local b3 = floor(n / 256) % 256
  local b4 = n % 256
  return char(b1, b2, b3, b4)
end

-- 4-byte big-endian string -> number (reads bytes [off+1..off+4], off default 0)
function Util.readU32be(s, off)
  off = off or 0
  local b1, b2, b3, b4 = byte(s, off + 1, off + 4)
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

-- compact base36 encoding of a non-negative integer (for wire message ids)
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function Util.toBase36(n)
  n = floor(n)
  if n <= 0 then return "0" end
  local out = {}
  while n > 0 do
    local d = n % 36
    out[#out + 1] = B36:sub(d + 1, d + 1)
    n = floor(n / 36)
  end
  -- reverse
  local s = {}
  for i = #out, 1, -1 do s[#s + 1] = out[i] end
  return table.concat(s)
end

-- ---------------------------------------------------------------------------
-- String split / join / escape (wire framing helpers)
-- ---------------------------------------------------------------------------
-- split on a single-character separator (literal, not a pattern)
function Util.split(s, sep)
  local out, n, start = {}, 0, 1
  while true do
    local i = s:find(sep, start, true)
    if not i then
      n = n + 1; out[n] = s:sub(start)
      break
    end
    n = n + 1; out[n] = s:sub(start, i - 1)
    start = i + 1
  end
  return out
end

-- backslash-escape the wire separators | ; : and backslash itself, so free text
-- (display names) can't break framing. NUL is never produced upstream.
local ESC_MAP = { ["\\"] = "\\\\", ["|"] = "\\p", [";"] = "\\s", [":"] = "\\c" }
function Util.escape(s)
  return (s:gsub("[\\|;:]", ESC_MAP))
end
local UNESC_MAP = { ["\\"] = "\\", ["p"] = "|", ["s"] = ";", ["c"] = ":" }
function Util.unescape(s)
  return (s:gsub("\\(.)", UNESC_MAP))
end

-- shallow copy
function Util.shallowCopy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

ns.Util = Util
return Util
