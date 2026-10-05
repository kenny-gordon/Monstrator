local _, M = ...
local aliases = { food = { "food", "innkeeper" }, travel = { "flight", "boat", "zeppelin", "portal" },
    supplies = { "profession_supplies", "reagent" }, mail = { "mailbox" }, herbalism = { "herb" }, herbs = { "herb" },
    mining = { "ore" }, mine = { "ore" }, node = { "herb", "ore" }, nodes = { "herb", "ore" }, gather = { "herb", "ore" },
    treasure = { "chest" }, loot = { "chest" }, fish = { "fishing" }, smithing = { "anvil", "forge" },
    blacksmithing = { "anvil", "forge" }, smelt = { "forge" }, cook = { "cooking" }, fire = { "cooking" },
    summon = { "meeting_stone" }, quest = { "quest_giver", "quest_object" } }

local function append(index, key, entry)
    if not index[key] then index[key] = {} end
    table.insert(index[key], entry)
end

local function hasSubgroup(entry, key)
    for _, value in ipairs(entry.subgroups or {}) do
        if value == key then return true end
    end
    return false
end

function M:EnsureIndex()
    if not self.index then self:BuildIndex() end
end

function M:EnsureClientIndex()
    if not self.index or self.index.clientGeneration ~= self.clientData.generation then self:BuildIndex() end
end

function M:RecordSearchText(record)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(record.mapID)
    return string.lower(record.name .. " " .. table.concat(record.tags, " ") .. " "
        .. record.category .. " " .. (info and info.name or tostring(record.mapID)) .. " "
        .. tostring(record.npcID or "") .. " " .. (record.creatureType or "") .. " " .. (record.classification or "")
        .. " " .. (record.title or ""))
end

function M:IndexRecord(record)
    local valid, reason = self:ValidateRecord(record)
    if not valid or self.index.byKey[record.key] then
        table.insert(self.quarantine, { record = record, reason = reason or "Duplicate stable key." })
        return nil
    end
    if record.verification == "pending" then return true end
    local entry = { record = record, text = self:RecordSearchText(record), subgroups = self:RecordSubgroups(record) }
    self.index.byKey[record.key] = entry
    table.insert(self.index.all, entry)
    append(self.index.byMap, record.mapID, entry)
    append(self.index.byKind, record.kind, entry)
    append(self.index.byCategory, record.category, entry)
    if record.npcID then append(self.index.byNPC, record.npcID, entry) end
    local seen = {}
    for token in entry.text:gmatch("%S+") do
        if not seen[token] then append(self.index.byToken, token, entry); seen[token] = true end
    end
    self.searchCandidate = nil
    return true
end

function M:BuildIndex()
    self.index = { all = {}, byKey = {}, byMap = {}, byKind = {}, byCategory = {}, byNPC = {}, byToken = {},
        referenceMaps = {}, clientGeneration = self.clientData.generation }
    self.searchCandidate = nil
    self.quarantine = {}
    for _, record in ipairs(self.data.entries) do self:IndexRecord(record) end
    for _, map in pairs(self.clientData.maps) do
        for _, record in ipairs(map.entries) do self:IndexRecord(record) end
    end
    for _, record in pairs(self.observations.entries) do self:IndexRecord(record) end
    for key, record in pairs(self.favorites.entries) do
        local valid, reason = self:ValidateRecord(record)
        if not valid then table.insert(self.quarantine, { record = record, reason = "Favorite " .. key .. ": " .. reason }) end
    end
    if #self.quarantine > 0 then self:Error(#self.quarantine .. " invalid records quarantined; use /monstrator issues.") end
end

function M:PlayerPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if issecretvalue and issecretvalue(mapID) then return end
    if not mapID then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if issecretvalue and issecretvalue(position) then return end
    if not position then return end
    local x, y = position:GetXY()
    if issecretvalue and (issecretvalue(x) or issecretvalue(y)) then return end
    if self:IsFinite(x) and self:IsFinite(y) then return mapID, x * 100, y * 100 end
end

function M:WorldPosition(mapID, x, y)
    if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
    local instance, position = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
    if issecretvalue and (issecretvalue(instance) or issecretvalue(position)) then return end
    if not position then return end
    local wx, wy = position:GetXY()
    if issecretvalue and (issecretvalue(instance) or issecretvalue(wx) or issecretvalue(wy)) then return end
    if self:IsFinite(wx) and self:IsFinite(wy) then return instance, wx, wy end
