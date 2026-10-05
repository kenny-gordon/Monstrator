# DBC2CSV workflow for Forever

## What is ready

The selected tool is **Marlamin/DBC2CSV**, not an unrelated converter with the
same name. Official Windows release **v1.0.10** is installed outside the addon:

```text
C:\Users\Admin\.copilot\session-state\e20b46ab-172d-4af2-80a7-632297fc0077\files\dbc2csv\v1.0.10\DBC2CSV.exe
```

The executable starts successfully using the installed .NET 8 runtime.
Its bundled Creature definition did not list the user's client build, so
`definitions\Creature.dbd` was updated from current WoWDBDefs. The original
bundled definition is retained as `Creature.bundled.dbd` outside the definitions
directory. The updated definition explicitly lists **1.60.1.70205**.

Sources:

- [DBC2CSV repository and requirements](https://github.com/Marlamin/DBC2CSV)
- [Official v1.0.10 release](https://github.com/Marlamin/DBC2CSV/releases/tag/v1.0.10)
- [Creature layout definitions](https://github.com/wowdev/WoWDBDefs/blob/master/definitions/Creature.dbd)

## Verified local extraction (5 October 2026)

Read-only extraction from the installed **1.60.1.70205 / wow_classic_beta**
client produced these tables and successfully converted them with DBC2CSV:

| Table | CSV records | Use |
| --- | ---: | --- |
| UiMap | 60 | UI map IDs, names and hierarchy |
| UiMapAssignment | 61 | Map/area relationships and world-space regions |
| TaxiNodes | 100 | Named taxi-node metadata and world-space positions |
| AreaPOI | 372 | Named map-POI metadata; not all are unconditional/static |
| AreaPOIState | 20 | POI state metadata |
| CreatureType | 13 | Creature-type names, not NPC identities |
| CreatureFamily | 27 | Creature-family metadata |
| Faction | 253 | Faction metadata |
| FactionTemplate | 453 | Faction-template relationships |
| TaxiPath | 328 | Client taxi-path metadata, not recommended player routes |
| TaxiPathNode | 10,778 | Flight-path vertices, not NPC placements |
| GameObjects | 1,520 | Named objects and world-space positions; mostly signs/scenery |
| AreaTrigger | 344 | Trigger positions/volumes, not verified entrance destinations |
| AreaTriggerActionSet | 243 | Trigger action-set IDs/flags, not destination mappings |
| AreaTriggerSphere | 8 | Trigger shape radii |
| SkillLine | 154 | Skill names/metadata, not trainer locations |
| SkillLineCategory | 9 | Skill category names |
| UiMapArt | 144 | Map-art references |
| UiMapArtStyleLayer | 6 | Map-art layer dimensions |
| GossipNPCOptionDisplayInfo | 50 | Option icons/flags, not NPC identities or placements |
| QuestPOIBlob | 54 | Quest objective/map relationships |
| QuestPOIPoint | 99 | Quest objective world positions, not NPC spawn points |
| AreaGroupMember | 666 | Area-group membership |
| BattlemasterList | 10 | Battleground metadata, not battlemaster NPC locations |
| BattlemasterListXMap | 11 | Battleground/world-map relationships |
| QuestLine | 3 | Quest-line names |
| QuestInfo | 7 | Quest types |
| QuestSort | 39 | Quest categories |
| AreaTriggerCreateProperties | 14 | Trigger creation metadata |
| GameObjectLabel | 1 | Object-label relationship |
| UiMapPinInfo | 4 | Map-pin display metadata |

Files are outside the addon in:

```text
C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\extracted\DBFilesClient
C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\csv
```

All 31 CSV outputs are nonempty, have consistent row shapes and unique IDs.
The temporary folder contains `dataset-inventory.json` with columns, record
counts, file sizes and SHA256 hashes, plus
an extraction report and logs. Keep a copy if needed: Windows may clean temporary
storage. Only the object candidates described below are integrated; no extracted
record is automatically treated as a confirmed NPC spawn.

The extractor is wowdev/TACTSharp **0.2.0-alpha1**, built outside WoW from commit
`c12f9fa3c4ceeb619b0453947cee86fccad6774a`. Three local reader changes allow
shared read-only archive access, disable game-data CDN fallback, and explicitly
reject encrypted BLTE chunks. A public community listfile supplies filename/ID
lookups; the successful table bytes came from local archives. No account files,
hotfix caches or game-process memory were read.

**Creature, Map and AreaTable could not be exported** because they encountered
encrypted BLTE content. No decryption or bypass was attempted; no partial table
was accepted. Creature conversion therefore remains unverified. The temporary
source-built extractor is not the unchanged official release executable.

WorldMapOverlay extracted but has no matching layout even after updating its
definition; it is not accepted as converted data. UiMapGroupMember extracted but
the converter reports no rows. Failed conversions leave no CSV. Faction,
AreaPOI and TaxiPathNode converted after updating their definitions from current
WoWDBDefs, retaining the bundled originals outside the definitions directory.

Two additional scans targeted 22 location/travel/service tables, resulting in
11 further DB2 files and eight accepted CSVs. GameObjects and SkillLineCategory
needed updated public definitions. GameObjects contains 1,515 TypeID=5 objects
(examples indicate signs/scenery), three TypeID=48 meeting stones and two
TypeID=38 farms; it is not a mailbox/vendor census. No TypeID=19 mailbox rows
were present. Do not interpret names on signposts as the signposted destination.

LFGDungeons, CreatureDifficulty, DungeonEncounter and GameObjectDisplayInfo
encountered encrypted content and were not exported. WorldSafeLocs (both
requested DB2 and legacy DBC IDs), DungeonMap, DungeonMapChunk and
WorldMapTransforms were absent from the selected root. TaxiPathNodeProperty
and TaxiNodeCondition were not found in the filename list. UiMapLink,
AreaTriggerBox and AreaTriggerCylinder extracted but conversion reported no
rows; no CSV was accepted. Total retained: 24 DB2 files, 19 converted CSVs.
These additional datasets remain outside the addon pending meaningful placement
mapping and validation; they do not increase the runtime directory count.

A further scan of 23 entrance/NPC-service/quest tables retained 17 DB2 files
and converted six nonempty tables. Current total: **41 DB2 files / 25 CSVs**.
All 99 quest points join to existing blobs and known UI maps, including Mount
Hyjal (2482). These are quest objective positions; they do not identify the
objective's NPC, provide quest names, or prove a fixed spawn.

JournalInstance, JournalInstanceEntrance, JournalInstanceQueueLoc,
JournalEncounter, JournalEncounterCreature, JournalEncounterXMapLoc,
AdventureMapPOI, AreaPOIUiWidgetSet, GossipXUIDisplayInfo, WaypointNode and
WaypointSafeLocs produced no rows. UiMapPOI and AreaGroup were absent from the
selected root. QuestV2, CreatureLabel, GossipNPCOption and CreatureXDisplayInfo
encountered encrypted content and were not exported. Repeated scans of these
same files will not recover the missing data. No new directory entries are
claimed from this scan.

The next relationship pass checked 23 previously unrequested tables and retained
18 additional DB2 files. Six more CSVs converted: QuestLine (3), QuestInfo (7),
QuestSort (39), AreaTriggerCreateProperties (14), GameObjectLabel (1), and
UiMapPinInfo (4). Current inventory supersedes earlier totals: **59 retained
DB2 files / 31 accepted CSVs**. Empty/layout-mismatched tables remain excluded.
This is a directory-related scan, not a claim to have every client/server table.

## Integrated local object candidates

`tools\object-csv.cjs` joins GameObjects, UiMap and UiMapAssignment and produces
`ExtractedObjectData.lua`. Of 1,520 objects, 663 have supported types and usable
zone assignments; 616 phased, two unsupported/unnamed and 239 unmapped objects
are excluded. Original world coordinates and source CSV hashes are retained.
The generated percentages are **candidates**, not accepted pins: runtime checks
each against the live forward transform within one yard on the same world map.
Build 1.60.1.70205 and enUS are required.

```powershell
node .\tools\object-csv.cjs `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\csv\GameObjects.csv' `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\csv\UiMap.csv' `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\csv\UiMapAssignment.csv' `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\Objects.generated.lua' `
  '1.60.1.70205'
```

World scanning now feeds checked objects into Static locations / Objects, along
with existing API markers. Signs are labeled `[Sign]`; their names do not prove
that the named destination is at the sign's position. No NPC identity, mailbox
census, trainer position or vendor inventory is inferred. Actual live accepted
counts still need an in-game scan. The single-folder payload adds startup memory;
no load-on-demand or memory-budget certification is claimed.

External websites may help confirm identities and zone coverage by hand, but
their zone references are not percent coordinates and no website dataset is
bundled or scraped.

## Implemented use of extracted metadata

`tools\client-map-csv.cjs` generates the build-gated `ClientMapCatalog.lua` from
the real UiMap CSV: 50 System=0 / Type=3 world-zone IDs, including the custom
Forever zones. It preserves the source CSV hash and refuses invalid rows,
duplicates and output overwrites. For example, generate to a new output path:

```powershell
node .\tools\client-map-csv.cjs `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\csv\UiMap.csv' `
  'C:\Users\Admin\AppData\Local\Temp\Monstrator-70205-20261005\ClientMapCatalog.generated.lua' `
  '1.60.1.70205'
```

Global world selection or `/monstrator sync world` uses these IDs to query
supported flight/POI APIs one zone per visible half-second tick. Only API-returned
map markers enter the index. The extracted taxi coordinates, POI positions and
path vertices are deliberately not treated as verified percent placements.
Live API availability and resulting marker counts still need in-game testing.

## Correct expectations

DBC2CSV **converts extracted files**. It does not open/extract CASC storage
directly, download game files, or reconstruct missing server data. The root WoW
installation has a `Data` archive directory and build metadata confirming
1.60.1.70205. Only the selected client tables and archive manifests/indexes were
read; private account/cache files were not read.

The documented converter supports **WDB5+** formats, not legacy WDBC DBC files.
An updated definition is necessary, but a newly changed binary format may also
require a newer reader.

The verified Creature layout contains ID, localized names/titles, classification,
type/family, animation/display fields and item fields. It does **not** expose
NPC spawn positions or a vendor-stock list. `creature_template` and `npc_vendor`
are typically server-database table names; do not assume they are client DB2s.
`AlwaysItem` is not a verified vendor inventory field.

Maps/UI-map definitions are useful metadata, but a legacy map/area ID is not a
UI map ID, and world-space coordinates are not 0–100 zone percentages. Do not
rename columns and treat the result as validated addon coordinates. Spawn
placement evidence must come from an actual permitted dataset, supported live
client map APIs, or reviewed observations.

Use public, accessible files and respect applicable terms/rights. Established
community practice is not blanket permission to extract or redistribute every
asset, access protected/encrypted content, or copy another site's database.
No bypass, process inspection, asset redistribution, or cache/hotfix harvesting
is included in this workflow.

## 1. Supply an extracted table

Use a suitable CASC export tool to extract `Creature.db2` for the actual client
build to a working folder you choose, subject to applicable permissions.
Do not mix builds or hotfix caches. Do not rename unrelated binary files to
`Creature.db2`; the converter looks up the definition by table name.

The extraction above used TACTTool separately from DBC2CSV. It does not imply
that an unavailable or encrypted table can be exported.

## 2. Convert without overwriting the input or existing output

From the addon folder, replace the example input/output paths with actual paths:

```powershell
.\tools\convert-db2.ps1 `
  -Converter 'C:\Users\Admin\.copilot\session-state\e20b46ab-172d-4af2-80a7-632297fc0077\files\dbc2csv\v1.0.10\DBC2CSV.exe' `
  -InputFile 'C:\MonstratorWork\extracted\Creature.db2' `
  -OutputDirectory 'C:\MonstratorWork\csv-build-70205'
```

The wrapper checks the header and definition, stages a copy, refuses existing
outputs, and validates CSV existence/nonempty output and converter failure
messages. DBC2CSV may print a conversion failure and still exit zero, so exit
code alone is not enough. The original input is untouched; the staged copy is
removed after execution. Failed partial CSV output is removed. No `.bin`
hotfix cache is supplied implicitly.

Definition selection is driven by the table format/layout and the reader.
This converter does not provide a verified `--build` switch; do not invent one.

## 3. Creature metadata is not a spawn source

`Creature` is encrypted in this client and Monstrator does not decrypt it. Even
where Creature rows are readable, names and titles do not supply coordinates,
so they are never turned into directory entries. NPC placements come from the
built-in Monstrator database (`Data\Native`) and from reviewed in-game
discoveries harvested with `tools\monstrator-db.cjs harvest`. Shared CSV parsing
for the remaining tools lives in `tools\csv.cjs`.

## 4. Generate actual directory records only with verified placements

The existing [schema](DATA_SCHEMA.md) and `tools\import-data.cjs` require stable
spawn keys, UI map IDs, verified percent coordinates, category/tags,
edition/build/locale and permission provenance. One NPC can have multiple
placements; a metadata list must not collapse them.

Client-provided flight/landmark records load separately at runtime through
`ClientData.lua`. Local NPC capture stays pending until reviewed. These sources
provide positions that Creature metadata alone cannot supply.
