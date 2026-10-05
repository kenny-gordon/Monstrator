local addonName, M = ...
M.name = addonName
M.version = "1.0.0"
M.L = setmetatable({}, { __index = function(_, key) return key end })
local L = M.L
M.defaults = {
    collecting = false, observationLimit = 1000, frameScale = 1,
    textScale = 1, highContrast = false, minimapHidden = false,
    minimapAngle = 225, debug = false, discovering = false,
    sortOrder = "distance", evidenceFilter = "all", referenceEnabled = true, groupNPCs = true,
    scope = "zone", zoneMap = 0, regionMap = 0, windowX = 0, windowY = 0,
}

function M:Notice(message)
    print("|cffd6a64b[Monstrator]|r " .. tostring(message))
end

function M:Error(message)
    self:Notice(self.L["Error: "] .. tostring(message))
end

function M:Debug(message)
    if self.settings and self.settings.debug then self:Notice(message) end
end

function M:IsFinite(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function M:Diagnostic()
    local version, build, date, interface = GetBuildInfo()
    self:Notice(("Version %s; build %s; interface %s; locale %s; project %s"):format(
        tostring(version), tostring(build), tostring(interface), GetLocale(), tostring(WOW_PROJECT_ID)))
    if interface == 16001 then
        self:Notice("Client interface matches Monstrator TOC 16001.")
    else
        self:Error("Client interface " .. tostring(interface) .. " differs from Monstrator TOC 16001; compatibility needs verification.")
    end
    local checks = {
        playerMap = C_Map and C_Map.GetBestMapForUnit,
        playerPosition = C_Map and C_Map.GetPlayerMapPosition,
        worldPosition = C_Map and C_Map.GetWorldPosFromMapPos,
        userWaypoint = C_Map and C_Map.SetUserWaypoint,
        waypointSupport = C_Map and C_Map.CanSetUserWaypointOnMap,
        timer = C_Timer and C_Timer.NewTicker,
        TomTom = TomTom and TomTom.AddWaypoint,
        gossip = C_GossipInfo and C_GossipInfo.GetOptions,
        taxiNodes = C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap,
        mapLandmarks = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap,
    }
    for _, name in ipairs({ "playerMap", "playerPosition", "worldPosition", "userWaypoint",
        "waypointSupport", "timer", "TomTom", "gossip", "taxiNodes", "mapLandmarks" }) do
        self:Notice(name .. ": " .. (type(checks[name]) == "function" and "available" or "unavailable"))
    end
    self:Notice("Profiler namespace: " .. tostring(type(C_AddOnProfiler)))
    local clientCount, mapCount, offMapCount = 0, 0, 0
    for _, map in pairs(self.clientData.maps) do
        mapCount = mapCount + 1
        clientCount = clientCount + #map.entries
        offMapCount = offMapCount + (map.offMap or 0)
    end
    self:Notice(("Client map cache: %d markers across %d queried maps (not a complete world database)."):format(clientCount, mapCount))
    self:Notice(("Off-map markers skipped in latest cached map reads: %d. Coordinates were not clamped."):format(offMapCount))
    local objectAccepted, objectRejected = 0, 0
    for _, check in pairs(self.clientData.objectChecks or {}) do
        objectAccepted = objectAccepted + check.accepted
        objectRejected = objectRejected + check.rejected
    end
    self:Notice(("Extracted object checks: %d accepted, %d rejected against live transforms."):format(objectAccepted, objectRejected))
    local counts, meta, overlays = self:NativeSummary()
    if meta or next(overlays) then
        self:Notice(("Monstrator database %s (%s): %d NPCs, %d objects, %d items, %d quests; overlay %d discoveries, %d corrections, %d deletions."):format(
            meta and meta.version or "local", tostring(meta and meta.flavor or "Forever"), counts.Npc or 0, counts.Object or 0,
            counts.Item or 0, counts.Quest or 0, overlays.discovery or 0, overlays.correction or 0, overlays.deleted or 0))
        self:Notice(meta and meta.source and ("Imported base data: %s (credited, not relicensed)."):format(meta.source)
            or "Standalone build: Monstrator's own discoveries and corrections only (no imported base data).")
    else
        self:Notice("Monstrator database is empty (standalone build). Collect NPCs in game, or import data with tools\\monstrator-db.cjs.")
    end
    local q = self.dbIndex
    if q then
        self:Notice(("Directory index: %s; %d NPCs and %d objects across %d maps; %d maps expanded."):format(
            q.ready and "ready" or ("indexing " .. (q.nextIndex - 1) .. "/" .. #q.ids),
            q.npcCount, q.objectCount, q.mapCount, (function() local n = 0 for _ in pairs(self.dbCache) do n = n + 1 end return n end)()))
    else
        self:Notice("Directory index: not started" .. (self.settings and not self.settings.referenceEnabled and " (database disabled in Settings)." or "."))
    end
    if self.clientMapCatalog then
        local queue = self.clientData.worldQueue
        self:Notice(("Extracted catalog: %d zone maps, build %s; world scan %s."):format(
            #self.clientMapCatalog.maps, self.clientMapCatalog.build,
            queue and ("queued at map " .. queue.next) or (self.clientData.worldScanned and "finished" or "not started")))
    end
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        local memory = GetAddOnMemoryUsage(addonName)
        self:Notice(("Total addon memory: %.1f KB (includes data, journal, indexes and open UI)"):format(memory))
        self:Notice(("Memory context: UI %s; indexes %s; journal %d; static records %d. Cached UI remains allocated after closing."):format(
            self.window and (self.window:IsShown() and "open" or "cached/closed") or "not created",
            self.index and "built" or "not built", self.observations and self:ObservationCount() or 0,
            self.data and #self.data.entries or 0))
        if memory > 150 then self:Notice("Total exceeds the 150 KB target; this is not an isolated core-only measurement.") end
    end
end

function M:ProfileSearch()
    self:EnsureIndex()
    self:IndexDatabase()
    if type(debugprofilestop) ~= "function" then self:Error("Client timing API unavailable."); return end
    local npcCount = self.index.byKind.npc and #self.index.byKind.npc or 0
    if npcCount == 0 then self:Error("No indexed NPC records; a zero-NPC benchmark is not meaningful."); return end
    self:Notice("Measured NPC dataset: " .. npcCount .. " records. Distances obey the normal 0.5s cache; not a worst-case certification.")
    for _, query in ipairs({ "", "food", "no-match-monstrator" }) do
        local started = debugprofilestop()
        local count = #self:Query("global", "npc", "All", query, "directory")
        local elapsed = debugprofilestop() - started
        self:Notice(("Query '%s': %d matches, %.2f ms%s"):format(query, count, elapsed,
            elapsed >= 50 and " - exceeds 50 ms target" or ""))
    end
    self:RefreshIfVisible()
end

local function initializeTable(name, defaults)
    local value = _G[name]
    if value == nil then
        value = { schema = 1 }
        _G[name] = value
    end
    if type(value) ~= "table" or (value.schema ~= nil and value.schema ~= 1) then
        M:Error(name .. " has an unsupported saved schema; preserved unchanged. Addon disabled.")
        return nil
    end
    value.schema = 1
    for key, default in pairs(defaults or {}) do
        if value[key] == nil then value[key] = default end
    end
    return value
end

function M:Initialize()
    self.ready = nil
    self.index = nil
    self.settings = initializeTable("Monstrator_Settings", self.defaults)
    self.favorites = initializeTable("Monstrator_Favorites", { entries = {} })
    self.observations = initializeTable("Monstrator_Observations", { entries = {}, nextID = 1 })
    if not self.settings or not self.favorites or not self.observations then return end
    if type(self.favorites.entries) ~= "table" or type(self.observations.entries) ~= "table" then
        self:Error(L["Invalid saved entries; preserved unchanged. Addon disabled."])
        return
    end
    local s = self.settings
    if not self:IsFinite(s.observationLimit) or s.observationLimit < 1 or s.observationLimit > 100000
        or s.observationLimit % 1 ~= 0
        or not self:IsFinite(s.frameScale) or s.frameScale < 0.6 or s.frameScale > 1.5
        or not self:IsFinite(s.textScale) or s.textScale < 0.8 or s.textScale > 1.5
        or not self:IsFinite(s.minimapAngle)
        or not self:IsFinite(self.observations.nextID) or self.observations.nextID < 1
        or self.observations.nextID % 1 ~= 0 then
        self:Error(L["Invalid saved limits/scales/identity counter; preserved unchanged. Addon disabled."])
        return
    end
    if not ({ distance = true, name = true, zone = true, npcID = true, level = true })[s.sortOrder]
        or not ({ all = true, confirmed = true, pending = true, map = true, reference = true })[s.evidenceFilter] then
        self:Error(L["Invalid saved sort/evidence filter; preserved unchanged. Addon disabled."]); return
    end
    for _, key in ipairs({ "collecting", "discovering", "referenceEnabled", "groupNPCs", "highContrast", "minimapHidden", "debug" }) do
        if type(s[key]) ~= "boolean" then
            self:Error(L["Invalid saved setting "] .. key .. "; preserved unchanged. Addon disabled.")
            return
        end
    end
    for _, entries in ipairs({ self.favorites.entries, self.observations.entries }) do
        for key, record in pairs(entries) do
            if type(record) ~= "table" or type(key) ~= "string" or record.key ~= key then
                self:Error(L["Invalid saved record identity; preserved unchanged. Addon disabled."])
                return
            end
        end
    end
    -- Remembered view state is cosmetic, so bad values are reset instead of disabling the addon.
    if not ({ zone = true, region = true, global = true })[s.scope] then s.scope = "zone" end
    for _, key in ipairs({ "zoneMap", "regionMap" }) do
        if not self:IsFinite(s[key]) or s[key] < 0 or s[key] % 1 ~= 0 then s[key] = 0 end
    end
    for _, key in ipairs({ "windowX", "windowY" }) do
        if not self:IsFinite(s[key]) or math.abs(s[key]) > 4000 then s[key] = 0 end
    end
    self:InitializeScanner()
    self.ready = true
    self:CreateLauncher()
    if C_Timer and C_Timer.After then C_Timer.After(1, function() self:StartDatabaseIndex() end)
    else self:StartDatabaseIndex() end
end

SLASH_MONSTRATOR1 = "/monstrator"
SLASH_MONSTRATOR2 = "/mon"
SlashCmdList.MONSTRATOR = function(input)
    local command, argument = input:match("^(%S*)%s*(.-)$")
    if command == "diagnostic" then M:Diagnostic(); return end
    if not M.ready then M:Error(L["Not initialized. Use /monstrator diagnostic."]); return end
    if command == "debug" then
        M.settings.debug = not M.settings.debug
        M:Notice(L["Debug: "] .. tostring(M.settings.debug))
    elseif command == "minimap" then
        M.settings.minimapHidden = not M.settings.minimapHidden
        M.launcher:SetShown(not M.settings.minimapHidden)
    elseif command == "collect" then
        M.settings.collecting = not M.settings.collecting
        M:Notice(L["Local collection: "] .. tostring(M.settings.collecting))
    elseif command == "discover" then
        M.settings.discovering = not M.settings.discovering
        M:Notice(L["NPC target/mouseover discovery: "] .. tostring(M.settings.discovering)
            .. ". Encounter positions require review; players are excluded.")
    elseif command == "limit" then
        local limit = tonumber(argument)
        if not M:IsFinite(limit) or limit < 1 or limit > 100000 or limit % 1 ~= 0 then
            M:Error(L["Limit must be an integer from 1 to 100000."]); return
        end
        M.settings.observationLimit = limit
        M.fullNotice = nil
        M:Notice(L["Observation limit: "] .. limit)
    elseif command == "export" then M:ShowExport()
    elseif command == "issues" then M:ShowIssues()
    elseif command == "profile" then M:ProfileSearch()
    elseif command == "sync" then
        if argument == "world" then
            if M:StartClientWorldSync(true) then
                if not M.window then M:CreateWindow() end
                M.window:Show()
                M.scope, M.kind, M.category = "global", "location", "All"
                M:UpdateCategories()
            end
        elseif argument == "" then M:SyncClientData()
        else M:Error(L["Use /monstrator sync or /monstrator sync world."]) end
    elseif command == "zone" or command == "region" then M:JumpToPlace(command, argument)
    elseif command == "reset" then M:ResetView()
    elseif command == "items" or command == "item" then M:ShowItemLookup(argument)
    elseif command == "model" then M:ShowSelectedModel()
    elseif command == "scan" then M:ScanCommand(argument)
    elseif command == "journal" then M:Toggle("journal")
    elseif command == "capture" then M:CaptureNPC("manual-target")
    elseif command == "npcs" then M:ShowNPCInventory()
    elseif command == "audit" then M:AuditObservations()
    elseif command == "tags" then
        local tags = {}
        for tag in pairs(M.tags) do table.insert(tags, tag) end
        table.sort(tags)
        M:ShowCopy("Canonical tags:\n" .. table.concat(tags, ", "))
    elseif command == "landmark" then M:CaptureLandmark(argument)
    elseif command == "clear" then
        if argument ~= "CONFIRM" then M:Error(L["Use /monstrator clear CONFIRM to erase the local journal."]); return end
        wipe(M.observations.entries)
        M.fullNotice = nil
        M:BuildIndex()
        M:RefreshIfVisible()
        M:Notice(L["Local journal cleared. Favorites retained."])
    elseif command == "help" then
        M:Notice("/monstrator [diagnostic | issues | profile | sync [world] | zone [NAME] | region [NAME] | items [NAME] | model | scan [add|remove|list|on|off|rares|sound|test] | reset | journal | npcs | audit | tags | capture | discover | debug | minimap | collect | limit N | landmark NAME | export | clear CONFIRM]")
    elseif command == "" then M:Toggle()
    else M:Error(L["Unknown command. Use /monstrator help."]) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        M:Initialize()
        events:UnregisterEvent("ADDON_LOADED")
    end
end)
