local saved = { native = M.native, index = M.dbIndex, cache = M.dbCache,
    data = M.data.entries, observations = M.observations, clientData = M.clientData,
    enabled = M.settings.referenceEnabled, filter = M.settings.evidenceFilter, grouping = M.settings.groupNPCs,
    map = playerMap, x = playerX, y = playerY, notice = M.Notice, err = M.Error }

-- A lib-shaped provider (the interface NativeProvider exposes), installed directly so getters can misbehave.
local npcs = {
    [20] = { name = "Butcher Near", title = "Meat Vendor", flags = 4, spawns = { [1] = { { 41, 50 } } } },
    [21] = { name = "Butcher Far", title = "Meat Vendor", flags = 4, spawns = { [1] = { { 90, 90 } } } },
    [22] = { name = "Angry Boar", flags = 0, level = 12, friendly = "", spawns = { [1] = { { 10, 10 }, { 45, 52 } } } },
    [23] = { name = "Quest Giver", flags = 2, spawns = { [1] = { { 30, 30 } } } },
    [24] = { name = "Linen Seller", flags = 4, spawns = { [1] = { { 70, 70 } } } },
}
local npcIDs = {}
for id in pairs(npcs) do table.insert(npcIDs, id) end
table.sort(npcIDs)
local items = {
    [2672] = { name = "Haunch of Meat", vendors = { 21, 20 }, drops = { 22 }, rewards = { 900 }, req = 5 },
    [2589] = { name = "Linen Cloth", vendors = { 24 }, drops = { 22 }, objects = { 50 } },
    [100] = { name = "Meaty Haunch Deluxe" },
    [101] = { name = "Haunch" },
    [102] = { name = "" },
}
local itemIDs = { 100, 101, 102, 2589, 2672 }
local function getter(source, field) return function(id) return source[id] and source[id][field] end end
local provider = {
    native = true, version = "1.0.4",
    Npc = { GetAllIds = function() return npcIDs end, name = getter(npcs, "name"), spawns = getter(npcs, "spawns"),
        mapIDs = getter(npcs, "spawns"),
        subName = getter(npcs, "title"), npcFlags = getter(npcs, "flags"), maxLevel = getter(npcs, "level"),
        friendlyToFaction = getter(npcs, "friendly") },
    Item = { GetAllIds = function() return itemIDs end, name = getter(items, "name"), vendors = getter(items, "vendors"),
        npcDrops = getter(items, "drops"), objectDrops = getter(items, "objects"), questRewards = getter(items, "rewards"),
        requiredLevel = getter(items, "req"), itemLevel = function() error("broken getter must be contained") end },
    Object = { name = function(id) if id == 50 then return "Linen Crate" end end,
        spawns = function(id) if id == 50 then return { [1] = { { 50, 50 } } } end end },
    Quest = { name = function(id) if id == 900 then return "Meat Run" end end,
        starterNpcs = function(id) if id == 900 then return { 23 } end end, questLevel = function() return 6 end },
}

M.data.entries, M.observations = {}, { entries = {}, nextID = 1 }
M.native = { data = {}, meta = {}, provider = provider }
M.clientData, M.dbCache, M.dbIndex = { maps = {}, errors = {}, generation = 0 }, {}, nil
M.items, M.itemSearch, M.mapTransforms = nil, nil, nil
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = true, "all", true
M:StartDatabaseIndex()
assert(M:DatabaseReady())
assert(M:ItemProvider() == provider, "a provider with an Item API must be accepted")

