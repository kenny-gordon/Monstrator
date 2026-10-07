local _, M = ...
local L = M.L

local function traceback(message)
    return tostring(message) .. (debugstack and ("\n" .. debugstack(2)) or "")
end

local function reportException(message)
    if geterrorhandler then geterrorhandler()(message) end
end

function M:NavigateRecord(record)
    local valid, reason = self:ValidateRecord(record)
    if not valid then self:Error(L["Cannot navigate: "] .. reason); return false end
    if record.verification == "pending" then
        self:Error(L["Review the encounter coordinates before navigating."]); return false
    end
    local title, caveat = record.name, nil
    if record.verification == "reference" and record.source:match("^monstrator%-db:") then
        local label = L["Monstrator DB"]
        title, caveat = title .. " [" .. label .. "]", (L[" (%s location - confirm on arrival)"]):format(label)
    elseif record.verification == "reference" then
        title, caveat = title .. " [" .. L["Legacy"] .. "]", L[" (legacy saved location - may have moved on Forever)"]
    end
    self.navigationCaveat = caveat
    local ok = self:SetNavigationWaypoint(record.mapID, record.x, record.y, title)
    self.navigationCaveat = nil
    return ok
end

function M:ViewRecordOnMap(record)
    local valid, reason = self:ValidateRecord(record)
    if not valid then self:Error(L["Cannot navigate: "] .. reason); return false end
    if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapInfo(record.mapID) then
        self:Error(L["Waypoint map is unknown to this client."]); return false
    end
    if InCombatLockdown and InCombatLockdown() then self:Error(L["map.combat"]); return false end
    local ok, err = xpcall(function()
        if not WorldMapFrame and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_WorldMap") end
        local map = WorldMapFrame
        if not map or not map.SetMapID or not map.GetMapID or not map.ScrollContainer
            or not map.ScrollContainer.Child then error(L["map.unavailable"]) end
        if ShowUIPanel then ShowUIPanel(map) else map:Show() end
        map:SetMapID(record.mapID)
        if not map:IsShown() or map:GetMapID() ~= record.mapID then error(L["map.unavailable"]) end
        if not self.mapPreview then
            local pin = CreateFrame("Button", nil, map.ScrollContainer.Child)
            pin:SetSize(28, 28)
            pin:SetFrameLevel(map.ScrollContainer.Child:GetFrameLevel() + 20)
            pin.icon = pin:CreateTexture(nil, "ARTWORK")
            pin.icon:SetAllPoints()
            pin.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            pin:SetScript("OnEnter", function(owner)
                local r = owner.record
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetText(r.name)
                GameTooltip:AddLine(("%.1f, %.1f"):format(r.x, r.y), 1, 1, 1)
                GameTooltip:AddLine(L[r.verification], 1, 0.82, 0, true)
                if r.verification == "pending" then
                    GameTooltip:AddLine(L["Review the encounter coordinates before navigating."], 1, 0.6, 0.2, true)
                end
                GameTooltip:Show()
            end)
            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
            local function position(owner)
                local canvas = map.ScrollContainer.Child
                local width, height = canvas:GetWidth(), canvas:GetHeight()
                local r = owner.record
                local visible = map:GetMapID() == r.mapID
                owner.icon:SetShown(visible)
                owner:EnableMouse(visible)
                if visible then
                    owner:ClearAllPoints()
                    owner:SetPoint("CENTER", canvas, "TOPLEFT", width * r.x / 100, -height * r.y / 100)
                end
            end
            pin.position = position
            pin:SetScript("OnUpdate", position)
            self.mapPreview = pin
        end
        self.mapPreview.record = record
        self.mapPreview.position(self.mapPreview)
        self.mapPreview:Show()
        if self.window then self.window:Hide() end
    end, traceback)
    if not ok then self:Error(tostring(err)); return false end
    return true
end

function M:SetNavigationWaypoint(mapID, x, y, title)
    if not self:IsFinite(mapID) or mapID < 1 or mapID % 1 ~= 0
        or not self:IsFinite(x) or not self:IsFinite(y) or x < 0 or x > 100 or y < 0 or y > 100
        or type(title) ~= "string" or title == "" then
        self:Error(L["Invalid waypoint input."]); return false
    end
    if not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapInfo(mapID) then
        self:Error(L["Waypoint map is unknown to this client."]); return false
    end
    if TomTom and type(TomTom.AddWaypoint) == "function" then
        local ok, handle = xpcall(function()
            local waypoint = TomTom:AddWaypoint(mapID, x / 100, y / 100, {
                title = "Monstrator: " .. title, persistent = false, minimap = true,
                world = true, crazy = true, cleardistance = 10, arrivaldistance = 10,
            })
            if not waypoint then return nil end
            if TomTom.IsValidWaypoint and not TomTom:IsValidWaypoint(waypoint) then return nil end
            if TomTom.SetCrazyArrow then TomTom:SetCrazyArrow(waypoint, 10, "Monstrator: " .. title) end
            return waypoint
        end, traceback)
        if ok and handle then
            self:Notice(L["TomTom arrow set: "] .. title .. (self.navigationCaveat or ""))
            return true
        end
        self:Error(L["TomTom rejected waypoint: "] .. tostring(handle))
        if not ok then reportException(handle) end
    end
    if type(C_Map.SetUserWaypoint) == "function" and type(C_Map.GetUserWaypoint) == "function"
        and type(C_Map.CanSetUserWaypointOnMap) == "function"
        and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function" then
        local ok, result = xpcall(function()
            if not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
            local pin = C_Map.GetUserWaypoint()
            if not pin or pin.uiMapID ~= mapID or not pin.position then return false end
            local px, py = pin.position:GetXY()
            return math.abs(px - x / 100) < 0.0001 and math.abs(py - y / 100) < 0.0001
        end, traceback)
        if ok and result then
            self:Notice(L["Map pin set (no TomTom arrow): "] .. title .. (self.navigationCaveat or ""))
            return true
        end
        self:Error(L["Native pin unavailable/rejected: "] .. tostring(result))
        if not ok then reportException(result) end
    end
    self:Notice(L["No navigation provider accepted this waypoint. Showing coordinates for manual copying."])
    self:ShowCopy(("%s\nMap ID %d: %.2f, %.2f\nTomTom command: /way #%d %.2f %.2f %s"):format(
        title, mapID, x, y, mapID, x, y, title))
    return false
end
