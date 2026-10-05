#!/usr/bin/env node
// Monstrator's native database toolchain: import, corrections, verification, determinism and packaging,
// plus harvesting what players actually confirmed on the Forever server back into the shipped data.
//
//   node tools\monstrator-db.cjs import [--from <importer>] [dir]  convert an installed data source into Data\Native
//   node tools\monstrator-db.cjs harvest [SavedVariables] [--include-pending]
//                                                          fold in-game sightings + exact NPC scan sightings
//                                                          into Data\Source\Discoveries.lua
//   node tools\monstrator-db.cjs review <file|folder>... [--apply] [--min-reporters N] [--accept-held]
//                                                          check player submissions (/monstrator submit): reject
//                                                          broken seals, hold new/unusual data until N players agree,
//                                                          --apply merges accepted records into Discoveries
//   node tools\monstrator-db.cjs overlay                   build Data\Native\Overlay.lua from Discoveries + Corrections
//   node tools\monstrator-db.cjs verify [--determinism [importer args]]  schema, references, hashes (and re-import compare)
//   node tools\monstrator-db.cjs diff <other Data\Native>   added/removed/changed IDs per kind
//   node tools\monstrator-db.cjs stats                     database summary
//   node tools\monstrator-db.cjs package [--standalone]    dist\Monstrator-<version>[-standalone].zip with CREDITS.md;
//                                                          --standalone ships no imported data
//   node tools\monstrator-db.cjs build [import args]       import + overlay + verify
//
// Lua files are evaluated with fengari: set MONSTRATOR_LUA_RUNTIME to its folder or `npm install fengari`.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const nativeDir = path.join(root, 'Data', 'Native');
const sourceDir = process.env.MONSTRATOR_SOURCE_DIR ? path.resolve(process.env.MONSTRATOR_SOURCE_DIR) : path.join(root, 'Data', 'Source');
const KINDS = ['Npc', 'Object', 'Item', 'Quest'];
const LAYOUT = {
  Npc: ['name', 'subName', 'npcFlags', 'minLevel', 'maxLevel', 'friendlyToFaction', 'spawns'],
  Object: ['name', 'spawns', 'class'],
  Item: ['name', 'requiredLevel', 'itemLevel', 'class', 'subClass', 'startQuest', 'vendors', 'npcDrops',
    'objectDrops', 'questRewards', 'itemDrops'],
  Quest: ['name', 'questLevel', 'requiredLevel', 'starterNpcs', 'starterObjects', 'finisherNpcs', 'finisherObjects'],
};
const LISTS = new Set(['vendors', 'npcDrops', 'objectDrops', 'questRewards', 'itemDrops', 'starterNpcs',
  'starterObjects', 'finisherNpcs', 'finisherObjects']);
const NUMBERS = new Set(['npcFlags', 'minLevel', 'maxLevel', 'requiredLevel', 'itemLevel', 'class', 'subClass',
  'startQuest', 'questLevel']);
// Observation tags/events -> creature npcFlags bits (same bits NativeIndex.lua decodes).
const TAG_FLAGS = { quest_giver: 2, vendor: 4, flight: 8, trainer: 16, innkeeper: 128, bank: 256, guild: 512,
  tabard: 1024, auction: 4096, stable: 8192, repair: 16384 };
const EVENT_FLAGS = { 'local:MERCHANT_SHOW': 4, 'local:TRAINER_SHOW': 16, 'local:TAXIMAP_OPENED': 8 };
const SAME_POINT = 0.5;  // map % - closer points are one spawn
const DRIFT = 2.0;       // map % - farther from every known spawn is reported as drift

