-- Tamper-evident discovery submissions.
-- Every journal record and exact scan sighting carries a seal computed when the game captured or the player
-- reviewed it; a shared submission adds an overall seal. Editing SavedVariables or the pasted text breaks the
-- seals, which the maintainer's `monstrator-db.cjs review` rejects. An addon cannot hide a secret, so this is
-- tamper-evident, not tamper-proof: the review step still holds new or unusual data until other players agree.
-- Pure Lua shared by the game client and the toolchain, so both compute identical seals.
local _, M = ...

local FORMAT = "MONSTRATOR SUBMISSION v1"
local DOMAIN = "monstrator-seal-v1"
-- Float bases keep every product below 2^53 and avoid 32-bit integer wraparound in other Lua runtimes.
local LANES = {
    { 2147483629, 1000003.0 }, { 2147483587, 1000033.0 },
    { 2147483579, 1000037.0 }, { 2147483563, 1000039.0 },
}
-- Field order is part of the format; append only.
local FIELDS = { "key", "kind", "npcID", "name", "category", "mapID", "x", "y", "tags", "source", "build",
    "locale", "verification", "precision", "sightings", "lastSeen", "level", "classification", "edited" }
local INTEGER = { npcID = true, mapID = true, sightings = true, lastSeen = true, level = true }
local HUNDREDTHS = { x = true, y = true }

M.submissionFormat = FORMAT

