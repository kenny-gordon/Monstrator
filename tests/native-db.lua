local saved = { native = M.native, index = M.dbIndex, cache = M.dbCache,
    data = M.data.entries, observations = M.observations, clientData = M.clientData,
    enabled = M.settings.referenceEnabled, filter = M.settings.evidenceFilter, grouping = M.settings.groupNPCs,
    map = playerMap, x = playerX, y = playerY, items = M.items, itemSearch = M.itemSearch,
    transforms = M.mapTransforms, notice = M.Notice }

-- Fixture in the exact format tools\monstrator-db.cjs import/overlay write (tab-separated, spawns keyed by UiMap).
M.native = { data = {}, meta = {} }
assert(M:NativeProvider() == nil, "no native data registered means no native provider")
local N = M.NativeData("Npc", "1.0.4", "Forever", "abc", "ExampleDB")
N[10] = "Innkeeper Kauth\tInnkeeper\t131\t30\t30\tH\t1:40,50 41,51"
N[11] = "Harn Longcast\tAlchemy Trainer\t17\t\t\t\t1:20,30"
N[13] = "Tal\tWind Rider Master\t8\t\t\tH\t2:47,50"
N[14] = "Plainstrider\t\t0\t\t\t\t777:1,1"
N[15] = "[DND] Quest Trigger\t\t0\t\t\t\t1:5,5"
N[16] = "Moorat Longstride\tArmorer\t16388\t\t\tAH\t1:60.125,60;2:10,10"
N[17] = "Waypoint (Only GM can see it)\t\t0\t1\t1\tAH\t"
N[20] = "Butcher Near\tMeat Vendor\t4\t\t\t\t1:41,50"
N[22] = "Angry Boar\t\t0\t11\t12\t\t1:10,10 45,52"
local O = M.NativeData("Object", "1.0.4", "Forever", "abc")
O[50] = "Linen Crate\t1:50,50"
O[51] = "Mailbox\t1:46.1,40.2;2:1e-05,99\tmailbox"
local I = M.NativeData("Item", "1.0.4", "Forever", "abc")
I[2672] = "Haunch of Meat\t5\t15\t0\t0\t\t20\t22\t\t900\t"
I[2589] = "Linen Cloth\t\t\t7\t5\t\t\t22\t50\t\t"
I[3000] = "Mysterious Letter\t\t\t12\t0\t900\t\t\t\t\t"
local Q = M.NativeData("Quest", "1.0.4", "Forever", "abc")
Q[900] = "Meat Run\t6\t4\t11\t\t10,11\t51"

