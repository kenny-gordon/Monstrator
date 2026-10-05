local data, buildInfo, worldPosition = M.extractedObjects, GetBuildInfo, M.WorldPosition
local nativeData = M.clientData
M.clientData = { maps = {}, errors = {}, generation = 0 }
local candidateCount = 0
for _, records in pairs(data.maps) do candidateCount = candidateCount + #records end
assert(candidateCount == 663, "real generated object candidate count must stay explicit")
M.extractedObjects = { build = "1.60.1.70205", locale = "enUS", maps = { [1] = {
    { 1, "Synthetic sign [Sign]", 20, 30, 0, 200, 300, 5 },
    { 2, "Synthetic meeting stone", 30, 40, 0, 300, 400, 48 },
} } }
GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
M.WorldPosition = function(_, mapID, x, y) return 0, x * 10, y * 10 end
local records = {}
local function add(r) records[#records + 1] = r end
M:AddExtractedObjects(1, add)
assert(#records == 2 and records[1].verification == "client-object")
assert(records[1].npcID == nil and records[1].category == "Objects")
assert(M:ValidateRecord(records[1]))
assert(M.clientData.objectChecks[1].accepted == 2)
local sourceMaps, sourceEntries = M.clientData.maps, M.data.entries
M.clientData.maps = { [1] = { entries = records, updated = GetTime() } }
M.data.entries = {}
M:BuildIndex()
assert(#M:Query("zone", "location", "Objects", "sign", "directory") == 1,
    "verified objects must be searchable in the real directory")
assert(#M:Query("zone", "npc", "All", "", "directory") == 0, "objects never enter the NPC list")
M.clientData.maps, M.data.entries = sourceMaps, sourceEntries
records[1].objectType = 19
assert(not M:ValidateRecord(records[1]), "object types must not be relabeled as unsupported services")
M.WorldPosition = function(_, _, x, y) return 0, x * 10 + 0.99, y * 10 end
records = {}
M:AddExtractedObjects(1, add)
assert(#records == 2, "less than one yard round-trip discrepancy is allowed")
M.WorldPosition = function(_, _, x, y) return 0, x * 10 + 1.01, y * 10 end
records = {}
M:AddExtractedObjects(1, add)
assert(#records == 0 and M.clientData.objectChecks[1].rejected == 2)
local notices = #messages
M:AddExtractedObjects(1, add)
assert(#messages == notices, "transform-rejection notices must not spam")
M.WorldPosition = function(_, _, x, y) return 1, x * 10, y * 10 end
M:AddExtractedObjects(1, add)
assert(#records == 0, "wrong instance must never yield a pin")
GetBuildInfo = function() return "1.60.1", "different", "", 16001 end
M:AddExtractedObjects(1, add)
assert(#records == 0 and M.clientData.objectMismatchNotice)
GetBuildInfo = function() return "1.60.1", "70205", "", 16001 end
M.WorldPosition = function() error("synthetic transform failure") end
M:AddExtractedObjects(1, add)
assert(M.clientData.errors.objects:find("synthetic transform failure", 1, true))
notices = #messages
M:AddExtractedObjects(1, add)
assert(#messages == notices, "failed transform provider must pause")
M.extractedObjects, GetBuildInfo, M.WorldPosition, M.clientData = data, buildInfo, worldPosition, nativeData
M:BuildIndex()
