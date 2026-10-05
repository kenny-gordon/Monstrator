const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const os = require('node:os');
const { spawnSync } = require('node:child_process');
const runtimePath = process.env.MONSTRATOR_LUA_RUNTIME;
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(runtimePath || 'fengari');
const root = path.resolve(__dirname, '..');
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
function execute(source, name, module = false) {
  const status = lauxlib.luaL_loadbuffer(state, to_luastring(source), null, to_luastring(name));
  if (status !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  if (module) {
    lua.lua_pushstring(state, to_luastring('Monstrator'));
    lua.lua_getglobal(state, to_luastring('M'));
  }
  if (lua.lua_pcall(state, module ? 2 : 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
}
execute(fs.readFileSync(path.join(__dirname, 'mock.lua'), 'utf8'), 'mock.lua');
const toc = fs.readFileSync(path.join(root, 'Monstrator.toc'), 'utf8');
// Generated native data is large; tests install small native fixtures instead, tests/native-db.lua covers the
// decoder, and tools\monstrator-db.cjs verify plus the importer's parity check cover the real files.
for (const file of toc.split(/\r?\n/).filter(line => line.endsWith('.lua') && !/^Data[\\/]Native[\\/]/.test(line))) {
  execute(fs.readFileSync(path.join(root, file), 'utf8'), file, true);
}
execute(fs.readFileSync(path.join(__dirname, 'behavior.lua'), 'utf8'), 'behavior.lua');
execute(fs.readFileSync(path.join(__dirname, 'client-data.lua'), 'utf8'), 'client-data.lua');
execute(fs.readFileSync(path.join(__dirname, 'extracted-objects.lua'), 'utf8'), 'extracted-objects.lua');
execute(fs.readFileSync(path.join(__dirname, 'npc-directory.lua'), 'utf8'), 'npc-directory.lua');
execute(fs.readFileSync(path.join(__dirname, 'native-index.lua'), 'utf8'), 'native-index.lua');
execute(fs.readFileSync(path.join(__dirname, 'places.lua'), 'utf8'), 'places.lua');
execute(fs.readFileSync(path.join(__dirname, 'items.lua'), 'utf8'), 'items.lua');
execute(fs.readFileSync(path.join(__dirname, 'native-db.lua'), 'utf8'), 'native-db.lua');
execute(fs.readFileSync(path.join(__dirname, 'ui-refactor.lua'), 'utf8'), 'ui-refactor.lua');
execute(fs.readFileSync(path.join(__dirname, 'scanner.lua'), 'utf8'), 'scanner.lua');
execute(fs.readFileSync(path.join(__dirname, 'submission.lua'), 'utf8'), 'submission.lua');

// Locales: every file loads only for its own client locale, translates keys the addon actually uses, and keeps
// the same format specifiers as English so string.format can never fail in another language.
{
  const codeText = fs.readdirSync(root).filter((f) => f.endsWith('.lua')).map((f) => fs.readFileSync(path.join(root, f), 'utf8')).join('\n');
  const enUS = fs.readFileSync(path.join(root, 'Locales', 'enUS.lua'), 'utf8');
  const keyPattern = /^L\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)"/gm;
  const english = new Map([...enUS.matchAll(keyPattern)].map((m) => [m[1], m[2]]));
  const specifiers = (text) => (text.match(/%[-\d.]*[sdf]/g) || []).join(' ');
  const locales = toc.split(/\r?\n/).filter((line) => /^Locales[\\/]\w+\.lua$/.test(line)).map((line) => line.slice(8, -4));
  assert.deepEqual(locales.slice().sort(), ['deDE', 'enUS', 'esES', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW']);
  let reference;
  for (const locale of locales.filter((name) => name !== 'enUS')) {
    const source = fs.readFileSync(path.join(root, 'Locales', locale + '.lua'), 'utf8');
    assert.ok(!source.startsWith('\uFEFF'), locale + ' must not start with a BOM');
    const keys = [...source.matchAll(keyPattern)];
    reference = reference || keys.map((m) => m[1]).join('|');
    assert.equal(keys.map((m) => m[1]).join('|'), reference, locale + ' must translate the same keys as the other locales');
    const translated = new Set(keys.map((m) => m[1]));
    const untranslated = [...english.keys()].filter((key) => !translated.has(key));
    assert.deepEqual(untranslated, [], locale + ' must translate every enUS string');
    for (const [, key, value] of keys) {
      const unescaped = key.replace(/\\\\/g, '\\');
      assert.ok(english.has(key) || codeText.includes('"' + key + '"'), locale + ': unused key ' + unescaped);
      assert.equal(specifiers(value), specifiers(english.get(key) || key), locale + ': format specifiers differ for ' + key);
    }
    for (const [client, expected] of [['enUS', 0], [locale, keys.length]].concat(locale === 'esES' ? [['esMX', keys.length]] : [])) {
      lua.lua_pushstring(state, to_luastring(source));
      lua.lua_setglobal(state, to_luastring('LOCALE_SOURCE'));
      lua.lua_pushstring(state, to_luastring(client));
      lua.lua_setglobal(state, to_luastring('LOCALE_CLIENT'));
      execute(`local chunk = assert(load(LOCALE_SOURCE, "=locale"))
        local saved = GetLocale
        GetLocale = function() return LOCALE_CLIENT end
        local addon = { L = {} }
        local ok, err = pcall(chunk, "Monstrator", addon)
        GetLocale = saved
        assert(ok, err)
        local n = 0
        for _, value in pairs(addon.L) do assert(type(value) == "string" and value ~= ""); n = n + 1 end
        LOCALE_COUNT = n`, 'locale-' + locale);
      lua.lua_getglobal(state, to_luastring('LOCALE_COUNT'));
      assert.equal(lua.lua_tointeger(state, -1), expected, locale + ' loaded ' + client + ' strings');
      lua.lua_pop(state, 1);
    }
  }
}

// The native row codec must round-trip every layout exactly.
{
  const db = require('../tools/monstrator-db.cjs');
  const rows = {
    Npc: ['Innkeeper Kauth\tInnkeeper\t131\t30\t30\tH\t1:40,50 41,51', 'Moorat\tArmorer\t16388\t\t\tAH\t1:60.125,60;2:10,10',
      'Waypoint\t\t0\t1\t1\tAH\t'],
    Object: ['Mailbox\t1:46.1,40.2;2:0.005,99\tmailbox', 'Linen Crate\t1:50,50\t'],
    Item: ['Haunch of Meat\t5\t15\t0\t0\t\t20,21\t22\t\t900\t'],
    Quest: ['Meat Run\t6\t4\t11\t\t10,11\t51'],
  };
  for (const [kind, list] of Object.entries(rows)) {
    for (const raw of list) assert.equal(db.encodeRow(kind, db.decodeRow(kind, raw)), raw, kind + ' row must round-trip');
  }
  assert.equal(typeof db.decodeRow('Object', rows.Object[0]).class, 'string', 'object classes are names, not numbers');
  assert.deepEqual(db.normalizeSpawns({ 1: [[40, 50], [null, 3], { x: 1 }], 2: [{ 1: 10.004, 2: 20 }] }),
    { 1: [[40, 50]], 2: [[10, 20]] }, 'non-finite or missing coordinates must be dropped, not become (0,0)');
}
const { generate } = require('../tools/import-data.cjs');
const { generate: generateCatalog } = require('../tools/client-map-csv.cjs');
const { generate: generateObjects } = require('../tools/object-csv.cjs');
const objectFixture = 'ID,Name_lang,OwnerID,Pos[0],Pos[1],Pos[2],TypeID,PhaseID,PhaseGroupID,PhaseUseFlags\n' +
  '1,Synthetic sign,0,75,150,0,5,0,0,0\n2,Phased,0,75,150,0,5,1,0,0\n' +
  '3,Unknown type,0,75,150,0,19,0,0,0\n4,Off map,0,10000,150,0,5,0,0,0\n';
const objectMaps = 'ID,System,Type\n1,0,3\n2,0,3\n';
const objectAssignments = 'ID,UiMapID,MapID,Region[0],Region[1],Region[2],Region[3],Region[4],Region[5],' +
  'UiMin[0],UiMin[1],UiMax[0],UiMax[1],WMODoodadPlacementID,WMOGroupID\n' +
  '1,1,0,0,0,-100,100,200,100,0,0,1,1,0,0\n' +
  '2,2,0,-1000,-1000,-100,1000,1000,100,0,0,1,1,0,0\n';
const objectCandidates = generateObjects(objectFixture, objectMaps, objectAssignments, '1.60.1.70205');
assert.equal(objectCandidates.records.length, 1);
assert.deepEqual(objectCandidates.skipped, { conditional: 1, unsupported: 1, unmapped: 1 });
assert.equal(objectCandidates.records[0].mapID, 1, 'use the smallest containing zone, not a continent-sized region');
assert.equal(objectCandidates.records[0].x, 25);
assert.equal(objectCandidates.records[0].y, 25);
assert.equal(objectCandidates.records[0].name, 'Synthetic sign [Sign]');
assert.throws(() => generateObjects(objectFixture + '1,Duplicate,0,75,150,0,5,0,0,0\n',
  objectMaps, objectAssignments, '1.60.1.70205'), /duplicate/);
assert.throws(() => generateObjects(objectFixture.replace('75,150', 'bad,150'),
  objectMaps, objectAssignments, '1.60.1.70205'), /numeric/);
assert.throws(() => generateObjects(objectFixture, objectMaps, objectAssignments, '12.0.1.1'), /Forever/);
const catalogFixture = 'ID,System,Type\n3,0,3\n1,0,3\n2,1,3\n4,0,2\n';
assert.deepEqual(generateCatalog(catalogFixture, '1.60.1.70205').maps, [1, 3]);
assert.throws(() => generateCatalog('ID,System,Type\n1,0,3\n1,0,3\n', '1.60.1.70205'), /duplicate/);
assert.throws(() => generateCatalog('ID,System,Type\n1,bad,3\n', '1.60.1.70205'), /numeric/);
assert.throws(() => generateCatalog(catalogFixture, '12.0.1.1'), /Forever/);
assert.throws(() => generateCatalog('ID,System,Type\n1,1,3\n', '1.60.1.70205'), /No world-zone/);
const record = {
  key: 'synthetic:1', npcID: 1, name: 'Synthetic "vendor"\n',
  kind: 'npc', category: 'Vendors', mapID: 1, x: 1, y: 2,
  source: 'synthetic-test-only', permission: 'test-fixture', build: 'test',
  edition: 'Forever', locale: 'enUS', verification: 'curated', precision: 'confirmed', tags: ['vendor'],
};
assert.equal(generate([record]).accepted, 1);
assert.equal(generate([record, record]).duplicates, 1);
assert.equal(generate([{ ...record, x: NaN }]).rejected.length, 1);
assert.equal(generate([{ ...record, permission: '' }]).rejected.length, 1);
assert.equal(generate([{ ...record, tags: ['unknown'] }]).rejected.length, 1);
assert.equal(generate([{ ...record, mapID: 0 }]).rejected.length, 1);
assert.equal(generate([{ ...record, edition: 'Retail' }]).rejected.length, 1);
assert.equal(generate([{ ...record, key: 'client:taxi:1:2' }]).rejected.length, 1);
assert.equal(generate([{ ...record, key: 'reference:1' }]).rejected.length, 1);
assert.equal(generate([{ ...record, level: -1, reaction: 4, classification: 'elite', creatureType: 'Humanoid' }]).accepted, 1);
assert.equal(generate([{ ...record, reaction: 9 }]).rejected.length, 1);
assert.equal(generate([{ ...record, level: -2 }]).rejected.length, 1);
assert.equal(generate([{ ...record, classification: 123 }]).rejected.length, 1);
execute(generate([record]).text, 'generated-import.lua', true);
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-import-test-'));
const inputPath = path.join(temporary, 'input.json');
const outputPath = path.join(temporary, 'output.lua');
const mapsPath = path.join(temporary, 'maps.csv');
const assignmentsPath = path.join(temporary, 'assignments.csv');
try {
  fs.writeFileSync(inputPath, JSON.stringify([record]));
  const runImport = () => spawnSync(process.execPath,
    [path.join(root, 'tools', 'import-data.cjs'), inputPath, outputPath], { encoding: 'utf8' });
  assert.equal(runImport().status, 0);
  const original = fs.readFileSync(outputPath, 'utf8');
  assert.equal(runImport().status, 1, 'existing output must not be overwritten');
  assert.equal(fs.readFileSync(outputPath, 'utf8'), original);
  fs.unlinkSync(outputPath);
  fs.writeFileSync(inputPath, JSON.stringify([record, { ...record, x: -1 }]));
  assert.equal(runImport().status, 1);
  assert.equal(fs.existsSync(outputPath), false, 'rejected input must not produce partial output');
  fs.writeFileSync(inputPath, catalogFixture);
  const makeCatalog = () => spawnSync(process.execPath, [
    path.join(root, 'tools', 'client-map-csv.cjs'), inputPath, outputPath, '1.60.1.70205',
  ], { encoding: 'utf8' });
  assert.equal(makeCatalog().status, 0);
  const savedCatalog = fs.readFileSync(outputPath, 'utf8');
  assert.equal(makeCatalog().status, 1);
  assert.equal(fs.readFileSync(outputPath, 'utf8'), savedCatalog);
  fs.unlinkSync(outputPath);
  fs.writeFileSync(inputPath, 'ID,System,Type\n1,0,3\n1,0,3\n');
  assert.equal(makeCatalog().status, 1);
  assert.equal(fs.existsSync(outputPath), false, 'invalid catalog must not leave partial output');
  fs.writeFileSync(inputPath, objectFixture);
  fs.writeFileSync(mapsPath, objectMaps);
  fs.writeFileSync(assignmentsPath, objectAssignments);
  const makeObjects = () => spawnSync(process.execPath, [
    path.join(root, 'tools', 'object-csv.cjs'), inputPath, mapsPath, assignmentsPath, outputPath, '1.60.1.70205',
  ], { encoding: 'utf8' });
  assert.equal(makeObjects().status, 0);
  const savedObjects = fs.readFileSync(outputPath, 'utf8');
  assert.equal(makeObjects().status, 1);
  assert.equal(fs.readFileSync(outputPath, 'utf8'), savedObjects);
  fs.unlinkSync(outputPath);
  fs.writeFileSync(inputPath, objectFixture.replace('75,150', 'bad,150'));
  assert.equal(makeObjects().status, 1);
  assert.equal(fs.existsSync(outputPath), false);
  if (process.env.MONSTRATOR_DBC2CSV) {
    const binary = path.join(temporary, 'Creature.db2');
    const converted = path.join(temporary, 'converted');
    const invokeConverter = () => spawnSync('powershell.exe', [
      '-NoProfile', '-File', path.join(root, 'tools', 'convert-db2.ps1'),
      '-Converter', process.env.MONSTRATOR_DBC2CSV, '-InputFile', binary,
      '-OutputDirectory', converted,
    ], { encoding: 'utf8' });
    try {
      fs.writeFileSync(binary, 'WDBC');
      assert.notEqual(invokeConverter().status, 0, 'unsupported legacy format must fail');
      fs.writeFileSync(binary, 'WDC1');
      const failedConversion = invokeConverter();
      assert.notEqual(failedConversion.status, 0, 'malformed modern table must fail despite converter exit status');
      assert.ok(fs.existsSync(converted), failedConversion.stderr || 'conversion wrapper did not reach conversion');
      assert.match(failedConversion.stdout, /Loaded \d+ definitions/,
        'installed converter must successfully load the updated definition set');
      assert.equal(fs.readFileSync(binary, 'utf8'), 'WDC1', 'original input must remain untouched');
      assert.equal(fs.existsSync(path.join(converted, 'Creature.db2')), false, 'staged input must be cleaned');
      assert.equal(fs.existsSync(path.join(converted, 'Creature.csv')), false, 'failed conversion must not leave CSV');
      fs.writeFileSync(path.join(converted, 'Creature.csv'), 'preserve');
      assert.notEqual(invokeConverter().status, 0);
      assert.equal(fs.readFileSync(path.join(converted, 'Creature.csv'), 'utf8'), 'preserve');
    } finally {
      if (fs.existsSync(binary)) fs.unlinkSync(binary);
      for (const name of ['Creature.db2', 'Creature.csv']) {
        const file = path.join(converted, name);
        if (fs.existsSync(file)) fs.unlinkSync(file);
      }
      if (fs.existsSync(converted)) fs.rmdirSync(converted);
    }
  }
} finally {
  if (fs.existsSync(inputPath)) fs.unlinkSync(inputPath);
  if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
  if (fs.existsSync(mapsPath)) fs.unlinkSync(mapsPath);
  if (fs.existsSync(assignmentsPath)) fs.unlinkSync(assignmentsPath);
  fs.rmdirSync(temporary);
}

// Submissions: an independent double-precision implementation (WoW's Lua 5.1 number model) must match the
// fengari-run addon code, and the maintainer review must accept, hold and reject the right records.
{
  const SEAL_VECTOR = '654b3b0b1531361376cd9a8b08a4f965';
  const lanes = [[2147483629, 1000003], [2147483587, 1000033], [2147483579, 1000037], [2147483563, 1000039]];
  const sealHash = (text) => {
    const bytes = Buffer.from(text, 'utf8');
    return lanes.map(([mod, base], i) => {
      const lane = i + 1;
      let h = lane * 7919;
      const feed = (data) => { for (const b of data) h = (h * base + b + lane) % mod; };
      feed(Buffer.from('monstrator-seal-v1')); feed(bytes); feed(Buffer.from(String(bytes.length)));
      return h.toString(16).padStart(8, '0');
    }).join('');
  };
  lua.lua_getglobal(state, to_luastring('SUBMISSION_VECTOR_OUT'));
  const vector = to_jsstring(lua.lua_tostring(state, -1));
  lua.lua_getglobal(state, to_luastring('SUBMISSION_SAMPLE'));
  const sample = to_jsstring(lua.lua_tostring(state, -1));
  lua.lua_pop(state, 2);
  assert.equal(sealHash('Monstrator'), vector, 'seal hash must agree across Lua runtimes');
  assert.equal(vector, SEAL_VECTOR, 'the seal algorithm must never change; existing seals would break');

  const esc = (v) => String(v).replace(/[%|;\r\n]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0'));
  const line = (r) => [r.key, 'npc', r.npcID, esc(r.name), r.category || 'Vendors', r.mapID, Math.floor(r.x * 100 + 0.5),
    Math.floor(r.y * 100 + 0.5), (r.tags || []).join(','), 'local:MERCHANT_SHOW', '1.60.1.70205', 'enUS',
    r.verification || 'user-confirmed', 'confirmed', 1, 1700000000, '', '', ''].join('|');
  const submission = (submitter, records, { breakRecord, breakOverall } = {}) => {
    const lines = ['MONSTRATOR SUBMISSION v1', 'addon=1.0.0', 'build=70205', 'locale=enUS', 'submitter=' + submitter,
      'created=1700000000', 'records=' + records.length];
    records.forEach((r, i) => {
      const canonical = line(r);
      const seal = sealHash(canonical + '|' + submitter);
      lines.push('R|' + canonical + '|' + (breakRecord === i ? seal.replace(/^./, (c) => (c === '0' ? '1' : '0')) : seal));
    });
    const body = lines.join('\n') + '\n';
    lines.push('seal=' + (breakOverall ? '0'.repeat(32) : sealHash(body)), 'END');
    return lines.join('\r\n');
  };
  const db = require('../tools/monstrator-db.cjs');
  const npcs = db.readNative(path.join(root, 'Data', 'Native'), 'Npc');
  let known;
  for (const [id, raw] of npcs) {
    const row = db.decodeRow('Npc', raw);
    const map = row.spawns && Object.keys(row.spawns)[0];
    if (map && row.name && !/[|%;]/.test(row.name)) { known = { npcID: id, name: row.name, mapID: Number(map), x: row.spawns[map][0][0], y: row.spawns[map][0][1] }; break; }
  }
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-review-test-'));
  const inbox = path.join(work, 'inbox');
  const source = path.join(work, 'source');
  fs.mkdirSync(inbox);
  const fresh = { npcID: 999999, name: 'Forever | Only; Vendor', mapID: 1429, x: 33.3, y: 44.4, tags: ['vendor'] };
  try {
    const records = [{ key: 'local:1', ...fresh }];
    if (known) records.push({ key: 'local:2', ...known });
    fs.writeFileSync(path.join(inbox, '1-alpha.txt'), 'Issue body\n```\n' + submission('aaaaaaaaaaaaaaaa', records) + '\n```\n');
    fs.writeFileSync(path.join(inbox, '2-forged.txt'), submission('bbbbbbbbbbbbbbbb', [{ key: 'local:1', ...fresh, x: 90 }], { breakRecord: 0 }));
    fs.writeFileSync(path.join(inbox, '3-edited.txt'), submission('cccccccccccccccc', [{ key: 'local:1', ...fresh }], { breakOverall: true }));
    fs.writeFileSync(path.join(inbox, '4-game.txt'), sample);
    const review = (...args) => spawnSync(process.execPath, ['--stack-size=65500', path.join(root, 'tools', 'monstrator-db.cjs'), 'review', ...args],
      { encoding: 'utf8', env: { ...process.env, MONSTRATOR_SOURCE_DIR: source } });
    let run = review(inbox);
    assert.equal(run.status, 2, 'rejections give a non-zero exit code: ' + run.stderr);
    assert.match(run.stdout, /3-edited\.txt: whole submission rejected - overall seal does not match/);
    assert.match(run.stdout, /2-forged\.txt record 1: 999999 .* seal broken/);
    assert.match(run.stdout, /1-alpha\.txt record 1: 999999 Forever \| Only; Vendor - .*not in the database \(1\/2 reporters\)/, run.stdout);
    if (known) assert.match(run.stdout, /1-alpha\.txt record 2: .* - consistent with database/);
    assert.doesNotMatch(run.stdout, /4-game\.txt.*(seal broken|whole submission rejected)/, 'in-game submissions verify in the tool');
    assert.match(run.stdout, /4-game\.txt record \d: \d+ Seal \| Tester; 100% - captured before seals existed/);
    assert.equal(fs.existsSync(source), false, 'a dry run writes nothing');

    fs.writeFileSync(path.join(inbox, '5-beta.txt'), submission('dddddddddddddddd', [{ key: 'local:7', ...fresh, x: 33.8 }]));
    run = review(inbox, '--apply');
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout, /999999 Forever \| Only; Vendor - corroborated by 2 reporters/, 'a second player corroborates new data');
    const discoveries = fs.readFileSync(path.join(source, 'Discoveries.lua'), 'utf8');
    assert.match(discoveries, /\[999999\] = \{/);
    assert.match(discoveries, /name = "Forever \| Only; Vendor"/);
    const ledger = JSON.parse(fs.readFileSync(path.join(source, 'SubmissionLedger.json'), 'utf8'));
    assert.equal(Object.keys(ledger.submissions).length, 4, 'every readable submission is recorded once');
    run = review(inbox);
    assert.match(run.stdout, /1-alpha\.txt: already reviewed, skipped/, 'resubmitting the same text is ignored');
    assert.match(run.stdout, /Reviewed 0 new submission/);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}
console.log('PASS: Lua/UI behavior, native database index/overlay/standalone/audit, 10 locales, zone browsing, grouping, incremental map indexes, native-map providers, journal editing, import/CSV validation' +
  (process.env.MONSTRATOR_DBC2CSV ? ', and real DBC2CSV failure-safety checks.' : '.'));
