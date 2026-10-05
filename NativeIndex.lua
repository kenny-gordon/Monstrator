local _, M = ...
local L = M.L
-- Indexes Monstrator's native database (NativeDB.lua + Data\Native) into directory records, one zone at a
-- time. NPC IDs are bucketed by UiMap in time-sliced chunks at login; records for a zone are built only
-- when that zone is browsed (or warmed in the background), so the full world is never expanded at once.
M.dbCache = {}

local CHUNK = 2000
local KEY_PREFIX = "reference:monstrator:"
local SOURCE_PREFIX = "monstrator-db:"
M.dbKeyPrefix, M.dbSourcePrefix = KEY_PREFIX, SOURCE_PREFIX

local flags = {
    VENDOR = 4, FLIGHT_MASTER = 8, TRAINER = 16, SPIRIT_HEALER = 32, INNKEEPER = 128, BANKER = 256,
    PETITIONER = 512, TABARD_DESIGNER = 1024, BATTLEMASTER = 2048, AUCTIONEER = 4096,
    STABLEMASTER = 8192, REPAIR = 16384, QUEST_GIVER = 2,
}
M.npcFlags = flags
local titleTags = {
    { "riding", { "trainer", "riding" } },
    { "weapon master", { "trainer", "weapon_master" } },
    { "flight master", { "flight" } },
    { "wind rider master", { "flight" } },
    { "gryphon master", { "flight" } },
    { "hippogryph master", { "flight" } },
    { "bat handler", { "flight" } },
    { "food", { "food", "vendor" } },
    { "drink", { "drink", "vendor" } },
    { "baker", { "food", "vendor" } },
    { "butcher", { "food", "vendor" } },
    { "innkeeper", { "innkeeper" } },
    { "reagent", { "reagent", "vendor" } },
    { "trade supplies", { "profession_supplies", "vendor" } },
    { "supplies", { "profession_supplies", "vendor" } },
    { "weapon", { "weapon", "vendor" } },
    { "armor", { "armor", "vendor" } },
    { "armorer", { "armor", "vendor" } },
    { "potion", { "potion", "vendor" } },
    { "guild master", { "guild" } },
    { "tabard", { "tabard" } },
    { "banker", { "bank" } },
    { "auctioneer", { "auction" } },
    { "stable", { "stable" } },
}
local classes = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
-- GM/test/trigger creatures that exist in the data but are never meaningful directory entries.
local internal = { "only gm", "unused", "trigger", "invisible", "test npc", "visual marker", "[dnd]", "<txt>", "doodad" }

-- Object class (assigned by the import tools) -> directory category and canonical tags.
local objectKinds = {
    mailbox = { "Mailboxes", { "mailbox" } }, meeting_stone = { "Instances", { "meeting_stone", "dungeon" } },
    herb = { "Objects", { "herb" } }, ore = { "Objects", { "ore" } }, chest = { "Objects", { "chest" } },
    fishing = { "Objects", { "fishing" } }, anvil = { "Objects", { "anvil" } }, forge = { "Objects", { "forge" } },
    cooking = { "Objects", { "cooking" } }, quest = { "Objects", { "quest_object" } },
}
M.objectKinds = objectKinds

local function hasFlag(value, bit)
    return value and value % (bit * 2) >= bit
end

local function read(getter, id)
    if type(getter) ~= "function" then return end
    local ok, value = pcall(getter, id)
    if ok then return value end
end

local function addTag(tags, seen, tag)
    if M.tags[tag] and not seen[tag] then seen[tag] = true; table.insert(tags, tag) end
end

