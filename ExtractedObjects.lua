local _, M = ...

function M:AddExtractedObjects(mapID, add)
    local data = self.extractedObjects
    local version, build = GetBuildInfo()
    if not data then return end
    if data.build ~= tostring(version) .. "." .. tostring(build) or data.locale ~= GetLocale() then
        if not self.clientData.objectMismatchNotice then
            self.clientData.objectMismatchNotice = true
            self:Notice("Extracted objects skipped: client build/locale differs from the local dataset.")
        end
        return
    end
    local entries = data.maps[mapID]
    if not entries then return end
    if not C_Map or type(C_Map.GetWorldPosFromMapPos) ~= "function" or not CreateVector2D then
        if not self.clientData.errors.objects then
            self.clientData.errors.objects = "World-position API unavailable."
            self:Error("Extracted object positions cannot be checked: world-position API unavailable.")
        end
        return
    end
    if self.clientData.errors.objects then return end
    local accepted, rejected = 0, 0
    for _, r in ipairs(entries) do
        local ok, instance, wx, wy = pcall(self.WorldPosition, self, mapID, r[3], r[4])
        if not ok then
            self.clientData.errors.objects = tostring(instance)
            self:Error("Extracted object transform failed: " .. tostring(instance) .. ". Use /monstrator sync to retry.")
            break
        end
        -- Check the extracted assignment against the live transform within one yard.
        if self:IsFinite(instance) and instance == r[5] and self:IsFinite(wx) and self:IsFinite(wy)
            and (wx - r[6]) ^ 2 + (wy - r[7]) ^ 2 <= 1 then
            local sign = r[2]:match("^(.-) %[Sign%]$")
            add({
                key = ("client:object:%d:%d"):format(mapID, r[1]), name = sign and ("Sign: " .. sign) or r[2],
                kind = "location", category = "Objects", mapID = mapID, x = r[3], y = r[4],
                tags = { "landmark" }, source = "client:local-GameObjects",
                build = data.build, locale = data.locale, edition = "Forever",
                verification = "client-object", precision = "map", objectType = r[8],
            })
            accepted = accepted + 1
        else rejected = rejected + 1 end
    end
    self.clientData.objectChecks = self.clientData.objectChecks or {}
    self.clientData.objectChecks[mapID] = { accepted = accepted, rejected = rejected }
    if rejected > 0 and not self.clientData.objectRejectNotice then
        self.clientData.objectRejectNotice = true
        self:Notice("Some extracted objects failed live coordinate verification and were excluded; see /monstrator diagnostic.")
    end
end
