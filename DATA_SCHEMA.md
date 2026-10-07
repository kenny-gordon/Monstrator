# Monstrator data and contribution contract

Static records live in the private addon namespace's `data.entries` flat array.
The array is reserved for permitted, Forever-compatible curated content.
The built-in Monstrator database is a separate lazy source, never inserted as curated data.
Runtime indexes and quarantined records are not SavedVariables.

## Record fields

| Field | Contract |
|---|---|
| `key` | Nonempty stable record/spawn string; external provider prefix recommended; `local:`, `client:` and `reference:` reserved |
| `npcID` | Positive integer for NPC records; omit for landmarks; one NPC can have multiple record keys |
| `name` | Nonempty localized display name, not a stable identifier |
| `kind` | `npc` or `location` |
| `category` | NPC: Services, Vendors, Trainers, Transit, Combat. Location: Mailboxes, Instances, Transit, Landmarks, Objects |
| `mapID` | Positive integer **UI map ID**, verified against the live Forever client; not a legacy area ID |
| `x`, `y` | Finite numbers in **0–100 percent**, converted once at API boundaries |
| `tags` | Contiguous array of canonical strings from `Data.lua`; suggest taxonomy extensions for review |
| `source` | Provider URL/attribution, or local interaction evidence |
| `permission` | Required for curated imports; established license/permission reference, not an assumed grant |
| `build`, `locale` | Strings identifying evidence's source build and language |
| `edition` | Curated imports must explicitly declare `Forever`; other editions are rejected |
| `verification` | `pending`, `user-confirmed`, `curated`, `client-map`, `client-object`, or `reference` |
| `precision` | `encounter` (player position), `confirmed` placement, `map` marker, or unverified `reference` placement |
| `faction` | Optional Alliance, Horde or Both; omitted means unrestricted |
| `lastSeen`, `sightings` | Local observation timestamp/count, not player identity |
| `level` | Optional observed integer NPC level; -1 denotes unknown/boss level |
| `creatureType`, `classification` | Optional client-provided NPC type/rank strings |
| `reaction` | Optional observed reaction to player (1–8), not a faction eligibility rule |
| `title` | Optional NPC subname/title string (e.g. `Alchemy Supplies`), shown as `<title>` and searchable |

External JSON imports require `curated`/`confirmed` records and a nonempty
permission reference. Runtime validates maps separately; an accepted offline
import does not certify that a map or spawn exists in Forever.
Builds remain provenance, not automatic cross-build verification. Contributor
review must establish compatibility before adding a dataset to the TOC.

Client map records are locations with `client:` keys/source and `client-map` /
`map` evidence. They come from capability-checked flight-node or non-timed,
non-event POI APIs, never inferred NPC IDs. They are a runtime session layer;
they do not occupy bounded journal slots or establish static server spawns.
The current map refreshes at most every 30 seconds while the directory is open;
unchanged data does not rebuild indexes. Visited-map data is not an exhaustive
world catalog and can be stale until that map is queried/refreshed again.
The extracted zone-map catalog stores only UI map IDs, its exact client build,
local source and source-CSV SHA256. It drives a paced, supported-API scan of
world-zone maps, not an offline placement import. Catalog build mismatch blocks
the scan; current-map collection remains available. No map assignment/world
coordinate conversion or NPC identity is inferred from these IDs.

Extracted objects use `client:object:MAP:ID` keys, `client:local-GameObjects`
source, `client-object` verification and `map` precision. `objectType` preserves
the supported client type (5, 38 or 48). The generator excludes phased objects,
unsupported types and out-of-zone positions, selects the smallest containing
world-zone assignment and retains original world coordinates. Runtime checks
the generated percentages against the live forward map transform within one
yard and requires the exact world map, build and locale. A failed check excludes
the record; coordinates are never clamped. Sign names are explicitly labeled;
they describe the object, not its destination or an inferred service.

## Monstrator database source

`Data\Native\LootReference.lua` is a separate supplementary Classic loot layer,
not a placement or curated-data import. It registers
`native.lootReference = { source, commit, drops }`, where each `drops[itemID]` is
a comma-separated list of NPC IDs already known to the base database. The Item
provider appends these to `npcDrops` without changing its underlying row, skipping
duplicates, deleted NPCs, unknown items and explicitly overlaid item rows.
`Item.npcDropReference(itemID, npcID)` identifies only effective supplementary
relationships. NPC item lists and item source lookup share this provider, so both
surfaces see the same enriched data. All coordinates still come from Monstrator.
`atlasloot-manifest.json` records provenance, coverage and SHA-256 hashes of the
derived data, original source and GPLv2 licence. None ship in the standalone build
(the required TOC loot module is replaced with an empty stub).

