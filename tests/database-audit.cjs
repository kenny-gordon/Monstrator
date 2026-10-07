const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { parseRows, inspect, compare, replacementIssues } = require('../tools/database-audit.cjs');
const { evalLua } = require('../tools/monstrator-db.cjs');
const { quote } = require('../tools/import-data.cjs');

const fixtures = () => ({
  Npc: new Map([[1, 'Boss\t\t0\t10\t11\tAH\t1:20,30']]),
  Object: new Map([[2, 'Chest\t1:30,40\tchest']]),
  Item: new Map([[3, 'Sword\t1\t5\t2\t7\t0\t\t1\t2\t4\t']]),
  Quest: new Map([[4, 'Quest\t5\t1\t1\t2\t1\t2']]),
});
assert.deepEqual(inspect(fixtures()).issues, [], 'clean data and startQuest=0 sentinel are accepted');
const malformed = parseRows('D[1]="a"\nD[1]="b"\nD[0]="c"\nD[2]=garbage', 'Npc');
assert.ok(malformed.issues.some((i) => i.message.startsWith('Duplicate entity')));
assert.ok(malformed.issues.some((i) => i.message.startsWith('Entity IDs')));
assert.ok(malformed.issues.some((i) => i.message.startsWith('ID must')));
assert.ok(malformed.issues.some((i) => i.message.startsWith('Malformed')));
const sample = fixtures();
sample.Npc.set(1, 'Boss\t\t0\t12\t11\tAH\t1:20,30 20,30;1:101,30');
sample.Item.set(3, 'Sword\t1\t5\t2\t7\t99\t1,1\t0\t2,x\t4\t');
const issues = inspect(sample).issues;
for (const code of ['level-range', 'duplicate-spawn', 'duplicate-map', 'coordinates',
  'duplicate-reference', 'reference-id', 'reference-format', 'unresolved-reference']) {
  assert.ok(issues.some((issue) => issue.code === code), code + ' must be detected');
}
assert.ok(issues.some((i) => i.kind === 'Item' && i.id === 3 && i.field === 'startQuest' && i.relatedID === 99),
  'unresolved references identify exact source and target IDs');
const existing = fixtures(), candidate = fixtures();
candidate.Quest.clear();
candidate.Npc.set(1, 'Boss\t\t0\t12\t11\tAH\t1:20,30');
assert.deepEqual(compare(existing, candidate).Quest.removed, [4]);
assert.deepEqual(compare(existing, candidate).Npc.changed[0].fields, ['minLevel']);
assert.ok(replacementIssues(existing, candidate).some((i) => i.code === 'coverage-loss'));
assert.ok(replacementIssues(existing, candidate, true).some((i) => i.code === 'level-range'),
  'allow-removals must never bypass schema failures');
assert.ok(!replacementIssues(existing, candidate, true).some((i) => i.code === 'coverage-loss'));
const strings = ['name\t4\t30\tH\t1456', 'UTF-8: Café 中文', '\u0000\u0001\u001f\n\r"\\', '1\t999999'];
for (const value of strings) {
  assert.equal(evalLua(`local value = ${quote(value)}`, 'lossless JSON', 'value'), value,
    'Lua-to-JSON bridge preserves controls followed by digits and UTF-8');
}
assert.deepEqual(evalLua(`local value = { [${quote(strings[0])}] = ${quote(strings[1])} }`, 'JSON keys', 'value'),
  { [strings[0]]: strings[1] });

const root = path.resolve(__dirname, '..'), work = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-db-audit-'));
try {
  const file = path.join(work, 'report.json');
  const result = spawnSync(process.execPath, [path.join(root, 'tools', 'monstrator-db.cjs'), 'audit', '--output', file],
    { encoding: 'utf8', env: process.env });
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(report.base.issues.filter((i) => i.severity === 'error').length, 0);
  assert.equal(report.effective.issues.filter((i) => i.severity === 'error').length, 0);
  assert.equal(report.effective.counts.Npc.entities, 10122);
  assert.deepEqual(report.effective.issues.filter((i) => i.code === 'unresolved-reference').map((i) => [i.id, i.relatedID]),
    [[10590, 3482], [20483, 8338], [22719, 9233], [227911, 84377]]);
  assert.ok(report.externalReview.unresolvedItemQuests.length === 4, 'review context accompanies unresolved IDs');

  const source = path.join(work, 'source'), out = path.join(work, 'native');
  fs.mkdirSync(source);
  fs.writeFileSync(path.join(source, 'QuestieDB_Forever.toc'),
    '## Version: fixture\n## X-BUILD-COMMIT: fixture\n## Author: Test\nfixture.lua\n');
  const writeSource = ({ invalid = false, removeQuest = false, unstable = false } = {}) => {
    fs.writeFileSync(path.join(source, 'fixture.lua'), `
local calls = 0
LibQuestieDB = {
  Support = { Get = function() return { private = { areaIdToUiMapId = "[1]=1", areaIdToUiMapIdOverride = "" } } end },
  Npc = {
    GetAllIds = function() return {1} end,
    name = function()
      calls = calls + 1
      return ${unstable ? 'calls > 1 and "Changed name" or "Boss"' : '"Boss"'}
    end,
    npcFlags = function() return 0 end,
    minLevel = function() return ${invalid ? 12 : 10} end,
    maxLevel = function() return 11 end,
    spawns = function() return { [1] = {{20,30}} } end,
  },
  Object = { GetAllIds = function() return {} end },
  Item = { GetAllIds = function() return {} end },
  Quest = {
    GetAllIds = function() return ${removeQuest ? '{}' : '{4}'} end,
    name = function() return "Quest" end,
    startedBy = function() return {{1}} end,
    finishedBy = function() return {{1}} end,
  },
}`);
  };
  const invokeImport = (...extra) => spawnSync(process.execPath,
    [path.join(root, 'tools', 'monstrator-db.cjs'), 'import', '--from', 'questiedb', source, 'Forever', ...extra],
    { encoding: 'utf8', env: { ...process.env, MONSTRATOR_NATIVE_OUT: out } });
  writeSource();
  let imported = invokeImport();
  assert.equal(imported.status, 0, imported.stderr);
  const names = fs.readdirSync(out);
  const before = new Map(names.map((file) => [file, fs.readFileSync(path.join(out, file))]));
  const unchanged = () => {
    assert.deepEqual(fs.readdirSync(out), names);
    for (const [file, bytes] of before) assert.deepEqual(fs.readFileSync(path.join(out, file)), bytes, 'rejected imports preserve ' + file);
  };
  writeSource({ invalid: true });
  imported = invokeImport('--allow-removals');
  assert.notEqual(imported.status, 0);
  assert.match(imported.stderr, /Minimum level exceeds maximum level/);
  unchanged();
  writeSource({ removeQuest: true });
  imported = invokeImport();
  assert.notEqual(imported.status, 0);
  assert.match(imported.stderr, /Import would remove 1 Quest IDs/);
  unchanged();
  writeSource({ unstable: true });
  imported = invokeImport();
  assert.notEqual(imported.status, 0);
  assert.match(imported.stderr, /Import rejected before writing: Npc 1.name differs/);
  unchanged();
  writeSource({ removeQuest: true });
  imported = invokeImport('--allow-removals');
  assert.equal(imported.status, 0, imported.stderr);
  assert.equal(JSON.parse(fs.readFileSync(path.join(out, 'manifest.json'), 'utf8')).files['Quests.lua'].entries, 0,
    'explicit reviewed deletions can be accepted when structure and parity pass');
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