local state = M:StartItemIndex()
assert(state and state.ready, "small item lists must index in one slice")
assert(#state.list == 4, "nameless items must be skipped")
assert(M:StartItemIndex() == state, "the item index must only be built once")
assert(table.concat(state.byNPC[22], ",") == "2589,2672" or table.concat(state.byNPC[22], ",") == "2672,2589")
assert(#state.byNPC[20] == 1 and state.byNPC[20][1] == 2672, "vendors must map back to the items they sell")

local results = M:SearchItems("haunch")
assert(#results == 3, "token search must match every item containing the word")
assert(results[1] == 101, "exact names must rank first")
assert(results[2] == 2672, "prefix matches must rank before substring matches")
assert(M:SearchItems("  HAUNCH  ")[1] == 101, "searches must ignore case and surrounding spaces")
assert(#M:SearchItems("meat haunch") == 2, "multi-word searches must require every token")
results = M:SearchItems("2589")
assert(results[1] == 2589, "numeric searches must find items by ID")
assert(#M:SearchItems("") == 0, "an empty search lists nothing until the user types")
results = M:SearchItems("", 22)
assert(#results == 2 and results[1] == 2672 and results[2] == 2589, "NPC item lists must be sorted by name")
assert(#M:SearchItems("linen", 20) == 0, "NPC item lists must only include that NPC's items")

local errors = {}
M.Error = function(_, message) errors[#errors + 1] = message end
local details = M:ItemDetails(2672)
M:ItemDetails(2672)
assert(#errors == 1 and errors[1]:find("Native database getter failed for ID 2672", 1, true),
    "a broken native getter is contained and reported once, never silently ignored")
M.Error = saved.err
assert(details.name == "Haunch of Meat" and details.requiredLevel == 5 and details.itemLevel == nil)
assert(#details.vendor == 2 and #details.drop == 1 and #details.quest == 1 and #details.object == 0)

playerMap, playerX, playerY = 1, 0.4, 0.5
local vendors = M:ResolveItemSources(details, "vendor")
assert(#vendors == 2 and vendors[1].id == 20 and vendors[2].id == 21, "sources must be sorted nearest first")
assert(vendors[1].mapID == 1 and vendors[1].x == 41 and vendors[1].y == 50)
assert(math.abs(vendors[1].distance - 10) < 0.01, "distances must use world coordinates; got " .. tostring(vendors[1].distance))
assert(vendors[1].title == "Meat Vendor")
local drops = M:ResolveItemSources(details, "drop")
assert(drops[1].x == 45 and drops[1].y == 52 and drops[1].count == 2, "drops must point at the nearest of all spawns")
assert(drops[1].level == 12)
local quests = M:ResolveItemSources(details, "quest")
assert(quests[1].kind == "npc" and quests[1].id == 23 and quests[1].questName == "Meat Run" and quests[1].questLevel == 6,
    "quest rewards must resolve to the quest giver")
local objects = M:ResolveItemSources(M:ItemDetails(2589), "object")
assert(objects[1].kind == "object" and objects[1].name == "Linen Crate" and objects[1].x == 50)
local record = M:SourceRecord(vendors[1])
assert(select(2, M:ValidateRecord(record)) == nil, select(2, M:ValidateRecord(record)) or "item sources must produce valid waypoint records")
assert(record.npcID == 20 and record.kind == "npc")
assert(M:SourceRecord(objects[1]) == nil, "objects are not NPC reference records")
local waypoints = {}
TomTom = { AddWaypoint = function(_, mapID, x, y, options) table.insert(waypoints, { mapID, x, y, options.title }); return {} end,
    IsValidWaypoint = function() return true end, SetCrazyArrow = function() end }
assert(M:NavigateSource(vendors[1]) and waypoints[1][1] == 1 and waypoints[1][4]:find("Butcher Near", 1, true))
assert(M:NavigateSource(objects[1]) and waypoints[2][2] == 0.5 and waypoints[2][4]:find("Linen Crate", 1, true),
    "object sources must still get a waypoint")
TomTom = nil
assert(M:SourceRecord({ kind = "quest", id = 1, name = "x" }) == nil, "sources without a location cannot be navigated")

-- The item window
M:ShowItemLookup("haunch")
local f = M.itemFrame
assert(f and f:IsShown())
assert(f.template == "PortraitFrameTemplate" and f.CloseButton:GetScript("OnClick"),
    "item lookup uses the same native window chrome as the directory")
assert(M.itemResults[1] == 101 and M.itemDetails.id == 101)
assert(f.empty:IsShown() == false)
assert(f.itemRows[1].name:GetText():find("Haunch", 1, true))
assert(f.itemRows[4]:IsShown() == false, "unused item rows must be hidden")
M.itemSelectedIndex = 2
M:RefreshItemWindow()
assert(M.itemDetails.id == 2672)
assert(M.itemTab == "vendor", "the first tab with sources must be chosen")
assert(f.tabs.vendor:GetText() == "Sold by (2)", f.tabs.vendor:GetText())
assert(f.sourceRows[1].name:GetText() == "Butcher Near")
assert(f.sourceRows[1].distance:GetText() == "10 yd")
assert(f.sourceRows[1].detail:GetText():find("<Meat Vendor>", 1, true))
assert(f.detailInfo:GetText():find("Requires level 5", 1, true))

M:ShowItemSourcesInDirectory()
assert(M.npcFilter and M.npcFilter.ids[20] and M.npcFilter.ids[21] and M.npcFilter.ids[22] and not M.npcFilter.ids[23])
assert(M.scope == "global" and M.kind == "npc" and M.view == "directory")
local found = {}
for _, entry in ipairs(M.results) do found[entry.record.npcID] = true end
assert(found[20] and found[21] and found[22] and not found[23] and not found[24],
    "the directory must only list the item's sources")
assert(M.window.clearFilter:IsShown(), "a clear button must be offered while filtering")
assert(M:BreadcrumbText():find("Sources of Haunch of Meat", 1, true))
M.window.clearFilter:Click()
assert(M.npcFilter == nil and not M.window.clearFilter:IsShown())
found = {}
for _, entry in ipairs(M:Query("global", "npc", "All", "", "directory")) do found[entry.record.npcID] = true end
assert(found[23] and found[24], "clearing the filter must restore every NPC")

-- Details pane buttons and the NPC item list
M:Query("global", "npc", "All", "butcher near", "directory")
M.selected, M.offset = 1, 0
M:Render()
assert(M.window.info.model:IsShown() and M.window.info.items:IsShown(), "NPC details must offer the model and item buttons")
M.window.info.items:Click()
assert(M.itemNPC and M.itemNPC.id == 20 and #M.itemResults == 1 and M.itemResults[1] == 2672)
assert(f.status:GetText():find("Butcher Near", 1, true))
f.clearNPC:Click()
assert(M.itemNPC == nil)

-- 3D viewer
pendingTimers = {}
M.window.info.model:Click()
local viewer = M.modelFrame
assert(viewer and viewer:IsShown() and viewer.kind == "npc" and viewer.id == 20)
assert(viewer.title:GetText() == "Butcher Near")
local function drainTimers()
    for _ = 1, 20 do
        local timers = pendingTimers
        pendingTimers = {}
        for _, callback in ipairs(timers) do callback() end
    end
end
drainTimers()
assert(viewer.status:GetText():find("did not send this NPC", 1, true), "uncached creatures must explain why nothing shows")
assert(viewer.fallback:IsShown() and not viewer.model:IsShown(), "a missing NPC model must show the fallback icon")
viewer.model.GetModelFileID = function() return 12345 end
M:ShowModel("npc", 20, "Butcher Near")
assert(viewer.status:GetText():find("NPC ID 20", 1, true))
assert(viewer.model:IsShown() and not viewer.fallback:IsShown(), "a loaded NPC model replaces the fallback")

-- Items: wearable ones go on the character, everything else shows its icon instead of an empty stage.
local itemSlots = { [2672] = { "", "food.blp" }, [9001] = { "INVTYPE_CHEST", "chest.blp" }, [9002] = { "INVTYPE_FINGER", "ring.blp" } }
GetItemInfoInstant = function(id) local s = itemSlots[id]; if s then return id, "", "", s[1], s[2] end end
M:ShowModel("item", 2672, "Haunch of Meat")
assert(viewer.kind == "item" and not viewer.undressButton:IsShown() and viewer.fallback:IsShown())
assert(viewer.status:GetText():find("no 3D model", 1, true))
M:ShowModel("item", 9001, "Chestpiece")
assert(viewer.undressButton:IsShown() and viewer.model:IsShown() and not viewer.fallback:IsShown())
M:ShowModel("item", 9002, "Ring")
assert(viewer.fallback:IsShown() and viewer.status:GetText():find("not visible", 1, true))
pendingTimers = {}
M:ShowModel("item", 7777, "Uncached")
assert(viewer.status:GetText():find("Loading item", 1, true))
drainTimers()
assert(viewer.fallback:IsShown() and viewer.status:GetText():find("no 3D model", 1, true), "an item that never loads must still settle")
GetItemInfoInstant = nil
viewer:Hide()

-- Regression: the window renders while a multi-slice index is still being built.
for id = 5000, 6499 do items[id] = { name = "Filler " .. id }; table.insert(itemIDs, id) end
M.itemFrame:Hide()
M.items, M.itemSearch, M.itemOffset, M.itemSelectedIndex, M.itemResults = nil, nil, nil, nil, nil
pendingTimers = {}
M:Query("global", "npc", "All", "butcher near", "directory")
M.selected, M.offset = 1, 0
M:ShowNPCItems()
assert(M.items and not M.items.ready, "large item lists must index across several frames")
assert(f.status:GetText():find("Indexing items", 1, true))
for _ = 1, 10 do
    local timers = pendingTimers
    pendingTimers = {}
    for _, callback in ipairs(timers) do callback() end
end
assert(M.items.ready and #M.items.list == 1504)
assert(M.itemNPC.id == 20 and M.itemResults[1] == 2672 and M.itemDetails.id == 2672,
    "the NPC item list must appear once indexing finishes")
M:ShowItemLookup("filler 6499")
assert(M.itemResults[1] == 6499)

local errors = {}
M.Error = function(_, message) table.insert(errors, message) end
M.itemFrame:Hide()
provider.Item = nil
assert(not M:ItemProvider())
M:ShowItemLookup("x")
assert(errors[1] and errors[1]:find("no item data", 1, true), "missing item data must be reported")

M.native, M.dbIndex, M.dbCache = saved.native, saved.index, saved.cache
M.items, M.itemSearch, M.mapTransforms = nil, nil, nil
M.data.entries, M.observations, M.clientData = saved.data, saved.observations, saved.clientData
M.Notice, M.Error = saved.notice, saved.err
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = saved.enabled, saved.filter, saved.grouping
playerMap, playerX, playerY = saved.map, saved.x, saved.y
M:BuildIndex()
