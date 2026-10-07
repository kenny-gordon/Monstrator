local saved = { createFrame = CreateFrame, unitGUID = UnitGUID, portrait = SetPortraitTexture,
    displayPortrait = SetPortraitTextureFromCreatureDisplayID, state = M.portraits, clock = clock }
local available = { [2001] = 501, [2002] = 502, [2003] = 501 }
local modelCount, queries, paints = 0, 0, 0
CreateFrame = function(kind, ...)
    local frame = saved.createFrame(kind, ...)
    if kind == "PlayerModel" then
        modelCount = modelCount + 1
        frame.ClearModel = function(self) self.creature = nil end
        frame.SetCreature = function(self, id)
            self.creature = id
            queries = queries + 1
            if self:IsShown() and available[id] and self:GetScript("OnModelLoaded") then
                self:GetScript("OnModelLoaded")(self)
            end
        end
        frame.GetDisplayInfo = function(self) return available[self.creature] or 0 end
    end
    return frame
end
UnitGUID = function() return nil end
SetPortraitTextureFromCreatureDisplayID = function(texture, id)
    assert(id == 501 or id == 502, "portrait API must receive a display ID, never an NPC ID")
    texture:SetTexture("portrait:" .. id)
    paints = paints + 1
end
M.portraits = nil
local timerIndex = #pendingTimers
local function drain()
    local count = 0
    while timerIndex < #pendingTimers do
        timerIndex = timerIndex + 1
        pendingTimers[timerIndex]()
        count = count + 1
        assert(count < 100, "portrait loading must be bounded")
    end
end
local function npc(id)
    return { kind = "npc", category = "Combat", npcID = id, tags = {} }
end
local row = M.window.rows[1].icon
local detail = M.window.info.icon
local setTexture = row.SetTexture
local reported = #messages
row.SetTexture = function(self, icon)
    if icon == "Interface\\Icons\\INV_Box_01" then return false end
    return setTexture(self, icon)
end
M:SetEntryArtwork(row, { kind = "location", category = "Objects", tags = { "chest" } })
assert(row.texture == "Interface\\Icons\\INV_Misc_QuestionMark" and #messages == reported + 1,
    "a rejected icon asset is reported and uses visible fallback artwork, never an empty slot")