// ---------------------------------------------------------------- helpers
const fail = (message) => { console.error('error: ' + message); process.exit(1); };
const rel = (p) => path.relative(root, p) || '.';
const sha256 = (data) => crypto.createHash('sha256').update(data).digest('hex');
const fmt = (n) => String(Math.round(n * 1000) / 1000);
const luaQuote = (s) => '"' + String(s).replace(/[\\"]/g, '\\$&').replace(/[\r\n]/g, ' ') + '"';
const luaLiteral = (s) => '"' + String(s).replace(/[\\"]/g, '\\$&').replace(/\r/g, '\\r').replace(/\n/g, '\\n') + '"';
const round = (n) => Math.round(Number(n) * 100) / 100;
// Lua tables keyed 1..n arrive as JS arrays; return [numericKey, value] pairs either way.
const entries = (value) => (Array.isArray(value) ? value.map((v, i) => [i + 1, v]) : Object.entries(value || {}).map(([k, v]) => [Number(k), v]));

function lua() {
  const runtime = process.env.MONSTRATOR_LUA_RUNTIME || 'fengari';
  try { return require(runtime); } catch { fail('fengari not found; set MONSTRATOR_LUA_RUNTIME or npm install fengari'); }
}

// Evaluates Lua source and returns `expr` converted to plain JS (tables with 1..n keys become arrays).
function evalLua(source, name, expr) {
  const { lua: L, lauxlib, lualib, to_luastring, to_jsstring } = lua();
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  const program = `${source}\nreturn __monstrator_json(${expr})`;
  const json = String.raw`
function __monstrator_json(value)
  local out = {}
  local function emit(v)
    local t = type(v)
    if t == "table" then
      local n = #v
      local count = 0
      for _ in pairs(v) do count = count + 1 end
      if count > 0 and count == n then
        out[#out + 1] = "["
        for i = 1, n do if i > 1 then out[#out + 1] = "," end emit(v[i]) end
        out[#out + 1] = "]"
      else
        out[#out + 1] = "{"
        local first = true
        for k, item in pairs(v) do
          if not first then out[#out + 1] = "," end
          first = false
          out[#out + 1] = string.format("%q", tostring(k)):gsub("\\\n", "\\n") .. ":"
          emit(item)
        end
        out[#out + 1] = "}"
      end
    elseif t == "string" then
      out[#out + 1] = (string.format("%q", v):gsub("\\\n", "\\n"):gsub("\\(%d+)", function(d) return string.format("\\u%04x", tonumber(d)) end))
    elseif t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
      elseif math.type and math.type(v) == "integer" then out[#out + 1] = tostring(v)
      else out[#out + 1] = string.format("%.17g", v) end
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    else out[#out + 1] = "null" end
  end
  emit(value)
  return table.concat(out)
end
`;
  for (const [chunk, label] of [[json, 'json'], [program, name]]) {
    if (lauxlib.luaL_loadbuffer(state, to_luastring(chunk), null, to_luastring(label)) !== L.LUA_OK)
      fail(`${label}: ${to_jsstring(L.lua_tostring(state, -1))}`);
    if (L.lua_pcall(state, 0, label === name ? 1 : 0, 0) !== L.LUA_OK) fail(`${label}: ${to_jsstring(L.lua_tostring(state, -1))}`);
  }
  const text = to_jsstring(L.lua_tostring(state, -1));
  return JSON.parse(text);
}

function readSource(file, fallback) {
  if (!fs.existsSync(file)) return fallback;
  const value = evalLua(`local __source = (function()\n${fs.readFileSync(file, 'utf8')}\nend)()`, rel(file), '__source');
  return value && typeof value === 'object' ? value : fallback;
}

// Parses a generated Data\Native\<Kind>s.lua file into Map<id, rawRow>.
function readNative(dir, kind) {
  const rows = new Map();
  const file = path.join(dir, `${kind}s.lua`);
  if (!fs.existsSync(file)) return rows;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^D\[(\d+)\]="(.*)"$/);
    if (m) rows.set(Number(m[1]), m[2].replace(/\\(.)/g, '$1'));
  }
  return rows;
}

function decodeRow(kind, raw) {
  const fields = raw.split('\t');
  const row = {};
  LAYOUT[kind].forEach((name, i) => {
    const value = fields[i] ?? '';
    if (value === '') return;
    if (name === 'spawns') row.spawns = decodeSpawns(value);
    else if (LISTS.has(name)) row[name] = value.split(',').map(Number);
    else if (NUMBERS.has(name) && !(kind === 'Object' && name === 'class')) row[name] = Number(value);
    else row[name] = value;
  });
  return row;
}

function encodeRow(kind, row) {
  return LAYOUT[kind].map((name) => {
    const value = row[name];
    if (value === undefined || value === null || value === '') return '';
    if (name === 'spawns') return encodeSpawns(value);
    if (LISTS.has(name)) return [...new Set(value.map(Number))].join(',');
    return String(value).replace(/[\t\r\n]/g, ' ');
  }).join('\t');
}

function decodeSpawns(text) {
  const spawns = {};
  for (const part of text.split(';')) {
    const [map, points] = part.split(':');
    if (!points) continue;
    spawns[map] = points.split(' ').filter(Boolean).map((p) => p.split(',').map(Number));
  }
  return spawns;
}

function encodeSpawns(spawns) {
  return Object.keys(spawns).map(Number).sort((a, b) => a - b)
    .filter((map) => spawns[map] && spawns[map].length)
    .map((map) => `${map}:${spawns[map].map(([x, y]) => `${fmt(x)},${fmt(y)}`).join(' ')}`).join(';');
}

// Lua arrays-of-pairs may arrive as JS arrays or as {"1":[..]} objects; normalize to {map: [[x,y],...]}.
function normalizeSpawns(value) {
  const spawns = {};
  for (const [map, points] of entries(value)) {
    const list = Array.isArray(points) ? points : Object.values(points || {});
    // Non-finite Lua numbers arrive as null; drop them instead of letting them coerce to (0,0).
    spawns[map] = list.map((p) => (Array.isArray(p) ? p : [p[1] ?? p.x, p[2] ?? p.y]))
      .filter((p) => p.length >= 2 && p.every((v) => typeof v === 'number' && Number.isFinite(v)))
      .map((p) => p.map(round));
  }
  return spawns;
}

function nearest(points, x, y) {
  let best = Infinity;
  for (const [px, py] of points || []) best = Math.min(best, Math.hypot(px - x, py - y));
  return best;
}

function addPoint(spawns, map, x, y) {
  if (!Number.isFinite(x) || !Number.isFinite(y)) return false;
  x = round(x); y = round(y);
  spawns[map] = spawns[map] || [];
  if (nearest(spawns[map], x, y) <= SAME_POINT) return false;
  spawns[map].push([x, y]);
  return true;
}

function writeLuaTable(value, indent = '') {
  const pad = indent + '  ';
  if (Array.isArray(value)) {
    if (value.every((v) => typeof v !== 'object')) return '{ ' + value.map((v) => writeLuaTable(v)).join(', ') + ' }';
    return '{\n' + value.map((v) => pad + writeLuaTable(v, pad) + ',').join('\n') + '\n' + indent + '}';
  }
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort((a, b) => (/^\d+$/.test(a) && /^\d+$/.test(b) ? a - b : a.localeCompare(b)));
    if (!keys.length) return '{}';
    return '{\n' + keys.map((k) => `${pad}${/^\d+$/.test(k) ? `[${k}]` : /^[A-Za-z_]\w*$/.test(k) ? k : `[${luaQuote(k)}]`} = ${writeLuaTable(value[k], pad)},`).join('\n') + '\n' + indent + '}';
  }
  if (typeof value === 'string') return luaQuote(value);
  return String(value);
}

function manifest() {
  const file = path.join(nativeDir, 'manifest.json');
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
}

// ---------------------------------------------------------------- import
// Importers live in tools\importers\<name>.cjs. Each reads an installed copy of another data source and writes
// Data\Native\<Kind>s.lua + manifest.json in Monstrator's own format (with a parity check against the source).
// Nothing they read is needed at runtime, so the addon never depends on the source being installed.
const IMPORTERS = Object.fromEntries(fs.readdirSync(path.join(__dirname, 'importers'))
  .filter((f) => f.endsWith('.cjs')).map((f) => [path.basename(f, '.cjs'), path.join(__dirname, 'importers', f)]));

function importerArgs(args) {
  const rest = [...args];
  const names = Object.keys(IMPORTERS);
  let name = names.length === 1 ? names[0] : null;
  const at = rest.findIndex((a) => a === '--from' || a.startsWith('--from='));
  if (at >= 0) name = rest[at].includes('=') ? rest.splice(at, 1)[0].split('=')[1] : rest.splice(at, 2)[1];
  if (!name) fail(`choose an importer with --from <name> (available: ${names.join(', ') || 'none'})`);
  if (!IMPORTERS[name]) fail(`unknown importer '${name}' (available: ${names.join(', ') || 'none'})`);
  return [IMPORTERS[name], rest];
}

function cmdImport(args) {
  const [script, rest] = importerArgs(args);
  const result = spawnSync(process.execPath, ['--stack-size=65500', script, ...rest], { stdio: 'inherit', env: process.env });
  if (result.status !== 0) fail('import failed (see parity output above)');
}

// ---------------------------------------------------------------- harvest
function findSavedVariables() {
  const accounts = path.resolve(root, '..', '..', '..', 'WTF', 'Account');
  const found = [];
  if (fs.existsSync(accounts)) for (const account of fs.readdirSync(accounts)) {
    const file = path.join(accounts, account, 'SavedVariables', 'Monstrator.lua');
    if (fs.existsSync(file)) found.push(file);
  }
  return found;
}

const discoveryFile = path.join(sourceDir, 'Discoveries.lua');
const ledgerFile = path.join(sourceDir, 'SubmissionLedger.json');
const section = (title, list) => { if (list.length) { console.log(`\n${title} (${list.length}):`); list.slice(0, 50).forEach((l) => console.log('  ' + l)); } };

function readDiscoveries() {
  const discoveries = readSource(discoveryFile, {});
  discoveries.Npc = Object.fromEntries(entries(discoveries.Npc));
  return discoveries;
}

function writeDiscoveries(discoveries, origin) {
  fs.mkdirSync(sourceDir, { recursive: true });
  fs.writeFileSync(discoveryFile, `-- Forever discoveries from in-game Monstrator journals, merged by tools\\monstrator-db.cjs ${origin}.\r\n`
    + '-- Safe to edit by hand; harvest/review merge into it and overlay folds it into Data\\Native\\Overlay.lua.\r\n'
    + 'return ' + writeLuaTable(discoveries).replace(/\n/g, '\r\n') + '\r\n', 'utf8');
}

const usableNpc = (record) => record && record.kind === 'npc' && Number.isInteger(Number(record.npcID)) && Number(record.npcID) > 0
  && typeof record.name === 'string' && record.name !== '' && Number.isInteger(record.mapID) && record.mapID > 0
  && Number.isFinite(record.x) && Number.isFinite(record.y) && record.x >= 0 && record.x <= 100 && record.y >= 0 && record.y <= 100;

// How a record compares with the shipped database: null when consistent, otherwise the reason to look closer.
function compareWithDatabase(base, record) {
  const id = Number(record.npcID);
  const known = base.has(id) ? decodeRow('Npc', base.get(id)) : null;
  if (!known) return { kind: 'new', text: `${id} ${record.name} (map ${record.mapID}) is not in the database` };
  if (known.name && known.name !== record.name) return { kind: 'name', text: `${id} reported as "${record.name}", database has "${known.name}"` };
  if (!known.spawns || !known.spawns[record.mapID]) return { kind: 'map', text: `${id} ${record.name}: map ${record.mapID} not in database` };
  const gap = nearest(known.spawns[record.mapID], record.x, record.y);
  if (gap > DRIFT) return { kind: 'drift', text: `${id} ${record.name}: map ${record.mapID} ${fmt(record.x)},${fmt(record.y)} is ${fmt(gap)}% from nearest database spawn` };
  return null;
}

function mergeNpc(discoveries, record) {
  const id = Number(record.npcID);
  const entry = discoveries.Npc[id] = discoveries.Npc[id] || { name: record.name, spawns: {} };
  entry.spawns = normalizeSpawns(entry.spawns);
  entry.name = record.name;
  if (record.title) entry.title = record.title;
  if (record.level) {
    entry.minLevel = Math.min(entry.minLevel ?? record.level, record.level);
    entry.maxLevel = Math.max(entry.maxLevel ?? record.level, record.level);
  }
  let flags = entry.npcFlags || 0;
  for (const tag of Object.values(record.tags || {})) flags |= TAG_FLAGS[tag] || 0;
  flags |= EVENT_FLAGS[record.source] || 0;
  if (flags) entry.npcFlags = flags;
  entry.sightings = (entry.sightings || 0) + (record.sightings || 1);
  entry.lastSeen = Math.max(entry.lastSeen || 0, record.lastSeen || 0);
  entry.build = record.build || entry.build;
  return addPoint(entry.spawns, record.mapID, record.x, record.y);
}

// Runs Submission.lua (the same code the addon uses) so seals are computed identically.
function submissionLua(prelude, expr) {
  const module = fs.readFileSync(path.join(root, 'Submission.lua'), 'utf8');
  return evalLua(`${prelude}\nlocal __M = {}\n(function(...)\n${module}\nend)(nil, __M)`, 'Submission.lua', expr);
}

// Seal status of every journal entry and scan sighting in a SavedVariables file.
function savedVariableSeals(source) {
  return submissionLua(source, `(function()
    local settings = type(Monstrator_Settings) == "table" and Monstrator_Settings or {}
    local function status(record)
      if type(record) ~= "table" then return "invalid" end
      if record.seal == nil then return "unsealed" end
      return record.seal == __M.RecordSeal(record, settings.submitterID) and "sealed" or "tampered"
    end
    local out = { obs = {}, scans = {} }
    local obs = type(Monstrator_Observations) == "table" and Monstrator_Observations.entries or {}
    for key, record in pairs(obs) do out.obs[tostring(key)] = status(record) end
    for i, hit in ipairs(type(settings.scanLog) == "table" and settings.scanLog or {}) do
      local record = __M.ScanRecord(__M, hit)
      out.scans[i] = record and status(record) or "skip"
    end
    return out
  end)()`);
}

function cmdHarvest(args) {
  const includePending = args.includes('--include-pending');
  const files = args.filter((a) => !a.startsWith('--'));
  const inputs = files.length ? files.map((f) => path.resolve(f)) : findSavedVariables();
  if (!inputs.length) fail('no SavedVariables\\Monstrator.lua found; pass its path');
  const base = readNative(nativeDir, 'Npc');
  const discoveries = readDiscoveries();
  const report = { used: 0, skipped: 0, scans: 0, tampered: 0, newNPCs: new Set(), newMaps: [], drift: [], points: 0 };
  for (const file of inputs) {
    const source = fs.readFileSync(file, 'utf8');
    const seals = savedVariableSeals(source);
    const obs = evalLua(source, rel(file), 'Monstrator_Observations');
    const records = Object.entries((obs && obs.entries) || {}).map(([key, record]) => ({ ...record, seal: seals.obs[key] }));
    // NPC scan sightings with an exact vignette position are first-party spawn data too (usually rares).
    const settings = evalLua(source, rel(file), 'Monstrator_Settings');
    entries((settings && settings.scanLog) || {}).forEach(([index, hit]) => {
      if (!hit || !hit.exact) return;
      report.scans++;
      records.push({ kind: 'npc', npcID: hit.npcID, name: hit.name, mapID: hit.mapID, x: hit.x, y: hit.y,
        level: hit.level, lastSeen: hit.time, verification: 'user-confirmed', source: 'scan:vignette',
        seal: seals.scans[index - 1] });
    });
    for (const record of records) {
      if (record.seal === 'tampered') { report.tampered++; continue; }
      const usable = usableNpc(record)
        && (record.verification === 'user-confirmed' || (includePending && record.verification === 'pending'));
      if (!usable) { report.skipped++; continue; }
      report.used++;
      if (mergeNpc(discoveries, record)) report.points++;
      const issue = compareWithDatabase(base, record);
      if (!issue) continue;
      if (issue.kind === 'new') report.newNPCs.add(issue.text);
      else if (issue.kind === 'drift') report.drift.push(issue.text);
      else report.newMaps.push(issue.text);
    }
  }
  writeDiscoveries(discoveries, 'harvest');
  console.log(`Harvested ${report.used} observations from ${inputs.length} file(s), including ${report.scans} exact NPC scan sightings (${report.skipped} skipped: not NPC, `
    + `${includePending ? 'invalid' : 'pending - use --include-pending'}); ${report.points} new points.`);
  if (report.tampered) console.log(`Rejected ${report.tampered} record(s) whose seal no longer matches (edited outside the game).`);
  console.log(`Discoveries now: ${Object.keys(discoveries.Npc).length} NPCs in ${rel(discoveryFile)}`);
  section('NPCs not in the database (Forever-only)', [...report.newNPCs]);
  section('Known NPCs seen on a new map or under another name', report.newMaps);
  section(`Possible coordinate drift (> ${DRIFT}% from every known spawn)`, report.drift);
  console.log('\nNext: node tools\\monstrator-db.cjs overlay');
}

// ---------------------------------------------------------------- review (player submissions)
const SUBMISSION_HEADER = 'MONSTRATOR SUBMISSION v1';
const AGREE = 1.0; // map % - reports this close from different players corroborate each other

function submissionFiles(args) {
  const files = [];
  for (const arg of args) {
    const full = path.resolve(arg);
    if (!fs.existsSync(full)) fail(`not found: ${arg}`);
    if (fs.statSync(full).isDirectory()) {
      for (const name of fs.readdirSync(full).sort()) if (/\.(txt|md|lua)$/i.test(name)) files.push(path.join(full, name));
    } else files.push(full);
  }
  return files;
}

// A file may hold several pasted submissions (for example an exported issue thread).
function splitSubmissions(text) {
  const parts = text.replace(/\r\n?/g, '\n').split(new RegExp(`(?=^\\s*${SUBMISSION_HEADER}\\s*$)`, 'm'));
  return parts.filter((part) => part.includes(SUBMISSION_HEADER));
}

function parseSubmission(text, label) {
  const parsed = submissionLua('', `(function()
    local result, reason = __M.ParseSubmission(${luaLiteral(text)})
    return { result = result, reason = reason }
  end)()`);
  if (!parsed.result) return { label, error: parsed.reason || 'unreadable' };
  const result = parsed.result;
  result.label = label;
  result.records = Object.values(result.records || {}).map((r) => ({ ...r, tags: Object.values(r.tags || {}) }));
  return result;
}

function readLedger() {
  if (!fs.existsSync(ledgerFile)) return { submissions: {}, reports: [] };
  const ledger = JSON.parse(fs.readFileSync(ledgerFile, 'utf8'));
  ledger.submissions = ledger.submissions || {};
  ledger.reports = ledger.reports || [];
  return ledger;
}

function cmdReview(args) {
  const apply = args.includes('--apply');
  const acceptHeld = args.includes('--accept-held');
  const minAt = args.indexOf('--min-reporters');
  const minReporters = minAt >= 0 ? Number(args[minAt + 1]) : 2;
  if (!Number.isInteger(minReporters) || minReporters < 1) fail('--min-reporters needs a whole number >= 1');
  const paths = args.filter((a, i) => !a.startsWith('--') && !(minAt >= 0 && i === minAt + 1));
  if (!paths.length) fail('usage: review <file|folder>... [--apply] [--min-reporters N] [--accept-held]');
  const base = readNative(nativeDir, 'Npc');
  const ledger = readLedger();
  const rejected = [], held = [], accepted = [], fresh = [];
  for (const file of submissionFiles(paths)) {
    const blocks = splitSubmissions(fs.readFileSync(file, 'utf8'));
    if (!blocks.length) { rejected.push(`${rel(file)}: no submission found`); continue; }
    blocks.forEach((block, n) => {
      const where = file.startsWith(root + path.sep) ? rel(file) : file;
      const label = blocks.length > 1 ? `${where}#${n + 1}` : where;
      const sub = parseSubmission(block, label);
      if (sub.error) { rejected.push(`${label}: whole submission rejected - ${sub.error}`); return; }
      if (ledger.submissions[sub.seal] || fresh.some((s) => s.seal === sub.seal)) {
        console.log(`${label}: already reviewed, skipped`); return;
      }
      fresh.push(sub);
    });
  }
  // Corroboration counts distinct reporters, including reports kept from earlier reviews.
  const reports = [...ledger.reports];
  for (const sub of fresh) for (const r of sub.records) if (r.status !== 'tampered' && usableNpc(r)) {
    reports.push({ submitter: sub.header.submitter, npcID: Number(r.npcID), name: r.name, mapID: r.mapID, x: r.x, y: r.y });
  }
  const reporters = (r) => new Set(reports.filter((o) => o.npcID === Number(r.npcID) && o.name === r.name && o.mapID === r.mapID
    && Math.hypot(o.x - r.x, o.y - r.y) <= AGREE).map((o) => o.submitter)).size;
  for (const sub of fresh) {
    sub.records.forEach((r, i) => {
      const tag = `${sub.label} record ${i + 1}: ${r.npcID ? r.npcID + ' ' : ''}${r.name || '?'}`;
      if (r.status === 'tampered') { rejected.push(`${tag} - seal broken (edited after capture)`); return; }
      if (r.kind === 'location') { held.push({ r, sub, why: `${tag} - location: add by hand to Data\\Source\\Corrections.lua if it checks out` }); return; }
      if (!usableNpc(r)) { rejected.push(`${tag} - invalid NPC/map/coordinates`); return; }
      const count = reporters(r);
      const reasons = [];
      if (r.status === 'unsealed') reasons.push('captured before seals existed');
      if (r.verification !== 'user-confirmed') reasons.push('unconfirmed encounter position');
      if (r.edited) reasons.push('position moved by hand during review');
      const issue = compareWithDatabase(base, r);
      if (issue) reasons.push(issue.text);
      if (!reasons.length || count >= minReporters) {
        accepted.push({ r, sub, why: `${tag} - ${reasons.length ? `corroborated by ${count} reporters (${reasons.join('; ')})` : 'consistent with database'}` });
      } else held.push({ r, sub, why: `${tag} - ${reasons.join('; ')} (${count}/${minReporters} reporters)` });
    });
  }
  console.log(`Reviewed ${fresh.length} new submission(s): ${accepted.length} accepted, ${held.length} held, ${rejected.length} rejected.`);
  section('Rejected', rejected);
  section('Held for maintainer review (more reports or --accept-held)', held.map((h) => h.why));
  section('Accepted', accepted.map((a) => a.why));
  if (!apply) { console.log('\nDry run. Re-run with --apply to merge accepted records into Data\\Source\\Discoveries.lua.'); return rejected.length ? 2 : 0; }
  const discoveries = readDiscoveries();
  let points = 0;
  for (const item of [...accepted, ...(acceptHeld ? held.filter((h) => h.r.kind === 'npc') : [])]) {
    if (mergeNpc(discoveries, item.r)) points++;
  }
  writeDiscoveries(discoveries, 'review');
  const today = new Date().toISOString().slice(0, 10);
  for (const sub of fresh) {
    ledger.submissions[sub.seal] = { submitter: sub.header.submitter, created: Number(sub.header.created) || null,
      build: sub.header.build || null, records: sub.records.length, reviewed: today };
  }
  ledger.reports = reports;
  fs.writeFileSync(ledgerFile, JSON.stringify(ledger, null, 2).replace(/\n/g, '\r\n') + '\r\n', 'utf8');
  console.log(`\nMerged ${points} new point(s) into ${rel(discoveryFile)}; ledger ${rel(ledgerFile)} updated.`);
  console.log('Next: node tools\\monstrator-db.cjs overlay');
  return 0;
}

// ---------------------------------------------------------------- overlay
function applyCorrection(kind, current, fix) {
  const row = { ...(current || {}) };
  for (const [key, value] of Object.entries(fix)) {
    if (key === 'spawns') row.spawns = normalizeSpawns(value);
    else if (key === 'addSpawns') {
      row.spawns = row.spawns || {};
      for (const [map, points] of Object.entries(normalizeSpawns(value))) for (const [x, y] of points) addPoint(row.spawns, Number(map), x, y);
    } else if (LISTS.has(key)) row[key] = Array.isArray(value) ? value : Object.values(value);
    else if (!LAYOUT[kind].includes(key)) fail(`Corrections.${kind}: unknown field '${key}'`);
    else row[key] = value === false ? undefined : value;
  }
  return row;
}

// Builds Overlay.lua text. With standalone=true the imported base is ignored entirely, so every row comes only
// from Monstrator's own sources (no merged third-party fields or spawns); deletions and base-only fixes are dropped.
function buildOverlay(standalone = false) {
  const discoveries = readSource(path.join(sourceDir, 'Discoveries.lua'), {});
  const corrections = readSource(path.join(sourceDir, 'Corrections.lua'), {});
  const lines = ['-- Monstrator native overlay. GENERATED by tools\\monstrator-db.cjs overlay from Data\\Source\\Discoveries.lua',
    '-- and Data\\Source\\Corrections.lua. Each row replaces (or with false, deletes) the base row of the same ID.'
    + (standalone ? '\n-- Standalone build: rows contain only Monstrator\'s own data.' : ''),
    'local _, M = ...'];
  const summary = [];
  let dropped = 0;
  for (const kind of KINDS) {
    const base = standalone ? new Map() : readNative(nativeDir, kind);
    const rows = new Map(); // id -> { row|false, origin }
    for (const [id, found] of entries(discoveries[kind])) {
      if (kind !== 'Npc') continue;
      const known = base.has(id) ? decodeRow(kind, base.get(id)) : {};
      const row = { ...known, spawns: normalizeSpawns(known.spawns) };
      row.name = found.name || row.name;
      if (found.title) row.subName = found.title;
      row.npcFlags = (row.npcFlags || 0) | (found.npcFlags || 0);
      if (found.minLevel) row.minLevel = Math.min(row.minLevel ?? found.minLevel, found.minLevel);
      if (found.maxLevel) row.maxLevel = Math.max(row.maxLevel ?? found.maxLevel, found.maxLevel);
      for (const [map, points] of Object.entries(normalizeSpawns(found.spawns))) {
        for (const [x, y] of points) if (nearest(row.spawns[map], x, y) > DRIFT || !row.spawns[map]) addPoint(row.spawns, Number(map), x, y);
      }
      const text = encodeRow(kind, row);
      if (text !== base.get(id)) rows.set(id, { text, origin: 'discovery' });
    }
    for (const [id, fix] of entries(corrections[kind])) {
      if (!Number.isInteger(id) || id <= 0) fail(`Corrections.${kind}: bad ID '${id}'`);
      if (fix === false) { if (standalone) dropped++; else rows.set(id, { text: false, origin: 'correction' }); continue; }
      const current = rows.get(id)?.text || base.get(id);
      const row = applyCorrection(kind, current ? decodeRow(kind, current) : null, fix);
      if (!row.name && standalone) { dropped++; continue; }
      if (!row.name) fail(`Corrections.${kind}[${id}]: new entities need a name`);
      rows.set(id, { text: encodeRow(kind, row), origin: 'correction' });
    }
    if (!rows.size) continue;
    lines.push(`do local D, O = M.NativeOverlay(${luaQuote(kind)})`);
    for (const id of [...rows.keys()].sort((a, b) => a - b)) {
      const { text, origin } = rows.get(id);
      lines.push(`D[${id}]=${text === false ? 'false' : luaQuote(text)} O[${id}]=${luaQuote(origin)}`);
    }
    lines.push('end');
    const counts = {};
    for (const { origin, text } of rows.values()) { const k = text === false ? 'deleted' : origin; counts[k] = (counts[k] || 0) + 1; }
    summary.push(`${kind}: ${Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(', ')}`);
  }
  return { text: lines.join('\n').replace(/\n/g, '\r\n') + '\r\n', summary, dropped };
}

function cmdOverlay() {
  const { text, summary } = buildOverlay(false);
  const file = path.join(nativeDir, 'Overlay.lua');
  fs.writeFileSync(file, text, 'utf8');
  console.log(`Wrote ${rel(file)}: ${summary.length ? summary.join('; ') : 'empty (no discoveries or corrections)'}`);
}

// ---------------------------------------------------------------- verify
function loadRuntime(dir) {
  const files = KINDS.map((k) => path.join(dir, `${k}s.lua`)).concat([path.join(dir, 'Overlay.lua')]).filter(fs.existsSync);
  const chunks = files.map((f) => `assert(load(${luaLiteral(fs.readFileSync(f, 'utf8'))}, ${luaQuote(path.basename(f))}))("Monstrator", M)`);
  return `M = {}\nassert(load(${luaLiteral(fs.readFileSync(path.join(root, 'NativeDB.lua'), 'utf8'))}, "NativeDB.lua"))("Monstrator", M)\n${chunks.join('\n')}`;
}

function cmdVerify(args) {
  const errors = [];
  const m = manifest();
  const imported = KINDS.some((k) => readNative(nativeDir, k).size > 0);
  if (!m && imported) errors.push('Data\\Native\\manifest.json missing (run import)');
  else if (!m) console.log('Standalone database: no imported base data; checking the overlay only.');
  else for (const [name, info] of Object.entries(m.files)) {
    const file = path.join(nativeDir, name);
    if (!fs.existsSync(file)) { errors.push(`${name} missing`); continue; }
    const hash = sha256(fs.readFileSync(file));
    if (hash !== info.sha256) errors.push(`${name}: sha256 differs from manifest (edited by hand? re-run import)`);
  }
  // The overlay codec must reproduce every base row exactly, or overlay rows would silently alter data.
  for (const kind of KINDS) {
    let bad = 0;
    for (const [id, raw] of readNative(nativeDir, kind)) {
      if (encodeRow(kind, decodeRow(kind, raw)) !== raw) { if (bad++ < 5) errors.push(`${kind} ${id}: codec round-trip changes the row`); }
    }
    if (bad > 5) errors.push(`${kind}: ${bad} rows fail the codec round-trip`);
  }
  // Decode every row through the real runtime (NativeDB.lua + overlay) and check schema + references.
  const check = String.raw`
local db = M:NativeProvider() or { Npc = { Has = function() return false end, GetAllIds = function() return {} end } }
local errors, warnings, stats = {}, {}, { maps = {} }
local function err(msg) if #errors < 40 then errors[#errors + 1] = msg end errors.n = (errors.n or 0) + 1 end
local function warn(kind, msg) warnings[kind] = (warnings[kind] or 0) + 1 end
local numeric = { Npc = { "npcFlags", "minLevel", "maxLevel" }, Item = { "requiredLevel", "itemLevel", "class", "subClass", "startQuest" }, Quest = { "questLevel", "requiredLevel" } }
for _, kind in ipairs({ "Npc", "Object", "Item", "Quest" }) do
  local t = db[kind]
  stats[kind] = 0
  for _, id in ipairs(t and t.GetAllIds() or {}) do
    stats[kind] = stats[kind] + 1
    local name = t.name(id)
    if type(name) ~= "string" or name == "" then err(kind .. " " .. id .. ": empty name") end
    for _, f in ipairs(numeric[kind] or {}) do
      local ok, v = pcall(t[f], id)
      if not ok or (v ~= nil and (type(v) ~= "number" or v ~= v)) then err(kind .. " " .. id .. "." .. f .. ": not a number") end
    end
    if t.spawns then
      for map, points in pairs(t.spawns(id) or {}) do
        if type(map) ~= "number" or map <= 0 or map % 1 ~= 0 then err(kind .. " " .. id .. ": bad map " .. tostring(map)) end
        stats.maps[map] = true
        for _, p in ipairs(points) do
          if not (p[1] and p[2] and p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 100) then
            err(kind .. " " .. id .. ": coordinate out of range on map " .. map)
          end
        end
      end
    end
    if kind == "Npc" then
      local lo, hi = t.minLevel(id), t.maxLevel(id)
      if lo and hi and lo > hi then warn("npc level range inverted") end
    elseif kind == "Item" then
      for _, f in ipairs({ "vendors", "npcDrops" }) do for _, ref in ipairs(t[f](id) or {}) do if not db.Npc.Has(ref) then warn("item " .. f .. " -> unknown NPC") end end end
      for _, ref in ipairs(t.objectDrops(id) or {}) do if not (db.Object and db.Object.Has(ref)) then warn("item objectDrops -> unknown object") end end
      for _, ref in ipairs(t.questRewards(id) or {}) do if not (db.Quest and db.Quest.Has(ref)) then warn("item questRewards -> unknown quest") end end
      local q = t.startQuest(id)
      if q and q > 0 and not (db.Quest and db.Quest.Has(q)) then warn("item startQuest -> unknown quest") end
    elseif kind == "Quest" then
      for _, f in ipairs({ "starterNpcs", "finisherNpcs" }) do for _, ref in ipairs(t[f](id) or {}) do if not db.Npc.Has(ref) then warn("quest " .. f .. " -> unknown NPC") end end end
      for _, f in ipairs({ "starterObjects", "finisherObjects" }) do for _, ref in ipairs(t[f](id) or {}) do if not (db.Object and db.Object.Has(ref)) then warn("quest " .. f .. " -> unknown object") end end end
    end
  end
end
local maps = 0
for _ in pairs(stats.maps) do maps = maps + 1 end
stats.maps = maps
local _, _, overlays = M:NativeSummary()
return { errors = errors, errorCount = errors.n or 0, warnings = warnings, stats = stats, overlays = overlays }
`;
  const result = evalLua(`${loadRuntime(nativeDir)}\n__verify = (function()\n${check}\nend)()`, 'verify', '__verify');
  for (const e of Object.values(result.errors || {})) errors.push(e);
  const s = result.stats;
  console.log(`Decoded: ${s.Npc} NPCs, ${s.Object} objects, ${s.Item} items, ${s.Quest} quests on ${s.maps} maps.`);
  const overlays = Object.entries(result.overlays || {});
  console.log(`Overlay: ${overlays.length ? overlays.map(([k, v]) => `${v} ${k}`).join(', ') : 'none'}`);
  const warnings = Object.entries(result.warnings || {}).sort();
  if (warnings.length) {
    console.log('Reference warnings (inherited source data; not fatal):');
    for (const [k, v] of warnings) console.log(`  ${v} x ${k}`);
  }
  if (args.includes('--determinism')) {
    const generator = m && path.resolve(root, m.generator || '');
    if (!m || !fs.existsSync(generator)) fail('--determinism needs an imported database with a known generator');
    const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-determinism-'));
    console.log('Re-importing into ' + temp + ' ...');
    try {
      // Arguments after --determinism (e.g. the source folder) are forwarded to the importer.
      const importArgs = args.slice(args.indexOf('--determinism') + 1);
      const run = spawnSync(process.execPath, ['--stack-size=65500', generator, ...importArgs],
        { env: { ...process.env, MONSTRATOR_NATIVE_OUT: temp }, encoding: 'utf8' });
      if (run.status !== 0) errors.push('determinism re-import failed: ' + (run.stderr || run.stdout).slice(-500));
      else for (const name of ['manifest.json', ...KINDS.map((k) => `${k}s.lua`)]) {
        const a = path.join(nativeDir, name), b = path.join(temp, name);
        if (!fs.existsSync(b) || sha256(fs.readFileSync(a)) !== sha256(fs.readFileSync(b))) errors.push(`determinism: ${name} differs on re-import`);
      }
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
    if (!errors.some((e) => e.startsWith('determinism'))) console.log('Determinism: re-import is byte-identical.');
  }
  if (result.errorCount > errors.length) errors.push(`... ${result.errorCount} schema errors in total`);
  if (errors.length) { errors.forEach((e) => console.error('  ' + e)); fail(`verify found ${errors.length} problem(s)`); }
  console.log('Verify: OK (manifest hashes, schema, coordinates' + (args.includes('--determinism') ? ', determinism' : '') + ').');
}

// ---------------------------------------------------------------- diff / stats
function cmdDiff(args) {
  if (!args[0]) fail('usage: diff <other Data\\Native folder>');
  const other = path.resolve(args[0]);
  for (const kind of KINDS) {
    const a = readNative(other, kind), b = readNative(nativeDir, kind);
    const added = [...b.keys()].filter((id) => !a.has(id));
    const removed = [...a.keys()].filter((id) => !b.has(id));
    const changed = [...b.keys()].filter((id) => a.has(id) && a.get(id) !== b.get(id));
    console.log(`${kind}: +${added.length} -${removed.length} ~${changed.length}`);
    const sample = (label, ids) => ids.length && console.log(`  ${label}: ${ids.slice(0, 15).join(', ')}${ids.length > 15 ? ' ...' : ''}`);
    sample('added', added); sample('removed', removed); sample('changed', changed);
  }
}

function cmdStats() {
  const m = manifest();
  if (m) console.log(`Imported base: ${m.source.name} ${m.source.version} (${m.source.flavor}, ${String(m.source.commit).slice(0, 10)})`);
  else console.log('Standalone database: no imported base data.');
  const flagNames = { 4: 'vendors', 8: 'flight masters', 16: 'trainers', 128: 'innkeepers', 256: 'bankers', 2: 'quest givers', 4096: 'auctioneers', 8192: 'stable masters', 16384: 'repair' };
  for (const kind of KINDS) {
    const rows = readNative(nativeDir, kind);
    let points = 0;
    const maps = new Set(), flags = {}, classes = {};
    for (const raw of rows.values()) {
      const row = decodeRow(kind, raw);
      for (const [map, list] of Object.entries(row.spawns || {})) { maps.add(map); points += list.length; }
      if (kind === 'Npc') for (const bit of Object.keys(flagNames)) if ((row.npcFlags || 0) & Number(bit)) flags[flagNames[bit]] = (flags[flagNames[bit]] || 0) + 1;
      if (kind === 'Object' && row.class) classes[row.class] = (classes[row.class] || 0) + 1;
    }
    console.log(`${kind}s: ${rows.size}${points ? `, ${points} spawn points on ${maps.size} maps` : ''}`);
    if (kind === 'Npc') console.log('  ' + Object.entries(flags).map(([k, v]) => `${v} ${k}`).join(', '));
    if (kind === 'Object') console.log('  directory classes: ' + Object.entries(classes).sort().map(([k, v]) => `${k} ${v}`).join(', '));
  }
  const overlay = path.join(nativeDir, 'Overlay.lua');
  const text = fs.existsSync(overlay) ? fs.readFileSync(overlay, 'utf8') : '';
  const count = (o) => (text.match(new RegExp(`O\\[\\d+\\]="${o}"`, 'g')) || []).length;
  console.log(`Overlay: ${count('discovery')} discoveries, ${count('correction')} corrections`);
}

// ---------------------------------------------------------------- package
const CRC_TABLE = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
function crc32(buf) { let c = 0xffffffff; for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }

// Release notes for the data a package carries, generated from manifest.json so attribution always matches
// exactly what ships (replaces a hand-maintained third-party notice).
function creditsText(m, standalone) {
  const lines = ['# Monstrator data credits', '',
    'Monstrator code, UI, tools, overlay (`Data/Native/Overlay.lua`, built from hand-reviewed corrections and',
    'confirmed in-game discoveries) and locales are original Monstrator work by Metalbullz.',
    '`ClientData.lua` / `ExtractedObjectData.lua` are generated from the game client with DBC2CSV.', ''];
  if (standalone || !m) {
    lines.push('This is a **standalone** build: it contains no imported third-party data. The directory fills from',
      'your own in-game collection (Settings > Collect locally) and from Monstrator\'s overlay.', '',
      'To add a larger base database from an addon you have installed yourself, run',
      '`node tools/monstrator-db.cjs import --from <importer>` from a source checkout.');
  } else {
    const s = m.source || {};
    lines.push('## Imported base data', '',
      `\`Data/Native/Npcs.lua\`, \`Objects.lua\`, \`Items.lua\` and \`Quests.lua\` were converted by \`${m.generator}\` from`,
      `**${s.name}** ${s.version} (${s.flavor}, commit \`${s.commit}\`)${s.homepage ? ` - ${s.homepage}` : ''}.`, '',
      `- Credits: ${s.credits || `${s.name} contributors`}`,
      `- License: ${s.license || 'not declared by the source; credited, not relicensed.'}`,
      '- Per-file entry counts and SHA-256 hashes are recorded in `Data/Native/manifest.json`.', '',
      'If you redistribute this build publicly, confirm redistribution terms with the source project first, or',
      'publish the standalone build (`node tools/monstrator-db.cjs package --standalone`) instead.');
  }
  return lines.join('\r\n') + '\r\n';
}

function cmdPackage(args = []) {
  const standalone = args.includes('--standalone');
  const toc = fs.readFileSync(path.join(root, 'Monstrator.toc'), 'utf8');
  const version = (toc.match(/^## Version:\s*(.+)$/m) || [])[1]?.trim() || '0.0.0';
  const excluded = new Set(['tools', 'tests', 'dist', '.git', 'node_modules', path.join('Data', 'Source')]);
  const files = [];
  (function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name), r = path.relative(root, full);
      if (excluded.has(r) || entry.name.startsWith('.')) continue;
      if (entry.isDirectory()) walk(full); else files.push(r);
    }
  })(root);
  // Every file the TOC loads must ship.
  for (const line of toc.split(/\r?\n/)) if (/\.lua$/i.test(line.trim()) && !line.trim().startsWith('#') && !files.includes(line.trim())) fail(`TOC file missing from package: ${line.trim()}`);
  const m = manifest();
  const imported = new Set(KINDS.map((k) => path.join('Data', 'Native', `${k}s.lua`)));
  const contents = new Map();
  for (const file of files) {
    if (standalone && file === path.join('Data', 'Native', 'manifest.json')) continue;
    if (standalone && imported.has(file)) {
      const kind = path.basename(file, 's.lua');
      contents.set(file, Buffer.from(`-- Monstrator native ${kind} data: standalone build, no imported base data.\r\n`
        + '-- Monstrator\'s own rows live in Overlay.lua; see CREDITS.md.\r\nlocal _, M = ...\r\n', 'utf8'));
    } else contents.set(file, fs.readFileSync(path.join(root, file)));
  }
  if (standalone) {
    const own = buildOverlay(true);
    contents.set(path.join('Data', 'Native', 'Overlay.lua'), Buffer.from(own.text, 'utf8'));
    console.log(`Standalone overlay: ${own.summary.join('; ') || 'empty'}${own.dropped ? ` (${own.dropped} base-only corrections dropped)` : ''}`);
  }
  contents.set('CREDITS.md', Buffer.from(creditsText(m, standalone), 'utf8'));
  const names = [...contents.keys()].sort();
  const locals = [], central = [];
  let offset = 0;
  for (const file of names) {
    const data = contents.get(file);
    const packed = zlib.deflateRawSync(data, { level: 9 });
    const name = Buffer.from('Monstrator/' + file.split(path.sep).join('/'), 'utf8');
    const crc = crc32(data);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0); header.writeUInt16LE(20, 4); header.writeUInt16LE(0x0800, 6);
    header.writeUInt16LE(8, 8); header.writeUInt32LE(0, 10); header.writeUInt32LE(crc, 14);
    header.writeUInt32LE(packed.length, 18); header.writeUInt32LE(data.length, 22); header.writeUInt16LE(name.length, 26);
    const dir = Buffer.alloc(46);
    dir.writeUInt32LE(0x02014b50, 0); dir.writeUInt16LE(20, 4); dir.writeUInt16LE(20, 6); dir.writeUInt16LE(0x0800, 8);
    dir.writeUInt16LE(8, 10); dir.writeUInt32LE(0, 12); dir.writeUInt32LE(crc, 16); dir.writeUInt32LE(packed.length, 20);
    dir.writeUInt32LE(data.length, 24); dir.writeUInt16LE(name.length, 28); dir.writeUInt32LE(offset, 42);
    locals.push(header, name, packed);
    central.push(dir, name);
    offset += 30 + name.length + packed.length;
  }
  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(names.length, 8); end.writeUInt16LE(names.length, 10);
  end.writeUInt32LE(centralBuf.length, 12); end.writeUInt32LE(offset, 16);
  const out = path.join(root, 'dist', `Monstrator-${version}${standalone ? '-standalone' : ''}.zip`);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, Buffer.concat([...locals, centralBuf, end]));
  console.log(`Packaged ${names.length} files into ${rel(out)} (${(fs.statSync(out).size / 1048576).toFixed(2)} MB; `
    + `${standalone || !m ? 'standalone, no imported data' : `includes imported ${m.source.name} data, credited in CREDITS.md`}).`);
}

// ---------------------------------------------------------------- main
module.exports = { decodeRow, encodeRow, decodeSpawns, encodeSpawns, normalizeSpawns, readNative, LAYOUT };
if (require.main !== module) return;
const [command, ...rest] = process.argv.slice(2);
const commands = {
  import: cmdImport, harvest: cmdHarvest, overlay: cmdOverlay, verify: cmdVerify, diff: cmdDiff, stats: cmdStats,
  package: cmdPackage, review: (args) => { process.exitCode = cmdReview(args) || 0; },
  build: (args) => { cmdImport(args); cmdOverlay(); cmdVerify([]); },
};
const wantsHelp = (a) => a === '-h' || a === '--help' || a === 'help';
if (!commands[command] || rest.some(wantsHelp)) {
  console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 21).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  process.exit(!command || wantsHelp(command) || commands[command] ? 0 : 1);
}
commands[command](rest);
