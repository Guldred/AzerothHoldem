--[[ TrustPanel.lua — the fair-play indicator, embedded in the table window (one
  window during play): a small status icon + line at the bottom-left summarizing
  the verification pipeline (seed sealed -> deck committed -> cards verified ->
  end-of-hand audit), and a big red on-table banner the moment a cheat is detected.
  The detailed per-check readout lives in the tooltip-free summary text. ]]

local ADDON, ns = ...
local W = ns.W
local function rgba(t, a) return t[1], t[2], t[3], a or t[4] or 1 end

local cluster, banner

local function build()
  local host = ns.UI.tableFrame
  if not host then return end                       -- table window is built first (.toc order)

  cluster = CreateFrame("Frame", nil, host)
  cluster:SetWidth(220); cluster:SetHeight(16)
  cluster:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 12, 56)
  cluster.icon = cluster:CreateTexture(nil, "ARTWORK")
  cluster.icon:SetWidth(14); cluster.icon:SetHeight(14); cluster.icon:SetPoint("LEFT", 0, 0)
  cluster.icon:SetTexture(W.ICON.waiting)
  cluster.text = W.label(cluster, "", "GameFontDisableSmall", "LEFT")
  cluster.text:SetPoint("LEFT", cluster.icon, "RIGHT", 4, 0)

  -- the unmissable cheat banner, across the middle of the felt
  banner = W.label(host, "", "GameFontNormalLarge")
  banner:SetPoint("CENTER", host, "CENTER", 0, 40)
  banner:SetText("")

  ns.UI.trustPanel = cluster
end

local function setState(icon, text)
  if not cluster then return end
  cluster.icon:SetTexture(icon)
  cluster.text:SetText(text)
end

local function refresh(v)
  if not cluster then return end
  if not v then banner:SetText(""); return end
  if v.aborted then
    setState(W.ICON.notready, "fair play: FAILED")
    banner:SetText("|cffff2222>>> CHEAT: " .. (v.cheat and v.cheat.code or "?") .. " <<<|r")
    return
  end
  banner:SetText("")
  if v.auditPassed then setState(W.ICON.ready, "fair play: hand verified")
  elseif v.holeVerified then setState(W.ICON.ready, "fair play: cards verified")
  elseif v.sealed then setState(W.ICON.waiting, "fair play: deck sealed, verifying…")
  else setState(W.ICON.waiting, "fair play: preparing…") end
end

-- fired straight from the cheat callback (independent of the refresh loop)
function ns.UI.showCheat(code, detail)
  if not cluster then return end
  setState(W.ICON.notready, "fair play: FAILED")
  if banner then banner:SetText("|cffff2222>>> CHEAT: " .. tostring(code) .. " <<<|r") end
end

build()
ns.UI.register(refresh)
return ns.UI.trustPanel