M:SetEntryArtwork(row, { kind = "location", category = "Mailboxes", tags = {} })
M:SetEntryArtwork(row, { kind = "location", category = "Objects", tags = { "chest" } })
assert(#messages == reported + 1, "missing artwork is reported once rather than on every recycled row")
row.SetTexture = setTexture
row.entryIcon = nil
M:SetEntryArtwork(row, { kind = "location", category = "Objects", tags = { "chest" } })
assert(row.texture == "Interface\\Icons\\INV_Box_01" and row:IsShown() and not row.portraitTexture:IsShown(),
    "container fallback uses valid native box artwork and never a recycled creature portrait")
local icons = {}
for id = 1617, 1622 do
    local icon = M:EntryIcon({ kind = "location", category = "Objects", objectID = id, tags = { "herb" } })
    assert(not icons[icon], "common herb nodes have distinct native item artwork")
    icons[icon] = true
end
assert(M:EntryIcon({ kind = "npc", category = "Combat", objectID = 1617, tags = {} })
    ~= M:EntryIcon({ kind = "location", category = "Objects", objectID = 1617, tags = { "herb" } }),
    "object artwork must not leak into NPC portraits")
M:SetEntryArtwork(row, npc(2001))
M:SetEntryArtwork(detail, npc(2001))
assert(queries == 1, "row and details share one creature lookup")
assert(M.portraits.model:IsShown() and M.portraits.model.alpha == 0,
    "model loading runs on an active but invisible resolver")
drain()
assert(not M.portraits.model:IsShown(), "idle appearance resolver does not keep rendering")
assert(row.portraitTexture.texture == "portrait:501" and detail.portraitTexture.texture == "portrait:501")
assert(row.portraitDisplayID == 501)
assert(row.isPortrait and not row.portraitTexture.mask and row.texCoords[1] == 0 and row.texCoords[2] == 1,
    "resolved portraits retain the full creature image in a square slot")
assert(row.slotBorder:IsShown() and not row.portraitBorder,
    "NPC portraits use the same square native border as objects, with no gold portrait ring")
local oldQueries, oldPaints = queries, paints
M:SetEntryArtwork(row, npc(2001))
assert(queries == oldQueries and paints == oldPaints, "cached portraits do not reload on every render")
M:SetEntryArtwork(row, npc(2002))
M:SetEntryArtwork(row, { kind = "location", category = "Mailboxes", tags = {} })
drain()
assert(row.texture == "Interface\\Icons\\INV_Letter_15", "late portrait cannot overwrite a recycled location row")
row.portraitTexture:SetTexture("late engine portrait")
assert(row:IsShown() and not row.portraitTexture:IsShown(),
    "engine-side portrait updates cannot overwrite static icons because the textures are separate")
assert(not row.isPortrait and not row.portraitTexture.mask and row.slotBorder:IsShown(),
    "recycling a portrait into a location preserves the same square framing")
assert(row.texCoords[1] == 0.07 and row.texCoords[2] == 0.93)
M:SetEntryArtwork(row, npc(2002))
assert(row.portraitTexture.texture == "portrait:502", "recycled rows can use the resolved display cache")
M:SetEntryArtwork(row, npc(2003))
drain()
assert(row.portraitTexture.texture == "portrait:501", "NPCs that share a display still reset correctly on recycled rows")
M:SetEntryArtwork(row, npc(2999))
drain()
assert(row.texture == M:EntryIcon(npc(2999)), "uncached NPC keeps the honest icon fallback")
assert(row.slotBorder:IsShown() and not row.portraitBorder)
oldQueries = queries
M:SetEntryArtwork(row, npc(2999))
assert(queries == oldQueries, "unavailable creatures are not queried on every refresh")
clock = clock + 61
available[2999] = 502
M:SetEntryArtwork(row, npc(2999))
drain()
assert(row.portraitTexture.texture == "portrait:502", "an unavailable creature can resolve after the retry cooldown")
assert(modelCount == 1, "all visible NPCs share one hidden model resolver")
local prime = M.PrimeCreature
local primed, retryCount = nil, 0
local setCreature = M.portraits.model.SetCreature
M.PrimeCreature = function(_, id)
    primed = id
end
M.portraits.model.SetCreature = function(self, id)
    if id == 2995 then
        retryCount = retryCount + 1
        if retryCount == 3 then available[id] = 502 end
    end
    setCreature(self, id)
end
M:SetEntryArtwork(row, npc(2995))
drain()
assert(primed == 2995 and row.portraitTexture.texture == "portrait:502",
    "an uncached creature is requested and retried after delayed cache arrival")
M.PrimeCreature = prime
M.portraits.model.SetCreature = setCreature
local getDisplay = M.portraits.model.GetDisplayInfo
M.portraits.model.GetDisplayInfo = function() return 501 end
M:SetEntryArtwork(row, npc(2996))
drain()
assert(not row.isPortrait and row:IsShown(), "a stale display ID without OnModelLoaded must not become the next NPC portrait")
M.portraits.model.GetDisplayInfo = getDisplay
for i = 1, 257 do
    available[3000 + i] = 501
    M:SetEntryArtwork(row, npc(3000 + i))
    drain()
end
local cacheCount = 0
for _ in pairs(M.portraits.cache) do cacheCount = cacheCount + 1 end
assert(cacheCount == 256 and #M.portraits.cacheOrder == 256,
    "browsing thousands of creatures must not grow the appearance cache without a bound")
oldQueries = queries
M:SetEntryArtwork(row, npc(2001))
drain()
assert(row.portraitTexture.texture == "portrait:501" and queries == oldQueries + 1,
    "evicted appearance data can be resolved again without stale artwork")
local liveUnit
UnitGUID = function(unit)
    if unit == "target" then return "Creature-0-0-0-0-2001-0001" end
end
SetPortraitTexture = function(texture, unit) liveUnit = unit; texture:SetTexture("live portrait") end
M:SetEntryArtwork(row, npc(2002))
drain()
assert(row.portraitTexture.texture == "portrait:502", "unrelated target must never supply the portrait")
M:SetEntryArtwork(row, npc(2001))
assert(liveUnit == "target" and row.portraitTexture.texture == "live portrait", "matching live unit supplies its actual portrait")
UnitGUID = function() return nil end
M:SetEntryArtwork(row, npc(2001))
assert(row.portraitTexture.texture == "portrait:501" and not row.portraitUnitGUID,
    "when the live unit disappears the same row restores its cached database portrait")
UnitGUID = function(unit)
    if unit == "target" then return "Creature-0-0-0-0-2998-0001" end
end
M:SetEntryArtwork(row, npc(2998))
assert(row.portraitTexture.texture == "live portrait")
UnitGUID = function() return nil end
M:SetEntryArtwork(row, npc(2998))
drain()
assert(row.texture == M:EntryIcon(npc(2998)) and not row.isPortrait,
    "a vanished live unit with no cached appearance resets to its fallback, never the old portrait")
available[2997] = 501
M:SetEntryArtwork(row, npc(2997))
UnitGUID = function(unit)
    if unit == "target" then return "Creature-0-0-0-0-2997-0001" end
end
M:SetEntryArtwork(row, npc(2997))
drain()
assert(row.portraitTexture.texture == "live portrait" and row.portraitUnitGUID,
    "late generic appearance must not overwrite a live portrait of the selected spawn")
UnitGUID = function() return nil end
M:SetEntryArtwork(row, npc(2997))
assert(row.portraitTexture.texture == "portrait:501", "resolved generic appearance is available once the live unit disappears")
SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = nil, nil
M:SetEntryArtwork(row, npc(2002))
assert(row.texture == M:EntryIcon(npc(2002)), "clients without portrait APIs retain category icons")
CreateFrame, UnitGUID = saved.createFrame, saved.unitGUID
SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = saved.portrait, saved.displayPortrait
M.portraits, clock = saved.state, saved.clock
row.entryIcon, row.portraitNPC, detail.entryIcon, detail.portraitNPC = nil, nil, nil, nil
M:Render()
