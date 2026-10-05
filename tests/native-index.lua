local saved = { native = M.native, index = M.dbIndex, cache = M.dbCache, data = M.data.entries,
    observations = M.observations, clientData = M.clientData, enabled = M.settings.referenceEnabled,
    filter = M.settings.evidenceFilter, grouping = M.settings.groupNPCs, map = playerMap, x = playerX, y = playerY,
    showCopy = M.ShowCopy }

-- Native fixture: map 1 and 2 are the only UiMaps the mock client knows; 777 must be dropped.
M.native = { data = {}, meta = {} }
local N = M.NativeData("Npc", "1.0.4", "Forever", "abc")
N[10] = "Innkeeper Kauth\tInnkeeper\t131\t30\t30\tH\t1:40,50 40,50 41,51"
N[11] = "Harn Longcast\tAlchemy Trainer\t17\t\t\t\t1:20,30"
N[12] = "Krang Stonehoof\tWarrior Trainer\t16\t\t\t\t1:21,31"
N[13] = "Tal\tWind Rider Master\t8\t\t\tH\t2:47,50"
N[14] = "Plainstrider\t\t0\t\t\t\t777:1,1"
N[15] = "[DND] Quest Trigger\t\t0\t\t\t\t1:5,5"
N[16] = "Moorat Longstride\tArmorer\t16388\t\t\tAH\t1:60,60 -1,-1"
local overlay, origin = M.NativeOverlay("Npc")
overlay[15] = false
overlay[18] = "Axle Smoothslice\tGoblin Engineer\t0\t\t\t\t1:70,70"
origin[18] = "discovery"
overlay[12] = "Krang Stonehoof\tWarrior Trainer\t16\t\t\t\t1:22,32"
origin[12] = "correction"

local lib = M:NativeProvider()
assert(lib.Npc.Has(18) and not lib.Npc.Has(15), "overlay rows must add and delete entities")
assert(lib.Npc.Origin(18) == "discovery" and lib.Npc.Origin(12) == "correction" and lib.Npc.Origin(10) == nil)
assert(lib.Npc.spawns(12)[1][1][1] == 22, "corrections must replace the base row")
local counts, meta, overlays = M:NativeSummary()
assert(counts.Npc == 7 and meta.version == "1.0.4" and overlays.discovery == 1 and overlays.correction == 1 and overlays.deleted == 1)

local category, tags = M:NPCIdentity(16, "Alchemy Trainer")
assert(category == "Trainers" and table.concat(tags, ","):find("profession_trainer"))
category, tags = M:NPCIdentity(16, "Warrior Trainer")
assert(table.concat(tags, ","):find("class_trainer"))
assert(M:NPCIdentity(8, "Wind Rider Master") == "Transit")
assert(M:NPCIdentity(128, "Innkeeper") == "Services")
assert(M:NPCIdentity(4 + 16384, "Armorer") == "Vendors")
assert(M:NPCIdentity(0, nil) == "Combat")

M.data.entries, M.observations = {}, { entries = {}, nextID = 1 }
M.clientData, M.dbCache, M.dbIndex = { maps = {}, errors = {}, generation = 0 }, {}, nil
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = true, "all", true
M:StartDatabaseIndex()
assert(M:DatabaseReady() and M.dbIndex.lib == lib, "small databases must index in a single slice")
assert(M.dbIndex.npcCount == 6 and M.dbIndex.mapCount == 2, "unknown UiMaps must be excluded; got " .. M.dbIndex.npcCount)
assert(not M.dbIndex.byMap[777])