function M:NPCIdentity(npcFlags, title)
    local tags, seen = {}, {}
    if hasFlag(npcFlags, flags.VENDOR) then addTag(tags, seen, "vendor") end
    if hasFlag(npcFlags, flags.REPAIR) then addTag(tags, seen, "repair") end
    if hasFlag(npcFlags, flags.FLIGHT_MASTER) then addTag(tags, seen, "flight"); addTag(tags, seen, "flight_path") end
    if hasFlag(npcFlags, flags.TRAINER) then addTag(tags, seen, "trainer") end
    if hasFlag(npcFlags, flags.INNKEEPER) then addTag(tags, seen, "innkeeper"); addTag(tags, seen, "food") end
    if hasFlag(npcFlags, flags.BANKER) then addTag(tags, seen, "bank") end
    if hasFlag(npcFlags, flags.AUCTIONEER) then addTag(tags, seen, "auction") end
    if hasFlag(npcFlags, flags.STABLEMASTER) then addTag(tags, seen, "stable") end
    if hasFlag(npcFlags, flags.PETITIONER) then addTag(tags, seen, "guild") end
    if hasFlag(npcFlags, flags.TABARD_DESIGNER) then addTag(tags, seen, "tabard") end
    if hasFlag(npcFlags, flags.QUEST_GIVER) then addTag(tags, seen, "quest_giver") end
    local lower = type(title) == "string" and title:lower() or ""
    if lower ~= "" then
        for _, rule in ipairs(titleTags) do
            if lower:find(rule[1], 1, true) then
                for _, tag in ipairs(rule[2]) do addTag(tags, seen, tag) end
            end
        end
        if seen.trainer and not seen.riding and not seen.weapon_master then
            local class = false
            for _, name in ipairs(classes) do
                if lower:find(name, 1, true) then class = true end
            end
            addTag(tags, seen, class and "class_trainer" or "profession_trainer")
        end
    end
    local category = "Combat"
    if seen.flight then category = "Transit"
    elseif seen.trainer then category = "Trainers"
    elseif seen.bank or seen.auction or seen.innkeeper or seen.stable or seen.guild or seen.tabard
        or hasFlag(npcFlags, flags.SPIRIT_HEALER) or hasFlag(npcFlags, flags.BATTLEMASTER) then category = "Services"
    elseif seen.vendor or seen.repair then category = "Vendors"
    elseif seen.quest_giver then category = "Services" end
    return category, tags
end

function M:DatabaseProvenance()
    local lib = self:NativeProvider()
    local version = tostring(lib and lib.version or "?")
    local origin = lib and lib.source
        and ("base data imported from " .. lib.source .. " (credits: " .. lib.source .. " contributors)")
        or "Monstrator discoveries and corrections"
    return SOURCE_PREFIX .. version, "Monstrator database " .. version .. "; " .. origin .. ". Not live-verified.", version
end

function M:DataSourceLabel()
    return "Monstrator DB"
end

