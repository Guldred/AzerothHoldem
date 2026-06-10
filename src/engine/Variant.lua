--[[ Variant.lua — pluggable poker-variant contract + registry.

  Keeps rules/transport/crypto independent of any specific game. A variant is a
  table implementing the contract below; Rules.lua drives betting generically and
  calls into the variant only for deck composition, the community-card schedule,
  and best-hand evaluation. Texas Hold'em is the first implementation; Omaha (4
  hole cards, must use exactly 2) can be added later WITHOUT touching the core.

  VARIANT CONTRACT (a variant table must provide):
    .name            string id, e.g. "texas"
    .deckSize        number, 52
    .holeCount       number of private hole cards per player
    .minPlayers, .maxPlayers
    .boardSchedule   { [street] = cumulative community-card count }, streets are
                     ns.Const.STREET values PREFLOP/FLOP/TURN/RIVER
    .streets         ordered array of streets that have a betting round
    :bestHand(hole, board) -> HandEval score  (hole: array of card ids; board:
                     array of revealed community card ids). Returns a comparable
                     score (ns.HandEval.compare orders them).
]]

local ADDON, ns = ...
local Variant = {}

local registry = {}

function Variant.register(impl)
  if type(impl) ~= "table" or type(impl.name) ~= "string" then
    error("Variant.register: impl must be a table with a string .name")
  end
  registry[impl.name] = impl
end

function Variant.get(name)
  return registry[name]
end

function Variant.list()
  local out = {}
  for name in pairs(registry) do out[#out + 1] = name end
  table.sort(out)
  return out
end

ns.Variant = Variant
return Variant
