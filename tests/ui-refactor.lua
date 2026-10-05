local saved = {}
for _, key in ipairs({ "settings", "observations", "data", "clientData", "dbIndex",
    "index", "results", "directoryCounts", "scope", "kind", "category", "view", "offset", "selected" }) do
    saved[key] = M[key]
end
local showCopy, navigate, refresh = M.ShowCopy, M.SetNavigationWaypoint, M.RefreshIfVisible
local inventory = M.NPCInventory
local settings = {}
for key, value in pairs(M.settings) do settings[key] = value end
M.settings = settings
M.settings.textScale, M.settings.evidenceFilter = 1, "all"
M.dbIndex = nil
M.clientData = { maps = {}, errors = {}, generation = 0 }
local function record(key, verification)
    return { key = key, name = "Synthetic UI NPC", npcID = 123, kind = "npc",
        category = "Combat", mapID = 1, x = 10, y = 20, tags = {},
        source = verification == "reference" and "classic-reference:test" or "synthetic-test-only",
        permission = "test-fixture", edition = verification == "reference" and "Classic" or "Forever",
        build = "test", locale = "enUS", verification = verification,
        precision = verification == "reference" and "reference" or
            (verification == "pending" and "encounter" or "confirmed") }
end
local confirmed = record("synthetic:ui-confirmed", "curated")
local reference = record("reference:ui:123:1:1", "reference")
local pending = record("local:ui-pending", "pending")
M.observations = { entries = {
    [pending.key] = pending, [confirmed.key] = confirmed,
}, nextID = 1 }
M.data = { entries = { reference } }
M:BuildIndex()
M.scope, M.kind, M.category, M.view, M.offset, M.selected =
    "global", "all", "All", "directory", 0, 1
M.directoryCounts = { all = 2, npc = 2, location = 0, uniqueNPCs = 1, categories = {} }
M.results = { { record = reference, placementCount = 3 } }

M.ShowCopy = function() error("Help must not use the export/copy dialog") end
M:ShowHelp()
assert(M.helpFrame:IsShown() and M.helpFrame ~= M.copyFrame)
assert(M.helpFrame.body:GetText():find("Pending observations", 1, true))
assert(M.helpFrame.body.fontSize >= 15, "help must have a readable base font")
assert(M.helpFrame.body.width >= 500, "help needs a spacious reading area")
M.helpFrame:GetScript("OnKeyDown")(M.helpFrame, "ESCAPE")
assert(not M.helpFrame:IsShown())
M.ShowCopy = showCopy

M:ShowEntryDetails({ record = reference })
local body = M.detailsFrame.body:GetText()
assert(body:find("Legacy saved location", 1, true), "old Classic favorites must be labeled as legacy")
assert(body:find("Source: classic-reference:test", 1, true))
assert(body:find("test-fixture", 1, true), "reference records must show their license/permission note")
assert(body:find("NPCs & creatures", 1, true), "generic NPCs must not be labeled hostile")
local waypointTitle, waypointCalls = nil, 0
M.SetNavigationWaypoint = function(_, _, _, _, title)
    waypointCalls, waypointTitle = waypointCalls + 1, title
    return true
end
M.detailsFrame.navigate:Click()
assert(waypointCalls == 1 and waypointTitle:find("[Legacy]", 1, true))
M:ShowEntryDetails({ record = pending })
M.detailsFrame.navigate:Click()
assert(waypointCalls == 1, "pending details must not bypass the navigation guard")
M.detailsFrame:Hide()
M.SetNavigationWaypoint = navigate

M:Render()
assert(M.window.rows[1].name:GetText():find("(3 locations)", 1, true))
assert(M.window.rows[1].name.fontSize >= 13 and M.window.rows[1].height >= 44,
    "native rows must retain readable type and vertical spacing")
local textCalls, fontCalls, colorCalls = uiCalls.text, uiCalls.font, uiCalls.color
M:Render()
assert(uiCalls.text == textCalls and uiCalls.font == fontCalls and uiCalls.color == colorCalls)
M.results[1].placementCount = 4
M:Render()
assert(M.window.rows[1].name:GetText():find("(4 locations)", 1, true))
M.results[1].placementCount = 1
M:Render()
assert(not M.window.rows[1].name:GetText():find("locations", 1, true))
assert(M.window.viewButtons.review:GetText():find("(1)", 1, true),
    "Review must count pending observations, not all journal entries")
assert(M.window.onboarding:GetText():find("Confirmed NPC: 1 placements / 1 IDs", 1, true),
    "reference records must never increase the confirmed count")