local lib = M:NativeProvider()
assert(lib and lib.native and lib.version == "1.0.4" and M:NativeProvider() == lib, "the native provider must be cached")
assert(lib.imported and lib.source == "ExampleDB", "imported base data must keep its source for attribution")
assert(lib.areaMap == nil and lib.addonName == nil, "the native provider must not retain unused addon adapters")
local ids = lib.Npc.GetAllIds()
assert(#ids == 9 and ids[1] == 10 and ids[9] == 22, "IDs must be sorted")
assert(lib.Npc.name(10) == "Innkeeper Kauth" and lib.Npc.subName(10) == "Innkeeper" and lib.Npc.npcFlags(10) == 131)
assert(lib.Npc.minLevel(10) == 30 and lib.Npc.maxLevel(10) == 30 and lib.Npc.friendlyToFaction(10) == "H")
assert(lib.Npc.subName(22) == nil and lib.Npc.maxLevel(11) == nil and lib.Npc.friendlyToFaction(11) == nil,
    "empty fields must decode to nil")
assert(lib.Npc.name(999) == nil and lib.Npc.spawns(999) == nil, "unknown IDs must return nil")
local spawns = lib.Npc.spawns(16)
assert(#spawns[1] == 1 and spawns[1][1][1] == 60.125 and spawns[1][1][2] == 60 and spawns[2][1][1] == 10,
    "spawns must decode exactly per map")
assert(lib.Npc.spawns(17) == nil, "NPCs without spawns must return nil")
local maps = lib.Npc.mapIDs(16)
assert(maps[1] and maps[2] and not maps[3])
assert(lib.Object.spawns(51)[2][1][1] == 1e-05, "exponent-formatted coordinates must decode losslessly")
assert(table.concat(lib.Item.vendors(2672), ",") == "20" and table.concat(lib.Item.questRewards(2672), ",") == "900")
assert(lib.Item.vendors(2589) == nil and table.concat(lib.Item.objectDrops(2589), ",") == "50")
assert(lib.Item.itemLevel(2672) == 15 and lib.Item.class(2589) == 7 and lib.Item.startQuest(3000) == 900)
assert(lib.Quest.starterNpcs(900)[1] == 11 and lib.Quest.starterObjects(900) == nil
    and #lib.Quest.finisherNpcs(900) == 2 and lib.Quest.finisherObjects(900)[1] == 51)
assert(lib.Quest.starterNpcs(1) == nil and lib.Quest.questLevel(900) == 6 and lib.Quest.requiredLevel(900) == 4)
assert(lib.Quest.startedBy == nil and lib.Quest.finishedBy == nil, "quest fields are read directly without legacy adapters")

-- The directory, item lookup and waypoints run entirely from native data.
local notices = {}
M.Notice = function(_, text) table.insert(notices, text) end
M.data.entries, M.observations = {}, { entries = {}, nextID = 1 }
M.clientData, M.dbCache, M.dbIndex = { maps = {}, errors = {}, generation = 0 }, {}, nil
M.items, M.itemSearch, M.mapTransforms = nil, nil, nil
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = true, "all", true
M:StartDatabaseIndex()
assert(M:DatabaseReady() and M.dbIndex.lib == lib)
assert(M.dbIndex.mapCount == 2 and M.dbIndex.npcCount == 7 and M.dbIndex.objectCount == 1, "unknown UiMaps and spawnless NPCs must be excluded")
local loaded = false
for _, text in ipairs(notices) do loaded = loaded or text:find("Monstrator database 1.0.4 loaded", 1, true) ~= nil end
assert(loaded, "the load notice must name the Monstrator database")
local records = M:DatabaseMapRecords(1)
local npcRecords = 0
for _, record in ipairs(records) do if record.kind == "npc" then npcRecords = npcRecords + 1 end end
assert(npcRecords == 7, "internal NPCs must be dropped; got " .. npcRecords)
for _, record in ipairs(records) do
    local ok, reason = M:ValidateRecord(record)
    assert(ok, reason)
    assert(record.source:find("^monstrator%-db:") and record.permission:find("ExampleDB contributors", 1, true))
end
assert(M:DataSourceLabel() == "Monstrator DB")
assert(M:DataSourceSummary():find("Data: Monstrator DB 7 NPCs / 2 zones", 1, true), M:DataSourceSummary())
playerMap, playerX, playerY = 1, 0.4, 0.5
M:BuildIndex()
clock = clock + 1
assert(#M:Query("zone", "npc", "All", "alchemy", "directory") == 1)
if not M.window then M:CreateWindow() end
M.selected, M.offset = 1, 0
M:Render()
assert(M.window.info.body:GetText():find("Monstrator database", 1, true), "details must credit the native database")
local waypoints = {}
TomTom = { AddWaypoint = function(_, mapID, x, y, options) table.insert(waypoints, { mapID, x, y, options.title }); return {} end,
    IsValidWaypoint = function() return true end, SetCrazyArrow = function() end }
M:NavigateRecord(M.results[1].record)
assert(waypoints[1] and waypoints[1][4]:find("[Monstrator DB]", 1, true), tostring(waypoints[1] and waypoints[1][4]))

assert(M:ItemProvider() == lib)
local state = M:StartItemIndex()
assert(state.ready and #state.list == 3 and state.byNPC[22] and #state.byNPC[22] == 2)
local details = M:ItemDetails(2672)
assert(details.itemLevel == 15 and #details.vendor == 1 and #details.drop == 1)
local quest = M:ResolveItemSources(details, "quest")
assert(quest[1] and quest[1].id == 11 and quest[1].questName == "Meat Run", "quest rewards must resolve to the native quest giver")
local gathered = M:ResolveItemSources(M:ItemDetails(2589), "object")
assert(gathered[1].name == "Linen Crate" and gathered[1].mapID == 1 and gathered[1].x == 50)
local vendor = M:ResolveItemSources(details, "vendor")[1]
assert(vendor.name == "Butcher Near" and math.abs(vendor.distance - 10) < 0.01)
local record = M:SourceRecord(vendor)
assert(M:ValidateRecord(record) and record.source:find("^monstrator%-db:"))
TomTom = nil

-- Item lookup must not depend on the NPC index having started (reference data toggled off).
M.dbIndex, M.items, M.itemSearch = nil, nil, nil
M.settings.referenceEnabled = false
assert(M:ItemProvider() == lib and M:StartItemIndex().ready)
local offline = M:ResolveItemSources(M:ItemDetails(2672), "vendor")[1]
assert(offline.mapID == 1 and M:ValidateRecord(M:SourceRecord(offline)), "item sources must resolve without the NPC index")

-- Loot imports supplement reference relationships, never placements or corrected item rows.
M.native.lootReference = { source = "AtlasLootClassic", drops = { [2589] = "11,22,999", [999] = "11" } }
M.native.provider, M.items, M.itemSearch = nil, nil, nil
local enriched = M:NativeProvider()
assert(table.concat(enriched.Item.npcDrops(2589), ",") == "22,11", "new drops append without duplicating base drops or unknown NPCs")
assert(enriched.Item.npcDrops(999) == nil, "loot imports cannot create unknown items")
assert(enriched.Item.npcDropReference(2589, 11) == "AtlasLootClassic"
    and enriched.Item.npcDropReference(2589, 22) == nil, "only supplementary relationships carry AtlasLoot attribution")
M:StartItemIndex()
assert(#M:SearchItems("", 11) == 1 and M:SearchItems("", 11)[1] == 2589,
    "NPC item lists include imported loot without an AtlasLoot addon")
local lootSources = M:ResolveItemSources(M:ItemDetails(2589), "drop")
local added
for _, source in ipairs(lootSources) do if source.id == 11 then added = source end end
assert(added and added.lootReference == "AtlasLootClassic" and added.x == 20 and added.y == 30,
    "loot sources preserve attribution and use existing Monstrator coordinates")
assert(M:SourceRecord(added).verification == "reference", "loot imports must not promote sources to verified")
M:ShowItemLookup("2589")
M.itemTab = "drop"
M:RenderItemWindow()
local visible
for _, row in ipairs(M.itemFrame.sourceRows) do
    if row.source and row.source.id == 11 then
        visible = row
        assert(row.detail:GetText():find("AtlasLootClassic", 1, true), "imported loot is visibly attributed")
    end
end
assert(visible, "imported loot appears in item lookup")
local tooltip, originalAddLine = {}, GameTooltip.AddLine
GameTooltip.AddLine = function(_, text) tooltip[#tooltip + 1] = text end
visible:GetScript("OnEnter")(visible)
GameTooltip.AddLine = originalAddLine
assert(tooltip[1] == M.L["AtlasLoot reference (not Forever-confirmed)"], "loot tooltip discloses Classic reference status")
local correctedItems, itemOrigins = M.NativeOverlay("Item")
correctedItems[2589], itemOrigins[2589] = I[2589], "correction"
local corrected = M:NativeProvider()
assert(table.concat(corrected.Item.npcDrops(2589), ",") == "22" and not corrected.Item.npcDropReference(2589, 11),
    "explicit item corrections override all supplementary reference drops")
correctedItems[2589] = false
M.native.provider = nil
assert(M:NativeProvider().Item.npcDrops(2589) == nil, "a deleted item is not resurrected by imported loot")

-- Standalone build: no imported base rows, only Monstrator's own overlay. Everything must still work.
M.native = { data = {}, meta = {} }
assert(M:NativeProvider() == nil, "an empty standalone database has no provider")
local SD, SO = M.NativeOverlay("Npc")
SD[30], SO[30] = "Scout Rhea\tFlight Master\t8\t40\t40\tH\t1:30,30", "discovery"
SD[31], SO[31] = "Kara Fernwhisper\tFood & Drink\t132\t\t\t\t1:31,31", "correction"
local own = M:NativeProvider()
assert(own and not own.imported and own.source == nil and own.version == "local", "overlay-only data must be served")
assert(#own.Npc.GetAllIds() == 2 and own.Npc.name(30) == "Scout Rhea" and own.Npc.spawns(31)[1][1][1] == 31)
assert(own.Item == nil and own.Quest == nil, "kinds without data stay absent")
local counts, meta, overlays = M:NativeSummary()
assert(counts.Npc == 2 and meta == nil and overlays.discovery == 1 and overlays.correction == 1)
local _, permission = M:DatabaseProvenance()
assert(permission:find("Monstrator discoveries", 1, true) and not permission:find("ExampleDB", 1, true),
    "standalone records must not credit a source they do not contain")
M.dbIndex, M.dbCache, M.items, M.itemSearch = nil, {}, nil, nil
M.settings.referenceEnabled = true
M:StartDatabaseIndex()
assert(M:DatabaseReady() and M.dbIndex.npcCount == 2, "the directory must index overlay-only NPCs")
M:StartItemIndex()
M.observations = { entries = { a = { kind = "npc", npcID = 99, name = "New", mapID = 1, x = 1, y = 1, verification = "pending" } }, nextID = 2 }
local copied
local savedCopy = M.ShowCopy
M.ShowCopy = function(_, text) copied = text end
local groups = M:AuditObservations()
M.ShowCopy = savedCopy
assert(groups and #groups.new == 1 and copied, "the journal audit must work with a partial database")
local diag = {}
M.Notice = function(_, text) table.insert(diag, text) end
M:Diagnostic()
local standaloneLine = false
for _, text in ipairs(diag) do standaloneLine = standaloneLine or text:find("Standalone build", 1, true) ~= nil end
assert(standaloneLine, "the diagnostic must report a standalone database")
M.native = { data = {}, meta = {} }
diag = {}
M:Diagnostic()
M.native, M.Notice = saved.native, saved.notice
M.dbIndex, M.dbCache = saved.index, saved.cache
M.items, M.itemSearch, M.mapTransforms = saved.items, saved.itemSearch, saved.transforms
M.data.entries, M.observations, M.clientData = saved.data, saved.observations, saved.clientData
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = saved.enabled, saved.filter, saved.grouping
playerMap, playerX, playerY = saved.map, saved.x, saved.y
M:BuildIndex()