function M:StartDatabaseIndex()
    if self.dbIndex or not self.settings or not self.settings.referenceEnabled then return end
    local lib = self:NativeProvider()
    if not lib then return end
    local ok, ids = pcall(lib.Npc.GetAllIds)
    if not ok or type(ids) ~= "table" then self:Error(L["Monstrator database NPC list unavailable."]); return end
    local state = { lib = lib, version = tostring(lib.version), ids = ids, nextIndex = 1,
        byMap = {}, mapCount = 0, npcCount = 0, ready = false, knownMaps = {},
        objectsByMap = {}, objectCount = 0 }
    self.dbIndex = state
    local function knownMap(uiMap)
        if state.knownMaps[uiMap] == nil then
            state.knownMaps[uiMap] = (uiMap and uiMap > 0 and C_Map and C_Map.GetMapInfo
                and C_Map.GetMapInfo(uiMap)) and true or false
        end
        return state.knownMaps[uiMap]
    end
    state.knownMap = knownMap
    local mapsOf = lib.Npc.mapIDs or lib.Npc.spawns
    local function step()
        if self.dbIndex ~= state then return end
        local last = math.min(#ids, state.nextIndex + CHUNK - 1)
        for i = state.nextIndex, last do
            local id = ids[i]
            local maps = read(mapsOf, id)
            if type(maps) == "table" then
                local counted = false
                for uiMap in pairs(maps) do
                    if knownMap(uiMap) then
                        local list = state.byMap[uiMap]
                        if not list then list = {}; state.byMap[uiMap] = list; state.mapCount = state.mapCount + 1 end
                        if list[#list] ~= id then table.insert(list, id) end
                        if not counted then counted = true; state.npcCount = state.npcCount + 1 end
                    end
                end
            end
        end
        state.nextIndex = last + 1
        if state.nextIndex <= #ids then
            if C_Timer and C_Timer.After then C_Timer.After(0, step) else step() end
            return
        end
        self:IndexDatabaseObjects(state)
        state.ready, state.knownMaps = true, nil
        self.index = nil
        self:Notice((L["Monstrator database %s loaded: %d NPCs, %d objects in %d zones."]):format(
            state.version, state.npcCount, state.objectCount, state.mapCount))
        self:RefreshIfVisible()
        self:WarmDatabaseCache(state)
    end
    step()
end

-- Materialize one map per frame so the first World-scope query does not stall the client.
function M:WarmDatabaseCache(state)
    if not (C_Timer and C_Timer.After) then return end
    local maps = {}
    for mapID in pairs(state.byMap) do table.insert(maps, mapID) end
    for mapID in pairs(state.objectsByMap) do if not state.byMap[mapID] then table.insert(maps, mapID) end end
    table.sort(maps)
    local i = 0
    local function warm()
        if self.dbIndex ~= state or not self.settings.referenceEnabled then return end
        i = i + 1
        local mapID = maps[i]
        if not mapID then return end
        self:DatabaseMapRecords(mapID)
        C_Timer.After(0.05, warm)
    end
    C_Timer.After(1, warm)
end

function M:DatabaseReady()
    return self.dbIndex and self.dbIndex.ready and self.settings.referenceEnabled
end

-- Only classified objects (mailboxes, nodes, chests, stations...) become directory locations.
function M:IndexDatabaseObjects(state)
    local object = state.lib.Object
    if not (object and object.class and object.GetAllIds) then return end
    local ok, ids = pcall(object.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    for _, id in ipairs(ids) do
        local class = read(object.class, id)
        if class and objectKinds[class] then
            local maps = read(object.mapIDs or object.spawns, id)
            local counted = false
            for uiMap in pairs(type(maps) == "table" and maps or {}) do
                if state.knownMap(uiMap) then
                    local list = state.objectsByMap[uiMap]
                    if not list then
                        list = {}; state.objectsByMap[uiMap] = list
                        if not state.byMap[uiMap] then state.mapCount = state.mapCount + 1 end
                    end
                    table.insert(list, id)
                    if not counted then counted = true; state.objectCount = state.objectCount + 1 end
                end
            end
        end
    end
end

local function pointKey(x, y)
    return ("%s,%s"):format(tostring(x), tostring(y))
end

local function validPoint(x, y)
    return M:IsFinite(x) and M:IsFinite(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100
end

function M:DatabaseObjectRecords(state, mapID, records, source, permission)
    local ids = state.objectsByMap[mapID]
    if not ids then return 0 end
    local object, rejected = state.lib.Object, 0
    for _, id in ipairs(ids) do
        local name, kind = read(object.name, id), objectKinds[read(object.class, id) or ""]
        local spawns = kind and type(name) == "string" and name ~= "" and read(object.spawns, id)
        local points = type(spawns) == "table" and spawns[mapID]
        local seen = {}
        for _, point in ipairs(type(points) == "table" and points or {}) do
            local x, y = point[1], point[2]
            local key = validPoint(x, y) and pointKey(x, y)
            if key and not seen[key] then
                seen[key] = true
                local record = {
                    key = ("%so%d:%d:%s"):format(KEY_PREFIX, id, mapID, key),
                    objectID = id, name = name, kind = "location", category = kind[1], tags = kind[2],
                    mapID = mapID, x = x, y = y, source = source, permission = permission,
                    edition = "Forever", build = state.version, locale = GetLocale(),
                    verification = "reference", precision = "reference",
                    nativeOrigin = object.Origin and object.Origin(id) or nil,
                }
                if self:ValidateRecord(record) then table.insert(records, record) else rejected = rejected + 1 end
            end
        end
    end
    return rejected
end

function M:DatabaseMapRecords(mapID)
    if self.dbCache[mapID] then return self.dbCache[mapID] end
    local state = self.dbIndex
    if not (state and state.ready) then return {} end
    if not state.byMap[mapID] and not state.objectsByMap[mapID] then return {} end
    local npc, records, rejected = state.lib.Npc, {}, 0
    local source, permission = self:DatabaseProvenance()
    for _, id in ipairs(state.byMap[mapID] or {}) do
        local name = read(npc.name, id)
        local lowered = type(name) == "string" and name:lower() or ""
        local skip = lowered == ""
        for _, word in ipairs(internal) do
            if lowered:find(word, 1, true) then skip = true end
        end
        local spawns = not skip and read(npc.spawns, id)
        local points = type(spawns) == "table" and spawns[mapID]
        if type(points) == "table" then
            local title = read(npc.subName, id)
            if type(title) ~= "string" or title == "" then title = nil end
            local npcFlags = read(npc.npcFlags, id)
            local level = read(npc.maxLevel, id)
            local friendly = read(npc.friendlyToFaction, id)
            local faction = friendly == "A" and "Alliance" or friendly == "H" and "Horde"
                or friendly == "AH" and "Both" or nil
            local category, tags = self:NPCIdentity(type(npcFlags) == "number" and npcFlags or 0, title)
            local origin = npc.Origin and npc.Origin(id) or nil
            local seen = {}
            for _, point in ipairs(points) do
                local x, y = type(point) == "table" and point[1], type(point) == "table" and point[2]
                local key = validPoint(x, y) and pointKey(x, y)
                if key and not seen[key] then
                    seen[key] = true
                    local record = {
                        key = ("%s%d:%d:%s"):format(KEY_PREFIX, id, mapID, key),
                        npcID = id, name = name, title = title, kind = "npc",
                        category = category, tags = tags, faction = faction,
                        level = (type(level) == "number" and level > 0 and level % 1 == 0) and level or nil,
                        mapID = mapID, x = x, y = y,
                        source = source, permission = permission,
                        edition = "Forever", build = state.version, locale = GetLocale(),
                        verification = "reference", precision = "reference",
                        nativeOrigin = origin,
                    }
                    if self:ValidateRecord(record) then table.insert(records, record)
                    else rejected = rejected + 1 end
                end
            end
        end
    end
    rejected = rejected + self:DatabaseObjectRecords(state, mapID, records, source, permission)
    if rejected > 0 then self:Debug(("Monstrator DB map %d: %d placements rejected by validation."):format(mapID, rejected)) end
    self.dbCache[mapID] = records
    return records
end

-- Adds database records for one map (or every indexed map) to the directory index.
function M:IndexDatabase(mapID)
    if not self:DatabaseReady() then return end
    local state = self.dbIndex
    local function indexMap(id)
        if self.index.referenceMaps[id] then return end
        self.index.referenceMaps[id] = true
        for _, record in ipairs(self:DatabaseMapRecords(id)) do self:IndexRecord(record) end
    end
    if mapID then indexMap(mapID)
    else
        for id in pairs(state.byMap) do indexMap(id) end
        for id in pairs(state.objectsByMap) do indexMap(id) end
    end
end


-- Compares the local journal with the database: Forever-only NPCs, NPCs on new maps and coordinate drift.
-- tools\monstrator-db.cjs harvest turns confirmed findings into shipped data.
local AUDIT_DRIFT = 2
function M:AuditObservations()
    local lib = self:NativeProvider()
    local groups = { new = {}, map = {}, drift = {} }
    local matched, total = 0, 0
    local keys = {}
    for key in pairs(self.observations.entries) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local r = self.observations.entries[key]
        if r.kind == "npc" and r.npcID and r.mapID and self:IsFinite(r.x) and self:IsFinite(r.y) then
            total = total + 1
            local line = ("%d %s - %s %.1f, %.1f (%s)"):format(r.npcID, r.name or "?", self:MapName(r.mapID), r.x, r.y,
                L[r.verification] or r.verification)
            if not (lib and lib.Npc.Has(r.npcID)) then table.insert(groups.new, line)
            else
                local points = (read(lib.Npc.spawns, r.npcID) or {})[r.mapID]
                if type(points) ~= "table" or #points == 0 then table.insert(groups.map, line)
                else
                    local best
                    for _, p in ipairs(points) do
                        local d = math.sqrt((p[1] - r.x) ^ 2 + (p[2] - r.y) ^ 2)
                        if not best or d < best then best = d end
                    end
                    if best > AUDIT_DRIFT then table.insert(groups.drift, line .. (L[" - %.1f%% from nearest database spawn"]):format(best))
                    else matched = matched + 1 end
                end
            end
        end
    end
    local lines = { (L["Journal audit: %d NPC observations; %d match the database."]):format(total, matched), "" }
    local function section(title, list)
        table.insert(lines, ("%s (%d)"):format(title, #list))
        for _, line in ipairs(list) do table.insert(lines, "  " .. line) end
        table.insert(lines, "")
    end
    section(L["NPCs not in the database (Forever-only)"], groups.new)
    section(L["Known NPCs seen on a new map"], groups.map)
    section(L["Possible coordinate drift"], groups.drift)
    table.insert(lines, L["Confirm findings in the Review journal, then run tools\\monstrator-db.cjs harvest and overlay to add them to the database."])
    self:ShowCopy(table.concat(lines, "\n"))
    return groups, matched, total
end
