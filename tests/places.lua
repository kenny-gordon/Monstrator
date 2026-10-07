local saved = { info = C_Map.GetMapInfo, entries = M.data.entries, observations = M.observations,
    clientData = M.clientData, reference = M.settings.referenceEnabled, sort = M.settings.sortOrder,
    scope = M.scope, kind = M.kind, category = M.category, map = playerMap, index = M.dbIndex }
local maps = {
    [10] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [20] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1] = { name = "Mulgore", mapType = 3, parentMapID = 10 },
    [2] = { name = "Durotar", mapType = 3, parentMapID = 10 },
    [3] = { name = "Elwynn Forest", mapType = 3, parentMapID = 20 },
    [4] = { name = "Deeprun Tram", mapType = 4, parentMapID = 0 },
}
C_Map.GetMapInfo = function(id) return maps[id] end
M.regionCache, M.zoneCatalogCache = nil, nil
M.observations = { entries = {}, nextID = 1 }
M.clientData = { maps = {}, errors = {}, generation = 0 }
M.dbIndex = nil
M.settings.referenceEnabled = false
local function npc(id, name, mapID, x, level)
    return { key = "curated:place-" .. id, kind = "npc", name = name, npcID = id, mapID = mapID, x = x, y = 50,
        category = "Services", tags = { "innkeeper" }, level = level, source = "test", build = "test",
        locale = "enUS", verification = "curated", precision = "confirmed", permission = "test", edition = "Forever" }
end
M.data.entries = {
    npc(101, "Bluff Keeper", 1, 10, 30), npc(102, "Second Bluff", 1, 60, 5),
    npc(103, "Razor Keeper", 2, 20, 10), npc(104, "Goldshire Keeper", 3, 30, 20),
    npc(105, "Tram Keeper", 4, 40, 1),
}
M:BuildIndex()
playerMap = 1

assert(select(2, M:MapRegion(1)) == "Kalimdor" and M:MapRegion(3) == 20)
assert(M:MapRegion(4) == 0, "maps without a continent fall into Other regions")

local function names(results)
    local list = {}
    for _, entry in ipairs(results) do table.insert(list, entry.record.name) end
    return table.concat(list, ",")
