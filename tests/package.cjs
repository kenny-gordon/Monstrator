const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const zlib = require('node:zlib');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');

function readZip(file) {
  const buffer = fs.readFileSync(file), files = new Map();
  let offset = 0;
  while (buffer.readUInt32LE(offset) === 0x04034b50) {
    assert.equal(buffer.readUInt16LE(offset + 8), 8);
    const size = buffer.readUInt32LE(offset + 18), length = buffer.readUInt16LE(offset + 26);
    const start = offset + 30 + length + buffer.readUInt16LE(offset + 28);
    const name = buffer.subarray(offset + 30, offset + 30 + length).toString('utf8');
    const data = zlib.inflateRawSync(buffer.subarray(start, start + size));
    assert.equal(data.length, buffer.readUInt32LE(offset + 22));
    files.set(name, data);
    offset = start + size;
  }
  assert.equal(buffer.readUInt32LE(offset), 0x02014b50);
  return files;
}

const root = path.resolve(__dirname, '..'), work = fs.mkdtempSync(path.join(os.tmpdir(), 'monstrator-package-'));
try {
  const toc = fs.readFileSync(path.join(root, 'Monstrator.toc'), 'utf8');
  const runtime = toc.split(/\r?\n/).map((line) => line.trim()).filter((line) => line && !line.startsWith('#'));
  const required = ['Monstrator.toc', 'README.md', 'CHANGELOG.md', 'CONTRIBUTING.md', 'DATA_SCHEMA.md', 'LICENSE', ...runtime];
  for (const file of required) {
    const destination = path.join(work, file);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(path.join(root, file), destination);
  }
  for (const folder of ['tools', path.join('Data', 'Source'), path.join('Data', 'Native')]) {
    fs.cpSync(path.join(root, folder), path.join(work, folder), { recursive: true });
  }
  const clutter = ['debug.log', 'report.json', 'scratch.lua', 'backup.bak', path.join('Data', 'Native', 'review.json'),
    path.join('Locales', 'backup.lua'), path.join('scratch', 'page.html')];
  for (const file of clutter) {
    fs.mkdirSync(path.dirname(path.join(work, file)), { recursive: true });
    fs.writeFileSync(path.join(work, file), 'must not ship');
  }
  const run = (...args) => spawnSync(process.execPath, [path.join(work, 'tools', 'monstrator-db.cjs'), 'package', ...args],
    { encoding: 'utf8', env: process.env });
  const version = toc.match(/^## Version:\s*(.+)$/m)[1].trim();
  for (const standalone of [false, true]) {
    const result = standalone ? run('--standalone') : run();
    assert.equal(result.status, 0, result.stderr);
    const zip = readZip(path.join(work, 'dist', `Monstrator-${version}${standalone ? '-standalone' : ''}.zip`));
    const key = (file) => 'Monstrator/' + file.split(path.sep).join('/');
    for (const file of required) assert.ok(zip.has(key(file)), 'required file: ' + file);
    for (const file of clutter) assert.ok(!zip.has(key(file)), 'excluded clutter: ' + file);
    assert.ok(![...zip.keys()].some((name) => /Monstrator\/(?:tools|tests|Data\/Source)\//.test(name)));
    assert.ok(zip.has('Monstrator/CREDITS.md'));
    for (const file of runtime.filter((file) => !file.startsWith('Data\\Native\\'))) {
      assert.deepEqual(zip.get(key(file)), fs.readFileSync(path.join(root, file)), 'runtime preserved: ' + file);
    }
    for (const name of ['manifest.json', 'atlasloot-manifest.json', 'AtlasLoot-source.lua', 'AtlasLoot-LICENSE.txt']) {
      assert.equal(zip.has(`Monstrator/Data/Native/${name}`), !standalone, 'imported metadata: ' + name);
    }
    if (standalone) {
      assert.match(zip.get('Monstrator/Data/Native/LootReference.lua').toString(), /no imported loot/);
      assert.match(zip.get('Monstrator/Data/Native/Npcs.lua').toString(), /no imported base data/);
    } else {
      for (const file of runtime) assert.deepEqual(zip.get(key(file)), fs.readFileSync(path.join(root, file)));
      assert.match(zip.get('Monstrator/CREDITS.md').toString(), /GPLv2/);
    }
  }
  assert.equal(run('--unknown').status, 1);
  assert.equal(run('--standalone', '--standalone').status, 1);
  fs.writeFileSync(path.join(work, 'Monstrator.toc'), toc + '\r\nmissing.lua\r\n');
  assert.equal(run().status, 1, 'missing runtime file must stop packaging');
  fs.writeFileSync(path.join(work, 'Monstrator.toc'), toc + '\r\n..\\outside.lua\r\n');
  assert.equal(run().status, 1, 'TOC paths cannot escape the addon');
} finally {
  fs.rmSync(work, { recursive: true, force: true });
}
