local guid, name = UnitGUID, UnitName
local observations, static, clientData = M.observations, M.data.entries, M.clientData
local collecting, discovering = M.settings.collecting, M.settings.discovering
M.observations = { entries = {}, nextID = 1 }
M.data.entries = {}
M.clientData = { maps = {}, errors = {}, generation = 0 }
M.settings.observationLimit = 1000
M.settings.collecting, M.settings.discovering = false, false
M.discoveryWindow, M.discoverySeen = nil, nil
UnitGUID = function() return "Creature-0-0-0-0-98765-0001" end
UnitName = function() return "Synthetic NPC discovery" end
UnitLevel = function() return 42 end
UnitCreatureType = function() return "Humanoid" end
UnitClassification = function() return "elite" end
UnitReaction = function() return 4 end
M:CaptureNPC("PLAYER_TARGET_CHANGED", "target")
assert(M:ObservationCount() == 0, "passive discovery must be off by default")
SlashCmdList.MONSTRATOR("discover")
assert(M.settings.discovering)
M:CaptureNPC("PLAYER_TARGET_CHANGED", "target")
M:CaptureNPC("UPDATE_MOUSEOVER_UNIT", "mouseover")
assert(M:ObservationCount() == 1 and M.observations.entries["local:1"].sightings == 1,
    "the same GUID must be throttled across target and mouseover events")
local r = M.observations.entries["local:1"]
assert(r.npcID == 98765 and r.level == 42 and r.reaction == 4
    and r.creatureType == "Humanoid" and r.classification == "elite")
assert(r.verification == "pending" and r.precision == "encounter")
M:BuildIndex()
assert(#M:Query("global", "npc", "All", "98765", "directory") == 0,
    "discovered encounters must never become verified NPC placements automatically")
assert(#M:Query("global", "npc", "All", "98765 humanoid elite", "review") == 1)
clock = clock + 31
M:CaptureNPC("PLAYER_TARGET_CHANGED", "target")
assert(r.sightings == 2 and M:ObservationCount() == 1)
M.settings.collecting = true
M:CaptureNPC("MERCHANT_SHOW")
assert(M:ObservationCount() == 1 and r.category == "Vendors",
    "service interaction must enrich a nearby pending discovery instead of duplicating it")
assert(table.concat(r.tags, ","):find("vendor", 1, true))
M:Review(r, "accept", 10, 10, "Vendors", "vendor,repair")
assert(#M:Query("global", "npc", "All", "98765", "directory") == 1)
local export = assert(load(M:ExportText()))()
assert(export[1].level == 42 and export[1].classification == "elite")
UnitGUID = function() return "Player-1-123" end
clock = clock + 31
M:CaptureNPC("UPDATE_MOUSEOVER_UNIT", "mouseover")
assert(M:ObservationCount() == 1, "discovery must exclude players")
UnitGUID = function() return "Creature-0-0-0-0-45678-0002" end
UnitLevel = function() return 0/0 end
UnitReaction = function() return 99 end
M:CaptureNPC("PLAYER_TARGET_CHANGED", "target")
local pending = M.observations.entries["local:2"]
assert(pending and pending.level == nil and pending.reaction == nil, "bad optional metadata must not enter saved records")
local inventory = M:NPCInventory()
assert(#inventory == 2)
local first
for _, item in ipairs(inventory) do if item.npcID == 98765 then first = item end end
assert(first and first.confirmed == 1 and first.pending == 0 and first.maps[1])
local showCopy, inventoryText = M.ShowCopy
M.ShowCopy = function(_, text) inventoryText = text end
SlashCmdList.MONSTRATOR("npcs")
assert(inventoryText:find("2 distinct NPC IDs", 1, true) and inventoryText:find("98765", 1, true))
M.ShowCopy = showCopy

M.settings.evidenceFilter = "confirmed"
assert(#M:Query("global", "all", "All", "", "journal") == 1)
M.settings.evidenceFilter = "pending"
assert(#M:Query("global", "all", "All", "", "journal") == 1)
assert(#M:Query("global", "all", "All", "", "directory") == 0)
M.settings.evidenceFilter = "map"
assert(#M:Query("global", "all", "All", "", "journal") == 0)
M.settings.evidenceFilter = "all"

local second = {}
for k, v in pairs(r) do second[k] = v end
second.key, second.name, second.npcID, second.mapID = "synthetic:npc-sort", "Alpha", 1, 2
M.data.entries = { second }
M:BuildIndex()
M.settings.sortOrder = "name"
local results = M:Query("global", "npc", "All", "", "directory")
assert(#results == 2 and results[1].record == second)
M.settings.sortOrder = "npcID"
results = M:Query("global", "npc", "All", "", "directory")
assert(results[1].record.npcID == 1)
local mapInfo = C_Map.GetMapInfo
C_Map.GetMapInfo = function(id) return { name = id == 1 and "A zone" or "Z zone" } end
M.settings.sortOrder = "zone"
results = M:Query("global", "npc", "All", "", "directory")
assert(results[1].record == r, "zone sorting must use names before NPC name")
C_Map.GetMapInfo = mapInfo
M.settings.sortOrder = "distance"
clock = clock + 1
M:UpdateDistances(results)
assert(results[1].record == r, "nearest sort must keep cross-instance unavailable distances last")
M.window.sort:Click()
assert(M.settings.sortOrder == "zone" and M.window.sort:GetText():find("Zone A-Z", 1, true))
M.window.sort:Click()
assert(M.settings.sortOrder == "name" and M.window.sort:GetText():find("Name A-Z", 1, true))
M.window.evidence:Click()
assert(M.settings.evidenceFilter == "confirmed")
M.settings.sortOrder, M.settings.evidenceFilter = "distance", "all"
UnitGUID, UnitName = guid, name
UnitLevel, UnitReaction, UnitCreatureType, UnitClassification = nil, nil, nil, nil
M.observations, M.data.entries, M.clientData = observations, static, clientData
M.settings.collecting, M.settings.discovering = collecting, discovering
M:BuildIndex()
