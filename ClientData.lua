local _, M = ...
M.clientData = { maps = {}, errors = {}, generation = 0 }

local function available(value)
    return not issecretvalue or not issecretvalue(value)
end

local function invoke(provider, fn, ...)
    if M.clientData.errors[provider] then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then
        M.clientData.errors[provider] = tostring(result)
        M:Error(provider .. " client-data provider failed: " .. tostring(result) .. ". Use /monstrator sync to retry.")
        return nil
    end
    if not available(result) then return nil end
    return result
end

local function mapRecord(mapID, id, info, category, tags, provider, build)
    if not available(info) or type(info) ~= "table" then return nil end
    if not available(info.name) or not available(info.position)
        or type(info.name) ~= "string" or not info.position then return nil end
    local x, y = info.position:GetXY()
    if not M:IsFinite(id) or id < 1 or id % 1 ~= 0 or not M:IsFinite(x) or not M:IsFinite(y) then return nil end
    -- Providers can project nodes outside the requested map's normalized bounds.
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, "off-map" end
    return {
        key = ("client:%s:%d:%d"):format(provider, mapID, id), name = info.name,
        mapID = mapID, x = x * 100, y = y * 100, kind = "location",
        category = category, tags = tags, source = "client:" .. provider,
        build = tostring(build), locale = GetLocale(), edition = "Forever",
        verification = "client-map", precision = "map",
    }
end

