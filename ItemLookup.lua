local _, M = ...
local L = M.L
-- Item lookup and 3D model viewer. Item data comes from the Monstrator database; sources are resolved
-- lazily per selected item.

local ITEM_CHUNK = 1000
local ITEM_ROWS, SOURCE_ROWS = 12, 8
local MAX_RESULTS = 500
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local tabs = { "vendor", "drop", "object", "quest" }

local read = M.ReadNativeField

local function safeCall(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, object, ...)
    if ok then return a, b end
end

function M:ItemProvider()
    local lib = self:NativeProvider()
    local item = lib and lib.Item
    if type(item) == "table" and type(item.GetAllIds) == "function" and type(item.name) == "function" then
        return lib
    end
end

function M:StartItemIndex()
    if self.items then return self.items end
    local lib = self:ItemProvider()
    if not lib then return end
    local ok, ids = pcall(lib.Item.GetAllIds)
    if not ok or type(ids) ~= "table" then return end
    local state = { lib = lib, ids = ids, nextIndex = 1, list = {}, names = {}, lower = {}, byNPC = {}, ready = false }
    self.items = state
    local item = lib.Item
    local function link(npcs, itemID)
        if type(npcs) ~= "table" then return end
        for _, npcID in ipairs(npcs) do
            local list = state.byNPC[npcID]
            if not list then list = {}; state.byNPC[npcID] = list end
            if list[#list] ~= itemID then table.insert(list, itemID) end
        end
    end
    local function step()
        if self.items ~= state then return end
        local last = math.min(#ids, state.nextIndex + ITEM_CHUNK - 1)
        for i = state.nextIndex, last do
            local id = ids[i]
            local name = read(item.name, id)
            if type(name) == "string" and name ~= "" then
                table.insert(state.list, id)
                state.names[id], state.lower[id] = name, name:lower()
                link(read(item.vendors, id), id)
                link(read(item.npcDrops, id), id)
            end
        end
        state.nextIndex = last + 1
        if state.nextIndex <= #ids then
            if C_Timer and C_Timer.After then C_Timer.After(0, step) else step() end
            self:RenderItemWindow()
            return
        end
        table.sort(state.list, function(a, b)
            if state.lower[a] ~= state.lower[b] then return state.lower[a] < state.lower[b] end
            return a < b
        end)
        state.ready = true
        self.itemSearch = nil
        self:RefreshItemWindow()
    end
    step()
    return state
end

function M:SearchItems(query, npcID)
    local state = self.items
    if not state or not state.ready then return {} end
    query = string.lower(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local key = query .. "|" .. tostring(npcID)
    if self.itemSearch and self.itemSearch.key == key then return self.itemSearch.results end
    local pool = npcID and (state.byNPC[npcID] or {}) or state.list
    local results = {}
    local exactID = tonumber(query)
    if exactID and state.names[exactID] and not npcID then table.insert(results, exactID) end
    if query ~= "" or npcID then
        local tokens = {}
        for token in query:gmatch("%S+") do table.insert(tokens, token) end
        for _, id in ipairs(pool) do
            local name, ok = state.lower[id], true
            for _, token in ipairs(tokens) do
                if not name:find(token, 1, true) then ok = false; break end
            end
            if ok and id ~= exactID then table.insert(results, id) end
        end
        table.sort(results, function(a, b)
            if a == exactID or b == exactID then return a == exactID end
            local an, bn = state.lower[a], state.lower[b]
            local ae, be = an == query, bn == query
            if ae ~= be then return ae end
            local ap, bp = an:sub(1, #query) == query, bn:sub(1, #query) == query
            if ap ~= bp then return ap end
            if an ~= bn then return an < bn end
            return a < b
        end)
    end
    local total = #results
    for i = #results, MAX_RESULTS + 1, -1 do results[i] = nil end
    self.itemSearch = { key = key, results = results, total = total }
    return results, total
end

function M:ItemDetails(itemID)
    local lib = self:ItemProvider()
    if not lib then return end
    local item = lib.Item
    local function list(getter)
        local value = read(getter, itemID)
        return type(value) == "table" and value or {}
    end
    return {
        id = itemID, name = (self.items and self.items.names[itemID]) or read(item.name, itemID) or (L["Item %d"]):format(itemID),
        itemLevel = read(item.itemLevel, itemID), requiredLevel = read(item.requiredLevel, itemID),
        class = read(item.class, itemID), subClass = read(item.subClass, itemID),
        startQuest = read(item.startQuest, itemID),
        vendor = list(item.vendors), drop = list(item.npcDrops), object = list(item.objectDrops),
        quest = list(item.questRewards), containers = list(item.itemDrops),
    }
end

-- Map rectangles are affine in world space, so three probes per map convert every spawn point cheaply.
function M:MapTransform(mapID)
    self.mapTransforms = self.mapTransforms or {}
    local cached = self.mapTransforms[mapID]
    if cached ~= nil then return cached or nil end
    local instance, x0, y0 = self:WorldPosition(mapID, 0, 0)
    local instance1, x1, y1 = self:WorldPosition(mapID, 100, 0)
    local instance2, x2, y2 = self:WorldPosition(mapID, 0, 100)
    local transform = false
    if instance and instance == instance1 and instance == instance2 then
        transform = { instance = instance, x0 = x0, y0 = y0, ux = (x1 - x0) / 100, uy = (y1 - y0) / 100,
            vx = (x2 - x0) / 100, vy = (y2 - y0) / 100 }
    end
    self.mapTransforms[mapID] = transform
    return transform or nil
end

function M:NearestSpawn(spawns)
    if type(spawns) ~= "table" then return end
    local playerMap, px, py = self:PlayerPosition()
    local here = playerMap and self:MapTransform(playerMap)
    local wx, wy
    if here then wx, wy = here.x0 + here.ux * px + here.vx * py, here.y0 + here.uy * px + here.vy * py end
    local best, count = nil, 0
    for mapID, points in pairs(spawns) do
        if type(mapID) == "number" and type(points) == "table" and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) then
            local transform = here and self:MapTransform(mapID)
            local sameWorld = transform and transform.instance == here.instance
            for _, point in ipairs(points) do
                local x, y = type(point) == "table" and point[1], type(point) == "table" and point[2]
                if self:IsFinite(x) and self:IsFinite(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                    count = count + 1
                    local distance
                    if sameWorld then
                        local dx = transform.x0 + transform.ux * x + transform.vx * y - wx
                        local dy = transform.y0 + transform.uy * x + transform.vy * y - wy
                        distance = math.sqrt(dx * dx + dy * dy)
                    end
                    if not best or (distance and (not best.distance or distance < best.distance)) then
                        best = { mapID = mapID, x = x, y = y, distance = distance }
                    end
                end
            end
        end
    end
    if best then best.count = count end
    return best
end

local function sourceOrder(a, b)
    if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
    if a.distance and b.distance and a.distance ~= b.distance then return a.distance < b.distance end
    if (a.mapID ~= nil) ~= (b.mapID ~= nil) then return a.mapID ~= nil end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

function M:ResolveItemSources(details, tab)
    local lib = self:ItemProvider()
    if not lib or not details then return {} end
    local sources = {}
    local faction = UnitFactionGroup("player")
    local function npcSource(npcID, extra)
        local name = read(lib.Npc.name, npcID)
        if type(name) ~= "string" or name == "" then return end
        local title = read(lib.Npc.subName, npcID)
        local friendly = read(lib.Npc.friendlyToFaction, npcID)
        local enemy = (friendly == "A" and faction == "Horde") or (friendly == "H" and faction == "Alliance")
        local spot = self:NearestSpawn(read(lib.Npc.spawns, npcID)) or {}
        local level = read(lib.Npc.maxLevel, npcID)
        local source = { kind = "npc", id = npcID, name = name, title = type(title) == "string" and title ~= "" and title or nil,
            level = type(level) == "number" and level > 0 and level or nil, enemy = enemy,
            mapID = spot.mapID, x = spot.x, y = spot.y, distance = spot.distance, count = spot.count }
        for k, v in pairs(extra or {}) do source[k] = v end
        table.insert(sources, source)
    end
    if tab == "vendor" or tab == "drop" then
        for _, npcID in ipairs(details[tab]) do
            local reference
            if tab == "drop" and lib.Item.npcDropReference then
                reference = lib.Item.npcDropReference(details.id, npcID)
            end
            npcSource(npcID, { lootReference = reference })
        end
    elseif tab == "object" and lib.Object then
        for _, objectID in ipairs(details.object) do
            local name = read(lib.Object.name, objectID)
            if type(name) == "string" and name ~= "" then
                local spot = self:NearestSpawn(read(lib.Object.spawns, objectID)) or {}
                table.insert(sources, { kind = "object", id = objectID, name = name, mapID = spot.mapID,
                    x = spot.x, y = spot.y, distance = spot.distance, count = spot.count })
            end
        end
    elseif tab == "quest" and lib.Quest then
        for _, questID in ipairs(details.quest) do
            local name = read(lib.Quest.name, questID)
            if type(name) == "string" and name ~= "" then
                local starters = read(lib.Quest.starterNpcs, questID)
                local npcID = type(starters) == "table" and starters[1]
                local level = read(lib.Quest.questLevel, questID)
                local quest = { questID = questID, questName = name, questLevel = type(level) == "number" and level or nil }
                if npcID then
                    local before = #sources
                    npcSource(npcID, quest)
                    if #sources == before then npcID = nil end
                end
                if not npcID then
                    table.insert(sources, { kind = "quest", id = questID, name = name, questID = questID,
                        questName = name, questLevel = quest.questLevel })
                end
            end
        end
    end
    table.sort(sources, sourceOrder)
    return sources
end

function M:SourceRecord(source)
    if not source or not source.mapID or source.kind ~= "npc" then return end
    local provenance, permission, version = self:DatabaseProvenance()
    return {
        key = (self.dbKeyPrefix .. "item-source:%d"):format(source.id),
        name = source.name, kind = "npc", npcID = source.id, mapID = source.mapID, x = source.x, y = source.y,
        category = source.enemy and "Combat" or "Services", tags = {},
        title = source.title, verification = "reference", precision = "reference", edition = "Forever",
        source = provenance,
        build = version, locale = GetLocale and GetLocale() or "enUS",
        permission = permission,
    }
end

function M:NavigateSource(source)
    if not source then return false end
    local label = L[self:DataSourceLabel()]
    if not source.mapID then
        self:Notice((L["%s: no coordinates listed in the %s."]):format(source.name, label))
        return false
    end
    local record = self:SourceRecord(source)
    if record then return self:NavigateRecord(record) end
    self.navigationCaveat = (L[" (%s location - confirm on arrival)"]):format(label)
    local ok = self:SetNavigationWaypoint(source.mapID, source.x, source.y, source.name .. " [" .. label .. "]")
    self.navigationCaveat = nil
    return ok
end

local requested = {}
local function itemInfo(itemID)
    if type(GetItemInfo) ~= "function" then return end
    local name, link, quality = GetItemInfo(itemID)
    if not name and not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[itemID] = true
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return name, link, quality
end

local function itemIcon(itemID)
    local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        or (GetItemIcon and GetItemIcon(itemID))
    return icon or QUESTION_ICON
end

local function qualityColor(quality)
    local colors = rawget(_G, "ITEM_QUALITY_COLORS")
    local color = quality and colors and colors[quality]
    return color and color.hex or "|cffffffff"
end

local function try(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function itemClassName(class, subClass)
    if not class then return end
    local className = try(rawget(_G, "GetItemClassInfo"), class)
    local subName = subClass and try(rawget(_G, "GetItemSubClassInfo"), class, subClass)
    if className and subName and subName ~= className then return className .. " / " .. subName end
    return className
end

function M:ShowItemLookup(query, npcID, npcName)
    if not self:ItemProvider() then
        self:Error(L["Item lookup has no item data in this build (standalone). Import a database with tools\\monstrator-db.cjs to enable it."])
        return
    end
    if not self.itemFrame then self:CreateItemWindow() end
    local f = self.itemFrame
    f:SetScale(self.settings.frameScale)
    self.itemNPC = npcID and { id = npcID, name = npcName or (L["NPC %d"]):format(npcID) } or nil
    self.itemOffset, self.itemSelectedIndex, self.itemResults = 0, 1, {}
    f:Show()
    if query ~= nil then f.search:SetText(query) end
    self:StartItemIndex()
    self.itemOffset, self.itemSelectedIndex = 0, 1
    self:RefreshItemWindow()
end

function M:ShowNPCItems()
    local entry = self.results and self.results[self.selected or 1]
    local r = entry and entry.record
    if r and r.npcID then self:ShowItemLookup("", r.npcID, r.name) end
end

function M:RefreshItemWindow()
    local f = self.itemFrame
    if not f or not f:IsShown() then return end
    local results, total = self:SearchItems(f.search:GetText(), self.itemNPC and self.itemNPC.id)
    self.itemResults, self.itemTotal = results, total or (self.itemSearch and self.itemSearch.total) or #results
    self.itemSelectedIndex = math.max(1, math.min(self.itemSelectedIndex or 1, #results))
    self.itemOffset = math.max(0, math.min(self.itemOffset or 0, #results - ITEM_ROWS))
    self:SelectItem(results[self.itemSelectedIndex])
end

function M:SelectItem(itemID)
    if self.itemDetails and self.itemDetails.id == itemID then self:RenderItemWindow(); return end
    self.itemDetails = itemID and self:ItemDetails(itemID) or nil
    self.itemSourceCache, self.sourceOffset = {}, 0
    if self.itemDetails then
        local chosen
        for _, tab in ipairs(tabs) do
            if #self.itemDetails[tab] > 0 then chosen = chosen or tab end
        end
        if not (self.itemTab and #self.itemDetails[self.itemTab] > 0) then self.itemTab = chosen or "vendor" end
    end
    self:RenderItemWindow()
end

function M:CurrentItemSources()
    local details = self.itemDetails
    if not details then return {} end
    local cache = self.itemSourceCache
    local entry = cache[self.itemTab]
    local now = GetTime and GetTime() or 0
    if not entry or now - entry.time > 5 then
        entry = { time = now, sources = self:ResolveItemSources(details, self.itemTab) }
        cache[self.itemTab] = entry
    end
    return entry.sources
end

function M:RenderItemWindow()
    local f = self.itemFrame
    if not f or not f:IsShown() then return end
    local state = self.items
    local status
    if not state then status = L["Item data unavailable."]
    elseif not state.ready then
        status = (L["Indexing items... %d%%"]):format(math.floor((state.nextIndex - 1) * 100 / math.max(1, #state.ids)))
    elseif self.itemNPC then
        status = (L["Items sold or dropped by %s: %d"]):format(self.itemNPC.name, self.itemTotal or 0)
    else
        status = ("%d of %d items"):format(self.itemTotal or 0, #state.list)
    end
    f.status:SetText(status)
    f.clearNPC:SetShown(self.itemNPC ~= nil)
    local results = self.itemResults or {}
    self.itemOffset = math.max(0, math.min(self.itemOffset or 0, #results - ITEM_ROWS))
    self.itemSelectedIndex = self.itemSelectedIndex or 1
    f.listPanel.heading:SetText(self.itemNPC and (L["Items from "] .. self.itemNPC.name) or L["Items"])
    local query = f.search:GetText()
    f.empty:SetShown(#results == 0)
    if #results == 0 then
        f.empty:SetText(state and state.ready and (query == "" and not self.itemNPC
            and L["Type an item name or ID.\nExamples: linen, haunch, 2589"]
            or L["No matching items."]) or L["Loading items..."])
    end
    for i, row in ipairs(f.itemRows) do
        local index = self.itemOffset + i
        local itemID = results[index]
        row.itemID, row.index = itemID, index
        row:SetShown(itemID ~= nil)
        if itemID then
            local name, _, quality = itemInfo(itemID)
            row.icon:SetTexture(itemIcon(itemID))
            row.name:SetText(qualityColor(quality) .. (name or state.names[itemID]) .. "|r")
            local level = read(state.lib.Item.requiredLevel, itemID)
            row.detail:SetText((level and level > 0) and (L["Req "] .. level) or ("#" .. itemID))
            row.selection:SetShown(index == self.itemSelectedIndex)
        end
    end
    f.itemPage:SetText(#results > 0 and (L["%d-%d of %d"]):format(self.itemOffset + 1,
        math.min(#results, self.itemOffset + ITEM_ROWS), #results) or "")
    self:RenderItemDetails()
end

function M:RenderItemDetails()
    local f = self.itemFrame
    local d = self.itemDetails
    for _, control in ipairs({ f.detailIcon, f.directoryButton, f.previewButton, f.linkButton, f.sourcePage }) do
        control:SetShown(d ~= nil)
    end
    for _, tab in ipairs(tabs) do f.tabs[tab]:SetShown(d ~= nil) end
    if not d then
        f.detailName:SetText(L["Nothing selected"])
        f.detailInfo:SetText(L["Pick an item to see who sells it, drops it, or rewards it."])
        f.sourceEmpty:SetText("")
        for _, row in ipairs(f.sourceRows) do row:Hide() end
        return
    end
    local name, _, quality = itemInfo(d.id)
    f.detailIcon:SetTexture(itemIcon(d.id))
    f.detailName:SetText(qualityColor(quality) .. (name or d.name) .. "|r")
    local info = { L["Item ID "] .. d.id }
    if d.itemLevel and d.itemLevel > 0 then table.insert(info, L["Item level "] .. d.itemLevel) end
    if d.requiredLevel and d.requiredLevel > 0 then table.insert(info, L["Requires level "] .. d.requiredLevel) end
    local className = itemClassName(d.class, d.subClass)
    local lines = { table.concat(info, " | ") }
    if className then table.insert(lines, className) end
    if d.startQuest then
        local lib = self:ItemProvider()
        local questName = lib and read(lib.Quest and lib.Quest.name, d.startQuest)
        table.insert(lines, "|cffffd100Starts a quest:|r " .. tostring(questName or d.startQuest))
    end
    if #d.containers > 0 then table.insert(lines, (L["Found in %d container item(s)"]):format(#d.containers)) end
    f.detailInfo:SetText(table.concat(lines, "\n"))
    local labels = { vendor = L["Sold by"], drop = L["Dropped by"], object = L["Gathered"], quest = L["Quest reward"] }
    for _, tab in ipairs(tabs) do
        local b = f.tabs[tab]
        b:SetText((L["%s (%d)"]):format(labels[tab], #d[tab]))
        b.activeMarker:SetShown(self.itemTab == tab)
        if #d[tab] == 0 then b:Disable() else b:Enable() end
    end
    local sources = self:CurrentItemSources()
    self.sourceOffset = math.max(0, math.min(self.sourceOffset or 0, #sources - SOURCE_ROWS))
    local npcSources = #d.vendor + #d.drop
    if npcSources > 0 then f.directoryButton:Enable() else f.directoryButton:Disable() end
    f.sourceEmpty:SetText(#sources == 0 and (L["No sources listed in the %s for this tab."]):format(L[self:DataSourceLabel()]) or "")
    for i, row in ipairs(f.sourceRows) do
        local source = sources[self.sourceOffset + i]
        row.source = source
        row:SetShown(source ~= nil)
        if source then
            local nameText = source.name
            if source.questName and source.kind == "npc" then nameText = source.questName .. " |cff9aa3b5- from " .. source.name .. "|r" end
            if source.enemy then nameText = "|cffff6060" .. nameText .. "|r" end
            row.name:SetText(nameText)
            local where
            if source.mapID then
                where = ("%s  %.1f, %.1f"):format(self:MapName(source.mapID), source.x, source.y)
                if source.count and source.count > 1 then where = where .. (" | %d spawns"):format(source.count) end
            else where = L["Location not listed"] end
            if source.level then where = L["Lv "] .. source.level .. " | " .. where end
            if source.title then where = "<" .. source.title .. "> " .. where end
            if source.lootReference then where = where .. " | " .. source.lootReference end
            row.detail:SetText(where)
            if source.distance then
                local yards = math.floor(source.distance + 0.5)
                row.distance:SetText((L["%d yd"]):format(yards))
                if source.distance < 40 then row.distance:SetTextColor(0.3, 1, 0.3)
                elseif source.distance <= 100 then row.distance:SetTextColor(1, 0.85, 0.2)
                else row.distance:SetTextColor(1, 0.35, 0.35) end
            else
                row.distance:SetText(source.mapID and L["far"] or "")
                row.distance:SetTextColor(0.65, 0.67, 0.72)
            end
        end
    end
    f.sourcePage:SetText(#sources > 0 and (L["%d-%d of %d"]):format(self.sourceOffset + 1,
        math.min(#sources, self.sourceOffset + SOURCE_ROWS), #sources) or "")
end

function M:ShowItemSourcesInDirectory()
    local d = self.itemDetails
    if not d then return end
    local ids, count = {}, 0
    for _, tab in ipairs({ "vendor", "drop" }) do
        for _, npcID in ipairs(d[tab]) do
            if not ids[npcID] then ids[npcID] = true; count = count + 1 end
        end
    end
    if count == 0 then return end
    self:SetNPCFilter(ids, L["Sources of "] .. d.name)
end

function M:CreateItemWindow()
    local W = self.Widgets
    local label, button = W.label, W.button
    local f = CreateFrame("Frame", "MonstratorItemLookup", UIParent, "PortraitFrameTemplate")
    f:SetSize(840, 560)
    f:SetPoint("CENTER", UIParent, "CENTER", 40, -20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    W.escapeCloses(f)
    f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    f.TitleContainer.TitleText:SetText(L["ITEM LOOKUP"])
    local subtitle = label(f, "Who sells it, drops it, gathers it or rewards it - nearest first", 70, -38, 11)
    subtitle:SetWidth(500)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetTextColor(0.7, 0.72, 0.78)
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    local rule = f:CreateTexture(nil, "BACKGROUND")
    rule:SetPoint("TOPLEFT", 16, -60)
    rule:SetSize(808, 1)
    rule:SetColorTexture(0.55, 0.62, 0.72, 0.7)

    f.search = W.edit(f, 28, -68, 330)
    f.search:SetMaxLetters(100)
    f.searchHint = label(f.search, "Search items by name or ID", 4, -5, 12)
    f.searchHint:SetTextColor(0.65, 0.65, 0.65)
    button(f, "x", 362, -68, 26, function() f.search:SetText(""); f.search:SetFocus() end)
    f.search:SetScript("OnTextChanged", function()
        f.searchHint:SetShown(f.search:GetText() == "" and not f.search:HasFocus())
        self.itemSearchGeneration = (self.itemSearchGeneration or 0) + 1
        local generation = self.itemSearchGeneration
        local function run()
            if generation ~= self.itemSearchGeneration then return end
            self.itemOffset, self.itemSelectedIndex = 0, 1
            self:RefreshItemWindow()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.15, run) else run() end
    end)
    f.search:SetScript("OnEditFocusGained", function() f.searchHint:Hide() end)
    f.search:SetScript("OnEditFocusLost", function() f.searchHint:SetShown(f.search:GetText() == "") end)
    f.search:SetScript("OnEnterPressed", function() f.search:ClearFocus() end)
    f.status = label(f, "", 400, -73, 12)
    f.status:SetWidth(290)
    f.status:SetMaxLines(1)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(0.85, 0.82, 0.6)
    f.clearNPC = button(f, "Show all items", 700, -68, 124, function()
        self.itemNPC = nil
        self.itemOffset, self.itemSelectedIndex = 0, 1
        self:RefreshItemWindow()
    end)

    f.listPanel = W.panel(f, "Items", 16, -100, 380, 404)
    f.detailPanel = W.panel(f, "Sources", 404, -100, 420, 404)
    local faction = UnitFactionGroup("player")
    f.itemRows = {}
    for i = 1, ITEM_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(356, 26)
        row:SetPoint("TOPLEFT", 28, -142 - (i - 1) * 28)
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetColorTexture(faction == "Horde" and 0.55 or 0.2, faction == "Horde" and 0.18 or 0.38,
            faction == "Horde" and 0.18 or 0.65, 0.55)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.12)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = label(row, "", 30, -6, 13)
        row.name:SetWidth(250)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.detail = label(row, "", 284, -7, 11)
        row.detail:SetWidth(68)
        row.detail:SetJustifyH("RIGHT")
        row.detail:SetTextColor(0.65, 0.67, 0.72)
        row:SetScript("OnClick", function(b)
            if not b.itemID then return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") then
                local _, link = itemInfo(b.itemID)
                if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                return
            end
            self.itemSelectedIndex = b.index
            f.search:ClearFocus()
            self:SelectItem(b.itemID)
        end)
        row:SetScript("OnEnter", function(b)
            if not b.itemID then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. b.itemID)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.itemRows[i] = row
    end
    f.empty = label(f, "", 40, -200, 13)
    f.empty:SetWidth(330)
    f.empty:SetTextColor(0.7, 0.72, 0.78)
    f.itemPage = label(f, "", 200, -482, 11)
    f.itemPage:SetWidth(180)
    f.itemPage:SetJustifyH("RIGHT")
    f.itemPage:SetTextColor(0.65, 0.67, 0.72)
    local function scrollItems(_, delta)
        local count = #(self.itemResults or {})
        self.itemOffset = math.max(0, math.min(math.max(0, count - ITEM_ROWS), (self.itemOffset or 0) - delta * 3))
        self:RenderItemWindow()
    end
    f.listPanel:EnableMouseWheel(true)
    f.listPanel:SetScript("OnMouseWheel", scrollItems)
    for _, row in ipairs(f.itemRows) do row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", scrollItems) end

    local iconButton = CreateFrame("Button", nil, f)
    iconButton:SetSize(40, 40)
    iconButton:SetPoint("TOPLEFT", 420, -142)
    f.detailIcon = iconButton:CreateTexture(nil, "ARTWORK")
    f.detailIcon:SetAllPoints()
    iconButton:SetScript("OnEnter", function()
        if not self.itemDetails then return end
        GameTooltip:SetOwner(iconButton, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.itemDetails.id)
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.detailName = label(f, "", 468, -142, 15)
    f.detailName:SetWidth(340)
    f.detailName:SetMaxLines(1)
    f.detailName:SetJustifyH("LEFT")
    f.detailInfo = label(f, "", 468, -162, 11)
    f.detailInfo:SetWidth(344)
    f.detailInfo:SetHeight(42)
    f.detailInfo:SetJustifyH("LEFT")
    f.detailInfo:SetJustifyV("TOP")
    f.detailInfo:SetTextColor(0.8, 0.82, 0.86)
    f.tabs = {}
    for i, tab in ipairs(tabs) do
        local b = button(f, tab, 414 + (i - 1) * 101, -208, 99, function()
            self.itemTab, self.sourceOffset = tab, 0
            self:RenderItemWindow()
        end)
        W.marker(b)
        f.tabs[tab] = b
    end
    f.sourceRows = {}
    for i = 1, SOURCE_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(396, 29)
        row:SetPoint("TOPLEFT", 416, -238 - (i - 1) * 30)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.12)
        local separator = row:CreateTexture(nil, "BACKGROUND")
        separator:SetPoint("BOTTOMLEFT", 0, 0)
        separator:SetSize(396, 1)
        separator:SetColorTexture(0.55, 0.62, 0.72, 0.25)
        row.name = label(row, "", 4, -2, 12)
        row.name:SetWidth(320)
        row.name:SetMaxLines(1)
        row.name:SetJustifyH("LEFT")
        row.detail = label(row, "", 4, -16, 10)
        row.detail:SetWidth(388)
        row.detail:SetMaxLines(1)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetTextColor(0.65, 0.67, 0.72)
        row.distance = label(row, "", 326, -2, 11)
        row.distance:SetWidth(66)
        row.distance:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(b, mouse)
            local source = b.source
            if not source then return end
            if mouse == "RightButton" then
                if source.kind == "npc" then self:ShowModel("npc", source.id, source.name) end
                return
            end
            self:NavigateSource(source)
        end)
        row:SetScript("OnEnter", function(b)
            local source = b.source
            if not source then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(source.name)
            if source.lootReference then
                GameTooltip:AddLine(L["AtlasLoot reference (not Forever-confirmed)"], 1, 0.82, 0, true)
            end
            if source.title then GameTooltip:AddLine("<" .. source.title .. ">", 0.9, 0.82, 0.5) end
            if source.questName then
                GameTooltip:AddLine(L["Quest: "] .. source.questName .. (source.questLevel and (" [" .. source.questLevel .. "]") or ""), 1, 0.82, 0)
            end
            if source.mapID then
                GameTooltip:AddLine((L["%s  %.1f, %.1f"]):format(self:MapName(source.mapID), source.x, source.y), 1, 1, 1)
                GameTooltip:AddLine(L["Left-click: set waypoint (nearest spawn)"], 0.6, 0.9, 0.6)
            end
            if source.enemy then GameTooltip:AddLine(L["Hostile to your faction"], 1, 0.4, 0.4) end
            if source.kind == "npc" then GameTooltip:AddLine(L["Right-click: 3D model"], 0.6, 0.9, 0.6) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.sourceRows[i] = row
    end
    f.sourceEmpty = label(f, "", 420, -250, 12)
    f.sourceEmpty:SetWidth(380)
    f.sourceEmpty:SetTextColor(0.7, 0.72, 0.78)
    f.sourcePage = label(f, "", 620, -482, 11)
    f.sourcePage:SetWidth(192)
    f.sourcePage:SetJustifyH("RIGHT")
    f.sourcePage:SetTextColor(0.65, 0.67, 0.72)
    local function scrollSources(_, delta)
        local count = #self:CurrentItemSources()
        self.sourceOffset = math.max(0, math.min(math.max(0, count - SOURCE_ROWS), (self.sourceOffset or 0) - delta * 2))
        self:RenderItemWindow()
    end
    f.detailPanel:EnableMouseWheel(true)
    f.detailPanel:SetScript("OnMouseWheel", scrollSources)
    for _, row in ipairs(f.sourceRows) do row:EnableMouseWheel(true); row:SetScript("OnMouseWheel", scrollSources) end

    f.directoryButton = button(f, "Show sources in directory", 16, -516, 200, function() self:ShowItemSourcesInDirectory() end)
    f.previewButton = button(f, "3D preview", 222, -516, 110, function()
        if self.itemDetails then self:ShowModel("item", self.itemDetails.id, self.itemDetails.name) end
    end)
    f.linkButton = button(f, "Link in chat", 338, -516, 110, function()
        if not self.itemDetails then return end
        local _, link = itemInfo(self.itemDetails.id)
        if link and ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
        if link and ChatFrame_OpenChat then ChatFrame_OpenChat(link) return end
        self:Notice(L["Item not cached yet; try again in a moment."])
    end)
    local hint = label(f, "Left-click a source for a waypoint. Shift-click an item to link it.", 456, -521, 11)
    hint:SetWidth(368)
    hint:SetJustifyH("RIGHT")
    hint:SetTextColor(0.6, 0.62, 0.68)
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function()
        if f.renderQueued or not f:IsShown() then return end
        f.renderQueued = true
        local function render() f.renderQueued = nil; self:RenderItemWindow() end
        if C_Timer and C_Timer.After then C_Timer.After(0.2, render) else render() end
    end)
    f:SetScript("OnHide", function() GameTooltip:Hide(); f.search:ClearFocus() end)
    self.itemFrame = f
    f:Hide()
end

-- 3D model viewer: creature models for NPCs, a dress-up try-on for items.
function M:ShowSelectedModel()
    local entry = self.results and self.results[self.selected or 1]
    local r = entry and entry.record
    if r and r.npcID then self:ShowModel("npc", r.npcID, r.name)
    else self:Notice(L["Select an NPC to view its 3D model."]) end
end

function M:CreateModelWindow()
    local W = self.Widgets
    local f = CreateFrame("Frame", "MonstratorModelViewer", UIParent, "BackdropTemplate")
    f:SetSize(380, 480)
    f:SetPoint("CENTER", UIParent, "CENTER", 360, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    W.backdrop(f)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    W.escapeCloses(f)
    f.title = W.label(f, "", 18, -16, 15)
    f.title:SetWidth(300)
    f.title:SetMaxLines(1)
    f.title:SetJustifyH("LEFT")
    W.button(f, "X", 330, -12, 34, function() f:Hide() end)
    local stage = CreateFrame("Frame", nil, f, "BackdropTemplate")
    stage:SetPoint("TOPLEFT", 12, -44)
    stage:SetPoint("BOTTOMRIGHT", -12, 76)
    local shade = stage:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.55)
    local model = CreateFrame("DressUpModel", nil, stage)
    model:SetAllPoints()
    -- Shown instead of the model when there is nothing to render (uncached NPC, non-wearable item).
    f.fallback = stage:CreateTexture(nil, "ARTWORK")
    f.fallback:SetSize(96, 96)
    f.fallback:SetPoint("CENTER", 0, 20)
    f.fallback:Hide()
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    f.model, f.facing, f.zoom = model, 0, 1
    model:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then f.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function() f.dragX = nil end)
    model:SetScript("OnMouseWheel", function(_, delta)
        f.zoom = math.max(0.4, math.min(3, f.zoom - delta * 0.15))
        safeCall(model, "SetCamDistanceScale", f.zoom)
    end)
    model:SetScript("OnUpdate", function(_, elapsed)
        if f.dragX then
            local x = GetCursorPosition()
            f.facing = f.facing + (x - f.dragX) * 0.02
            f.dragX = x
            safeCall(model, "SetFacing", f.facing)
        elseif f.spin then
            f.facing = f.facing + elapsed * 0.8
            safeCall(model, "SetFacing", f.facing)
        end
    end)
    f.status = W.label(f, "", 18, -416, 11)
    f.status:SetWidth(344)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(0.7, 0.72, 0.78)
    W.button(f, "Reset view", 12, -444, 110, function()
        f.facing, f.zoom = 0, 1
        safeCall(model, "SetFacing", 0)
        safeCall(model, "SetCamDistanceScale", 1)
    end)
    f.spinButton = W.button(f, "Auto-rotate", 128, -444, 110, function() f.spin = not f.spin end)
    f.undressButton = W.button(f, "Undress", 244, -444, 124, function()
        safeCall(model, "Undress")
        if f.kind == "item" then safeCall(model, "TryOn", "item:" .. f.id) end
    end)
    f:SetScript("OnHide", function() f.dragX = nil end)
    self.modelFrame = f
    f:Hide()
end

-- Equip slots that render on a character model; other slots (rings, trinkets, bags...) have no visible model.
local visibleSlots = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
    INVTYPE_CLOAK = true, INVTYPE_TABARD = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

-- Returns equipLoc, icon (either may be nil while the item is not cached).
local function itemAppearance(itemID)
    if type(GetItemInfoInstant) == "function" then
        local ok, _, _, _, equipLoc, icon = pcall(GetItemInfoInstant, itemID)
        if ok and (equipLoc or icon) then return equipLoc, icon end
    end
    if type(GetItemInfo) == "function" then
        local ok, name, _, _, _, _, _, _, _, equipLoc, icon = pcall(GetItemInfo, itemID)
        if ok and name then return equipLoc, icon end
    end
end

-- Asks the server for an uncached creature (the same query a creature link tooltip makes), so SetCreature
-- can render it on a later attempt. Harmless when the client already knows the creature.
local primer
function M:PrimeCreature(id)
    local ok, err = pcall(function()
        primer = primer or CreateFrame("GameTooltip", "MonstratorCreatureCacheTooltip", UIParent, "GameTooltipTemplate")
        primer:SetOwner(UIParent, "ANCHOR_NONE")
        primer:SetHyperlink(("unit:Creature-0-0-0-0-%d-0000000000"):format(id))
        primer:Hide()
    end)
    if not ok then self:Error(tostring(err)) end
    return ok
end

local function showFallback(f, icon)
    f.model:Hide()
    f.fallback:SetTexture(icon or QUESTION_ICON)
    f.fallback:Show()
end

local function showModel(f)
    f.fallback:Hide()
    f.model:Show()
end

function M:ShowModel(kind, id, name)
    if not id then return end
    if not self.modelFrame then self:CreateModelWindow() end
    local f, model = self.modelFrame, self.modelFrame.model
    f:SetScale(self.settings.frameScale)
    f.kind, f.id, f.facing, f.zoom = kind, id, 0, 1
    f.generation = (f.generation or 0) + 1
    f.title:SetText(name or (kind .. " " .. id))
    f.undressButton:SetShown(false)
    f:Show()
    safeCall(model, "ClearModel")
    safeCall(model, "SetFacing", 0)
    safeCall(model, "SetCamDistanceScale", 1)
    local generation, attempts = f.generation, 0
    if kind == "item" then
        local function load()
            if f.generation ~= generation or not f:IsShown() then return end
            attempts = attempts + 1
            local equipLoc, icon = itemAppearance(id)
            if not equipLoc and not icon and attempts < 6 and C_Timer and C_Timer.After then
                itemInfo(id)
                showFallback(f, QUESTION_ICON)
                f.status:SetText(L["Loading item..."])
                C_Timer.After(0.5, load)
            elseif equipLoc and visibleSlots[equipLoc] then
                showModel(f)
                f.undressButton:SetShown(true)
                safeCall(model, "SetUnit", "player")
                safeCall(model, "TryOn", "item:" .. id)
                f.status:SetText(L["Preview on your character.\nDrag to rotate, mouse wheel to zoom."])
            else
                showFallback(f, icon)
                f.status:SetText(equipLoc and equipLoc ~= "" and L["Worn but not visible on a character model; showing its icon."]
                    or L["This item has no 3D model; showing its icon."])
            end
        end
        load()
        return
    end
    showModel(f)
    f.status:SetText(L["Loading model... Drag to rotate, mouse wheel to zoom."])
    local function load()
        if f.generation ~= generation or not f:IsShown() then return end
        attempts = attempts + 1
        safeCall(model, "SetCreature", id)
        local file = safeCall(model, "GetModelFileID")
        if not model.GetModelFileID or (file and file ~= 0) then
            showModel(f)
            f.status:SetText((L["NPC ID %d. Drag to rotate, mouse wheel to zoom."]):format(id))
        elseif attempts < 12 and C_Timer and C_Timer.After then
            if attempts == 1 or attempts == 6 then self:PrimeCreature(id) end
            C_Timer.After(0.5, load)
        else
            showFallback(f, QUESTION_ICON)
            f.status:SetText(L["Model not available: the server did not send this NPC.\nTarget or meet it once, then try again."])
        end
    end
    load()
end