end
assert(#M:Query("zone", "npc", "All", "", "directory") == 2, "follow mode uses the player's zone")
M.zoneMap = 3
local results = M:Query("zone", "npc", "All", "", "directory")
assert(#results == 1 and results[1].record.name == "Goldshire Keeper", "a pinned zone overrides the player's zone")
assert(M:DirectoryCounts("zone", "").npc == 1)
M.zoneMap = nil
assert(#M:Query("region", "npc", "All", "", "directory") == 3, "region scope defaults to the player's continent")
M.regionMap = 20
assert(#M:Query("region", "npc", "All", "", "directory") == 1)
assert(M:DirectoryCounts("region", "").npc == 1)
M.regionMap = nil
assert(#M:Query("global", "npc", "All", "", "directory") == 5)

M.settings.sortOrder = "zone"
results = M:Query("global", "npc", "All", "", "directory")
M:SortResults(results)
assert(names(results) == "Goldshire Keeper,Razor Keeper,Bluff Keeper,Second Bluff,Tram Keeper",
    "zone sort orders by region, then zone, then distance; Other regions last: " .. names(results))
M.settings.sortOrder = "level"
M:SortResults(results)
assert(names(results):match("^Tram Keeper,Second Bluff,Razor Keeper"), "level sort is ascending")

M.kind, M.category = "npc", "All"
local catalog = M:ZoneCatalog()
assert(#catalog == 3 and catalog[1].name == "Eastern Kingdoms" and catalog[2].name == "Kalimdor"
    and catalog[3].id == 0, "regions sort by name with Other last")
assert(#catalog[2].zones == 2 and catalog[2].zones[1].name == "Durotar" and catalog[2].zones[2].count == 2)

M.scope, M.view = "zone", "directory"
M.window:Show()
M:Refresh()
assert(M.window.areaTrail == nil and M.RenderAreaTrail == nil,
    "directory must not construct or render the removed map breadcrumb strip")
assert(M.window.subtitle:GetText() == M.L["WoW Forever NPC & location directory - by Metalbullz"],
    "the header is a simple native-style subtitle rather than a second navigation surface")
local picker = M.window.picker
assert(not picker:IsShown())
M.window.placeButton:Click()
assert(picker:IsShown() and picker.data[1].active, "the picker opens with follow mode active")
assert(#picker.data == 2 + 3 + 4)
picker.filter:SetText("dur")
assert(#picker.data == 4 and picker.data[4].text:find("Durotar", 1, true))
picker.filter:GetScript("OnEnterPressed")()
assert(not picker:IsShown() and M.scope == "zone" and M.zoneMap == 2)
assert(M.window.placeButton:GetText():find("Durotar", 1, true) and M.window.filters:GetText():find("Durotar", 1, true))
assert(#M.results == 1 and M.results[1].record.name == "Razor Keeper")
M.window.scopeButtons.region:Click()
assert(M.scope == "region" and #M.results == 3 and M.window.placeButton:GetText():find("Kalimdor", 1, true))
M.window.placeButton:Click()
for _, row in ipairs(picker.rows) do
    if row.data and row.data.scope == "region" and row.data.id == 20 then row:Click() end
end
assert(M.regionMap == 20 and #M.results == 1)
assert(M.window.placeButton:GetText():find("Eastern Kingdoms", 1, true),
    "sidebar identifies the browsed region rather than the player's zone")
M.window.placeButton:Click()
picker.filter:SetText("kalim")
picker.filter:GetScript("OnEnterPressed")()
assert(M.scope == "region" and M.regionMap == 10, "Enter picks a region when no zone name matches")
M.window.placeButton:Click()
picker.filter:SetText("zzz")
assert(picker.status:GetText():find("No zone or region", 1, true))
picker:Hide()
M.window.scopeButtons.zone:Click()
assert(M.zoneMap == 2, "Zone returns to the pinned zone")
SlashCmdList.MONSTRATOR("zone elwynn")
assert(M.scope == "zone" and M.zoneMap == 3)
SlashCmdList.MONSTRATOR("region kalim")
assert(M.scope == "region" and M.regionMap == 10)
SlashCmdList.MONSTRATOR("zone")
assert(M.scope == "zone" and M.zoneMap == nil)
M.window.placeButton:Click()
for _, key in ipairs({ "options", "reviewFrame", "copyFrame", "detailsFrame" }) do if M[key] then M[key]:Hide() end end
M.window:GetScript("OnKeyDown")(M.window, "ESCAPE")
assert(not picker:IsShown() and M.window:IsShown(), "Escape closes the picker before the window " .. tostring(picker:IsShown()) .. tostring(M.window:IsShown()) .. tostring(M.window.propagates))

SlashCmdList.MONSTRATOR("zone elwynn")
assert(M.settings.scope == "zone" and M.settings.zoneMap == 3, "the pinned zone is remembered in settings")
SlashCmdList.MONSTRATOR("region kalim")
assert(M.settings.scope == "region" and M.settings.regionMap == 10)
SlashCmdList.MONSTRATOR("zone")
assert(M.settings.zoneMap == 0)
M.selected = 1
M:Render()
local info = M.window.info
assert(info.location:GetText():find("Mulgore, Kalimdor", 1, true), "location card shows zone and region")
assert(not info.location:GetText():find("/way ", 1, true),
    "the visual location card does not spend a line on a technical navigation command")
assert(info.zone:GetText() == "Browse region", "the player's own zone offers its region")
info.zone:Click()
assert(M.scope == "region" and M.regionMap == 10)
M.selected = 1
M:Render()
assert(info.zone:GetText() == "Browse this zone")
info.zone:Click()
assert(M.scope == "zone" and M.zoneMap == M.results[1].record.mapID, "Browse this zone pins the record's zone")
M.window.rows[1]:GetScript("OnEnter")(M.window.rows[1])
SlashCmdList.MONSTRATOR("reset")
assert(M.scope == "zone" and M.zoneMap == nil and M.settings.windowX == 0 and M.settings.zoneMap == 0)
M:SelectPlace("zone", 3)
M.selected = 1
M:Render()
info.zone:Click()
assert(M.scope == "region" and M.regionMap == 20,
    "Browse region widens the selected zone's continent, not the player's continent")
M.window.scopeButtons.global:Click()
assert(M.scope == "global", "sidebar still provides world browsing after removing header navigation")
M.window:Hide()
M.settings.sortOrder, M.settings.evidenceFilter = "level", "pending"
M.window.search:SetText("old search")
M:Toggle()
assert(M.scope == "zone" and not M.zoneMap and not M.regionMap and M.kind == "all" and M.category == "All")
assert(M.view == "directory" and M.settings.sortOrder == "distance" and M.settings.evidenceFilter == "all"
    and M.window.search:GetText() == "", "normal reopening shows all nearby entries rather than old distant filters")
assert(#M.results == 2 and M.window.placeButton:GetText():find("Mulgore", 1, true))
playerMap = 2
M:Refresh()
assert(#M.results == 1 and M.results[1].record.name == "Razor Keeper"
    and M.window.placeButton:GetText():find("Durotar", 1, true), "local opening follows the player when changing zones")
M.window:Hide()
SlashCmdList.MONSTRATOR("zone elwynn")
assert(M.scope == "zone" and M.zoneMap == 3 and M.window.placeButton:GetText():find("Elwynn Forest", 1, true),
    "an explicit zone command must override the ordinary nearby landing view")
M.window:Hide()
M:Toggle("favorites")
assert(M.view == "favorites", "explicit favorites opening retains its requested view")
playerMap = 1
M:ShowSettings()
local hidden = M.settings.minimapHidden
M.options.minimap:Click()
assert(M.settings.minimapHidden ~= hidden and M.options.minimap:GetText():find("Minimap button", 1, true))
M.options.minimap:Click()
M.options:GetScript("OnKeyDown")(M.options, "ESCAPE")
assert(not M.options:IsShown(), "Escape closes Settings")
M:ShowCopy("Synthetic inventory\n123 | Sample NPC")
assert(M.copyFrame.template == "PortraitFrameTemplate" and M.copyFrame.box.width == 680)
assert(M.copyFrame.box:GetText() == "Synthetic inventory\n123 | Sample NPC",
    "native copy dialog preserves the entire export without changing its contents")
assert(M.copyFrame.scroll:GetVerticalScroll() == 0)
if M.copyFrame then
    M.copyFrame:Show()
    M.copyFrame:GetScript("OnKeyDown")(M.copyFrame, "ESCAPE")
    assert(not M.copyFrame:IsShown(), "Escape closes the copy dialog")
end

C_Map.GetMapInfo, M.data.entries, M.observations, M.clientData = saved.info, saved.entries, saved.observations, saved.clientData
M.settings.referenceEnabled, M.settings.sortOrder = saved.reference, saved.sort
M.scope, M.kind, M.category, playerMap = saved.scope, saved.kind, saved.category, saved.map
M.dbIndex, M.zoneMap, M.regionMap = saved.index, nil, nil
M.regionCache, M.zoneCatalogCache = nil, nil
M:BuildIndex()

if not M.launcher then M:CreateLauncher() end
assert(M.launcher and M.launcher.border and M.launcher.icon, "minimap button must be a round bordered launcher")
assert(M:DataSourceSummary():find("^Data: "), "data summary must describe the active source")
