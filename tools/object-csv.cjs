const fs = require('node:fs');
const crypto = require('node:crypto');
const { parseCSV } = require('./csv.cjs');
const { quote } = require('./import-data.cjs');

function table(text, required) {
  const rows = parseCSV(text), header = rows.shift();
  if (!header || new Set(header).size !== header.length || required.some(key => !header.includes(key))) {
    throw new Error('Missing or duplicate required headers.');
  }
  const seen = new Set();
  return rows.map(row => {
    if (row.length !== header.length) throw new Error('Column count mismatch.');
    const value = Object.fromEntries(header.map((key, i) => [key, row[i]]));
    if (!/^\d+$/.test(value.ID) || !Number.isSafeInteger(Number(value.ID))
        || Number(value.ID) <= 0 || seen.has(value.ID)) throw new Error('Invalid or duplicate ID.');
    seen.add(value.ID);
    return value;
  });
}

function number(value) {
  if (!value?.trim() || !Number.isFinite(Number(value))) throw new Error('Invalid numeric coordinate/metadata.');
  return Number(value);
}

function generate(objectsText, mapsText, assignmentsText, build) {
  if (!/^1\.60\.\d+\.\d+$/.test(build)) throw new Error('Supply the full Forever build.');
  const maps = new Set(table(mapsText, ['ID', 'System', 'Type'])
    .filter(row => row.System === '0' && row.Type === '3').map(row => number(row.ID)));
  const assignments = table(assignmentsText, ['ID', 'UiMapID', 'MapID', 'Region[0]', 'Region[1]',
    'Region[2]', 'Region[3]', 'Region[4]', 'Region[5]', 'UiMin[0]', 'UiMin[1]',
    'UiMax[0]', 'UiMax[1]', 'WMODoodadPlacementID', 'WMOGroupID'])
    .filter(row => maps.has(number(row.UiMapID)) && row.WMODoodadPlacementID === '0'
      && row.WMOGroupID === '0' && row['UiMin[0]'] === '0' && row['UiMin[1]'] === '0'
      && row['UiMax[0]'] === '1' && row['UiMax[1]'] === '1')
    .map(row => {
      const region = Array.from({ length: 6 }, (_, i) => number(row[`Region[${i}]`]));
      if (region[3] <= region[0] || region[4] <= region[1] || region[5] <= region[2]) {
        throw new Error('Invalid assignment bounds.');
      }
      return { mapID: number(row.UiMapID), worldMapID: number(row.MapID), region,
        area: (region[3] - region[0]) * (region[4] - region[1]) };
    });
  const records = [], skipped = { conditional: 0, unsupported: 0, unmapped: 0 };
  for (const row of table(objectsText, ['ID', 'Name_lang', 'OwnerID', 'Pos[0]', 'Pos[1]', 'Pos[2]',
    'TypeID', 'PhaseID', 'PhaseGroupID', 'PhaseUseFlags'])) {
    if (row.PhaseID !== '0' || row.PhaseGroupID !== '0' || row.PhaseUseFlags !== '0') {
      skipped.conditional++; continue;
    }
    const typeID = number(row.TypeID);
    if (![5, 38, 48].includes(typeID) || !row.Name_lang.trim() || /^zzold/i.test(row.Name_lang)) {
      skipped.unsupported++; continue;
    }
    const wx = number(row['Pos[0]']), wy = number(row['Pos[1]']), wz = number(row['Pos[2]']);
    const worldMapID = number(row.OwnerID);
    const candidates = assignments.filter(a => a.worldMapID === worldMapID
      && wx >= a.region[0] && wx <= a.region[3] && wy >= a.region[1] && wy <= a.region[4]
      && wz >= a.region[2] && wz <= a.region[5]).sort((a, b) => a.area - b.area || a.mapID - b.mapID);
    if (!candidates.length) { skipped.unmapped++; continue; }
    const a = candidates[0];
    records.push({ id: number(row.ID), name: row.Name_lang + (typeID === 5 ? ' [Sign]' : ''),
      mapID: a.mapID, worldMapID, wx, wy, typeID,
      x: (a.region[4] - wy) / (a.region[4] - a.region[1]) * 100,
      y: (a.region[3] - wx) / (a.region[3] - a.region[0]) * 100 });
  }
  const hashes = [objectsText, mapsText, assignmentsText].map(text => crypto.createHash('sha256').update(text).digest('hex'));
  const grouped = new Map();
  for (const r of records) {
    if (!grouped.has(r.mapID)) grouped.set(r.mapID, []);
    grouped.get(r.mapID).push(r);
  }
  let text = `local _, M = ...\nM.extractedObjects = { build = "${build}", locale = "enUS",\n` +
    `    hashes = { ${hashes.map(hash => `"${hash}"`).join(', ')} }, maps = {\n`;
  for (const [mapID, entries] of [...grouped].sort((a, b) => a[0] - b[0])) {
    text += `    [${mapID}] = {\n`;
    for (const r of entries) {
      const name = quote(r.name);
      text += `        { ${r.id}, ${name}, ${r.x}, ${r.y}, ${r.worldMapID}, ${r.wx}, ${r.wy}, ${r.typeID} },\n`;
    }
    text += '    },\n';
  }
  text += '} }\n';
  return { text, records, skipped };
}

if (require.main === module) {
  try {
    const [, , objects, maps, assignments, output, build] = process.argv;
    if (!output) throw new Error('Usage: node tools\\object-csv.cjs GameObjects.csv UiMap.csv UiMapAssignment.csv OUTPUT BUILD');
    const result = generate(...[objects, maps, assignments].map(file => fs.readFileSync(file, 'utf8')), build);
    if (!result.records.length) throw new Error('No mappable object candidates.');
    fs.writeFileSync(output, result.text, { flag: 'wx' });
    console.log(JSON.stringify({ candidates: result.records.length, skipped: result.skipped }));
  } catch (error) {
    console.error(error.message); process.exitCode = 1;
  }
}
module.exports = { generate };