end

function M:MapName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or ("Map " .. tostring(mapID))
end

-- Walks the UiMap parent chain to the owning continent; maps without one fall into region 0 ("Other").
function M:MapRegion(mapID)
    self.regionCache = self.regionCache or {}
    local cached = mapID and self.regionCache[mapID]
    if cached then return cached.id, cached.name end
    local continent = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
    local id, name, current = 0, self.L["Other regions"], mapID
    for _ = 1, 8 do
        local info = current and current > 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(current)
        if not info then break end
        if info.mapType == continent then id, name = current, info.name; break end
        current = info.parentMapID
    end
    if mapID then self.regionCache[mapID] = { id = id, name = name } end
    return id, name
end

function M:PlayerMap()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

function M:ScopeMap()
    return self.zoneMap or self:PlayerMap()
end

function M:ScopeRegion()
    if self.regionMap then return self.regionMap end
    local map = self:PlayerMap()
    return map and (self:MapRegion(map)) or 0
end

function M:PlaceName(scope)
    scope = scope or self.scope
    if scope == "zone" then
        local map = self:ScopeMap()
        return map and self:MapName(map) or self.L["Position unavailable"]
    elseif scope == "region" then
        local _, name = self:MapRegion(self.regionMap or self:PlayerMap())
        return name
    end
    return self.L["Whole world"]
end

