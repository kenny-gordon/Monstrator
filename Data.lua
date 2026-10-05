local _, M = ...
M.data = { schema = 1, dataVersion = "1.0.0", entries = {} }
M.tags = {}
for _, tag in ipairs({
    "innkeeper", "flight", "repair", "bank", "auction", "mailbox", "stable",
    "guild", "tabard", "food", "drink", "reagent", "potion", "weapon",
    "armor", "profession_supplies", "vendor", "trainer", "class_trainer",
    "profession_trainer", "riding", "weapon_master", "portal", "zeppelin",
    "boat", "flight_path", "dungeon", "raid", "quest_giver", "landmark",
    "herb", "ore", "chest", "fishing", "anvil", "forge", "meeting_stone", "cooking", "quest_object",
}) do M.tags[tag] = true end

M.categories = {
    all = { "All" },
    npc = { "All", "Services", "Vendors", "Trainers", "Transit", "Combat" },
    location = { "All", "Mailboxes", "Instances", "Transit", "Landmarks", "Objects" },
}

function M:ValidateRecord(record)
    if type(record) ~= "table" then return nil, "Record must be a table." end
    if type(record.key) ~= "string" or record.key == "" then return nil, "Missing stable record key." end
    if record.verification == "curated" and (record.key:match("^local:") or record.key:match("^client:")) then
        return nil, "Curated records cannot use reserved local/client keys."
    end
    if record.kind ~= "npc" and record.kind ~= "location" then return nil, "Invalid record kind." end
    if type(record.name) ~= "string" or record.name == "" then return nil, "Missing name." end
    if not self:IsFinite(record.mapID) or record.mapID < 1 or record.mapID % 1 ~= 0 then
        return nil, "Invalid numeric map ID."
    end
    if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapInfo(record.mapID) then
        return nil, "Unknown map ID: " .. record.mapID
    end
    if not self:IsFinite(record.x) or not self:IsFinite(record.y)
        or record.x < 0 or record.x > 100 or record.y < 0 or record.y > 100 then
        return nil, "Coordinates must be finite percentages from 0 to 100."
    end
    if record.kind == "npc" and (not self:IsFinite(record.npcID)
        or record.npcID < 1 or record.npcID % 1 ~= 0) then return nil, "Invalid NPC ID." end
    local validCategory = false
    for _, category in ipairs(self.categories[record.kind]) do
        if category ~= "All" and category == record.category then validCategory = true end
    end
    if not validCategory then return nil, "Invalid category." end
    if type(record.tags) ~= "table" then return nil, "Missing tags." end
    local count = 0
    for index, tag in pairs(record.tags) do
        count = count + 1
        if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or index > #record.tags then
            return nil, "Tags must be a contiguous array."
        end
        if not self.tags[tag] then return nil, "Unknown canonical tag: " .. tostring(tag) end
    end
    if count ~= #record.tags then return nil, "Tags must be a contiguous array." end
    for i = 1, count do
        if type(record.tags[i]) ~= "string" then return nil, "Tags must be a contiguous string array." end
    end
    if record.faction ~= nil and record.faction ~= "Alliance" and record.faction ~= "Horde"
        and record.faction ~= "Both" then return nil, "Invalid faction." end
    if type(record.source) ~= "string" or type(record.build) ~= "string"
        or type(record.locale) ~= "string" then return nil, "Missing source/build/locale provenance." end
    if record.verification ~= "pending" and record.verification ~= "user-confirmed" and record.verification ~= "client-map"
        and record.verification ~= "client-object"
        and record.verification ~= "reference"
        and record.verification ~= "curated" then return nil, "Invalid verification state." end
    if record.precision ~= "encounter" and record.precision ~= "confirmed" and record.precision ~= "map"
        and record.precision ~= "reference" then return nil, "Invalid position evidence." end
    if record.verification == "reference" then
        local native = record.edition == "Forever" and record.source:match("^monstrator%-db:")
            and record.key:match("^reference:monstrator:")
        -- Favorites saved by older builds may still hold Classic reference snapshots; they stay readable.
        local legacy = record.edition == "Classic" and record.source:match("^classic%-reference:")
            and record.kind == "npc" and record.key:match("^reference:")
        local object = native and record.kind == "location" and self:IsFinite(record.objectID)
            and record.objectID >= 1 and record.objectID % 1 == 0
        if (record.kind ~= "npc" and not object) or not (native or legacy) or record.precision ~= "reference"
            or type(record.permission) ~= "string" or record.permission == "" then
            return nil, "Database records must retain source, license and unverified placement evidence."
        end
    elseif record.precision == "reference" or record.key:match("^reference:") then
        return nil, "Reference evidence cannot be promoted without a new local/curated record."
    end
    if (record.verification == "client-map" or record.verification == "client-object") and (record.kind ~= "location" or record.precision ~= "map"
        or not record.key:match("^client:") or not record.source:match("^client:")) then
        return nil, "Client map records must retain map-marker provenance."
    end
    if record.verification == "client-object" and (record.category ~= "Objects"
        or record.source ~= "client:local-GameObjects"
        or (record.objectType ~= 5 and record.objectType ~= 38 and record.objectType ~= 48)) then
        return nil, "Extracted objects must retain object type/source evidence."
    end
    if record.verification == "curated" and (type(record.permission) ~= "string" or record.permission == "") then
        return nil, "Curated records require permission/license provenance."
    end
    if record.verification == "curated" and record.edition ~= "Forever" then
        return nil, "Curated records must explicitly target the Forever edition."
    end
    if record.sightings ~= nil and (not self:IsFinite(record.sightings)
        or record.sightings < 1 or record.sightings % 1 ~= 0) then return nil, "Invalid sighting count." end
    if record.lastSeen ~= nil and (not self:IsFinite(record.lastSeen) or record.lastSeen < 0) then
        return nil, "Invalid observation timestamp."
    end
    if record.level ~= nil and (not self:IsFinite(record.level) or record.level < -1 or record.level % 1 ~= 0) then
        return nil, "Invalid NPC level."
    end
    if record.reaction ~= nil and (not self:IsFinite(record.reaction) or record.reaction < 1
        or record.reaction > 8 or record.reaction % 1 ~= 0) then return nil, "Invalid NPC reaction." end
    for _, key in ipairs({ "creatureType", "classification", "title" }) do
        if record[key] ~= nil and type(record[key]) ~= "string" then return nil, "Invalid NPC " .. key .. "." end
    end
    if record.nativeOrigin ~= nil and record.nativeOrigin ~= "discovery" and record.nativeOrigin ~= "correction" then
        return nil, "Invalid native data origin."
    end
    return true
end
