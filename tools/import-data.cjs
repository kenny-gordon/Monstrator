const fs = require('node:fs');

const categories = {
  npc: ['Services', 'Vendors', 'Trainers', 'Transit', 'Combat'],
  location: ['Mailboxes', 'Instances', 'Transit', 'Landmarks', 'Objects'],
};
const tags = new Set([
  'innkeeper', 'flight', 'repair', 'bank', 'auction', 'mailbox', 'stable', 'guild',
  'tabard', 'food', 'drink', 'reagent', 'potion', 'weapon', 'armor',
  'profession_supplies', 'vendor', 'trainer', 'class_trainer', 'profession_trainer',
  'riding', 'weapon_master', 'portal', 'zeppelin', 'boat', 'flight_path',
  'dungeon', 'raid', 'quest_giver', 'landmark',
  'herb', 'ore', 'chest', 'fishing', 'anvil', 'forge', 'meeting_stone', 'cooking', 'quest_object',
]);
const fields = ['key', 'npcID', 'name', 'kind', 'category', 'mapID', 'x', 'y',
  'source', 'permission', 'edition', 'build', 'locale', 'verification', 'precision', 'tags', 'faction',
  'level', 'reaction', 'creatureType', 'classification'];

function validate(record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return 'expected an object';
  for (const field of ['key', 'name', 'source', 'permission', 'build', 'locale']) {
    if (typeof record[field] !== 'string' || !record[field].trim()) return `missing ${field}`;
  }
  if (['local:', 'client:', 'reference:'].some(prefix => record.key.startsWith(prefix))) {
    return 'local:, client: and reference: keys are reserved';
  }
  if (!categories[record.kind]?.includes(record.category)) return 'invalid kind/category';
  if (!Number.isSafeInteger(record.mapID) || record.mapID <= 0) return 'invalid mapID';
  if (record.kind === 'npc' && (!Number.isSafeInteger(record.npcID) || record.npcID <= 0)) return 'invalid npcID';
  if (![record.x, record.y].every(n => Number.isFinite(n) && n >= 0 && n <= 100)) return 'invalid coordinates';
  if (record.verification !== 'curated' || record.precision !== 'confirmed') return 'requires curated confirmed placement';
  if (record.edition !== 'Forever') return 'requires explicit Forever edition';
  if (!Array.isArray(record.tags) || record.tags.some(t => !tags.has(t))) return 'invalid canonical tags';
  if (record.faction !== undefined && !['Alliance', 'Horde', 'Both'].includes(record.faction)) return 'invalid faction';
  if (record.level !== undefined && (!Number.isSafeInteger(record.level) || record.level < -1)) return 'invalid level';
  if (record.reaction !== undefined && (!Number.isSafeInteger(record.reaction)
      || record.reaction < 1 || record.reaction > 8)) return 'invalid reaction';
  for (const field of ['creatureType', 'classification']) {
    if (record[field] !== undefined && typeof record[field] !== 'string') return `invalid ${field}`;
  }
  return null;
}

function quote(value) {
  return '"' + value.replace(/[\\"\x00-\x1f\x7f]/g, char => {
    if (char === '\\' || char === '"') return '\\' + char;
    return '\\' + char.charCodeAt(0).toString().padStart(3, '0');
  }) + '"';
}

function lua(value) {
  if (typeof value === 'string') return quote(value);
  if (Array.isArray(value)) return '{' + value.map(lua).join(', ') + '}';
  return String(value);
}

function generate(records) {
  if (!Array.isArray(records)) throw new Error('Input must be a JSON array.');
  const seen = new Set(), accepted = [], rejected = [];
  let duplicates = 0;
  records.forEach((record, index) => {
    const reason = validate(record);
    if (reason) { rejected.push({ index, reason }); return; }
    if (seen.has(record.key)) { duplicates++; rejected.push({ index, reason: 'duplicate key' }); return; }
    seen.add(record.key);
    accepted.push(record);
  });
  const lines = ['local _, M = ...', '-- Generated from a permitted, reviewed dataset; maps are validated again in-game.'];
  for (const record of accepted) {
    lines.push('table.insert(M.data.entries, {');
    for (const field of fields) {
      if (record[field] !== undefined) lines.push(`    ${field} = ${lua(record[field])},`);
    }
    lines.push('})');
  }
  return { text: lines.join('\n') + '\n', accepted: accepted.length, duplicates, rejected };
}

if (require.main === module) {
  const [, , input, output] = process.argv;
  if (!input || !output) {
    console.error('Usage: node tools\\import-data.cjs input.json output.lua');
    process.exitCode = 1;
  } else {
    try {
      const result = generate(JSON.parse(fs.readFileSync(input, 'utf8')));
      console.log(JSON.stringify({ accepted: result.accepted, duplicates: result.duplicates, rejected: result.rejected }, null, 2));
      if (result.rejected.length) {
        console.error('Import rejected. No output written; correct every rejected record first.');
        process.exitCode = 1;
      } else {
        fs.writeFileSync(output, result.text, { flag: 'wx' });
      }
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}

module.exports = { generate, validate, quote };
