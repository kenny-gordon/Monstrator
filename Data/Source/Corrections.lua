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
  Npc = {
    -- Warlock Infernal scales with its summoner: Wowhead Classic npc=89 "Level 50 - 60" (QuestieDB lists 50 only).
    [89] = { maxLevel = 60 },
    -- Levels where QuestieDB disagrees with both the in-game journal (harvest overlay review) and Wowhead Classic
    -- tooltips (nether.wowhead.com/classic/tooltip/npc/<id>, checked 2026-10-07). Wowhead's full range is used.
    [3078] = { minLevel = 10, maxLevel = 10 },   -- Kennah Hawkseye
    [3080] = { minLevel = 13, maxLevel = 13 },   -- Harant Ironbrace
    [3221] = { minLevel = 14, maxLevel = 14 },   -- Brave Rockhorn
    [3634] = { minLevel = 15, maxLevel = 17 },   -- Deviate Stalker
    [3945] = { minLevel = 30, maxLevel = 39 },   -- Caravaneer Ruzzgot
    [4196] = { minLevel = 1, maxLevel = 50 },    -- Silithid Swarm (scales with the hatching egg/zone)
    [4388] = { minLevel = 39, maxLevel = 41 },   -- Young Murk Thresher
    [4883] = { minLevel = 43, maxLevel = 43 },   -- Krak
    [5766] = { minLevel = 4, maxLevel = 9 },     -- Savannah Cub
    [5774] = { minLevel = 1, maxLevel = 2 },     -- Riding Wolf
    [5781] = { minLevel = 20, maxLevel = 21 },   -- Silithid Creeper Egg
    [5797] = { minLevel = 25, maxLevel = 25 },   -- Aean Swiftriver
    [5814] = { minLevel = 30, maxLevel = 30 },   -- Innkeeper Thulbek
    [5953] = { minLevel = 28, maxLevel = 32 },   -- Razor Hill Grunt
    [7730] = { minLevel = 40, maxLevel = 40 },   -- Stonetalon Grunt
    [10048] = { minLevel = 30, maxLevel = 30 },  -- Gereck
    [14718] = { minLevel = 26, maxLevel = 27 },  -- Horde Laborer
  },
  Object = {},
  Item = {},
  Quest = {},
}
