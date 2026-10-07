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
local help = M.helpFrame
assert(help:IsShown() and help ~= M.copyFrame)
assert(#help.topicRows == #M.helpTopics and help.topic == 1, "help opens on the first topic")
assert(help.heading:GetText() == "Getting started")
assert(help.lines[1].bullet:IsShown() and not help.lines[1].text:GetText():find("\226\128\162", 1, true),
    "bullet glyph is drawn separately for a hanging indent")
assert(help.lines[1].text.fontSize >= 15, "help must have a readable base font")
assert(help.lines[1].text.width >= 480, "help needs a spacious reading area")
help.topicRows[5]:Click()
assert(help.topic == 5 and help.heading:GetText() == "Review journal")
local found = false
for _, item in ipairs(help.lines) do
    if item.text:IsShown() and item.text:GetText():find("Pending observations", 1, true) then found = true end
end
assert(found, "review topic explains pending observations")
assert(help.topicRows[5].selection.shown and not help.topicRows[1].selection.shown)
help.topicRows[#M.helpTopics]:Click()
assert(help.lines[1].text:GetText():find("^|cffffd100/monstrator|r"), "commands render as a highlighted list")
assert(not help.lines[1].bullet:IsShown())
for _, topic in ipairs(M.helpTopics) do
    assert(M.L[topic[2]] ~= topic[2], "help topic text exists: " .. topic[2])
end
help:GetScript("OnKeyDown")(help, "ESCAPE")
assert(not help:IsShown())
M:ShowHelp()
assert(help.topic == #M.helpTopics, "help reopens on the last topic")
help:Hide()
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
assert(M.window.template == "PortraitFrameTemplate", "directory inherits the client's native window chrome")
assert(M.window.TitleContainer.TitleText:GetText() == "MONSTRATOR")
assert(M.window.PortraitContainer.portrait.texture == "Interface\\Icons\\INV_Misc_Map02")
assert(M.window.close == M.window.CloseButton)
assert(M.window.resultsPanel.backdrop.bgFile == "Interface\\FrameGeneral\\UI-Background-Rock")
assert(M.window.detailsPanel.parchment.atlas == "QuestBG-Parchment",
    "selected entry uses the client's quest parchment, not bundled artwork")
local info = M.window.info
assert(M.window.rows[1].icon.texture == M:EntryIcon(reference))
assert(info.icon.texture == M.window.rows[1].icon.texture, "list and details use the same category icon")
assert(M.window.rows[1].iconBorder.texture == "Interface\\Buttons\\UI-Quickslot2")
assert(M.window.categoryButtons[1].browseIcon, "browse filters have visual category cues")
local browse = M.window.kindButtons.all
assert(not browse.Left:IsShown() and not browse.Middle:IsShown() and not browse.Right:IsShown(),
    "list styling hides template regions without passing nil texture assets")
assert(M.window.viewButtons.directory.template == "PanelTabButtonTemplate")
assert(M.window.viewButtons.directory.activeMarker:IsShown() and not M.window.viewButtons.review.activeMarker:IsShown())
local changeView = M.ChangeView
local tabView
M.ChangeView = function(_, view) tabView = view end
for _, view in ipairs({ "directory", "favorites", "review" }) do
    M.window.viewButtons[view]:Click()
    assert(tabView == view, "each native tab switches its own list")
end
M.ChangeView = changeView
assert(info.scroll.height == 274, "selection has more room than the previous 180px viewport")
assert(info.name.color[1] < 0.4 and info.body.color[1] < 0.4, "parchment uses readable dark ink")
assert(info.name.shadowX == 0 and info.name.shadowY == 0
    and info.body.shadowX == 0 and info.body.shadowY == 0,
    "dark parchment text must not inherit the dark shadow used on native gold text")
assert(info.body.fontSize == 13 and info.body.spacing == 2, "parchment body has readable type and leading")
for _, section in ipairs(info.sections) do
    assert(section.body.wordWrap and section.body.nonSpaceWrap and section.body.maxLines == 0,
        "all parchment sections explicitly wrap full evidence, including long words, without line limits")
    assert(section.body.x + section.body.width <= section.width, "wrapped text stays inside its section")
end
assert(M.window.rows[1].distance.width == 144 and M.window.rows[1].distance.maxLines == 2
    and M.window.rows[1].distance.wordWrap, "long cross-world labels have a wider wrapping column")
assert(M.window.rows[1].detail.x + M.window.rows[1].detail.width < M.window.rows[1].distance.x,
    "wrapped distances do not overlap the secondary location text")
assert(not M.window.coverage:IsShown() and not M.window.onboarding:IsShown()
    and M.window.status:GetScript("OnEnter"), "diagnostic summaries are available in the footer tooltip")
assert(M.window.resultFocus:GetText() == M.L["Keyboard"] and M.window.resultFocus:GetScript("OnEnter"),
    "keyboard results control must not be mistaken for setting a combat focus target")
M.window.search:SetFocus()
M.window.resultFocus:Click()
assert(not M.window.search:HasFocus() and not M.focusIndex, "keyboard button releases search input for result navigation")
local currentWindow, currentRefresh = M.window, M.Refresh
local refreshed = false
M.Refresh = function() refreshed = true end
local timerStart = #pendingTimers
currentWindow.search:GetScript("OnTextChanged")()
assert(#pendingTimers == timerStart + 1)
M.window = nil
pendingTimers[#pendingTimers]()
assert(not refreshed, "a queued search must not refresh a missing or replaced window")
local queued = #pendingTimers
currentWindow.search:GetScript("OnTextChanged")()
assert(#pendingTimers == queued, "an incomplete window must not queue search work")
M.window, M.Refresh = currentWindow, currentRefresh
M.searchPending = nil
assert(info.location:GetText():find("/way #1 ", 1, true))
assert(info.identity:GetText():find("NPC ID 123", 1, true))
assert(info.scroll.scrollChild == info.content and #info.sections == 3)
assert(info.content.height > info.scroll.height, "long details remain accessible by scrolling")
assert(M:EntryIcon({ kind = "npc", category = "Trainers", title = "Fishing Trainer", tags = {} })
    == "Interface\\Icons\\Trade_Fishing")
assert(M:EntryIcon({ kind = "location", category = "Objects", tags = { "ore" } })
    == "Interface\\Icons\\Trade_Mining")
assert(M:EntryIcon({ kind = "location", category = "Mailboxes", tags = {} })
    == "Interface\\Icons\\INV_Letter_15")
assert(M:EntryIcon({ kind = "npc", category = "Services", tags = { "quest_giver" } })
    == "Interface\\Icons\\INV_Misc_Note_01", "quest NPCs have a contextual icon, not a generic key")
assert(M:EntryIcon({ kind = "npc", category = "Services", tags = { "flight", "quest_giver" } })
    == "Interface\\Icons\\Ability_Mount_Wyvern_01", "specific services take priority over quest-giver status")
assert(not M.window.rows[1].detail:GetText():find("NPC ID", 1, true))
assert(M:EntryIcon({ kind = "npc", category = "Combat", tags = {} })
    == "Interface\\Icons\\INV_Misc_Head_Human_01", "unknown creature artwork must not imply hostility")
assert(M.window.rows[1].name.fontSize == 14 and M.window.rows[1].detail.fontSize == 13,
    "result names and secondary text remain readable at the base text scale")
assert(M.window.rows[1].name.fontSize >= 13 and M.window.rows[1].height >= 44,
    "native rows must retain readable type and vertical spacing")
local textCalls, fontCalls, colorCalls = uiCalls.text, uiCalls.font, uiCalls.color
M:Render()
assert(uiCalls.text == textCalls and uiCalls.font == fontCalls and uiCalls.color == colorCalls)
local oldCategory = reference.category
reference.category = "Vendors"
M:Render()
assert(info.identity:GetText():find("Vendors", 1, true), "details update when a record changes in place")
assert(info.icon.texture == M:EntryIcon(reference))
reference.category = oldCategory
info.scroll:SetVerticalScroll(50)
M.results = { { record = confirmed } }
M:Render()
assert(info.scroll:GetVerticalScroll() == 0, "a new selection starts at the top of its details")
M.results = {}
M:Render()
assert(not info.sections[1]:IsShown() and not info.sections[2]:IsShown() and info.sections[3]:IsShown())
assert(not info.navigate:IsShown() and info.body:GetText():find("Select a result", 1, true))
M.results = { { record = reference, placementCount = 3 } }
M:Render()
local originalHeight = rawget(info.body, "GetStringHeight")
info.body.GetStringHeight = function() return 360 end
M.settings.textScale = 1.5
M:Render()
assert(info.sections[3].height == 402 and info.content.height >= 402,
    "wrapped evidence expands its card and scroll content instead of clipping")
info.body.GetStringHeight = originalHeight
M.settings.textScale = 1
M:Render()
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
assert(M.options.template == "PortraitFrameTemplate" and M.options.width == 700)
for key, setting in pairs({ collect = "collecting", discover = "discovering", references = "referenceEnabled",
    group = "groupNPCs", contrast = "highContrast" }) do
    assert(M.options[key].template == "UICheckButtonTemplate")
    assert(M.options[key]:GetChecked() == M.settings[setting], "checkbox reflects saved setting " .. setting)
end
assert(M.options.minimap:GetChecked() == not M.settings.minimapHidden)
local refreshCalls = 0
M.RefreshIfVisible = function() refreshCalls = refreshCalls + 1 end
local grouped = M.settings.groupNPCs
M.options.group:Click()
assert(M.settings.groupNPCs ~= grouped and refreshCalls == 1)
assert(M.options.group:GetChecked() == M.settings.groupNPCs)
M.options.group:Click()
assert(M.settings.groupNPCs == grouped and refreshCalls == 2)
local enabled = M.settings.referenceEnabled
M.options.references:Click()
assert(M.settings.referenceEnabled ~= enabled and refreshCalls == 3)
assert(M.options.references:GetChecked() == M.settings.referenceEnabled)
local collection = M.settings.collecting
M.options.collect:Click()
assert(M.settings.collecting ~= collection and M.options.collect:GetChecked() == M.settings.collecting)
M.options.collect:Click()
for control, setting in pairs({ discover = "discovering", contrast = "highContrast" }) do
    local previous = M.settings[setting]
    M.options[control]:Click()
    assert(M.settings[setting] ~= previous and M.options[control]:GetChecked() == M.settings[setting])
    M.options[control]:Click()
    assert(M.settings[setting] == previous)
end
local oldLimit = M.settings.observationLimit
M.options.limit:SetText("0")
M.options.applyLimit:Click()
assert(M.settings.observationLimit == oldLimit, "invalid limits leave settings untouched")
M.options.limit:SetText("2000")
M.options.applyLimit:Click()
assert(M.settings.observationLimit == 2000)
M.settings.observationLimit = oldLimit
M.options:Hide()
M.RefreshIfVisible = refresh
local savedView = M.view
M.view = "review"
M:Render()
assert(M.window.info.navigate:GetText() == M.L["Review placement"], "journal primary action explains review")
M.view = "favorites"
M:Render()
assert(M.window.kindButtons.npc:GetText() == M.L["NPCs"],
    "favorites must not display unrelated directory totals in the sidebar")
M.view = "directory"
M:Render()
assert(M.window.info.navigate:GetText() == M.L["Navigate"], "directory primary action explains navigation")
M.view = savedView
M:Render()

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
local getAtlasInfo, originalWindow = C_Texture.GetAtlasInfo, M.window
local originalFonts, originalFocus, originalPending = M.fonts, M.focusOrder, M.searchPending
local errorsBefore = #messages
C_Texture.GetAtlasInfo = function() return nil end
M.fonts = {}
M:CreateWindow()
assert(not M.window.info.parchment and M.window.detailsPanel.parchment == nil,
    "clients without the quest atlas retain the dark native layout")
local fallbackReported = false
for i = errorsBefore + 1, #messages do
    if messages[i]:find("Quest parchment atlas unavailable", 1, true) then fallbackReported = true end
end
assert(fallbackReported, "missing artwork is reported, not silently hidden")
C_Texture.GetAtlasInfo = getAtlasInfo
M.window, M.fonts, M.focusOrder, M.searchPending = originalWindow, originalFonts, originalFocus, originalPending
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
