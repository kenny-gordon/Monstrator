const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { identity, parseHTML, loadReferences, compareReferences, queueReferences } = require('../tools/wowhead-audit.cjs');

const url = 'https://www.wowhead.com/classic/npc=823/deputy-willem';
const expected = identity(url);
const html = `<html><head><link href='${url}' rel='canonical'><title>Deputy Willem - NPC - Classic World of Warcraft</title>
<meta content="Deputy Willem is a level 18 NPC that can be found in Elwynn Forest." name="description"></head></html>`;
const parsed = parseHTML(html, expected);
assert.deepEqual(parsed.facts, { name: 'Deputy Willem', minLevel: 18, maxLevel: 18 });
assert.equal(parseHTML(html.replace('npc=823', 'npc=824'), expected).status, 'unavailable');
assert.equal(parseHTML('<title>Just a moment...</title>', expected).status, 'unavailable');
const range = parseHTML(html.replaceAll('Deputy Willem', 'Kobold Vermin').replaceAll('npc=823', 'npc=6')
  .replace('level 18', 'level 1 - 2'), identity('https://www.wowhead.com/classic/npc=6'));
assert.deepEqual(range.facts, { name: 'Kobold Vermin', minLevel: 1, maxLevel: 2 });
const itemURL = 'https://www.wowhead.com/classic/item=22719';
const itemHTML = `<head><link rel="canonical" href="${itemURL}"><title>Omarion&apos;s Handbook - Item - Classic World of Warcraft</title>
<meta name="description" content="This item has an item level of 60."></head>`;
assert.deepEqual(parseHTML(itemHTML, identity(itemURL)).facts, { name: "Omarion's Handbook", itemLevel: 60 });
assert.equal(parseHTML(html.replace('Classic World of Warcraft', 'TBC Classic'), expected).status, 'unavailable');
assert.equal(parseHTML(`<head><script>${html}</script><!--${html}--></head>`, expected).status, 'unavailable');
assert.equal(parseHTML(html.replace('level 18', 'level 20-18'), expected).status, 'unavailable');
for (const bad of ['https://example.com/classic/npc=823', 'https://www.wowhead.com.evil.test/classic/npc=823',
  'https://www.wowhead.com/npc=823', 'https://www.wowhead.com/classic/fr/npc=823', 'https://www.wowhead.com/classic/npc=0',
  'https://www.wowhead.com/classic/npc=823?xml', 'http://www.wowhead.com/classic/npc=823']) {
  assert.throws(() => identity(bad));
}
const tables = { Npc: new Map([[823, 'Deputy Willem\t\t2\t18\t18\tA\t1:50,50'],
  [6, 'Kobold Vermin\t\t0\t1\t1\t\t1:50,50']]), Item: new Map(), Quest: new Map(), Object: new Map() };
const refs = [
  { ...expected, ...parsed, url, checkedAt: '2026-10-07' },
  { ...identity('https://www.wowhead.com/classic/npc=6'), ...range, url: 'https://www.wowhead.com/classic/npc=6' },
  { kind: 'Item', id: 20483, edition: 'tbc', status: 'readable', facts: { name: 'Tainted Arcane Sliver' } },
  { kind: 'Npc', id: 99, edition: 'classic', status: 'unavailable', reason: 'not found' },
  { kind: 'Quest', id: 9233, edition: 'classic', status: 'readable', facts: { name: "Omarion's Handbook" } },
];
const result = compareReferences(tables, refs);
assert.deepEqual(result.summary, { references: 5, matched: 1, conflicts: 1, unavailable: 1, versionMismatch: 1,
  missingLocal: 1, comparedFields: 6 });
assert.equal(result.results[1].fields.find((f) => f.field === 'maxLevel').matches, false);
assert.equal(result.coverage.Npc.checkedRecords, 2);
assert.deepEqual(queueReferences(tables, refs), []);
assert.equal(queueReferences(tables, []).length, 2);
assert.equal(tables.Npc.get(6), 'Kobold Vermin\t\t0\t1\t1\t\t1:50,50', 'comparison never edits data');

