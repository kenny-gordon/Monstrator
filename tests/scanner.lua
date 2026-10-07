-- NPC scan: detection sources, watch list, alert throttling, combat-safe targeting, vignettes and UI.
assert(M.ready, "scanner tests need an initialized addon")
local s = M.settings
s.scanWatch, s.scanWatchNames, s.scanLog = { [0.5] = "bad", [77] = "" , [5] = "Kept" }, { Mixed = "bad", ok = "OK" }, { { name = 1 }, { name = "Old", time = 1 } }
s.scanEnabled, s.scanRares, s.scanSound = "yes", nil, false
M:InitializeScanner()
assert(s.scanEnabled == true and s.scanRares == true and s.scanSound == false, "bad scan flags reset, valid ones kept")
assert(s.scanWatch[5] == "Kept" and s.scanWatch[77] == nil and s.scanWatch[0.5] == nil, "invalid watch IDs are dropped")
assert(s.scanWatchNames.ok == "OK" and s.scanWatchNames.Mixed == nil)
assert(#s.scanLog == 1 and s.scanLog[1].name == "Old")
wipe(s.scanWatch); wipe(s.scanWatchNames); wipe(s.scanLog)

local units = {}
local savedGUID, savedName = UnitGUID, UnitName
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitExists = function(unit) return units[unit] ~= nil end
UnitClassification = function(unit) return units[unit] and units[unit].class or "normal" end
UnitIsDead = function(unit) return units[unit] and units[unit].dead or false end
UnitLevel = function() return 42 end
local sounds, warnings = 0, 0
PlaySound = function() sounds = sounds + 1 end
RaidWarningFrame = {}
RaidNotice_AddMessage = function() warnings = warnings + 1 end
local fire = M.scanEvents:GetScript("OnEvent")
local function npc(unit, id, name, class) units[unit] = { guid = "Creature-0-0-0-0-" .. id .. "-0000ABCD", name = name, class = class } end

npc("nameplate1", 501, "Ordinary Wolf")
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(#s.scanLog == 0 and not M.scanAlert, "ordinary NPCs never alert")

npc("nameplate2", 502, "Mirelow", "rare")
M:CreateScanAlert()
local target = M.scanTargetButton
local attributes = {}
target.SetAttribute = function(_, key, value) attributes[key] = value end
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate2")
assert(#s.scanLog == 1 and s.scanLog[1].npcID == 502 and s.scanLog[1].reason == "rare", "rares alert and are logged")
assert(s.scanLog[1].mapID == 1 and s.scanLog[1].x and not s.scanLog[1].exact, "sightings record the (approximate) encounter position")
assert(M.scanAlert:IsShown() and M.scanAlert.name:GetText() == "Mirelow")
assert(M.scanAlert.heading:GetText() == "RARE SPOTTED")
assert(M.scanAlert.strata == "FULLSCREEN_DIALOG", "alerts draw above the directory and scan windows")
assert(not M.scanTargetButton or M.scanTargetButton.strata == M.scanAlert.strata, "Target button shares the alert strata")
assert(attributes.macrotext == "/targetexact Mirelow" and target:IsShown(), "the secure target button follows the alert")
assert(sounds == 0, "sound respects the setting")
assert(warnings == 1, "alerts post a raid warning")
do
    local savedSet, savedGet, savedRaid = SetRaidTarget, GetRaidTargetIndex, IsInRaid
    local savedLeader, savedAssistant, savedCombat = UnitIsGroupLeader, UnitIsGroupAssistant, InCombatLockdown
    local markers, markCalls = {}, 0
    SetRaidTarget = function(unit, index) markCalls = markCalls + 1; markers[unit] = index end
    GetRaidTargetIndex = function(unit) return markers[unit] end
    IsInRaid = function() return false end
    InCombatLockdown = function() return false end
    M.scanAlert.mark:Click()
    assert(markers.nameplate2 == 8 and markCalls == 1, "alert button places a skull over the actual sighted rare")
    assert(M:MarkScanNPC() and markCalls == 1, "already marked NPC does not trigger another change")
    markers.nameplate2 = 4
    assert(not M:MarkScanNPC() and markers.nameplate2 == 4, "existing raid markers are preserved")
    markers.nameplate2 = nil
    InCombatLockdown = function() return true end
    assert(not M:MarkScanNPC() and markCalls == 1, "combat must never queue an automatic later marker")
    InCombatLockdown = function() return false end
    IsInRaid = function() return true end
    UnitIsGroupLeader, UnitIsGroupAssistant = function() return false end, function() return false end
    assert(not M:MarkScanNPC() and markCalls == 1, "raid permission is checked before marking")
    UnitIsGroupAssistant = function() return true end
    assert(M:MarkScanNPC() and markCalls == 2, "raid assistant can place the marker")
    markers.nameplate2 = nil
    local rare = units.nameplate2
    npc("nameplate2", 777, "Unrelated creature")
    assert(not M:MarkScanNPC() and markCalls == 2, "recycled nameplate token cannot mark the wrong creature")
    npc("nameplate2", 502, "Mirelow", "rare")
    units.nameplate2.guid = "Creature-0-0-0-0-502-DIFFERENT"
    assert(not M:MarkScanNPC() and markCalls == 2, "a different spawn of the same NPC is not the sighted rare")
    units.nameplate2 = nil
    units.target = rare
    assert(M:MarkScanNPC() and markers.target == 8, "targeted rare can be marked after its nameplate disappears")
    units.target = nil
    units.nameplate2 = rare
    SetRaidTarget, GetRaidTargetIndex, IsInRaid = savedSet, savedGet, savedRaid
    UnitIsGroupLeader, UnitIsGroupAssistant, InCombatLockdown = savedLeader, savedAssistant, savedCombat
end
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate2")
assert(#s.scanLog == 1, "the same NPC does not re-alert within the cooldown")
clock = clock + 301
s.scanSound = true
fire(nil, "PLAYER_TARGET_CHANGED")
units.target = units.nameplate2
fire(nil, "PLAYER_TARGET_CHANGED")
assert(#s.scanLog == 2 and s.scanLog[1].source == "target" and sounds == 1, "alerts repeat after the cooldown")

s.scanRares = false
npc("nameplate3", 503, "Another Rare", "rareelite")
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate3")
assert(#s.scanLog == 2, "rare alerts can be switched off")

units.nameplate4 = { guid = "Player-1-0000ABCD", name = "Some Player", class = "rare" }
assert(M:AddScanWatch("Some Player"))
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate4")
assert(#s.scanLog == 2, "players are never scanned")
assert(M:RemoveScanWatch("Some Player"))

-- Watching by ID, by unknown name and by target.
assert(M:AddScanWatch("504"))
assert(s.scanWatch[504], "numeric input watches an NPC ID")
npc("nameplate5", 504, "Plain Quest Giver")
units.nameplate5.dead = true
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate5")
assert(#s.scanLog == 2, "dead NPCs do not alert")
units.nameplate5.dead = false
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate5")
assert(s.scanLog[1].npcID == 504 and s.scanLog[1].reason == "watch", "watched NPCs alert without being rare")
assert(M.scanAlert.heading:GetText() == "WATCHED NPC SPOTTED")
assert(not M:AddScanWatch("0") and not M:AddScanWatch("1.5"), "invalid IDs are rejected")
assert(M:AddScanWatch("Forever Custom Boss"))
assert(s.scanWatchNames["forever custom boss"] == "Forever Custom Boss", "unknown names are watched by name")
npc("nameplate6", 9999901, "Forever Custom Boss")
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate6")
assert(s.scanLog[1].name == "Forever Custom Boss", "name watches match any NPC ID")
npc("target", 505, "Targeted Guard")
assert(M:AddScanWatch("") and s.scanWatch[505] == "Targeted Guard", "an empty add watches the current target")
units.target = nil
assert(not M:AddScanWatch(""), "an empty add without a target is an error")
local dbName = M:NPCName(11)
if dbName then
    assert(M:AddScanWatch(dbName:upper()) and s.scanWatch[11], "exact database names resolve to NPC IDs")
    assert(M:RemoveScanWatch(dbName) and not s.scanWatch[11], "names remove their resolved IDs")
end
assert(not M:RemoveScanWatch("not watched"))

-- Combat lockdown defers secure changes until combat ends.
InCombatLockdown = function() return true end
attributes = {}
clock = clock + 301
npc("nameplate7", 506, "Combat Rare", "rare")
s.scanRares = true
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate7")
assert(M.scanAlert.name:GetText() == "Combat Rare" and attributes.macrotext == nil and M.scanTargetPending,
    "secure attributes are not touched in combat")
InCombatLockdown = function() return false end
fire(nil, "PLAYER_REGEN_ENABLED")
assert(attributes.macrotext == "/targetexact Combat Rare" and not M.scanTargetPending)
assert(target:GetText() == "Target")
InCombatLockdown = function() return true end
M:SetScanTarget("Other Rare")
assert(attributes.macrotext == "/targetexact Combat Rare" and target:GetText() == "After combat",
    "a stale secure button is labelled until combat ends")
InCombatLockdown = function() return false end
fire(nil, "PLAYER_REGEN_ENABLED")
assert(attributes.macrotext == "/targetexact Other Rare" and target:GetText() == "Target")
M:SetScanTarget("Combat Rare")
M.scanAlert.close:Click()
assert(not M.scanAlert:IsShown() and not target:IsShown(), "closing the alert hides the target button")

-- Minimap vignettes, with exact positions when the client provides them.
C_VignetteInfo = {
    GetVignetteInfo = function(guid)
        if guid == "v1" then return { objectGUID = "Creature-0-0-0-0-507-0000ABCD", name = "Vignette Rare" } end
        if guid == "v2" then return { objectGUID = "GameObject-0-0-0-0-9-0000ABCD", name = "Treasure" } end
    end,
    GetVignettePosition = function() return CreateVector2D(0.25, 0.75) end,
}
fire(nil, "VIGNETTE_MINIMAP_UPDATED", "v2")
fire(nil, "VIGNETTE_MINIMAP_UPDATED", "v1")
assert(s.scanLog[1].name == "Vignette Rare" and s.scanLog[1].source == "vignette", "creature vignettes alert, objects do not")
assert(s.scanLog[1].x == 25 and s.scanLog[1].y == 75 and s.scanLog[1].exact, "vignette positions are used (and marked exact for harvest)")
C_VignetteInfo = nil

-- Waypoints go to where the NPC was seen.
local waypoint
TomTom = { AddWaypoint = function(_, mapID, x, y, options) waypoint = { mapID, x, y, options.title }; return {} end }
assert(M:ScanWaypoint(s.scanLog[1]))
assert(waypoint[1] == 1 and math.abs(waypoint[2] - 0.25) < 1e-9 and waypoint[4]:find("Vignette Rare", 1, true))
TomTom = nil

-- Scanning off silences every source.
M:ScanCommand("off")
clock = clock + 301
local before = #s.scanLog
fire(nil, "NAME_PLATE_UNIT_ADDED", "nameplate7")
assert(#s.scanLog == before and s.scanEnabled == false)
M:ScanCommand("on")
assert(s.scanEnabled and #s.scanLog > before, "turning scanning on sweeps visible nameplates")
M:ScanCommand("rares"); assert(s.scanRares == false); M:ScanCommand("rares")
M:ScanCommand("sound"); assert(s.scanSound == false); M:ScanCommand("sound")
M:ScanCommand("test")
assert(M.scanAlert:IsShown() and M.scanAlert.name:GetText() == "Test alert")
messages = {}
M:ScanCommand("bogus")
assert(messages[1]:find("/monstrator scan", 1, true))

-- Scan window and the directory's Watch button.
M:ToggleScanWindow()
local w = M.scanWindow
assert(w:IsShown() and w.enabled:GetText():find("Enabled", 1, true))
local list = M:ScanWatchList()
assert(#list >= 3 and w.watchRows[1]:IsShown() and not w.watchEmpty:IsShown())
for i = 2, #list do assert(list[i - 1].name:lower() <= list[i].name:lower(), "watch list is sorted by name") end
assert(w.logRows[1]:IsShown() and w.logRows[1].detail:GetText():find(M:MapName(s.scanLog[1].mapID), 1, true), w.logRows[1].detail:GetText())
local removing = w.watchRows[1].entry
w.watchRows[1].remove:Click()
assert(not M:IsWatched(removing.npcID, removing.name), "the remove button unwatches its row")
w.input:SetText("508")
w.addButton:Click()
assert(s.scanWatch[508] and w.input:GetText() == "", "the window adds IDs")
M:ScanCommand("clear")
assert(#s.scanLog == 0 and w.logEmpty:IsShown())
M:ToggleScanWindow()
assert(not w:IsShown())

if not M.window then M:CreateWindow() end
M.window:Show()
M.results = { { record = { key = "scan-test", npcID = 509, name = "Directory NPC", kind = "npc", category = "Vendors", mapID = 1, x = 10, y = 10 } } }
M.selected = 1
M:RenderWatchButton()
assert(M.window.info.watch:IsShown() and M.window.info.watch:GetText() == "Watch for this NPC")
M.window.info.watch:Click()
assert(s.scanWatch[509] == "Directory NPC" and M.window.info.watch:GetText():find("Stop watching", 1, true))
M.window.info.watch:Click()
assert(not s.scanWatch[509])
M.results[1].record.npcID = nil
M:RenderWatchButton()
assert(not M.window.info.watch:IsShown(), "locations cannot be watched")
M.results = {}

UnitGUID, UnitName = savedGUID, savedName
UnitExists, UnitClassification, UnitIsDead, UnitLevel, InCombatLockdown = nil, nil, nil, nil, nil
PlaySound, RaidWarningFrame, RaidNotice_AddMessage = nil, nil, nil
wipe(s.scanWatch); wipe(s.scanWatchNames); wipe(s.scanLog)
s.scanEnabled, s.scanRares, s.scanSound = true, true, true
if M.scanAlert then M.scanAlert:Hide() end
