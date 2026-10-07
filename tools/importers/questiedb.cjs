// Converts an installed QuestieDB (Forever) addon into Monstrator's native data files (Data\Native\*.lua).
// Usage: node tools\monstrator-db.cjs import --from questiedb [path\to\QuestieDB] [flavor]
// (or run this file directly with the same arguments). One of Monstrator's pluggable importers: it only
// reads an installed copy of the source addon; nothing from it is loaded or required at runtime.
// Needs the fengari Lua VM: `npm install fengari` somewhere, then set MONSTRATOR_LUA_RUNTIME to its folder
// (or install it next to this script).
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const root = path.resolve(__dirname, '..', '..');
const qdb = path.resolve(process.argv[2] || path.join(root, '..', 'QuestieDB'));
const flavor = process.argv[3] || 'Forever';
// MONSTRATOR_NATIVE_OUT redirects output (used by `monstrator-db verify --determinism`).
const out = path.resolve(process.env.MONSTRATOR_NATIVE_OUT || path.join(root, 'Data', 'Native'));
const crypto = require('node:crypto');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(process.env.MONSTRATOR_LUA_RUNTIME || 'fengari');

const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
function run(source, name, args = []) {
  if (lauxlib.luaL_loadbuffer(state, to_luastring(source), null, to_luastring(name)) !== lua.LUA_OK)
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  for (const a of args) {
    if (typeof a === 'string') lua.lua_pushstring(state, to_luastring(a)); else lua.lua_getglobal(state, to_luastring(a.global));
  }
  if (lua.lua_pcall(state, args.length, 0, 0) !== lua.LUA_OK) throw new Error(name + ': ' + to_jsstring(lua.lua_tostring(state, -1)));
}

