--[[ Log.lua — chat-frame logging (WoW-coupled only via DEFAULT_CHAT_FRAME). ]]

local ADDON, ns = ...
local Log = { level = 2 }   -- 0 silent, 1 error, 2 info, 3 debug

local TAG = "|cff66ccffAzeroth Hold'em|r: "

local function emit(color, msg)
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then
    frame:AddMessage(TAG .. (color or "") .. tostring(msg) .. (color and "|r" or ""))
  end
end

function Log.info(msg)  if Log.level >= 2 then emit(nil, msg) end end
function Log.debug(msg) if Log.level >= 3 then emit("|cff999999", msg) end end
function Log.error(msg) if Log.level >= 1 then emit("|cffff5555", msg) end end
-- a prominent, hard-to-miss banner for a detected cheat
function Log.cheat(msg) emit("|cffff0000>>> CHEAT DETECTED <<< ", msg) end

ns.Log = Log
return Log
