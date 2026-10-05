const fs = require('node:fs');
const crypto = require('node:crypto');
const { parseCSV } = require('./csv.cjs');

function generate(text, build) {
  if (!/^1\.60\.\d+\.\d+$/.test(build)) throw new Error('Supply the full Forever build.');
  const rows = parseCSV(text);
  const header = rows.shift();
  if (!header || new Set(header).size !== header.length) throw new Error('Missing or duplicate headers.');
  const columns = ['ID', 'System', 'Type'].map(name => {
    const index = header.indexOf(name);
    if (index < 0) throw new Error(`Missing ${name} column.`);
    return index;
  });
  const seen = new Set(), maps = [];
  for (const row of rows) {
    if (row.length !== header.length) throw new Error('Column count mismatch.');
    const values = columns.map(index => {
      if (!/^\d+$/.test(row[index])) throw new Error('Invalid numeric map metadata.');
      const value = Number(row[index]);
      if (!Number.isSafeInteger(value)) throw new Error('Invalid numeric map metadata.');
      return value;
    });
    const [id, system, type] = values;
    if (id <= 0 || seen.has(id)) throw new Error('Invalid or duplicate UI map ID.');
    seen.add(id);
    if (system === 0 && type === 3) maps.push(id);
  }
  if (!maps.length) throw new Error('No world-zone maps found.');
  maps.sort((a, b) => a - b);
  const digest = crypto.createHash('sha256').update(text).digest('hex');
  return {
    maps,
    text: `local _, M = ...\nM.clientMapCatalog = {\n` +
      `    build = "${build}", source = "local-client:UiMap", csvSHA256 = "${digest}",\n` +
      `    maps = { ${maps.join(', ')} },\n}\n`,
  };
}

if (require.main === module) {
  try {
    const [, , input, output, build] = process.argv;
    if (!input || !output) throw new Error('Usage: node tools\\client-map-csv.cjs UiMap.csv ClientMapCatalog.lua BUILD');
    const result = generate(fs.readFileSync(input, 'utf8'), build);
    fs.writeFileSync(output, result.text, { flag: 'wx' });
    console.log(`Generated ${result.maps.length} zone-map IDs. No placements were inferred.`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { generate };
