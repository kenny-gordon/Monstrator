local _, M = ...
local L = M.L
local backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
    tileSize = 16, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 },
}
local insetBackdrop = {
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 256, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function applyWindowBackdrop(frame, inset)
    frame:SetBackdrop(inset and insetBackdrop or backdrop)
    -- The dialog background texture is translucent; a solid layer keeps windows behind from showing through.
    if not frame.solidBackground then
        frame.solidBackground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame.solidBackground:SetPoint("TOPLEFT", 4, -4)
        frame.solidBackground:SetPoint("BOTTOMRIGHT", -4, 4)
    end
    frame.solidBackground:SetColorTexture(0.035, 0.03, 0.025, 1)
    frame:SetBackdropColor(inset and 0.7 or 0.08, inset and 0.6 or 0.07, inset and 0.45 or 0.055, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
end

local categoryIcons = {
    Services = "INV_Misc_GroupLooking", Vendors = "INV_Misc_Coin_01",
    Trainers = "INV_Misc_Book_09", Transit = "Ability_Mount_Wyvern_01",
    Combat = "Ability_Tracking", Mailboxes = "INV_Letter_15",
    Instances = "INV_Misc_StoneTablet_05", Landmarks = "INV_Misc_Map02",
    Objects = "INV_Box_01",
}
local browseShortcuts = {
    { "all", "All" }, { "npc", "Services" }, { "npc", "Vendors" },
    { "npc", "Trainers" }, { "npc", "Transit" }, { "location", "Objects" },
}

function M:BrowseCategory(index)
    if self.kind == "all" then
        local shortcut = browseShortcuts[index]
        if shortcut then return shortcut[1], shortcut[2] end
    else
        return self.kind, self.categories[self.kind][index]
    end
end
local professionIcons = {
    alchemy = "Trade_Alchemy", blacksmithing = "Trade_BlackSmithing",
    enchanting = "Trade_Engraving", engineering = "Trade_Engineering",
    leatherworking = "Trade_LeatherWorking", tailoring = "Trade_Tailoring",
    herbalism = "Trade_Herbalism", mining = "Trade_Mining", skinning = "INV_Misc_Pelt_Wolf_01",
    cooking = "INV_Misc_Food_15", first_aid = "Spell_Holy_SealOfSacrifice",
    fishing = "Trade_Fishing",
}
local herbIcons = {
    [1617] = "INV_Misc_Herb_10", [1618] = "INV_Misc_Flower_02",
    [1619] = "INV_Misc_Herb_07", [1620] = "INV_Jewelry_Talisman_03",
    [1621] = "INV_Misc_Root_01", [1622] = "INV_Misc_Herb_11",
}
local tagIcons = {
    { "innkeeper", "INV_Misc_Rune_01" }, { "bank", "INV_Misc_Bag_10" },
    { "flight", "Ability_Mount_Wyvern_01" }, { "stable", "Ability_Mount_RidingHorse" },
    { "guild", "INV_Shirt_GuildTabard_01" }, { "tabard", "INV_Shirt_GuildTabard_01" },
    { "auction", "INV_Misc_Coin_02" }, { "repair", "Trade_BlackSmithing" },
    { "mailbox", "INV_Letter_15" }, { "herb", "Trade_Herbalism" },
    { "ore", "Trade_Mining" }, { "fishing", "Trade_Fishing" },
    { "anvil", "Trade_BlackSmithing" }, { "forge", "Trade_BlackSmithing" },
    { "chest", "INV_Box_01" }, { "cooking", "Trade_Cooking" },
    { "quest_object", "INV_Misc_Note_01" },
    { "food", "INV_Misc_Food_11" }, { "drink", "INV_Drink_07" },
    { "boat", "INV_Misc_Map02" },
    { "quest_giver", "INV_Misc_Note_01" },
}

function M:EntryIcon(record)
    if record.kind == "location" then
        for _, tag in ipairs(record.tags or {}) do
            if tag == "herb" and herbIcons[record.objectID] then
                return "Interface\\Icons\\" .. herbIcons[record.objectID]
            end
        end
    end
    if record.category == "Trainers" then
        for _, key in ipairs(self:RecordSubgroups(record)) do
            local profession = key:match("^trainer:(.+)$")
            if professionIcons[profession] then return "Interface\\Icons\\" .. professionIcons[profession] end
        end
    end
    for _, icon in ipairs(tagIcons) do
        for _, tag in ipairs(record.tags or {}) do
            if tag == icon[1] then return "Interface\\Icons\\" .. icon[2] end
        end
    end
    return "Interface\\Icons\\" .. (categoryIcons[record.category]
        or (record.kind == "npc" and "Ability_Tracking" or "INV_Misc_Map02"))
end

local missingIcons = {}
local function setStaticIcon(texture, icon)
    if texture:SetTexture(icon) == false then
        if not missingIcons[icon] then
            missingIcons[icon] = true
            M:Error((L["Icon asset unavailable: %s"]):format(tostring(icon)))
        end
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

local function portraitCall(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok then M:Error(tostring(value)); return end
    return value, true
end

local function artworkStyle(texture, portrait)
    if texture.isPortrait == portrait then return end
    texture.isPortrait = portrait
    if texture.portraitTexture then
        texture:SetShown(not portrait)
        texture.portraitTexture:SetShown(portrait)
        if portrait then
            -- Crop inside the client portrait's circular image so square corners contain artwork.
            texture.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
        end
    end
    if texture.slotBorder then texture.slotBorder:Show() end
    texture:SetTexCoord(portrait and 0 or 0.07, portrait and 1 or 0.93,
        portrait and 0 or 0.07, portrait and 1 or 0.93)
end

local function paintPortrait(texture, displayID)
    local artwork = texture.portraitTexture or texture
    local _, ok = portraitCall(SetPortraitTextureFromCreatureDisplayID, artwork, displayID)
    if ok then
        artworkStyle(texture, true)
        texture.portraitDisplayID = displayID
        texture.portraitUnitGUID = nil
    end
end

local function resolvePortrait()
    local state = M.portraits
    if state.busy then return end
    local job
    while true do
        job = table.remove(state.queue, 1)
        if not job then return end
        local active = false
        for texture in pairs(job.textures) do
            if texture.portraitNPC == job.id then active = true; break end
        end
        if active then break end
        state.pending[job.id] = nil
    end
    state.busy = true
    local modelLoaded = false
    portraitCall(state.model.ClearModel, state.model)
    state.model:SetScript("OnModelLoaded", function() modelLoaded = true end)
    state.model:Show()
    local _, started = portraitCall(state.model.SetCreature, state.model, job.id)
    local attempts = 0
    local function finish(displayID)
        if not state.cache[job.id] then
            table.insert(state.cacheOrder, job.id)
            if #state.cacheOrder > 256 then state.cache[table.remove(state.cacheOrder, 1)] = nil end
        end
        state.cache[job.id] = { displayID = displayID, time = GetTime() }
        for texture in pairs(job.textures) do
            if displayID and texture.portraitNPC == job.id and not texture.portraitUnitGUID then
                paintPortrait(texture, displayID)
            end
        end
        state.pending[job.id], state.busy = nil, false
        state.model:SetScript("OnModelLoaded", nil)
        state.model:Hide()
        C_Timer.After(0, resolvePortrait)
    end
    local function loaded()
        attempts = attempts + 1
        local displayID, ok = portraitCall(state.model.GetDisplayInfo, state.model)
        if modelLoaded and ok and M:IsFinite(displayID) and displayID > 0 and displayID % 1 == 0 then
            finish(displayID)
        elseif ok and attempts < 6 then
            if not modelLoaded then
                if attempts == 1 then M:PrimeCreature(job.id) end
                portraitCall(state.model.SetCreature, state.model, job.id)
            end
            C_Timer.After(0.2, loaded)
        else
            finish()
        end
    end
    if started then C_Timer.After(0.1, loaded) else finish() end
end

function M:SetEntryArtwork(texture, record)
    local icon = self:EntryIcon(record)
    local npcID = record.kind == "npc" and record.npcID or nil
    if texture.entryIcon ~= icon or texture.portraitNPC ~= npcID then
        setStaticIcon(texture, icon)
        artworkStyle(texture, false)
        texture.entryIcon, texture.portraitNPC = icon, npcID
        texture.portraitDisplayID = nil
        texture.portraitUnitGUID = nil
    end
    if not self:IsFinite(npcID) or npcID < 1 or npcID % 1 ~= 0 then return end
    if SetPortraitTexture and UnitGUID then
        for _, unit in ipairs({ "target", "mouseover" }) do
            local guid = UnitGUID(unit)
            if not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" then
                local kind, _, _, _, _, id = strsplit("-", guid)
                if (kind == "Creature" or kind == "Vehicle") and tonumber(id) == npcID then
                    local _, ok = portraitCall(SetPortraitTexture, texture.portraitTexture or texture, unit)
                    if ok then
                        artworkStyle(texture, true)
                        texture.portraitDisplayID = nil
                        texture.portraitUnitGUID = guid
                        return
                    end
                end
            end
        end
    end
    if texture.portraitUnitGUID then
        setStaticIcon(texture, icon)
        artworkStyle(texture, false)
        texture.portraitUnitGUID = nil
    end
    if not SetPortraitTextureFromCreatureDisplayID or not C_Timer or not C_Timer.After then return end
    if not self.portraits then
        local model = CreateFrame("PlayerModel", nil, UIParent)
        model:SetSize(1, 1)
        model:SetPoint("CENTER")
        model:SetAlpha(0)
        model:Hide()
        if not model.SetCreature or not model.GetDisplayInfo then return end
        self.portraits = { model = model, cache = {}, cacheOrder = {}, queue = {}, pending = {} }
    end
    local state = self.portraits
    local cached = state.cache[npcID]
    if cached then
        if cached.displayID then
            if texture.portraitDisplayID ~= cached.displayID then
                paintPortrait(texture, cached.displayID)
            end
            return
        elseif GetTime() - cached.time < 60 then return end
    end
    local job = state.pending[npcID]
    if not job then
        job = { id = npcID, textures = {} }
        state.pending[npcID] = job
        table.insert(state.queue, job)
    end
    job.textures[texture] = true
    resolvePortrait()
end

local function entrySlot(parent, x, y, size)
    local inset = size > 30 and 2 or 0
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", x + inset, y - inset)
    icon:SetSize(size - inset * 2, size - inset * 2)
    icon.slotSize, icon.artworkInset = size, inset
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = parent:CreateTexture(nil, "OVERLAY")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("auctionhouse-itemicon-small-border") then
        border:SetPoint("TOPLEFT", x - size / 14, y + size / 14)
        border:SetSize(size * 16 / 14, size * 16 / 14)
        border:SetAtlas("auctionhouse-itemicon-small-border")
    else
        border:SetPoint("TOPLEFT", x - size * 0.18, y + size * 0.18)
        border:SetSize(size * 1.36, size * 1.36)
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    end
    icon.slotBorder = border
    icon.portraitTexture = parent:CreateTexture(nil, "ARTWORK")
    icon.portraitTexture:SetAllPoints(icon)
    icon.portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    icon.portraitTexture:Hide()
    return icon, border
end
-- Shrinks a font (never below 8pt) until its text fits `spec.fit` pixels; translated labels vary a lot in length.
local function applyFont(spec, scale)
    local size = spec.size * scale
    spec.font:SetFont(spec.path, size, spec.flags)
    if spec.fit and spec.font.GetStringWidth then
        local width = spec.font.GetUnboundedStringWidth and spec.font:GetUnboundedStringWidth()
        if type(width) ~= "number" then width = spec.font:GetStringWidth() end
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

local label, button, panel

M.helpTopics = {
    { "Getting started", "help.browse" }, { "Sub-groups", "help.subgroups" },
    { "Results and sorting", "help.results" }, { "Database", "help.database" },
    { "Review journal", "help.review" }, { "Item lookup", "help.items" },
    { "NPC scan", "help.scan" }, { "Share discoveries", "help.share" },
    { "Keyboard", "help.keyboard" }, { "Commands", "help.commands" },
}

local HELP_BULLET = "\226\128\162 "
local HELP_TEXT_WIDTH = 500

function M:ShowHelpTopic(index)
    local f = self.helpFrame
    local topic = self.helpTopics[index] or self.helpTopics[1]
    index = self.helpTopics[index] and index or 1
    f.topic = index
    f.heading:SetText(L[topic[1]])
    for i, row in ipairs(f.topicRows) do
        row.selection:SetShown(i == index)
        row.label:SetTextColor(i == index and 1 or 0.85, i == index and 0.82 or 0.86, i == index and 0 or 0.9)
    end
    local y, count = 0, 0
    for line in (L[topic[2]] .. "\n"):gmatch("(.-)\r?\n") do
        if line ~= "" then
            count = count + 1
            local item = f.lines[count]
            if not item then
                item = { bullet = label(f.content, "", 0, 0, 15), text = label(f.content, "", 0, 0, 15) }
                item.bullet:SetText(HELP_BULLET)
                item.bullet:SetTextColor(1, 0.82, 0)
                item.text:SetJustifyH("LEFT")
                item.text:SetJustifyV("TOP")
                f.lines[count] = item
            end
            local body = line:sub(1, #HELP_BULLET) == HELP_BULLET and line:sub(#HELP_BULLET + 1)
            local command, description = line:match("^(/.-) %- (.+)$")
            local indent = body and 18 or 0
            item.bullet:SetShown(body and true or false)
            item.bullet:SetPoint("TOPLEFT", 0, -y)
            item.text:SetPoint("TOPLEFT", indent, -y)
            item.text:SetWidth(HELP_TEXT_WIDTH - indent)
            if command then
                item.text:SetText("|cffffd100" .. command .. "|r  |cffb8bec8" .. description .. "|r")
            else
                item.text:SetText(body or line)
                item.text:SetTextColor(0.92, 0.93, 0.96)
            end
            item.text:Show()
            y = y + (item.text:GetStringHeight() or 18) + (command and 7 or 12)
        end
    end
    for i = count + 1, #f.lines do
        f.lines[i].bullet:Hide()
        f.lines[i].text:Hide()
    end
    f.content:SetHeight(math.max(1, y))
    f.scroll:SetVerticalScroll(0)
end

function M:ShowHelp(index)
    if not self.helpFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        f:SetSize(760, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        applyWindowBackdrop(f)
        f.title = label(f, "Directory help", 22, -18, 20)
        f.title:SetWidth(600)
        f.title:SetJustifyH("LEFT")
        button(f, "Close", 664, -14, 76, function() f:Hide() end)

        local nav = panel(f, "Help", 16, -54, 184, 450)
        f.topicRows = {}
        for i, topic in ipairs(self.helpTopics) do
            local row = CreateFrame("Button", nil, nav)
            row:SetSize(172, 30)
            row:SetPoint("TOPLEFT", 6, -44 - (i - 1) * 33)
            row.selection = row:CreateTexture(nil, "BACKGROUND")
            row.selection:SetAllPoints()
            row.selection:SetColorTexture(1, 0.82, 0, 0.16)
            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.08)
            row.label = label(row, topic[1], 10, -8, 13)
            row.label:SetWidth(156)
            row.label:SetJustifyH("LEFT")
            row.label:SetMaxLines(1)
            row:SetScript("OnClick", function() self:ShowHelpTopic(i) end)
            f.topicRows[i] = row
        end

        f.heading = label(f, "", 216, -62, 18)
        f.heading:SetTextColor(1, 0.82, 0)
        local rule = f:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 0.82, 0, 0.35)
        rule:SetPoint("TOPLEFT", 216, -88)
        rule:SetSize(510, 1)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 216, -100)
        scroll:SetPoint("BOTTOMRIGHT", -38, 18)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(HELP_TEXT_WIDTH, 1)
        scroll:SetScrollChild(content)
        f.scroll, f.content, f.lines = scroll, content, {}

        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", function(_, key)
            f:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then f:Hide() end
        end)
        self.helpFrame = f
    end
    self.helpFrame:Show()
    self:ShowHelpTopic(index or self.helpFrame.topic or 1)
end

label = function(parent, text, x, y, size, fit)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    font:SetPoint("TOPLEFT", x, y)
    font:SetText(L[text])
    font:SetFont(STANDARD_TEXT_FONT, size or 14)
    trackFont(font, fit)
    return font
end

button = function(parent, text, x, y, width, callback, listIcon)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 150, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(L[text])
    local fontString = b:GetFontString()
    fontString:SetMaxLines(1)
    if listIcon then
        for _, region in ipairs({ b.Left, b.Middle, b.Right }) do region:Hide() end
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", 34, 0)
        fontString:SetWidth((width or 150) - 42)
        fontString:SetJustifyH("LEFT")
        fontString:SetWordWrap(false)
        fontString:SetNonSpaceWrap(false)
        b.browseIcon = b:CreateTexture(nil, "ARTWORK")
        b.browseIcon:SetPoint("TOPLEFT", 10, -4)
        b.browseIcon:SetSize(16, 16)
        setStaticIcon(b.browseIcon, "Interface\\Icons\\" .. listIcon)
    end
    local spec = trackFont(fontString, (width or 150) - (listIcon and 42 or 14))
    b.labelFont = fontString
    b.labelSpec = spec
    local setText = b.SetText
    b.SetText = function(self, value)
        setText(self, value)
        applyFont(spec, M.settings and M.settings.textScale or 1)
    end
    b:SetScript("OnClick", callback)
    return b
end

local function quietButton(b)
    for _, region in ipairs({ b.Left, b.Middle, b.Right }) do region:Hide() end
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local font = b.labelFont
    font:SetTextColor(0.86, 0.84, 0.78)
    b.quiet = true
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

local function check(parent, text, x, y, width, callback, statusLabel)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(26, 26)
    b.caption = label(b, text, 30, -6, 13)
    b.caption:SetWidth(width - 30)
    b.caption:SetJustifyH("LEFT")
    b.caption:SetMaxLines(2)
    b:SetHitRectInsets(0, -(width - 26), 0, 0)
    b.SetText = function(self, value) self.caption:SetText(value) end
    b.GetText = function(self) return self.caption:GetText() end
    b:SetScript("OnClick", callback)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[statusLabel] .. L[self:GetChecked() and "Enabled" or "Disabled"])
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

