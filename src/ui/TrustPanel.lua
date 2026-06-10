--[[ TrustPanel.lua — the verification readout with ready-check style icons and a
  prominent CHEAT banner. Green check = verified, yellow ? = pending, red X = failed. ]]

local ADDON, ns = ...
local W = ns.W
local COL = W.COL
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local panel, rows

local function row(parent, y, text)
  local r = {}
  r.icon = W.tex(parent, "ARTWORK", W.ICON.waiting)
  r.icon:SetWidth(16); r.icon:SetHeight(16); r.icon:SetPoint("TOPLEFT", 14, y)
  r.label = W.label(parent, text, "GameFontHighlightSmall", "LEFT")
  r.label:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  return r
end

local function setIcon(r, state)
  if state == true then r.icon:SetTexture(W.ICON.ready)
  elseif state == "bad" then r.icon:SetTexture(W.ICON.notready)
  else r.icon:SetTexture(W.ICON.waiting) end
end

local function build()
  panel = W.panel(UIParent, 226, 156, "Verification")
  panel:SetPoint("TOPRIGHT", -16, -130)
  rows = {
    seed = row(panel, -30, "Joint seed sealed"),
    deck = row(panel, -52, "Deck committed"),
    hole = row(panel, -74, "Your cards verified"),
    audit = row(panel, -96, "End-of-hand audit"),
  }
  panel.banner = W.label(panel, "", "GameFontNormalLarge"); panel.banner:SetPoint("BOTTOM", 0, 10)
  panel:Hide()
  ns.UI.trustPanel = panel
end

local function refresh(v)
  if not panel then return end
  if not v then panel:Hide(); return end
  panel:Show()
  setIcon(rows.seed, v.sealed)
  setIcon(rows.deck, v.sealed)
  setIcon(rows.hole, v.aborted and "bad" or v.holeVerified)
  setIcon(rows.audit, v.aborted and "bad" or v.auditPassed)
  panel.banner:SetText(v.aborted and ("|cffff2222CHEAT: " .. (v.cheat and v.cheat.code or "?") .. "|r") or "")
end

-- fired straight from the cheat callback (independent of the refresh loop)
function ns.UI.showCheat(code, detail)
  if not panel then return end
  panel:Show()
  panel.banner:SetText("|cffff2222>>> CHEAT: " .. tostring(code) .. " <<<|r")
  if rows then setIcon(rows.hole, "bad"); setIcon(rows.audit, "bad") end
end

build()
ns.UI.register(refresh)
return ns.UI.trustPanel
