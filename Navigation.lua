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