function M:RefreshClientMap(mapID, force)
    if not self:IsFinite(mapID) or mapID < 1 or mapID % 1 ~= 0
        or not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapInfo(mapID) then return false end
    local now = GetTime()
    local previous = self.clientData.maps[mapID]
    if not force and previous and now - previous.updated < 30 then return false end
    local records, seen, offMap = {}, {}, 0
    local _, build = GetBuildInfo()
    local function createRecord(id, info, category, tags, provider)
        local record, reason = mapRecord(mapID, id, info, category, tags, provider, build)
        if reason == "off-map" then offMap = offMap + 1 end
        return record
    end
    local function add(record)
        if not record then return end
        local valid, reason = self:ValidateRecord(record)
        if not valid then self:Error("Client map record rejected: " .. reason); return end
        if seen[record.key] then return end
        seen[record.key] = true
        table.insert(records, record)
    end
    if C_TaxiMap and type(C_TaxiMap.GetTaxiNodesForMap) == "function" then
        local nodes = invoke("taxi", C_TaxiMap.GetTaxiNodesForMap, mapID)
        if type(nodes) == "table" then
            for _, node in ipairs(nodes) do
                if available(node) and type(node) == "table" and available(node.faction) then
                    local record = createRecord(node.nodeID, node, "Transit", { "flight", "flight_path" }, "taxi")
                    if record then
                        if node.faction == 1 then record.faction = "Horde"
                        elseif node.faction == 2 then record.faction = "Alliance" end
                    end
                    add(record)
                end
            end
        end
    end
    if C_AreaPoiInfo and type(C_AreaPoiInfo.GetAreaPOIForMap) == "function"
        and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function"
        and type(C_AreaPoiInfo.IsAreaPOITimed) == "function" then
        local ids = invoke("poi", C_AreaPoiInfo.GetAreaPOIForMap, mapID)
        if type(ids) == "table" then
            for _, id in ipairs(ids) do
                if self:IsFinite(id) then
                    local timed = invoke("poi", C_AreaPoiInfo.IsAreaPOITimed, id)
                    if timed == false then
                        local info = invoke("poi", C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
                        if type(info) == "table" and available(info.isCurrentEvent) and info.isCurrentEvent ~= true then
                            add(createRecord(id, info, "Landmarks", { "landmark" }, "poi"))
                        end
                    end
                end
            end
        end
    end
    self:AddExtractedObjects(mapID, add)
    if offMap > 0 and not self.clientData.offMapNotice then
        self.clientData.offMapNotice = true
        self:Debug("Client APIs returned off-map markers; skipped (see /monstrator diagnostic).")
    end
    local changed = not previous or #previous.entries ~= #records
    if not changed then
        for i, record in ipairs(records) do
            local old = previous.entries[i]
            if old.key ~= record.key or old.name ~= record.name or old.x ~= record.x
                or old.y ~= record.y or old.faction ~= record.faction or old.build ~= record.build then
                changed = true; break
            end
        end
    end
    if not changed then previous.updated, previous.offMap = now, offMap; return false end
    self.clientData.maps[mapID] = { entries = records, updated = now, offMap = offMap }
    self.clientData.generation = self.clientData.generation + 1
    if self.index and self.index.clientGeneration == self.clientData.generation - 1
        and (not previous or #previous.entries == 0) then
        for _, record in ipairs(records) do self:IndexRecord(record) end
        self.index.clientGeneration = self.clientData.generation
    end
    return true
end

function M:SyncClientData()
    wipe(self.clientData.errors)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not self:IsFinite(mapID) or not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapInfo(mapID) then
        self:Error("Current map unavailable; no client data loaded."); return
    end

    self:RefreshClientMap(mapID, true)
    self:BuildIndex()
    self:RefreshIfVisible()
    self:Notice(("Loaded %d current-map points from available client APIs. These are map markers, not NPC spawn records."):format(
        #self.clientData.maps[mapID].entries))
    if not C_TaxiMap or type(C_TaxiMap.GetTaxiNodesForMap) ~= "function" then
        self:Notice("Flight-node API unavailable on this client.")
    end
    if not C_AreaPoiInfo or type(C_AreaPoiInfo.GetAreaPOIForMap) ~= "function"
        or type(C_AreaPoiInfo.GetAreaPOIInfo) ~= "function" or type(C_AreaPoiInfo.IsAreaPOITimed) ~= "function" then
        self:Notice("Non-timed landmark API unavailable on this client.")
    end
end

function M:ClientWorldMaps()
    local version, build = GetBuildInfo()
    local catalog = self.clientMapCatalog
    if catalog and catalog.build == tostring(version) .. "." .. tostring(build) then return catalog.maps end
    if not C_Map or type(C_Map.GetMapChildrenInfo) ~= "function"
        or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetMapInfo) ~= "function" then return end
    local root = C_Map.GetBestMapForUnit("player")
    local visited = {}
    while self:IsFinite(root) and root > 0 and not visited[root] do
        visited[root] = true
        local info = invoke("map-catalog", C_Map.GetMapInfo, root)
        if type(info) ~= "table" or not available(info.parentMapID) then return end
        if info.parentMapID == 0 then
            local children = invoke("map-catalog", C_Map.GetMapChildrenInfo, root,
                Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, true)
            if type(children) ~= "table" then return end
            local maps, seen = {}, {}
            for _, child in ipairs(children) do
                if available(child) and type(child) == "table" and self:IsFinite(child.mapID)
                    and child.mapID > 0 and child.mapID % 1 == 0 and not seen[child.mapID] then
                    seen[child.mapID] = true
                    table.insert(maps, child.mapID)
                end
            end
            table.sort(maps)
            if #maps > 0 then return maps end
            return
        end
        root = info.parentMapID
    end
end

function M:StartClientWorldSync(force)
    if self.clientData.worldQueue then
        if force then self:Notice("World map scan already running; keep the directory open.") end
        return false
    end
    if self.clientData.worldScanned and not force then return false end
    if force then wipe(self.clientData.errors) end
    local maps = self:ClientWorldMaps()
    if not maps then
        self.clientData.worldSyncStatus = self.L["mapScan.limited"]
        if force then self:Error(self.clientData.worldSyncStatus) end
        self.clientData.worldSyncRefused = true
        return false
    end
    local version, build = GetBuildInfo()
    local extracted = self.extractedObjects
    local extractedMatches = extracted and extracted.build == tostring(version) .. "." .. tostring(build)
        and extracted.locale == GetLocale()
    if not C_Map or type(C_Map.GetMapInfo) ~= "function"
        or not ((C_TaxiMap and type(C_TaxiMap.GetTaxiNodesForMap) == "function")
        or (extractedMatches and type(C_Map.GetWorldPosFromMapPos) == "function" and CreateVector2D)
        or (C_AreaPoiInfo and type(C_AreaPoiInfo.GetAreaPOIForMap) == "function"
        and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function"
        and type(C_AreaPoiInfo.IsAreaPOITimed) == "function")) then
        self.clientData.worldSyncStatus = self.L["mapScan.limited"]
        if force then self:Error("World map scan requires a flight/POI provider or a supported extracted-object transform.") end
        self.clientData.worldSyncRefused = true
        return false
    end
    self.clientData.worldSyncStatus, self.clientData.worldSyncRefused = nil, nil
    self.clientData.worldQueue = { next = 1, force = force, maps = maps }
    if force then self:Notice(("Scanning %d zone maps while the directory is open."):format(#maps)) end
    return true
end

function M:StepClientWorldSync()
    local queue = self.clientData.worldQueue
    if not queue then return false end
    local now = GetTime()
    if queue.updated and now - queue.updated < 0.5 then return false end
    queue.updated = now
    local mapID = queue.maps[queue.next]
    local changed = self:RefreshClientMap(mapID, queue.force)
    queue.next = queue.next + 1
    if queue.next > #queue.maps then
        self.clientData.worldQueue = nil
        self.clientData.worldScanned = true
        local count = 0
        for _, map in pairs(self.clientData.maps) do count = count + #map.entries end
        if queue.force then self:Notice(("World map scan finished: %d map markers."):format(count)) end
        if next(self.clientData.errors) then
            self:Error("Some world-map providers failed; use /monstrator sync world to retry.")
        end
    end
    return changed
end
