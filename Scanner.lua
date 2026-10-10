local _, M = ...
local L = M.L
-- NPC scan: alerts when a watched NPC (or, optionally, any rare) appears on a nameplate, as your target or
-- mouseover, or as a minimap vignette. Watch entries are NPC IDs, plus plain names for NPCs the database lacks.

local REALERT_SECONDS = 300
local LOG_LIMIT = 50
local WATCH_ROWS, LOG_ROWS = 6, 5
local MAX_NAME_MATCHES = 25
local RARE = { rare = true, rareelite = true, worldboss = true }
local RANK = { rare = "Rare", rareelite = "Rare Elite", worldboss = "Boss", elite = "Elite" }
local SCAN_ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function creatureID(guid)
    if type(guid) ~= "string" or not readable(guid) then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    id = tonumber(id)
    if id and id > 0 and id % 1 == 0 then return id end
end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

function M:InitializeScanner()
    local s = self.settings
    for key, default in pairs({ scanEnabled = true, scanRares = true, scanSound = true }) do
        if type(s[key]) ~= "boolean" then s[key] = default end
    end
    local function clean(list, keyCheck)
        if type(list) ~= "table" then return {} end
        for key, name in pairs(list) do
            if not keyCheck(key) or type(name) ~= "string" or name == "" then list[key] = nil end
        end
        return list
    end
    s.scanWatch = clean(s.scanWatch, function(id) return self:IsFinite(id) and id > 0 and id % 1 == 0 end)
    s.scanWatchNames = clean(s.scanWatchNames, function(name) return type(name) == "string" and name ~= "" and name == name:lower() end)
    local log = type(s.scanLog) == "table" and s.scanLog or {}
    for i = #log, 1, -1 do
        local e = log[i]
        if type(e) ~= "table" or type(e.name) ~= "string" or not self:IsFinite(e.time) then table.remove(log, i) end
    end
    for i = #log, LOG_LIMIT + 1, -1 do log[i] = nil end
    s.scanLog = log
    self.scanSeen = {}
end

function M:NPCName(npcID)
    local lib = self:NativeProvider()
    if not lib or type(lib.Npc.name) ~= "function" then return end
    local ok, name = pcall(lib.Npc.name, npcID)
    if ok and type(name) == "string" and name ~= "" then return name end
end

function M:FindNPCsByName(name)
    local lib = self:NativeProvider()
    local wanted = trim(name):lower()
    if not lib or wanted == "" or type(lib.Npc.GetAllIds) ~= "function" then return {} end
    local ok, ids = pcall(lib.Npc.GetAllIds)
    local found = {}
    if not ok or type(ids) ~= "table" then return found end
    for _, id in ipairs(ids) do
        local npcName = self:NPCName(id)
        if npcName and npcName:lower() == wanted then
            table.insert(found, id)
            if #found >= MAX_NAME_MATCHES then break end
        end
    end
    table.sort(found)
    return found
end

function M:IsWatched(npcID, name)
    local s = self.settings
    if npcID and s.scanWatch[npcID] then return true end
    return type(name) == "string" and s.scanWatchNames[name:lower()] ~= nil
end

function M:WatchNPC(npcID, name, quiet)
    if not self:IsFinite(npcID) or npcID < 1 or npcID % 1 ~= 0 then
        self:Error(L["NPC IDs must be positive whole numbers."]); return false
    end
    name = name or self:NPCName(npcID) or (L["NPC %d"]):format(npcID)
    self.settings.scanWatch[npcID] = name
    self.scanSeen[npcID] = nil
    if not quiet then self:Notice((L["Watching for %s (NPC ID %d)."]):format(name, npcID)) end
    self:ScanNameplates()
    self:RefreshScanViews()
    return true
end

function M:WatchName(name)
    name = trim(name)
    if name == "" then return false end
    self.settings.scanWatchNames[name:lower()] = name
    self:Notice((L["Watching for any NPC named \"%s\" (not in the database)."]):format(name))
    self:ScanNameplates()
    self:RefreshScanViews()
    return true
end

function M:UnwatchNPC(npcID)
    local name = self.settings.scanWatch[npcID]
    if not name then return false end
    self.settings.scanWatch[npcID] = nil
    self:Notice((L["Stopped watching %s."]):format(name))
    self:RefreshScanViews()
    return true
end

