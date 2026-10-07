local saved = { createFrame = CreateFrame, unitGUID = UnitGUID, portrait = SetPortraitTexture,
    displayPortrait = SetPortraitTextureFromCreatureDisplayID, state = M.portraits, clock = clock }
local available = { [2001] = 501, [2002] = 502, [2003] = 501 }
local modelCount, queries, paints = 0, 0, 0
CreateFrame = function(kind, ...)
    local frame = saved.createFrame(kind, ...)
    if kind == "PlayerModel" then
        modelCount = modelCount + 1
        frame.ClearModel = function(self) self.creature = nil end
        frame.SetCreature = function(self, id) self.creature = id; queries = queries + 1 end
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
local row = CreateFrame("Frame"):CreateTexture()
local detail = CreateFrame("Frame"):CreateTexture()
M:SetEntryArtwork(row, npc(2001))
M:SetEntryArtwork(detail, npc(2001))
assert(queries == 1, "row and details share one creature lookup")
drain()
assert(row.texture == "portrait:501" and detail.texture == "portrait:501")
assert(row.portraitDisplayID == 501)
local oldQueries, oldPaints = queries, paints
M:SetEntryArtwork(row, npc(2001))
assert(queries == oldQueries and paints == oldPaints, "cached portraits do not reload on every render")
M:SetEntryArtwork(row, npc(2002))
M:SetEntryArtwork(row, { kind = "location", category = "Mailboxes", tags = {} })
drain()
assert(row.texture == "Interface\\Icons\\INV_Letter_15", "late portrait cannot overwrite a recycled location row")
M:SetEntryArtwork(row, npc(2002))
assert(row.texture == "portrait:502", "recycled rows can use the resolved display cache")
M:SetEntryArtwork(row, npc(2003))
drain()
assert(row.texture == "portrait:501", "NPCs that share a display still reset correctly on recycled rows")
M:SetEntryArtwork(row, npc(2999))
drain()
assert(row.texture == M:EntryIcon(npc(2999)), "uncached NPC keeps the honest icon fallback")
oldQueries = queries
M:SetEntryArtwork(row, npc(2999))
assert(queries == oldQueries, "unavailable creatures are not queried on every refresh")
clock = clock + 61
available[2999] = 502
M:SetEntryArtwork(row, npc(2999))
drain()
assert(row.texture == "portrait:502", "an unavailable creature can resolve after the retry cooldown")
assert(modelCount == 1, "all visible NPCs share one hidden model resolver")
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
assert(row.texture == "portrait:501" and queries == oldQueries + 1,
    "evicted appearance data can be resolved again without stale artwork")
local liveUnit
UnitGUID = function(unit)
    if unit == "target" then return "Creature-0-0-0-0-2001-0001" end
end
SetPortraitTexture = function(texture, unit) liveUnit = unit; texture:SetTexture("live portrait") end
M:SetEntryArtwork(row, npc(2002))
drain()
assert(row.texture == "portrait:502", "unrelated target must never supply the portrait")
M:SetEntryArtwork(row, npc(2001))
assert(liveUnit == "target" and row.texture == "live portrait", "matching live unit supplies its actual portrait")
SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = nil, nil
M:SetEntryArtwork(row, npc(2002))
assert(row.texture == M:EntryIcon(npc(2002)), "clients without portrait APIs retain category icons")
CreateFrame, UnitGUID = saved.createFrame, saved.unitGUID
SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = saved.portrait, saved.displayPortrait
M.portraits, clock = saved.state, saved.clock
