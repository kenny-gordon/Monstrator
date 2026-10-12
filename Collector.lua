local _, M = ...
local L = M.L

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

-- The <Warrior Trainer> style subtitle is only exposed through the unit tooltip: it is the line after the name,
-- unless that line is already the level line ("Level 10 Humanoid") or the unit belongs to a player.
local scanTooltip
local function levelPrefix()
    local template = type(TOOLTIP_UNIT_LEVEL) == "string" and TOOLTIP_UNIT_LEVEL or "Level %s"
    local prefix = template:match("^(.-)%%")
    return prefix and prefix:match("^%s*(.-)%s*$") or ""
end

local function tooltipLine(unit)
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        local line = ok and type(data) == "table" and type(data.lines) == "table" and data.lines[2]
        return line and line.leftText
    end
    if not CreateFrame then return end
    local ok, text = pcall(function()
        scanTooltip = scanTooltip or CreateFrame("GameTooltip", "MonstratorUnitScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTooltip:ClearLines()
        scanTooltip:SetUnit(unit)
        local line = _G["MonstratorUnitScanTooltipTextLeft2"]
        local value = line and line:GetText()
        scanTooltip:Hide()
        return value
    end)
    return ok and text or nil
end

function M:UnitTitle(unit)
    if UnitIsPlayer and UnitIsPlayer(unit) == true then return end
    local controlled = UnitPlayerControlled and UnitPlayerControlled(unit)
    if readable(controlled) and controlled == true then return end
    local text = tooltipLine(unit)
    if not readable(text) or type(text) ~= "string" then return end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*<?%s*(.-)%s*>?%s*$")
    if text == "" or #text > 64 then return end
    local prefix = levelPrefix()
    if prefix ~= "" and text:sub(1, #prefix) == prefix then return end
    if type(LEVEL) == "string" and LEVEL ~= "" and text:find(LEVEL, 1, true) then return end
    if text:find("^%d") or text:find("??", 1, true) then return end
    return text
end

-- Applies a subtitle the client showed for this NPC: the database derives categories and sub-groups (class or
-- profession trainer, food vendor, flight master) from the same text, so journal entries group the same way.
function M:ApplyObservedTitle(record, title)
    if type(title) ~= "string" or title == "" then return false end
    local changed = record.title ~= title
    record.title = title
    -- The tooltip shows no NPC flags, so a "<... Trainer>" subtitle stands in for the trainer flag.
    local inferred = title:lower():find("trainer", 1, true) and self.npcFlags and self.npcFlags.TRAINER or 0
    local category, tags = self:NPCIdentity(inferred, title)
    if category ~= "Combat" and (record.category == "Unclassified" or record.category == "Combat") then
        changed = changed or record.category ~= category
        record.category = category
    end
    for _, tag in ipairs(tags) do
        local found = false
        for _, saved in ipairs(record.tags) do if saved == tag then found = true end end
        if not found then table.insert(record.tags, tag); changed = true end
    end
    return changed
end

-- Gives every journal record of this NPC the subtitle seen now. Confirmed records keep a valid seal only if
-- they were intact beforehand, so an edited record stays detectably broken.
function M:BackfillTitle(npcID, title, onlyMissing)
    if not npcID or type(title) ~= "string" then return 0 end
    local count = 0
    for _, existing in pairs(self.observations.entries) do
        if existing.kind == "npc" and existing.npcID == npcID and existing.title ~= title
            and (not onlyMissing or existing.title == nil) and type(existing.tags) == "table" then
            local intact = self:RecordSealValid(existing)
            if self:ApplyObservedTitle(existing, title) then
                count = count + 1
                if intact then self:SealRecord(existing) end
            end
        end
    end
    if count > 0 then self:RefreshIfVisible() end
    return count
end

function M:AddObservation(record)
    local valid, reason = self:ValidateRecord(record)
    if not valid then self:Error(reason); return nil end
    local count = 0
    local radius = record.kind == "npc" and self.encounterRadius or 0.05
    local function near(existing)
        return existing.npcID == record.npcID and existing.kind == record.kind and existing.mapID == record.mapID
            and (record.kind == "npc" or existing.name == record.name)
            and math.sqrt((existing.x - record.x) ^ 2 + (existing.y - record.y) ^ 2) < radius
    end
    local function addsDetail(existing)
        if record.title ~= nil and existing.title ~= record.title then return true end
        for _, tag in ipairs(record.tags) do
            local found = false
            for _, savedTag in ipairs(existing.tags or {}) do if tag == savedTag then found = true end end
            if not found then return true end
        end
    end
    for _, existing in pairs(self.observations.entries) do
        count = count + 1
        local existingValid = self:ValidateRecord(existing)
        if existingValid and existing.verification ~= "pending" and existing.verification ~= "rejected"
            and near(existing) and not addsDetail(existing) then
            -- Already reviewed at this placement; another sighting adds nothing.
            return existing
        end
        if existingValid and existing.verification == "pending" and near(existing) then
            -- Only reseal intact records; an edited SavedVariables entry must stay detectably broken.
            local intact = self:RecordSealValid(existing)
            existing.lastSeen = record.lastSeen
            existing.sightings = (existing.sightings or 1) + 1
            if (existing.category == "Unclassified" or existing.category == "Combat")
                and record.category ~= "Unclassified" and record.category ~= "Combat" then
                existing.category = record.category
            end
            for _, key in ipairs({ "level", "reaction", "observer", "creatureType", "classification", "title", "faction" }) do
                if record[key] ~= nil then existing[key] = record[key] end
            end
            for _, tag in ipairs(record.tags) do
                local found = false
                for _, savedTag in ipairs(existing.tags) do if tag == savedTag then found = true end end
                if not found then table.insert(existing.tags, tag) end
            end
            if intact then self:SealRecord(existing) end
            self:NoteJournalEvidence(existing)
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
    self:NormalizeJournalIdentity(record)
    self:SealRecord(record)
    self.observations.entries[record.key] = record
    self:NoteJournalEvidence(record)
    self:RefreshIfVisible()
    return record
end

-- New services or a subtitle seen for an NPC change how its database rows are filed; rebuild lazily.
function M:NoteJournalEvidence(record)
    if self.npcEvidence and self:NoteNPCEvidence(record) then
        wipe(self.dbCache)
        self.indexStale = true
    end
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

-- Journal records captured before subtitles were recorded take the database's subtitle for the same NPC ID.
function M:BackfillTitlesFromDatabase()
    local lib = self.native and self:NativeProvider()
    local provider = lib and lib.Npc
    if not provider or type(provider.subName) ~= "function" then return 0 end
    local titles, count = {}, 0
    for _, record in pairs(self.observations.entries) do
        if record.kind == "npc" and record.title == nil and self:IsFinite(record.npcID) then
            titles[record.npcID] = titles[record.npcID] or self.ReadNativeField(provider.subName, record.npcID) or false
        end
    end
    for npcID, title in pairs(titles) do
        if type(title) == "string" and title ~= "" then count = count + self:BackfillTitle(npcID, title, true) end
    end
    return count
end

-- Removes journal records that add nothing to the database: non-directory creatures, sightings that match a
-- database placement, and repeat sightings of a kept record. Returns counts by reason; apply=true deletes.
function M:PruneJournal(apply)
    local lib = self.native and self:NativeProvider()
    if not (lib and lib.Npc) then return nil, L["The database is still loading; try again in a moment."] end
    local counts, removed, keys = { noise = 0, known = 0, duplicate = 0, kept = 0 }, {}, {}
    for key, record in pairs(self.observations.entries) do
        if record.kind == "npc" then table.insert(keys, key) end
    end
    local function rank(record) return record.verification == "user-confirmed" and 0 or 1 end
    table.sort(keys, function(a, b)
        local ra, rb = self.observations.entries[a], self.observations.entries[b]
        if rank(ra) ~= rank(rb) then return rank(ra) < rank(rb) end
        local na, nb = tonumber(a:match("%d+$")) or 0, tonumber(b:match("%d+$")) or 0
        if na ~= nb then return na < nb end
        return a < b
    end)
    local keptByPlacement = {}
    for _, key in ipairs(keys) do
        local record, reason = self.observations.entries[key]
        if not self:ValidateRecord(record) then reason = nil
        elseif self:IsNoiseRecord(record) then reason = "noise"
        elseif not self:ObservationNovelty(record) then reason = "known"
        else
            local bucket = record.npcID .. ":" .. record.mapID
            keptByPlacement[bucket] = keptByPlacement[bucket] or {}
            for _, kept in ipairs(keptByPlacement[bucket]) do
                if math.sqrt((kept.x - record.x) ^ 2 + (kept.y - record.y) ^ 2) < self.encounterRadius
                    and (record.title == nil or record.title == kept.title) then
                    local extra = false
                    for _, tag in ipairs(record.tags) do
                        local found = false
                        for _, savedTag in ipairs(kept.tags) do if tag == savedTag then found = true end end
                        if not found then extra = true end
                    end
                    if not extra then reason = "duplicate"; break end
                end
            end
            if not reason then table.insert(keptByPlacement[bucket], record) end
        end
        if reason then
            counts[reason] = counts[reason] + 1
            removed[#removed + 1] = key
        else counts.kept = counts.kept + 1 end
    end
    if apply then
        for _, key in ipairs(removed) do self.observations.entries[key] = nil end
        self.fullNotice = nil
        self:BuildIndex()
        self:RefreshIfVisible()
    end
    return counts, #removed
end

function M:PruneCommand(argument)
    local apply = argument == "CONFIRM"
    local counts, total = self:PruneJournal(apply)
    if not counts then self:Error(total); return end
    local summary = (L["%d non-directory creatures, %d already in the database, %d repeat sightings; %d NPC records kept."])
        :format(counts.noise, counts.known, counts.duplicate, counts.kept)
    if apply then self:Notice((L["Journal pruned: removed %d records. "]):format(total) .. summary)
    else self:Notice((L["Prune would remove %d records: "]):format(total) .. summary .. L[" Use /monstrator prune CONFIRM to apply."]) end
end

-- NPC interaction windows -> the category and service tags the database derives from the matching npcFlags bit.
M.serviceEvents = {
    TRAINER_SHOW = { "Trainers", { "trainer" } },
    TAXIMAP_OPENED = { "Transit", { "flight" } },
    BANKFRAME_OPENED = { "Services", { "bank" } },
    PET_STABLE_SHOW = { "Services", { "stable" } },
    AUCTION_HOUSE_SHOW = { "Services", { "auction" } },
    PETITION_VENDOR_SHOW = { "Services", { "guild" } },
    OPEN_TABARD_FRAME = { "Services", { "tabard" } },
    CONFIRM_BINDER = { "Services", { "innkeeper" } },
    QUEST_GREETING = { "Services", { "quest_giver" } },
    QUEST_DETAIL = { "Services", { "quest_giver" } },
    QUEST_PROGRESS = { "Services", { "quest_giver" } },
    QUEST_COMPLETE = { "Services", { "quest_giver" } },
}

-- The database's friendlyToFaction: faction-aligned NPCs report their group; unaligned NPCs the player may not
-- attack and that are at least neutral serve both factions. Hostile creatures have no faction.
function M:UnitFriendlyFaction(unit)
    if UnitIsPlayer and UnitIsPlayer(unit) == true then return end
    local group = UnitFactionGroup and UnitFactionGroup(unit)
    if readable(group) and (group == "Alliance" or group == "Horde") then return group end
    local reaction = UnitReaction and UnitReaction(unit, "player")
    local attackable = UnitCanAttack and UnitCanAttack("player", unit)
    if readable(reaction) and readable(attackable) and type(reaction) == "number" and reaction >= 4
        and attackable == false then return "Both" end
end

-- Creatures that are never directory entries: player companions, ambient wildlife and summoned totems.
-- enUS names; other locales fall back to the player-controlled check and the database novelty test.
M.nonDirectoryTypes = { ["Critter"] = true, ["Non-combat Pet"] = true, ["Wild Pet"] = true, ["Totem"] = true,
    ["Gas Cloud"] = true }
-- Untyped creatures that are not hostile and offer no service are world props (crates, braziers, wardrobes);
-- hostile untyped creatures (oozes, swarms, elementals) are real encounters.
M.propCreatureTypes = { ["Not specified"] = true }
function M:IsPropRecord(record)
    return record.kind == "npc" and type(record.creatureType) == "string"
        and self.propCreatureTypes[record.creatureType] == true
        and self:IsFinite(record.reaction) and record.reaction >= 4
        and (type(record.tags) ~= "table" or next(record.tags) == nil)
end
-- Encounter positions are where the player stood, so sightings closer than this are the same placement.
M.encounterRadius = 5
local SERVICE_FLAGS = { vendor = "VENDOR", repair = "REPAIR", flight = "FLIGHT_MASTER", trainer = "TRAINER",
    innkeeper = "INNKEEPER", bank = "BANKER", auction = "AUCTIONEER", stable = "STABLEMASTER", guild = "PETITIONER",
    tabard = "TABARD_DESIGNER", quest_giver = "QUEST_GIVER" }

function M:IsDirectoryUnit(unit)
    local controlled = UnitPlayerControlled and UnitPlayerControlled(unit)
    if readable(controlled) and controlled == true then return false end
    local otherPet = UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)
    if readable(otherPet) and otherPet == true then return false end
    local creatureType = UnitCreatureType and UnitCreatureType(unit)
    if readable(creatureType) and self.nonDirectoryTypes[creatureType] then return false end
    return true
end

-- Journal records that are not directory material: noise creature types, uncached names, and non-humanoid known
-- IDs under a different name (player-named pets and summons share their template's NPC ID).
function M:IsNoiseRecord(record)
    if record.kind ~= "npc" then return false end
    if record.name == "Unknown" or record.name == UNKNOWNOBJECT then return true end
    if type(record.creatureType) == "string" and self.nonDirectoryTypes[record.creatureType] then return true end
    if self:IsPropRecord(record) then return true end
    local lib = self.native and self:NativeProvider()
    local npc = lib and lib.Npc
    if npc and npc.Has(record.npcID) and record.creatureType ~= "Humanoid" then
        local known = self.ReadNativeField(npc.name, record.npcID)
        if type(known) == "string" and known ~= "" and known ~= record.name then return true end
    end
    return false
end

-- Why an NPC observation adds something the database does not already have, or nil when it matches.
function M:ObservationNovelty(record)
    if record.kind ~= "npc" then return "location" end
    local lib = self.native and self:NativeProvider()
    local npc = lib and lib.Npc
    if not npc or not npc.Has(record.npcID) then return "new" end
    local read = self.ReadNativeField
    local points = (read(npc.spawns, record.npcID) or {})[record.mapID]
    if type(points) ~= "table" or #points == 0 then return "map" end
    local best
    for _, p in ipairs(points) do
        local d = math.sqrt((p[1] - record.x) ^ 2 + (p[2] - record.y) ^ 2)
        if not best or d < best then best = d end
    end
    if best > self.encounterRadius then return "position" end
    if type(record.title) == "string" and read(npc.subName, record.npcID) ~= record.title then return "title" end
    if self:IsFinite(record.level) and record.level > 0 then
        local minLevel, maxLevel = read(npc.minLevel, record.npcID), read(npc.maxLevel, record.npcID)
        if self:IsFinite(minLevel) and self:IsFinite(maxLevel) and (record.level < minLevel or record.level > maxLevel) then
            return "level"
        end
    end
    local npcFlags = read(npc.npcFlags, record.npcID) or 0
    for _, tag in ipairs(record.tags or {}) do
        local bit = SERVICE_FLAGS[tag] and self.npcFlags[SERVICE_FLAGS[tag]]
        if bit and npcFlags % (bit * 2) < bit then return "service" end
    end
end

function M:CaptureNPC(event, unit)
    local manual = event == "manual-target"
    local discovery = event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT"
        or event == "NAME_PLATE_UNIT_ADDED"
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
    -- The client reports this placeholder until the creature's name is cached.
    if name == "Unknown" or name == UNKNOWNOBJECT then self:Debug("Uncached NPC name; capture skipped."); return end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then
        if manual then self:Error(L["Only NPC targets can be captured; players are never recorded."]) end
        return
    end
    npcID = tonumber(npcID)
    if not npcID then self:Error(L["Could not parse NPC identity."]); return end
    if not manual and not self:IsDirectoryUnit(unit) then return end
    if discovery then
        local now = GetTime()
        if not self.discoveryWindow or now - self.discoveryWindow >= 30 then
            self.discoveryWindow, self.discoverySeen = now, {}
        end
        if self.discoverySeen[guid] then return end
    end
    local category, tags = "Unclassified", {}
    if manual or discovery then
        local attackable = UnitCanAttack and UnitCanAttack("player", unit)
        if readable(attackable) and attackable == true then category = "Combat" end
    end
    if event == "MERCHANT_SHOW" then
        category, tags = "Vendors", { "vendor" }
        local repair = CanMerchantRepair and CanMerchantRepair()
        if readable(repair) and repair then table.insert(tags, "repair") end
    elseif M.serviceEvents[event] then
        local service = M.serviceEvents[event]
        category, tags = service[1], {}
        for i, tag in ipairs(service[2]) do tags[i] = tag end
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
        record.faction = self:UnitFriendlyFaction(unit)
        -- The reaction is relative to this character; its faction says which side the reaction speaks for.
        local observer = UnitFactionGroup and UnitFactionGroup("player")
        if record.reaction and readable(observer) and (observer == "Alliance" or observer == "Horde") then
            record.observer = observer
        end
        if self:IsPropRecord(record) then
            if manual then self:Notice(L["Not a directory NPC (world prop); nothing recorded: "] .. name) end
            return
        end
        local title = self:UnitTitle(unit)
        self:ApplyObservedTitle(record, title)
        if title then self:BackfillTitle(npcID, title) end
        -- Sightings that only repeat what the database already says are not journal material.
        if not self:ObservationNovelty(record) then
            if discovery then self.discoverySeen[guid] = true end
            if manual then self:Notice(L["Already in the database at this position; nothing new to record: "] .. name) end
            return
        end
        local saved = self:AddObservation(record)
        if saved and discovery then self.discoverySeen[guid] = true end
        if saved and manual then self:Notice(L["NPC target saved for review: "] .. name .. " (player encounter position).") end
    end
end

local function boundedText(value, limit)
    if readable(value) and type(value) == "string" and #value <= limit and not value:match("^%s*$") then
        return value
    end
end

local function boundedNumber(value, minimum, maximum)
    if readable(value) and M:IsFinite(value) and value >= minimum and value <= maximum and value % 1 == 0 then
        return value
    end
end

function M:CaptureTrainerServices()
    if not self.ready or not self.settings.collecting then return end
    local countFn, infoFn = GetNumTrainerServices, GetTrainerServiceInfo
    if type(countFn) ~= "function" or type(infoFn) ~= "function" then
        self:Error(L["Trainer service data is unavailable on this client."])
        return
    end
    local guid, name = UnitGUID("npc"), UnitName("npc")
    if not readable(guid) or not readable(name) or type(guid) ~= "string" or type(name) ~= "string" then
        self:Debug("Trainer identity unavailable; trainer services were not saved.")
        return
    end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    npcID = tonumber(npcID)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not npcID then
        self:Debug("Trainer identity was not an NPC; trainer services were not saved.")
        return
    end
    local count = boundedNumber(countFn(), 0, 200)
    if not count then
        self:Error(L["Trainer service list exceeded the capture limit."])
        return
    end
    local services = {}
    -- Classic returns name, subText, type, isExpanded and exposes the level separately;
    -- the mainline client returns name, type, texture, reqLevel.
    local levelFn = GetTrainerServiceLevelReq
    local classic = type(levelFn) == "function"
    -- Classic clients omit or blank individual requirement fields for some services; an unreadable field is left
    -- out of the snapshot rather than discarding every service the trainer offers.
    local function call(fn, ...)
        if type(fn) ~= "function" then return end
        local ok, a, b, c, d, e = pcall(fn, ...)
        if ok then return a, b, c, d, e end
    end
    local skipped = 0
    for index = 1, count do
        local serviceName, serviceType, requiredLevel, subText
        if classic then
            serviceName, subText, serviceType = call(infoFn, index)
            if readable(serviceType) and serviceType ~= "header" then requiredLevel = call(levelFn, index) end
        else
            local _
            serviceName, serviceType, _, requiredLevel, subText = call(infoFn, index)
        end
        serviceName = boundedText(serviceName, 200)
        if not serviceName then
            skipped = skipped + 1
        else
            local service = { name = serviceName }
            service.serviceType = type(serviceType) == "string" and boundedText(serviceType, 40) or nil
            service.subText = type(subText) == "string" and boundedText(subText, 200) or nil
            service.requiredLevel = boundedNumber(requiredLevel, 0, 255)
            if service.serviceType ~= "header" then
                local skill, rank = call(GetTrainerServiceSkillReq, index)
                skill, rank = boundedText(skill, 100), boundedNumber(rank, 0, 100000)
                if skill and rank then service.skill, service.skillRank = skill, rank end
                local abilityCount = boundedNumber(call(GetTrainerServiceNumAbilityReq, index), 0, 20) or 0
                service.abilities = {}
                for abilityIndex = 1, abilityCount do
                    local ability = boundedText(call(GetTrainerServiceAbilityReq, index, abilityIndex), 100)
                    if ability then table.insert(service.abilities, ability) end
                end
                service.cost = boundedNumber(call(GetTrainerServiceCost, index), 0, 2000000000)
            end
            table.insert(services, service)
        end
    end
    if skipped > 0 then self:Debug(("Trainer capture skipped %d unnamed service line(s)."):format(skipped)) end
    if #services == 0 then
        self:Debug("Trainer window listed no readable services; nothing saved.")
        return
    end
    local _, build = GetBuildInfo()
    local characterClass = UnitClass and boundedText(UnitClass("player"), 100)
    local characterLevel = UnitLevel and boundedNumber(UnitLevel("player"), 1, 255)
    self.trainerSnapshots[npcID] = {
        npcID = npcID, name = name, observedAt = time(), build = tostring(build),
        locale = GetLocale(), characterClass = characterClass, characterLevel = characterLevel,
        services = services,
    }
    self.indexStale = true
    self:Notice(L["Trainer services saved locally for "] .. name .. ".")
    self:RefreshIfVisible()
end

function M:TrainerSnapshotLines(npcID)
    local snapshot = self.trainerSnapshots and self.trainerSnapshots[npcID]
    if snapshot == nil then return {} end
    if type(snapshot) ~= "table" or snapshot.npcID ~= npcID or type(snapshot.services) ~= "table"
        or not boundedNumber(snapshot.observedAt, 0, 2000000000)
        or not boundedText(snapshot.build, 100) or not boundedText(snapshot.name, 200)
        or (snapshot.characterClass ~= nil and not boundedText(snapshot.characterClass, 100))
        or (snapshot.characterLevel ~= nil and not boundedNumber(snapshot.characterLevel, 1, 255)) then
        self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
        return {}
    end
    local count = 0
    for key in pairs(snapshot.services) do
        if not self:IsFinite(key) or key < 1 or key > 200 or key % 1 ~= 0 then
            self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
            return {}
        end
        count = count + 1
    end
    if count > 200 then
        self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
        return {}
    end
    for index = 1, count do
        local service = snapshot.services[index]
        if type(service) ~= "table" or not boundedText(service.name, 200)
            or (service.serviceType ~= nil and not boundedText(service.serviceType, 40))
            or (service.subText ~= nil and not boundedText(service.subText, 200))
            or (service.requiredLevel ~= nil and not boundedNumber(service.requiredLevel, 0, 255))
            or (service.skill ~= nil and not boundedText(service.skill, 100))
            or (service.skillRank ~= nil and not boundedNumber(service.skillRank, 0, 100000))
            or (service.cost ~= nil and not boundedNumber(service.cost, 0, 2000000000))
            or (service.abilities ~= nil and type(service.abilities) ~= "table") then
            self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
            return {}
        end
        local abilityCount = 0
        for key, ability in pairs(service.abilities or {}) do
            if not self:IsFinite(key) or key < 1 or key > 20 or key % 1 ~= 0
                or not boundedText(ability, 100) then
                self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
                return {}
            end
            abilityCount = abilityCount + 1
        end
        if abilityCount > 20 then
            self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
            return {}
        end
        for abilityIndex = 1, abilityCount do
            if not boundedText(service.abilities[abilityIndex], 100) then
                self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
                return {}
            end
        end
    end
    local lines = {
        L["Trainer services observed %s (build %s; character-specific: %s, level %s)."]:format(
            date("%Y-%m-%d", snapshot.observedAt), snapshot.build,
            snapshot.characterClass or L["unknown"], tostring(snapshot.characterLevel or L["unknown"])),
        L["The client may hide services by class, level, skill or trainer state."],
    }
    if count == 0 then
        table.insert(lines, L["No services were listed by the trainer UI."])
        return lines
    end
    for index = 1, math.min(count, 30) do
        local service = snapshot.services[index]
        if type(service) ~= "table" or boundedText(service.name, 200) == nil then
            self:Error(L["Invalid saved trainer snapshot; it was not displayed."])
            return {}
        end
        local details = { "- " .. service.name }
        if boundedText(service.serviceType, 40) then
            table.insert(details, L["Availability: %s"]:format(service.serviceType))
        end
        if boundedText(service.subText, 200) then table.insert(details, service.subText) end
        if boundedNumber(service.requiredLevel, 0, 255) and service.requiredLevel > 1 then
            table.insert(details, L["Required level: %d"]:format(service.requiredLevel))
        end
        if boundedText(service.skill, 100) and boundedNumber(service.skillRank, 0, 100000) then
            table.insert(details, L["Required skill: %s %d"]:format(service.skill, service.skillRank))
        end
        if boundedNumber(service.cost, 0, 2000000000) then
            table.insert(details, L["Cost: %d copper"]:format(service.cost))
        end
        if type(service.abilities) == "table" then
            for _, ability in ipairs(service.abilities) do
                ability = boundedText(ability, 100)
                if ability then table.insert(details, L["Required ability: %s"]:format(ability)) end
            end
        end
        table.insert(lines, table.concat(details, " | "))
    end
    if count > 30 then table.insert(lines, L["%d additional services not shown."]:format(count - 30)) end
    return lines
end

-- Relationships the database stores alongside NPCs: quest starters/finishers, vendor stock and loot drops.
-- Kept by ID in Monstrator_Observations.relations and folded into Quest/Item rows by `monstrator-db.cjs harvest`.
local RELATION_LIMIT = 20000
-- Skinning and Pick Pocket loot comes from a creature but is not that creature's drop table.
local NON_DROP_SPELLS = { [8613] = true, [8617] = true, [8618] = true, [10768] = true, [921] = true }

function M:Relations()
    local relations = self.observations.relations
    if type(relations) ~= "table" then relations = {}; self.observations.relations = relations end
    for _, key in ipairs({ "quests", "items" }) do
        if type(relations[key]) ~= "table" then relations[key] = {} end
    end
    if not self:IsFinite(relations.size) or relations.size < 0 then
        local size = 0
        for _, key in ipairs({ "quests", "items" }) do for _ in pairs(relations[key]) do size = size + 1 end end
        relations.size = size
    end
    return relations
end

function M.GUIDIdentity(guid)
    if not readable(guid) or type(guid) ~= "string" then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if not id or id <= 0 or id % 1 ~= 0 then return end
    if kind == "Creature" or kind == "Vehicle" then return "npc", id end
    if kind == "GameObject" then return "object", id end
end

-- Records that `ref` belongs in list `field` of quest/item `id`; returns true when it was new.
function M:NoteRelation(bucket, id, name, field, ref)
    if not self.settings.collecting or not self:IsFinite(id) or id <= 0 or id % 1 ~= 0
        or not self:IsFinite(ref) or ref <= 0 then return false end
    local relations = self:Relations()
    local entry = relations[bucket][id]
    if type(entry) ~= "table" then
        if relations.size >= RELATION_LIMIT then return false end
        entry = {}
        relations[bucket][id] = entry
        relations.size = relations.size + 1
    end
    if readable(name) and type(name) == "string" and name ~= "" and #name <= 120 then entry.name = name end
    if type(entry[field]) ~= "table" then entry[field] = {} end
    local new = entry[field][ref] == nil
    entry[field][ref] = time()
    return new
end

function M:CaptureQuestRelation(event)
    local questID = GetQuestID and GetQuestID()
    if not readable(questID) or not self:IsFinite(questID) or questID <= 0 then return end
    local kind, id = self.GUIDIdentity(UnitGUID("npc"))
    if not kind then return end
    local title = GetTitleText and GetTitleText()
    local starts = event == "QUEST_DETAIL"
    local field = (starts and "starter" or "finisher") .. (kind == "npc" and "Npcs" or "Objects")
    return self:NoteRelation("quests", questID, title, field, id)
end

local function linkItemID(link)
    return readable(link) and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

function M:CaptureVendorStock(guid)
    local kind, npcID = self.GUIDIdentity(guid)
    if kind ~= "npc" or not GetMerchantNumItems then return 0 end
    local total, count = GetMerchantNumItems(), 0
    if not readable(total) or not self:IsFinite(total) then return 0 end
    for slot = 1, math.min(total, 200) do
        local itemID = GetMerchantItemID and GetMerchantItemID(slot)
        if not readable(itemID) or type(itemID) ~= "number" then
            itemID = linkItemID(GetMerchantItemLink and GetMerchantItemLink(slot))
        end
        local name = GetMerchantItemInfo and GetMerchantItemInfo(slot)
        if itemID and self:NoteRelation("items", itemID, name, "vendors", npcID) then count = count + 1 end
    end
    return count
end

function M:CaptureLoot()
    if not GetNumLootItems or not GetLootSourceInfo then return 0 end
    local fishing = IsFishingLoot and IsFishingLoot()
    if readable(fishing) and fishing then return 0 end
    local gathered = self.nonDropCast and GetTime() - self.nonDropCast < 5
    local slots, count = GetNumLootItems(), 0
    if not readable(slots) or not self:IsFinite(slots) then return 0 end
    for slot = 1, math.min(slots, 50) do
        local itemID = linkItemID(GetLootSlotLink and GetLootSlotLink(slot))
        if itemID then
            local _, name = GetLootSlotInfo(slot)
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do
                local kind, id = self.GUIDIdentity(sources[i])
                local field = kind == "npc" and not gathered and "npcDrops" or kind == "object" and "objectDrops"
                if field and self:NoteRelation("items", itemID, name, field, id) then count = count + 1 end
            end
        end
    end
    return count
end

function M:HandleCaptureEvent(event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" and NON_DROP_SPELLS[spellID] then self.nonDropCast = GetTime() end
        return
    end
    if event == "LOOT_OPENED" then
        if self.ready and self.settings.collecting then self:CaptureLoot() end
        return
    end
    self:CaptureNPC(event, unit or (event == "PLAYER_TARGET_CHANGED" and "target"
        or (event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or "npc")))
    if not self.ready or not (self.settings and self.settings.collecting) then return end
    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then self:CaptureQuestRelation(event) end
    if event == "MERCHANT_SHOW" then
        -- Merchant item data can arrive a moment after the window opens; keep the vendor's GUID from now.
        local guid = UnitGUID("npc")
        local capture = function() self:CaptureVendorStock(guid) end
        if C_Timer and C_Timer.After then C_Timer.After(0.3, capture) else capture() end
    end
    if event == "TRAINER_SHOW" then
        local capture = function() self:CaptureTrainerServices() end
        if C_Timer and C_Timer.After then C_Timer.After(0.1, capture) else capture() end
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

function M:Review(record, action, x, y, category, tagText, deferRefresh)
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
        -- Hand-moved or previously broken records are flagged so the maintainer review holds them.
        if math.abs(record.x - x) > 0.5 or math.abs(record.y - y) > 0.5
            or (record.seal ~= nil and not self:RecordSealValid(record)) then record.edited = true end
        -- A category the reviewer picked by hand outranks the one derived from flags and subtitle.
        if category ~= record.category then record.categoryLocked = true end
        record.x, record.y, record.category = x, y, category
        record.tags = tags
        record.verification = "user-confirmed"
        record.precision = "confirmed"
        self:SealRecord(record)
        if not self.index or alreadyIndexed then self:BuildIndex() else self:IndexRecord(record) end
        if not deferRefresh then
            self:Notice(L["User-confirmed placement saved. This does not independently verify a static spawn."])
        end
    else self:Error(L["Unknown review action."]); return false end
    if action == "reject" then self:BuildIndex() end
    if not deferRefresh then self:RefreshIfVisible() end
    return true
end

function M:ObservationGroupMatches(record, anchor, group)
    if group == "zone" then return record.mapID == anchor.mapID end
    if group == "type" then return record.kind == anchor.kind and record.category == anchor.category end
    return false
end

function M:PendingObservationGroupCount(anchor, group)
    local count = 0
    for _, record in pairs(self.observations.entries) do
        if record.verification == "pending" and self:ObservationGroupMatches(record, anchor, group) then
            count = count + 1
        end
    end
    return count
end

function M:BulkReview(anchor, group)
    if group ~= "zone" and group ~= "type" then
        self:Error(L["Bulk review requires grouping by zone or type."])
        return nil
    end
    if self.observations.entries[anchor.key] ~= anchor or anchor.verification ~= "pending" then
        self:Error(L["Select a pending journal entry for bulk review."])
        return nil
    end
    local records = {}
    for _, record in pairs(self.observations.entries) do
        if record.verification == "pending" and self:ObservationGroupMatches(record, anchor, group) then
            local valid, reason = self:ValidateRecord(record)
            if not valid then
                self:Error((L["Bulk review stopped; invalid record %s: %s"]):format(tostring(record.key), reason))
                return nil
            end
            table.insert(records, record)
        end
    end
    if #records == 0 then return 0 end
    for index, record in ipairs(records) do
        if not self:Review(record, "accept", record.x, record.y, record.category,
            table.concat(record.tags, ","), true) then
            self:RefreshIfVisible()
            self:Error((L["Bulk review stopped after %d entries."]):format(index - 1))
            return nil
        end
    end
    self:RefreshIfVisible()
    self:Notice((L["Bulk-confirmed %d placements in %s. Encounter positions remain approximate."])
        :format(#records, group == "zone" and self:MapName(anchor.mapID)
            or (L[anchor.category] .. " / " .. L[anchor.kind])))
    return #records
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "TRAINER_SHOW", "GOSSIP_SHOW", "TAXIMAP_OPENED",
    "BANKFRAME_OPENED", "PET_STABLE_SHOW", "AUCTION_HOUSE_SHOW", "PETITION_VENDOR_SHOW", "OPEN_TABARD_FRAME",
    "CONFIRM_BINDER", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "LOOT_OPENED",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    -- Not every event exists in every client build.
    pcall(frame.RegisterEvent, frame, event)
end
pcall(frame.RegisterUnitEvent or frame.RegisterEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", "player")
frame:SetScript("OnEvent", function(_, event, ...)
    -- Only these events carry a unit token; other payloads (e.g. QUEST_DETAIL's item ID) are not units.
    if event == "NAME_PLATE_UNIT_ADDED" or event == "UNIT_SPELLCAST_SUCCEEDED" then M:HandleCaptureEvent(event, ...)
    else M:HandleCaptureEvent(event) end
end)

function M:ExportText()
    local lines = { "-- Monstrator local observations; approximate until reviewed.", "return {" }
    local keys = {}
    for key in pairs(self.observations.entries) do table.insert(keys, key) end
    table.sort(keys)
    local fields = { "key", "npcID", "name", "kind", "category", "mapID", "x", "y",
        "source", "build", "locale", "verification", "precision", "lastSeen", "sightings", "faction",
        "level", "reaction", "observer", "creatureType", "classification", "title" }
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