function M:UnwatchName(name)
    local key = trim(name):lower()
    local display = self.settings.scanWatchNames[key]
    if not display then return false end
    self.settings.scanWatchNames[key] = nil
    self:Notice((L["Stopped watching %s."]):format(display))
    self:RefreshScanViews()
    return true
end

function M:ToggleWatch(npcID, name)
    if self.settings.scanWatch[npcID] then return self:UnwatchNPC(npcID) end
    return self:WatchNPC(npcID, name)
end

-- Accepts an NPC ID, an exact NPC name, or nothing (the current target).
function M:AddScanWatch(text)
    text = trim(text)
    if text == "" then
        local guid, name = UnitGUID("target"), UnitName("target")
        local npcID = creatureID(guid)
        if not npcID or type(name) ~= "string" or not readable(name) then
            self:Error(L["Target an NPC, or give an NPC ID or name."]); return false
        end
        return self:WatchNPC(npcID, name)
    end
    local id = tonumber(text)
    if id then return self:WatchNPC(id) end
    local ids = self:FindNPCsByName(text)
    if #ids == 0 then return self:WatchName(text) end
    for _, npcID in ipairs(ids) do self:WatchNPC(npcID, nil, true) end
    self:Notice((L["Watching for %s (%d database IDs)."]):format(self:NPCName(ids[1]) or text, #ids))
    return true
end

function M:RemoveScanWatch(text)
    text = trim(text)
    local id = tonumber(text)
    if id then
        if self:UnwatchNPC(id) then return true end
    elseif self:UnwatchName(text) then return true
    else
        local removed = 0
        for npcID, name in pairs(self.settings.scanWatch) do
            if name:lower() == text:lower() then self.settings.scanWatch[npcID] = nil; removed = removed + 1 end
        end
        if removed > 0 then
            self:Notice((L["Stopped watching %s."]):format(text))
            self:RefreshScanViews()
            return true
        end
    end
    self:Error((L["\"%s\" is not on the watch list."]):format(text))
    return false
end

function M:ScanWatchList()
    local list = {}
    for npcID, name in pairs(self.settings.scanWatch) do table.insert(list, { npcID = npcID, name = name }) end
    for key, name in pairs(self.settings.scanWatchNames) do table.insert(list, { nameKey = key, name = name }) end
    table.sort(list, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return (a.npcID or 0) < (b.npcID or 0)
    end)
    return list
end

function M:ScanMatch(npcID, name, classification)
    if self:IsWatched(npcID, name) then return "watch" end
    if self.settings.scanRares and classification and RARE[classification] then return "rare" end
end

function M:ScanUnit(unit, source)
    if not self.ready or not self.settings.scanEnabled or type(unit) ~= "string" then return end
    if UnitExists and not UnitExists(unit) then return end
    local guid, name = UnitGUID(unit), UnitName(unit)
    local npcID = creatureID(guid)
    if not npcID or type(name) ~= "string" or not readable(name) then return end
    if UnitIsDead then
        local dead = UnitIsDead(unit)
        if readable(dead) and dead then return end
    end
    local classification = UnitClassification and UnitClassification(unit)
    if not readable(classification) or type(classification) ~= "string" then classification = nil end
    local reason = self:ScanMatch(npcID, name, classification)
    if not reason then return end
    local level = UnitLevel and UnitLevel(unit)
    if not self:IsFinite(level) then level = nil end
    return self:ScanAlert({ npcID = npcID, name = name, reason = reason, source = source,
        classification = classification, level = level, unit = unit, guid = guid })
end

function M:ScanNameplates()
    if not self.ready or not self.settings.scanEnabled or not UnitExists then return end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) then self:ScanUnit(unit, "nameplate") end
    end
end

function M:ScanVignette(vignetteGUID)
    if not self.ready or not self.settings.scanEnabled or not readable(vignetteGUID) then return end
    local api = C_VignetteInfo
    if not api or type(api.GetVignetteInfo) ~= "function" then return end
    local ok, info = pcall(api.GetVignetteInfo, vignetteGUID)
    if not ok or type(info) ~= "table" then return end
    local npcID = creatureID(info.objectGUID)
    local name = readable(info.name) and type(info.name) == "string" and info.name or nil
    if not npcID then return end
    name = name or self:NPCName(npcID)
    if not name then return end
    local reason = self:IsWatched(npcID, name) and "watch" or (self.settings.scanRares and "rare" or nil)
    if not reason then return end
    local hit = { npcID = npcID, name = name, reason = reason, source = "vignette", guid = info.objectGUID }
    local mapID = self:PlayerPosition()
    if mapID and type(api.GetVignettePosition) == "function" then
        local okPosition, position = pcall(api.GetVignettePosition, vignetteGUID, mapID)
        local x, y
        if okPosition and position and readable(position) and position.GetXY then x, y = position:GetXY() end
        if self:IsFinite(x) and self:IsFinite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            hit.mapID, hit.x, hit.y, hit.exact = mapID, x * 100, y * 100, true
        end
    end
    return self:ScanAlert(hit)
end

function M:ScanHeadline(hit)
    return (hit.reason == "watch" and L["Watched NPC spotted: "] or L["Rare spotted: "]) .. hit.name
end

function M:ScanDetail(hit)
    local parts = {}
    if hit.level then
        local rank = RANK[hit.classification or ""]
        table.insert(parts, L["Level "] .. (hit.level < 1 and "??" or hit.level) .. (rank and (" " .. L[rank]) or ""))
    end
    if hit.mapID then
        table.insert(parts, ("%s %.1f, %.1f"):format(self:MapName(hit.mapID), hit.x, hit.y))
    end
    if hit.source then table.insert(parts, L["scan:" .. hit.source]) end
    return table.concat(parts, "  |  ")
end

function M:ScanAlert(hit)
    local now = GetTime()
    local last = self.scanSeen[hit.npcID]
    if last and now - last < REALERT_SECONDS then return false end
    self.scanSeen[hit.npcID] = now
    if not hit.mapID then
        local mapID, x, y = self:PlayerPosition()
        if mapID then hit.mapID, hit.x, hit.y = mapID, x, y end
    end
    local log = self.settings.scanLog
    local _, build = GetBuildInfo()
    local entry = { npcID = hit.npcID, name = hit.name, reason = hit.reason, source = hit.source,
        mapID = hit.mapID, x = hit.x, y = hit.y, exact = hit.exact or nil, time = time(), level = hit.level,
        classification = hit.classification, build = tostring(build), locale = GetLocale() }
    self:SealScanHit(entry)
    table.insert(log, 1, entry)
    for i = #log, LOG_LIMIT + 1, -1 do log[i] = nil end
    local headline = self:ScanHeadline(hit)
    self:Notice("|cffff5533" .. headline .. "|r  " .. self:ScanDetail(hit))
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, headline,
            (ChatTypeInfo and ChatTypeInfo.RAID_WARNING) or { r = 1, g = 0.35, b = 0.2 })
    end
    if self.settings.scanSound and PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if FlashClientIcon then pcall(FlashClientIcon) end
    self:ShowScanAlert(hit)
    self:RefreshScanViews()
    return true