local records = M:DatabaseMapRecords(1)
assert(#records == 6, "duplicates, sentinels and deleted rows must be dropped; got " .. #records)
assert(M:DatabaseMapRecords(1) == records, "zone records must be cached")
local byID = {}
for _, record in ipairs(records) do
    local ok, reason = M:ValidateRecord(record)
    assert(ok, reason)
    assert(record.edition == "Forever" and record.verification == "reference")
    assert(record.key:match("^reference:monstrator:") and record.source == "monstrator-db:1.0.4")
    byID[record.npcID] = record
end
assert(byID[10].category == "Services" and byID[10].faction == "Horde" and byID[10].level == 30)
assert(byID[11].category == "Trainers" and byID[11].title == "Alchemy Trainer")
assert(byID[16].category == "Vendors" and byID[16].faction == "Both" and table.concat(byID[16].tags, ","):find("repair"))
assert(byID[18].nativeOrigin == "discovery" and byID[12].nativeOrigin == "correction" and byID[12].x == 22)
assert(M:DatabaseMapRecords(2)[1].category == "Transit")
assert(#M:DatabaseMapRecords(777) == 0)

playerMap, playerX, playerY = 1, 0.4, 0.5
local savedFaction = UnitFactionGroup
UnitFactionGroup = function() return "Horde" end
M:BuildIndex()
clock = clock + 1
assert(#M:Query("zone", "npc", "All", "", "directory") == 5, "grouping must merge an NPC's placements")
assert(#M:Query("zone", "npc", "Trainers", "", "directory") == 2)
local counts = M:DirectoryCounts("zone", "")
assert(counts.npc == 5 and counts.categories.npc.Trainers == 2, "filter counts must match the grouped rows they open")
M.settings.groupNPCs = false
local placements = #M:Query("zone", "npc", "All", "", "directory")
assert(placements > 5 and M:DirectoryCounts("zone", "").npc == placements, "ungrouped counts must match placement rows")
M.settings.groupNPCs = true
assert(#M:Query("zone", "npc", "All", "alchemy", "directory") == 1, "titles must be searchable")
assert(#M:Query("zone", "npc", "All", "food", "directory") == 1, "innkeepers must answer food searches")
if not M.window then M:CreateWindow() end
M:Query("zone", "npc", "All", "alchemy", "directory")
M.selected, M.offset = 1, 0
M:Render()
assert(M.window.rows[1].name:GetText():find("<Alchemy Trainer>", 1, true), "rows must show NPC titles")
assert(M.window.info.title:GetText() == "<Alchemy Trainer>", "the details pane must follow the selection")
assert(M.window.info.body:GetText():find("Monstrator database", 1, true))
assert(M.window.rows[1].detail:GetText():find("NPC ID 11", 1, true))
M:Query("zone", "npc", "All", "axle", "directory")
M.selected = 1
M:Render()
assert(M.window.info.body:GetText():find("Forever discovery", 1, true), "details must explain overlay origins")
UnitFactionGroup = function() return "Alliance" end
assert(#M:Query("zone", "npc", "All", "", "directory") == 4, "Horde-only NPCs must be hidden from Alliance")
UnitFactionGroup = savedFaction
M.settings.evidenceFilter = "confirmed"
assert(#M:Query("zone", "npc", "All", "", "directory") == 0, "database placements must not count as confirmed")
M.settings.evidenceFilter = "all"
M.settings.referenceEnabled = false
M:BuildIndex()
assert(#M:Query("zone", "npc", "All", "", "directory") == 0, "the database toggle must hide database records")
M.settings.referenceEnabled = true

local forged = {}
for key, value in pairs(byID[11]) do forged[key] = value end
forged.edition = "Classic"
assert(not M:ValidateRecord(forged), "database records must declare the Forever edition")
forged.edition, forged.source = "Forever", "otherdb:1.0.4"
assert(not M:ValidateRecord(forged), "records claiming another provider's provenance must be rejected")

-- Audit compares confirmed sightings with the database.
local copied
M.ShowCopy = function(_, text) copied = text end
M.observations.entries = {
    a = { kind = "npc", npcID = 11, name = "Harn Longcast", mapID = 1, x = 20.5, y = 30, verification = "user-confirmed" },
    b = { kind = "npc", npcID = 11, name = "Harn Longcast", mapID = 1, x = 40, y = 30, verification = "pending" },
    c = { kind = "npc", npcID = 11, name = "Harn Longcast", mapID = 2, x = 1, y = 1, verification = "pending" },
    d = { kind = "npc", npcID = 99999, name = "Forever Newcomer", mapID = 1, x = 1, y = 1, verification = "pending" },
    e = { kind = "location", mapID = 1, x = 1, y = 1 },
}
local groups, matched, total = M:AuditObservations()
assert(total == 4 and matched == 1 and #groups.new == 1 and #groups.map == 1 and #groups.drift == 1)
assert(copied:find("Forever Newcomer", 1, true) and copied:find("harvest", 1, true))

M.native, M.dbIndex, M.dbCache = saved.native, saved.index, saved.cache
M.data.entries, M.observations, M.clientData = saved.data, saved.observations, saved.clientData
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = saved.enabled, saved.filter, saved.grouping
playerMap, playerX, playerY = saved.map, saved.x, saved.y
M.ShowCopy = saved.showCopy
M:BuildIndex()
