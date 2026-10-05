M.data.entries = {}
Monstrator_Observations = { schema = 1, entries = {}, nextID = 1 }
Monstrator_Favorites = { schema = 1, entries = {} }
M:Initialize()
local taxiCalls, poiCalls = 0, 0
C_TaxiMap = {
    GetTaxiNodesForMap = function(mapID)
        taxiCalls = taxiCalls + 1
        return {
            { nodeID = 10, name = "Synthetic Horde flight", faction = 1, position = CreateVector2D(0.2, 0.3) },
            { nodeID = 11, name = "Synthetic Alliance flight", faction = 2, position = CreateVector2D(0.4, 0.5) },
            { nodeID = 12, name = "Synthetic invalid flight", faction = 0, position = CreateVector2D(2, 0.5) },
            { nodeID = 13, name = "Synthetic negative flight", faction = 0, position = CreateVector2D(-0.1, 0.5) },
            { nodeID = 14, name = "Synthetic off-map Y flight", faction = 0, position = CreateVector2D(0.5, 1.1) },
        }
    end,
}
C_AreaPoiInfo = {
    GetAreaPOIForMap = function() poiCalls = poiCalls + 1; return { 20, 21, 22, 23 } end,
    IsAreaPOITimed = function(id) return id == 21 end,
    GetAreaPOIInfo = function(_, id)
        return { name = "Synthetic POI " .. id, position = CreateVector2D(0.5, id == 23 and -0.2 or 0.6), isCurrentEvent = id == 22 }
    end,
}
clock = clock + 31
local initialMessages = #messages
assert(M:RefreshClientMap(1, true))
assert(#M.clientData.maps[1].entries == 3, "retain two faction flights plus the non-event, non-timed POI")
assert(M.clientData.maps[1].offMap == 4, "off-map flights and POIs must be counted before record validation")
assert(#messages == initialMessages, "skipped off-map markers stay out of chat; diagnostic reports them")
M:BuildIndex()
local results = M:Query("zone", "location", "All", "", "directory")
assert(#results == 2, "the opposite faction's flight node must be filtered")
for _, entry in ipairs(results) do
    assert(entry.record.verification == "client-map" and entry.record.precision == "map")
    assert(entry.record.npcID == nil, "map points must not fabricate NPC identities")
end
assert(#M:Query("zone", "all", "All", "synthetic map flight", "directory") == 1,
    "AND search must combine zone names and service tags across record kinds")
local counts = M:DirectoryCounts("zone", "synthetic map")
assert(counts.all == 2 and counts.npc == 0 and counts.location == 2)
assert(counts.categories.location.Transit == 1 and counts.categories.location.Landmarks == 1,
    "visible counts must exclude opposite-faction records and include all categories")
M.scope, M.kind, M.category = "zone", "location", "All"
M.window.search:SetText("")
M.searchPending = nil
M:UpdateCategories()
assert(M.window.kindButtons.location:GetText():find("%(2%)"))
assert(M.window.categoryButtons[4]:GetText():find("Transit %(1%)"))
M:ShowEntryDetails(M.results[1])
assert(M.detailsFrame.body:GetText():find("Map location: no NPC identity is inferred.", 1, true))
assert(M.detailsFrame.body:GetText():find("Map marker only", 1, true))
M.detailsFrame:Hide()
local calls = taxiCalls
assert(not M:RefreshClientMap(1) and taxiCalls == calls, "map provider must be throttled")
clock = clock + 31
local refreshMessages = #messages
assert(not M:RefreshClientMap(1), "unchanged map content must not require an index rebuild")
assert(taxiCalls == calls + 1)
assert(#messages == refreshMessages, "off-map notices must not spam on repeated refresh")
local taxiProvider, poiProvider = C_TaxiMap.GetTaxiNodesForMap, C_AreaPoiInfo.GetAreaPOIForMap
C_TaxiMap.GetTaxiNodesForMap = function()
    return {
        { nodeID = 30, name = "Synthetic origin", position = CreateVector2D(0, 0) },
        { nodeID = 31, name = "Synthetic far boundary", position = CreateVector2D(1, 1) },
    }
end
C_AreaPoiInfo.GetAreaPOIForMap = function() return {} end
assert(M:RefreshClientMap(2, true))
assert(#M.clientData.maps[2].entries == 2 and M.clientData.maps[2].offMap == 0)
assert(M.clientData.maps[2].entries[1].x == 0 and M.clientData.maps[2].entries[2].y == 100,
    "normalized map boundaries must convert exactly once")
M.clientData.maps[2] = nil
C_TaxiMap.GetTaxiNodesForMap, C_AreaPoiInfo.GetAreaPOIForMap = taxiProvider, poiProvider
local flight = M.clientData.maps[1].entries[2]
M:ToggleFavorite(flight)
C_TaxiMap.GetTaxiNodesForMap = function() return {} end
clock = clock + 31
assert(M:RefreshClientMap(1))
M:BuildIndex()
results = M:Query("global", "location", "All", "", "favorites")
assert(#results == 1 and results[1].stale, "removed native points preserve stale favorite snapshots")
C_TaxiMap.GetTaxiNodesForMap = function() error("synthetic provider failure") end
clock = clock + 31
M:RefreshClientMap(1)
assert(M.clientData.errors.taxi:find("synthetic provider failure", 1, true))
local errorMessages = #messages
clock = clock + 31
M:RefreshClientMap(1)
assert(#messages == errorMessages, "failed provider must not repeat errors every refresh")
C_TaxiMap.GetTaxiNodesForMap = function() return {} end
M:SyncClientData()
assert(M.clientData.errors.taxi == nil)

M.settings.collecting = false
M:CaptureNPC("manual-target")
assert(M:ObservationCount() == 1, "explicit NPC capture is separate from automatic opt-in")
local record
for _, value in pairs(M.observations.entries) do record = value end
assert(record.verification == "pending" and record.precision == "encounter")
local counter = M.observations.nextID
assert(not M:Review(record, "accept", 12, 20, "Services", "unknown"))
assert(record.verification == "pending" and record.x == 10, "bad tags must not partially mutate observations")
assert(M:Review(record, "accept", 12, 20, "Services", "innkeeper, food, FOOD"))
assert(#record.tags == 2)
results = M:Query("zone", "npc", "All", "food", "directory")
assert(#results == 1 and results[1].record == record)
assert(M:Review(record, "accept", 13, 21, "Services", "repair"))
assert(M.index.byKey[record.key].record.x == 13, "confirmed edits must replace old cached world/index entries")
assert(#M:Query("zone", "npc", "All", "food", "directory") == 0)
assert(#M:Query("zone", "npc", "All", "repair", "directory") == 1)
assert(#M:Query("zone", "all", "All", "", "directory") == 2,
    "combined view must include both confirmed NPCs and native locations")
M:ShowEntryDetails(M.index.byKey[record.key])
assert(M.detailsFrame.review:IsShown(), "only owned journal records should expose editing")
M.detailsFrame.review:Click()
assert(M.reviewFrame:IsShown() and M.reviewFrame.record == record and not M.detailsFrame:IsShown())
M.reviewFrame:Hide()
assert(#M:Query("global", "npc", "All", "", "review") == 0)
assert(#M:Query("global", "npc", "All", "", "journal") == 1)
local identity = UnitGUID
UnitGUID = function() return "Player-1-123" end
M:CaptureNPC("manual-target")
assert(M.observations.nextID == counter, "player targets must not produce records")
UnitGUID = identity
assert(M:Review(record, "reject"))
assert(M:ObservationCount() == 0 and M.index.byKey[record.key] == nil)

local catalog, buildInfo, mapInfo = M.clientMapCatalog, GetBuildInfo, C_Map.GetMapInfo
assert(#catalog.maps == 50 and catalog.build == "1.60.1.70205")
assert(not M:StartClientWorldSync(), "an extracted catalog must not run on an unmatched build")
M.clientMapCatalog = { build = "1.60.1.70205", maps = { 1, 2, 3 } }
GetBuildInfo = function() return "1.60.1", "70205", "test-date", 16001 end
M.clientData.maps, M.clientData.errors = {}, {}
M.clientData.worldScanned = nil
C_TaxiMap.GetTaxiNodesForMap = function(mapID)
    taxiCalls = taxiCalls + 1
    return { { nodeID = 99, name = "Synthetic world flight " .. mapID,
        faction = 0, position = CreateVector2D(0.2, 0.3) } }
end
C_AreaPoiInfo.GetAreaPOIForMap = function() return {} end
assert(M:StartClientWorldSync())
assert(not M:StartClientWorldSync(), "duplicate scans must not restart the queue")
local before = taxiCalls
clock = clock + 1
assert(M:StepClientWorldSync())
M:Render()
assert(M.window.coverage:GetText():find("Scanning zones: 1/3", 1, true),
    "coverage must show progress even when queried maps return no new results")
assert(taxiCalls == before + 1 and M.clientData.worldQueue.next == 2)
assert(not M:StepClientWorldSync() and taxiCalls == before + 1, "one map per half-second maximum")
clock = clock + 0.5
assert(M:StepClientWorldSync())
M:BuildIndex()
assert(#M:Query("global", "location", "All", "", "directory") == 2,
    "global results must include non-player maps returned by supported APIs")
clock = clock + 0.5
assert(not M:StepClientWorldSync(), "unknown maps must not produce fabricated placements")
assert(not M.clientData.worldQueue and M.clientData.worldScanned)
M:Render()
assert(M.window.coverage:GetText():find("World scan finished", 1, true))
assert(not M:StartClientWorldSync(), "completed automatic scans must not run again on every selection")
assert(M:StartClientWorldSync(true), "explicit retry must allow a new scan")
M.window:Hide()
before = taxiCalls
clock = clock + 1
M:DistanceTick()
assert(taxiCalls == before and M.clientData.worldQueue.next == 1, "hidden UI must pause queued scanning")
M.clientData.worldQueue = nil
C_TaxiMap, C_AreaPoiInfo = nil, nil
local extractedData = M.extractedObjects
M.extractedObjects = nil
assert(not M:StartClientWorldSync(true), "missing providers must be reported, not queued as success")
M.extractedObjects = extractedData
C_TaxiMap = { GetTaxiNodesForMap = function() return {} end }
SlashCmdList.MONSTRATOR("sync world")
assert(M.clientData.worldQueue and M.window:IsShown())
assert(M.scope == "global" and M.kind == "location" and M.view == "directory",
    "explicit world sync must expose static global results and start visible refresh")
assert(M.ticker and not M.ticker.cancelled)
M.window:Hide()
M.clientData.worldQueue = nil
M.clientMapCatalog, GetBuildInfo, C_Map.GetMapInfo = catalog, buildInfo, mapInfo