end

-- Navigates to where the NPC was seen, falling back to its nearest database spawn.
function M:ScanWaypoint(hit)
    if not hit then return false end
    if hit.mapID and self:IsFinite(hit.x) and self:IsFinite(hit.y) then
        return self:SetNavigationWaypoint(hit.mapID, hit.x, hit.y, hit.name .. " " .. L["(seen here)"])
    end
    local lib = self:NativeProvider()
    local ok, spawns = false, nil
    if lib and hit.npcID then ok, spawns = pcall(lib.Npc.spawns, hit.npcID) end
    local spot = ok and self:NearestSpawn(spawns)
    if spot and spot.mapID then return self:SetNavigationWaypoint(spot.mapID, spot.x, spot.y, hit.name) end
    self:Error(L["No known position for this NPC."])
    return false
end

function M:MarkScanNPC()
    local hit = self.scanHit
    if inCombat() then self:Error(L["scan.markCombat"]); return false end
    if not GetRaidTargetIndex then
        self:Error(L["scan.markUnavailable"]); return false
    end
    if IsInRaid and IsInRaid() and not ((UnitIsGroupLeader and UnitIsGroupLeader("player"))
        or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        self:Error(L["scan.markPermission"]); return false
    end
    local units = { "target", "mouseover" }
    if hit and hit.unit then table.insert(units, 1, hit.unit) end
    for i = 1, 40 do table.insert(units, "nameplate" .. i) end
    for _, unit in ipairs(units) do
        local guid = UnitGUID(unit)
        local dead = UnitIsDead and UnitIsDead(unit)
        if hit and readable(guid) and creatureID(guid) == hit.npcID
            and (not hit.guid or guid == hit.guid) and readable(dead) and not dead then
            local marker = GetRaidTargetIndex(unit)
            if not readable(marker) then self:Error(L["scan.markUnavailable"]); return false end
            if marker == 8 then return true end
            if marker and marker ~= 0 then self:Error(L["scan.markOccupied"]); return false end
            return unit
        end
    end
    self:Error(L["scan.markMissing"])
    return false
end

-- Targeting an NPC by name needs a secure button. Its attributes and visibility cannot change in combat, so it
-- is a separate top-level frame (never anchored to the alert) and updates are deferred to PLAYER_REGEN_ENABLED.
function M:SetScanTarget(name)
    self.scanTargetName = name and name:gsub("[\r\n]", "") or nil
    self:ApplyScanTarget()
end

function M:ApplyScanTarget()
    local b = self.scanTargetButton
    if not b then return end
    local name = self.scanTargetName
    if inCombat() then
        self.scanTargetPending = true
        -- The macro still targets the previous NPC until combat ends; alpha and text are not protected, so say so.
        if b:IsShown() and b.appliedName ~= name then
            b:SetAlpha(0.4)
            b:SetText(L["After combat"])
        end
        return
    end
    self.scanTargetPending = nil
    if self.scanMarkButton then
        self.scanMarkButton:SetAttribute("active", name ~= nil)
        self.scanMarkButton:SetAttribute("macrotext", "")
        self.scanMarkButton:SetShown(name ~= nil)
    end
    b.appliedName = name
    b:SetAlpha(1)
    b:SetText(L["Target"])
    if name then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/targetexact " .. name)
        b:Show()
    else
        b:SetAttribute("macrotext", nil)
        b:Hide()
    end
end

function M:CreateScanAlert()
    local W = self.Widgets
    local f = CreateFrame("Frame", "MonstratorScanAlert", UIParent, "BackdropTemplate")
    f:SetSize(380, 142)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    -- Alerts must sit above every Monstrator window (HIGH/DIALOG), not underneath them.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    W.backdrop(f)
    f.portrait = f:CreateTexture(nil, "ARTWORK")
    f.portrait:SetPoint("TOPLEFT", 14, -14)
    f.portrait:SetSize(46, 46)
    f.heading = W.label(f, "", 70, -12, 12)
    f.heading:SetTextColor(1, 0.42, 0.25)
    f.name = W.label(f, "", 70, -28, 17)
    f.info = W.label(f, "", 70, -52, 11)
    for _, text in ipairs({ f.heading, f.name, f.info }) do
        text:SetWidth(296)
        text:SetMaxLines(1)
        text:SetJustifyH("LEFT")
    end
    f.info:SetTextColor(0.86, 0.84, 0.78)
    f.waypoint = W.button(f, "Waypoint", 104, -80, 84, function() self:ScanWaypoint(self.scanHit) end)
    f.model = W.button(f, "3D model", 194, -80, 84, function()
        if self.scanHit then self:ShowModel("npc", self.scanHit.npcID, self.scanHit.name) end
    end)
    f.close = W.button(f, "Close", 284, -80, 82, function() f:Hide() end)
    local mark = CreateFrame("Button", "MonstratorScanMark", UIParent,
        "SecureActionButtonTemplate,SecureHandlerStateTemplate,UIPanelButtonTemplate")
    mark:SetSize(352, 24)
    mark:SetPoint("TOPLEFT", UIParent, "TOP", -176, -260)
    mark:SetFrameStrata("FULLSCREEN_DIALOG")
    mark:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
    mark:SetText(L["scan.mark"])
    mark:RegisterForClicks("AnyUp", "AnyDown")
    mark:SetAttribute("type", "macro")
    mark:SetAttribute("macrotext", "")
    mark:SetAttribute("_onstate-combat", [[
        self:SetAttribute("macrotext", "")
        if newstate == "combat" then
            self:Hide()
        elseif self:GetAttribute("active") then
            self:Show()
        end
    ]])
    if RegisterStateDriver then
        RegisterStateDriver(mark, "combat", "[combat] combat; peace")
        mark:SetScript("PreClick", function(button)
            if inCombat() then return end
            button:SetAttribute("macrotext", "")
            local unit = self:MarkScanNPC()
            if type(unit) == "string" then
                button:SetAttribute("macrotext", "/tm [@" .. unit .. ",exists,nodead] 8")
            end
        end)
    else
        mark:Disable()
        self:Error(L["scan.markUnavailable"])
    end
    mark:Hide()
    self.scanMarkButton, f.mark = mark, mark
    f.mark:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["scan.mark"])
        GameTooltip:AddLine(L["scan.markHint"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnHide", function() self:SetScanTarget(nil) end)
    local ok, target = pcall(CreateFrame, "Button", "MonstratorScanTarget", UIParent,
        "SecureActionButtonTemplate,UIPanelButtonTemplate")
    if ok and target then
        target:SetSize(84, 24)
        target:SetPoint("TOPLEFT", UIParent, "TOP", -190 + 14, -150 - 80)
        target:SetFrameStrata("FULLSCREEN_DIALOG")
        target:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
        target:SetText(L["Target"])
        if target.RegisterForClicks then target:RegisterForClicks("AnyUp", "AnyDown") end
        target:Hide()
        self.scanTargetButton = target
    end
    f:Hide()
    self.scanAlert = f
end

function M:ShowScanAlert(hit)
    if not self.scanAlert then
        if inCombat() then self.scanAlertPending = hit; return end
        self:CreateScanAlert()
    end
    local f = self.scanAlert
    self.scanHit = hit
    f.heading:SetText(hit.reason == "watch" and L["WATCHED NPC SPOTTED"] or L["RARE SPOTTED"])
    f.name:SetText(hit.name)
    f.info:SetText(self:ScanDetail(hit))
    f.portrait:SetTexture(SCAN_ICON)
    if hit.unit and SetPortraitTexture then pcall(SetPortraitTexture, f.portrait, hit.unit) end
    f:Show()
    f:Raise()
    self:SetScanTarget(hit.name)
end

local function ago(seconds)
    if seconds < 60 then return L["just now"] end
    if seconds < 3600 then return (L["%d min ago"]):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return (L["%d h ago"]):format(math.floor(seconds / 3600)) end
    return (L["%d days ago"]):format(math.floor(seconds / 86400))
end

function M:CreateScanWindow()
    local W = self.Widgets
    local label, button = W.label, W.button
    local f = CreateFrame("Frame", "MonstratorScanWindow", UIParent, "PortraitFrameTemplate")
    f:SetSize(560, 580)
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    W.escapeCloses(f)
    f.PortraitContainer.portrait:SetTexture(SCAN_ICON)
    f.TitleContainer.TitleText:SetText(L["NPC SCAN"])
    W.trackFont(f.TitleContainer.TitleText)
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    local subtitle = label(f, "Alerts when a watched NPC or a rare shows up on a nameplate, target, mouseover or the minimap", 24, -58, 12)
    subtitle:SetWidth(512)
    subtitle:SetMaxLines(2)
    subtitle:SetWordWrap(true)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.86, 0.84, 0.78)
    f.subtitle = subtitle
    local function toggle(key)
        return function()
            self.settings[key] = not self.settings[key]
            if key == "scanEnabled" and self.settings.scanEnabled then self:ScanNameplates() end
            self:RefreshScanViews()
        end
    end
    f.enabled = button(f, "Scanning", 20, -98, 172, toggle("scanEnabled"))
    f.rares = button(f, "Rare alerts", 196, -98, 172, toggle("scanRares"))
    f.sound = button(f, "Alert sound", 372, -98, 168, toggle("scanSound"))
    f.input = W.edit(f, 26, -134, 290)
    f.input:SetMaxLetters(80)
    f.hint = label(f.input, "NPC ID or exact name", 4, -5, 12)
    f.hint:SetTextColor(0.65, 0.65, 0.65)
    local function add()
        if self:AddScanWatch(f.input:GetText()) then f.input:SetText("") end
        f.input:ClearFocus()
    end
    f.input:SetScript("OnTextChanged", function() f.hint:SetShown(f.input:GetText() == "") end)
    f.input:SetScript("OnEnterPressed", add)
    f.addButton = button(f, "Watch", 324, -134, 100, function()
        if trim(f.input:GetText()) == "" then self:Error(L["Enter an NPC ID or name first."]); return end
        add()
    end)
    button(f, "Watch target", 430, -134, 110, function() self:AddScanWatch("") end)

    f.watchPanel = W.panel(f, "Watch list", 16, -168, 528, 196)
    f.watchPage = label(f, "", 300, -180, 11)
    f.watchPage:SetWidth(170)
    f.watchPage:SetJustifyH("RIGHT")
    button(f, "^", 476, -174, 26, function() self.scanWatchOffset = math.max(0, (self.scanWatchOffset or 0) - WATCH_ROWS); self:RefreshScanWindow() end)
    button(f, "v", 506, -174, 26, function() self.scanWatchOffset = (self.scanWatchOffset or 0) + WATCH_ROWS; self:RefreshScanWindow() end)
    f.watchRows = {}
    for i = 1, WATCH_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(500, 24)
        row:SetPoint("TOPLEFT", 28, -212 - (i - 1) * 25)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        row.hover = hover
        row.name = label(row, "", 4, -5, 13)
        row.name:SetWidth(300)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.detail = label(row, "", 310, -6, 11)
        row.detail:SetWidth(110)
        row.detail:SetJustifyH("RIGHT")
        row.detail:SetTextColor(0.86, 0.84, 0.78)
        row.remove = button(row, "Remove", 428, 0, 70, function()
            local entry = row.entry
            if not entry then return end
            if entry.npcID then self:UnwatchNPC(entry.npcID) else self:UnwatchName(entry.name) end
        end)
        row:SetScript("OnClick", function()
            if row.entry and row.entry.npcID then self:ShowModel("npc", row.entry.npcID, row.entry.name) end
        end)
        f.watchRows[i] = row
    end
    f.watchEmpty = label(f, "Nothing watched yet. Add an NPC ID or name, target an NPC and press Watch target, or use Watch in the directory.", 32, -218, 12)
    f.watchEmpty:SetWidth(490)
    f.watchEmpty:SetJustifyH("LEFT")
    f.watchEmpty:SetTextColor(0.86, 0.84, 0.78)

    f.logPanel = W.panel(f, "Recent sightings", 16, -372, 528, 160)
    button(f, "Clear", 470, -378, 62, function()
        wipe(self.settings.scanLog)
        self:RefreshScanWindow()
    end)
    f.logRows = {}
    for i = 1, LOG_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(500, 22)
        row:SetPoint("TOPLEFT", 28, -416 - (i - 1) * 23)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        row.hover = hover
        row.name = label(row, "", 4, -4, 12)
        row.name:SetWidth(220)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.detail = label(row, "", 228, -5, 11)
        row.detail:SetWidth(268)
        row.detail:SetMaxLines(1)
        row.detail:SetJustifyH("RIGHT")
        row.detail:SetTextColor(0.86, 0.84, 0.78)
        row:SetScript("OnClick", function() self:ScanWaypoint(row.entry) end)
        f.logRows[i] = row
    end
    f.logEmpty = label(f, "No sightings yet. Click a sighting to set a waypoint where it was seen.", 32, -420, 12)
    f.logEmpty:SetWidth(490)
    f.logEmpty:SetJustifyH("LEFT")
    f.logEmpty:SetTextColor(0.86, 0.84, 0.78)
    button(f, "Test alert", 20, -540, 120, function()
        local mapID, x, y = self:PlayerPosition()
        self.scanSeen[0] = nil
        self:ShowScanAlert({ npcID = 0, name = L["Test alert"], reason = "rare", source = "test", mapID = mapID, x = x, y = y })
    end)
    f.status = label(f, "", 150, -545, 11)
    f.status:SetWidth(390)
    f.status:SetJustifyH("RIGHT")
    f.status:SetTextColor(0.85, 0.82, 0.6)
    f:Hide()
    self.scanWindow = f
end

function M:RefreshScanWindow()
    local f = self.scanWindow
    if not f or not f:IsShown() then return end
    local s = self.settings
    local state = function(value) return L[value and "Enabled" or "Disabled"] end
    f.enabled:SetText(L["Scanning: "] .. state(s.scanEnabled))
    f.rares:SetText(L["Rare alerts: "] .. state(s.scanRares))
    f.sound:SetText(L["Alert sound: "] .. state(s.scanSound))
    local list = self:ScanWatchList()
    local maxOffset = math.max(0, math.floor((#list - 1) / WATCH_ROWS) * WATCH_ROWS)
    self.scanWatchOffset = math.max(0, math.min(self.scanWatchOffset or 0, maxOffset))
    for i, row in ipairs(f.watchRows) do
        local entry = list[self.scanWatchOffset + i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry.name)
            row.detail:SetText(entry.npcID and (L["NPC ID "] .. entry.npcID) or L["by name"])
        end
    end
    f.watchEmpty:SetShown(#list == 0)
    f.watchPage:SetText(#list > 0 and (L["%d-%d of %d"]):format(self.scanWatchOffset + 1,
        math.min(#list, self.scanWatchOffset + WATCH_ROWS), #list) or "")
    local now = time()
    for i, row in ipairs(f.logRows) do
        local entry = s.scanLog[i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText((entry.reason == "watch" and "|cffffd060" or "|cffff7050") .. entry.name .. "|r")
            local where = entry.mapID and ("%s %.1f, %.1f"):format(self:MapName(entry.mapID), entry.x or 0, entry.y or 0)
                or L["unknown location"]
            row.detail:SetText(where .. "  -  " .. ago(math.max(0, now - entry.time)))
        end
    end
    f.logEmpty:SetShown(#s.scanLog == 0)
    f.status:SetText(s.scanEnabled and (L["Watching %d NPCs%s."]):format(#list, s.scanRares and L[" plus all rares"] or "")
        or L["Scanning is off; no alerts will be shown."])
end

function M:RefreshScanViews()
    self:RefreshScanWindow()
    if self.window and self.window:IsShown() and self.RenderWatchButton then self:RenderWatchButton() end
end

function M:ToggleScanWindow()
    if not self.scanWindow then self:CreateScanWindow() end
    self.scanWindow:SetScale(self.settings.frameScale)
    self.scanWindow:SetShown(not self.scanWindow:IsShown())
    self:RefreshScanWindow()
end

function M:ScanCommand(argument)
    local command, rest = trim(argument):match("^(%S*)%s*(.-)$")
    command = command:lower()
    local s = self.settings
    if command == "" then self:ToggleScanWindow()
    elseif command == "on" or command == "off" then
        s.scanEnabled = command == "on"
        self:Notice(L["NPC scan: "] .. L[s.scanEnabled and "Enabled" or "Disabled"])
        if s.scanEnabled then self:ScanNameplates() end
    elseif command == "rares" then
        s.scanRares = not s.scanRares
        self:Notice(L["Rare alerts: "] .. L[s.scanRares and "Enabled" or "Disabled"])
    elseif command == "sound" then
        s.scanSound = not s.scanSound
        self:Notice(L["Alert sound: "] .. L[s.scanSound and "Enabled" or "Disabled"])
    elseif command == "add" or command == "watch" then self:AddScanWatch(rest)
    elseif command == "remove" or command == "unwatch" then self:RemoveScanWatch(rest)
    elseif command == "list" then
        local list = self:ScanWatchList()
        if #list == 0 then self:Notice(L["The watch list is empty."]) end
        for _, entry in ipairs(list) do
            self:Notice(entry.name .. (entry.npcID and (" (" .. entry.npcID .. ")") or (" (" .. L["by name"] .. ")")))
        end
    elseif command == "clear" then
        wipe(s.scanLog)
        self:Notice(L["Sighting log cleared."])
    elseif command == "test" then
        self.scanSeen[0] = nil
        local mapID, x, y = self:PlayerPosition()
        self:ShowScanAlert({ npcID = 0, name = L["Test alert"], reason = "rare", source = "test", mapID = mapID, x = x, y = y })
    else
        self:Error(L["Use /monstrator scan [on | off | rares | sound | add ID/NAME | remove ID/NAME | list | clear | test]."])
        return
    end
    self:RefreshScanViews()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "VIGNETTE_MINIMAP_UPDATED", "PLAYER_REGEN_ENABLED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_REGEN_ENABLED" then
        if M.scanAlertPending then
            local hit = M.scanAlertPending
            M.scanAlertPending = nil
            M:ShowScanAlert(hit)
        end
        if M.scanTargetPending then M:ApplyScanTarget() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then M:ScanUnit(arg, "nameplate")
    elseif event == "PLAYER_TARGET_CHANGED" then M:ScanUnit("target", "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then M:ScanUnit("mouseover", "mouseover")
    elseif event == "VIGNETTE_MINIMAP_UPDATED" then M:ScanVignette(arg) end
end)
M.scanEvents = events
