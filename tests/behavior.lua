local function record(key, x, npcID)
    return { key = key, name = "Synthetic Innkeeper", npcID = npcID or 123,
        kind = "npc", category = "Services", mapID = 1, x = x or 20, y = 10,
        tags = { "innkeeper" }, source = "synthetic-test-only", permission = "test-fixture",
        edition = "Forever", build = "test", locale = "enUS", verification = "curated", precision = "confirmed" }
end
M:Initialize()
assert(M.ready and M.settings.collecting == false)
M.settings.groupNPCs = false
M:Diagnostic()
local matched = false
for _, message in ipairs(messages) do
    if message:find("Client interface matches Monstrator TOC 16001.", 1, true) then matched = true end
end
assert(matched, "matching interface must no longer be described as provisional")
local originalBuildInfo = GetBuildInfo
GetBuildInfo = function() return "future", "future", "future", 16002 end
M:Diagnostic()
local mismatch = false
for _, message in ipairs(messages) do
    if message:find("Client interface 16002 differs from Monstrator TOC 16001", 1, true) then mismatch = true end
end
assert(mismatch, "future interface mismatches must be reported")
GetBuildInfo = originalBuildInfo
assert(M.index == nil, "global indexes must not be allocated at startup")
M:EnsureIndex()
assert(#M.index.all == 0)
local a, b = record("synthetic:a", 20), record("synthetic:b", 11)
M.data.entries = { a, b }
M:BuildIndex()
assert(#M.index.byNPC[123] == 2, "NPC index must preserve multiple spawns")
local results = M:Query("zone", "npc", "All", "food", "directory")
assert(#results == 2 and results[1].record == b)
assert(math.abs(results[1].distance - 10) < 0.001)
assert(#M:Query("global", "npc", "All", "innk", "directory") == 2)
assert(#M:Query("global", "location", "All", "", "directory") == 0)
local bad = record("bad"); bad.x = 0/0
assert(not M:ValidateRecord(bad))
bad.x, bad.mapID = 0, 999
assert(not M:ValidateRecord(bad))
bad.mapID, bad.tags = 1, { "unrecognized" }
assert(not M:ValidateRecord(bad))
bad.tags = { [1] = "food", [3] = "innkeeper" }
assert(not M:ValidateRecord(bad))
assert(type(M.DistanceTick) == "function", "ticker handler must exist before UI opening")
assert(type(M.DirectoryCounts) == "function", "counts helper must be registered even before any nonempty query")
M:ToggleFavorite(a); M:ToggleFavorite(b)
assert(M.favorites.entries[a.key] and M.favorites.entries[b.key])
M.data.entries = { b }; M:BuildIndex()
results = M:Query("global", "npc", "All", "", "favorites")
assert(#results == 2)
local stale = false
for _, entry in ipairs(results) do if entry.record.key == a.key then stale = entry.stale end end
assert(stale)
local changed = record(b.key, 80)
M.data.entries = { changed }; M:BuildIndex()
results = M:Query("global", "npc", "All", "", "favorites")
for _, entry in ipairs(results) do
    if entry.record.key == b.key then assert(entry.stale and entry.record.x == 11) end
end
M.data.entries = { b }; M:BuildIndex()
M:CaptureNPC("MERCHANT_SHOW")
assert(M:ObservationCount() == 0)
M.settings.collecting = true
M:CaptureNPC("MERCHANT_SHOW")
M:CaptureNPC("MERCHANT_SHOW")
assert(M:ObservationCount() == 1)
local observation
for _, r in pairs(M.observations.entries) do observation = r end
assert(observation.precision == "encounter" and observation.sightings == 2)
M.settings.observationLimit = 1
M:CaptureLandmark("Synthetic landmark")
assert(M:ObservationCount() == 1 and M.fullNotice)
M:Review(observation, "accept", 15, 20, "Vendors")
assert(observation.verification == "user-confirmed")
assert(M.index.byKey[observation.key])
local export = M:ExportText()
local exported = assert(load(export))()
assert(exported[1].key == observation.key)
assert(not M:SetNavigationWaypoint(1, -1, 1, "invalid"))
local showCopy = M.ShowCopy
M.ShowCopy = function(_, text) assert(text:find("Map ID")); M.copied = true end
assert(not M:SetNavigationWaypoint(1, 10, 10, "Synthetic"))
assert(M.copied)
local arrow
TomTom = {
    AddWaypoint = function(_, mapID, x, y, options)
        assert(mapID == 1 and x == 0.1 and y == 0.2 and options.crazy)
        return { id = "test" }
    end,
    IsValidWaypoint = function() return true end,
    SetCrazyArrow = function(_, handle) arrow = handle end,
}
assert(M:SetNavigationWaypoint(1, 10, 20, "Synthetic") and arrow)
TomTom.AddWaypoint = function() error("synthetic API failure") end
local pin
UiMapPoint = { CreateFromCoordinates = function(id, x, y)
    return { uiMapID = id, position = CreateVector2D(x, y) }
end }
C_Map.CanSetUserWaypointOnMap = function() return true end
C_Map.SetUserWaypoint = function(value) pin = value end
C_Map.GetUserWaypoint = function() return pin end
assert(M:SetNavigationWaypoint(1, 10, 20, "Synthetic"))
TomTom = nil
local exceptions, previousHandler = {}, geterrorhandler
geterrorhandler = function() return function(message) exceptions[#exceptions + 1] = message end end
C_Map.GetUserWaypoint = function() return { uiMapID = pin.uiMapID, position = { x = 0.1, y = 0.2 } } end
M.copied = false
assert(M:SetNavigationWaypoint(1, 10, 20, "Plain vector") and not M.copied,
    "native waypoint readback can return plain x/y fields without a GetXY method")
assert(#exceptions == 0, "plain native waypoint vectors must not raise Lua errors")
C_Map.GetUserWaypoint = function() return { uiMapID = 1, position = { x = 0.3, y = 0.2 } } end
assert(not M:SetNavigationWaypoint(1, 10, 20, "Wrong coordinates") and M.copied,
    "mismatched native coordinates must fall back to manual copying")
C_Map.GetUserWaypoint = function() return { uiMapID = 1, position = {} } end
M.copied = false
assert(not M:SetNavigationWaypoint(1, 10, 20, "Missing coordinates") and M.copied)
C_Map.GetUserWaypoint = function() return { uiMapID = 1, position = { x = "bad", y = 0.2 } } end
assert(not M:SetNavigationWaypoint(1, 10, 20, "Invalid coordinates"))
C_Map.GetUserWaypoint = function() return { uiMapID = 2, position = { x = 0.1, y = 0.2 } } end
assert(not M:SetNavigationWaypoint(1, 10, 20, "Wrong map"))
assert(#exceptions == 0, "unsupported native pin shapes must reject explicitly, not call missing methods")
geterrorhandler = previousHandler
C_Map.GetUserWaypoint = function() return pin end
C_Map.CanSetUserWaypointOnMap = function() return false end
assert(not M:SetNavigationWaypoint(1, 10, 20, "Synthetic"))
M.ShowCopy = showCopy
TomTom = nil
M:Toggle()
assert(M.window:IsShown() and M.ticker.interval == 0.5)
local window = M.window
assert(M.kind == "all", "first opening must expose both NPCs and map markers")
assert(window.kindButtons.all.activeMarker:IsShown())
assert(window.kindButtons.all:GetText():find("%(2%)"), "type buttons must show available counts")
assert(window.rows[1].detail:GetText():find("Synthetic Map", 1, true), "rows must identify their zone")
window.detailsButton:Click()
assert(M.detailsFrame:IsShown() and M.detailsFrame.entry.record == M.results[M.selected].record)
assert(M.detailsFrame.body:GetText():find("NPC ID: 123", 1, true))
assert(M.detailsFrame.body:GetText():find("Evidence: Curated", 1, true))
assert(not M.detailsFrame.review:IsShown(), "static data must not be edited as a journal record")
local detailKey = M.detailsFrame.entry.record.key
local wasFavorite = M.favorites.entries[detailKey] ~= nil
M.detailsFrame.favorite:Click()
assert((M.favorites.entries[detailKey] ~= nil) ~= wasFavorite, "detail favorite action must update saved snapshots")
M.detailsFrame.favorite:Click()
assert((M.favorites.entries[detailKey] ~= nil) == wasFavorite)
local navigate = M.SetNavigationWaypoint
local detailNavigation
M.SetNavigationWaypoint = function(_, mapID, x, y, name)
    detailNavigation = { mapID, x, y, name }
end
M.detailsFrame.navigate:Click()
assert(detailNavigation[1] == 1 and detailNavigation[4] == M.detailsFrame.entry.record.name)
M.SetNavigationWaypoint = navigate
M.detailsFrame:GetScript("OnKeyDown")(M.detailsFrame, "ESCAPE")
assert(not M.detailsFrame:IsShown())
local counts = M:DirectoryCounts("zone", "services")
assert(counts.npc == 1 and counts.all == 1, "category counts must honor search, independently of selected category")
assert(#M:Query("global", "all", "All", "synthetic map", "favorites") == 2,
    "favorites must support zone-name search without losing stale snapshots")
M:Refresh()
assert(#window.panels == 3 and window.resultsPanel == window.panels[2])
assert(window.resultsPanel.width > window.panels[1].width and window.resultsPanel.width > window.detailsPanel.width,
    "the result list must be the widest column")
for i, section in ipairs(window.panels) do
    assert(section.x >= 0 and section.x + section.width <= window.width)
    assert(-section.y + section.height <= window.height)
    if i > 1 then
        assert(window.panels[i - 1].x + window.panels[i - 1].width < section.x,
            "columns must have distinct gutters")
    end
end
for _, row in ipairs(window.rows) do
    local list = window.resultsPanel
    assert(row.x >= list.x and row.x + row.width < list.x + list.width)
    assert(row.distance.x + row.distance.width <= row.width and row.name.x + row.name.width <= row.distance.x + 4,
        "names and right-aligned distances must not overlap")
    assert(-row.y + row.height <= -list.y + list.height,
        "all reusable rows must fit inside the result panel")
end
assert(window.scopeButtons.zone.activeMarker:IsShown())
assert(not window.scopeButtons.global.activeMarker:IsShown())
window.scopeButtons.global:Click()
assert(window.scopeButtons.global.activeMarker:IsShown() and not window.scopeButtons.zone.activeMarker:IsShown())
window.scopeButtons.zone:Click()
window.search:SetText("")
window.search:GetScript("OnEditFocusLost")()
assert(window.searchHint:IsShown())
window.search:GetScript("OnEditFocusGained")()
assert(not window.searchHint:IsShown())
for _, callback in ipairs(pendingTimers) do callback() end
clock = clock + 0.5
M.ticker.callback()
local textCalls, fontCalls, colorCalls = uiCalls.text, uiCalls.font, uiCalls.color
for i = 1, 120 do
    clock = clock + 0.5
    M.ticker.callback()
end
assert(uiCalls.text == textCalls and uiCalls.font == fontCalls and uiCalls.color == colorCalls,
    "stationary refreshes must not reassign unchanged text/fonts/colors")
M:Render()
assert(uiCalls.text == textCalls and uiCalls.font == fontCalls and uiCalls.color == colorCalls,
    "explicit unchanged rendering must reuse display state")
playerX = playerX + 0.001
clock = clock + 0.5
M.ticker.callback()
assert(uiCalls.text > textCalls, "movement must still refresh distance text")
local selectedKey = M.results[M.selected].record.key
playerX = 0.15
clock = clock + 0.5
M.ticker.callback()
assert(M.results[M.selected].record.key == selectedKey, "movement sorting must preserve selected identity")
playerX = 0.1
local distanceTime = M.lastDistanceUpdate
clock = clock + 0.1
M.ticker.callback()
assert(M.lastDistanceUpdate == distanceTime, "math must not run again within 0.5 seconds")
M.window.search:SetText("first")
M.window.search:SetText("innk")
for _, callback in ipairs(pendingTimers) do callback() end
assert(not M.searchPending and #M.results == 1)
M.window:GetScript("OnKeyDown")(M.window, "A")
assert(M.window.propagates, "gameplay keys must not be swallowed")
M.window:GetScript("OnKeyDown")(M.window, "TAB")
assert(not M.window.propagates)
M.results = {}
for i, distance in ipairs({ 39, 40, 100, 101 }) do
    M.results[i] = { record = record("synthetic:color:" .. i), distance = distance }
end
M.offset = 0
M:Render()
assert(M.window.rows[1].distance.color[2] == 1)
assert(M.window.rows[2].distance.color[2] == 0.85)
assert(M.window.rows[3].distance.color[2] == 0.85)
assert(M.window.rows[4].distance.color[2] == 0.85 and M.window.rows[4].distance.color[1] == 0.85,
    "faraway results use neutral distance text rather than a danger color")
M.settings.highContrast = true
M:Render()
assert(M.window.rows[1].distance.color[3] == 0.6 and M.window.rows[4].distance:GetText():find("101 yd"))
M.settings.textScale = 1.5
M:Render()
assert(window.rows[1].name.fontSize == 21 and window.rows[1].detail.fontSize == 19.5)
assert(-window.rows[1].name.y + window.rows[1].name.fontSize <= -window.rows[1].detail.y,
    "maximum supported text scale must keep name and secondary lines separate")
assert(23 + window.rows[1].detail.fontSize <= window.rows[1].height,
    "maximum supported text scale must fit the row's second line")
M.settings.textScale = 1
M:Render()
M.window:Hide()
assert(tickers[#tickers].cancelled)
M:Toggle("review")
assert(M.window:IsShown() and M.view == "review")
assert(window.empty:GetText():find("No pending observations", 1, true))
assert(window.viewButtons.review.activeMarker:IsShown())
local withoutTicker = C_Timer.NewTicker
C_Timer.NewTicker = nil
local transforms = worldPositionCalls
local previousDistanceTime = M.lastDistanceUpdate
clock = clock + 1
M:DistanceTick()
assert(worldPositionCalls == transforms and M.lastDistanceUpdate == previousDistanceTime,
    "an empty view must not perform world-distance math")
M.results = { { record = b } }
M:StartRefresh()
local update = M.window:GetScript("OnUpdate")
local tickTime = M.lastDistanceUpdate
update(M.window, 0.4)
assert(M.lastDistanceUpdate == tickTime)
clock = clock + 1
update(M.window, 0.1)
assert(M.lastDistanceUpdate > tickTime)
M.window:Hide()
assert(M.window:GetScript("OnUpdate") == nil)
C_Timer.NewTicker = withoutTicker
M:Toggle("review")
M:ShowSettings()
M:ShowReview(observation)
local reviewEvidence = M.reviewFrame.evidence:GetText()
local seenAt = tostring(observation.lastSeen)
if type(date) == "function" then
    local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", observation.lastSeen)
    if ok then seenAt = formatted end
end
assert(reviewEvidence:find(M.L["NPC ID: "] .. observation.npcID, 1, true))
assert(reviewEvidence:find(M.L["Seen: %s | Sightings: %d"]:format(seenAt, 2), 1, true))
assert(reviewEvidence:find(M.L["Submission seal: %s"]:format(M.L["seal:intact"]), 1, true))
assert(reviewEvidence:find(M.L["Source: "] .. M.L["Vendors"], 1, true))
local intactSeal = observation.seal
observation.seal = "invalid"
M:ShowReview(observation)
assert(M.reviewFrame.evidence:GetText():find(M.L["seal:mismatch"], 1, true), "tampered records must be marked")
observation.seal = intactSeal
M.window:Hide()
assert(M.ticker == nil)
local many = {}
for i = 1, 10000 do
    local r = record("synthetic:stress:" .. i, (i % 10000) / 100)
    r.name = "Synthetic " .. i
    many[i] = r
end
M.data.entries = many
M:BuildIndex()
clock = clock + 1
results = M:Query("global", "npc", "All", "synthetic", "directory")
assert(#results == 10001, "all stress records plus reviewed observation must remain available")
M.offset = 0
M:Render()
window.pageDown:Click()
assert(M.offset == 9 and window.rows[1].entry == results[10])
assert(window.page:GetText():find("Rows 10-18 of 10001", 1, true))
window.pageUp:Click()
assert(M.offset == 0)
for i = 2, #results do
    assert(results[i - 1].distance <= results[i].distance, "full result set must sort before virtualization")
end
local positionAPI = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = nil
clock = clock + 1
M:UpdateDistances(results)
for _, entry in ipairs(results) do assert(entry.distance == nil) end
C_Map.GetWorldPosFromMapPos = positionAPI
local before = Monstrator_Favorites
M:Initialize()
assert(Monstrator_Favorites == before and M.favorites.entries[a.key])
local preserved = { schema = 999, entries = { sentinel = true } }
Monstrator_Observations = preserved
M.ready = nil
M:Initialize()
assert(not M.ready and Monstrator_Observations == preserved and preserved.entries.sentinel)
print("behavior assertions passed")