const root = path.resolve(__dirname, '..'), work = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-wowhead-'));
try {
  const manifest = path.join(work, 'reference.json'), snapshot = path.join(work, 'willem.html');
  fs.writeFileSync(snapshot, html);
  const entry = { kind: 'Npc', id: 823, url, checkedAt: '2026-10-07', file: 'willem.html' };
  const write = (entries) => fs.writeFileSync(manifest, JSON.stringify({ schemaVersion: 1, entries }));
  write([entry]);
  const reference = loadReferences(manifest)[0];
  assert.deepEqual(reference.facts, parsed.facts);
  assert.match(reference.sha256, /^[a-f0-9]{64}$/);
  write([entry, entry]); assert.throws(() => loadReferences(manifest), /duplicate/);
  write([{ ...entry, id: 824 }]); assert.throws(() => loadReferences(manifest), /Mismatched/);
  write([{ ...entry, file: path.join(root, 'README.md') }]); assert.throws(() => loadReferences(manifest), /inside/);
  write([{ ...entry, file: undefined, facts: { name: 'Deputy Willem' } }]);
  assert.throws(() => loadReferences(manifest), /evidence/);
  write([{ ...entry, checkedAt: '2026-02-30' }]); assert.throws(() => loadReferences(manifest), /date/);
  write([{ ...entry, file: undefined, facts: { minLevel: 20, maxLevel: 18 },
    evidence: { minLevel: 'metadata', maxLevel: 'metadata' } }]);
  assert.throws(() => loadReferences(manifest), /range/);

  const report = path.join(work, 'report.json'), queue = path.join(work, 'queue.json');
  const sample = path.join(root, 'Data', 'Source', 'WowheadFacts.json');
  const run = spawnSync(process.execPath, [path.join(root, 'tools', 'monstrator-db.cjs'), 'audit',
    '--wowhead', sample, '--output', report, '--queue', queue], { encoding: 'utf8', env: process.env });
  assert.equal(run.status, 2, run.stderr); // Review findings, not a failed comparison.
  const actual = JSON.parse(fs.readFileSync(report, 'utf8')).wowhead;
  assert.equal(actual.summary.references, 32);
  assert.equal(actual.summary.matched, 27);
  assert.equal(actual.summary.conflicts, 1);
  assert.equal(actual.summary.versionMismatch, 1);
  assert.equal(actual.summary.missingLocal, 3);
  const conflict = actual.results.find((r) => r.status === 'conflict');
  assert.equal(conflict.id, 89);
  assert.deepEqual(conflict.fields.find((f) => f.field === 'maxLevel'), {
    field: 'maxLevel', local: 50, reference: 60, matches: false, evidence: 'page metadata',
  });
  assert.equal(actual.coverage.Npc.checkedRecords, 16);
  assert.equal(actual.coverage.Item.checkedRecords, 10);
  assert.equal(actual.coverage.Quest.checkedRecords, 2);
  const pending = JSON.parse(fs.readFileSync(queue, 'utf8')).entries;
  assert.ok(!pending.some((r) => r.kind === 'Npc' && r.id === 823));
  assert.ok(pending.some((r) => r.kind === 'Item' && r.id === 20483));
  assert.ok(pending.some((r) => r.kind === 'Npc' && r.id === 277055), 'custom Forever entities stay in the review queue, not a deletion list');
  const cli = (args) => spawnSync(process.execPath, [path.join(root, 'tools', 'monstrator-db.cjs'), 'audit', ...args],
    { encoding: 'utf8', env: process.env });
  const snapshotBefore = fs.readFileSync(sample, 'utf8');
  assert.equal(cli(['--wowhead', sample, '--output', sample]).status, 1);
  assert.equal(cli(['--output', sample, '--wowhead', sample]).status, 1);
  assert.equal(cli(['--queue', report, '--wowhead', sample, '--output', report]).status, 1);
  assert.equal(cli(['--queue', report]).status, 1);
  assert.equal(cli(['--wowhead', sample, '--output', path.join(root, 'README.md')]).status, 1);
  assert.equal(fs.readFileSync(sample, 'utf8'), snapshotBefore, 'overwrite attempts leave input intact');
  const outside = path.join(work, 'outside'), inside = path.join(work, 'snapshots');
  fs.mkdirSync(outside); fs.mkdirSync(inside);
  fs.writeFileSync(path.join(outside, 'page.html'), html);
  fs.symlinkSync(outside, path.join(inside, 'linked'), 'junction');
  const linkedManifest = path.join(inside, 'reference.json');
  fs.writeFileSync(linkedManifest, JSON.stringify({ schemaVersion: 1, entries: [{ ...entry, file: 'linked/page.html' }] }));
  assert.throws(() => loadReferences(linkedManifest), /inside/, 'linked snapshots cannot escape input folder');
  write([entry]);
  assert.equal(cli(['--wowhead', manifest, '--output', snapshot]).status, 1);
  assert.equal(cli(['--wowhead', manifest, '--queue', snapshot]).status, 1);
  assert.equal(fs.readFileSync(snapshot, 'utf8'), html);
  const cleanRun = cli(['--queue', queue, '--output', report, '--wowhead', manifest]);
  assert.equal(cleanRun.status, 0, cleanRun.stderr);
  assert.equal(JSON.parse(fs.readFileSync(report, 'utf8')).wowhead.summary.matched, 1);
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
