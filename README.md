# Monstrator

By Metalbullz. A Forever navigation directory and local-only discovery journal.

## Status and installation

Keep this folder under the client's `Interface\AddOns\Monstrator`, enable it in
the addon list, and open it with `/monstrator` or the minimap map icon.
Right-click the icon for Favorites; drag it to reposition.

Monstrator is **self-contained**: it needs no other addon at runtime. TomTom is
optional (used for the arrow when installed; otherwise the built-in map pin is
used). The TOC uses **16001**, confirmed by a user-run diagnostic on Forever
**1.60.1, build 70205**. Run `/monstrator diagnostic` after client updates; a
differing interface is reported explicitly.

All listed Lua files load at login; separating data into a Lua file does **not**
make it load-on-demand. The addon does not scan game archives, account files or
process memory.

### Localization

The UI ships in **10 locales**: enUS, deDE, frFR, esES/esMX, ptBR, itIT, ruRU,
koKR, zhCN and zhTW (`Locales\`). Missing strings fall back to English. NPC,
item and zone names come from the database and the client and stay in English
where the source is English; search keywords (food, flight, repair...) are
English aliases.

## Native Forever database (built in)

Monstrator reads only its own database format in `Data\Native`; no other addon
is needed at runtime. The full build carries **10,121 NPCs (59,768 spawn
points), 6,586 objects (48,746 spawn points), 14,899 items and 4,256 quests**,
about 3.7 MB on disk. `Data\Native\manifest.json` records where imported rows
came from, their counts and a SHA-256 hash for every file. A **standalone**
build (see *Release builds* below) carries only Monstrator's own data and works
the same way, with a smaller directory that grows as you collect.

- **Compact and lazy.** Each entity is one tab-separated string. `NativeDB.lua`
  decodes a row only when the UI asks for it and keeps decoded rows in a weak
  cache. Spawns are stored by UiMap ID, so no zone translation is needed at
  runtime. The zone index reads only map IDs in 2,000-NPC background slices.
- **Contents.** NPC titles (`<Alchemy Supplies>`), levels, faction and service
  flags (vendor, repair, trainer, flight master, innkeeper, banker, auctioneer,
  stable master, quest giver). Items record who sells, drops, contains or
  rewards them. Quests record their start and end NPCs and objects. Objects are
  classed (mailbox, herb, ore, chest, anvil, forge, cooking fire, fishing pool,
  meeting stone, quest object) so they appear under **Static locations**.
- **Overlay.** `Data\Native\Overlay.lua` applies Monstrator's own data on top of
  the import: hand-reviewed fixes from `Data\Source\Corrections.lua` and
  confirmed Forever sightings from `Data\Source\Discoveries.lua`. Overlay
  records can add, correct or delete entities and are labeled **Forever
  discovery** in the Details pane.
- **Labels.** Database records show **Monstrator DB** on result rows, waypoints
  and the Details pane, and stay in the *Database records* evidence tier;
  confirmed journal placements always rank above them.
- `/monstrator diagnostic` reports database version, index state and counts.
  `/monstrator audit` compares your journal with the database (new NPCs, moved
  spawns, new services) so you can see what is worth harvesting.

### Data origin and credits

Monstrator's own data: the code, UI, locales, tools, `Data\Source\Corrections.lua`
(hand-reviewed fixes), `Data\Source\Discoveries.lua` (confirmed in-game
sightings and exact NPC scan sightings) and the overlay built from them.
`ClientData.lua` / `ExtractedObjectData.lua` are generated from your game client
with DBC2CSV.

Imported data: a full build may contain base tables converted by an importer.
Their origin, version, credits and licence status are recorded automatically in
every generated data file header, in `Data\Native\manifest.json`, in
`/monstrator diagnostic` and on every record's provenance, and each release zip
gets a generated `CREDITS.md` that matches exactly what it ships. Imported rows
are credited, never relicensed; the standalone build contains none.

### Database toolchain

`tools\monstrator-db.cjs` is Monstrator's own build pipeline. It needs Node and
the fengari Lua runtime (`npm install fengari`, or set `MONSTRATOR_LUA_RUNTIME`).

| Command | Purpose |
|---|---|
| `import [--from <importer>] [source dir]` | Run an importer from `tools\importers` into `Data\Native` with a field-by-field parity check |
| `harvest [SavedVariables] [--include-pending]` | Fold confirmed sightings and exact NPC scan (vignette) sightings into `Data\Source\Discoveries.lua` |
| `overlay` | Build `Data\Native\Overlay.lua` from Discoveries + Corrections |
| `verify [--determinism [importer args]]` | Schema, cross-references and manifest hashes; `--determinism` re-imports (forwarding any source folder/flavor args) and compares bytes |
| `diff <other Data\Native>` | Added/removed/changed IDs per kind |
| `stats` | Database summary |
| `package [--standalone]` | Release zip with a generated `CREDITS.md`; `--standalone` ships no imported data (see below) |
| `build [import args]` | `import` + `overlay` + `verify` |

```powershell
$env:MONSTRATOR_LUA_RUNTIME = 'C:\Temp\MonstratorTests\node_modules\fengari'
node .\tools\monstrator-db.cjs build --from <importer> <source folder>
```

Importers live in `tools\importers\<name>.cjs` and only read an installed copy
of the source; adding a new source means adding one file there. Every importer
must decode each written entity through the real `NativeDB.lua` and compares every field, ID list and spawn point with
the source; any mismatch fails the build. The current full build checks 35,862
entities with 0 problems; coordinates are written losslessly, and only 82
nameless IDs that the UI cannot show are skipped. Re-importing the same source
is byte-identical (`verify --determinism`).

Pinned coordinates for Mulgore, Eastern Plaguelands, Redridge Mountains and
Stormwind City are converted with Forever's map rescales, because Forever
resized those maps.

### Release builds

| Build | Command | Contents |
|---|---|---|
| Full | `package` | Imported base tables + Monstrator overlay; `CREDITS.md` names the import source, its credits and licence status |
| Standalone | `package --standalone` | No imported data: the base tables are empty stubs and the overlay is rebuilt from Monstrator's own sources only (no merged imported fields or spawns) |

`verify` accepts both states: without imported data it checks the overlay only.
Without an imported base, the directory, NPC scan, waypoints, favorites and the
journal audit all work from your own data; item lookup needs imported item data
and says so.


## Directory and journal

The window follows a directory layout: a **Browse** column on the left (Zone / Region / World scope with a zone picker, Directory / Favorites / Review journal lists, entry type and
category with counts), a wide **Results** list in the middle (name with
`<title>`, right-aligned colour-coded distance, zone/coordinates/evidence line
and a coloured evidence badge), and a **Details** column on the right that
follows the selection with Navigate / Favorite / full-details actions.

### Zones and regions

The Browse column has three scopes: **Zone**, **Region** (the continent) and **World**.
The button under them shows the current target (for example `Zone: Mulgore  >`) and
opens the **zone picker** over the results list. The picker lists every zone with data,
grouped under its continent (Eastern Kingdoms, Kalimdor, and Other regions for maps
without a continent). Each zone shows a count of distinct NPCs or locations for the
current entry type, evidence filter and faction. Type in the picker to filter zones or
continents; Enter picks the first matching zone.

- Click a zone to browse it from anywhere; distances show as Different zone until you
  are there.
- Click a continent heading to browse that whole region.
- **Follow my position** returns to tracking your current zone.
- The Zone button returns to the last picked zone; the Region button defaults to your
  current continent.
- `/monstrator zone NAME` and `/monstrator region NAME` jump to a zone or continent
  by full or partial name; with no name they return to following you.
- In the picker, Enter picks the first zone whose name matches the filter, or the
  matching continent when no zone name matches (type `kalim` to browse Kalimdor).
- The Details column has **Browse this zone**, which pins the selected entry's zone
  (or, when you are already browsing that zone, switches to its continent).
- The chosen scope, pinned zone/continent and window position are remembered across
  sessions. `/monstrator reset` (or **Reset window & filters** in Settings) restores
  the defaults.

The results heading shows `place / type / category`. Row tooltips and the Details
column show the zone, continent, coordinates, distance and a `/way` command you can
paste into TomTom.

Choose a scope, NPCs/Static locations, then a category.
The first opening now defaults to **All entries**, combining reviewed NPCs and
client map locations rather than hiding locations behind an empty NPC filter.
Type and category buttons show counts for the current scope/search/faction,
before applying the selected type/category. The directory still defaults to
Current zone; Global world broadens coverage.
Search supports partial names, multiple terms (AND), canonical tags and aliases
such as food/innkeeper, category names and live zone names. For example, Global
world with `riverglades flight` searches both the zone and flight tag. It
debounces by 200 ms; it is not typo correction. Favorites and journal searches
also accept zone/category names.
NPC searches additionally match **NPC IDs, creature type and rank** when captured.
The **Sort** control cycles Nearest first, Zone A-Z, Name A-Z, Level (low-high) and
NPC ID. Nearest first keeps unknown distances last and groups them by continent, then
zone. Zone A-Z orders by continent, then zone, then distance, then name. NPC-ID sorting retains separate
placement rows and sorts non-NPC locations after known NPC IDs. The **Evidence**
control filters all sources, confirmed placements, pending review, client
locations or Database records. It applies to directory, favorites and journal views, with a reminder
in empty states. Pending records still require Review/Manage journal to appear;
the directory never promotes them automatically. Sort/evidence choices persist.
**Group NPC locations** is enabled by default: one row per NPC ID, zone and
evidence state shows the nearest known source location and its location count.
Distinct placements remain indexed, and the nearest row updates as you move.
Disable grouping in Settings to inspect every location. Journal/favorite rows
are never collapsed, preserving individually editable records and saved snapshots.
Type/category counts report matching placements, not unique identities.
All matches remain scrollable using the mouse wheel; nine row frames are reused.
Favorites and journal review are independent views, not restricted by the current
directory's scope/type/category filters.

The refactored layout uses **opaque faction-tinted backgrounds**, larger readable
text, quieter selected controls and more spacious rows instead of the original
transparent yellow-text overlay. Rows expose evidence and NPC identity at a glance.
The Review action shows pending encounters only, and onboarding distinguishes
confirmed placements from confirmed NPC IDs instead of hiding journal backlog.
Help has a dedicated readable panel; copy/export dialogs are reserved for copying.

The layout groups search above three distinct inset panels: scope/type with
player position, categories, and a wider results panel. Selected filters and
views have a visible marker. Footer actions stay separate from the results,
with a row-range indicator and up/down page controls. Clear empties the search;
Help explains interactions. Empty views explain how to collect/review records.
This adapts the supplied HTML mockup's **layout only**, retaining native WoW
buttons, fonts and faction border styling rather than reproducing its web theme.

Rows now identify their zone alongside coordinates and distance. **Selected
entry details** opens a scrollable card with category, faction, tags, evidence,
source/build/locale and NPC ID when actually known, plus Navigate/Favorite actions.
Only local journal entries offer Edit journal. **Capture NPC target** adds a
pending observation; **Scan world maps** starts the visible world scan. The
coverage panel shows scan progress and cached marker/map totals (including
opposing-faction cached markers, which directory counts filter out).

- Left-click a directory/favorite row to navigate; right-click to toggle its
  favorite snapshot.
- TomTom is asked to show its arrow even with profile auto-arrow disabled.
  If it rejects a waypoint, try a supported native pin. A native pin does not
  promise a directional arrow. If both fail, a manual-copy text window appears.
  The displayed `/way` command requires TomTom; it is not a third engine.
- Distances use map-to-world transforms on the same world instance, not
  percentage-coordinate approximations or travel-route length. They update at
  most once per 0.5 seconds while open. New query matches may temporarily show
  unavailable distance until the next allowed update.
- Distance text does not depend on color. Settings include high contrast and
  independent text/frame scaling.
- Tab/Shift+Tab traverse the search and buttons; Enter activates the focused
  button or selected row. Up/Down select rows when the search field is unfocused.
  Escape closes the main frame (or clears edit focus first). Other keys propagate
  to normal gameplay. Live keyboard behavior needs verification on the client.

Collection is **off by default**. Enable it in Settings or with
`/monstrator collect`. Vendor, trainer, gossip and flight interactions record
supported NPC identity and the **player's approximate encounter coordinates**.
Restricted/unavailable identities are skipped; unavailable positions are
reported. This cannot enumerate all server NPCs or recover exact spawn points.
Manual landmark capture works even when automatic collection is off.

Review journal opens pending records. Select a record, check/correct its
coordinates and category, then explicitly confirm placement or delete it.
Only confirmed records enter the directory. User confirmation is not independent
proof of a static server spawn: do not promote patrol sightings as fixed points.
Category review does not invent service tags that were not observed.
The review dialog now lets you explicitly enter canonical service tags, such as
`innkeeper, food` or `repair`, after checking what the NPC actually provides.
Unknown tags are rejected without changing the record. `/monstrator tags` lists
the vocabulary. Settings **Manage journal** (or `/monstrator journal`) includes
confirmed entries so you can correct placement/category/tags or delete them.
Deleting a confirmed entry removes it from the directory, retaining any stale
favorite snapshot. `/monstrator capture` explicitly records your current NPC
target for review even with automatic collection off; player targets are rejected.

## Item lookup and 3D viewer

The **Items** button (or `/mon items NAME`) opens an item lookup backed by the
built-in Monstrator database. It works even when database records are hidden in Settings.
About 15,000 items are indexed in the background on first open. Search by name
(every word must match; exact and prefix matches rank first) or by item ID.
Shift-click an item to link it in chat.

For the selected item, the tabs list who **sells**, **drops**, **gathers** (objects)
or **rewards** it (quest givers), sorted by distance to the nearest spawn. Hostile
NPCs are shown in red. Left-click a source to set a TomTom or map waypoint;
right-click an NPC source to see its 3D model. **Show sources in directory**
filters the main window to every vendor and dropper of the item, and
**Clear item filter** removes the filter. In the Details pane, **Items sold/dropped**
lists everything the selected NPC sells or drops.

**3D model** (Details pane, or `/mon model`) opens a viewer for the selected NPC:
drag to rotate, use the mouse wheel to zoom, or turn on auto-rotate. NPCs the
client has not cached are requested from the server and retried for a few
seconds; if the server never sends one, the viewer says so instead of showing an
empty stage. **3D preview** in the item window tries wearable items on your
character; rings, trinkets and items without a model (food, reagents) show their icon.

## NPC scan

**NPC scan** (footer button, or `/mon scan`) alerts you when a watched NPC
appears on a nameplate, as your target or mouseover, or as a minimap marker
(vignette). With **Rare alerts** on, every rare, rare elite and world boss alerts
too. An alert plays the raid-warning sound (optional), posts a raid-warning
message and a chat line, flashes the client icon and opens a popup with:

- **Target**: targets the NPC with `/targetexact`. This is a secure button, so
  it updates after combat ends if the alert arrives mid-fight.
- **Waypoint**: sets a waypoint where the NPC was seen. Vignettes give its
  exact position; otherwise your position at the time is used.
- **3D model**.

Each NPC alerts at most once every five minutes. Dead NPCs and players are ignored.

Add NPCs to the watch list in any of these ways:

- **Watch for this NPC** in the Details pane.
- An NPC ID or exact name in the scan window.
- **Watch target**.
- `/mon scan add ID|NAME`.

A name that exists in the database is resolved to its NPC IDs. A name the
database does not know is watched by name, which covers custom Forever NPCs.
The last 50 sightings are kept under **Recent sightings**; click one to navigate
back to it. Everything is saved in `Monstrator_Settings` (`scanWatch`,
`scanWatchNames`, `scanLog`). Sightings with an exact vignette position are
first-party spawn data: `tools\monstrator-db.cjs harvest` folds them into
`Data\Source\Discoveries.lua`, so rares found in game end up in the database.

## Building the NPC catalog

**NPC discovery** in Settings, or `/monstrator discover`, separately enables
target/mouseover collection. It is off by default, independently of service
interaction collection. Select/hover NPCs while exploring to collect actual
client NPC identities, level, creature type, rank and reaction when available.
Players and restricted identities are excluded. Discovery does not scan process
memory, enumerate unseen server NPCs, or record player identities.

Positions remain the player's **encounter location**, never inferred exact NPC
coordinates. Review is mandatory before navigation-directory promotion.
Repeated target/mouseover events for the same NPC GUID are throttled in a
30-second transient window; the GUID itself is not saved or exported. Matching
nearby pending observations merge sightings/metadata. A later vendor/trainer/
flight interaction can enrich a Combat discovery instead of duplicating it.
Distinct locations remain distinct placement records.

**NPC inventory** in the footer, or `/monstrator npcs`, displays an alphabetized
summary grouped by NPC ID, with confirmed/pending counts and observed zones.
It includes all saved/indexed NPC sources, irrespective of the current browse
filters; it does not invent missing NPCs. Search an ID in Manage journal to review
all its encounters, or in the directory to navigate confirmed placements.
Optional captured metadata is included in local journal exports.
Inventory reports Database records separately from confirmed placements and
pending encounters. It respects the **Monstrator database** setting; previously
expanded records may remain cached until reload.

Journal capacity remains bounded (default 1,000, adjustable with
`/monstrator limit N`). Discovery cannot deliver a complete NPC corpus without
exploration. The built-in database covers most of the world but cannot know
about custom Forever content until someone sees it; harvest confirmed sightings
with `tools\monstrator-db.cjs harvest` to ship them in the overlay.
Core Creature data in the client remains encrypted and is not decrypted.

## Client-provided game data

Open **Static locations** to see the current map's flight nodes and non-timed
landmarks when the relevant APIs are supported. Settings **Load map data** or
`/monstrator sync` refreshes the layer and reports its current-map count and
unavailable providers. Diagnostic output includes provider availability.

These are labeled **Game map marker**, never NPC spawns or manually verified
static placements. Flight nodes are map locations, not invented flight-master
NPC IDs. Opposing-faction flight nodes are filtered. Timed/event POIs are excluded;
landmarks are skipped if the client cannot identify timed POIs. Map-marker
coordinates are not guaranteed to identify a specific object at that location.
Providers may project markers outside the requested zone. Normalized positions
outside 0–1 are skipped before conversion, never clamped into false edge pins.
A notice explains this once per session; `/monstrator diagnostic` reports the
skip count from the latest cached map reads. Valid boundary positions are kept.

Data is read on directory use and refreshed for the current map at most every
30 seconds while the UI is open. Unchanged data does not rebuild indexes.
Selecting **Global world** queues a scan of **50 world-zone maps** from the
locally extracted UiMap table for build **1.60.1.70205**. It queries one map per
0.5-second visible UI tick, using the same supported live providers; closing the
window pauses the scan. The catalog is rejected on other builds. Empty or
unavailable maps do not fabricate records. `/monstrator sync world` opens Static
locations/Global world and explicitly retries the scan; normal Global selection
scans once per session. Existing cached maps retain the 30-second refresh limit.
This is not an exhaustive server database. Markers are not saved to the journal and are rediscovered each
session; favoriting a marker saves a provenance-labeled snapshot. A provider
exception is reported and pauses that provider until `/monstrator sync` retries.
Availability and actual returned records must be verified inside Forever:
the previous screenshot did not probe these newly added APIs.

**Extracted Objects:** 663 local object candidates are now bundled for build
1.60.1.70205/enUS and loaded on map queries or the world scan. Before indexing,
each candidate's generated map position must round-trip through the live
map-to-world API within one yard on the same world map. Unsupported APIs,
different builds/locales and mismatches exclude the entries; diagnostics report
accepted/rejected counts. No live accepted-count claim is made yet.
Choose Static locations → **Objects**, or All entries, to browse accepted entries.
Signs carry `[Sign]` in their names: navigation locates the sign, not the place
written on it. Entries are labeled **Extracted client object**, never NPC
placements. Phased objects and unsupported types are not included.

The object payload adds startup memory in this single-folder package; it is not
load-on-demand and the 150 KB target remains uncertified. The generated source
is reproducible with `tools\object-csv.cjs`, using the three local CSVs documented
in [DBC2CSV.md](DBC2CSV.md). Local extraction is not a redistribution license.

Additional extracted taxi/POI/faction metadata is retained outside the addon;
see [DBC2CSV.md](DBC2CSV.md). Raw world-space positions, conditional/obsolete
taxi endpoints and flight paths are not imported as confirmed placements or
route recommendations.

The limit defaults to **1,000 journal entries**, including confirmed entries.
At capacity, capture of new entries pauses with a notice; nothing is evicted.
Reviewing/promoting an entry does not free its journal slot. Delete an entry,
clear the journal deliberately, or raise the limit. Close matching pending
sightings are deduplicated conservatively; ambiguous nearby spawns still need
human review.

Favorites use record IDs, not NPC IDs, and retain placement snapshots.
Removed records remain visible as stale favorites instead of redirecting to a
different spawn. Saved tables with unsupported schemas/invalid identities are
preserved and disable initialization; records with invalid maps/data are
quarantined and inspectable with `/monstrator issues`. Missing SavedVariables
on first install are normal, not evidence of a cold-start bug.

## Commands

| Command | Purpose |
|---|---|
| `/monstrator` or `/mon` | Toggle directory |
| `/monstrator diagnostic` | Build/interface/API availability and total addon memory, if supported |
| `/monstrator profile` | Time queries against actual reviewed records; not a worst-case certification |
| `/monstrator discover` | Toggle target/mouseover NPC discovery |
| `/monstrator collect` | Toggle automatic local collection |
| `/monstrator zone [NAME]` | Browse a zone by (partial) name; no name follows your position |
| `/monstrator region [NAME]` | Browse a continent, e.g. `kalimdor`; no name uses your continent |
| `/monstrator items [NAME]` | Open the item lookup, optionally searching for NAME or an item ID |
| `/monstrator model` | Open the 3D model viewer for the selected NPC |
| `/monstrator scan [add ID/NAME \| remove ID/NAME \| list \| on \| off \| rares \| sound \| clear \| test]` | Open the NPC scan window, or manage the watch list, alerts and sighting log |
| `/monstrator reset` | Reset window position, scope, sort and evidence filter |
| `/monstrator sync` | Refresh current-map flight/landmark data and retry failed providers |
| `/monstrator journal` | Manage pending and confirmed journal entries |
| `/monstrator audit` | Compare journal observations with the database (new NPCs, moved spawns, new services) |
| `/monstrator npcs` | NPC inventory grouped by NPC ID |
| `/monstrator tags` | Show canonical review tags |
| `/monstrator capture` | Capture the selected NPC at your approximate encounter position |
| `/monstrator limit 1000` | Set integer journal limit, 1–100000 |
| `/monstrator landmark NAME` | Save current position as a pending named landmark |
| `/monstrator export` | Selectable Lua journal text for manual copying |
| `/monstrator issues` | Inspect quarantine reasons |
| `/monstrator debug` | Toggle additional capture diagnostics |
| `/monstrator minimap` | Toggle minimap button |
| `/monstrator clear CONFIRM` | Erase the journal, including user-confirmed placements; retain favorites |
| `/monstrator help` | Show command list |

SavedVariables are account-wide: settings, favorites and observations. No player
names/GUIDs, chat or credentials are collected, and nothing is uploaded.
Journal export contains NPC/location observations and no executable import is
provided inside WoW. Reload/logout is needed for WoW to persist changes to disk.
Back up saved data through normal client management before deleting anything;
`/reload` is not data recovery.

## Permitted external data

See [DATA_SCHEMA.md](DATA_SCHEMA.md). Public accessibility is not permission to
redistribute a website's or another project's database. Use verified edition/build/map
data and explicit rights/attribution; do not quietly substitute Classic or Retail.

An offline Node importer is supplied:

```powershell
node .\tools\import-data.cjs .\permitted-data.json .\Imported.lua
```

It reports accepted/rejected/duplicate counts, refuses any rejected input, and
never overwrites an existing output. Permission text is provenance supplied by
the contributor, **not** automatically verified legal permission. After review,
add the generated file to the TOC immediately after `Data.lua` and before
`Directory.lua`. Runtime map checks quarantine unknown maps. No populated
external dataset or reuse agreement is currently included.

For extracted DB2 tables, [DBC2CSV.md](DBC2CSV.md) describes the installed
converter and the guarded DB2-to-CSV-to-metadata workflow. Creature metadata is
not a navigable spawn dataset; neither names nor titles supply coordinates.

## Validation

The dependency-free importer uses Node. Lua behavior tests use Fengari (Lua 5.3)
with WoW mocks; they do not emulate the client or establish Lua 5.1/client
compatibility by themselves.

```powershell
# Install the test-only runtime outside the addon directory:
npm install --prefix C:\Temp\MonstratorTests --no-audit --no-fund fengari
$env:MONSTRATOR_LUA_RUNTIME = 'C:\Temp\MonstratorTests\node_modules\fengari'
node .\tests\run.cjs
```

Set `MONSTRATOR_DBC2CSV` to the installed converter executable to also exercise
the PowerShell wrapper against unsupported/truncated binary fixtures, checking
definition loading, failure reporting, original-input preservation, staged-file
cleanup and no-overwrite behavior. Those negative tests are not a successful
conversion of a real game table.

Before release, run the live diagnostic; test actual vendor/trainer/flight
capture, opt-out/cap/full-state, manual review, persistence across reload/logout
and cold start, keyboard/UI scaling, and TomTom/native/missing-provider navigation.
Test source map compatibility and near/far color boundaries at 40/100 yards.
Use representative 10,000-record synthetic fixtures outside release data to
measure cold/warm/global search, sort and allocation costs **inside WoW**.
The desktop suite verifies fixture counts/order, not the **under-50-ms** target.
The **150 KB core** target is unverified; diagnostic memory includes static
tables, journal, indexes and open UI, not an isolated core budget. Record startup
and open-UI measurements separately. The user-run build 70205 diagnostic
reported **145.7 KB total addon memory** in one snapshot; UI/journal state and
representative data size were not established, so this is not budget
certification. No new profiler API is assumed available.

Later screenshots reported **147.2 KB** before the displayed UI and **972.4 KB**
with it open. These snapshots do not isolate retained memory from garbage
awaiting normal client collection, and do not by themselves prove a leak.
Diagnostics now include UI/cache state, index state and record counts to make
comparisons more meaningful. The refresh loop skips empty results and unchanged
distance updates; rendering caches text, fonts and colors rather than resetting
them every tick. Cached frames remain allocated after closing. No forced global
garbage collection is performed, since it can stall the whole client.

The minimap button uses built-in frames rather than depending on libraries
bundled inside TomTom. Universal compatibility with minimap collectors is not
claimed. Font picker, TTS, addon communication, patrol mapping, campsites, route
planning and distribution-service integration remain deferred.