const tocPath = path.join(qdb, `QuestieDB_${flavor}.toc`);
if (!fs.existsSync(tocPath)) throw new Error('QuestieDB TOC not found: ' + tocPath);
const tocText = fs.readFileSync(tocPath, 'latin1');
const meta = new Map();
const files = [];
for (const line of tocText.split(/\r?\n/)) {
  const m = line.match(/^## ([^:]+):\s?(.*)$/);
  if (m) meta.set(m[1].toLowerCase(), m[2]);
  else if (line.endsWith('.lua') && !line.startsWith('#')) files.push(line);
}
lua.lua_pushjsfunction(state, L => {
  const value = meta.get(to_jsstring(lauxlib.luaL_checkstring(L, 2)).toLowerCase());
  if (value === undefined) lua.lua_pushnil(L); else lua.lua_pushstring(L, Buffer.from(value, 'latin1'));
  return 1;
});
lua.lua_setglobal(state, to_luastring('__qdbmeta'));

// Minimal C_EncodingUtil for QuestieDB's baked TOC metadata store.
const bytesArg = (L, i) => Buffer.from(lua.lua_tolstring(L, i));
function cborPush(L, buf) {
  let p = 0;
  const arg = info => {
    if (info < 24) return info;
    if (info === 24) return buf[p++];
    if (info === 25) { const v = buf.readUInt16BE(p); p += 2; return v; }
    if (info === 26) { const v = buf.readUInt32BE(p); p += 4; return v; }
    if (info === 27) { const v = Number(buf.readBigUInt64BE(p)); p += 8; return v; }
    throw new Error('indefinite CBOR unsupported ' + info);
  };
  const item = () => {
    const ib = buf[p++], major = ib >> 5, info = ib & 31;
    if (major === 7) {
      if (info === 20) return lua.lua_pushboolean(L, false);
      if (info === 21) return lua.lua_pushboolean(L, true);
      if (info === 22 || info === 23) return lua.lua_pushnil(L);
      let v;
      if (info === 25) {
        const h = buf.readUInt16BE(p), s = h & 0x8000 ? -1 : 1, e = (h >> 10) & 31, f = h & 1023;
        v = e === 0 ? s * f * 2 ** -24 : e === 31 ? (f ? NaN : s * Infinity) : s * (1 + f / 1024) * 2 ** (e - 15);
        p += 2;
      } else if (info === 26) { v = buf.readFloatBE(p); p += 4; }
      else if (info === 27) { v = buf.readDoubleBE(p); p += 8; }
      else throw new Error('simple ' + info);
      return lua.lua_pushnumber(L, v);
    }
    const n = arg(info);
    if (major === 0) return Number.isInteger(n) && n <= 2 ** 53 ? lua.lua_pushinteger(L, n) : lua.lua_pushnumber(L, n);
    if (major === 1) return lua.lua_pushinteger(L, -1 - n);
    if (major === 2 || major === 3) { const s = buf.subarray(p, p + n); p += n; return lua.lua_pushstring(L, Uint8Array.from(s)); }
    if (major === 4) { lua.lua_createtable(L, n, 0); for (let i = 1; i <= n; i++) { item(); lua.lua_rawseti(L, -2, i); } return; }
    if (major === 5) { lua.lua_createtable(L, 0, n); for (let i = 0; i < n; i++) { item(); item(); lua.lua_rawset(L, -3); } return; }
    if (major === 6) return item();
    throw new Error('major ' + major);
  };
  item();
}
lua.lua_createtable(state, 0, 3);
lua.lua_pushjsfunction(state, L => {
  lua.lua_pushstring(L, Uint8Array.from(Buffer.from(bytesArg(L, 1).toString('latin1'), 'base64'))); return 1;
});
lua.lua_setfield(state, -2, to_luastring('DecodeBase64'));
lua.lua_pushjsfunction(state, L => {
  const b = bytesArg(L, 1); let result;
  for (const fn of [zlib.inflateSync, zlib.inflateRawSync, zlib.gunzipSync]) { try { result = fn(b); break; } catch (e) { /* next */ } }
  if (!result) throw new Error('decompress failed');
  lua.lua_pushstring(L, Uint8Array.from(result)); return 1;
});
lua.lua_setfield(state, -2, to_luastring('DecompressString'));
lua.lua_pushjsfunction(state, L => { cborPush(L, bytesArg(L, 1)); return 1; });
lua.lua_setfield(state, -2, to_luastring('DeserializeCBOR'));
lua.lua_setglobal(state, to_luastring('C_EncodingUtil'));

run(`
loadstring = loadstring or load
unpack = unpack or table.unpack
tinsert = tinsert or table.insert
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
bit = bit or { band = function(a, b) return a & b end, bor = function(a, b) return a | b end,
  bxor = function(a, b) return a ~ b end, lshift = function(a, b) return a << b end, rshift = function(a, b) return a >> b end }
C_AddOns = { GetAddOnMetadata = function(name, key) if name:match("^QuestieDB") then return __qdbmeta(name, key) end end }
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
C_Timer = { After = function(_, f) f() end, NewTicker = function() return { Cancel = function() end } end }
CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
GetLocale = function() return "enUS" end
GetTime = function() return 0 end
UnitClassBase = function() return "WARRIOR", 1 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitRace = function() return "Human", "Human", 1 end
UnitFactionGroup = function() return "Alliance" end
UnitLevel = function() return 1 end
GetRealmName = function() return "Forever" end
GetBuildInfo = function() return "1.15.0", "0", "", 11500 end
strsplit = function(sep, s) local t = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = p end return table.unpack(t) end
QDBNS = {}
`, 'shims');
let started = Date.now();
for (const file of files) run(fs.readFileSync(path.join(qdb, file), 'latin1'), file, ['QuestieDB', { global: 'QDBNS' }]);
console.log(`Loaded QuestieDB ${meta.get('version')} (${flavor}) from ${files.length} files in ${Date.now() - started} ms`);

// Each entity becomes one tab-separated string; NativeDB.lua decodes them lazily.
run(String.raw`
local lib = assert(LibQuestieDB, "QuestieDB did not publish LibQuestieDB")
local function read(getter, id)
  if type(getter) ~= "function" then return end
  local ok, value = pcall(getter, id)
  if ok then return value end
end
local zone = lib.Support and lib.Support.Get and lib.Support.Get("ZoneDB")
local areaMap = {}
for _, field in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
  local text = zone and zone.private and zone.private[field]
  if type(text) == "string" then
    for area, uiMap in text:gmatch("%[(%d+)%]%s*=%s*(%d+)") do areaMap[tonumber(area)] = tonumber(uiMap) end
  end
end
assert(next(areaMap), "QuestieDB zone map unavailable")
local function clean(s) return (tostring(s or ""):gsub("[%c]", " ")) end
local function num(v)
  if type(v) ~= "number" or v ~= v then return "" end
  if v % 1 == 0 then return string.format("%d", v) end
  return string.format("%.14g", v)
end
local function ids(list)
  if type(list) ~= "table" then return "" end
  local parts = {}
  for _, id in ipairs(list) do if type(id) == "number" then parts[#parts + 1] = string.format("%d", id) end end
  return table.concat(parts, ",")
end
local function spawns(value)
  if type(value) ~= "table" then return "", 0 end
  local byMap, maps = {}, {}
  for area, points in pairs(value) do
    local uiMap = areaMap[area]
    if uiMap and uiMap > 0 and type(points) == "table" then
      local list = byMap[uiMap]
      if not list then list = { seen = {} }; byMap[uiMap] = list; maps[#maps + 1] = uiMap end
      for _, p in ipairs(points) do
        local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
          local key = num(x) .. "," .. num(y)
          if not list.seen[key] then list.seen[key] = true; list[#list + 1] = key end
        end
      end
    end
  end
  table.sort(maps)
  local parts, count = {}, 0
  for _, uiMap in ipairs(maps) do
    if #byMap[uiMap] > 0 then
      parts[#parts + 1] = uiMap .. ":" .. table.concat(byMap[uiMap], " ")
      count = count + #byMap[uiMap]
    end
  end
  return table.concat(parts, ";"), count
end
local function sorted(list)
  local copy = {}
  for _, id in ipairs(list or {}) do copy[#copy + 1] = id end
  table.sort(copy)
  return copy
end
local function quote(s) return '"' .. s:gsub('[\\"]', "\\%0") .. '"' end
local output, counts = {}, {}
local function emit(kind, rows)
  local lines = {}
  for _, row in ipairs(rows) do lines[#lines + 1] = string.format("D[%d]=%s", row[1], quote(row[2])) end
  output[kind], counts[kind] = table.concat(lines, "\n"), #rows
end

local rows, points = {}, 0
for _, id in ipairs(sorted(lib.Npc.GetAllIds())) do
  local name = read(lib.Npc.name, id)
  if type(name) == "string" and name ~= "" then
    local where, n = spawns(read(lib.Npc.spawns, id))
    points = points + n
    rows[#rows + 1] = { id, table.concat({ clean(name), clean(read(lib.Npc.subName, id)), num(read(lib.Npc.npcFlags, id)),
      num(read(lib.Npc.minLevel, id)), num(read(lib.Npc.maxLevel, id)), clean(read(lib.Npc.friendlyToFaction, id)), where }, "\t") }
  end
end
emit("Npc", rows)
counts.npcSpawns = points

-- Object class drives which objects become directory locations; decorative objects get an empty class.
local questObjects = {}
if lib.Quest then
  for _, id in ipairs(lib.Quest.GetAllIds and lib.Quest.GetAllIds() or {}) do
    for _, getter in ipairs({ lib.Quest.startedBy, lib.Quest.finishedBy }) do
      local by = read(getter, id)
      for _, objectID in ipairs(type(by) == "table" and type(by[2]) == "table" and by[2] or {}) do questObjects[objectID] = true end
    end
  end
end
for _, id in ipairs(lib.Item.GetAllIds()) do
  local drops = read(lib.Item.objectDrops, id)
  for _, objectID in ipairs(type(drops) == "table" and drops or {}) do questObjects[objectID] = true end
end
local herbs = {}
for _, herb in ipairs({ "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
  "Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite",
  "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom", "Gromsblood", "Golden Sansam",
  "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus", "Bloodthistle" }) do herbs[herb] = true end
local exact = { ["Mailbox"] = "mailbox", ["Anvil"] = "anvil", ["Stone Anvil"] = "anvil", ["Forge"] = "forge",
  ["Heated Forge"] = "forge", ["Meeting Stone"] = "meeting_stone", ["Cooking Fire"] = "cooking", ["Cooking Table"] = "cooking",
  ["Campfire"] = "cooking", ["Bonfire"] = "cooking", ["Dwarven Campfire"] = "cooking", ["Floating Wreckage"] = "fishing",
  ["Floating Debris"] = "fishing" }
local function objectClass(id, name)
  if exact[name] then return exact[name] end
  if herbs[name] then return "herb" end
  if name:find("Vein$") or name:find("Deposit$") then return "ore" end
  if name:find("School$") or name:find("^School of ") then return "fishing" end
  if name:find("Chest$") or name:find("Strongbox$") or name:find("Footlocker$") or name:find("Lockbox$")
    or name:find("Coffer$") then return "chest" end
  if questObjects[id] then return "quest" end
  return ""
end

rows, points = {}, 0
local classes = {}
if lib.Object then
  for _, id in ipairs(sorted(lib.Object.GetAllIds and lib.Object.GetAllIds())) do
    local name = read(lib.Object.name, id)
    if type(name) == "string" and name ~= "" then
      local where, n = spawns(read(lib.Object.spawns, id))
      points = points + n
      local class = objectClass(id, clean(name))
      if class ~= "" then classes[class] = (classes[class] or 0) + n end
      rows[#rows + 1] = { id, clean(name) .. "\t" .. where .. "\t" .. class }
    end
  end
end
emit("Object", rows)
counts.objectSpawns = points
local classSummary = {}
for class, n in pairs(classes) do classSummary[#classSummary + 1] = class .. "=" .. n end
table.sort(classSummary)
counts.objectClasses = table.concat(classSummary, " ")

rows = {}
for _, id in ipairs(sorted(lib.Item.GetAllIds())) do
  local name = read(lib.Item.name, id)
  if type(name) == "string" and name ~= "" then
    rows[#rows + 1] = { id, table.concat({ clean(name), num(read(lib.Item.requiredLevel, id)), num(read(lib.Item.itemLevel, id)),
      num(read(lib.Item.class, id)), num(read(lib.Item.subClass, id)), num(read(lib.Item.startQuest, id)),
      ids(read(lib.Item.vendors, id)), ids(read(lib.Item.npcDrops, id)), ids(read(lib.Item.objectDrops, id)),
      ids(read(lib.Item.questRewards, id)), ids(read(lib.Item.itemDrops, id)) }, "\t") }
  end
end
emit("Item", rows)

rows = {}
if lib.Quest then
  for _, id in ipairs(sorted(lib.Quest.GetAllIds and lib.Quest.GetAllIds())) do
    local name = read(lib.Quest.name, id)
    if type(name) == "string" and name ~= "" then
      local starters = read(lib.Quest.startedBy, id)
      local finishers = read(lib.Quest.finishedBy, id)
      starters, finishers = type(starters) == "table" and starters or {}, type(finishers) == "table" and finishers or {}
      rows[#rows + 1] = { id, table.concat({ clean(name), num(read(lib.Quest.questLevel, id)), num(read(lib.Quest.requiredLevel, id)),
        ids(starters[1]), ids(starters[2]), ids(finishers[1]), ids(finishers[2]) }, "\t") }
    end
  end
end
emit("Quest", rows)
NATIVE_OUTPUT, NATIVE_COUNTS = output, counts
`, 'convert');

function global(name) { lua.lua_getglobal(state, to_luastring(name)); }
function field(key) {
  lua.lua_getfield(state, -1, to_luastring(key));
  const value = lua.lua_type(state, -1) === lua.LUA_TSTRING ? Buffer.from(lua.lua_tolstring(state, -1))
    : lua.lua_tonumber(state, -1);
  lua.lua_pop(state, 1);
  return value;
}
global('NATIVE_COUNTS');
const counts = {};
for (const key of ['Npc', 'Object', 'Item', 'Quest', 'npcSpawns', 'objectSpawns', 'objectClasses']) counts[key] = field(key);
lua.lua_pop(state, 1);
counts.objectClasses = counts.objectClasses ? counts.objectClasses.toString('utf8') : '';

const version = meta.get('version') || 'unknown';
const commit = meta.get('x-build-commit') || 'unknown';
const credits = meta.get('author') || 'QuestieDB contributors';
const header = (kind) => [
  `-- Monstrator native ${kind} data. GENERATED by tools\\monstrator-db.cjs import --from questiedb.`,
  `-- Converted from QuestieDB ${version} (${flavor}, build ${commit}).`,
  `-- Imported data, not relicensed. QuestieDB credits: ${credits}`,
  'local _, M = ...',
  `local D = M.NativeData("${kind}", ${JSON.stringify(version)}, ${JSON.stringify(flavor)}, ${JSON.stringify(commit)}, "QuestieDB")`,
  '',
].join('\r\n');
global('NATIVE_OUTPUT');
let total = 0;
const generated = new Map(), candidate = {};
const manifest = {
  generator: 'tools/importers/questiedb.cjs',
  source: { name: 'QuestieDB', version, flavor, commit, homepage: 'https://github.com/Questie/QuestieDB',
    credits: 'QuestieDB and Questie contributors. ' + credits,
    license: 'No license file published by the source; imported data is credited, not relicensed.' },
  spawnPoints: { npc: counts.npcSpawns, object: counts.objectSpawns },
  objectClassPoints: Object.fromEntries(counts.objectClasses.split(' ').filter(Boolean).map(s => {
    const [k, v] = s.split('='); return [k, Number(v)];
  })),
  files: {},
};
for (const kind of ['Npc', 'Object', 'Item', 'Quest']) {
  const body = field(kind).toString('utf8').replace(/\n/g, '\r\n');
  const text = header(kind) + body + '\r\n';
  generated.set(`${kind}s.lua`, text);
  const size = Buffer.byteLength(text, 'utf8');
  total += size;
  manifest.files[`${kind}s.lua`] = { kind, entries: counts[kind], bytes: size,
    sha256: crypto.createHash('sha256').update(text, 'utf8').digest('hex') };
  console.log(`${kind}s.lua: ${counts[kind]} entries, ${(size / 1048576).toFixed(2)} MB`);
}
console.log(`NPC spawn points: ${counts.npcSpawns}, object spawn points: ${counts.objectSpawns}, total ${(total / 1048576).toFixed(2)} MB`);
console.log(`Directory object classes (points): ${counts.objectClasses}`);

// Validate before writing: parity alone can pass when the source itself loses named entities.
const { parseRows, readTables, replacementIssues } = require('../database-audit.cjs');
for (const kind of ['Npc', 'Object', 'Item', 'Quest']) {
  const parsed = parseRows(generated.get(`${kind}s.lua`), kind);
  if (parsed.issues.length) throw new Error(JSON.stringify(parsed.issues.slice(0, 10)));
  candidate[kind] = parsed.rows;
}
const previous = fs.existsSync(path.join(out, 'manifest.json')) ? readTables(out).tables : null;
const blockers = replacementIssues(previous, candidate, process.argv.slice(4).includes('--allow-removals'));
if (blockers.length) {
  for (const issue of blockers.slice(0, 20)) console.error(`${issue.kind} ${issue.id || ''}: ${issue.message}`);
  throw new Error('Import rejected before writing: structural errors or unreviewed coverage loss');
}

// Decode the candidate in memory and compare every entity/field against the live source.
run('NATIVE_M = {}', 'native-namespace');
run(fs.readFileSync(path.join(root, 'NativeDB.lua'), 'utf8'), 'NativeDB.lua', ['Monstrator', { global: 'NATIVE_M' }]);
for (const kind of ['Npc', 'Object', 'Item', 'Quest'])
  run(generated.get(`${kind}s.lua`), `${kind}s.lua`, ['Monstrator', { global: 'NATIVE_M' }]);
run(String.raw`
local live, native = LibQuestieDB, NATIVE_M:NativeProvider()
local problems, checked, rounded, maxError = {}, 0, 0, 0
local function fail(message) if #problems < 25 then problems[#problems + 1] = message end; problems.n = (problems.n or 0) + 1 end
local function read(getter, id)
  if type(getter) ~= "function" then return end
  local ok, value = pcall(getter, id)
  if ok then return value end
end
local zone = live.Support.Get("ZoneDB")
local areaMap = {}
for _, f in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
  for area, uiMap in tostring(zone.private[f] or ""):gmatch("%[(%d+)%]%s*=%s*(%d+)") do areaMap[tonumber(area)] = tonumber(uiMap) end
end
local function same(a, b)
  if type(a) == "string" then a = a:gsub("%c", " ") end
  if a == "" then a = nil end
  if type(a) == "number" and a ~= a then a = nil end
  return a == b
end
local function sameList(a, b)
  local want, have = {}, {}
  for _, v in ipairs(type(a) == "table" and a or {}) do if type(v) == "number" then want[v] = true end end
  for _, v in ipairs(b or {}) do have[v] = true end
  for v in pairs(want) do if not have[v] then return false end end
  for v in pairs(have) do if not want[v] then return false end end
  return true
end
local function sameSpawns(a, b)
  local kept = 0
  for area, points in pairs(type(a) == "table" and a or {}) do
    local uiMap = areaMap[area]
    if uiMap and uiMap > 0 and type(points) == "table" then
      for _, p in ipairs(points) do
        local x, y = type(p) == "table" and p[1], type(p) == "table" and p[2]
        if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
          local best
          for _, q in ipairs(b and b[uiMap] or {}) do
            local e = math.max(math.abs(q[1] - x), math.abs(q[2] - y))
            if not best or e < best then best = e end
          end
          if not best or best > 1e-6 then return false end
          if best > 1e-9 then rounded = rounded + 1 end
          if best > maxError then maxError = best end
          kept = kept + 1
        end
      end
    end
  end
  return true, kept
end
local fields = {
  Npc = { "name", "subName", "npcFlags", "minLevel", "maxLevel", "friendlyToFaction" },
  Object = { "name" },
  Item = { "name", "requiredLevel", "itemLevel", "class", "subClass", "startQuest" },
  Quest = { "name", "questLevel", "requiredLevel" },
}
local lists = { Item = { "vendors", "npcDrops", "objectDrops", "questRewards", "itemDrops" } }
local stats = {}
for kind, names in pairs(fields) do
  local liveIDs, named, missing = read(live[kind].GetAllIds) or {}, 0, 0
  for _, id in ipairs(liveIDs) do
    local name = read(live[kind].name, id)
    if type(name) == "string" and name ~= "" then
      named = named + 1
      if not native[kind].Has(id) then missing = missing + 1; fail(kind .. " " .. id .. " missing")
      else
        for _, f in ipairs(names) do
          if not same(read(live[kind][f], id), native[kind][f](id)) then fail(kind .. " " .. id .. "." .. f .. " differs") end
        end
        for _, f in ipairs(lists[kind] or {}) do
          if not sameList(read(live[kind][f], id), native[kind][f](id)) then fail(kind .. " " .. id .. "." .. f .. " differs") end
        end
        if live[kind].spawns then
          if not sameSpawns(read(live[kind].spawns, id), native[kind].spawns(id)) then fail(kind .. " " .. id .. ".spawns lost points") end
        end
        if kind == "Quest" then
          for _, f in ipairs({ "startedBy", "finishedBy" }) do
            local a, b = read(live.Quest[f], id), native.Quest[f](id)
            a = type(a) == "table" and a or {}
            if not sameList(a[1], b[1]) or not sameList(a[2], b[2]) then fail("Quest " .. id .. "." .. f .. " differs") end
          end
        end
        checked = checked + 1
      end
    end
  end
  stats[#stats + 1] = ("%s %d/%d named (%d unnamed live IDs skipped)"):format(kind, named - missing, named, #liveIDs - named)
end
table.sort(stats)
PARITY = ("checked %d entities (%s); %d coordinates inexact (max error %.6f map %%); %d problems")
  :format(checked, table.concat(stats, ", "), rounded, maxError, problems.n or 0)
PARITY_PROBLEMS = table.concat(problems, "\n")
`, 'parity');
global('PARITY');
console.log('Parity: ' + to_jsstring(lua.lua_tostring(state, -1)));
lua.lua_pop(state, 1);
global('PARITY_PROBLEMS');
const problems = to_jsstring(lua.lua_tostring(state, -1));
lua.lua_pop(state, 1);
if (problems) throw new Error('Import rejected before writing: ' + problems);
fs.mkdirSync(out, { recursive: true });
for (const [name, text] of generated) fs.writeFileSync(path.join(out, name), text, 'utf8');
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', 'utf8');