function M:ZoneCatalog()
    self:EnsureIndex()
    self:IndexDatabase()
    local faction = UnitFactionGroup("player")
    local key = table.concat({ tostring(self.index), #self.index.all, self.kind, self.settings.evidenceFilter,
        tostring(self.settings.referenceEnabled), tostring(faction) }, "|")
    if self.zoneCatalogCache and self.zoneCatalogCache.key == key then return self.zoneCatalogCache.regions end
    local byRegion, regions = {}, {}
    for mapID, entries in pairs(self.index.byMap) do
        local count, ids = 0, {}
        for _, entry in ipairs(entries) do
            local r = entry.record
            if (self.kind == "all" or r.kind == self.kind) and self:MatchesEvidence(r)
                and (not r.faction or r.faction == "Both" or r.faction == faction) then
                local identity = r.kind == "npc" and r.npcID or (r.objectID and "o" .. r.objectID)
                if not identity then count = count + 1
                elseif not ids[identity] then ids[identity] = true; count = count + 1 end
            end
        end
        if count > 0 then
            local regionID, regionName = self:MapRegion(mapID)
            local region = byRegion[regionID]
            if not region then
                region = { id = regionID, name = regionName, count = 0, zones = {} }
                byRegion[regionID] = region
                table.insert(regions, region)
            end
            region.count = region.count + count
            table.insert(region.zones, { id = mapID, name = self:MapName(mapID), count = count })
        end
    end
    table.sort(regions, function(a, b)
        if (a.id == 0) ~= (b.id == 0) then return b.id == 0 end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    for _, region in ipairs(regions) do
        table.sort(region.zones, function(a, b)
            if a.name ~= b.name then return a.name < b.name end
            return a.id < b.id
        end)
    end
    self.zoneCatalogCache = { key = key, regions = regions }
    return regions
end

local function distanceOrder(a, b)
    if a.distance ~= b.distance then
        if a.distance == nil then return false end
        if b.distance == nil then return true end
        return a.distance < b.distance
    end
    if (a.sortZone or "") ~= (b.sortZone or "") then return (a.sortZone or "") < (b.sortZone or "") end
    if a.record.name ~= b.record.name then return a.record.name < b.record.name end
    return a.record.key < b.record.key
end

local function nameOrder(a, b)
    if a.record.name ~= b.record.name then return a.record.name < b.record.name end
    return a.record.key < b.record.key
end

local function zoneOrder(a, b)
    if a.sortZone ~= b.sortZone then return a.sortZone < b.sortZone end
    if a.distance ~= b.distance and a.distance and b.distance then return a.distance < b.distance end
    return nameOrder(a, b)
end

local function levelOrder(a, b)
    local first, second = a.record.level or math.huge, b.record.level or math.huge
    if first ~= second then return first < second end
    return zoneOrder(a, b)
end

local function npcOrder(a, b)
    local first, second = a.record.npcID or math.huge, b.record.npcID or math.huge
    if first ~= second then return first < second end
    return nameOrder(a, b)
end

local function selectPlacement(entry)
    if not entry.placements then return end
    local nearest = entry.placements[1]
    for i = 2, #entry.placements do
        if distanceOrder(entry.placements[i], nearest) then nearest = entry.placements[i] end
    end
    entry.record, entry.text = nearest.record, nearest.text
    entry.distance, entry.distanceLabel = nearest.distance, nearest.distanceLabel
end

function M:GroupNPCResults(results)
    if not self.settings.groupNPCs then return results end
    local grouped, byKey = {}, {}
    for _, entry in ipairs(results) do
        local r = entry.record
        local identity = r.kind == "npc" and r.npcID or (r.objectID and "o" .. r.objectID)
        if identity then
            local key = identity .. ":" .. r.mapID .. ":" .. r.verification
            local group = byKey[key]
            if not group then
                group = { record = r, text = entry.text, placements = {}, placementCount = 0 }
                byKey[key] = group
                table.insert(grouped, group)
            end
            table.insert(group.placements, entry)
            group.placementCount = group.placementCount + 1
        else table.insert(grouped, entry) end
    end
    for _, entry in ipairs(grouped) do selectPlacement(entry) end
    return grouped
end

function M:SortResults(results)
    local order = self.settings.sortOrder
    local labels = {}
    for _, entry in ipairs(results) do
        local mapID = entry.record.mapID
        local text = labels[mapID]
        if not text then
            local _, region = self:MapRegion(mapID)
            text = region .. "\31" .. self:MapName(mapID)
            labels[mapID] = text
        end
        entry.sortZone = text
    end
    table.sort(results, order == "name" and nameOrder or (order == "zone" and zoneOrder
        or (order == "npcID" and npcOrder or (order == "level" and levelOrder or distanceOrder))))
end

function M:MatchesEvidence(record)
    if record.verification == "reference" and not self.settings.referenceEnabled then return false end
    local filter = self.settings.evidenceFilter
    if filter == "confirmed" then
        return record.verification == "user-confirmed" or record.verification == "curated"
    elseif filter == "pending" then return record.verification == "pending"
    elseif filter == "map" then
        return record.verification == "client-map" or record.verification == "client-object"
    elseif filter == "reference" then return record.verification == "reference"
    end
    return true
end

function M:UpdateDistances(results, onlyChanges)
    if #results == 0 then return false end
    local now = GetTime()
    local changed = false
    if not self.lastDistanceUpdate or now - self.lastDistanceUpdate >= 0.5 then
        self.lastDistanceUpdate = now
        local mapID, x, y = self:PlayerPosition()
        local instance, px, py
        if mapID then instance, px, py = self:WorldPosition(mapID, x, y) end
        local position = self.distancePosition
        if not position or position.instance ~= instance or position.x ~= px or position.y ~= py
            or position.mapID ~= mapID then
            self.distanceGeneration = (self.distanceGeneration or 0) + 1
            self.distancePosition = { instance = instance, x = px, y = py, mapID = mapID }
        end
        local function update(entry)
            if entry.distanceGeneration ~= self.distanceGeneration or not entry.world then
                local oldDistance, oldLabel = entry.distance, entry.distanceLabel
                entry.distance = nil
                entry.distanceLabel = self.L["Distance unavailable"]
                local r = entry.record
                if px then
                    if not entry.world then
                        local wi, wx, wy = self:WorldPosition(r.mapID, r.x, r.y)
                        if wx then entry.world = { instance = wi, x = wx, y = wy } end
                    end
                    local world = entry.world
                    if world and world.instance == instance then
                        entry.distance = math.sqrt((world.x - px)^2 + (world.y - py)^2)
                    elseif world then entry.distanceLabel = self.L["Different world/instance"] end
                elseif mapID and mapID ~= r.mapID then entry.distanceLabel = self.L["Different zone"] end
                entry.distanceGeneration = self.distanceGeneration
                if entry.distance ~= oldDistance or entry.distanceLabel ~= oldLabel then changed = true end
            end
        end
        for _, entry in ipairs(results) do
            if entry.placements then
                for _, placement in ipairs(entry.placements) do update(placement) end
                local oldRecord, oldDistance = entry.record, entry.distance
                selectPlacement(entry)
                if entry.record ~= oldRecord or entry.distance ~= oldDistance then changed = true end
            else update(entry) end
        end
    end
    if not onlyChanges or changed then self:SortResults(results) end
    return changed
end

local function matches(text, query)
    for token in query:gmatch("%S+") do
        local found = text:find(token, 1, true) ~= nil
        if not found and aliases[token] then
            for _, alias in ipairs(aliases[token]) do
                if text:find(alias, 1, true) then found = true; break end
            end
        end
        if not found then return false end
    end
    return true
end

function M:SearchCandidates(query)
    if self.searchCandidate and self.searchCandidate.query == query then return self.searchCandidate.entries end
    local candidates = self.index.all
    for term in query:gmatch("%S+") do
        local union, seen = {}, {}
        for token, entries in pairs(self.index.byToken) do
            if matches(token, term) then
                for _, entry in ipairs(entries) do
                    if not seen[entry] then table.insert(union, entry); seen[entry] = true end
                end
            end
        end
        if #union < #candidates then candidates = union end
    end
    self.searchCandidate = { query = query, entries = candidates }
    return candidates
end

function M:Query(scope, kind, category, query, view)
    local playerMap = self:PlayerMap()
    if self:RefreshClientMap(playerMap) then self:EnsureClientIndex() end
    local mapID = scope == "zone" and self:ScopeMap() or playerMap
    if scope == "zone" and mapID ~= playerMap and self:RefreshClientMap(mapID) then self:EnsureClientIndex() end
    self:EnsureIndex()
    self.results = self.results or {}
    wipe(self.results)
    local region = scope == "region" and self:ScopeRegion()
    local subgroupDef = self:ActiveSubgroup(kind, category)
    local subgroup = subgroupDef and subgroupDef.key
    if view == "directory" and (scope ~= "zone" or mapID) then
        self:IndexDatabase(scope == "zone" and mapID or nil)
    elseif view == "favorites" then
        for _, record in pairs(self.favorites.entries) do
            if record.verification == "reference" then self:IndexDatabase(record.mapID) end
        end
    end
    local candidates = self.index.all
    local function choose(list)
        if list and #list < #candidates then candidates = list end
    end
    if scope == "zone" then
        if not mapID then return self.results end
        choose(self.index.byMap[mapID] or {})
    end
    if kind ~= "all" then choose(self.index.byKind[kind] or {}) end
    if category ~= "All" then choose(self.index.byCategory[category] or {}) end
    local npcFilter = view == "directory" and self.npcFilter and self.npcFilter.ids
    if npcFilter then choose(self.index.byKind.npc or {}) end
    query = string.lower(query or "")
    if view == "directory" and query ~= "" then choose(self:SearchCandidates(query)) end
    if view == "review" or view == "journal" then
        for _, r in pairs(self.observations.entries) do
            if r.verification == "pending" or view == "journal" then
                local valid = self:ValidateRecord(r)
                if valid and self:MatchesEvidence(r) and matches(self:RecordSearchText(r), query) then
                    table.insert(self.results, { record = r, text = r.name })
                end
            end
        end
    elseif view == "favorites" then
        for key, saved in pairs(self.favorites.entries) do
            local entry = self.index.byKey[key]
            local revised = entry and (entry.record.mapID ~= saved.mapID or entry.record.x ~= saved.x
                or entry.record.y ~= saved.y or entry.record.npcID ~= saved.npcID or entry.record.name ~= saved.name)
            if not entry or revised then
                local valid, reason = self:ValidateRecord(saved)
                if valid then entry = { record = saved, stale = true }
                else entry = nil
                end
            end
            if entry and self:MatchesEvidence(entry.record) and matches(self:RecordSearchText(entry.record), query) then
                table.insert(self.results, entry)
            end
        end
    else
        for _, entry in ipairs(candidates) do
            local r = entry.record
            if (kind == "all" or r.kind == kind) and self:MatchesEvidence(r)
                and (not r.faction or r.faction == "Both" or r.faction == UnitFactionGroup("player"))
                and (scope ~= "zone" or r.mapID == mapID)
                and (not region or self:MapRegion(r.mapID) == region)
                and (category == "All" or r.category == category) and matches(entry.text, query)
                and (not subgroup or hasSubgroup(entry, subgroup))
                and (not npcFilter or (r.npcID and npcFilter[r.npcID])) then
                table.insert(self.results, entry)
            end
        end
    end
    if view == "directory" then self.results = self:GroupNPCResults(self.results) end
    self:UpdateDistances(self.results)
    return self.results
end

function M:DirectoryCounts(scope, query)
    self:EnsureIndex()
    local counts = { all = 0, npc = 0, location = 0, uniqueNPCs = 0, categories = {}, subgroups = {} }
    local identities, objects = {}, {}
    local mapID = scope == "zone" and self:ScopeMap() or self:PlayerMap()
    local region = scope == "region" and self:ScopeRegion()
    if scope ~= "zone" or mapID then self:IndexDatabase(scope == "zone" and mapID or nil) end
    local faction = UnitFactionGroup("player")
    query = string.lower(query or "")
    local candidates = scope == "zone" and (self.index.byMap[mapID] or {}) or self.index.all
    local npcFilter = self.npcFilter and self.npcFilter.ids
    local grouped = self.settings.groupNPCs
    for _, entry in ipairs(candidates) do
        local r = entry.record
        if (scope ~= "zone" or r.mapID == mapID) and (not region or self:MapRegion(r.mapID) == region)
            and self:MatchesEvidence(r)
            and (not npcFilter or (r.npcID and npcFilter[r.npcID]))
            and (not r.faction or r.faction == "Both" or r.faction == faction)
            and matches(entry.text, query) then
            -- Count rows exactly as GroupNPCResults builds them, so each button matches the list it opens.
            local identity = grouped and (r.kind == "npc" and r.npcID or (r.objectID and "o" .. r.objectID))
            local groupKey = identity and (identity .. ":" .. r.mapID .. ":" .. r.verification)
            if groupKey and objects[groupKey] then
            else
            if groupKey then objects[groupKey] = true end
            counts.all = counts.all + 1
            counts[r.kind] = counts[r.kind] + 1
            if r.kind == "npc" and not identities[r.npcID] then
                identities[r.npcID] = true
                counts.uniqueNPCs = counts.uniqueNPCs + 1
            end
            local categories = counts.categories[r.kind]
            if not categories then categories = {}; counts.categories[r.kind] = categories end
            categories[r.category] = (categories[r.category] or 0) + 1
            for _, key in ipairs(entry.subgroups or {}) do counts.subgroups[key] = (counts.subgroups[key] or 0) + 1 end
            end
        end
    end
    return counts
end

function M:NPCInventory()
    self:EnsureIndex()
    self:IndexDatabase()
    local byID = {}
    local function include(record)
        if record.kind ~= "npc" or (record.verification == "reference" and not self.settings.referenceEnabled) then return end
        local item = byID[record.npcID]
        if not item then
            item = { npcID = record.npcID, name = record.name, confirmed = 0, pending = 0, reference = 0, maps = {} }
            byID[record.npcID] = item
        end
        item.maps[record.mapID] = true
        if record.verification == "pending" then item.pending = item.pending + 1
        elseif record.verification == "reference" then item.reference = item.reference + 1
        else item.confirmed = item.confirmed + 1 end
    end
    for _, entry in ipairs(self.index.byKind.npc or {}) do include(entry.record) end
    for _, record in pairs(self.observations.entries) do
        if record.verification == "pending" and self:ValidateRecord(record) then include(record) end
    end
    local inventory = {}
    for _, item in pairs(byID) do table.insert(inventory, item) end
    table.sort(inventory, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.npcID < b.npcID
    end)
    return inventory
end

function M:ToggleFavorite(record)
    if self.favorites.entries[record.key] then self.favorites.entries[record.key] = nil
    else
        local copy = {}
        for key, value in pairs(record) do
            if type(value) == "table" then
                copy[key] = {}
                for k, v in pairs(value) do copy[key][k] = v end
            else copy[key] = value end
        end
        self.favorites.entries[record.key] = copy
    end
    self:RefreshIfVisible()
end