Records from the built-in database (`Data\Native`, read through `NativeDB.lua`
and indexed by `NativeIndex.lua`) are built at runtime and never persisted except
as favorite snapshots. They use these keys:

- NPC placements: `reference:monstrator:<npcID>:<mapID>:<x>,<y>`
- Object placements: `reference:monstrator:o<objectID>:<mapID>:<x>,<y>`

They carry `monstrator-db:<version>` sources, the `Forever` edition and
`reference` verification/precision, plus an optional `title` (NPC subname).
Spawns are stored by UI map ID and kept only when the live client knows the map.
Categories and tags come from `npcFlags` (and trainer subnames for class vs.
profession) or from the object class (mailbox, herb, ore, chest...). They are not
verified live spawns and cannot be silently promoted to curated or
user-confirmed records under the same key.

Native rows are tab-separated strings with a fixed field layout per kind
(`LAYOUT` in `tools\monstrator-db.cjs`). Spawns are encoded as
`mapID:x,y x,y;mapID:x,y` (points separated by spaces, maps by `;`). Each imported data file registers with
`M.NativeData(kind, version, flavor, commit, source)`; `source` names the import origin for attribution (nil for
Monstrator's own data). `Data\Native\manifest.json` records the source (name, version, commit, credits, licence status),
counts and SHA-256 of each file, and `verify` rejects any mismatch. A standalone build has no manifest and empty
base files; `verify` then checks the overlay only.

The native provider exposes `starterNpcs`, `starterObjects`, `finisherNpcs` and
`finisherObjects` directly for quests. NPC/object `mapIDs` getters expose UI map
keys without decoding spawn points. Third-party `startedBy`/`finishedBy` shapes
and area-map conversions are handled only by the offline importer; the runtime
does not carry those compatibility adapters.

`Data\Native\Overlay.lua` is generated from `Data\Source\Corrections.lua`
(hand-reviewed) and `Data\Source\Discoveries.lua` (harvested from confirmed
journal entries and exact NPC scan vignette sightings). Overlay entries add, replace or delete (`false`) rows; each
records its origin (correction or discovery), and discoveries are labeled
**Forever discovery**. `verify` decodes overlaid rows through the real runtime and applies the same
schema and reference checks as imported rows.

`referenceEnabled` (shown as **Monstrator database** in Settings) defaults on.
Evidence: Confirmed excludes database records, and Evidence: Database records
isolates them. Turning the setting off also hides database favorites without
deleting their snapshots. Inventory database counts never increase confirmed
counts. Navigation titles and notifications label database targets
**Monstrator DB**.

`groupNPCs` defaults on for directory browsing: records group by NPC ID, UI map ID
and verification state. Group wrappers retain all matching placements and select
the nearest comparable distance on the half-second tick; unmatched distances
sort last and deterministic key ordering breaks ties. Different zones/evidence
states are not merged. Disabling grouping returns individual placement rows.
Journal/favorites never group, and aggregate placement counts remain separate
from distinct NPC-ID counts.

Journal review can edit both pending and user-confirmed records, including
explicit validated tags; edits rebuild index state and discard old
world-coordinate caches. Unknown tags do not partially mutate records.
Duplicate pending sightings merge newly observed service tags. Manual NPC
target capture does not record players and remains approximate encounter data.
Opt-in target/mouseover discovery shares the journal and review gate, with a
30-second transient per-GUID throttle. GUIDs are never persisted/exported.
Metadata merges only on matching nearby pending observations; service
interactions can upgrade a generic Combat category. Confirmed placement evidence
is not silently replaced by new encounter coordinates.

Map/world transforms supply comparable yard positions only within compatible
world instances. No transit route, patrol history or server spawn GUID is stored.
Localized zone names are display metadata and must not replace map IDs.

## Storage and indexing

Saved schema version 1:

- `Monstrator_Settings`: schema plus UI/capture preferences.
- `Monstrator_Favorites`: schema and `entries[key]` snapshots.
- `Monstrator_Observations`: schema, monotonic `nextID`, and `entries[key]`.
  Pending and user-confirmed entries share the bounded journal.

Missing legacy schema markers on compatible table shapes are upgraded to 1;
missing defaults are added. Unknown newer schemas and malformed containers are
preserved, reported, and not consumed. Future migrations must be explicit and
non-destructive. Never initialize missing data and call that cold-start recovery.

Indexes are built on first directory/query/inspection use, not at login.
Indexes: record key, map ID, kind, category, NPC ID (list), and normalized
whitespace-separated search tokens (name, canonical tags, category, NPC ID,
observed creature type/rank and live
localized map name). Zone names enrich search, never replace numeric map IDs.
Partial/alias token candidates are cached
for the most recent query. Remaining predicates are applied after choosing the
smallest candidate list. Confirmed observations are indexed incrementally;
deletions rebuild indexes. Every match remains available before row virtualization.
Lua lowercase handling is not full Unicode case folding; do not claim translated
or accent-insensitive NPC search.

The UI's All entries filter combines both kinds without changing record kinds.
Filter counts honor scope, faction and search before the chosen type/category;
they exclude pending observations. Coverage totals separately report the raw
client-map cache, which can include opposite-faction markers.

Sort orders are distance/name/zone/NPC ID; evidence filters are all/confirmed/
pending/client locations/database records. Both settings are validated and saved. The inventory
summary groups identities without collapsing their indexed placement records.
Reaction is captured evidence, not an inferred Alliance/Horde access restriction.
Distance generations reuse computed distances while the player is stationary;
new entries and unavailable transforms still receive computation/retry on the
normal half-second schedule. Source loading/index memory is separate from the
small virtualized row count, and no live performance budget is certified.
First-time client-map scans append markers to the existing index rather than
rebuilding all reference records. Changed/removal data on already populated
maps triggers a full rebuild; generation checks prevent stale updates from
being hidden by a later incremental append.

## Contributor review

1. Establish source rights and include attribution; do not paste proprietary
   database dumps, copyrighted guides or unlicensed addon source.
2. Confirm Forever edition/build and UI map ID; keep multiple spawns distinct.
3. Supply actual placement evidence, not copied illustrative coordinates,
   player encounter points presented as exact spawns, or quest objective areas.
4. Validate finite coordinates, record identity and canonical tags using the
   offline importer. All input must pass; inspect duplicate/rejection reports.
5. Test maps/coordinates inside Forever and review any runtime quarantine.
6. Record the evidence and compatibility limitations. Do not mark wandering
   NPCs as static without justification.

There are no automatic uploads or peer sharing. Players send corrections by
hand as sealed submissions (below), and a maintainer always reviews them.

## Discovery submissions

`/monstrator submit` (or **Share discoveries** in Settings) produces a
plain-text block for the player to copy into the submission issue form:

```
MONSTRATOR SUBMISSION v1
addon=1.0.0
build=70205
locale=enUS
submitter=<random 16-hex id>
created=<unix time>
records=<N>
R|<19 canonical fields>|<record seal or ->
...
seal=<hash of every line above plus a trailing newline>
END
```

It includes confirmed placements, pending NPC sightings (always held for
review) and exact scan sightings. The canonical fields are key, kind, npcID, name,
category, mapID, x, y, tags, source, build, locale, verification, precision,
sightings, lastSeen, level, classification and edited. Coordinates are written
in hundredths, and `% | ; CR LF` are percent-escaped.

**Seals.** Every record is sealed when the addon captures it, using the
submitter ID. Merging a repeat sighting reseals it only if the seal was still
intact. When a player moves a pending record by more than 0.5 during review,
it is marked `edited`. The whole block also carries an overall seal.

**Threat model.** A WoW addon cannot hold a secret, so the seals are
*tamper-evident*, not tamper-proof. They catch hand edits to the
SavedVariables file or the pasted text. They do not stop someone who
re-implements the algorithm. The real defences are on the review side:

- The overall seal must be valid, or the whole submission is rejected.
- A tampered record is rejected.
- Unsealed (legacy), unconfirmed, edited and location records are held.
- An NPC record is accepted automatically only if it matches the database
  (same name and map, within 1%). It is also accepted if at least
  `--min-reporters` (default 2) distinct submitters agree within 1%.
- `Data\Source\SubmissionLedger.json` records every reviewed submission seal,
  so a resubmitted block cannot count twice.

Maintainer workflow:

```
node tools\monstrator-db.cjs review <file-or-folder>            # dry run report
node tools\monstrator-db.cjs review <file-or-folder> --apply    # merge into Discoveries
node tools\monstrator-db.cjs review <...> --apply --accept-held # after manual checks
node tools\monstrator-db.cjs overlay
```

`harvest` reads the local SavedVariables and also rejects tampered records.
