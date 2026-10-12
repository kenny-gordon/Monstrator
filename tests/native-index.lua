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

local originalProfiler, profileClock = debugprofilestop, 0
debugprofilestop = function() profileClock = profileClock + 2; return profileClock end
local records = M:DatabaseMapRecords(1)
local expansion = M.dbIndex.expansionProfile
assert(expansion.maps == 1 and expansion.records == #records and expansion.milliseconds == 2
    and expansion.timedMaps == 1 and expansion.backgroundMaps == 0, "foreground expansion must be counted and timed")
assert(#records == 6, "duplicates, sentinels and deleted rows must be dropped; got " .. #records)
assert(M:DatabaseMapRecords(1) == records, "zone records must be cached")
assert(expansion.maps == 1 and expansion.milliseconds == 2, "cache hits must not inflate expansion metrics")
M:DatabaseMapRecords(2, true)
assert(expansion.maps == 2 and expansion.backgroundMaps == 1 and expansion.backgroundRecords == 1
    and expansion.backgroundMilliseconds == 2, "background expansions must be measured separately")
debugprofilestop = originalProfiler
M:DatabaseMapRecords(777)
assert(expansion.maps == 2, "unsupported maps must not be counted as materialized cache entries")
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

-- Sub-groups refine categories from titles, tags and levels.
local function keys(record) return table.concat(M:RecordSubgroups(record), ",") end
assert(keys(byID[11]) == "trainer:alchemy" and keys(byID[12]) == "trainer:warrior", keys(byID[11]) .. "/" .. keys(byID[12]))
assert(keys(byID[16]):find("vendor:armor", 1, true) and keys(byID[16]):find("vendor:repair", 1, true))
assert(keys(byID[10]) == "service:innkeeper,service:quest", "records may sit in several sub-groups")
assert(keys({ kind = "npc", category = "Trainers", title = "Grand Wizard", tags = { "trainer" } }) == "trainer:other",
    "unmatched records fall into the category's catch-all")
assert(keys({ kind = "npc", category = "Trainers", title = "Journeyman Blacksmith", tags = {} }) == "trainer:blacksmithing")
assert(keys({ kind = "npc", category = "Trainers", title = "Fishing Trainer", tags = {} }) == "trainer:fishing")
assert(keys({ kind = "npc", category = "Vendors", title = "Fishing Supplies", tags = {} }) == "supplies:fishing")
assert(keys({ kind = "npc", category = "Combat", level = 34, tags = {} }) == "level:31")
assert(keys({ kind = "location", category = "Objects", tags = { "herb" } }) == "object:herb")
assert(keys({ kind = "location", category = "Mailboxes", tags = { "mailbox" } }) == "", "categories without sub-groups")
assert(M:FindSubgroup("fishing trainer").key == "trainer:fishing")
assert(M:FindSubgroup("blacksmith").key == "trainer:blacksmithing", "a profession name means its trainer")
assert(M:FindSubgroup("Blacksmithing supplies").key == "supplies:blacksmithing")
assert(M:FindSubgroup("weapons").key == "vendor:weapons" and M:FindSubgroup("herbs").key == "object:herb")
assert(M:FindSubgroup("bankers").key == "service:bank" and M:FindSubgroup("xyzzy") == nil and M:FindSubgroup("") == nil)
M.kind, M.category, M.subgroup = "npc", "Trainers", "trainer:alchemy"
assert(#M:Query("zone", "npc", "Trainers", "", "directory") == 1, "the active sub-group filters results")
assert(#M:Query("zone", "npc", "All", "", "directory") == 5, "a sub-group of another category is ignored")
counts = M:DirectoryCounts("zone", "")
assert(counts.subgroups["trainer:alchemy"] == 1 and counts.subgroups["trainer:warrior"] == 1
    and counts.subgroups["service:innkeeper"] == 1, "sub-group counts follow the grouped rows")
M.subgroup = nil

if not M.window then M:CreateWindow() end
local w = M.window
local savedScope, savedZone = M.scope, M.zoneMap
M.scope, M.zoneMap = "zone", nil
M.kind, M.category = "all", "All"
M:UpdateCategories()
assert(w.categoryButtons[2]:IsShown() and w.categoryButtons[4]:GetText() == "Trainers (2)"
    and w.subgroupButtons[4]:IsShown(), "All entries exposes useful counted category/sub-group shortcuts")
w.categoryButtons[4]:Click()
assert(M.kind == "npc" and M.category == "Trainers" and #M.results == 2,
    "the trainer shortcut selects its type and category together")
M.kind, M.category = "all", "All"
M:UpdateCategories()
w.subgroupButtons[4]:Click()
assert(M.kind == "npc" and M.category == "Trainers" and w.subpicker:IsShown(),
    "a sub-group shortcut from All entries opens the correct type's picker")
w.subpicker:Hide()
M.kind, M.category = "all", "All"
M:UpdateCategories()
w.categoryButtons[6]:Click()
assert(M.kind == "location" and M.category == "Objects",
    "the object shortcut selects static locations rather than leaving an invalid mixed category")
M.kind = "npc"
M.category = "All"
M:UpdateCategories()
assert(M.categories.npc[4] == "Trainers" and w.subgroupButtons[4]:IsShown() and not w.subgroupButtons[1]:IsShown(),
    "only categories with sub-groups offer the picker")
w.categoryButtons[4]:Click()
assert(M.category == "Trainers" and #M.results == 2)
w.subgroupButtons[4]:Click()
assert(w.subpicker:IsShown() and w.subpicker.category == "Trainers")
local texts = {}
for _, data in ipairs(w.subpicker.data) do table.insert(texts, (data.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
texts = table.concat(texts, ";")
assert(texts:find("All Trainers  (2)", 1, true) and texts:find("Warrior  (1)", 1, true) and texts:find("Alchemy  (1)", 1, true)
    and texts:find("Class trainers", 1, true) and not texts:find("Fishing", 1, true), "empty sub-groups are hidden: " .. texts)
w.subpicker.filter:SetText("alch")
assert(#w.subpicker.data == 3 and w.subpicker.data[3].key == "trainer:alchemy", "the filter narrows the picker")
w.subpicker.rows[3]:Click()
assert(not w.subpicker:IsShown() and M.subgroup == "trainer:alchemy" and #M.results == 1)
assert(M.results[1].record.npcID == 11)
assert(w.categoryButtons[4]:GetText() == "Trainers: Alchemy (1)", w.categoryButtons[4]:GetText())
assert(w.filters:GetText():find("Alchemy", 1, true), "the breadcrumb names the sub-group")
w.subgroupButtons[4]:Click()
w.subpicker.rows[1]:Click()
assert(M.subgroup == nil and #M.results == 2, "the All row clears the sub-group")
w:Show()
w.subgroupButtons[4]:Click()
for _, key in ipairs({ "options", "reviewFrame", "copyFrame", "detailsFrame", "itemFrame", "modelFrame" }) do
    if M[key] then M[key]:Hide() end
end
w:GetScript("OnKeyDown")(w, "ESCAPE")
assert(not w.subpicker:IsShown() and w:IsShown(), "Escape closes the sub-group picker first ")
M.subgroup = "trainer:warrior"
w.categoryButtons[4]:Click()
assert(M.subgroup == nil, "clicking the category clears its sub-group")
M:JumpToSubgroup("alchemy trainer")
assert(M.kind == "npc" and M.category == "Trainers" and M.subgroup == "trainer:alchemy" and #M.results == 1)
M:JumpToSubgroup("warrior")
assert(M.subgroup == "trainer:warrior" and M.results[1].record.npcID == 12)
M.kind, M.category, M.subgroup = "all", "All", nil
M.scope, M.zoneMap = savedScope, savedZone
M:UpdateCategories()
if not M.window then M:CreateWindow() end
M:Query("zone", "npc", "All", "alchemy", "directory")
M.selected, M.offset = 1, 0
M:Render()
assert(M.window.rows[1].name:GetText():find("<Alchemy Trainer>", 1, true), "rows must show NPC titles")
assert(M.window.info.title:GetText() == "<Alchemy Trainer>", "the details pane must follow the selection")
assert(M.window.info.body:GetText():find("Monstrator database", 1, true))
assert(not M.window.rows[1].detail:GetText():find("NPC ID", 1, true), "rows reserve technical IDs for details")
assert(M.window.info.identity:GetText():find("NPC ID 11", 1, true), "technical identity remains available")
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

-- Noise gate: only sightings that add to the database become journal records, and repeats collapse.
local function sighting(npcID, name, x, y, fields)
    playerMap, playerX, playerY = 1, x / 100, y / 100
    local record = M:NewObservation(name, "npc", "Combat", {}, "UPDATE_MOUSEOVER_UNIT")
    record.npcID = npcID
    for key, value in pairs(fields or {}) do record[key] = value end
    return record
end
assert(M:ObservationNovelty(sighting(11, "Harn Longcast", 22, 31)) == nil, "a sighting at a database spawn is not novel")
assert(M:ObservationNovelty(sighting(11, "Harn Longcast", 40, 30)) == "position")
assert(M:ObservationNovelty(sighting(99999, "Forever Newcomer", 1, 1)) == "new")
assert(M:ObservationNovelty(sighting(13, "Tal", 47, 50)) == "map")
assert(M:ObservationNovelty(sighting(11, "Harn Longcast", 20, 30, { title = "Herbalism Trainer" })) == "title")
assert(M:ObservationNovelty(sighting(10, "Innkeeper Kauth", 40, 50, { level = 45 })) == "level")
assert(M:ObservationNovelty(sighting(10, "Innkeeper Kauth", 40, 50, { level = 30 })) == nil)
local vendorSighting = sighting(11, "Harn Longcast", 20, 30)
vendorSighting.tags = { "vendor" }
assert(M:ObservationNovelty(vendorSighting) == "service", "a service the database lacks is novel")
vendorSighting.tags = { "trainer" }
assert(M:ObservationNovelty(vendorSighting) == nil)

M.observations = { entries = {}, nextID = 1 }
local first = M:AddObservation(sighting(99999, "Forever Newcomer", 10, 10))
local again = M:AddObservation(sighting(99999, "Forever Newcomer", 13, 12))
assert(first and again == first and first.sightings == 2, "pending sightings within the encounter radius merge")
first.verification = "user-confirmed"
M:SealRecord(first)
assert(M:AddObservation(sighting(99999, "Forever Newcomer", 11, 11)) == first and first.sightings == 2,
    "confirmed placements absorb repeats without being edited")
local far = M:AddObservation(sighting(99999, "Forever Newcomer", 30, 30))
assert(far and far ~= first, "a distinct placement is a new record")
local count = 0
for _ in pairs(M.observations.entries) do count = count + 1 end
assert(count == 2)

-- Prune drops noise, database matches and repeats from an existing journal; submission skips the same.
M.observations = { entries = {}, nextID = 1 }
local function put(record, verification)
    M.observations.nextID = M.observations.nextID + 1
    record.key = "local:" .. M.observations.nextID
    record.verification = verification or "user-confirmed"
    M:SealRecord(record)
    M.observations.entries[record.key] = record
end
put(sighting(99999, "Forever Newcomer", 10, 10))
put(sighting(99999, "Forever Newcomer", 12, 10), "pending")
put(sighting(99999, "Forever Newcomer", 50, 50))
put(sighting(11, "Harn Longcast", 20, 30))
put(sighting(99998, "Prairie Dog", 5, 5, { creatureType = "Critter" }))
local repeatTrainer = sighting(99999, "Forever Newcomer", 11, 10)
repeatTrainer.tags = { "trainer" }
put(repeatTrainer)
local savedScanLog = M.settings.scanLog
M.settings.scanLog = {}
local text, submitted = M:SubmissionText()
M.settings.scanLog = savedScanLog
assert(submitted == 4 and not text:find("Harn Longcast", 1, true) and not text:find("Prairie Dog", 1, true),
    "submissions carry only records that add to the database")
local pruneCounts, removedCount = M:PruneJournal(false)
assert(removedCount == 3 and pruneCounts.noise == 1 and pruneCounts.known == 1 and pruneCounts.duplicate == 1
    and pruneCounts.kept == 3)
count = 0
for _ in pairs(M.observations.entries) do count = count + 1 end
assert(count == 6, "a preview must not delete")
M:PruneJournal(true)
count = 0
for _, record in pairs(M.observations.entries) do
    count = count + 1
    assert(record.name == "Forever Newcomer" and record.verification == "user-confirmed")
end
assert(count == 3, "prune keeps distinct placements and sightings that add a service")
local petSighting = sighting(11, "Gelmir", 20, 30, { creatureType = "Demon" })
assert(M:IsNoiseRecord(petSighting), "a known ID under a player-given name is a pet or summon")
assert(not M:IsNoiseRecord(sighting(11, "Harn Longcast", 20, 30, { creatureType = "Humanoid" })))
assert(not M:IsNoiseRecord(sighting(11, "Harn the Renamed", 20, 30, { creatureType = "Humanoid" })),
    "humanoid renames are reviewed, not discarded")
assert(M:IsNoiseRecord(sighting(99999, "Unknown", 1, 1)))
assert(M:IsNoiseRecord(sighting(99998, "Wardrobe", 1, 1, { creatureType = "Not specified", reaction = 5 })),
    "an untyped, non-hostile unit with no service is a world prop")
assert(not M:IsNoiseRecord(sighting(99998, "Living Lightning", 1, 1, { creatureType = "Not specified", reaction = 2 })),
    "hostile untyped creatures are real encounters")
assert(not M:IsNoiseRecord(sighting(99998, "Wardrobe", 1, 1, { creatureType = "Not specified", reaction = 5,
    tags = { "vendor" } })), "a prop that offers a service is kept")

-- One identity per NPC: database rows and journal rows agree on category, sub-group and title, and group together.
N[19] = "Zephras Citizen\t\t0\t10\t10\tAH\t2:80,80"
N[20] = "Zerril Softbreeze\t\t0\t20\t20\t\t2:60,60"
N[21] = "Aedi Thriceforged\t\t16\t20\t20\t\t2:62,62"
M.observations = { entries = {}, nextID = 1 }
local function seen2(npcID, name, x, y, category, tags, fields)
    playerMap, playerX, playerY = 2, x / 100, y / 100
    local record = M:NewObservation(name, "npc", category, tags, "GOSSIP_SHOW")
    record.npcID, record.reaction = npcID, 5
    for key, value in pairs(fields or {}) do record[key] = value end
    return record
end
put(seen2(19, "Zephras Citizen", 81, 80, "Combat", {}))
put(seen2(20, "Zerril Softbreeze", 61, 60, "Services", {}, { title = "Cook" }))
put(seen2(20, "Zerril Softbreeze", 62, 61, "Combat", { "trainer" }))
local locked = seen2(19, "Zephras Citizen", 90, 90, "Services", {})
locked.categoryLocked = true
put(locked)
M.native.provider, M.dbIndex, M.dbCache = nil, nil, {}
M:StartDatabaseIndex()
assert(M:NPCIdentity(0, nil, true) == "Unclassified", "friendly NPCs without a service are not combat targets")
M:BuildIndex()
local journalCitizen, journalZerril = {}, {}
for _, record in pairs(M.observations.entries) do
    assert(M:RecordSealValid(record), "normalized journal records keep a valid seal")
    if record.npcID == 19 and not record.categoryLocked then table.insert(journalCitizen, record) end
    if record.npcID == 20 then table.insert(journalZerril, record) end
end
assert(locked.category == "Services", "a category picked in review is kept")
assert(journalCitizen[1].category == "Unclassified")
for _, record in ipairs(journalZerril) do
    assert(record.category == "Trainers" and record.title == "Cook", "every record of one NPC shares its identity")
    assert(table.concat(M:RecordSubgroups(record), ",") == "trainer:cooking")
end
local dbByID = {}
for _, record in ipairs(M:DatabaseMapRecords(2)) do dbByID[record.npcID] = record end
assert(dbByID[19].category == "Unclassified")
assert(dbByID[20].category == "Trainers" and dbByID[20].title == "Cook",
    "journal-seen services and subtitles reach the database row")
assert(table.concat(M:RecordSubgroups(dbByID[20]), ",") == "trainer:cooking")
assert(table.concat(M:RecordSubgroups(dbByID[21]), ",") == "trainer:other")
M.trainerSnapshots = { [21] = { npcID = 21, services = { { name = "Blacksmithing" }, { name = "Rough Copper Vest" } } } }
assert(table.concat(M:RecordSubgroups(dbByID[21]), ",") == "trainer:blacksmithing",
    "an untitled trainer is filed by the profession its trainer window teaches")
M.trainerSnapshots = { [21] = { npcID = 21, services = { { name = "Cooking" }, { name = "Brilliant Smallfish" } } } }
assert(table.concat(M:RecordSubgroups(dbByID[21]), ",") == "trainer:cooking", "recipe names do not count")
M.trainerSnapshots = nil
playerMap, playerX, playerY = 2, 0.6, 0.6
M.settings.evidenceFilter = "all"
local zerrilRows = 0
for _, entry in ipairs(M:Query("zone", "npc", "Trainers", "", "directory")) do
    if entry.record.npcID == 20 then zerrilRows = zerrilRows + 1 end
end
assert(zerrilRows == 1, "journal and database placements of one NPC form a single row; got " .. zerrilRows)
assert(M:DirectoryCounts("zone", "").subgroups["trainer:cooking"] == 1)
N[19], N[20], N[21] = nil, nil, nil
M.native.provider = nil
M.native, M.dbIndex, M.dbCache = saved.native, saved.index, saved.cache
M.data.entries, M.observations, M.clientData = saved.data, saved.observations, saved.clientData
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = saved.enabled, saved.filter, saved.grouping
playerMap, playerX, playerY = saved.map, saved.x, saved.y
M.ShowCopy = saved.showCopy
M:BuildIndex()
