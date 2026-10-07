# Contributing to Monstrator

Thanks for helping. This guide covers the development setup, tests, the
database toolchain, client data, translations and the release checklist.
Data formats are described in [DATA_SCHEMA.md](DATA_SCHEMA.md).

## Project layout

| Path | Contents |
|---|---|
| `Monstrator.toc` | Load order, SavedVariables, localized notes |
| `Core.lua` | Startup, settings, slash commands, diagnostics |
| `Data.lua`, `Directory.lua` | Record validation, saved tables, indexes, search and sorting |
| `NativeDB.lua`, `NativeIndex.lua` | Lazy reader and zone index for the built-in database |
| `Collector.lua` | Journal capture, discovery and review |
| `Submission.lua` | Sealed discovery submissions |
| `Navigation.lua` | TomTom and map-pin waypoints |
| `ClientData.lua`, `ClientMapCatalog.lua`, `ExtractedObjects.lua`, `ExtractedObjectData.lua` | Live map markers and extracted client objects |
| `UI.lua`, `ItemLookup.lua`, `Scanner.lua` | Main window, help, item lookup, 3D viewer, NPC scan |
| `Locales\` | Translations (enUS holds symbolic keys; plain-English keys fall back to themselves) |
| `Data\Native\` | Generated database files, overlay and `manifest.json` |
| `Data\Source\` | Hand-written corrections and harvested discoveries (not shipped; built into the overlay) |
| `tools\` | Database toolchain, importers and client-data generators |
| `tests\` | Test runner, WoW API mocks and behaviour tests |

## Development setup

The tools and tests need [Node.js](https://nodejs.org/) and the
[fengari](https://github.com/fengari-lua/fengari) Lua runtime. Install fengari
outside the addon folder so it is never packaged:

```powershell
npm install --prefix C:\Temp\MonstratorTests --no-audit --no-fund fengari
$env:MONSTRATOR_LUA_RUNTIME = 'C:\Temp\MonstratorTests\node_modules\fengari'
```

## Tests

```powershell
node .\tests\run.cjs
```

The suite runs the addon's Lua against WoW API mocks (`tests\mock.lua`) and
checks the database codec, overlay, standalone build, importers, submissions,
the toolchain and every locale. Fengari is Lua 5.3, so the tests do not prove
Lua 5.1 or client compatibility on their own; check changes in game too.

Set `MONSTRATOR_DBC2CSV` to a DBC2CSV executable to also run the negative tests
for `tools\convert-db2.ps1`.

## Database toolchain

`tools\monstrator-db.cjs` builds, checks and packages the database. Run it with
`--help` for usage.

| Command | Purpose |
|---|---|
| `import [--from <importer>] [dir] [flavor]` | Convert an installed source with `tools\importers\<importer>.cjs` into `Data\Native`, checking every field through the real `NativeDB.lua`. Without a folder the importer looks for the source addon next to Monstrator |
| `harvest [SavedVariables] [--include-pending]` | Fold confirmed journal entries and exact NPC scan sightings into `Data\Source\Discoveries.lua`; tampered records are rejected |
| `review <file\|folder>... [--apply] [--min-reporters N] [--accept-held]` | Check pasted player submissions; `--apply` merges accepted records into Discoveries |
| `overlay` | Build `Data\Native\Overlay.lua` from Discoveries and Corrections |
| `verify [--determinism [importer args]]` | Schema, references, coordinates and manifest hashes; `--determinism` re-imports and compares bytes |
| `diff <other Data\Native>` | Added, removed and changed IDs per kind |
| `stats` | Database summary |
| `package [--standalone]` | Build `dist\Monstrator-<version>[-standalone].zip` with a generated `CREDITS.md` |
| `build [import args]` | `import`, then `overlay`, then `verify` |

Rules for imported data:

- Importers only read a copy of the source that is already installed; they never
  download or scrape.
- Each importer records the source name, version, commit, credits and licence
  status. These go into every generated file header, `manifest.json`, the
  diagnostic output and the release `CREDITS.md`. Imported data is credited,
  never relicensed.
- Re-importing the same source must be byte-identical (`verify --determinism`).
- Maps that Forever resized (Mulgore, Eastern Plaguelands, Redridge Mountains,
  Stormwind City) are converted with Forever's rescales.

### Corrections and discoveries

- Hand-reviewed fixes go in `Data\Source\Corrections.lua` (see the examples there).
- Player discoveries come from `harvest` (your own SavedVariables) or `review`
  (submission issues). Then run `overlay` and `verify`.

### Reviewing submissions

Save each pasted block from a **Discovery submission** issue to a text file, then:

```powershell
node .\tools\monstrator-db.cjs review .\submissions            # dry-run report
node .\tools\monstrator-db.cjs review .\submissions --apply    # merge accepted records
node .\tools\monstrator-db.cjs overlay
node .\tools\monstrator-db.cjs verify
```

Held records (new NPCs with one reporter, edited, unsealed or location records)
need a manual check before `--accept-held`. Commit `Data\Source\Discoveries.lua`,
`Data\Source\SubmissionLedger.json` and the rebuilt overlay together.

### Other tools

| Tool | Purpose |
|---|---|
| `tools\import-data.cjs input.json output.lua` | Validate a permitted curated dataset (see DATA_SCHEMA.md); refuses rejected input and never overwrites output |
| `tools\client-map-csv.cjs UiMap.csv out.lua BUILD` | Generate `ClientMapCatalog.lua` (world-zone UI map IDs for the world scan) |
| `tools\object-csv.cjs GameObjects.csv UiMap.csv UiMapAssignment.csv out.lua BUILD` | Generate `ExtractedObjectData.lua` |
| `tools\convert-db2.ps1 -Converter <DBC2CSV.exe> -InputFile <table.db2> -OutputDirectory <dir>` | Safely convert one extracted DB2 table to CSV |

## Client data

`ClientMapCatalog.lua` and `ExtractedObjectData.lua` are generated from tables
extracted from the Forever client (build 1.60.1.70205) and converted with
[DBC2CSV](https://github.com/Marlamin/DBC2CSV) using current
[WoWDBDefs](https://github.com/wowdev/WoWDBDefs) definitions.

1. Extract `UiMap`, `UiMapAssignment` and `GameObjects` from your own client
   installation with a CASC tool, without mixing builds or hotfix caches.
2. Convert each table:
   `.\tools\convert-db2.ps1 -Converter <DBC2CSV.exe> -InputFile <table.db2> -OutputDirectory <csv folder>`.
   The wrapper stages a copy, refuses to overwrite, and treats empty output or a
   reported conversion failure as an error (DBC2CSV can exit 0 on failure).
3. Generate the Lua files with `client-map-csv.cjs` and `object-csv.cjs` into a
   new path, compare, then replace the shipped files.

Notes:

- Generated data is tied to its client build and locale; the addon ignores it on
  other builds.
- Extracted object positions are candidates. At runtime each one must match the
  live map transform within one yard or it is dropped. Phased, unsupported and
  unmapped objects are excluded by the generator.
- `Creature`, `Map` and `AreaTable` are encrypted in this client and are not
  decrypted. Creature rows hold no spawn positions anyway, so NPC placements come
  only from the database and reviewed discoveries.
- Quest POI points, taxi paths and area triggers are not NPC placements and are
  not imported as such.

## Translations

- `Locales\enUS.lua` defines symbolic keys (help text, sort labels, evidence
  names). Plain-English keys used in code need no enUS entry.
- Every other locale must translate every key, in the same order as the other
  locales, keeping format specifiers (`%s`, `%d`, `%.1f`), colour codes
  (`|cff...|r`), `\n`, leading and trailing spaces, slash commands and the
  help bullet `• `. The tests enforce all of this.
- Locale files are UTF-8 without BOM. Write them with an editor or Node's
  `fs`, never by piping text through Windows PowerShell, which silently turns
  non-ASCII characters into `?`. The tests reject any value that gains `?`.

## Coding guidelines

- Target the Forever client (interface 16001), not Classic Era FrameXML. Preserve Lua 5.1 compatibility. Guard optional APIs (`C_Map`,
  `C_Timer`, `C_VignetteInfo` and similar) with existence checks.
- No new globals besides the SavedVariables, slash commands and named frames.
- Do not touch secure frames in combat.
- User-facing text goes through `L[...]` and must be added to every locale.
- Never invent placement data: every record keeps its source and evidence level.

### Interface references

The directory uses `PortraitFrameTemplate` and `PanelTabButtonTemplate` from
[Forever's shared panel templates](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml).
Area navigation stays in the Browse sidebar and searchable area picker.
Do not recreate the removed map breadcrumb strip or depend on the map's
internal navigation data or menu implementation. Normal opening is a current-zone
landing view; explicit zone/region commands must remain exempt from that reset.
The parchment atlas is `QuestBG-Parchment`, defined in
[Forever's quest templates](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestFrameTemplates.xml).
The textured background is `Interface\FrameGeneral\UI-Background-Rock`.
These are client-owned references, not bundled assets.
Keep the selected-entry parchment separate from the dark action tray. Pack
visible actions without gaps and preserve native buttons for navigation/map
preview; secondary actions must retain keyboard focus and full-label tooltips.

NPC artwork resolves a creature display ID through the documented
`PlayerModel:SetCreature` / `GetDisplayInfo` methods, then uses
`SetPortraitTextureFromCreatureDisplayID`; live-unit portraits use
`SetPortraitTexture`. Never pass an NPC ID as a display ID. Keep appearance
lookups serialized, the session cache bounded and late callbacks guarded
against recycled rows. Unavailable appearances keep their category icon.

Design research also examined
[Journalator's tabbed display](https://github.com/TheMouseNest/Journalator)
and [AtlasLoot's visual entry controls](https://github.com/Hoizame/AtlasLootClassic).
Use these for layout ideas only; do not copy their implementation or artwork.
Validate native templates in Forever's branch rather than assuming an Era
template or a texture setter's nil behavior is compatible. In-game release
checks must cover native tabs, enlarged/localized text, parchment contrast and
the reported dark-layout fallback when the atlas is missing.
Also check portraits after scrolling, Keyboard button help, rare marking with
and without raid permissions, combat restrictions, and live world-map discovery
on a client build newer than the extracted catalog. Build/locale gates on
extracted object coordinates must remain intact.
Map previews must keep normalized coordinates correct when the world-map canvas
resizes, hide on unrelated zones, preserve existing navigation, and label
pending encounter coordinates without confirming them. Check Shift-click and
the Details map button, including combat and unsupported-map failures.

## Release checklist

1. Bump `## Version` in `Monstrator.toc` and add a `CHANGELOG.md` entry.
2. `node .\tests\run.cjs`
3. `node .\tools\monstrator-db.cjs verify`
4. `node .\tools\monstrator-db.cjs package` and `package --standalone`.
5. In game, on a clean profile and with an existing one:
   - `/monstrator diagnostic` reports matching interface and database counts.
   - Search, browse, sub-groups, sort and evidence filters.
   - Navigation with and without TomTom.
   - Item lookup, 3D viewer and NPC scan alert (`/mon scan test`).
   - Collection, review, `/monstrator submit`, persistence across `/reload`.
   - At least one non-English client for layout overflow.
6. Publish the zip(s). Only publish the full build if the imported source's terms
   allow redistribution; otherwise publish the standalone build.
