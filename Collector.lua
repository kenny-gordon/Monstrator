local _, M = ...
local L = M.L

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

function M:AddObservation(record)
    local valid, reason = self:ValidateRecord(record)
    if not valid then self:Error(reason); return nil end
    local count = 0
    for _, existing in pairs(self.observations.entries) do
        count = count + 1
        local existingValid = self:ValidateRecord(existing)
        if existingValid and existing.verification == "pending" and existing.npcID == record.npcID
            and existing.kind == record.kind and existing.name == record.name
            and existing.mapID == record.mapID
            and math.abs(existing.x - record.x) < 0.05 and math.abs(existing.y - record.y) < 0.05 then
            existing.lastSeen = record.lastSeen
            existing.sightings = (existing.sightings or 1) + 1
            if existing.category == "Combat" and record.category ~= "Combat" then existing.category = record.category end
            for _, key in ipairs({ "level", "reaction", "creatureType", "classification" }) do
                if record[key] ~= nil then existing[key] = record[key] end
            end
            for _, tag in ipairs(record.tags) do
                local found = false
                for _, savedTag in ipairs(existing.tags) do if tag == savedTag then found = true end end
                if not found then table.insert(existing.tags, tag) end
            end
            self:RefreshIfVisible()
            return existing
        end
    end
    if count >= self.settings.observationLimit then
        if not self.fullNotice then
            self.fullNotice = true
            self:Notice(L["Journal full. New capture paused; review/delete records or increase /monstrator limit."])
        end
        return nil
    end
    while self.observations.entries["local:" .. self.observations.nextID] do
        self.observations.nextID = self.observations.nextID + 1
    end
    record.key = "local:" .. self.observations.nextID
    self.observations.nextID = self.observations.nextID + 1
    self.observations.entries[record.key] = record
    self:RefreshIfVisible()
    return record
end

function M:NewObservation(name, kind, category, tags, evidence)
    local mapID, x, y = self:PlayerPosition()
    if not mapID then self:Error(L["Position unavailable; observation not recorded."]); return end
    local _, build = GetBuildInfo()
    return {
        key = "pending", name = name, kind = kind, category = category,
        tags = tags, mapID = mapID, x = x, y = y,
        build = tostring(build), locale = GetLocale(), source = "local:" .. evidence,
        verification = "pending", precision = "encounter", lastSeen = time(), sightings = 1,
    }
end

function M:CaptureNPC(event, unit)
    local manual = event == "manual-target"
    local discovery = event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT"
    if not self.ready or (discovery and not self.settings.discovering)
        or (not manual and not discovery and not self.settings.collecting) then return end
    unit = unit or (manual and "target" or "npc")
    local guid, name = UnitGUID(unit), UnitName(unit)
    if not readable(guid) or not readable(name) then
        self:Debug("Restricted NPC identity; capture skipped."); return
    end
    if type(guid) ~= "string" or type(name) ~= "string" then
        if manual then self:Error(L["Select an NPC target before capturing."]); return end
        self:Debug("No NPC identity during " .. event); return
    end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        if manual then self:Error(L["Only NPC targets can be captured; players are never recorded."]) end
        return
    end
    npcID = tonumber(npcID)
    if not npcID then self:Error(L["Could not parse NPC identity."]); return end
    if discovery then
        local now = GetTime()
        if not self.discoveryWindow or now - self.discoveryWindow >= 30 then
            self.discoveryWindow, self.discoverySeen = now, {}
        end
        if self.discoverySeen[guid] then return end
    end
    local category, tags = (manual or discovery) and "Combat" or "Services", {}
    if event == "MERCHANT_SHOW" then
        category, tags = "Vendors", { "vendor" }
        local repair = CanMerchantRepair and CanMerchantRepair()
        if readable(repair) and repair then table.insert(tags, "repair") end
    elseif event == "TRAINER_SHOW" then category, tags = "Trainers", { "trainer" }
    elseif event == "TAXIMAP_OPENED" then category, tags = "Transit", { "flight" }
    end
    local record = self:NewObservation(name, "npc", category, tags, event)
    if record then
        record.npcID = npcID
        local fields = {
            level = UnitLevel and UnitLevel(unit),
            reaction = UnitReaction and UnitReaction(unit, "player"),
            creatureType = UnitCreatureType and UnitCreatureType(unit),
            classification = UnitClassification and UnitClassification(unit),
        }
        for key, value in pairs(fields) do
            if readable(value) and ((key == "level" and self:IsFinite(value) and value >= -1 and value % 1 == 0)
                or (key == "reaction" and self:IsFinite(value) and value >= 1 and value <= 8 and value % 1 == 0)
                or ((key == "creatureType" or key == "classification") and type(value) == "string")) then
                record[key] = value
            end
        end
        local saved = self:AddObservation(record)
        if saved and discovery then self.discoverySeen[guid] = true end
        if saved and manual then self:Notice(L["NPC target saved for review: "] .. name .. " (player encounter position).") end
    end
