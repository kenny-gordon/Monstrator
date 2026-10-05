local _, M = ...
local L = M.L
local backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true,
    tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function applyWindowBackdrop(frame, faction)
    frame:SetBackdrop(backdrop)
    faction = faction or UnitFactionGroup("player")
    -- The dialog background texture is translucent; a solid layer keeps windows behind from showing through.
    if not frame.solidBackground then
        frame.solidBackground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame.solidBackground:SetPoint("TOPLEFT", 4, -4)
        frame.solidBackground:SetPoint("BOTTOMRIGHT", -4, 4)
    end
    if faction == "Horde" then
        frame.solidBackground:SetColorTexture(0.07, 0.02, 0.02, 1)
        frame:SetBackdropColor(0.12, 0.035, 0.035, 0.99)
        frame:SetBackdropBorderColor(0.75, 0.24, 0.22, 1)
    else
        frame.solidBackground:SetColorTexture(0.015, 0.03, 0.06, 1)
        frame:SetBackdropColor(0.025, 0.055, 0.105, 0.99)
        frame:SetBackdropBorderColor(0.32, 0.55, 0.82, 1)
    end
end

-- Shrinks a font (never below 8pt) until its text fits `spec.fit` pixels; translated labels vary a lot in length.
local function applyFont(spec, scale)
    local size = spec.size * scale
    spec.font:SetFont(spec.path, size, spec.flags)
    if spec.fit and spec.font.GetStringWidth then
        local width = spec.font:GetStringWidth()
        if type(width) == "number" and width > spec.fit then
            spec.font:SetFont(spec.path, math.max(8, size * spec.fit / width), spec.flags)
        end
    end
end

local function trackFont(font, fit)
    M.fonts = M.fonts or {}
    local path, height, flags = font:GetFont()
    local spec = { font = font, path = path, size = height, flags = flags, fit = fit }
    table.insert(M.fonts, spec)
    if M.settings or fit then applyFont(spec, M.settings and M.settings.textScale or 1) end
    return spec
end

local label, button

function M:ShowHelp()
    if not self.helpFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(640, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        f.title = label(f, "Directory help", 22, -20, 20)
        f.title:SetWidth(550)
        f.title:SetJustifyH("LEFT")
        button(f, "Close", 548, -12, 72, function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 24, -62)
        scroll:SetPoint("BOTTOMRIGHT", -44, 24)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(550, 440)
        scroll:SetScrollChild(content)
        f.body = label(content,
            table.concat({ L["help.browse"], L["help.subgroups"], L["help.results"], L["help.database"], L["help.sort"], L["help.review"], L["help.items"], L["help.scan"], L["help.share"], L["help.keyboard"], L["help.commands"] }, "\n\n"),
            0, 0, 15)
        f.body:SetWidth(540)
        f.body:SetJustifyH("LEFT")
        f.body:SetJustifyV("TOP")
        f.body:SetTextColor(0.92, 0.93, 0.96)
        local bodyHeight = math.max(430, f.body:GetStringHeight() or 430)
        f.body:SetHeight(bodyHeight)
        content:SetHeight(bodyHeight)
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", function(_, key)
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then f:Hide() end
        end)
        self.helpFrame = f
    end
    self.helpFrame:Show()
end

label = function(parent, text, x, y, size)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetPoint("TOPLEFT", x, y)
    font:SetText(L[text])
    font:SetFont(STANDARD_TEXT_FONT, size or 14)
    trackFont(font)
    return font
end

button = function(parent, text, x, y, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 150, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(L[text])
    local fontString = b:GetFontString()
    fontString:SetMaxLines(1)
    local spec = trackFont(fontString, (width or 150) - 14)
    local setText = b.SetText
    b.SetText = function(self, value)
        setText(self, value)
        applyFont(spec, M.settings and M.settings.textScale or 1)
    end
    b:SetScript("OnClick", callback)
    return b
end

local function edit(parent, x, y, width, text)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 24)
    box:SetPoint("TOPLEFT", x, y)
    box:SetAutoFocus(false)
    box:SetText(text or "")
    trackFont(box)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function panel(parent, title, x, y, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetFrameLevel(parent:GetFrameLevel())
    applyWindowBackdrop(frame)
    if UnitFactionGroup("player") == "Horde" then
        frame:SetBackdropColor(0.17, 0.055, 0.055, 0.99)
    else
        frame:SetBackdropColor(0.045, 0.085, 0.15, 0.99)
    end
    local heading = label(frame, title, 12, -12, 14)
    heading:SetWidth(width - 24)
    heading:SetJustifyH("LEFT")
    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT", 10, -36)
    divider:SetSize(width - 20, 1)
    divider:SetColorTexture(0.5, 0.45, 0.35, 0.6)
    frame.heading = heading
    return frame
end

local function selectionMarker(control)
    local marker = control:CreateTexture(nil, "OVERLAY")
    marker:SetPoint("TOPLEFT", 3, -3)
    marker:SetPoint("BOTTOMLEFT", 3, 3)
    marker:SetWidth(3)
    if UnitFactionGroup("player") == "Horde" then
        marker:SetColorTexture(0.9, 0.3, 0.27, 1)
    else
        marker:SetColorTexture(0.35, 0.65, 1, 1)
    end
    marker:Hide()
    control.activeMarker = marker
end

local function escapeCloses(f)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(_, key)
        f:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then f:Hide() end
    end)
end

function M:ShowCopy(text)
    if not self.copyFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(640, 400)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        escapeCloses(f)
        label(f, "Select text and press Ctrl+C. Nothing is uploaded.", 18, -16)
        button(f, "Close", 550, -10, 70, function() f:Hide() end)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -55)
        scroll:SetPoint("BOTTOMRIGHT", -40, 20)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(570)
        box:SetAutoFocus(false)
        scroll:SetScrollChild(box)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box = box
        self.copyFrame = f
    end
    self.copyFrame.box:SetText(text)
    self.copyFrame:Show()
    self.copyFrame.box:SetFocus()
    self.copyFrame.box:HighlightText()
end

function M:ShowExport()
    local text = self:ExportText()
    if text then self:ShowCopy(text) end
end

function M:ShowIssues()
    self:EnsureIndex()
    local lines = { L["Quarantined records (preserved, excluded from directory):"] }
    for _, issue in ipairs(self.quarantine or {}) do
        local key = type(issue.record) == "table" and issue.record.key or "unknown"
        table.insert(lines, tostring(key) .. ": " .. issue.reason)
    end
    if #lines == 1 then table.insert(lines, L["No quarantined records."]) end
    self:ShowCopy(table.concat(lines, "\n"))
end

function M:ShowReview(record)
    if not self.reviewFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(560, 380)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        escapeCloses(f)
        f.title = label(f, "Review placement", 20, -20)
        f.title:SetWidth(520)
        f.title:SetJustifyH("LEFT")
        label(f, "Encounter position is approximate. Confirm a static placement.", 20, -55)
        label(f, "X (%)", 20, -95)
        label(f, "Y (%)", 180, -95)
        f.x = edit(f, 25, -120, 110)
        f.y = edit(f, 185, -120, 110)
        f.category = button(f, "Category", 20, -160, 220, function()
            local list = self.categories[f.record.kind]
            local index = 2
            for i, value in ipairs(list) do if value == f.value then index = i + 1 end end
            if index > #list then index = 2 end
            f.value = list[index]
            f.category:SetText(L[f.value])
        end)
        label(f, "Tags (comma separated)", 20, -202)
        f.tags = edit(f, 25, -228, 495)
        label(f, "Examples: food, innkeeper, repair, mailbox, flight", 20, -268, 11)
        button(f, "Confirm placement", 20, -310, 160, function()
            local x, y = tonumber(f.x:GetText()), tonumber(f.y:GetText())
            if not self:IsFinite(x) or not self:IsFinite(y) or x < 0 or x > 100 or y < 0 or y > 100 then
                self:Error(L["Enter coordinates between 0 and 100."]); return
            end
            if self:Review(f.record, "accept", x, y, f.value, f.tags:GetText()) then f:Hide() end
        end)
        button(f, "Delete record", 190, -310, 130, function()
            if self:Review(f.record, "reject") then f:Hide() end
        end)
        button(f, "Cancel", 330, -310, 100, function() f:Hide() end)
        self.reviewFrame = f
    end
    local f = self.reviewFrame
    f.record, f.value = record, record.category
    f.title:SetText(record.name .. " - " .. self:MapName(record.mapID))
    f.x:SetText(string.format("%.4f", record.x))
    f.y:SetText(string.format("%.4f", record.y))
    f.category:SetText(L[f.value])
    f.tags:SetText(table.concat(record.tags, ", "))
    f:Show()
end

