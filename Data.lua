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

-- Sub-groups refine a category (e.g. Trainers > Fishing). They are derived from each record's title
-- (the NPC's <subtitle>), tags, level or classification, so no stored data changes. A record may sit in
-- several sub-groups (an armorer that also repairs); `other` catches whatever no sibling matched.
-- Keys are stable identifiers; `label` is a locale key. Rows with `section` are headings only.
M.subgroups = {
    ["npc:Trainers"] = {
        { section = "Class trainers" },
        { key = "trainer:warrior", label = "Warrior", title = { "warrior" } },
        { key = "trainer:paladin", label = "Paladin", title = { "paladin" } },
        { key = "trainer:hunter", label = "Hunter", title = { "hunter", "pet trainer" } },
        { key = "trainer:rogue", label = "Rogue", title = { "rogue" } },
        { key = "trainer:priest", label = "Priest", title = { "priest" } },
        { key = "trainer:shaman", label = "Shaman", title = { "shaman" } },
        { key = "trainer:mage", label = "Mage", title = { "mage", "portal trainer" } },
        { key = "trainer:warlock", label = "Warlock", title = { "warlock", "demon trainer" } },
        { key = "trainer:druid", label = "Druid", title = { "druid" } },
        { section = "Profession trainers" },
        { key = "trainer:alchemy", label = "Alchemy", title = { "alchemy", "alchemist" } },
        { key = "trainer:blacksmithing", label = "Blacksmithing", title = { "blacksmith", "armorsmith", "weaponsmith", "armor crafter", "weapon crafter" } },
        { key = "trainer:enchanting", label = "Enchanting", title = { "enchant" } },
        { key = "trainer:engineering", label = "Engineering", title = { "engineer" } },
        { key = "trainer:leatherworking", label = "Leatherworking", title = { "leatherwork", "leathercraft" } },
        { key = "trainer:tailoring", label = "Tailoring", title = { "tailor" } },
        { key = "trainer:herbalism", label = "Herbalism", title = { "herbalis" } },
        { key = "trainer:mining", label = "Mining", title = { "mining", "miner" } },
        { key = "trainer:skinning", label = "Skinning", title = { "skinn" } },
        { key = "trainer:cooking", label = "Cooking", title = { "cook", "chef", "butcher" } },
        { key = "trainer:first_aid", label = "First Aid", title = { "first aid", "physician", "surgeon" } },
        { key = "trainer:fishing", label = "Fishing", title = { "fish" } },
        { section = "Other trainers" },
        { key = "trainer:weapon_master", label = "Weapon masters", tags = { "weapon_master" } },
        { key = "trainer:riding", label = "Riding", tags = { "riding" }, title = { "mechanostrider pilot" } },
        { key = "trainer:other", label = "Other trainers", other = true },
    },
    ["npc:Vendors"] = {
        { section = "Goods" },
        { key = "vendor:food", label = "Food & drink", tags = { "food", "drink" },
          title = { "baker", "butcher", "bartender", "barmaid", "waitress", "meat", "cheese", "fruit", "bread", "wine",
          "brew", "grocer", "cook", "chef", "fish vendor", "fish merchant", "treats", "mushroom", "pie", "vintner", "beverage" } },
        { key = "vendor:general", label = "General goods", title = { "general goods", "general supplies", "general store", "tradesman" } },
        { key = "vendor:weapons", label = "Weapons", tags = { "weapon" },
          title = { "blade", "gunsmith", "bow", "staff", "axe", "mace", "sword", "dagger" } },
        { key = "vendor:armor", label = "Armor & shields", tags = { "armor" }, title = { "clothier", "shield", "robe" } },
        { key = "vendor:ammo", label = "Ammunition", title = { "ammunition", "ammo", "arrow", "bullet", "bowyer", "gunsmith" } },
        { key = "vendor:reagents", label = "Reagents", tags = { "reagent" } },
        { key = "vendor:potions", label = "Potions", tags = { "potion" }, title = { "elixir" } },
        { key = "vendor:poisons", label = "Poisons", title = { "poison" } },
        { key = "vendor:bags", label = "Bags", title = { "bag" } },
        { key = "vendor:mounts", label = "Mounts & pets", title = { "mount", "breeder", "stable", "kodo", "mechanostrider",
          "saber handler", "raptor handler", "horse", "pets", "pet vendor", "kitten", "cat lady", "snake", "prairie dog",
          "cockroach", "owl trainer", "wintersaber" } },
        { key = "vendor:faction", label = "Faction quartermasters", title = { "quartermaster", "supply officer",
          "argent dawn", "explorers' league", "coin of ancestry" } },
        { key = "vendor:demon", label = "Demon tomes", title = { "demon trainer", "demon master" } },
        { key = "vendor:holiday", label = "Holiday & seasonal", title = { "holiday", "fireworks", "festival", "smokywood" } },
        { key = "vendor:repair", label = "Repairs", tags = { "repair" } },
        { section = "Profession supplies" },
        { key = "supplies:alchemy", label = "Alchemy", title = { "alchemy" } },
        { key = "supplies:blacksmithing", label = "Blacksmithing", title = { "blacksmithing" } },
        { key = "supplies:enchanting", label = "Enchanting", title = { "enchanting" } },
        { key = "supplies:engineering", label = "Engineering", title = { "engineering" } },
        { key = "supplies:leatherworking", label = "Leatherworking", title = { "leatherworking" } },
        { key = "supplies:tailoring", label = "Tailoring", title = { "tailoring" } },
        { key = "supplies:herbalism", label = "Herbalism", title = { "herbalism", "herbalist" } },
        { key = "supplies:mining", label = "Mining", title = { "mining" } },
        { key = "supplies:cooking", label = "Cooking", title = { "cooking" } },
        { key = "supplies:first_aid", label = "First Aid", title = { "first aid", "bandage" } },
        { key = "supplies:fishing", label = "Fishing", title = { "fishing", "fisherman", "bait", "tackle" } },
        { key = "supplies:trade", label = "Trade goods", title = { "trade supplies", "trade supplier", "trade goods" } },
        { key = "vendor:other", label = "Other vendors", other = true },
    },
    ["npc:Services"] = {
        { key = "service:innkeeper", label = "Innkeepers", tags = { "innkeeper" } },
        { key = "service:bank", label = "Bankers", tags = { "bank" } },
        { key = "service:auction", label = "Auctioneers", tags = { "auction" } },
        { key = "service:stable", label = "Stable masters", tags = { "stable" } },
        { key = "service:guild", label = "Guild masters", tags = { "guild" } },
        { key = "service:tabard", label = "Tabard designers", tags = { "tabard" } },
        { key = "service:spirit_healer", label = "Spirit healers", title = { "spirit healer" } },
        { key = "service:battlemaster", label = "Battlemasters", title = { "battlemaster" } },
        { key = "service:quest", label = "Quest givers", tags = { "quest_giver" } },
        { key = "service:other", label = "Other services", other = true },
    },
    ["npc:Transit"] = {
        { key = "transit:flight", label = "Flight masters", tags = { "flight" } },
        { key = "transit:zeppelin", label = "Zeppelins", tags = { "zeppelin" }, title = { "zeppelin" } },
        { key = "transit:boat", label = "Boats", tags = { "boat" }, title = { "boat", "dockmaster", "harbor" } },
        { key = "transit:portal", label = "Portals", tags = { "portal" }, title = { "portal" } },
        { key = "transit:other", label = "Other transit", other = true },
    },
    ["npc:Combat"] = {
        { section = "Level range" },
        { key = "level:1", label = "Levels 1-10", level = { 1, 10 } },
        { key = "level:11", label = "Levels 11-20", level = { 11, 20 } },
        { key = "level:21", label = "Levels 21-30", level = { 21, 30 } },
        { key = "level:31", label = "Levels 31-40", level = { 31, 40 } },
        { key = "level:41", label = "Levels 41-50", level = { 41, 50 } },
        { key = "level:51", label = "Levels 51-60", level = { 51, 60 } },
        { key = "level:61", label = "Level 61+", level = { 61, 1000 } },
        { section = "Rank" },
        { key = "rank:rare", label = "Rare", classification = { "rare", "rareelite" } },
        { key = "rank:elite", label = "Elite", classification = { "elite", "rareelite" } },
        { key = "rank:boss", label = "Bosses", classification = { "worldboss" } },
    },
    ["location:Instances"] = {
        { key = "instance:dungeon", label = "Dungeons", tags = { "dungeon" } },
        { key = "instance:raid", label = "Raids", tags = { "raid" } },
        { key = "instance:meeting_stone", label = "Meeting stones", tags = { "meeting_stone" } },
    },
    ["location:Transit"] = {
        { key = "route:flight", label = "Flight paths", tags = { "flight_path", "flight" } },
        { key = "route:zeppelin", label = "Zeppelins", tags = { "zeppelin" } },
        { key = "route:boat", label = "Boats", tags = { "boat" } },
        { key = "route:portal", label = "Portals", tags = { "portal" } },
    },
    ["location:Objects"] = {
        { key = "object:herb", label = "Herbs", tags = { "herb" } },
        { key = "object:ore", label = "Mining nodes", tags = { "ore" } },
        { key = "object:chest", label = "Treasure chests", tags = { "chest" } },
        { key = "object:fishing", label = "Fishing pools", tags = { "fishing" } },
        { key = "object:anvil", label = "Anvils", tags = { "anvil" } },
        { key = "object:forge", label = "Forges", tags = { "forge" } },
        { key = "object:cooking", label = "Cooking fires", tags = { "cooking" } },
        { key = "object:quest", label = "Quest objects", tags = { "quest_object" } },
    },
}
M.subgroupByKey = {}
for group, list in pairs(M.subgroups) do
    local kind, category = group:match("^(%a+):(.+)$")
    local section
    for _, def in ipairs(list) do
        if def.section then section = def.section end
        if def.key then def.kind, def.category, def.group = kind, category, section; M.subgroupByKey[def.key] = def end
    end
end

local function subgroupMatches(def, record, title)
    for _, word in ipairs(def.title or {}) do
        if title:find(word, 1, true) then return true end
    end
    for _, wanted in ipairs(def.tags or {}) do
        for _, tag in ipairs(record.tags or {}) do
            if tag == wanted then return true end
        end
    end
    if def.level and type(record.level) == "number" and record.level >= def.level[1] and record.level <= def.level[2] then
        return true
    end
    for _, value in ipairs(def.classification or {}) do
        if record.classification == value then return true end
    end
    return false
end

-- Returns the sub-group keys a record belongs to within its own category (possibly empty).
function M:RecordSubgroups(record)
    local list = self.subgroups[tostring(record.kind) .. ":" .. tostring(record.category)]
    if not list then return {} end
    local title, keys, other = type(record.title) == "string" and record.title:lower() or "", {}, nil
    for _, def in ipairs(list) do
        if def.other then other = def.key
        elseif def.key and subgroupMatches(def, record, title) then table.insert(keys, def.key) end
    end
    if other and #keys == 0 then keys[1] = other end
    return keys
end

-- The active sub-group definition, but only while its category is the one being browsed.
function M:ActiveSubgroup(kind, category)
    local def = self.subgroup and self.subgroupByKey[self.subgroup]
    if def and def.kind == (kind or self.kind) and def.category == (category or self.category) then return def end
end

-- Finds the sub-group best described by free text ("fishing trainer", "weapons", "herbs"); every word must
-- match its English or translated name, section or category. Trainers are tried first ("blacksmith" means
-- the trainer; "blacksmithing supplies" finds the vendor).
function M:FindSubgroup(text)
    local words = {}
    for word in string.lower(text or ""):gmatch("%S+") do table.insert(words, word) end
    if #words == 0 then return nil end
    local L = self.L
    for _, group in ipairs({ { "npc", "Trainers" }, { "npc", "Services" }, { "npc", "Vendors" }, { "npc", "Transit" },
        { "npc", "Combat" }, { "location", "Objects" }, { "location", "Instances" }, { "location", "Transit" } }) do
        local kind, category = group[1], group[2]
        do
            for _, def in ipairs(self.subgroups[kind .. ":" .. category] or {}) do
                if def.key then
                    local haystack = table.concat({ def.key, def.label, L[def.label], category, L[category],
                        def.group or "", def.group and L[def.group] or "" }, " "):lower()
                    local all = true
                    for _, word in ipairs(words) do
                        if not haystack:find(word, 1, true) then all = false; break end
                    end
                    if all then return def end
                end
            end
        end
    end
end

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
