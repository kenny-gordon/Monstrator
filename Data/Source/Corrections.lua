-- Hand-maintained corrections to the Monstrator database, applied by
--   node tools\monstrator-db.cjs overlay
-- Keys are entity IDs. Fields use the native layout (see DATA_SCHEMA.md). Examples:
--
--   Npc = {
--     [265810] = { name = "Kaga Wildhoof", subName = "Stable Master", npcFlags = 4194304,
--                  spawns = { [1412] = { { 47.5, 58.6 } } } },     -- add a Forever-only NPC
--     [3310]   = { addSpawns = { [1454] = { { 54.1, 68.2 } } } },  -- add a spawn point
--     [1234]   = false,                                            -- remove a wrong entity
--   },
--   Object = { [143981] = { spawns = { [1454] = { { 53.0, 66.4 } } } } },
return {
  Npc = {},
  Object = {},
  Item = {},
  Quest = {},
}
