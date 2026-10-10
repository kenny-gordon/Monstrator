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
local questData = { [900] = { name = "Meat Run", starterNpcs = { 23 }, questLevel = 6, requiredLevel = 4 } }
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
provider.Item.startQuest, provider.Item.itemDrops = getter(items, "startQuest"), getter(items, "containers")
provider.Quest = { GetAllIds = function()
    local ids = {}
    for id in pairs(questData) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end }
for _, field in ipairs({ "name", "starterNpcs", "starterObjects", "finisherNpcs", "finisherObjects",
    "questLevel", "requiredLevel" }) do provider.Quest[field] = getter(questData, field) end

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
assert(quests[1].relation == "quest.start", "starter fallback must not be mislabeled as a turn-in")
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

-- Quest/item relations are requested on demand; lists and actor rows stay bounded.
items[2672].startQuest = 0
items[103] = { name = "Mysterious Letter", startQuest = 900 }
items[104] = { name = "Sealed Reward", containers = { 100, 99999 } }
itemIDs[#itemIDs + 1], itemIDs[#itemIDs + 2] = 103, 104
questData[900].starterNpcs = { 23, 24, 23 }
questData[900].finisherNpcs = { 20, 21, 20 }
questData[900].finisherObjects = { 50, 50 }
questData[901] = { name = "Crate Delivery", starterObjects = { 50 }, finisherObjects = { 50, 51 } }
questData[902] = { name = "Unplaced Quest", starterNpcs = { 99999 } }
questData[903] = { name = "No Actors" }
for id = 910, 921 do questData[id] = { name = "Extra Quest " .. id, starterNpcs = { 20 } } end
npcs[21].friendly = "H"
M.items, M.itemSearch = nil, nil
M:StartItemIndex()
assert(M:ItemDetails(2672).startQuest == nil, "startQuest=0 means no quest")
local cachedResults, cachedTotal = M:SearchItems("haunch")
local repeatedResults, repeatedTotal = M:SearchItems("haunch")
assert(cachedResults == repeatedResults and cachedTotal == repeatedTotal and repeatedTotal == 3,
    "cached searches must return both results and the total")
assert(M:SearchItems("2672", 20)[1] == 2672 and #M:SearchItems("2589", 20) == 0,
    "numeric searches must work inside NPC filters without leaking unrelated items")
assert(#M:SearchItems("", 23) == 2, "NPC item lookup includes quest reward and quest-start items")
local turnIns = M:ResolveItemSources(M:ItemDetails(2672), "quest")
assert(#turnIns == 3, "all distinct turn-in NPCs and objects must be included")
local actorIDs = {}
for _, actor in ipairs(turnIns) do
    actorIDs[actor.kind .. ":" .. actor.id] = true
    assert(actor.relation == "quest.finish", "rewards navigate to turn-in providers when listed")
end
assert(actorIDs["npc:20"] and actorIDs["npc:21"] and actorIDs["object:50"])
local roles = M:QuestSources(900)
assert(#roles == 5 and roles[1].relation == "quest.start" and roles[5].relation == "quest.finish",
    "quest details retain all starter and finisher roles, deduplicated within a role")
local unknownSources = M:ResolveItemSources({ quest = { 99999 } }, "quest")
assert(#unknownSources == 1 and unknownSources[1].missing and unknownSources[1].questID == 99999,
    "unresolved reward quests must remain visible instead of disappearing")
local related = M:NPCQuestIDs(20)
assert(#related == 13 and related[1] == 900, "NPC lookup includes starter and finisher quests once")
assert(#M:NPCQuestIDs(99998) == 0)
M:ShowEntryDetails(M.results[1])
assert(M.detailsFrame.quests:IsShown() and M.detailsFrame.quests:IsEnabled())
assert(M.detailsFrame.scroll.y == -112 and M.detailsFrame.scroll.height == 174,
    "the quest action must not overlap the NPC title or scroll area")
M.detailsFrame.quests:Click()
local q = M.questFrame
assert(q and q:IsShown() and q.template == "PortraitFrameTemplate" and #q.results == 13)
assert(q.rows[8]:IsShown() and #q.rows == 8 and #q.sourceRows == 8, "quest lists must have bounded visible rows")
assert(q.selected == q.rows[1].quest and q.rows[1].activeMarker:IsShown())
assert(q.heading.width == 454 and q.sourceRows[1].name.width == 450,
    "quest and actor names must be bounded by their panels")
assert(q.levels.maxLines == 1 and math.abs(q.sourceRows[1].where.y) >= 12 * 1.5
    and math.abs(q.sourceRows[1].where.y) + 10 * 1.5 <= q.sourceRows[1].height,
    "quest source lines must not overlap even at maximum text scale")
q.next:Click()
assert(q.offset == 5 and q.previous:IsEnabled() and not q.next:IsEnabled())
q.previous:Click()
assert(q.offset == 0)
q.search:SetText("MEAT 900")
assert(#q.results == 1 and q.selected.id == 900, "quest searches require all case-insensitive tokens")
assert(q.levels:GetText():find("Required level: 4", 1, true))
q.items:Click()
assert(M.itemQuest.id == 900 and M.itemNPC == nil and #M.itemResults == 2)
assert(f.status:GetText():find("#900", 1, true) and f.clearNPC:IsShown())
assert(M:SearchItems("103")[1] == 103 and #M:SearchItems("2589") == 0,
    "quest item filtering includes start items and prevents exact-ID leakage")
f.clearNPC:Click()
assert(M.itemQuest == nil and #M:SearchItems("2589") == 1)
M:ShowItemLookup("103")
assert(f.questsButton:IsEnabled() and f.detailInfo:GetText():find("Starts quest", 1, true))
f.questsButton:Click()
assert(#q.results == 1 and q.selected.id == 900 and M.questFrame == q, "item links reuse the quest window")
M:ShowItemLookup("104")
assert(M.itemTab == "containers" and not f.questsButton:IsEnabled())
assert(#M:CurrentItemSources() == 2 and f.sourceRows[1].source.kind == "item")
local containerRow
for _, row in ipairs(f.sourceRows) do if row.source and row.source.id == 100 then containerRow = row end end
assert(containerRow)
containerRow:Click()
assert(M.itemDetails.id == 100 and M.itemQuest == nil, "container links open the parent item's lookup")
M:ShowQuestRelations({ 901, 901, 99999 }, "Fixture")
assert(#q.results == 2, "quest IDs must be deduplicated")
q.search:SetText("99999")
assert(q.selected.missing and q.levels:GetText() == M.L["quest.missing"])
q.search:SetText("901")
assert(#q.sources == 3, "object starters and turn-ins are both shown, preserving roles")
local missingActor
for _, row in ipairs(q.sourceRows) do if row.source and row.source.id == 51 then missingActor = row end end
assert(missingActor and missingActor.where:GetText() == M.L["quest.missing"])
local relationNotices = {}
M.Notice = function(_, message) relationNotices[#relationNotices + 1] = message end
missingActor:Click()
assert(relationNotices[1]:find("no coordinates", 1, true), "unknown locations must explicitly refuse navigation")
M.Notice = saved.notice
local questWaypoints = {}
TomTom = { AddWaypoint = function(_, mapID, x, y) questWaypoints[#questWaypoints + 1] = { mapID, x, y }; return {} end,
    IsValidWaypoint = function() return true end, SetCrazyArrow = function() end }
q.sourceRows[1]:Click()
assert(questWaypoints[1][1] == 1 and questWaypoints[1][2] == 0.5, "quest actors use existing safe waypoint navigation")
TomTom = nil
questData[904] = { name = "Many Actors", starterNpcs = { 20, 21, 22, 23, 24 },
    finisherNpcs = { 20, 21, 22, 23, 24 }, starterObjects = { 50 }, finisherObjects = { 50 } }
M:ShowQuestRelations({ 904 }, "Paging")
assert(#q.sources == 12 and q.sourceRows[8]:IsShown() and q.sourceNext:IsEnabled())
q.sourceNext:Click()
assert(q.sourceOffset == 4 and q.sourcePrevious:IsEnabled() and not q.sourceNext:IsEnabled())
q.sourcePrevious:Click()
assert(q.sourceOffset == 0)
q.search:SetText("no such quest")
assert(#q.results == 0 and q.selected == nil and q.sourceEmpty:IsShown() and not q.items:IsEnabled())
M:ShowQuestRelations({}, "Empty")
assert(q.empty:IsShown() and not q.items:IsEnabled() and not q.rows[1]:IsShown())
q.search:SetFocus()
q:GetScript("OnKeyDown")(q, "ESCAPE")
assert(not q:IsShown() and not q.search:HasFocus(), "Escape closes quest lookup and releases search focus")
M.detailsFrame:Hide()
local priorIndex = M.items
local replacement = {}
for key, value in pairs(provider) do replacement[key] = value end
M.native.provider = replacement
M:StartItemIndex()
assert(M.items ~= priorIndex and M.items.lib == replacement, "item indexes must invalidate when providers change")
M.native.provider = provider
M:StartItemIndex()

-- Back restores both sides of the lookup chain, including filters and source tabs.
M.itemFrame:Hide()
M.lookupHistory, M.lookupView = {}, nil
M:ShowItemLookup("haunch")
M.itemSelectedIndex = 2
M:RefreshItemWindow()
M.itemTab = "quest"
M:RenderItemWindow()
assert(f.detailPanel.heading:GetText() == "1 quests / 3 sources",
    "quest counts must distinguish related quests from their source rows")
f.questsButton:Click()
assert(q:IsShown() and not f:IsShown() and q.back:IsEnabled())
q.search:SetText("MEAT 900")
q.items:Click()
assert(f:IsShown() and not q:IsShown() and M.itemQuest.id == 900 and f.back:IsEnabled())
f.back:Click()
assert(q:IsShown() and not f:IsShown() and q.search:GetText() == "MEAT 900" and q.selected.id == 900)
q.back:Click()
assert(f:IsShown() and not q:IsShown() and f.search:GetText() == "haunch"
    and M.itemDetails.id == 2672 and M.itemSelectedIndex == 2 and M.itemTab == "quest",
    "Back must restore the selected item and source tab, not just the search")
for _ = 1, 4 do
    local timers = pendingTimers; pendingTimers = {}
    for _, callback in ipairs(timers) do callback() end
end
assert(M.itemSelectedIndex == 2 and M.itemDetails.id == 2672,
    "queued search callbacks must not overwrite the restored selection")
assert(#M.lookupHistory == 0 and not f.back:IsEnabled())
M:ShowItemLookup("", 20, "Butcher Near")
f.clearNPC:Click()
assert(M.itemNPC == nil and f.back:IsEnabled())
f.back:Click()
assert(M.itemNPC.id == 20 and f.clearNPC:IsShown() and #M.itemResults == 2,
    "Back must restore a cleared NPC filter")
local filterTooltip, tooltipAddLine = {}, GameTooltip.AddLine
GameTooltip.AddLine = function(_, text) filterTooltip[#filterTooltip + 1] = text end
f.statusHelp:GetScript("OnEnter")()
GameTooltip.AddLine = tooltipAddLine
assert(filterTooltip[1] == M.L["lookup.filterHint"], "filtered lists must explain how to clear or restore them")
M:ShowItemLookup("104")
local nestedContainer
for _, row in ipairs(f.sourceRows) do if row.source and row.source.id == 100 then nestedContainer = row end end
assert(nestedContainer)
nestedContainer:Click()
assert(M.itemDetails.id == 100)
f.back:Click()
assert(M.itemDetails.id == 104 and M.itemTab == "containers", "Back restores container-item lookup")
M:ShowQuestRelations({ 904 }, "History paging")
q.sourceNext:Click()
q.items:Click()
f.back:Click()
assert(q.sourceOffset == 4 and q.selected.id == 904, "Back restores quest source paging")
for _ = 1, 25 do M:ShowItemLookup("103") end
assert(#M.lookupHistory == 20, "lookup history must be bounded and session-only")
local changedHistoryNotices, originalNotice = {}, M.Notice
M.Notice = function(_, text) changedHistoryNotices[#changedHistoryNotices + 1] = text end
M.native.provider = replacement
f.back:Click()
assert(#M.lookupHistory == 0 and changedHistoryNotices[1] == M.L["lookup.historyChanged"]
    and not f.back:IsEnabled(), "database changes must explicitly invalidate incompatible lookup history")
M.Notice, M.native.provider = originalNotice, provider
items[2672].rewards = { 900, 900 }
assert(#M:ItemDetails(2672).quest == 1, "duplicate relation IDs must not inflate counts")
items[2672].rewards = { 900 }
f:Hide()
M.lookupView, M.lookupHistory = nil, {}

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
assert(M.items.ready and #M.items.list == 1506)
assert(M.itemNPC.id == 20 and M.itemResults[1] == 2672 and M.itemDetails.id == 2672,
    "the NPC item list must appear once indexing finishes")
M:ShowItemLookup("filler 6499")
assert(M.itemResults[1] == 6499)
M:ShowItemLookup("filler")
assert(#M.itemResults == 500 and M.itemTotal == 1500 and f.limit:IsShown(),
    "broad lookups must retain the exact match total while bounding displayed results")
assert(f.limit:GetText() == M.L["lookup.limit"]:format(500, 1500))
M.itemSelectedIndex, M.itemOffset = 21, 12
M:RefreshItemWindow()
local selectedFiller = M.itemDetails.id
M:ShowItemLookup("103")
M.items = nil
f.back:Click()
assert(M.lookupRestoreItem and not M.items.ready, "Back must wait for incremental item indexing when necessary")
for _ = 1, 10 do
    local timers = pendingTimers; pendingTimers = {}
    for _, callback in ipairs(timers) do callback() end
end
assert(M.itemDetails.id == selectedFiller and M.itemOffset == 12 and M.itemSelectedIndex == 21,
    "Back restores paged item results even after incremental reindexing")
M:ShowItemLookup("filler 6499")
assert(not f.limit:IsShown(), "refining the search removes the result-limit notice")

local errors = {}
M.Error = function(_, message) table.insert(errors, message) end
M.itemFrame:Hide()
provider.Item = nil
assert(not M:ItemProvider())
M:ShowItemLookup("x")
assert(errors[1] and errors[1]:find("no item data", 1, true), "missing item data must be reported")

M.native, M.dbIndex, M.dbCache = saved.native, saved.index, saved.cache
M.items, M.itemSearch, M.mapTransforms = nil, nil, nil
M.itemQuest = nil
M.lookupHistory, M.lookupView, M.lookupRestoreItem = {}, nil, nil
M.data.entries, M.observations, M.clientData = saved.data, saved.observations, saved.clientData
M.Notice, M.Error = saved.notice, saved.err
M.settings.referenceEnabled, M.settings.evidenceFilter, M.settings.groupNPCs = saved.enabled, saved.filter, saved.grouping
playerMap, playerX, playerY = saved.map, saved.x, saved.y
M:BuildIndex()
