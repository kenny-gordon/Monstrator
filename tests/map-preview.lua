local savedMap, savedCombat, savedPanel = WorldMapFrame, InCombatLockdown, ShowUIPanel
local savedPreview = M.mapPreview
local map = CreateFrame("Frame")
map.ScrollContainer = { Child = CreateFrame("Frame") }
map.ScrollContainer.Child:SetSize(1000, 800)
map.SetMapID = function(self, id) self.mapID = id end
map.GetMapID = function(self) return self.mapID end
WorldMapFrame = map
ShowUIPanel = function(frame) frame:Show() end
InCombatLockdown = function() return false end
M.mapPreview = nil
local record = { key = "map-preview", name = "Map test", kind = "location", category = "Landmarks",
    mapID = 1, x = 25, y = 75, tags = {}, source = "synthetic-test", permission = "test",
    build = "test", locale = "enUS", edition = "Forever", precision = "confirmed", verification = "curated" }
local navigation = M.SetNavigationWaypoint
M.SetNavigationWaypoint = function() error("preview must not change navigation") end
assert(M:ViewRecordOnMap(record) and map:IsShown() and map.mapID == 1)
local pin = M.mapPreview
assert(pin.record == record and pin.icon:IsShown() and not M.window:IsShown())
local px, py
pin.SetPoint = function(_, point, canvas, relative, x, y)
    assert(point == "CENTER" and canvas == map.ScrollContainer.Child and relative == "TOPLEFT")
    px, py = x, y
end
pin.position(pin)
assert(px == 250 and py == -600, "preview places the marker at actual normalized coordinates")
map.ScrollContainer.Child:SetSize(2000, 1600)
pin:GetScript("OnUpdate")(pin)
assert(px == 500 and py == -1200, "marker tracks resized or zoomed canvas coordinates")
map.mapID = 2
pin:GetScript("OnUpdate")(pin)
assert(not pin.icon:IsShown(), "marker must not leak onto other zones")
map.mapID = 1
pin:GetScript("OnUpdate")(pin)
assert(pin.icon:IsShown())
record.verification, record.precision = "pending", "encounter"
assert(M:ViewRecordOnMap(record), "encounter can be previewed without confirming it or navigating")
assert(record.verification == "pending")
local results, selected, view, shift = M.results, M.selected, M.view, IsShiftKeyDown
M.results, M.selected, M.view = { { record = record } }, 1, "directory"
M:Render()
M.window.info.map:Click()
assert(M.mapPreview.record == record, "selected-entry map button previews its record")
M.window.info.sections[1].mapButton:Click()
assert(M.mapPreview.record == record, "clicking the Location coordinates opens their map preview")
IsShiftKeyDown = function() return true end
M.window.rows[1]:GetScript("OnClick")(M.window.rows[1], "LeftButton")
assert(M.mapPreview.record == record, "Shift-click opens the preview without invoking navigation")
IsShiftKeyDown = shift
M.results, M.selected, M.view = results, selected, view
M:Render()
InCombatLockdown = function() return true end
assert(not M:ViewRecordOnMap(record), "protected map UI is not opened in combat")
InCombatLockdown = function() return false end
local x = record.x
record.x = 101
assert(not M:ViewRecordOnMap(record), "invalid coordinates must be rejected")
record.x = x
WorldMapFrame = {}
assert(not M:ViewRecordOnMap(record), "unsupported world map must report failure")
M.SetNavigationWaypoint = navigation
WorldMapFrame, InCombatLockdown, ShowUIPanel = savedMap, savedCombat, savedPanel
pin:Hide()
M.mapPreview = savedPreview