function M.SealHash(text)
    local out = {}
    for lane, def in ipairs(LANES) do
        local mod, base = def[1], def[2]
        local h = lane * 7919.0
        local function feed(s)
            for i = 1, #s do h = (h * base + s:byte(i) + lane) % mod end
        end
        feed(DOMAIN)
        feed(text)
        feed(("%d"):format(#text))
        out[lane] = ("%08x"):format(h)
    end
    return table.concat(out)
end

local function escape(text)
    return (tostring(text):gsub("[%%|;\r\n]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function fieldText(record, field)
    local value = record[field]
    if field == "tags" then
        local tags = {}
        for _, tag in ipairs(type(value) == "table" and value or {}) do tags[#tags + 1] = escape(tag) end
        return table.concat(tags, ",")
    elseif field == "edited" then
        return value and "1" or ""
    elseif value == nil then
        return ""
    elseif HUNDREDTHS[field] then
        return finite(value) and ("%d"):format(math.floor(value * 100 + 0.5)) or "?"
    elseif INTEGER[field] then
        return finite(value) and ("%d"):format(math.floor(value + 0.5)) or "?"
    end
    return escape(value)
end

function M.CanonicalRecord(record)
    local parts = {}
    for i, field in ipairs(FIELDS) do parts[i] = fieldText(record, field) end
    return table.concat(parts, "|")
end

function M.RecordSeal(record, submitter)
    return M.SealHash(M.CanonicalRecord(record) .. "|" .. tostring(submitter or ""))
end

function M:SubmitterID()
    local s = self.settings
    if type(s.submitterID) ~= "string" or not s.submitterID:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") then
        -- Anonymous and random; it only lets the maintainer count distinct reporters.
        local seed = tostring(time and time() or 0) .. ":" .. tostring(GetTime and GetTime() or 0) .. ":"
            .. tostring(math.random(0, 2147483646)) .. ":" .. tostring(math.random(0, 2147483646))
        s.submitterID = M.SealHash(seed):sub(1, 16)
    end
    return s.submitterID
end

function M:SealRecord(record)
    if type(record) ~= "table" then return end
    record.seal = M.RecordSeal(record, self:SubmitterID())
    return record.seal
end

function M:RecordSealValid(record)
    return type(record) == "table" and type(record.seal) == "string"
        and record.seal == M.RecordSeal(record, self:SubmitterID())
end

-- Exact NPC scan sightings become regular user-confirmed NPC records for sharing.
function M:ScanRecord(hit)
    if type(hit) ~= "table" or not hit.exact or not finite(hit.npcID) or not finite(hit.mapID)
        or not finite(hit.x) or not finite(hit.y) or type(hit.name) ~= "string" or not finite(hit.time) then return end
    return {
        key = ("scan:%d:%d"):format(math.floor(hit.npcID), math.floor(hit.time)), kind = "npc",
        npcID = hit.npcID, name = hit.name, category = "Combat", mapID = hit.mapID, x = hit.x, y = hit.y,
        tags = {}, source = "scan:vignette", build = hit.build, locale = hit.locale,
        verification = "user-confirmed", precision = "confirmed", sightings = 1, lastSeen = hit.time,
        level = hit.level, classification = hit.classification, seal = hit.seal,
    }
end

function M:SealScanHit(hit)
    local record = self:ScanRecord(hit)
    if record then hit.seal = M.RecordSeal(record, self:SubmitterID()) end
end

local function sortedKeys(entries)
    local keys = {}
    for key in pairs(entries) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- Builds the shareable text. Character names, realms and GUIDs are never included.
function M:SubmissionText()
    local records = {}
    for _, key in ipairs(sortedKeys(self.observations.entries)) do
        local record = self.observations.entries[key]
        if self:ValidateRecord(record) and record.kind == "npc"
            and (record.verification == "user-confirmed" or record.verification == "pending") then
            records[#records + 1] = record
        elseif self:ValidateRecord(record) and record.kind == "location" and record.verification == "user-confirmed" then
            records[#records + 1] = record
        end
    end
    for _, hit in ipairs(self.settings.scanLog or {}) do
        local record = self:ScanRecord(hit)
        if record then records[#records + 1] = record end
    end
    if #records == 0 then return nil, 0 end
    local _, build = GetBuildInfo()
    local lines = {
        FORMAT,
        "addon=" .. escape(self.version or ""),
        "build=" .. escape(tostring(build)),
        "locale=" .. escape(GetLocale()),
        "submitter=" .. self:SubmitterID(),
        "created=" .. ("%d"):format(time()),
        "records=" .. #records,
    }
    for _, record in ipairs(records) do
        lines[#lines + 1] = "R|" .. M.CanonicalRecord(record) .. "|" .. (type(record.seal) == "string" and record.seal or "-")
    end
    local body = table.concat(lines, "\n") .. "\n"
    lines[#lines + 1] = "seal=" .. M.SealHash(body)
    lines[#lines + 1] = "END"
    return table.concat(lines, "\n"), #records
end

-- Parses and verifies a submission (also used by the toolchain). Returns nil, reason for unusable text.
-- Each record gets status "sealed", "unsealed" (captured before seals existed) or "tampered".
function M.ParseSubmission(text)
    if type(text) ~= "string" then return nil, "not text" end
    local lines = {}
    for line in (text:gsub("\r\n?", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line:match("^%s*(.-)%s*$")
    end
    local first
    for i, line in ipairs(lines) do if line == FORMAT then first = i; break end end
    if not first then return nil, "no '" .. FORMAT .. "' header" end
    local header, records, body, sealLine = {}, {}, {}, nil
    for i = first, #lines do
        local line = lines[i]
        if line == "END" then break end
        if sealLine then return nil, "text after the overall seal" end
        local overall = line:match("^seal=(%x+)$")
        if overall then sealLine = overall
        else
            body[#body + 1] = line
            if i > first then
                if line:sub(1, 2) == "R|" then
                    records[#records + 1] = line
                else
                    local key, value = line:match("^(%w+)=(.*)$")
                    if not key or #records > 0 then return nil, "malformed line " .. (i - first + 1) end
                    header[key] = unescape(value)
                end
            end
        end
    end
    if not sealLine then return nil, "missing overall seal (copy the whole text, including END)" end
    if sealLine ~= M.SealHash(table.concat(body, "\n") .. "\n") then
        return nil, "overall seal does not match; the submission was edited after it was created"
    end
    if type(header.submitter) ~= "string" or not header.submitter:match("^%x+$") then return nil, "missing submitter" end
    if tonumber(header.records) ~= #records then return nil, "record count does not match header" end
    local result = { header = header, records = {}, seal = sealLine }
    for index, line in ipairs(records) do
        local parts = {}
        for part in (line:sub(3) .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
        local seal = table.remove(parts)
        if #parts ~= #FIELDS then return nil, "record " .. index .. " has " .. #parts .. " fields, expected " .. #FIELDS end
        local record = {}
        for i, field in ipairs(FIELDS) do
            local value = parts[i]
            if field == "tags" then
                record.tags = {}
                for tag in value:gmatch("[^,]+") do record.tags[#record.tags + 1] = unescape(tag) end
            elseif field == "edited" then
                record.edited = value == "1" or nil
            elseif value ~= "" then
                if HUNDREDTHS[field] then record[field] = (tonumber(value) or 0 / 0) / 100
                elseif INTEGER[field] then record[field] = tonumber(value) or 0 / 0
                else record[field] = unescape(value) end
            end
        end
        if seal == "-" then record.status = "unsealed"
        elseif seal == M.SealHash(table.concat(parts, "|") .. "|" .. header.submitter) then record.status = "sealed"
        else record.status = "tampered" end
        result.records[index] = record
    end
    return result
end

function M:ShowSubmission()
    local text, count = self:SubmissionText()
    if not text then
        self:Notice(self.L["Nothing to share yet. Confirm journal placements or catch exact NPC scan sightings first."])
        return
    end
    self:ShowCopy(text)
    self:Notice((self.L["Submission ready: %d records. Copy all of it, including END, into a Monstrator submission issue or a .txt file."]):format(count))
end