panel = function(parent, title, x, y, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetFrameLevel(parent:GetFrameLevel())
    applyWindowBackdrop(frame, true)
    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", 5, -5)
    header:SetSize(width - 10, 30)
    header:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    header:SetVertexColor(0.7, 0.5, 0.25, 0.45)
    local heading = label(frame, title, 12, -12, 14)
    heading:SetWidth(width - 24)
    heading:SetJustifyH("LEFT")
    heading:SetTextColor(1, 0.82, 0)
    local divider = frame:CreateTexture(nil, "BACKGROUND")
    divider:SetPoint("TOPLEFT", 10, -36)
    divider:SetSize(width - 20, 1)
    divider:SetColorTexture(0.5, 0.45, 0.35, 0.6)
    frame.heading = heading
    return frame
end

local function selectionMarker(control)
    local selection = control:CreateTexture(nil, "BACKGROUND", nil, 1)
    selection:SetAllPoints()
    selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selection:SetBlendMode("ADD")
    selection:SetAlpha(0.3)
    selection:Hide()
    control.activeBackground = selection
    control.activeMarker = selection
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
        local f = CreateFrame("Frame", "MonstratorCopy", UIParent, "PortraitFrameTemplate")
        f:SetSize(760, 460)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        f.TitleContainer.TitleText:SetText(L["Select text and press Ctrl+C. Nothing is uploaded."])
        trackFont(f.TitleContainer.TitleText)
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        escapeCloses(f)
        panel(f, "", 16, -60, 728, 382)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 32, -78)
        scroll:SetPoint("BOTTOMRIGHT", -40, 20)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetFontObject(ChatFontNormal)
        box:SetWidth(680)
        box:SetFont(STANDARD_TEXT_FONT, 14)
        trackFont(box)
        box:SetAutoFocus(false)
        scroll:SetScrollChild(box)
        box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box = box
        f.scroll = scroll
        self.copyFrame = f
    end
    self.copyFrame.box:SetText(text)
    self.copyFrame.scroll:SetVerticalScroll(0)
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
        f:SetSize(560, 450)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        applyWindowBackdrop(f)
        escapeCloses(f)
        f.title = label(f, "Review placement", 20, -20)
        f.title:SetWidth(520)
        f.title:SetJustifyH("LEFT")
        f.evidenceScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        f.evidenceScroll:SetPoint("TOPLEFT", 20, -54)
        f.evidenceScroll:SetSize(495, 116)
        f.evidenceContent = CreateFrame("Frame", nil, f.evidenceScroll)
        f.evidenceContent:SetSize(495, 116)
        f.evidenceScroll:SetScrollChild(f.evidenceContent)
        f.evidence = label(f.evidenceContent, "", 0, 0, 11)
        f.evidence:SetWidth(495)
        f.evidence:SetJustifyH("LEFT")
        f.evidence:SetJustifyV("TOP")
        label(f, "X (%)", 20, -185)
        label(f, "Y (%)", 180, -185)
        f.x = edit(f, 25, -210, 110)
        f.y = edit(f, 185, -210, 110)
        f.category = button(f, "Category", 20, -250, 220, function()
            local list = self.categories[f.record.kind]
            local index = 2
            for i, value in ipairs(list) do if value == f.value then index = i + 1 end end
            if index > #list then index = 2 end
            f.value = list[index]
            f.category:SetText(L[f.value])
        end)
        label(f, "Tags (comma separated)", 20, -292)
        f.tags = edit(f, 25, -317, 495)
        label(f, "Examples: food, innkeeper, repair, mailbox, flight", 20, -349, 11)
        button(f, "Confirm placement", 20, -394, 160, function()
            local x, y = tonumber(f.x:GetText()), tonumber(f.y:GetText())
            if not self:IsFinite(x) or not self:IsFinite(y) or x < 0 or x > 100 or y < 0 or y > 100 then
                self:Error(L["Enter coordinates between 0 and 100."]); return
            end
            if self:Review(f.record, "accept", x, y, f.value, f.tags:GetText()) then f:Hide() end
        end)
        button(f, "Delete record", 190, -394, 130, function()
            if self:Review(f.record, "reject") then f:Hide() end
        end)
        button(f, "Cancel", 330, -394, 100, function() f:Hide() end)
        self.reviewFrame = f
    end
    local f = self.reviewFrame
    f.record, f.value = record, record.category
    f.title:SetText(record.name .. " - " .. self:MapName(record.mapID))
    local sourceEvent = type(record.source) == "string" and record.source:match("^local:(.+)$")
    local captureLabels = {
        ["manual-target"] = L["npc"],
        ["PLAYER_TARGET_CHANGED"] = L["scan:target"],
        ["UPDATE_MOUSEOVER_UNIT"] = L["scan:mouseover"],
        ["MERCHANT_SHOW"] = L["Vendors"],
        ["TRAINER_SHOW"] = L["Trainers"],
        ["GOSSIP_SHOW"] = L["Services"],
        ["TAXIMAP_OPENED"] = L["Transit"],
        ["manual-landmark"] = L["Landmarks"],
    }
    local captureSource = (sourceEvent and captureLabels[sourceEvent]) or record.source
    local sealState = record.seal == nil and "seal:missing"
        or (self:RecordSealValid(record) and "seal:intact" or "seal:mismatch")
    local seenAt = record.lastSeen and tostring(record.lastSeen) or L["unknown"]
    if record.lastSeen and type(date) == "function" then
        local ok, formatted = pcall(date, "%Y-%m-%d %H:%M", record.lastSeen)
        if ok then seenAt = formatted end
    end
    local evidence = {
        L["Encounter position is approximate. Confirm a static placement."],
        L["Evidence: "] .. L[record.verification] .. " / " .. L[record.precision],
        L["Source: "] .. captureSource,
    }
    if record.kind == "npc" then
        table.insert(evidence, (L["NPC ID: "] .. tostring(record.npcID or L["unknown"]))
            .. " | " .. (L["Level: %s | Type: %s | Rank: %s | Reaction: %s"]):format(
                tostring(record.level or L["unknown"]), record.creatureType or L["unknown"],
                record.classification or L["unknown"], tostring(record.reaction or L["unknown"])))
    end
    table.insert(evidence, (L["Seen: %s | Sightings: %d"]):format(seenAt, record.sightings or 1))
    table.insert(evidence, (L["Submission seal: %s"]):format(L[sealState]))
    table.insert(evidence, (L["Build: %s | Locale: %s"]):format(record.build, record.locale))
    f.evidence:SetText(table.concat(evidence, "\n"))
    f.evidence:SetHeight(0)
    local evidenceHeight = math.max(116, f.evidence:GetStringHeight() or 116)
    f.evidence:SetHeight(evidenceHeight)
    f.evidenceContent:SetHeight(evidenceHeight)
    f.evidenceScroll:SetVerticalScroll(0)
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
        local f = CreateFrame("Frame", "MonstratorSettings", UIParent, "PortraitFrameTemplate")
        f:SetSize(700, 550)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\Trade_Engineering")
        f.TitleContainer.TitleText:SetText(L["Monstrator Settings"])
        trackFont(f.TitleContainer.TitleText)
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
        f.journalPanel = panel(f, "Review journal", 16, -62, 328, 420)
        f.displayPanel = panel(f, "Details", 352, -62, 332, 420)
        f.collect = check(f, "Collection", 28, -110, 300, function()
            self.settings.collecting = not self.settings.collecting
            self:ShowSettings()
        end, "Local collection: ")
        f.discover = check(f, "NPC discovery", 28, -146, 300, function()
            SlashCmdList.MONSTRATOR("discover")
            self:ShowSettings()
        end, "NPC discovery: ")
        f.references = check(f, "Monstrator database", 28, -182, 300, function()
            self.settings.referenceEnabled = not self.settings.referenceEnabled
            self:ShowSettings()
            self:RefreshIfVisible()
        end, "Monstrator database: ")
        local warning = label(f, "Reference identities are not confirmed placements for this server.", 34, -220, 12)
        warning:SetWidth(290)
        warning:SetJustifyH("LEFT")
        warning:SetTextColor(0.8, 0.78, 0.7)
        warning:SetMaxLines(3)
        label(f, "Observation limit (1-100000)", 34, -276, 12)
        f.limit = edit(f, 40, -302, 140)
        f.applyLimit = button(f, "Apply", 194, -302, 128, function()
            local n = tonumber(f.limit:GetText())
            if not self:IsFinite(n) or n < 1 or n > 100000 or n % 1 ~= 0 then
                self:Error(L["Observation limit must be an integer from 1 to 100000."]); return
            end
            self.settings.observationLimit, self.fullNotice = n, nil
            self:Notice(L["Observation limit updated."])
        end)
        button(f, "Export journal", 30, -350, 140, function() self:ShowExport() end)
        button(f, "Share discoveries", 178, -350, 150, function() self:ShowSubmission() end)
        button(f, "Manage journal", 30, -386, 298, function()
            f:Hide()
            self:Toggle("journal")
        end)
        button(f, "Load map data", 30, -422, 298, function() self:SyncClientData() end)
        f.contrast = check(f, "High contrast", 364, -110, 302, function()
            self.settings.highContrast = not self.settings.highContrast
            self:ShowSettings()
            self:RefreshIfVisible()
        end, "High contrast: ")
        f.group = check(f, "Group NPC locations", 364, -146, 302, function()
            self.settings.groupNPCs = not self.settings.groupNPCs
            self:ShowSettings()
            self:RefreshIfVisible()
        end, "Group NPC locations: ")
        f.minimap = check(f, "Minimap button", 364, -182, 302, function()
            SlashCmdList.MONSTRATOR("minimap")
            self:ShowSettings()
        end, "Minimap button: ")
        f.scale = label(f, "Frame scale", 370, -244, 13)
        f.scale:SetWidth(190)
        f.scale:SetJustifyH("LEFT")
        f.text = label(f, "Text scale", 370, -290, 13)
        f.text:SetWidth(190)
        f.text:SetJustifyH("LEFT")
        local function scale(key, delta, minimum)
            local value = math.max(minimum, math.min(1.5, self.settings[key] + delta))
            self.settings[key] = math.floor(value * 10 + 0.5) / 10
            self:ShowSettings()
            if self.window then
                self.window:SetScale(self.settings.frameScale)
                self:Render()
            end
        end
        button(f, "-", 576, -240, 38, function() scale("frameScale", -0.1, 0.6) end)
        button(f, "+", 626, -240, 38, function() scale("frameScale", 0.1, 0.6) end)
        button(f, "-", 576, -286, 38, function() scale("textScale", -0.1, 0.8) end)
        button(f, "+", 626, -286, 38, function() scale("textScale", 0.1, 0.8) end)
        button(f, "Reset window & filters", 370, -350, 298, function() self:ResetView() end)
        button(f, "Close", 550, -502, 124, function() f:Hide() end)
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
    f.minimap:SetChecked(not self.settings.minimapHidden)
    f.collect:SetChecked(self.settings.collecting)
    f.contrast:SetChecked(self.settings.highContrast)
    f.scale:SetText(L["Frame scale: "] .. string.format("%.1f", self.settings.frameScale))
    f.text:SetText(L["Text scale: "] .. string.format("%.1f", self.settings.textScale))
    f.limit:SetText(tostring(self.settings.observationLimit))
    f.discover:SetChecked(self.settings.discovering)
    f.references:SetChecked(self.settings.referenceEnabled)
    f.group:SetChecked(self.settings.groupNPCs)
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
        if self.view ~= "directory" then
            text = L[key == "npc" and "NPCs" or (key == "all" and "All entries" or "Static locations")]
        elseif key == "npc" then
            text = (L["NPCs (%d)"]):format(counts.npc)
        else
            text = (key == "all" and L["All entries"] or L["Static locations"]) .. " (" .. counts[key] .. ")"
        end
        if b.renderText ~= text then b:SetText(text); b.renderText = text end
    end
    for i, b in ipairs(f.categoryButtons) do
        local kind, category = self:BrowseCategory(i)
        if category then
            local icon = "Interface\\Icons\\" .. (categoryIcons[category] or "INV_Misc_Map02")
            if b.renderIcon ~= icon then setStaticIcon(b.browseIcon, icon); b.renderIcon = icon end
            local categories = counts.categories[kind] or {}
            local amount = category == "All" and counts[kind] or (categories[category] or 0)
            local sub = self.category == category and self:ActiveSubgroup()
            local text = sub and (L[category] .. ": " .. L[sub.label] .. " (" .. ((counts.subgroups or {})[sub.key] or 0) .. ")")
                or (L[category] .. " (" .. amount .. ")")
            if self.view ~= "directory" then text = L[category] end
            if b.renderText ~= text then b:SetText(text); b.renderText = text end
        end
    end
    if f.subpicker:IsShown() then self:RenderSubgroupPicker(true) end
    local queue = self.clientData.worldQueue
    local coverage = queue and (L["Scanning zones: %d/%d"]):format(queue.next - 1, #queue.maps)
        or (self.clientData.worldScanned and L["World scan finished"]) or self.clientData.worldSyncStatus
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
            local kind, category = self:BrowseCategory(i)
            b.activeMarker:SetShown(kind == self.kind and category == self.category)
        end
        f.renderScope, f.renderKind, f.renderCategory = self.scope, self.kind, self.category
    end
    local filtering = self.npcFilter ~= nil and self.view == "directory"
    if f.clearFilter:IsShown() ~= filtering then f.clearFilter:SetShown(filtering) end
    local count, journalCount, pendingCount, confirmedNPCs, confirmedNPCIDs =
        #self.results, self:ObservationCount(), self:PendingObservationCount(), 0
    f.pageUp:SetShown(count > #f.rows)
    f.pageDown:SetShown(count > #f.rows)
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
        for key, b in pairs(f.viewButtons) do
            if self.view == key then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
        end
        f.renderNavView = self.view
    end
    local reviewText = L["Review journal"] .. " (" .. pendingCount .. ")"
    if f.viewButtons and f.viewButtons.review and f.viewButtons.review.renderText ~= reviewText then
        f.viewButtons.review:SetText(reviewText)
        f.viewButtons.review.renderText = reviewText
    end
    local visibleNames = {}
    for i = 1, #f.rows do
        local entry = self.results and self.results[(self.offset or 0) + i]
        if entry then
            local r = entry.record
            local key = ("%s:%s:%.1f:%.1f"):format(r.name, r.mapID, r.x, r.y)
            visibleNames[key] = (visibleNames[key] or 0) + 1
        end
    end
    for i, row in ipairs(f.rows) do
        local index = (self.offset or 0) + i
        local entry = self.results and self.results[index]
        row.entry, row.index = entry, index
        if row:IsShown() ~= (entry ~= nil) then row:SetShown(entry ~= nil) end
        if entry then
            local r = entry.record
            self:SetEntryArtwork(row.icon, r)
            local favorite = self.favorites.entries[r.key] ~= nil
            if row.renderName ~= r.name or row.renderFavorite ~= favorite or row.renderTitle ~= r.title
                or row.renderPlacementCount ~= entry.placementCount then
                row.name:SetText((favorite and "|cffffd100*|r " or "") .. r.name
                    .. (r.title and (" |cffc8b070<" .. r.title .. ">|r") or ""))
                row.renderName, row.renderFavorite, row.renderTitle = r.name, favorite, r.title
                row.renderPlacementCount = entry.placementCount
            end
            local yards = entry.distance and math.floor(entry.distance + 0.5)
            local evidence = entry.stale and L["Stale favorite"] or shortEvidenceName(r)
            local ambiguous = visibleNames[("%s:%s:%.1f:%.1f"):format(r.name, r.mapID, r.x, r.y)] > 1
            if row.renderKey ~= r.key or row.renderX ~= r.x or row.renderY ~= r.y
                or row.renderStale ~= entry.stale or row.renderVerification ~= r.verification
                or row.renderEvidence ~= evidence or row.renderNPCID ~= r.npcID
                or row.renderCategory ~= r.category or row.renderMap ~= r.mapID
                or row.renderAmbiguous ~= ambiguous then
                local map = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
                row.detail:SetText((map and map.name or (L["Map %d"]):format(r.mapID))
                    .. ("  %.1f, %.1f"):format(r.x, r.y) .. (ambiguous and (" | " .. evidence) or ""))
                local group = (r.verification == "curated" or r.verification == "user-confirmed") and "confirmed"
                    or (r.verification == "client-map" or r.verification == "client-object") and "map"
                    or isReferenceRecord(r) and "reference" or r.verification
                local color = f.evidenceColors[group] or f.evidenceColors.pending
                row.badge:SetColorTexture(color[1], color[2], color[3], 1)
                row.renderKey, row.renderX, row.renderY = r.key, r.x, r.y
                row.renderStale, row.renderVerification = entry.stale, r.verification
                row.renderEvidence, row.renderNPCID = evidence, r.npcID
                row.renderCategory, row.renderMap = r.category, r.mapID
                row.renderAmbiguous = ambiguous
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
                else red, green, blue = 0.85, 0.85, 0.8 end
            end
            if row.renderRed ~= red or row.renderGreen ~= green or row.renderBlue ~= blue then
                row.distance:SetTextColor(red, green, blue)
                row.renderRed, row.renderGreen, row.renderBlue = red, green, blue
            end
            if row.renderTextScale ~= self.settings.textScale then
                row.name:SetFont(STANDARD_TEXT_FONT, 14 * self.settings.textScale)
                row.distance:SetFont(STANDARD_TEXT_FONT, 12 * self.settings.textScale)
                row.detail:SetFont(STANDARD_TEXT_FONT, 13 * self.settings.textScale)
                row.renderTextScale = self.settings.textScale
            end
            local selected = self.selected == index
            if row.renderSelected ~= selected or row.renderContrast ~= self.settings.highContrast then
                if selected or self.settings.highContrast then row.name:SetTextColor(1, 0.82, 0)
                else row.name:SetTextColor(0.92, 0.9, 0.84) end
                row.renderSelected, row.renderContrast = selected, self.settings.highContrast
            end
            if row.selection:IsShown() ~= selected then row.selection:SetShown(selected) end
        end
    end
    self:RenderDetailsPane()
end

function M:UpdatePositionDisplay()
    local f = self.window
    if not f then return end
    local mapID, x, y = self:PlayerPosition()
    local rx, ry = x and math.floor(x * 10 + 0.5), y and math.floor(y * 10 + 0.5)
    if f.positionInitialized and f.positionMap == mapID and f.positionX == rx and f.positionY == ry
        and f.positionScale == self.settings.textScale then return end
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if mapID and rx and ry then
        f.position:SetText(L["You are in "] .. (info and info.name or tostring(mapID)) .. string.format("  (%.1f, %.1f)", rx / 10, ry / 10))
    else f.position:SetText(L["Position unavailable"]) end
    applyFont(f.positionSpec, self.settings.textScale)
    f.positionInitialized, f.positionMap, f.positionX, f.positionY = true, mapID, rx, ry
    f.positionScale = self.settings.textScale
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
    self.scope, self.kind, self.category, self.view = "zone", "all", "All", "directory"
    self.zoneMap, self.regionMap = nil, nil
    self.selected, self.offset = 1, 0
    local f = CreateFrame("Frame", "MonstratorDirectory", UIParent, "PortraitFrameTemplate")
    f:SetSize(1120, 682)
    f:SetPoint("CENTER", UIParent, "CENTER", s.windowX, s.windowY)
    f:SetFrameStrata("HIGH")
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
    f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    f.TitleContainer.TitleText:SetText("MONSTRATOR")
    trackFont(f.TitleContainer.TitleText)
    f.subtitle = label(f, "WoW Forever NPC & location directory - by Metalbullz", 70, -40, 12, 420)
    f.subtitle:SetWidth(420)
    f.subtitle:SetMaxLines(1)
    f.subtitle:SetJustifyH("LEFT")
    f.subtitle:SetTextColor(0.72, 0.7, 0.64)
    f.position = label(f, "", 510, -40, 12)
    f.positionSpec = trackFont(f.position, 402)
    f.position:SetWidth(402)
    f.position:SetMaxLines(1)
    f.position:SetJustifyH("RIGHT")
    f.position:SetTextColor(0.85, 0.86, 0.9)
    f.itemsButton = button(f, "Items", 930, -36, 68, function() self:ShowItemLookup() end)
    local helpButton = button(f, "Help", 1004, -36, 60, function() self:ShowHelp() end)
    f.close = f.CloseButton
    f.close:SetScript("OnClick", function() f:Hide() end)
    local headerRule = f:CreateTexture(nil, "BACKGROUND")
    headerRule:SetPoint("TOPLEFT", 16, -64)
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
        if self.window ~= f then return end
        self.searchGeneration = (self.searchGeneration or 0) + 1
        local generation = self.searchGeneration
        self.searchPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function()
                if generation ~= self.searchGeneration or self.window ~= f or not f:IsShown() then return end
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
    f.evidence = button(f, "Evidence", 808, -68, 190, function()
        local filters = { "all", "confirmed", "pending", "map", "reference" }
        for i, filter in ipairs(filters) do
            if self.settings.evidenceFilter == filter then self.settings.evidenceFilter = filters[i % #filters + 1]; break end
        end
        self.offset = 0
        self:Refresh()
    end)
    for _, b in ipairs({ f.itemsButton, helpButton, clearButton, f.sort, f.evidence }) do quietButton(b) end

    f.panels = {
        panel(f, "Browse", 16, -104, 232, 520),
        panel(f, "Results", 256, -104, 540, 520),
        panel(f, "Details", 804, -104, 300, 520),
    }
    f.resultsPanel, f.detailsPanel = f.panels[2], f.panels[3]
    local parchment = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment")
    if parchment then
        f.detailsPanel.parchment = f.detailsPanel:CreateTexture(nil, "ARTWORK", nil, -8)
        f.detailsPanel.parchment:SetPoint("TOPLEFT", 5, -5)
        f.detailsPanel.parchment:SetPoint("BOTTOMRIGHT", -5, 126)
        f.detailsPanel.parchment:SetAtlas("QuestBG-Parchment")
        f.detailsPanel.heading:SetTextColor(0.25, 0.13, 0.04)
    else
        self:Error(L["Quest parchment atlas unavailable; using native dark panels."])
    end
    f.filters = f.resultsPanel.heading
    f.filters:SetWidth(400)
    f.clearFilter = button(f, "Clear item filter", 670, -110, 118, function() self:SetNPCFilter(nil) end)
    quietButton(f.clearFilter)
    f.clearFilter:Hide()
    self.focusOrder = { f.search, clearButton, f.sort, f.evidence }
    local function control(text, x, y, callback, width, listIcon, primary)
        local b = button(f, text, x, y, width or 208, callback, listIcon)
        if not primary then
            quietButton(b)
        end
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
    f.minTabWidth, f.maxTabWidth, f.tabPadding = 210, 210, 16
    f.viewButtons = {}
    for i, view in ipairs({ "directory", "favorites", "review" }) do
        local tab = CreateFrame("Button", nil, f, "PanelTabButtonTemplate")
        tab:SetPoint("TOPLEFT", 20 + (i - 1) * 224, -681)
        tab:SetSize(210, 32)
        tab:SetText(L[view])
        tab.Text:SetMaxLines(1)
        tab.Text:SetHeight(24)
        local spec = trackFont(tab.Text, 182)
        local setText = tab.SetText
        tab.SetText = function(self, text)
            setText(self, text)
            applyFont(spec, M.settings.textScale)
        end
        tab:SetScript("OnClick", function() self:ChangeView(view) end)
        tab.activeMarker = tab.LeftActive
        f.viewButtons[view] = tab
        table.insert(self.focusOrder, tab)
    end
    section("Entry type", -226)
    f.kindButtons = {
        all = control("All entries", 28, -242, function() self.kind = "all"; self.category = "All"; self:UpdateCategories() end, nil, "INV_Misc_Map02"),
        npc = control("NPCs", 28, -270, function() self.kind = "npc"; self.category = "All"; self:UpdateCategories() end, nil, "INV_Misc_Head_Human_01"),
        location = control("Static locations", 28, -298, function() self.kind = "location"; self.category = "All"; self:UpdateCategories() end, nil, "INV_Misc_StoneTablet_05"),
    }
    section("Categories", -330)
    f.categoryButtons, f.subgroupButtons = {}, {}
    for i = 1, 6 do
        local b = control("All", 28, -350 - (i - 1) * 38, function()
            local kind, category = self:BrowseCategory(i)
            self.kind, self.category, self.subgroup = kind, category, nil
            if f.subpicker then f.subpicker:Hide() end
            self:UpdateCategories()
        end, 180, "INV_Misc_Map02")
        b:SetHeight(32)
        b.labelFont:SetHeight(30)
        b.labelFont:SetMaxLines(2)
        b.labelFont:SetWordWrap(true)
        b.labelFont:SetNonSpaceWrap(true)
        b.labelSpec.fit = 276
        selectionMarker(b)
        f.categoryButtons[i] = b
        local more = control(">", 212, -350 - (i - 1) * 38, function()
            local kind, category = self:BrowseCategory(i)
            if category then
                if kind ~= self.kind then
                    self.kind, self.category = kind, category
                    self:UpdateCategories()
                end
                self:ToggleSubgroupPicker(category)
            end
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
    for _, group in ipairs({ f.scopeButtons, f.kindButtons }) do
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
        local stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 0.86, 0.6, i % 2 == 0 and 0.035 or 0)
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selection:SetBlendMode("ADD")
        row.selection:SetAlpha(0.5)
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
        row.icon, row.iconBorder = entrySlot(row, 12, -7, 30)
        row.name = label(row, "", 52, -2)
        row.distance = label(row, "", 348, -5, 12)
        row.detail = label(row, "", 52, -24)
        row.name:SetWidth(288)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.distance:SetWidth(144)
        row.distance:SetHeight(36)
        row.distance:SetMaxLines(2)
        row.distance:SetWordWrap(true)
        row.distance:SetJustifyV("TOP")
        row.distance:SetJustifyH("RIGHT")
        row.detail:SetWidth(288)
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
            elseif IsShiftKeyDown() then self:ViewRecordOnMap(b.entry.record)
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
            GameTooltip:AddLine("Shift: " .. L["map.view"], 0.6, 0.85, 1, true)
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
    local function pageButton(direction, y, delta)
        local b = CreateFrame("Button", nil, f)
        b:SetPoint("TOPLEFT", 768, y)
        b:SetSize(22, 22)
        local asset = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. direction .. "Button-"
        b:SetNormalTexture(asset .. "Up")
        b:SetPushedTexture(asset .. "Down")
        b:SetHighlightTexture(asset .. "Highlight", "ADD")
        b:SetScript("OnClick", function() scrollRows(delta) end)
        b:SetScript("OnEnter", function() self.focusIndex = nil end)
        table.insert(self.focusOrder, b)
        return b
    end
    f.pageUp = pageButton("Up", -162, -#f.rows)
    f.pageDown = pageButton("Down", -548, #f.rows)
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
    f.info.parchment = parchment ~= nil and parchment ~= false
    f.info.icon, f.info.iconBorder = entrySlot(f, 824, -151, 48)
    f.info.name = label(f, "", 886, -146, 17)
    f.info.name:SetWidth(204)
    f.info.name:SetHeight(48)
    f.info.name:SetMaxLines(2)
    f.info.name:SetJustifyH("LEFT")
    if f.info.parchment then
        f.info.name:SetTextColor(0.2, 0.1, 0.03)
        f.info.name:SetShadowOffset(0, 0)
    end
    f.info.title = label(f, "", 824, -206, 12)
    f.info.title:SetWidth(266)
    f.info.title:SetMaxLines(1)
    f.info.title:SetJustifyH("LEFT")
    f.info.title:SetTextColor(0.9, 0.82, 0.5)
    if f.info.parchment then
        f.info.title:SetTextColor(0.38, 0.2, 0.06)
        f.info.title:SetShadowOffset(0, 0)
    end
    f.info.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.info.scroll:SetPoint("TOPLEFT", 818, -224)
    f.info.scroll:SetSize(250, 274)
    f.info.content = CreateFrame("Frame", nil, f.info.scroll)
    f.info.content:SetSize(250, 274)
    f.info.scroll:SetScrollChild(f.info.content)
    f.info.sections = {}
    for i, heading in ipairs({ "Location", "Details", "Evidence" }) do
        local card = CreateFrame("Frame", nil, f.info.content, "BackdropTemplate")
        card:SetWidth(250)
        card.rule = card:CreateTexture(nil, "BACKGROUND")
        card.rule:SetPoint("TOPLEFT", 10, -25)
        card.rule:SetSize(230, 1)
        if f.info.parchment then card.rule:SetColorTexture(0.3, 0.18, 0.08, 0.22)
        else card.rule:SetColorTexture(0.8, 0.7, 0.5, 0.22) end
        card.heading = label(card, heading, 10, -10, 12)
        card.heading:SetWidth(230)
        card.heading:SetJustifyH("LEFT")
        card.heading:SetTextColor(1, 0.82, 0)
        if f.info.parchment then
            card.heading:SetTextColor(0.3, 0.14, 0.04)
            card.heading:SetShadowOffset(0, 0)
        end
        card.body = label(card, "", 10, -32, 13)
        card.body:SetSpacing(2)
        card.body:SetWidth(230)
        card.body:SetWordWrap(true)
        card.body:SetNonSpaceWrap(true)
        card.body:SetMaxLines(0)
        card.body:SetJustifyH("LEFT")
        card.body:SetJustifyV("TOP")
        card.body:SetTextColor(0.88, 0.86, 0.8)
        if f.info.parchment then
            card.body:SetTextColor(0.2, 0.13, 0.07)
            card.body:SetShadowOffset(0, 0)
        end
        f.info.sections[i] = card
    end
    f.info.location = f.info.sections[1].body
    f.info.identity = f.info.sections[2].body
    f.info.body = f.info.sections[3].body
    local location = f.info.sections[1]
    location.mapButton = CreateFrame("Button", nil, location)
    location.mapButton:SetAllPoints()
    location.mapButton:SetScript("OnClick", function()
        local entry = self.results and self.results[self.selected]
        if entry then self:ViewRecordOnMap(entry.record) end
    end)
    location.mapButton:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["map.view"])
        GameTooltip:Show()
    end)
    location.mapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.info.navigate = control("Navigate", 818, -508, function()
        self:Activate(self.results and self.results[self.selected])
    end, 132, nil, true)
    f.info.favorite = control("Favorite", 818, -538, function()
        local entry = self.results and self.results[self.selected]
        if entry then self:ToggleFavorite(entry.record); self:Render() end
    end, 132)
    f.detailsButton = control("Entry details", 818, -598, function()
        self:ShowEntryDetails(self.results and self.results[self.selected])
    end, 132)
    f.info.zone = control("Browse this zone", 958, -538, function() self:BrowseRecordPlace() end, 132)
    f.info.model = control("3D model", 818, -568, function() self:ShowSelectedModel() end, 132)
    f.info.items = control("Items sold/dropped", 958, -568, function() self:ShowNPCItems() end, 132)
    f.info.watch = control("Watch for this NPC", 958, -598, function()
        local entry = self.results and self.results[self.selected]
        local r = entry and entry.record
        if r and r.npcID then self:ToggleWatch(r.npcID, r.name) end
    end, 132)
    f.info.map = control("map.view", 958, -508, function()
        local entry = self.results and self.results[self.selected]
        if entry then self:ViewRecordOnMap(entry.record) end
    end, 132, nil, true)
    f.info.actions = { f.info.navigate, f.info.map, f.info.favorite, f.info.zone,
        f.info.model, f.info.items, f.detailsButton, f.info.watch }
    f.info.actionRule = f:CreateTexture(nil, "ARTWORK")
    f.info.actionRule:SetPoint("TOPLEFT", 818, -502)
    f.info.actionRule:SetSize(272, 1)
    f.info.actionRule:SetColorTexture(0.55, 0.45, 0.3, 0.35)
    for _, b in ipairs(f.info.actions) do
        b:SetScript("OnEnter", function(owner)
            self.focusIndex = nil
            GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
            GameTooltip:SetText(owner:GetText())
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    f.coverage = label(f, "", 818, -534, 11)
    f.coverage:SetWidth(272)
    f.coverage:SetHeight(30)
    f.coverage:SetJustifyH("LEFT")
    f.coverage:SetTextColor(0.7, 0.72, 0.78)
    f.coverage:Hide()
    f.onboarding = label(f, "", 818, -566, 11)
    f.onboarding:SetWidth(272)
    f.onboarding:SetHeight(60)
    f.onboarding:SetJustifyH("LEFT")
    f.onboarding:SetTextColor(0.7, 0.72, 0.78)
    f.onboarding:Hide()

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
    f.footer:SetTextColor(0.7, 0.72, 0.75)
    f.status = CreateFrame("Frame", nil, f)
    f.status:SetPoint("TOPLEFT", 690, -642)
    f.status:SetSize(414, 28)
    f.status:EnableMouse(true)
    f.status:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(L["Database"])
        GameTooltip:AddLine(f.coverage:GetText(), 0.85, 0.85, 0.8, true)
        GameTooltip:AddLine(f.onboarding:GetText(), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    f.status:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.resultFocus = control("Keyboard", 1004, -68, function()
        self.focusIndex = nil
        f.search:ClearFocus()
        self:Render()
    end, 100)
    f.resultFocus:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Keyboard"])
        GameTooltip:AddLine(L["help.keyboard"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.resultFocus:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    self:SetEntryArtwork(info.icon, r or { kind = "location", category = "Landmarks" })
    local placeKey = self.scope .. ":" .. tostring(self:ScopeMap())
    local recordKey = r and table.concat({ r.name, r.title or "", r.category, r.verification,
        r.precision, tostring(r.mapID), tostring(r.x), tostring(r.y), tostring(r.npcID or ""),
        tostring(r.objectID or ""), tostring(r.level or ""), r.creatureType or "", r.classification or "",
        r.faction or "", r.nativeOrigin or "", table.concat(r.tags or {}, ",") }, "\031")
    if info.renderKey == (r and r.key) and info.renderYards == yards and info.renderFavorite == favorite
        and info.renderLabel == (entry and entry.distanceLabel) and info.renderStale == (entry and entry.stale)
        and info.renderPlacements == (entry and entry.placementCount) and info.renderPlace == placeKey
        and info.renderTextScale == self.settings.textScale and info.renderRecordKey == recordKey
        and info.renderView == self.view then return end
    local selectionChanged = info.renderKey ~= (r and r.key)
    info.renderKey, info.renderYards, info.renderFavorite = r and r.key, yards, favorite
    info.renderLabel, info.renderStale = entry and entry.distanceLabel, entry and entry.stale
    info.renderPlacements, info.renderPlace = entry and entry.placementCount, placeKey
    info.renderTextScale = self.settings.textScale
    info.renderRecordKey = recordKey
    info.renderView = self.view
    info.navigate:SetText(L[(self.view == "review" or self.view == "journal") and "Review placement" or "Navigate"])
    if selectionChanged then info.scroll:SetVerticalScroll(0) end
    for _, control in ipairs({ info.navigate, info.favorite, info.zone, f.detailsButton, info.map }) do control:SetShown(r ~= nil) end
    info.model:SetShown(r ~= nil and r.npcID ~= nil)
    info.items:SetShown(r ~= nil and r.npcID ~= nil and self:ItemProvider() ~= nil)
    self:RenderWatchButton()
    local actionIndex = 0
    for _, control in ipairs(info.actions) do
        if control:IsShown() then
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", 818 + (actionIndex % 2) * 140, -508 - math.floor(actionIndex / 2) * 30)
            actionIndex = actionIndex + 1
        end
    end
    info.actionRule:SetShown(r ~= nil)
    if not r then
        info.name:SetText(L["Nothing selected"])
        info.title:SetText("")
        info.location:SetText("")
        info.identity:SetText("")
        info.body:SetText(L["Select a result to see its location, identity and evidence. Left-click navigates, right-click saves a favorite."])
    else
        local map = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r.mapID)
        local _, regionName = self:MapRegion(r.mapID)
        info.name:SetText(r.name)
        info.title:SetText(r.title and ("<" .. r.title .. ">") or L[r.category])
        info.location:SetText(table.concat({
            (map and map.name or (L["Map %d"]):format(r.mapID)) .. ", " .. regionName,
            ((info.parchment and "|cff60330f" or "|cffd6a64b") .. "%.1f, %.1f|r"):format(r.x, r.y),
            yards and (L["Distance: %d yd"]):format(yards) or (entry.distanceLabel or L["Distance unavailable"]),
        }, "\n"))
        local identity = {
            L[r.faction or "Both"],
        }
        if r.npcID then
            local extra = {}
            if r.level then table.insert(extra, L["Level "] .. (r.level < 1 and "??" or r.level)) end
            if r.classification and r.classification ~= "normal" and r.classification ~= "minus" then
                table.insert(extra, r.classification)
            end
            if r.creatureType then table.insert(extra, r.creatureType) end
            table.insert(identity, L["NPC ID"] .. " " .. r.npcID)
            if #extra > 0 then table.insert(identity, table.concat(extra, ", ")) end
        end
        if r.objectID then table.insert(identity, L["Object ID "] .. r.objectID) end
        if entry.placementCount and entry.placementCount > 1 then
            table.insert(identity, (L["(%d locations)"]):format(entry.placementCount) .. " - " .. L["nearest shown"])
        end
        if r.tags and #r.tags > 0 then table.insert(identity, L["Tags: "] .. table.concat(r.tags, ", ")) end
        info.identity:SetText(table.concat(identity, "\n"))
        local evidence = { entry.stale and L["Stale favorite"] or recordEvidenceName(r) }
        if r.nativeOrigin then table.insert(evidence, L["nativeOrigin." .. r.nativeOrigin]) end
        info.body:SetText(table.concat(evidence, "\n"))
        info.favorite:SetText(L[favorite and "Remove favorite" or "Favorite"])
        local zoneText = (self.scope == "zone" and self:ScopeMap() == r.mapID) and L["Browse region"] or L["Browse this zone"]
        if info.zone.renderText ~= zoneText then info.zone:SetText(zoneText); info.zone.renderText = zoneText end
    end
    local offset = 0
    for i, card in ipairs(info.sections) do
        local visible = r ~= nil or i == 3
        card:SetShown(visible)
        if visible then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 0, -offset)
            card.body:SetHeight(0)
            local height = math.max(20, card.body:GetStringHeight() or 60)
            card.body:SetHeight(height)
            card:SetHeight(height + 38)
            offset = offset + height + 40
        end
    end
    info.content:SetHeight(math.max(274, offset))
    info.scroll:SetVerticalScroll(math.min(info.scroll:GetVerticalScroll(), math.max(0, offset - 274)))
    if info.scroll.ScrollBar then info.scroll.ScrollBar:SetShown(offset > 274) end
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
        self.searchGeneration = (self.searchGeneration or 0) + 1
        self.searchPending = nil
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
        local kind, category = self:BrowseCategory(i)
        b:SetShown(category ~= nil)
        if category then b:SetText(L[category]); b.renderText = nil end
        self.window.subgroupButtons[i]:SetShown(category ~= nil and self.subgroups[kind .. ":" .. category] ~= nil)
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
    elseif self.window:IsShown() then self.window:Hide()
    else
        self.scope, self.zoneMap, self.regionMap = "zone", nil, nil
        self.kind, self.category, self.subgroup, self.view = "all", "All", nil, "directory"
        self.npcFilter, self.offset, self.selected = nil, 0, 1
        self.settings.sortOrder, self.settings.evidenceFilter = "distance", "all"
        self.window.search:SetText("")
        self.searchPending = nil
        self:UpdateCategories()
        self.window:Show()
    end
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
