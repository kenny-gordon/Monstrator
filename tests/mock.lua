M = {}
messages = {}
print = function(message) table.insert(messages, tostring(message)) end
SlashCmdList = {}
STANDARD_TEXT_FONT = "test-font"
WOW_PROJECT_ID = 1
function wipe(t) for key in pairs(t) do t[key] = nil end end
function GetBuildInfo() return "1.60.1", "test", "test-date", 16001 end
function GetLocale() return "enUS" end
function UnitFactionGroup() return "Alliance" end
function time() return 1234 end
clock = 0
function GetTime() return clock end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function strsplit(delimiter, value)
    local result = {}
    for part in value:gmatch("[^" .. delimiter .. "]+") do table.insert(result, part) end
    return table.unpack(result)
end
function UnitGUID() return "Creature-0-0-0-0-123-0001" end
function UnitName() return "Synthetic Vendor" end
function CanMerchantRepair() return true end
function CreateVector2D(x, y)
    return { GetXY = function() return x, y end }
end
playerMap, playerX, playerY = 1, 0.1, 0.1
worldPositionCalls = 0
C_Map = {
    GetMapInfo = function(id) if id == 1 or id == 2 then return { name = "Synthetic Map" } end end,
    GetBestMapForUnit = function() return playerMap end,
    GetPlayerMapPosition = function() return CreateVector2D(playerX, playerY) end,
    GetWorldPosFromMapPos = function(id, pos)
        worldPositionCalls = worldPositionCalls + 1
        local x, y = pos:GetXY()
        return id, CreateVector2D(x * 1000, y * 1000)
    end,
}
pendingTimers, tickers = {}, {}
C_Timer = {
    After = function(_, callback) table.insert(pendingTimers, callback) end,
    NewTicker = function(interval, callback)
        local ticker = { interval = interval, callback = callback, Cancel = function(self) self.cancelled = true end }
        table.insert(tickers, ticker)
        return ticker
    end,
}
C_Texture = { GetAtlasInfo = function(atlas)
    if atlas == "QuestBG-Parchment" then return { width = 384, height = 512 } end
    if atlas == "honorsystem-bar-rewardborder-circle" then return { width = 36, height = 36 } end
end }
local methods = {}
uiCalls = { text = 0, font = 0, color = 0 }
function methods:SetPoint(point, x, y) self.point, self.x, self.y = point, x, y end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:SetMaxLines(value) self.maxLines = value end
function methods:SetWordWrap(value) self.wordWrap = value end
function methods:SetNonSpaceWrap(value) self.nonSpaceWrap = value end
function methods:SetShadowOffset(x, y) self.shadowX, self.shadowY = x, y end
function methods:SetSpacing(value) self.spacing = value end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked == true end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetTexCoord(left, right, top, bottom) self.texCoords = { left, right, top, bottom } end
function methods:AddMaskTexture(mask) self.mask = mask end
function methods:RemoveMaskTexture(mask) assert(self.mask == mask); self.mask = nil end
function methods:SetAtlas(atlas) self.atlas = atlas end
function methods:SetNormalTexture(asset)
    assert(asset ~= nil, "SetNormalTexture requires an asset")
    self.normalTexture = asset
end
function methods:SetPushedTexture(asset)
    assert(asset ~= nil, "SetPushedTexture requires an asset")
    self.pushedTexture = asset
end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetScript(key, fn) self.scripts[key] = fn end
function methods:GetScript(key) return self.scripts[key] end
function methods:SetText(text)
    uiCalls.text = uiCalls.text + 1
    self.text = text
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return rawget(self, "text") or "" end
function methods:GetFont() return rawget(self, "font") or "font", rawget(self, "fontSize") or 12, "" end
function methods:SetFont(path, size)
    uiCalls.font = uiCalls.font + 1
    self.font, self.fontSize = path, size
end
function methods:SetTextColor(r, g, b)
    uiCalls.color = uiCalls.color + 1
    self.color = { r, g, b }
end
function methods:SetPropagateKeyboardInput(value) self.propagates = value end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:IsShown() return self.shown end
function methods:Show()
    local old = self.shown; self.shown = true
    if not old and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local old = self.shown; self.shown = false
    if old and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HasFocus() return rawget(self, "focused") == true end
function methods:GetCenter() return 100, 100 end
function methods:GetEffectiveScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
local function object()
    return setmetatable({ shown = true, scripts = {} }, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^[A-Z]") then return function() end end
    end })
end
function methods:CreateFontString() return object() end
function methods:GetFontString() return object() end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:CreateTexture() return object() end
function methods:CreateMaskTexture() return object() end
function CreateFrame(kind, name, parent, template)
    local frame = object()
    frame.kind, frame.name, frame.parent, frame.template = kind, name, parent, template
    if template == "UIPanelScrollFrameTemplate" then frame.ScrollBar = object() end
    if template == "UIPanelButtonTemplate" then
        frame.Left, frame.Middle, frame.Right = object(), object(), object()
    end
    if template == "PortraitFrameTemplate" then
        frame.PortraitContainer = { portrait = object() }
        frame.TitleContainer = { TitleText = object() }
        frame.CloseButton = object()
        frame.CloseButton.template = "UIPanelCloseButtonDefaultAnchors"
    end
    if template == "PanelTabButtonTemplate" then
        frame.Text = object()
        frame.Left, frame.Middle, frame.Right = object(), object(), object()
        frame.LeftActive, frame.MiddleActive, frame.RightActive = object(), object(), object()
    end
    return frame
end
function PanelTemplates_SelectTab(tab)
    tab.Left:Hide(); tab.Middle:Hide(); tab.Right:Hide()
    tab.LeftActive:Show(); tab.MiddleActive:Show(); tab.RightActive:Show()
end
function PanelTemplates_DeselectTab(tab)
    tab.Left:Show(); tab.Middle:Show(); tab.Right:Show()
    tab.LeftActive:Hide(); tab.MiddleActive:Hide(); tab.RightActive:Hide()
end
UIParent, Minimap, GameTooltip = object(), object(), object()
math.atan2 = math.atan