end

function M:CaptureLandmark(name)
    if type(name) ~= "string" or name:match("^%s*$") then
        self:Error(L["Use /monstrator landmark NAME at the landmark's position."]); return
    end
    local record = self:NewObservation(name, "location", "Landmarks", { "landmark" }, "manual-landmark")
    if record then
        local saved = self:AddObservation(record)
        if saved then self:Notice(L["Landmark saved for review: "] .. name) end
    end
end

function M:ParseTags(text)
    if type(text) ~= "string" then return nil, "Tags must be comma/space-separated text." end
    local tags, seen = {}, {}
    for tag in string.lower(text):gmatch("[^,%s]+") do
        if not self.tags[tag] then return nil, "Unknown tag '" .. tag .. "'. See DATA_SCHEMA.md or /monstrator tags." end
        if not seen[tag] then table.insert(tags, tag); seen[tag] = true end
    end
    return tags
end

function M:Review(record, action, x, y, category, tagText)
    if self.observations.entries[record.key] ~= record then
        self:Error(L["This record is not in your journal."]); return false
    end
    if action == "reject" then
        self.observations.entries[record.key] = nil
        self.fullNotice = nil
    elseif action == "accept" then
        if record.verification ~= "pending" and record.verification ~= "user-confirmed" then
            self:Error(L["Only local observations can be edited."]); return false
        end
        if not self:IsFinite(x) or not self:IsFinite(y) or x < 0 or x > 100 or y < 0 or y > 100 then
            self:Error(L["Review coordinates must be finite percentages from 0 to 100."]); return false
        end
        local validCategory = false
        for _, value in ipairs(self.categories[record.kind]) do
            if value == category and value ~= "All" then validCategory = true end
        end
        if not validCategory then self:Error(L["Invalid review category."]); return false end
        local tags, reason = self:ParseTags(tagText or table.concat(record.tags, ","))
        if not tags then self:Error(reason); return false end
        local alreadyIndexed = self.index and self.index.byKey[record.key] ~= nil
        record.x, record.y, record.category = x, y, category
        record.tags = tags
        record.verification = "user-confirmed"
        record.precision = "confirmed"
        if not self.index or alreadyIndexed then self:BuildIndex() else self:IndexRecord(record) end
        self:Notice(L["User-confirmed placement saved. This does not independently verify a static spawn."])
    else self:Error(L["Unknown review action."]); return false end
    if action == "reject" then self:BuildIndex() end
    self:RefreshIfVisible()
    return true
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "TRAINER_SHOW", "GOSSIP_SHOW", "TAXIMAP_OPENED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event)
    M:CaptureNPC(event, event == "PLAYER_TARGET_CHANGED" and "target"
        or (event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "npc"))
end)

function M:ExportText()
    local lines = { "-- Monstrator local observations; approximate until reviewed.", "return {" }
    local keys = {}
    for key in pairs(self.observations.entries) do table.insert(keys, key) end
    table.sort(keys)
    local fields = { "key", "npcID", "name", "kind", "category", "mapID", "x", "y",
        "source", "build", "locale", "verification", "precision", "lastSeen", "sightings", "faction",
        "level", "reaction", "creatureType", "classification" }
    for _, key in ipairs(keys) do
        local record = self.observations.entries[key]
        local valid, reason = self:ValidateRecord(record)
        if not valid then
            self:Error(L["Cannot export invalid record "] .. key .. ": " .. reason .. ". No export produced.")
            return nil
        end
        table.insert(lines, "  {")
        for _, field in ipairs(fields) do
            local value = record[field]
            if type(value) == "string" then table.insert(lines, ("    %s = %q,"):format(field, value))
            elseif type(value) == "number" and self:IsFinite(value) then
                table.insert(lines, ("    %s = %.17g,"):format(field, value))
            end
        end
        local tags = {}
        for _, tag in ipairs(record.tags or {}) do table.insert(tags, string.format("%q", tag)) end
        table.insert(lines, "    tags = {" .. table.concat(tags, ", ") .. "},")
        table.insert(lines, "  },")
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end