function M:ShowNPCInventory()
    local inventory = self:NPCInventory()
    local lines = { (L["NPC inventory: %d distinct NPC IDs (all saved/indexed sources)."]):format(#inventory),
        L["Inventory evidence note"],
        L["NPC inventory columns"], "" }
    for _, item in ipairs(inventory) do
        local maps = {}
        for mapID in pairs(item.maps) do
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            table.insert(maps, info and info.name or tostring(mapID))
        end
        table.sort(maps)
        table.insert(lines, ("%d | %s | %d | %d | %d | %s"):format(item.npcID, item.name,
            item.confirmed, item.pending, item.reference or 0, table.concat(maps, ", ")))
    end
    if #inventory == 0 then table.insert(lines, L["Enable NPC discovery or capture a target; no NPC identities have been collected yet."]) end
    self:ShowCopy(table.concat(lines, "\n"))
end

local function isReferenceRecord(record)
    return record.verification == "reference"
end

local function isNativeRecord(record)
    return record.verification == "reference" and type(record.source) == "string"
        and record.source:match("^monstrator%-db:") ~= nil
end

local function recordEvidenceName(record)
    if isNativeRecord(record) then return L["evidenceNames.native"] end
    if isReferenceRecord(record) then return L["evidenceNames.legacy"] end
    return L[record.verification]
end

local function shortEvidenceName(record)
    if isNativeRecord(record) then return L["Monstrator DB"] end
    if isReferenceRecord(record) then return L["Legacy"] end
    return L[record.verification]
end

function M:ShowEntryDetails(entry)
    if not entry then self:Notice(L["Select a directory row first."]); return end
    if not self.detailsFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(560, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        f.title = label(f, "", 20, -20, 17)
        f.title:SetWidth(520)
        f.title:SetMaxLines(2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -76)
        scroll:SetSize(488, 210)
        f.content = CreateFrame("Frame", nil, scroll)
        f.content:SetSize(488, 212)
        scroll:SetScrollChild(f.content)
        f.body = label(f.content, "", 0, 0, 12)
        f.body:SetWidth(488)
        f.body:SetJustifyH("LEFT")
        f.body:SetJustifyV("TOP")
        f.navigate = button(f, "Navigate", 20, -310, 120, function()
            self:NavigateRecord(f.entry.record)
        end)
        f.favorite = button(f, "Favorite", 150, -310, 120, function()
            self:ToggleFavorite(f.entry.record)
            self:ShowEntryDetails(f.entry)
        end)
        f.review = button(f, "Edit journal", 280, -310, 120, function()
            self:ShowReview(f.entry.record)
            f:Hide()
        end)
        button(f, "Close", 410, -310, 120, function() f:Hide() end)
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", function(_, key)
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then f:Hide() end
        end)
        self.detailsFrame = f
    end
    local f, r = self.detailsFrame, entry.record
    local map = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
    f.entry = entry
    f.title:SetText(r.name .. (r.title and (" <" .. r.title .. ">") or ""))
    f.body:SetText(table.concat({
        (map and map.name or (L["Map %d"]):format(r.mapID)) .. (" | %.2f, %.2f"):format(r.x, r.y),
        L[r.kind] .. " / " .. L[r.category] .. " | " .. L[r.faction or "Both"],
        entry.distance and (L["Distance: %d yd"]):format(math.floor(entry.distance + 0.5))
            or (entry.distanceLabel or L["Distance unavailable"]),
        L["Tags: "] .. (#r.tags > 0 and table.concat(r.tags, ", ") or L["none"]),
        L["Evidence: "] .. (entry.stale and L["Stale favorite"] or recordEvidenceName(r)) .. " / " .. L[r.precision],
        L["Source: "] .. r.source,
        (L["Build: %s | Locale: %s"]):format(r.build, r.locale),
        r.npcID and (L["NPC ID: "] .. r.npcID) or (r.objectID and (L["Object ID: "] .. r.objectID)
            or L["Map location: no NPC identity is inferred."]),
        r.nativeOrigin and L["nativeOrigin." .. r.nativeOrigin] or "",
        r.npcID and (L["Level: %s | Type: %s | Rank: %s | Reaction: %s"]):format(tostring(r.level or L["unknown"]),
            r.creatureType or L["unknown"], r.classification or L["unknown"], tostring(r.reaction or L["unknown"])) or "",
        r.verification == "client-map" and L["Map marker only; not a confirmed NPC or object spawn."] or "",
        r.verification == "client-object" and L["Client object position checked against the live map. Signs locate the sign, not its named destination."] or "",
        isReferenceRecord(r) and L["Reference data; not verified for this server."] or "",
        isReferenceRecord(r) and tostring(r.permission) or "",
    }, "\n"))
    local height = math.max(212, f.body:GetStringHeight() or 212)
    f.body:SetHeight(height)
    f.content:SetHeight(height)
    f.favorite:SetText(L[self.favorites.entries[r.key] and "Remove favorite" or "Favorite"])
    f.review:SetShown(self.observations.entries[r.key] == r)
    f:Show()
end

function M:ShowSettings()
    if not self.options then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(470, 550)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        label(f, "Monstrator Settings", 20, -20)
        f.collect = button(f, "Collection", 20, -60, 390, function()
            self.settings.collecting = not self.settings.collecting
            self:ShowSettings()
        end)
        f.contrast = button(f, "High contrast", 20, -95, 390, function()
            self.settings.highContrast = not self.settings.highContrast
            self:ShowSettings()
            self:RefreshIfVisible()
        end)
        f.scale = label(f, "Frame scale", 20, -140)
        f.text = label(f, "Text scale", 20, -180)
        local function scale(key, delta, minimum)
            local value = math.max(minimum, math.min(1.5, self.settings[key] + delta))
            self.settings[key] = math.floor(value * 10 + 0.5) / 10
            self:ShowSettings()
            if self.window then
                self.window:SetScale(self.settings.frameScale)
                self:Render()
            end
        end
        button(f, "-", 255, -135, 60, function() scale("frameScale", -0.1, 0.6) end)
        button(f, "+", 330, -135, 60, function() scale("frameScale", 0.1, 0.6) end)
        button(f, "-", 255, -175, 60, function() scale("textScale", -0.1, 0.8) end)
        button(f, "+", 330, -175, 60, function() scale("textScale", 0.1, 0.8) end)
        f.limit = edit(f, 25, -230, 160)
        label(f, "Observation limit (1-100000)", 20, -205)
        button(f, "Apply", 210, -230, 180, function()
            local n = tonumber(f.limit:GetText())
            if not self:IsFinite(n) or n < 1 or n > 100000 or n % 1 ~= 0 then
                self:Error(L["Observation limit must be an integer from 1 to 100000."]); return
            end
            self.settings.observationLimit, self.fullNotice = n, nil
            self:Notice(L["Observation limit updated."])
        end)
        button(f, "Export journal", 20, -280, 125, function() self:ShowExport() end)
        button(f, "Share discoveries", 150, -280, 140, function() self:ShowSubmission() end)
        button(f, "Close", 295, -280, 115, function() f:Hide() end)
        button(f, "Manage journal", 20, -320, 180, function()
            f:Hide()
            self:Toggle("journal")
        end)
        button(f, "Load map data", 220, -320, 180, function() self:SyncClientData() end)
        f.discover = button(f, "NPC discovery", 20, -358, 410, function()
            SlashCmdList.MONSTRATOR("discover")
            self:ShowSettings()
        end)
        f.references = button(f, "Monstrator database", 20, -398, 410, function()
            self.settings.referenceEnabled = not (self.settings.referenceEnabled == true)
            self:ShowSettings()
            self:RefreshIfVisible()
        end)
        label(f, "Reference identities are not confirmed placements for this server.", 20, -434, 12)
        f.group = button(f, "Group NPC locations", 20, -466, 410, function()
            self.settings.groupNPCs = not self.settings.groupNPCs
            self:ShowSettings()
            self:RefreshIfVisible()
        end)
        f.minimap = button(f, "Minimap button", 20, -504, 200, function()
            SlashCmdList.MONSTRATOR("minimap")
            self:ShowSettings()
        end)
        button(f, "Reset window & filters", 230, -504, 200, function() self:ResetView() end)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        escapeCloses(f)
        self.options = f
    end
    local f = self.options
    f.minimap:SetText(L["Minimap button: "] .. L[self.settings.minimapHidden and "Disabled" or "Enabled"])
    f.collect:SetText(L["Local collection: "] .. L[self.settings.collecting and "Enabled" or "Disabled"])
    f.contrast:SetText(L["High contrast: "] .. L[self.settings.highContrast and "Enabled" or "Disabled"])
    f.scale:SetText(L["Frame scale: "] .. string.format("%.1f", self.settings.frameScale))
    f.text:SetText(L["Text scale: "] .. string.format("%.1f", self.settings.textScale))
    f.limit:SetText(tostring(self.settings.observationLimit))
    f.discover:SetText(L["NPC discovery: "] .. L[self.settings.discovering and "Enabled" or "Disabled"])
    f.references:SetText(L["Monstrator database: "] .. L[self.settings.referenceEnabled and "Enabled" or "Disabled"])
    f.group:SetText(L["Group NPC locations: "] .. L[self.settings.groupNPCs and "Enabled" or "Disabled"])
    f:Show()
end

function M:RefreshIfVisible()
    if self.window and self.window:IsShown() then self:Refresh() end
end

function M:Refresh()
    if self.searchPending then return end
    local s = self.settings
    s.scope, s.zoneMap, s.regionMap = self.scope, self.zoneMap or 0, self.regionMap or 0
    local selectedKey = self.results and self.results[self.selected or 1]
    selectedKey = selectedKey and selectedKey.record.key
    self:Query(self.scope, self.kind, self.category, self.window.search:GetText(), self.view)
    self.directoryCounts = self:DirectoryCounts(self.scope, self.window.search:GetText())
    self.lastMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    self.selected = 1
    for i, entry in ipairs(self.results) do
        if entry.record.key == selectedKey then self.selected = i; break end
    end
    self.offset = math.min(self.offset or 0, math.max(0, #self.results - #self.window.rows))
    self:Render()
end

function M:Render()
    local f = self.window
    if not f then return end
    local sortText = L["Sort: "] .. L["sort:" .. self.settings.sortOrder]
    if f.sort.renderText ~= sortText then f.sort:SetText(sortText); f.sort.renderText = sortText end
    local evidenceText = L["Evidence: "] .. L["filter:" .. self.settings.evidenceFilter]
    if f.evidence.renderText ~= evidenceText then f.evidence:SetText(evidenceText); f.evidence.renderText = evidenceText end
    local counts = self.directoryCounts or { all = 0, npc = 0, location = 0, categories = {} }
    for key, b in pairs(f.kindButtons) do
        local text
        if key == "npc" then
            text = (L["NPCs (%d)"]):format(counts.uniqueNPCs or counts.npc)
        else
            text = (key == "all" and L["All entries"] or L["Static locations"]) .. " (" .. counts[key] .. ")"
        end
        if b.renderText ~= text then b:SetText(text); b.renderText = text end
    end
    for i, b in ipairs(f.categoryButtons) do
        local category = self.categories[self.kind][i]
        if category then
            local categories = counts.categories[self.kind] or {}
            local amount = category == "All" and counts[self.kind] or (categories[category] or 0)
            local sub = self.category == category and self:ActiveSubgroup()
            local text = sub and (L[category] .. ": " .. L[sub.label] .. " (" .. ((counts.subgroups or {})[sub.key] or 0) .. ")")
                or (L[category] .. " (" .. amount .. ")")
            if b.renderText ~= text then b:SetText(text); b.renderText = text end
        end
    end
    if f.subpicker:IsShown() then self:RenderSubgroupPicker(true) end
    local queue = self.clientData.worldQueue
    local coverage = queue and (L["Scanning zones: %d/%d"]):format(queue.next - 1, #self.clientMapCatalog.maps)
        or (self.clientData.worldScanned and L["World scan finished"]) or nil
    coverage = (coverage and (coverage .. "\n") or "") .. self:DataSourceSummary()
    if f.renderCoverage ~= coverage then f.coverage:SetText(coverage); f.renderCoverage = coverage end
    if self.appliedTextScale ~= self.settings.textScale then
        for _, spec in ipairs(self.fonts or {}) do applyFont(spec, self.settings.textScale) end
        self.appliedTextScale = self.settings.textScale
    end
    local place = self.view == "directory" and (self:PlaceName() .. (self.npcFilter and self.npcFilter.label or "")) or ""
    local placeText = (L["place:" .. self.scope]):format(self:PlaceName())
    if f.placeButton.renderText ~= placeText then f.placeButton:SetText(placeText); f.placeButton.renderText = placeText end
    if f.renderScope ~= self.scope or f.renderKind ~= self.kind or f.renderCategory ~= self.category
        or f.renderSubgroup ~= self.subgroup
        or f.renderFilterView ~= self.view or f.renderPlace ~= place then
        f.filters:SetText(self:BreadcrumbText())
        f.renderFilterView, f.renderPlace, f.renderSubgroup = self.view, place, self.subgroup
        for key, b in pairs(f.scopeButtons) do b.activeMarker:SetShown(self.scope == key) end
        for key, b in pairs(f.kindButtons) do b.activeMarker:SetShown(self.kind == key) end
        for i, b in ipairs(f.categoryButtons) do
            b.activeMarker:SetShown(self.categories[self.kind][i] == self.category)
        end
        f.renderScope, f.renderKind, f.renderCategory = self.scope, self.kind, self.category
    end
    local filtering = self.npcFilter ~= nil and self.view == "directory"
    if f.clearFilter:IsShown() ~= filtering then f.clearFilter:SetShown(filtering) end
    local count, journalCount, pendingCount, confirmedNPCs, confirmedNPCIDs =
        #self.results, self:ObservationCount(), self:PendingObservationCount(), 0
    confirmedNPCIDs = {}
    self:EnsureIndex()
    if self.confirmedNPCCountIndex ~= self.index then
        for _, entry in ipairs(self.index.byKind.npc or {}) do
            if entry.record.verification == "curated" or entry.record.verification == "user-confirmed" then
                confirmedNPCs = confirmedNPCs + 1
                confirmedNPCIDs[entry.record.npcID] = true
            end
        end
        local identityCount = 0
        for _ in pairs(confirmedNPCIDs) do identityCount = identityCount + 1 end
        self.confirmedNPCCountIndex, self.confirmedNPCCount, self.confirmedNPCIdentityCount =
            self.index, confirmedNPCs, identityCount
    end
    confirmedNPCs = self.confirmedNPCCount or 0
    local onboardingText
    if pendingCount > 0 or confirmedNPCs > 0 then
        onboardingText = (L["Pending review: %d | Confirmed NPC: %d placements / %d IDs"])
            :format(pendingCount, confirmedNPCs, self.confirmedNPCIdentityCount or 0)
    else
        onboardingText = L["Tip: left-click a row for a waypoint, right-click to favorite."]
    end
    if f.onboarding and f.onboarding.renderText ~= onboardingText then
        f.onboarding:SetText(onboardingText)
        f.onboarding.renderText = onboardingText
    end
    if f.renderCount ~= count or f.renderView ~= self.view or f.renderJournal ~= journalCount then
        f.footer:SetText((L["Total found: %d | View: %s | Journal: %d"]):format(count, L[self.view], journalCount))
        f.renderCount, f.renderView, f.renderJournal = count, self.view, journalCount
    end
    if f.empty:IsShown() ~= (count == 0) then f.empty:SetShown(count == 0) end
    if f.renderEmptyView ~= self.view or f.renderEmptyJournal ~= journalCount
        or f.renderEmptyEvidence ~= self.settings.evidenceFilter then
        local message
        if self.view == "journal" then
            message = L["Your journal is empty.\nEnable local collection or save a manual landmark."]
        elseif self.view == "review" then
            message = L["No pending observations.\nEnable local collection in Settings, then interact with an NPC."]
        elseif self.view == "favorites" then
            message = L["No matching favorites.\nRight-click a directory row to save its placement."]
        elseif journalCount > 0 then
            message = L["No matching directory entries.\nOpen Review journal to confirm collected placements,\nor try Global world and different filters."]
        else
            message = L["No matching directory entries.\nTry Static locations for client map data,\nor enable collection and review NPC discoveries."]
        end
        if self.settings.evidenceFilter ~= "all" then
            message = message .. "\n" .. L["Evidence filter: "] .. L["filter:" .. self.settings.evidenceFilter]
                .. ".\nTry Evidence: All sources for broader results."
        end
        f.empty:SetText(message)
        f.renderEmptyView, f.renderEmptyJournal = self.view, journalCount
        f.renderEmptyEvidence = self.settings.evidenceFilter
    end
    if f.renderPageOffset ~= self.offset or f.renderPageCount ~= count then
        f.page:SetText((L["Rows %d-%d of %d"]):format(count == 0 and 0 or self.offset + 1,
            math.min(count, self.offset + #f.rows), count))
        f.renderPageOffset, f.renderPageCount = self.offset, count
    end
    if f.renderNavView ~= self.view then
        for key, b in pairs(f.viewButtons) do b.activeMarker:SetShown(self.view == key) end
        f.renderNavView = self.view
    end
    local reviewText = L["Review journal"] .. " (" .. pendingCount .. ")"
    if f.viewButtons and f.viewButtons.review and f.viewButtons.review.renderText ~= reviewText then
        f.viewButtons.review:SetText(reviewText)
        f.viewButtons.review.renderText = reviewText
    end
    for i, row in ipairs(f.rows) do
        local index = (self.offset or 0) + i
        local entry = self.results and self.results[index]
        row.entry, row.index = entry, index
        if row:IsShown() ~= (entry ~= nil) then row:SetShown(entry ~= nil) end
        if entry then
            local r = entry.record
            local favorite = self.favorites.entries[r.key] ~= nil
            local locations = entry.placementCount and entry.placementCount > 1
                and (" " .. (L["(%d locations)"]):format(entry.placementCount)) or ""
            if row.renderName ~= r.name or row.renderFavorite ~= favorite or row.renderTitle ~= r.title
                or row.renderPlacementCount ~= entry.placementCount then
                row.name:SetText((favorite and "|cffffd100*|r " or "") .. r.name
                    .. (r.title and (" |cffc8b070<" .. r.title .. ">|r") or "") .. locations)
                row.renderName, row.renderFavorite, row.renderTitle = r.name, favorite, r.title
                row.renderPlacementCount = entry.placementCount
            end
            local yards = entry.distance and math.floor(entry.distance + 0.5)
            local evidence = entry.stale and L["Stale favorite"] or shortEvidenceName(r)
            if row.renderKey ~= r.key or row.renderX ~= r.x or row.renderY ~= r.y
                or row.renderStale ~= entry.stale or row.renderVerification ~= r.verification
                or row.renderEvidence ~= evidence or row.renderNPCID ~= r.npcID then
                local map = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
                local identity = r.npcID and (L["NPC ID"] .. " " .. r.npcID .. " | ") or ""
                local level = (r.level and r.level > 0) and (L["Lv "] .. r.level .. " | ") or ""
                row.detail:SetText((L["%s  %.1f, %.1f | %s%s|cff9aa3b5%s|r"]):format(
                    map and map.name or (L["Map %d"]):format(r.mapID), r.x, r.y, level, identity, evidence))
                local group = (r.verification == "curated" or r.verification == "user-confirmed") and "confirmed"
                    or (r.verification == "client-map" or r.verification == "client-object") and "map"
                    or isReferenceRecord(r) and "reference" or r.verification
                local color = f.evidenceColors[group] or f.evidenceColors.pending
                row.badge:SetColorTexture(color[1], color[2], color[3], 1)
                row.renderKey, row.renderX, row.renderY = r.key, r.x, r.y
                row.renderStale, row.renderVerification = entry.stale, r.verification
                row.renderEvidence, row.renderNPCID = evidence, r.npcID
            end
            if row.renderYards ~= yards or row.renderLabel ~= entry.distanceLabel then
                row.distance:SetText(yards and string.format(L["%d yd"], yards)
                    or entry.distanceLabel or L["Distance unavailable"])
                row.renderYards, row.renderLabel = yards, entry.distanceLabel
            end
            local red, green, blue = 0.65, 0.67, 0.72
            if entry.distance then
                if self.settings.highContrast then red, green, blue = 1, 1, 0.6
                elseif entry.distance < 40 then red, green, blue = 0.3, 1, 0.3
                elseif entry.distance <= 100 then red, green, blue = 1, 0.85, 0.2
                else red, green, blue = 1, 0.35, 0.35 end
            end
            if row.renderRed ~= red or row.renderGreen ~= green or row.renderBlue ~= blue then
                row.distance:SetTextColor(red, green, blue)
                row.renderRed, row.renderGreen, row.renderBlue = red, green, blue
            end
            if row.renderTextScale ~= self.settings.textScale then
                row.name:SetFont(STANDARD_TEXT_FONT, 13 * self.settings.textScale)
                row.distance:SetFont(STANDARD_TEXT_FONT, 12 * self.settings.textScale)
                row.detail:SetFont(STANDARD_TEXT_FONT, 11 * self.settings.textScale)
                row.renderTextScale = self.settings.textScale
            end
            if row.selection:IsShown() ~= (self.selected == index) then row.selection:SetShown(self.selected == index) end
        end
    end
    self:RenderDetailsPane()
end

function M:UpdatePositionDisplay()
    local f = self.window
    if not f then return end
    local mapID, x, y = self:PlayerPosition()
    local rx, ry = x and math.floor(x * 10 + 0.5), y and math.floor(y * 10 + 0.5)
    if f.positionInitialized and f.positionMap == mapID and f.positionX == rx and f.positionY == ry then return end
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if mapID and rx and ry then
        f.position:SetText(L["You are in "] .. (info and info.name or tostring(mapID)) .. string.format("  (%.1f, %.1f)", rx / 10, ry / 10))
    else f.position:SetText(L["Position unavailable"]) end
    f.positionInitialized, f.positionMap, f.positionX, f.positionY = true, mapID, rx, ry
end

function M:ObservationCount()
    local count = 0
    for _ in pairs(self.observations.entries) do count = count + 1 end
    return count
end

function M:PendingObservationCount()
    local count = 0
    for _, record in pairs(self.observations.entries) do
        if record.verification == "pending" then count = count + 1 end
    end
    return count
end

function M:Activate(entry)
    if not entry then return end
    if self.searchPending then self:Notice(L["Search updating; try again shortly."]); return end
    if self.view == "review" or self.view == "journal" then self:ShowReview(entry.record)
    else
        self:NavigateRecord(entry.record)
    end
end

function M:ChangeView(view)
    self.view, self.offset, self.selected = view, 0, 1
    self:Refresh()
end

function M:StartRefresh()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(0.5, function() self:DistanceTick() end)
    else
        self.window.elapsed = 0
        self.window:SetScript("OnUpdate", function(f, elapsed)
            f.elapsed = f.elapsed + elapsed
            if f.elapsed >= 0.5 then f.elapsed = 0; self:DistanceTick() end
        end)
    end
end

function M:DistanceTick()
    if not self.window or not self.window:IsShown() or self.searchPending then return end
    self:UpdatePositionDisplay()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local scanning = self.clientData.worldQueue ~= nil
    local worldChanged = self:StepClientWorldSync()
    if self:RefreshClientMap(mapID) or worldChanged then self:EnsureClientIndex(); self:Refresh(); return end
    if scanning then self:Render() end
    if mapID ~= self.lastMap then self:Refresh(); return end
    if not self.results or #self.results == 0 then return end
    local selected = self.results and self.results[self.selected or 1]
    selected = selected and selected.record.key
    if not self:UpdateDistances(self.results, true) then return end
    for i, entry in ipairs(self.results or {}) do
        if entry.record.key == selected then self.selected = i; break end
    end
    self:Render()
end

function M:CreateWindow()
    local s = self.settings
    self.scope, self.kind, self.category, self.view = s.scope, "all", "All", "directory"
    local function knownMap(id) return id > 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id) and id or nil end
    self.zoneMap, self.regionMap = knownMap(s.zoneMap), knownMap(s.regionMap)
    self.selected, self.offset = 1, 0
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(1120, 682)
    f:SetPoint("CENTER", UIParent, "CENTER", s.windowX, s.windowY)
    f:SetFrameStrata("HIGH")
    local faction = UnitFactionGroup("player")
    applyWindowBackdrop(f, faction)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local x, y = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local ratio = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
        if self:IsFinite(x) and self:IsFinite(ux) then
            s.windowX = math.floor(x - ux * ratio + 0.5)
            s.windowY = math.floor(y - uy * ratio + 0.5)
        end
    end)
    f:SetClampedToScreen(true)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 20, -14)
    icon:SetSize(32, 32)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    local title = label(f, "MONSTRATOR", 60, -14, 20)
    title:SetWidth(260)
    title:SetJustifyH("LEFT")
    title:SetMaxLines(1)
    local subtitle = label(f, "WoW Forever NPC & location directory - by Metalbullz", 60, -38, 11)
    subtitle:SetWidth(420)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.7, 0.72, 0.78)
    f.position = label(f, "", 500, -22, 12)
    f.position:SetWidth(420)
    f.position:SetMaxLines(1)
    f.position:SetJustifyH("RIGHT")
    f.position:SetTextColor(0.85, 0.86, 0.9)
    f.itemsButton = button(f, "Items", 930, -16, 68, function() self:ShowItemLookup() end)
    local helpButton = button(f, "Help", 1004, -16, 60, function() self:ShowHelp() end)
    button(f, "X", 1070, -16, 34, function() f:Hide() end)
    local headerRule = f:CreateTexture(nil, "BACKGROUND")
    headerRule:SetPoint("TOPLEFT", 16, -56)
    headerRule:SetSize(1088, 1)
    headerRule:SetColorTexture(0.55, 0.62, 0.72, 0.7)

    f.search = edit(f, 28, -68, 560)
    f.search:SetTextInsets(0, 24, 0, 0)
    f.searchHint = label(f.search, "Try a name, zone, food, repair, mail or flight", 4, -5, 12)
    f.searchHint:SetTextColor(0.65, 0.65, 0.65)
    local clearButton = button(f, "x", 562, -68, 26, function() f.search:SetText(""); f.search:SetFocus() end)
    f.search:SetMaxLetters(200)
    f.search:SetScript("OnTextChanged", function()
        f.searchHint:SetShown(f.search:GetText() == "" and not f.search:HasFocus())
        self.searchGeneration = (self.searchGeneration or 0) + 1
        local generation = self.searchGeneration
        self.searchPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                if generation ~= self.searchGeneration or not f:IsShown() then return end
                self.searchPending, self.offset = nil, 0
                self:Refresh()
            end)
        else self.searchPending = nil; self.offset = 0; self:Refresh() end
    end)
    f.search:SetScript("OnEditFocusGained", function() f.searchHint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function() f.searchHint:SetShown(f.search:GetText() == "") end)
    f.sort = button(f, "Sort", 600, -68, 200, function()
        local orders = { "distance", "zone", "name", "level", "npcID" }
        for i, order in ipairs(orders) do
            if self.settings.sortOrder == order then self.settings.sortOrder = orders[i % #orders + 1]; break end
        end
        self:Refresh()
    end)
    f.evidence = button(f, "Evidence", 808, -68, 232, function()
        local filters = { "all", "confirmed", "pending", "map", "reference" }
        for i, filter in ipairs(filters) do
            if self.settings.evidenceFilter == filter then self.settings.evidenceFilter = filters[i % #filters + 1]; break end
        end
        self.offset = 0
        self:Refresh()
    end)

    f.panels = {
        panel(f, "Browse", 16, -104, 232, 520),
        panel(f, "Results", 256, -104, 540, 520),
        panel(f, "Details", 804, -104, 300, 520),
    }
    f.resultsPanel, f.detailsPanel = f.panels[2], f.panels[3]
    f.filters = f.resultsPanel.heading
    f.filters:SetWidth(400)
    f.clearFilter = button(f, "Clear item filter", 670, -110, 118, function() self:SetNPCFilter(nil) end)
    f.clearFilter:Hide()
    self.focusOrder = { f.search, clearButton, f.sort, f.evidence }
    local function control(text, x, y, callback, width)
        local b = button(f, text, x, y, width or 208, callback)
        table.insert(self.focusOrder, b)
        b:SetScript("OnEnter", function() self.focusIndex = nil end)
        return b
    end
    local function section(text, y)
        local heading = label(f, text, 30, y, 11)
        heading:SetWidth(204)
        heading:SetJustifyH("LEFT")
        heading:SetTextColor(0.7, 0.72, 0.78)
        return heading
    end
    section("Search scope", -146)
    f.scopeButtons = {
        zone = control("Zone", 28, -162, function() self:SelectPlace("zone", self.zoneMap) end, 66),
        region = control("Region", 98, -162, function() self:SelectPlace("region", self.regionMap) end, 66),
        global = control("World", 168, -162, function() self:SelectPlace("global") end, 68),
    }
    f.placeButton = control("Choose zone or region", 28, -190, function() self:TogglePlacePicker() end)
    section("Lists", -226)
    f.viewButtons = {
        directory = control("Directory", 28, -242, function() self:ChangeView("directory") end),
        favorites = control("Favorites", 28, -270, function() self:ChangeView("favorites") end),
        review = control("Review journal", 28, -298, function() self:ChangeView("review") end),
    }
    section("Entry type", -330)
    f.kindButtons = {
        all = control("All entries", 28, -346, function() self.kind = "all"; self.category = "All"; self:UpdateCategories() end),
        npc = control("NPCs", 28, -374, function() self.kind = "npc"; self.category = "All"; self:UpdateCategories() end),
        location = control("Static locations", 28, -402, function() self.kind = "location"; self.category = "All"; self:UpdateCategories() end),
    }
    section("Categories", -434)
    f.categoryButtons, f.subgroupButtons = {}, {}
    for i = 1, 6 do
        local b = control("All", 28, -450 - (i - 1) * 28, function()
            self.category, self.subgroup = self.categories[self.kind][i], nil
            if f.subpicker then f.subpicker:Hide() end
            self:ChangeView("directory")
        end, 180)
        selectionMarker(b)
        f.categoryButtons[i] = b
        local more = control(">", 212, -450 - (i - 1) * 28, function()
            local category = self.categories[self.kind][i]
            if category then self:ToggleSubgroupPicker(category) end
        end, 24)
        more:SetScript("OnEnter", function(b)
            self.focusIndex = nil
            if GameTooltip then
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Sub-groups"])
                GameTooltip:AddLine(L["Narrow this category, e.g. Trainers > Fishing or Vendors > Weapons."], 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        more:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        f.subgroupButtons[i] = more
    end
    for _, group in ipairs({ f.scopeButtons, f.viewButtons, f.kindButtons }) do
        for _, b in pairs(group) do selectionMarker(b) end
    end

    local nameHeader = label(f, "Name", 274, -144, 11)
    nameHeader:SetTextColor(0.7, 0.72, 0.78)
    local distanceHeader = label(f, "Distance", 664, -144, 11)
    distanceHeader:SetWidth(92)
    distanceHeader:SetJustifyH("RIGHT")
    distanceHeader:SetTextColor(0.7, 0.72, 0.78)
    local evidenceColors = {
        confirmed = { 0.3, 0.9, 0.35 }, pending = { 1, 0.8, 0.2 }, map = { 0.65, 0.5, 1 }, reference = { 0.45, 0.65, 0.95 },
    }
    f.rows = {}
    for i = 1, 9 do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(500, 44)
        row:SetPoint("TOPLEFT", 264, -162 - (i - 1) * 46)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetColorTexture(faction == "Horde" and 0.55 or 0.2,
            faction == "Horde" and 0.18 or 0.38, faction == "Horde" and 0.18 or 0.65, 0.55)
        local separator = row:CreateTexture(nil, "BACKGROUND")
        separator:SetPoint("BOTTOMLEFT", 0, 0)
        separator:SetSize(500, 1)
        separator:SetColorTexture(0.55, 0.62, 0.72, 0.25)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.12)
        row:SetHighlightTexture(hover)
        row.badge = row:CreateTexture(nil, "ARTWORK")
        row.badge:SetPoint("TOPLEFT", 2, -6)
        row.badge:SetSize(3, 32)
        row.badge:SetColorTexture(0.6, 0.6, 0.6, 1)
        row.name = label(row, "", 12, -4)
        row.distance = label(row, "", 396, -5, 12)
        row.detail = label(row, "", 12, -24)
        row.name:SetWidth(380)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.distance:SetWidth(96)
        row.distance:SetMaxLines(1)
        row.distance:SetJustifyH("RIGHT")
        row.detail:SetWidth(482)
        row.detail:SetMaxLines(1)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetTextColor(0.76, 0.78, 0.84)
        row:SetScript("OnClick", function(b, mouse)
            if not b.entry then return end
            self.selected = b.index
            f.search:ClearFocus()
            self.focusIndex = nil
            if mouse == "RightButton" then
                if self.view == "review" or self.view == "journal" then self:ShowReview(b.entry.record)
                else self:ToggleFavorite(b.entry.record) end
            else self:Activate(b.entry) end
            self:Render()
        end)
        row:SetScript("OnEnter", function(b)
            if not b.entry then return end
            local r = b.entry.record
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(r.name)
            if r.title then GameTooltip:AddLine("<" .. r.title .. ">", 0.9, 0.82, 0.5) end
            local _, regionName = self:MapRegion(r.mapID)
            GameTooltip:AddLine(self:MapName(r.mapID) .. ", " .. regionName .. (L[" (%.1f, %.1f)"]):format(r.x, r.y), 1, 1, 1, true)
            GameTooltip:AddLine(L[r.category] .. " | " .. recordEvidenceName(r), 1, 1, 1, true)
            local entry = b.entry
            if entry.distance then GameTooltip:AddLine((L["%d yd"]):format(math.floor(entry.distance + 0.5)), 0.3, 1, 0.3)
            elseif entry.distanceLabel then GameTooltip:AddLine(entry.distanceLabel, 0.7, 0.7, 0.7) end
            if entry.placementCount and entry.placementCount > 1 then
                GameTooltip:AddLine((L["(%d locations)"]):format(entry.placementCount) .. " - " .. L["nearest shown"], 0.9, 0.82, 0.5)
            end
            if r.npcID then GameTooltip:AddLine(L["NPC ID "] .. r.npcID, 1, 1, 1) end
            GameTooltip:AddLine(r.source, 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine(L["Left: navigate/review. Right: favorite/review."], 0.6, 0.85, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = row
    end
    f.evidenceColors = evidenceColors
    f.empty = label(f, "", 296, -290, 14)
    f.empty:SetWidth(440)
    f.empty:SetHeight(150)
    f.empty:SetJustifyH("CENTER")
    f.empty:SetJustifyV("MIDDLE")
    local function scrollRows(delta)
        self.offset = math.max(0, math.min(math.max(0, #(self.results or {}) - #f.rows), self.offset + delta))
        self:Render()
    end
    f.pageUp = control("^", 768, -162, function() scrollRows(-#f.rows) end, 22)
    f.pageDown = control("v", 768, -548, function() scrollRows(#f.rows) end, 22)
    f.picker = self:CreatePlacePicker(f)
    f.subpicker = self:CreateSubgroupPicker(f)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        scrollRows(-delta * 3)
    end)
    f.page = label(f, "", 274, -590, 11)
    f.page:SetWidth(480)
    f.page:SetJustifyH("LEFT")
    f.page:SetTextColor(0.7, 0.72, 0.78)

    f.info = {}
    f.info.name = label(f, "", 818, -146, 16)
    f.info.name:SetWidth(272)
    f.info.name:SetMaxLines(2)
    f.info.name:SetJustifyH("LEFT")
    f.info.title = label(f, "", 818, -190, 12)
    f.info.title:SetWidth(272)
    f.info.title:SetMaxLines(1)
    f.info.title:SetJustifyH("LEFT")
    f.info.title:SetTextColor(0.9, 0.82, 0.5)
    f.info.body = label(f, "", 818, -212, 12)
    f.info.body:SetWidth(272)
    f.info.body:SetHeight(196)
    f.info.body:SetJustifyH("LEFT")
    f.info.body:SetJustifyV("TOP")
    f.info.body:SetTextColor(0.88, 0.89, 0.93)
    f.info.navigate = control("Navigate", 818, -414, function()
        self:Activate(self.results and self.results[self.selected])
    end, 132)
    f.info.favorite = control("Favorite", 958, -414, function()
        local entry = self.results and self.results[self.selected]
        if entry then self:ToggleFavorite(entry.record); self:Render() end
    end, 132)
    f.detailsButton = control("Entry details", 818, -444, function()
        self:ShowEntryDetails(self.results and self.results[self.selected])
    end, 132)
    f.info.zone = control("Browse this zone", 958, -444, function() self:BrowseRecordPlace() end, 132)
    f.info.model = control("3D model", 818, -474, function() self:ShowSelectedModel() end, 132)
    f.info.items = control("Items sold/dropped", 958, -474, function() self:ShowNPCItems() end, 132)
    f.info.watch = control("Watch for this NPC", 818, -504, function()
        local entry = self.results and self.results[self.selected]
        local r = entry and entry.record
        if r and r.npcID then self:ToggleWatch(r.npcID, r.name) end
    end, 272)
    f.coverage = label(f, "", 818, -534, 11)
    f.coverage:SetWidth(272)
    f.coverage:SetHeight(30)
    f.coverage:SetJustifyH("LEFT")
    f.coverage:SetTextColor(0.7, 0.72, 0.78)
    f.onboarding = label(f, "", 818, -566, 11)
    f.onboarding:SetWidth(272)
    f.onboarding:SetHeight(60)
    f.onboarding:SetJustifyH("LEFT")
    f.onboarding:SetTextColor(0.7, 0.72, 0.78)

    local footerRule = f:CreateTexture(nil, "BACKGROUND")
    footerRule:SetPoint("TOPLEFT", 16, -632)
    footerRule:SetSize(1088, 1)
    footerRule:SetColorTexture(0.55, 0.62, 0.72, 0.7)
    f.captureButton = control("Capture NPC target", 16, -644, function() self:CaptureNPC("manual-target") end, 160)
    f.scanButton = control("Scan world maps", 182, -644, function() SlashCmdList.MONSTRATOR("sync world") end, 150)
    control("NPC inventory", 338, -644, function() self:ShowNPCInventory() end, 130)
    control("Settings", 474, -644, function() self:ShowSettings() end, 100)
    f.scanWindowButton = control("NPC scan", 580, -644, function() self:ToggleScanWindow() end, 100)
    f.footer = label(f, "", 690, -650, 12)
    f.footer:SetWidth(414)
    f.footer:SetJustifyH("RIGHT")
    f.resultFocus = control("Focus", 1046, -68, function()
        self.focusIndex = nil
        f.search:ClearFocus()
        self:Render()
    end, 58)
    table.insert(self.focusOrder, helpButton)
    local function focusNext()
        f.search:ClearFocus()
        local delta = IsShiftKeyDown() and -1 or 1
        local index = self.focusIndex or 1
        repeat
            index = (index + delta - 1) % #self.focusOrder + 1
        until self.focusOrder[index]:IsShown()
        self.focusIndex = index
        local target = self.focusOrder[index]
        if target == f.search then target:SetFocus()
        else target:LockHighlight() end
        for _, b in ipairs(self.focusOrder) do
            if b ~= target and b.UnlockHighlight then b:UnlockHighlight() end
        end
    end
    f.search:SetScript("OnTabPressed", focusNext)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(_, key)
        if (self.options and self.options:IsShown()) or (self.reviewFrame and self.reviewFrame:IsShown())
            or (self.copyFrame and self.copyFrame:IsShown()) or (self.detailsFrame and self.detailsFrame:IsShown())
            or (self.itemFrame and self.itemFrame:IsShown()) or (self.modelFrame and self.modelFrame:IsShown()) then
            f:SetPropagateKeyboardInput(true)
            return
        end
        local handled = true
        if key == "ESCAPE" and f.picker:IsShown() then f.picker:Hide()
        elseif key == "ESCAPE" and f.subpicker:IsShown() then f.subpicker:Hide()
        elseif key == "ESCAPE" then f:Hide()
        elseif key == "TAB" then
            if f.search:HasFocus() then handled = false else focusNext() end
        elseif key == "ENTER" and f.search:HasFocus() then
            handled = false
        elseif key == "ENTER" and self.focusIndex and self.focusIndex > 1 then
            if self.focusOrder[self.focusIndex] == f.resultFocus then
                self:Activate(self.results and self.results[self.selected])
            else self.focusOrder[self.focusIndex]:Click() end
        elseif key == "ENTER" then
            f.search:ClearFocus()
            self:Activate(self.results and self.results[self.selected])
        elseif (key == "UP" or key == "DOWN") and not f.search:HasFocus() then
            self.focusIndex = nil
            self.selected = math.max(1, math.min(#(self.results or {}), self.selected + (key == "UP" and -1 or 1)))
            if self.selected <= self.offset then self.offset = self.selected - 1 end
            if self.selected > self.offset + #f.rows then self.offset = self.selected - #f.rows end
            self:Render()
        else handled = false end
        f:SetPropagateKeyboardInput(not handled)
    end)
    f.search:SetScript("OnEnterPressed", function() f.search:ClearFocus(); self:Activate(self.results[self.selected]) end)
    f:SetScript("OnShow", function()
        self.searchPending = nil
        if self.scope ~= "zone" then self:StartClientWorldSync() end
        self:Refresh()
        self:UpdatePositionDisplay()
        self:StartRefresh()
    end)
    f:SetScript("OnHide", function()
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        f:SetScript("OnUpdate", nil)
        self.searchGeneration = (self.searchGeneration or 0) + 1
        self.searchPending = nil
        f.search:ClearFocus()
        f.picker:Hide()
        f.subpicker:Hide()
        GameTooltip:Hide()
    end)
    self.window = f
    f:Hide()
    self:UpdateCategories()
end

function M:BreadcrumbText()
    if self.view ~= "directory" then return L[self.view] .. " - " .. L[self.scope] end
    if self.npcFilter then return "|cffd6a64b" .. self.npcFilter.label .. "|r  /  " .. self:PlaceName() end
    return self:PlaceName() .. "  /  " .. L[self.kind] .. "  /  " .. L[self.category]
        .. (self:ActiveSubgroup() and ("  /  " .. L[self:ActiveSubgroup().label]) or "")
end

function M:SetNPCFilter(ids, label)
    self.npcFilter = ids and { ids = ids, label = label } or nil
    if not self.window then self:CreateWindow() end
    self.window:SetScale(self.settings.frameScale)
    self.window:Show()
    if ids then
        self.kind, self.category = "npc", "All"
        self.window.search:SetText("")
        self.searchPending = nil
        self.scope = "global"
        if self.window.picker then self.window.picker:Hide() end
        self:StartClientWorldSync()
        self.offset, self.selected = 0, 1
        self:UpdateCategories()
    else
        self.offset, self.selected = 0, 1
        self:ChangeView("directory")
    end
end

function M:SelectPlace(scope, id)
    self.scope = scope
    if scope == "zone" then self.zoneMap = id
    elseif scope == "region" then self.regionMap = id end
    if scope ~= "zone" then self:StartClientWorldSync() end
    if self.window and self.window.picker then self.window.picker:Hide() end
    self.offset, self.selected = 0, 1
    self:ChangeView("directory")
end

function M:PlacePickerRows(filter)
    filter = string.lower(filter or "")
    local playerMap = self:PlayerMap()
    local rows = {
        { scope = "zone", text = (L["Follow my position (%s)"]):format(playerMap and self:MapName(playerMap) or "?"),
          active = self.scope == "zone" and not self.zoneMap, header = true },
        { scope = "global", text = L["Whole world"], active = self.scope == "global", header = true },
    }
    for _, region in ipairs(self:ZoneCatalog()) do
        local regionMatch = filter == "" or region.name:lower():find(filter, 1, true)
        local zones = {}
        for _, zone in ipairs(region.zones) do
            if regionMatch or zone.name:lower():find(filter, 1, true) then table.insert(zones, zone) end
        end
        if #zones > 0 then
            local regionID = region.id
            table.insert(rows, { scope = "region", id = regionID, header = true, name = region.name,
                text = (L["%s  |cff9aa3b5(%d zones, %d)|r"]):format(region.name, #region.zones, region.count),
                active = self.scope == "region" and self:ScopeRegion() == regionID })
            for _, zone in ipairs(zones) do
                local here = zone.id == playerMap and " |cff7fd07f" .. L["(you are here)"] .. "|r" or ""
                table.insert(rows, { scope = "zone", id = zone.id, name = zone.name,
                    text = ("    %s  |cff9aa3b5(%d)|r%s"):format(zone.name, zone.count, here),
                    active = self.scope == "zone" and self.zoneMap == zone.id })
            end
        end
    end
    return rows
end

-- Shared overlay used by the place and sub-group pickers: it covers the results panel with a filter box,
-- a scrolling list of rows and a status line. `onPick(data)` runs when a row is clicked.
local function createOverlay(self, f, headingText, hintText, onPick, render)
    local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
    p:SetPoint("TOPLEFT", 256, -104)
    p:SetSize(540, 520)
    -- Own strata so the overlay always draws and receives clicks above the result rows.
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    p:SetFrameLevel(f:GetFrameLevel() + 20)
    applyWindowBackdrop(p)
    local shade = p:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", 4, -4)
    shade:SetPoint("BOTTOMRIGHT", -4, 4)
    if UnitFactionGroup("player") == "Horde" then shade:SetColorTexture(0.1, 0.03, 0.03, 1)
    else shade:SetColorTexture(0.02, 0.045, 0.09, 1) end
    p:EnableMouse(true)
    p.heading = label(p, headingText, 14, -12, 14)
    p.heading:SetWidth(440)
    p.heading:SetJustifyH("LEFT")
    button(p, "X", 496, -8, 32, function() p:Hide() end)
    p.filter = edit(p, 20, -38, 500)
    p.filterHint = label(p.filter, hintText, 4, -5, 12)
    p.filterHint:SetTextColor(0.65, 0.65, 0.65)
    p.filter:SetScript("OnTextChanged", function()
        p.filterHint:SetShown(p.filter:GetText() == "")
        p.offset = 0
        if p:IsShown() then render(true) end
    end)
    p.filter:SetScript("OnEscapePressed", function() p:Hide() end)
    p.rows = {}
    for i = 1, 17 do
        local row = CreateFrame("Button", nil, p)
        row:SetSize(500, 24)
        row:SetPoint("TOPLEFT", 20, -70 - (i - 1) * 25)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.12)
        row:SetHighlightTexture(hover)
        row.text = label(row, "", 8, -5, 12)
        row.text:SetWidth(484)
        row.text:SetMaxLines(1)
        row.text:SetJustifyH("LEFT")
        selectionMarker(row)
        row:SetScript("OnClick", function(b) if b.data and not b.data.section then onPick(b.data) end end)
        p.rows[i] = row
    end
    p.status = label(p, "", 20, -500, 11)
    p.status:SetWidth(500)
    p.status:SetJustifyH("LEFT")
    p.status:SetTextColor(0.7, 0.72, 0.78)
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        p.offset = math.max(0, math.min(math.max(0, #(p.data or {}) - #p.rows), (p.offset or 0) - delta * 3))
        render()
    end)
    p:Hide()
    return p
end

local function renderOverlayRows(p)
    p.offset = math.max(0, math.min(p.offset or 0, math.max(0, #p.data - #p.rows)))
    for i, row in ipairs(p.rows) do
        local data = p.data[p.offset + i]
        row.data = data
        row:SetShown(data ~= nil)
        if data then
            row.text:SetText(data.text)
            if data.section then row.text:SetTextColor(0.7, 0.72, 0.78)
            elseif data.header then row.text:SetTextColor(1, 0.82, 0.25)
            else row.text:SetTextColor(0.9, 0.91, 0.95) end
            row.activeMarker:SetShown(data.active == true)
        end
    end
end

function M:CreatePlacePicker(f)
    local p = createOverlay(self, f, "Choose zone or region", "Filter zones, e.g. barrens or kalimdor",
        function(data) self:SelectPlace(data.scope, data.id) end,
        function(rebuild) self:RenderPlacePicker(rebuild) end)
    p.filter:SetScript("OnEnterPressed", function()
        local filter = p.filter:GetText():lower()
        if filter == "" then return end
        -- Prefer a zone whose own name matches; otherwise the matching region itself.
        local zone, region
        for _, data in ipairs(p.data or {}) do
            local name = data.id and data.name and data.name:lower()
            if name and name:find(filter, 1, true) then
                if data.scope == "zone" and not zone then zone = data end
                if data.scope == "region" and not region then region = data end
            end
        end
        local first = zone or region
        if first then self:SelectPlace(first.scope, first.id) end
    end)
    return p
end

-- Rows for the sub-group picker of one category: an "All" row, then section headings and every
-- sub-group that has results in the current scope and search (the active one is always listed).
function M:SubgroupPickerRows(category, filter)
    filter = string.lower(filter or "")
    local counts = self.directoryCounts or { categories = {}, subgroups = {} }
    local subcounts = counts.subgroups or {}
    local total = (counts.categories[self.kind] or {})[category] or 0
    local rows = { { text = (L["All %s"]):format(L[category]) .. "  |cff9aa3b5(" .. total .. ")|r", header = true,
        active = self.category == category and not self:ActiveSubgroup(self.kind, category), category = category } }
    local section
    for _, def in ipairs(self.subgroups[self.kind .. ":" .. category] or {}) do
        if def.section then section = { text = L[def.section], section = true }
        else
            local amount = subcounts[def.key] or 0
            local active = self.subgroup == def.key and self.category == category
            local name = L[def.label]
            if (amount > 0 or active) and (filter == "" or name:lower():find(filter, 1, true)
                or def.key:find(filter, 1, true) or (section and section.text:lower():find(filter, 1, true))) then
                if section then table.insert(rows, section); section = nil end
                table.insert(rows, { key = def.key, category = category, name = name, active = active,
                    text = "    " .. name .. "  |cff9aa3b5(" .. amount .. ")|r" })
            end
        end
    end
    return rows
end

function M:CreateSubgroupPicker(f)
    local p = createOverlay(self, f, "Choose a sub-group", "Filter, e.g. fishing or blacksmith",
        function(data) self:SelectSubgroup(data.category, data.key) end,
        function(rebuild) self:RenderSubgroupPicker(rebuild) end)
    p.filter:SetScript("OnEnterPressed", function()
        for _, data in ipairs(p.data or {}) do
            if data.key then self:SelectSubgroup(data.category, data.key); return end
        end
    end)
    return p
end

function M:RenderSubgroupPicker(rebuild)
    local p = self.window and self.window.subpicker
    if not p or not p.category then return end
    if rebuild or not p.data then p.data = self:SubgroupPickerRows(p.category, p.filter:GetText()) end
    renderOverlayRows(p)
    local groups = 0
    for _, data in ipairs(p.data) do if data.key then groups = groups + 1 end end
    p.status:SetText(groups == 0 and L["No sub-group has results here. Try a wider scope or clear the search."]
        or (L["%d sub-groups | Mouse wheel scrolls | Enter picks the first match"]):format(groups))
end

function M:ToggleSubgroupPicker(category)
    local f = self.window
    local p = f and f.subpicker
    if not p then return end
    if p:IsShown() and p.category == category then p:Hide(); return end
    f.picker:Hide()
    p.category, p.offset, p.data = category, 0, nil
    p.heading:SetText((L["%s: choose a sub-group"]):format(L[category]))
    p.filter:SetText("")
    p:Show()
    self:RenderSubgroupPicker(true)
    p.filter:SetFocus()
end

function M:SelectSubgroup(category, key)
    self.category, self.subgroup = category, key
    if self.window and self.window.subpicker then self.window.subpicker:Hide() end
    self.offset, self.selected = 0, 1
    self:ChangeView("directory")
end

-- /monstrator find TEXT: open the matching sub-group (widening to the whole world when the current place has
-- none), or fall back to a plain search.
function M:JumpToSubgroup(text)
    if not self.window then self:CreateWindow() end
    self.window:SetScale(self.settings.frameScale)
    self.window:Show()
    local def = self:FindSubgroup(text)
    if not def then
        self.window.search:SetText(text or "")
        self:Notice((L["No sub-group matches \"%s\"; searching for it instead."]):format(text or ""))
        return
    end
    self.npcFilter = nil
    self.kind = def.kind
    self:UpdateCategories()
    self.window.search:SetText("")
    self.searchPending = nil
    self:SelectSubgroup(def.category, def.key)
    if #(self.results or {}) == 0 and self.scope ~= "global" then self:SelectPlace("global") end
    self:Notice((L["Showing %s."]):format(L[def.category] .. ": " .. L[def.label]))
end
function M:RenderPlacePicker(rebuild)
    local p = self.window and self.window.picker
    if not p then return end
    if rebuild or not p.data then p.data = self:PlacePickerRows(p.filter:GetText()) end
    renderOverlayRows(p)
    local zones = 0
    for _, data in ipairs(p.data) do if data.scope == "zone" and data.id then zones = zones + 1 end end
    local status = zones == 0 and (p.filter:GetText() ~= "" and L["No zone or region matches this filter."]
        or L["No zone data yet - the database may still be indexing."])
        or (L["%d zones | Mouse wheel scrolls | Enter picks the first match"]):format(zones)
    p.status:SetText(status)
end

function M:TogglePlacePicker()
    local p = self.window and self.window.picker
    if not p then return end
    if p:IsShown() then p:Hide(); return end
    if self.window.subpicker then self.window.subpicker:Hide() end
    p.offset = 0
    p.filter:SetText("")
    p:Show()
    p.data = self:PlacePickerRows("")
    for i, data in ipairs(p.data) do
        if data.active and data.id then p.offset = math.max(0, i - math.floor(#p.rows / 2)); break end
    end
    self:RenderPlacePicker()
    p.filter:SetFocus()
end

function M:JumpToPlace(scope, name)
    name = string.lower(name or "")
    if not self.window then self:CreateWindow() end
    if name == "" then
        self.window:Show()
        self:SelectPlace(scope, nil)
        return
    end
    local best
    for _, region in ipairs(self:ZoneCatalog()) do
        if scope == "region" then
            local text = region.name:lower()
            if text == name then best = region; break end
            if not best and text:find(name, 1, true) then best = region end
        else
            for _, zone in ipairs(region.zones) do
                local text = zone.name:lower()
                if text == name then best = zone; break end
                if not best and text:find(name, 1, true) then best = zone end
            end
            if best and best.name:lower() == name then break end
        end
    end
    if not best then self:Error((L["No %s with data matches \"%s\"."]):format(scope, name)); return end
    self.window:Show()
    self:SelectPlace(scope, best.id)
    self:Notice((L["Showing %s."]):format(best.name))
end

function M:RenderWatchButton()
    local f = self.window
    local entry = self.results and self.results[self.selected or 1]
    local r = entry and entry.record
    local watch = f and f.info and f.info.watch
    if not watch then return end
    watch:SetShown(r ~= nil and r.npcID ~= nil)
    if r and r.npcID then
        watch:SetText(L[self.settings.scanWatch[r.npcID] and "Stop watching (NPC scan)" or "Watch for this NPC"])
    end
end

function M:RenderDetailsPane()
    local f = self.window
    local entry = self.results and self.results[self.selected or 1]
    local r = entry and entry.record
    local yards = entry and entry.distance and math.floor(entry.distance + 0.5)
    local favorite = r and self.favorites.entries[r.key] ~= nil
    local info = f.info
    local placeKey = self.scope .. ":" .. tostring(self:ScopeMap())
    if info.renderKey == (r and r.key) and info.renderYards == yards and info.renderFavorite == favorite
        and info.renderLabel == (entry and entry.distanceLabel) and info.renderStale == (entry and entry.stale)
        and info.renderPlacements == (entry and entry.placementCount) and info.renderPlace == placeKey then return end
    info.renderKey, info.renderYards, info.renderFavorite = r and r.key, yards, favorite
    info.renderLabel, info.renderStale = entry and entry.distanceLabel, entry and entry.stale
    info.renderPlacements, info.renderPlace = entry and entry.placementCount, placeKey
    for _, control in ipairs({ info.navigate, info.favorite, info.zone, f.detailsButton }) do control:SetShown(r ~= nil) end
    info.model:SetShown(r ~= nil and r.npcID ~= nil)
    info.items:SetShown(r ~= nil and r.npcID ~= nil and self:ItemProvider() ~= nil)
    self:RenderWatchButton()
    if not r then
        info.name:SetText(L["Nothing selected"])
        info.title:SetText("")
        info.body:SetText(L["Select a result to see its location, identity and evidence. Left-click navigates, right-click saves a favorite."])
        return
    end
    local map = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
    local _, regionName = self:MapRegion(r.mapID)
    info.name:SetText(r.name)
    info.title:SetText(r.title and ("<" .. r.title .. ">") or L[r.category])
    local lines = {
        (map and map.name or (L["Map %d"]):format(r.mapID)) .. ", " .. regionName,
        ("|cffd6a64b%.1f, %.1f|r  -  "):format(r.x, r.y)
            .. (yards and ("%d yards away"):format(yards) or (entry.distanceLabel or L["Distance unavailable"])),
        "",
        L[r.kind] .. " / " .. L[r.category] .. " | " .. L[r.faction or "Both"],
    }
    if r.npcID then
        local extra = {}
        if r.level then table.insert(extra, L["Level "] .. (r.level < 1 and "??" or r.level)) end
        if r.classification and r.classification ~= "normal" and r.classification ~= "minus" then
            table.insert(extra, r.classification)
        end
        if r.creatureType then table.insert(extra, r.creatureType) end
        table.insert(lines, L["NPC ID"] .. " " .. r.npcID .. (#extra > 0 and (" | " .. table.concat(extra, ", ")) or ""))
    end
    if r.objectID then table.insert(lines, L["Object ID "] .. r.objectID) end
    if entry.placementCount and entry.placementCount > 1 then
        table.insert(lines, (L["(%d locations)"]):format(entry.placementCount) .. " - " .. L["nearest shown"])
    end
    if r.tags and #r.tags > 0 then table.insert(lines, L["Tags: "] .. table.concat(r.tags, ", ")) end
    table.insert(lines, "")
    table.insert(lines, "Evidence: " .. (entry.stale and L["Stale favorite"] or recordEvidenceName(r)))
    if r.nativeOrigin then table.insert(lines, L["nativeOrigin." .. r.nativeOrigin]) end
    table.insert(lines, ("|cff8f949e/way #%d %.1f %.1f|r"):format(r.mapID, r.x, r.y))
    info.body:SetText(table.concat(lines, "\n"))
    info.favorite:SetText(L[favorite and "Remove favorite" or "Favorite"])
    local zoneText = (self.scope == "zone" and self:ScopeMap() == r.mapID) and L["Browse region"] or L["Browse this zone"]
    if info.zone.renderText ~= zoneText then info.zone:SetText(zoneText); info.zone.renderText = zoneText end
end

function M:ResetView()
    local s = self.settings
    s.scope, s.zoneMap, s.regionMap, s.windowX, s.windowY = "zone", 0, 0, 0, 0
    s.sortOrder, s.evidenceFilter = "distance", "all"
    self.npcFilter = nil
    if self.window then
        local f = self.window
        self.scope, self.zoneMap, self.regionMap, self.kind, self.category = "zone", nil, nil, "all", "All"
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f.picker:Hide()
        f.search:SetText("")
        self:UpdateCategories()
    end
    self:Notice(L["Window position, scope and filters reset."])
end

function M:BrowseRecordPlace()
    local entry = self.results and self.results[self.selected or 1]
    local r = entry and entry.record
    if not r then return end
    if self.scope == "zone" and self:ScopeMap() == r.mapID then
        local regionID = self:MapRegion(r.mapID)
        self:SelectPlace("region", regionID > 0 and regionID or nil)
    else self:SelectPlace("zone", r.mapID) end
end

function M:UpdateCategories()
    for i, b in ipairs(self.window.categoryButtons) do
        local category = self.categories[self.kind][i]
        b:SetShown(category ~= nil)
        if category then b:SetText(L[category]); b.renderText = nil end
        self.window.subgroupButtons[i]:SetShown(category ~= nil and self.subgroups[self.kind .. ":" .. category] ~= nil)
    end
    self.subgroup = nil
    self.window.subpicker:Hide()
    self.window.renderScope = nil
    self:ChangeView("directory")
end

function M:Toggle(view)
    if not self.window then self:CreateWindow() end
    self.window:SetScale(self.settings.frameScale)
    if view then self.window:Show(); self:ChangeView(view)
    else self.window:SetShown(not self.window:IsShown()) end
end

function M:DataSourceSummary()
    local q = self.dbIndex
    local text
    local label = L[self:DataSourceLabel()]
    if q and q.ready then
        text = (L["Data: %s %d NPCs / %d zones"]):format(label, q.npcCount, q.mapCount)
    elseif q and q.ids then
        text = (L["Data: %s indexing %d%%"]):format(label, math.floor((q.nextIndex - 1) * 100 / math.max(1, #q.ids)))
    else
        text = L["Data: your discoveries only"]
    end
    local markers = 0
    for _, map in pairs(self.clientData and self.clientData.maps or {}) do markers = markers + #map.entries end
    if markers > 0 then text = text .. (L[" + %d map markers"]):format(markers) end
    return text
end

function M:CreateLauncher()
    -- Standard round minimap button: tracking-ring border, dark disc background and a masked icon.
    local b = CreateFrame("Button", "MonstratorMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", 0, 0)
    b.icon, b.border = icon, border
    b:SetScript("OnMouseDown", function() icon:SetTexCoord(0.15, 0.85, 0.15, 0.85) end)
    b:SetScript("OnMouseUp", function() icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then self:Toggle("favorites") else self:Toggle() end
    end)
    local function position()
        local angle = math.rad(self.settings.minimapAngle)
        local radius = ((Minimap:GetWidth() or 140) / 2) + 10
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end
    b:SetScript("OnDragStart", function()
        b:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            self.settings.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
            position()
        end)
    end)
    b:SetScript("OnDragStop", function()
        b:SetScript("OnUpdate", nil)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText("Monstrator")
        GameTooltip:AddLine(self:DataSourceSummary(), 0.85, 0.82, 0.6, true)
        GameTooltip:AddLine(L["Left: directory. Right: favorites. Drag: move."], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    position()
    b:SetShown(not self.settings.minimapHidden)
    self.launcher = b
end

M.Widgets = { label = label, button = button, edit = edit, panel = panel, backdrop = applyWindowBackdrop,
    escapeCloses = escapeCloses, marker = selectionMarker }

