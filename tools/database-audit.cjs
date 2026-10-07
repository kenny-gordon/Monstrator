const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { LAYOUT, decodeRow, evalLua } = require('./monstrator-db.cjs');
const { quote } = require('./import-data.cjs');

const TARGETS = {
  Item: { vendors: 'Npc', npcDrops: 'Npc', objectDrops: 'Object', questRewards: 'Quest', itemDrops: 'Item', startQuest: 'Quest' },
  Quest: { starterNpcs: 'Npc', starterObjects: 'Object', finisherNpcs: 'Npc', finisherObjects: 'Object' },
};
const NUMERIC = {
  Npc: ['npcFlags', 'minLevel', 'maxLevel'],
  Item: ['requiredLevel', 'itemLevel', 'class', 'subClass', 'startQuest'],
  Quest: ['questLevel', 'requiredLevel'],
};

function parseRows(text, kind) {
  const rows = new Map(), issues = [];
  const issue = (id, line, message) => issues.push({ severity: 'error', code: 'raw-row', kind, id, line, message });
  let previous = 0;
  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (!/^D\[/.test(line)) continue;
    const match = line.match(/^D\[(\d+)\]="((?:[^"\\]|\\.)*)"$/);
    if (!match) { issue(null, index + 1, 'Malformed native row assignment'); continue; }
    const id = Number(match[1]);
    if (!Number.isSafeInteger(id) || id <= 0) issue(id, index + 1, 'ID must be a positive safe integer');
    if (rows.has(id)) issue(id, index + 1, 'Duplicate entity ID overwrites an earlier row');
    if (id <= previous) issue(id, index + 1, 'Entity IDs are not strictly ascending');
    previous = id;
    rows.set(id, match[2].replace(/\\(.)/g, '$1'));
  }
  return { rows, issues };
}

function inspect(tables) {
  const issues = [], counts = {};
  const add = (severity, code, kind, id, field, message, extra = {}) =>
    issues.push({ severity, code, kind, id, field, message, ...extra });
  for (const kind of Object.keys(LAYOUT)) {
    const rows = tables[kind] || new Map();
    let spawnPoints = 0;
    const maps = new Set();
    for (const [id, raw] of rows) {
      if (!Number.isSafeInteger(id) || id <= 0) add('error', 'entity-id', kind, id, null, 'Invalid entity ID');
      if (typeof raw !== 'string') { add('error', 'row-type', kind, id, null, 'Row must be a string'); continue; }
      if (raw.split('\t').length !== LAYOUT[kind].length) {
        add('error', 'field-count', kind, id, null, `Expected ${LAYOUT[kind].length} tab-separated fields`);
      }
      const row = decodeRow(kind, raw);
      const fields = raw.split('\t');
      for (const field of Object.keys(TARGETS[kind] || {})) {
        const text = fields[LAYOUT[kind].indexOf(field)];
        if (text && !/^\d+(,\d+)*$/.test(text)) add('error', 'reference-format', kind, id, field, 'Malformed relationship field');
      }
      if (LAYOUT[kind].includes('spawns')) {
        const text = fields[LAYOUT[kind].indexOf('spawns')];
        if (text) {
          const point = '[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?';
          const part = `\\d+:${point},${point}(?: ${point},${point})*`;
          if (!new RegExp(`^${part}(?:;${part})*$`).test(text)) {
            add('error', 'spawn-format', kind, id, 'spawns', 'Malformed spawn field');
          }
          const maps = text.split(';').map((part) => part.split(':')[0]);
          if (new Set(maps).size !== maps.length) add('error', 'duplicate-map', kind, id, 'spawns', 'Repeated map key overwrites earlier points');
        }
      }
      if (!row.name || !row.name.trim()) add('error', 'empty-name', kind, id, 'name', 'Missing display name');
      if (row.name && /[\x00-\x1f\x7f\uFFFD]/.test(row.name)) add('error', 'name-encoding', kind, id, 'name', 'Control/replacement character in name');
      for (const field of NUMERIC[kind] || []) {
        if (row[field] !== undefined && !Number.isSafeInteger(row[field])) {
          add('error', 'numeric-field', kind, id, field, 'Expected a finite safe integer');
        }
      }
      if (row.minLevel !== undefined && row.maxLevel !== undefined && row.minLevel > row.maxLevel) {
        add('error', 'level-range', kind, id, 'minLevel', 'Minimum level exceeds maximum level');
      }
      for (const [field, target] of Object.entries(TARGETS[kind] || {})) {
        const refs = row[field] === undefined || (field === 'startQuest' && row[field] === 0)
          ? [] : Array.isArray(row[field]) ? row[field] : [row[field]];
        const seen = new Set();
        for (const ref of refs) {
          if (!Number.isSafeInteger(ref) || ref <= 0) {
            add('error', 'reference-id', kind, id, field, 'Reference must be a positive safe integer', { relatedID: ref });
          } else if (!(tables[target] || new Map()).has(ref)) {
            add('warning', 'unresolved-reference', kind, id, field, `Target ${target} is not present`, { relatedKind: target, relatedID: ref });
          }
          if (seen.has(ref)) add('error', 'duplicate-reference', kind, id, field, 'Duplicate relationship', { relatedID: ref });
          seen.add(ref);
        }
      }
      const spawnText = LAYOUT[kind].includes('spawns') ? fields[LAYOUT[kind].indexOf('spawns')] : '';
      const spawnEntries = spawnText ? spawnText.split(';').map((part) => {
        const [map, points] = part.split(':');
        return [map, (points || '').split(' ').filter(Boolean).map((point) => point.split(',').map(Number))];
      }) : [];
      for (const [map, points] of spawnEntries) {
        if (!Number.isSafeInteger(Number(map)) || Number(map) <= 0) add('error', 'map-id', kind, id, 'spawns', 'Invalid UI map ID');
        const seen = new Set();
        maps.add(Number(map));
        for (const point of points) {
          spawnPoints++;
          if (point.length !== 2 || point.some((v) => !Number.isFinite(v) || v < 0 || v > 100)) {
            add('error', 'coordinates', kind, id, 'spawns', 'Coordinates must be finite percentages in [0,100]', { mapID: Number(map) });
          }
          const key = point.join(',');
          if (seen.has(key)) add('error', 'duplicate-spawn', kind, id, 'spawns', 'Duplicate exact spawn point', { mapID: Number(map), point });
          seen.add(key);
        }
      }
    }
    counts[kind] = { entities: rows.size, spawnPoints, maps: maps.size };
  }
  return { counts, issues };
}

