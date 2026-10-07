const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { extract, audit, generate } = require('../tools/atlasloot.cjs');
const { readNative, evalLua } = require('../tools/monstrator-db.cjs');
const { quote } = require('../tools/import-data.cjs');

const source = `
local data = AtlasLoot.ItemDB:Add(...)
local normal = data:AddDifficulty("NORMAL")
local raid = data:AddDifficulty("40RAID")
data.Test = { items = {
  { npcID = 20, [normal] = { {1, 100}, {2, 101}, {3, "Label"}, {4, 102, [ATLASLOOT_IT_ALLIANCE] = 103} },
    [raid] = { {1, 101}, AtlasLoot:GameVersion_GE(AtlasLoot.BC_VERSION_NUM, {2, 104}) } },
  { npcID = {20, 21}, [normal] = { {1, 104} } },
  { npcID = 20, IgnoreAsSource = true, [normal] = { {1, 104} } },
  { npcID = 20, TableType = "Set", [normal] = { {1, 104} } },
  { npcID = 20, [normal] = { {1, 999} } },
  { npcID = 999, [normal] = { {1, 101} } },
  { npcID = 20, [normal] = { {1, 104, Price = "money:100"}, {2, 104, Quest = 500} } },
  { [normal] = { {1, 104} } },
} }
`;
const npcs = new Map([[20, 'Boss'], [21, 'Other Boss']]);
const items = new Map([
  [100, 'Existing\t\t\t\t\t\t\t20'],
  [101, 'New'], [102, 'Faction base'], [103, 'Faction alternate'], [104, 'Excluded'],
]);
const result = audit(extract(source), npcs, items);
assert.deepEqual(result.additions, { 101: [20], 102: [20], 103: [20] });
assert.deepEqual(result.counts, {
  relationships: 6, existing: 1, added: 3, unknownItems: 1, unknownNPCs: 1, ambiguousGroups: 1,
});
assert.throws(() => audit({ Test: { items: [{ npcID: -1 }] } }, npcs, items), /Invalid AtlasLoot NPC ID/);
assert.equal(generate({ 103: [20], 101: [20] }, 'abc'), generate({ 101: [20], 103: [20] }, 'abc'),
  'generation must be stable regardless of source table order');

const native = path.resolve(__dirname, '..', 'Data', 'Native');
const manifest = JSON.parse(fs.readFileSync(path.join(native, 'atlasloot-manifest.json'), 'utf8'));
const actual = audit(extract(fs.readFileSync(path.join(native, 'AtlasLoot-source.lua'), 'utf8')),
  readNative(native, 'Npc'), readNative(native, 'Item'));
assert.deepEqual(actual.counts, manifest.counts, 'published coverage must match the exact bundled source');
assert.equal(fs.readFileSync(path.join(native, 'LootReference.lua'), 'utf8'),
  generate(actual.additions, manifest.commit), 'shipped loot data must be reproducible byte-for-byte');
assert.equal(actual.counts.added, 884, 'the import must supply the measured missing relationships');

const root = path.resolve(__dirname, '..');
const modules = ['NativeDB.lua', ...['Npcs.lua', 'Objects.lua', 'Items.lua', 'Quests.lua', 'Overlay.lua', 'LootReference.lua']
  .map((name) => path.join('Data', 'Native', name))];
const chunks = modules.map((file) =>
  `assert(load(${quote(fs.readFileSync(path.join(root, file), 'utf8'))}))("Monstrator", M)`);
const applied = evalLua(`M = {}\n${chunks.join('\n')}
local db = assert(M:NativeProvider())
local count, items, bosses = 0, {}, {}
for itemID, text in pairs(M.native.lootReference.drops) do
  local drops = db.Item.npcDrops(itemID)
  local seen = {}
  for _, id in ipairs(drops) do assert(not seen[id], "duplicate source"); seen[id] = true end
  for id in text:gmatch("%d+") do
    id = tonumber(id)
    assert(seen[id] and db.Item.npcDropReference(itemID, id) == "AtlasLootClassic", "missing imported loot")
    count = count + 1
    items[itemID], bosses[id] = true, true
  end
end
local itemCount, bossCount = 0, 0
for _ in pairs(items) do itemCount = itemCount + 1 end
for _ in pairs(bosses) do bossCount = bossCount + 1 end
__applied = { relationships = count, items = itemCount, bosses = bossCount }
`, 'actual loot runtime', '__applied');
assert.equal(applied.relationships, actual.counts.added, 'every shipped relationship must be served by the real provider');
console.log(`AtlasLoot: ${applied.relationships} new relationships across ${applied.items} items / ${applied.bosses} NPCs.`);
