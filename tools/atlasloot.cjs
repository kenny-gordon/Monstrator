const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { evalLua, readNative, decodeRow } = require('./monstrator-db.cjs');
const { quote } = require('./import-data.cjs');

// Only the Classic dungeon/raid module is accepted; game APIs, file I/O and addon code are unavailable.
function extract(source) {
  const prelude = `
local data = {}
local function identity(_, name) return name end
data.AddDifficulty = function(_, name) return "difficulty:" .. name end
data.AddItemTableType = identity
data.AddExtraItemTableType = identity
data.AddContentType = identity
local names = setmetatable({}, { __index = function(_, key) return key end })
local env = {
  select = select, string = string, pairs = pairs, ipairs = ipairs, type = type,
  tonumber = tonumber, tostring = tostring, table = table, math = math,
  FACTION_HORDE = "Horde", FACTION_ALLIANCE = "Alliance",
  ATLASLOOT_IT_AMOUNT1 = "amount", ATLASLOOT_IT_ALLIANCE = "allianceItem", ATLASLOOT_IT_HORDE = "hordeItem",
  UnitFactionGroup = function() return "Alliance" end,
  C_Map = { GetAreaInfo = function(id) return tostring(id) end },
}
env._G = env
env.getfenv = function() return env end
env.AtlasLoot = {
  CLASSIC_VERSION_NUM = 1, BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3,
  Locales = names, IngameLocales = names,
  ItemDB = { Add = function() return data end },
  ReturnForGameVersion = function(classic) return classic end,
  GameVersion_GE = function(_, version, yes, no) if 1 >= version then return yes else return no end end,
  GameVersion_LT = function(_, version, yes, no) if 1 < version then return yes else return no end end,
}
local chunk = assert(load(${quote(source)}, "AtlasLootClassic data.lua", "t", env))
local instructions = 0
debug.sethook(function()
  instructions = instructions + 10000
  if instructions > 10000000 then error("AtlasLoot import exceeded instruction limit") end
end, "", 10000)
chunk("AtlasLootClassic_DungeonsAndRaids")
debug.sethook()
local result = {}
for key, instance in pairs(data) do
  if type(instance) == "table" then result[key] = instance end
end
__loot = result
`;
  return evalLua(prelude, 'AtlasLootClassic extraction', '__loot');
}

const positiveID = (id) => Number.isSafeInteger(id) && id > 0;
const values = (table) => Object.values(table || {});

function audit(data, npcs, items) {
  const additions = {}, seen = new Set();
  const counts = { relationships: 0, existing: 0, added: 0, unknownItems: 0, unknownNPCs: 0, ambiguousGroups: 0 };
  for (const instance of values(data)) {
    if (instance.IgnoreAsSource || instance.ExtraList || (instance.TableType && instance.TableType !== 'Item')) continue;
    for (const boss of values(instance.items)) {
      if (!boss || boss.IgnoreAsSource || boss.ExtraList || (boss.TableType && boss.TableType !== 'Item')) continue;
      const npcIDs = typeof boss.npcID === 'number' ? [boss.npcID] : values(boss.npcID);
      if (!npcIDs.length) continue;
      if (npcIDs.length !== 1) { counts.ambiguousGroups++; continue; }
      const npcID = npcIDs[0];
      if (!positiveID(npcID)) throw new Error('Invalid AtlasLoot NPC ID');
      for (const [difficulty, rows] of Object.entries(boss)) {
        if (!difficulty.startsWith('difficulty:')) continue;
        // Inherited difficulty lists are not needed for this union: the original list is visited separately.
        for (const row of values(rows)) {
          if (row && (row.Price || row.Quest || row.IgnoreAsSource)) continue;
          const primary = Array.isArray(row) ? row[1] : row && row['2'];
          for (const itemID of [primary, row && row.allianceItem, row && row.hordeItem]) {
            if (typeof itemID !== 'number') continue; // Labels, item sets and navigation links are not drops.
            if (!positiveID(itemID)) throw new Error('Invalid AtlasLoot item ID');
            const key = `${itemID}:${npcID}`;
            if (seen.has(key)) continue;
            seen.add(key);
            counts.relationships++;
            if (!npcs.has(npcID)) { counts.unknownNPCs++; continue; }
            if (!items.has(itemID)) { counts.unknownItems++; continue; }
            const current = decodeRow('Item', items.get(itemID)).npcDrops || [];
            if (current.includes(npcID)) { counts.existing++; continue; }
            (additions[itemID] ||= []).push(npcID);
            counts.added++;
          }
        }
      }
    }
  }
  for (const ids of values(additions)) ids.sort((a, b) => a - b);
  return { additions, counts };
}

function generate(additions, commit) {
  const lines = [
    '-- AtlasLootClassic Classic boss-loot reference; not Forever-confirmed.',
    '-- Derived data: GPL-2.0; see AtlasLoot-LICENSE.txt and atlasloot-manifest.json.',
    'local _, M = ...',
    `M.native.lootReference = { source = "AtlasLootClassic", commit = ${quote(commit)}, drops = {} }`,
    'local D = M.native.lootReference.drops',
  ];
  for (const id of Object.keys(additions).map(Number).sort((a, b) => a - b)) {
    lines.push(`D[${id}]=${quote(additions[id].join(','))}`);
  }
  return lines.join('\n') + '\n';
}

function main(args) {
  const [file, commit, mode] = args;
  if (!file || !/^[a-f0-9]{40}$/.test(commit || '') || (mode && mode !== '--apply')) {
    throw new Error('Usage: node tools\\atlasloot.cjs <Classic data.lua> <source commit SHA> [--apply]');
  }
  const root = path.resolve(__dirname, '..'), native = path.join(root, 'Data', 'Native');
  const source = fs.readFileSync(file, 'utf8');
  const result = audit(extract(source), readNative(native, 'Npc'), readNative(native, 'Item'));
  console.log(JSON.stringify(result.counts, null, 2));
  if (mode !== '--apply') return;
  const license = fs.readFileSync(path.join(path.dirname(file), 'LICENSE'), 'utf8');
  if (!license.includes('GNU GENERAL PUBLIC LICENSE') || !license.includes('Version 2, June 1991')) {
    throw new Error('The source folder must contain the original GPLv2 LICENSE');
  }
  if (!result.counts.added) throw new Error('No new loot relationships; no database files written');
  const text = generate(result.additions, commit);
  const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
  const manifest = {
    source: 'AtlasLootClassic', flavor: 'Classic reference (not Forever-confirmed)', commit,
    homepage: 'https://github.com/Hoizame/AtlasLootClassic', license: 'GPL-2.0',
    sourceFile: 'AtlasLootClassic_DungeonsAndRaids/data.lua', sourceSha256: hash(source),
    counts: result.counts, files: {
      'LootReference.lua': hash(text), 'AtlasLoot-LICENSE.txt': hash(license), 'AtlasLoot-source.lua': hash(source),
    },
  };
  fs.writeFileSync(path.join(native, 'LootReference.lua'), text);
  fs.writeFileSync(path.join(native, 'AtlasLoot-LICENSE.txt'), license);
  fs.writeFileSync(path.join(native, 'AtlasLoot-source.lua'), source);
  fs.writeFileSync(path.join(native, 'atlasloot-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
}

module.exports = { extract, audit, generate };
if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) { console.error('error: ' + error.message); process.exitCode = 1; }
}