function readTables(dir) {
  const tables = {}, issues = [];
  for (const kind of Object.keys(LAYOUT)) {
    const file = path.join(dir, `${kind}s.lua`);
    if (!fs.existsSync(file)) throw new Error('Database file missing: ' + file);
    const parsed = parseRows(fs.readFileSync(file, 'utf8'), kind);
    tables[kind] = parsed.rows;
    issues.push(...parsed.issues);
  }
  return { tables, issues };
}

function compare(current, candidate) {
  const result = {};
  for (const kind of Object.keys(LAYOUT)) {
    const a = current[kind] || new Map(), b = candidate[kind] || new Map();
    const added = [], removed = [], changed = [];
    for (const id of b.keys()) if (!a.has(id)) added.push(id);
    for (const [id, raw] of a) {
      if (!b.has(id)) removed.push(id);
      else if (raw !== b.get(id)) {
        const before = decodeRow(kind, raw), after = decodeRow(kind, b.get(id));
        changed.push({ id, name: before.name, fields: LAYOUT[kind].filter((field) =>
          JSON.stringify(before[field]) !== JSON.stringify(after[field])) });
      }
    }
    result[kind] = { added: added.sort((a, b) => a - b), removed: removed.sort((a, b) => a - b),
      changed: changed.sort((a, b) => a.id - b.id) };
  }
  return result;
}

function pfQuestNames(folder, npcs) {
  const file = path.join(folder, 'db-enUS-units.lua');
  const text = fs.readFileSync(file, 'utf8');
  const names = evalLua(`local env = { pfDB = { units = {} } }
assert(load(${quote(text)}, "pfQuest NPC names", "t", env))()
__names = env.pfDB.units.enUS`, 'pfQuest comparison', '__names');
  let matched = 0, absent = 0;
  const disagreements = [];
  for (const [id, raw] of npcs) {
    const name = decodeRow('Npc', raw).name, other = names[id];
    if (!other) absent++;
    else if (name === other) matched++;
    else disagreements.push({ id, name, referenceName: other });
  }
  return { scope: 'Vanilla NPC names only; no placement, loot or Forever verification',
    sourceFile: 'db-enUS-units.lua', sourceSha256: crypto.createHash('sha256').update(text).digest('hex'),
    matched, absent, disagreements: disagreements.sort((a, b) => a.id - b.id) };
}

function replacementIssues(current, candidate, allowRemovals = false) {
  const issues = inspect(candidate).issues.filter((issue) => issue.severity === 'error');
  if (current && !allowRemovals) {
    for (const [kind, changes] of Object.entries(compare(current, candidate))) {
      if (changes.removed.length) issues.push({ severity: 'error', code: 'coverage-loss', kind,
        message: `Import would remove ${changes.removed.length} ${kind} IDs; review them before using --allow-removals`,
        removed: changes.removed });
    }
  }
  return issues;
}

module.exports = { parseRows, inspect, readTables, compare, pfQuestNames, replacementIssues };
