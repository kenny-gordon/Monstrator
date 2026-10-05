-- Tamper-evident submissions: record seals, edit detection, merge/review resealing and the shared text format.
assert(M.ready, "submission tests need an initialized addon")
local s = M.settings
local savedID = s.submitterID
s.submitterID = nil
local id = M:SubmitterID()
assert(id:match("^%x+$") and #id == 16, "an anonymous 16-hex reporter ID is created on demand")
assert(M:SubmitterID() == id, "the reporter ID is stable")

assert(#M.SealHash("abc") == 32 and M.SealHash("abc") == M.SealHash("abc"), "seals are 32 hex digits and deterministic")
assert(M.SealHash("abc") ~= M.SealHash("abd") and M.SealHash("") ~= M.SealHash(" "), "one changed byte changes the seal")
-- Fixed vector: changing the algorithm would orphan every seal already captured in game.
SUBMISSION_VECTOR_OUT = M.SealHash("Monstrator")

local entries = M.observations.entries
for key in pairs(entries) do entries[key] = nil end
M.fullNotice = nil
local function observation(name, npcID, x, y, extra)
    local r = M:NewObservation(name, "npc", "Vendors", { "vendor" }, "MERCHANT_SHOW")
    r.npcID, r.x, r.y = npcID, x, y
    for k, v in pairs(extra or {}) do r[k] = v end
    return M:AddObservation(r)
end
local a = observation("Seal | Tester; 100%", 9001, 40.123, 50.456)
assert(a and type(a.seal) == "string" and M:RecordSealValid(a), "new journal records are sealed at capture")
local firstSeal = a.seal
observation("Seal | Tester; 100%", 9001, 40.13, 50.46)
assert(a.sightings == 2 and a.seal ~= firstSeal and M:RecordSealValid(a), "merged sightings reseal intact records")

-- Editing SavedVariables by hand breaks the seal, and a later in-game merge must not launder it.
a.x = 41.5
assert(not M:RecordSealValid(a), "hand-edited coordinates break the seal")
a.x = 40.123
assert(M:RecordSealValid(a), "restoring the value restores the seal")
a.name = "Seal | Tester; 100%"
local b = observation("Laundered", 9002, 10, 10)
b.level = 99
local broken = b.seal
observation("Laundered", 9002, 10.01, 10.01)
assert(b.seal == broken and not M:RecordSealValid(b), "merges never reseal a broken record")

-- Review: confirming in place reseals; moving it by hand or confirming a broken record flags it as edited.
assert(M:Review(a, "accept", a.x, a.y, "Vendors", "vendor"))
assert(a.verification == "user-confirmed" and M:RecordSealValid(a) and not a.edited, "confirmed in place")
assert(M:Review(b, "accept", 30, 30, "Vendors", "vendor"))
assert(b.edited == true and M:RecordSealValid(b), "moved/broken records are resealed but flagged edited")

-- Exact scan sightings are sealed when logged.
wipe(s.scanLog)
M.scanSeen = {}
M:ScanAlert({ npcID = 9100, name = "Exact Rare", reason = "rare", source = "vignette", mapID = 1, x = 12.5, y = 13.5, exact = true })
local hit = s.scanLog[1]
assert(hit.seal and hit.build and hit.locale, "scan sightings carry build, locale and a seal")
local scan = M:ScanRecord(hit)
assert(scan.seal == M.RecordSeal(scan, id), "scan seal matches its shared record form")
M:ScanAlert({ npcID = 9101, name = "Approximate", reason = "rare", source = "nameplate" })
assert(M:ScanRecord(s.scanLog[1]) == nil, "approximate sightings are not shared")

-- The whole submission round-trips through the parser and detects edits anywhere.
local text, count = M:SubmissionText()
assert(text and count == 3, "two journal records and one exact scan sighting are shared")
assert(not text:find("Player", 1, true) and text:find("submitter=" .. id, 1, true), "no character names, only the reporter ID")
local parsed = assert(M.ParseSubmission("Pasted in an issue:\n```\n" .. text:gsub("\n", "\r\n") .. "\n```\nthanks"))
assert(#parsed.records == 3 and parsed.header.submitter == id and parsed.seal, "surrounding text and CRLF are tolerated")
local byName = {}
for _, r in ipairs(parsed.records) do byName[r.name] = r end
local sealed = byName["Seal | Tester; 100%"]
assert(sealed and sealed.status == "sealed" and sealed.npcID == 9001 and math.abs(sealed.x - 40.12) < 1e-9
    and sealed.verification == "user-confirmed" and sealed.tags[1] == "vendor", "escaped fields decode")
assert(byName.Laundered.edited == true and byName["Exact Rare"].source == "scan:vignette")

local function fails(edited, pattern)
    local result, reason = M.ParseSubmission(edited)
    assert(result == nil and reason:find(pattern), "expected rejection: " .. tostring(reason))
end
fails(text:gsub("|4012|", "|4500|", 1), "overall seal")
fails(text:gsub("\nEND$", ""):gsub("\nseal=%x+$", ""), "missing overall seal")
fails(text:gsub("records=3", "records=2"), "overall seal")
fails("hello", "header")

-- A forged record with a recomputed overall seal is still caught by its record seal.
local lines = {}
for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
for i, line in ipairs(lines) do
    if line:find("|4012|", 1, true) then lines[i] = line:gsub("|4012|", "|4500|", 1) end
end
table.remove(lines); table.remove(lines)
local body = table.concat(lines, "\n") .. "\n"
local forged = assert(M.ParseSubmission(body .. "seal=" .. M.SealHash(body) .. "\nEND"))
local forgedStatus
for _, r in ipairs(forged.records) do if r.npcID == 9001 then forgedStatus = r.status end end
assert(forgedStatus == "tampered", "record seals catch edits even when the overall seal is redone")

-- Legacy records captured before seals existed are shared but marked unsealed.
a.seal = nil
local legacy = assert(M.ParseSubmission((M:SubmissionText())))
for _, r in ipairs(legacy.records) do if r.npcID == 9001 then assert(r.status == "unsealed") end end

SUBMISSION_SAMPLE = M:SubmissionText()
local savedCopy, copied = M.ShowCopy, nil
M.ShowCopy = function(_, value) copied = value end
M:ShowSubmission()
assert(copied == SUBMISSION_SAMPLE, "Share discoveries opens the copy window with the submission")
copied = nil
for key in pairs(entries) do entries[key] = nil end
wipe(s.scanLog)
M:ShowSubmission()
assert(copied == nil, "nothing to share opens nothing")
M.ShowCopy = savedCopy
s.submitterID = savedID or id