local onboarding = M.window.onboarding
local reviewButton = M.window.viewButtons.review
M.window.onboarding = nil
M.window.viewButtons.review = nil
M:Render()
M.window.onboarding = onboarding
M.window.viewButtons.review = reviewButton

M:ShowSettings()
local refreshCalls = 0
M.RefreshIfVisible = function() refreshCalls = refreshCalls + 1 end
local grouped = M.settings.groupNPCs
M.options.group:Click()
assert(M.settings.groupNPCs ~= grouped and refreshCalls == 1)
M.options.group:Click()
assert(M.settings.groupNPCs == grouped and refreshCalls == 2)
local enabled = M.settings.referenceEnabled
M.options.references:Click()
assert(M.settings.referenceEnabled ~= enabled and refreshCalls == 3)
M.options:Hide()
M.RefreshIfVisible = refresh

local inventoryText
M.NPCInventory = function()
    return { { npcID = 123, name = "Synthetic inventory", confirmed = 0,
        pending = 1, reference = 7, maps = { [1] = true } } }
end
M.ShowCopy = function(_, text) inventoryText = text end
M:ShowNPCInventory()
assert(inventoryText:find("Confirmed placements | Pending encounters | Database records", 1, true))
assert(inventoryText:find("123 | Synthetic inventory | 0 | 1 | 7 |", 1, true),
    "reference count must have its own inventory column")
M.ShowCopy, M.NPCInventory = showCopy, inventory

local stepWorld, refreshWindow, addObjects = M.StepClientWorldSync, M.Refresh, M.AddExtractedObjects
local taxi, poi = C_TaxiMap, C_AreaPoiInfo
local searchPending, lastMap = M.searchPending, M.lastMap
local windowShown = M.window:IsShown()
M.window:Show()
M.searchPending = nil
C_TaxiMap, C_AreaPoiInfo = nil, nil
M.AddExtractedObjects = function() end
M.Refresh = function() end
M.StepClientWorldSync = function() return false end
M.clientData = { maps = {}, errors = {}, generation = 0 }
M:BuildIndex()
local scanIndex = M.index
M:DistanceTick()
assert(M.index == scanIndex, "first empty client map scan must not rebuild the existing NPC index")
assert(M.index.clientGeneration == M.clientData.generation)
local mapID = C_Map.GetBestMapForUnit("player")
M.clientData.maps[mapID] = nil
M.AddExtractedObjects = function(_, id, add)
    add({ key = "client:poi:" .. id .. ":ui-scan", name = "Synthetic scan marker",
        kind = "location", category = "Landmarks", mapID = id, x = 10, y = 20,
        tags = { "landmark" }, source = "client:poi", permission = "client-api",
        edition = "Forever", build = "test", locale = "enUS",
        verification = "client-map", precision = "map" })
end
M:DistanceTick()
assert(M.index == scanIndex, "new client map markers must preserve the reference index identity")
assert(M.index.byKey["client:poi:" .. mapID .. ":ui-scan"],
    "incrementally scanned markers must remain searchable")
M.StepClientWorldSync = function() return true end
M:DistanceTick()
assert(M.index == scanIndex, "world scan completion must not force a full index rebuild")
M.StepClientWorldSync, M.Refresh, M.AddExtractedObjects = stepWorld, refreshWindow, addObjects
C_TaxiMap, C_AreaPoiInfo = taxi, poi
if not windowShown then M.window:Hide() end
M.searchPending, M.lastMap = searchPending, lastMap
for _, key in ipairs({ "settings", "observations", "data", "clientData", "dbIndex",
    "index", "results", "directoryCounts", "scope", "kind", "category", "view", "offset", "selected" }) do
    M[key] = saved[key]
end
M.confirmedNPCCountIndex = nil

-- Translated button labels that are too wide shrink to fit instead of being cut off.
do
    local b = M.Widgets.button(UIParent, "Long translated label", 0, 0, 60)
    local spec = M.fonts[#M.fonts]
    assert(spec.fit == 46, "helper buttons track the room available for their label")
    local measured = 92
    spec.font.GetStringWidth = function() return measured end
    b:SetText("Ansicht zuruecksetzen")
    assert(spec.font.fontSize == 8, "an over-wide label shrinks (never below 8pt)")
    measured = 30
    b:SetText("OK")
    assert(spec.font.fontSize == spec.size * M.settings.textScale, "a label that fits keeps its full size")
    b:Hide()
end
print("UI refactor regression assertions passed")
