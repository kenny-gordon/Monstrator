const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { parseCSV } = require('./csv.cjs');
const { generate: generateCatalog } = require('./client-map-csv.cjs');
const { generate: generateObjects } = require('./object-csv.cjs');

function readBuildInfo(file) {
  const lines = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/);
  const headers = lines.shift()?.split('|');
  if (!headers || !headers.includes('Version!STRING:0') || !headers.includes('Product!STRING:0')
      || !headers.includes('Active!DEC:1')) {
    throw new Error('Unsupported .build.info header; expected Version, Product, and Active columns.');
  }
  const index = {
    active: headers.indexOf('Active!DEC:1'),
    version: headers.indexOf('Version!STRING:0'),
    product: headers.indexOf('Product!STRING:0'),
  };
  const rows = lines.map(line => line.split('|')).filter(row => row.length === headers.length
    && row[index.active] === '1' && row[index.product] === 'wow_classic_beta');
  if (rows.length !== 1 || !/^1\.60\.\d+\.\d+$/.test(rows[0][index.version])) {
    throw new Error('Expected exactly one active Forever beta build in .build.info.');
  }
  return { version: rows[0][index.version], product: rows[0][index.product] };
}

function sha256(text) {
  return crypto.createHash('sha256').update(text).digest('hex');
}

function createCandidates({ buildInfo, exportsDirectory, outputDirectory }) {
  const build = readBuildInfo(buildInfo);
  const inputs = {};
  for (const name of ['UiMap.csv', 'UiMapAssignment.csv', 'GameObjects.csv']) {
    const file = path.join(exportsDirectory, name);
    const text = fs.readFileSync(file, 'utf8');
    inputs[name] = { sha256: sha256(text), rows: Math.max(0, parseCSV(text).length - 1) };
  }

  const catalog = generateCatalog(fs.readFileSync(path.join(exportsDirectory, 'UiMap.csv'), 'utf8'), build.version);
  const objects = generateObjects(
    fs.readFileSync(path.join(exportsDirectory, 'GameObjects.csv'), 'utf8'),
    fs.readFileSync(path.join(exportsDirectory, 'UiMap.csv'), 'utf8'),
    fs.readFileSync(path.join(exportsDirectory, 'UiMapAssignment.csv'), 'utf8'),
    build.version,
  );
  if (!objects.records.length) throw new Error('No mappable object candidates; output was not created.');

  const shippedFiles = {
    'ClientMapCatalog.lua': path.join(__dirname, '..', 'ClientMapCatalog.lua'),
    'ExtractedObjectData.lua': path.join(__dirname, '..', 'ExtractedObjectData.lua'),
  };
  const comparisons = Object.fromEntries(Object.entries(shippedFiles).map(([name, file]) => {
    const shippedSHA256 = sha256(fs.readFileSync(file, 'utf8'));
    const candidateText = name === 'ClientMapCatalog.lua' ? catalog.text : objects.text;
    const candidateSHA256 = sha256(candidateText);
    return [name, { shippedSHA256, candidateSHA256, changed: shippedSHA256 !== candidateSHA256 }];
  }));
  const output = path.resolve(outputDirectory);
  if (fs.existsSync(output)) throw new Error('Candidate output directory already exists; nothing was overwritten.');
  fs.mkdirSync(output, { recursive: false });
  try {
    fs.writeFileSync(path.join(output, 'ClientMapCatalog.lua'), catalog.text, { flag: 'wx' });
    fs.writeFileSync(path.join(output, 'ExtractedObjectData.lua'), objects.text, { flag: 'wx' });
    const manifest = {
      schemaVersion: 1,
      status: 'candidate-review-required',
      automaticPromotion: false,
      client: build,
      inputs,
      comparisons,
      candidates: {
        zoneMaps: catalog.maps.length,
        objects: objects.records.length,
        skippedObjects: objects.skipped,
      },
    };
    fs.writeFileSync(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
    return manifest;
  } catch (error) {
    for (const name of ['ClientMapCatalog.lua', 'ExtractedObjectData.lua', 'manifest.json']) {
      const file = path.join(output, name);
      if (fs.existsSync(file)) fs.unlinkSync(file);
    }
    fs.rmdirSync(output);
    throw error;
  }
}

if (require.main === module) {
  try {
    const [, , buildInfo, exportsDirectory, outputDirectory] = process.argv;
    if (!outputDirectory) {
      throw new Error('Usage: node tools\\client-candidates.cjs <.build.info> <CSV exports directory> <new candidate directory>');
    }
    const manifest = createCandidates({ buildInfo, exportsDirectory, outputDirectory });
    console.log(JSON.stringify(manifest, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = { createCandidates, readBuildInfo };
