# Monstrator

**An NPC, location and item directory for World of Warcraft: Forever.** By Metalbullz.

Find any vendor, trainer, flight master, rare, mailbox, herb or dungeon entrance
without leaving the game. Results are sorted by distance, and one click sets a
waypoint.

- **Directory**: search and browse NPCs, static locations and objects by zone,
  region or the whole world, with categories and sub-groups (every class and
  profession trainer, vendor type and service).
- **Navigation**: TomTom arrow when TomTom is installed, the built-in map pin
  otherwise, plus a copyable `/way` command.
- **Built-in database**: over 10,000 NPCs, 6,500 objects, 14,000 items and
  4,000 quests, with no other addon required.
- **Item lookup**: who sells, drops, gathers or rewards any item, sorted by distance.
- **3D viewer**: preview NPC models, and try wearable items on your character.
- **NPC scan**: alerts when a watched NPC or any rare appears, with a sighting log.
- **Discovery journal**: optionally record the NPCs you meet, review them, and
  share sealed corrections with the project.
- **Favorites**, **10 languages**, a minimap button, and a help window organized by topic.

## Installation

1. Download `Monstrator-<version>.zip` from the releases.
2. Extract it so the folder is `World of Warcraft\_classic_\Interface\AddOns\Monstrator`
   (use the AddOns folder of the client you play).
3. Enable **Monstrator** in the addon list at character select.

Requirements: WoW Forever client 1.60.1 (interface 16001). TomTom is optional.
Run `/monstrator diagnostic` after a client update; it reports any interface mismatch.

Two release builds exist:

| Build | Contents |
|---|---|
| `Monstrator-<version>.zip` | Full build: the imported base database plus Monstrator's own data |
| `Monstrator-<version>-standalone.zip` | Monstrator's own data only. The directory grows as you collect; item lookup needs the full build |

## Quick start

- `/monstrator` (or `/mon`), or click the minimap icon, to open the directory.
  Right-click the icon for Favorites; drag it to move it.
- Type in the search box: names, titles, NPC IDs, zones, or keywords such as
  `food`, `repair`, `flight` or `fishing trainer`.
- **Left-click** a result to set a waypoint. **Right-click** it to toggle a favorite.
- Press **?** in the title bar for help.

## Using the directory

The directory inherits the Forever client's native portrait-window frame:
centered title, circular map portrait, close control and native bottom tabs.
The header has a simple subtitle and player-position readout; no map-style
breadcrumb strip is used. Area browsing lives in the left **Browse** panel:
choose **Zone**, **Region** or **World**, or click the area name to open the
searchable area picker. Normal opening follows your current zone and sorts
nearest first; explicit area commands and Favorites/Journal remain available.
**All entries** offers direct category shortcuts to services, vendors, trainers,
transit and objects rather than an empty category list. Their **>** controls open
the relevant sub-groups directly; choosing NPCs or Static locations shows that
type's complete category list. Browse counts represent matching rows.
Browse sections have subtle dividers, consistently aligned 20px icons and
roomier rows. Selected entry types/categories have a gold edge accent; hover a
row for its full label. Scope and sub-group behavior is unchanged.
Textured browsing panels sit beside a quest-parchment Details page with dark
ink and section headings. If the parchment atlas is unavailable, Monstrator
reports it and retains the dark readable layout. No third-party artwork is bundled.
Navigation and map preview are native primary buttons in a separate dark
action tray beneath the parchment. Secondary
actions, filters and footer utilities use neutral text with native hover/focus
highlights instead of a grid of red buttons. Gold result names emphasize the
selected row; evidence remains in colored row badges, tooltips and Details.
The selected entry retains a larger square icon, and parchment sections use fine
dividers rather than heavy gold heading bars.
The tray packs only applicable actions into consecutive rows, so static
locations do not leave blank spaces for NPC-only controls. Hover an action to
see its full label. Controls no longer sit on the parchment's torn bottom edge.
Result paging uses native scrollbar arrow artwork, not text carets.
Long category labels/counts can wrap onto two lines. The header reserves a wider
position readout and refits it when coordinates or text scale change.
If visible rows share the same name and rounded coordinates, their evidence
labels are shown inline to distinguish database records from live/client data;
the separate records are not silently merged or promoted to confirmed evidence.
Parchment text uses shadow-free dark ink and extra line spacing; long distance
labels can wrap in the result list rather than being limited to one line.
NPC results and selected entries use real creature portraits when the client
knows their appearance. A matching target/mouseover supplies its live portrait;
otherwise Monstrator resolves the cached creature display ID through one shared,
invisible model, active only while loading. Uncached creatures are requested
through a creature tooltip before retrying. Unavailable NPCs retain a category
icon (a tracking symbol for unclassified creatures) and can retry later.
Locations keep service/object icons. Neither a portrait nor an icon proves a
confirmed location. Portrait resolution does not change journal or submission data.
Common herb nodes use their own item artwork by object ID rather than the same
herbalism icon. Containers use a native box icon. If the client rejects an icon
asset, Monstrator reports it once and shows a question mark instead of a blank slot.
All directory artwork uses the same square Auction House border: creature portraits,
object icons and fallbacks have consistent framing with no separate gold rings.
NPC portrait images are cropped inside the client's circular artwork to fill
the square, rather than showing a circular cutout inside a square border.
List icons use `auctionhouse-itemicon-small-border` when available, with a
native square-slot fallback on clients without it. Selected artwork uses the
same border style as list artwork at its larger 48px size; list icons stay 30px.
Details artwork is inset two pixels inside that slot to prevent edge overhang;
the frame size is unchanged.
Creature portrait camera angles come from the client and can vary
for animals; **3D model** provides a rotatable view when a portrait is unclear.

Use the bottom **Directory**, **Favorites** and **Review journal** tabs to switch
lists. Hover the footer's result summary for database coverage and journal
progress; these statistics no longer crowd the selected entry.
Grouped location counts appear in Details and row tooltips, leaving names
uncluttered. The Location section shows the area, coordinates and distance;
copyable navigation commands remain available through the navigation fallback.

**View on map** in Details, clicking the Location coordinates, or Shift-clicking
a result opens the native world map
at the selected entry's zone, with a gold star at its coordinates. The directory
closes to leave the map unobstructed; reopen it normally when done. This preview
does not change your TomTom arrow or native waypoint. Pending journal encounters
can be previewed without confirming them; their tooltip retains the review
warning. The marker disappears when browsing a different map. Normal left-click
still navigates, and right-click still toggles a favorite or opens journal review.
Map preview is unavailable during combat.

The window has three columns:

- **Browse** (left): scope, entry type and category.
  - **Zone**, **Region** (continent) or **World** scope. The button below them opens
    the zone picker; type to filter it, click a continent to browse the whole region.
  - **All entries**, **NPCs** or **Static locations**, then a category with counts.
    The **>** button beside a category opens its sub-groups, for example each
    trainer class and profession, vendor types, services, level ranges and
    rare/elite ranks, or herbs, ore and chests.
- **Results** (middle): name and title, colour-coded distance, zone, coordinates
  and an evidence badge. Scroll with the mouse wheel.
- **Details** (right): separate **Location**, **Details** and **Evidence** sections
  in a scrollable reading area, with **Navigate**,
  **Favorite**, **Browse this zone**, **3D model**, **Items sold/dropped** and
  **Watch for this NPC**.

**Search** matches partial names (every word must match), NPC titles, IDs,
creature type and rank, categories, tags and keywords, and zone names. Searching
`riverglades flight` in World scope finds flight masters in that zone.

**Sort** cycles Nearest first, Zone A-Z, Name A-Z, Level and NPC ID. Unknown
distances sort last. **Evidence** filters all sources, confirmed placements,
pending review, client map locations or database records.

**Grouping** (on by default) shows one row per NPC per zone, at its nearest known
location, with a location count. Turn it off in Settings to see every spawn point.

Result rows keep the name, location, distance and evidence visible; NPC IDs and
level details are in the Details pane rather than repeated in every row.
Nearby distances are green, mid-range distances gold, and farther distances
neutral. Service icons distinguish flight masters, stables, guild services and
quest-giving NPCs; a quest-giver icon does not mean a quest is currently available.

**Keyboard**: Tab and Shift+Tab move between controls, Enter activates, Up/Down
select rows when the search box is not focused, and Escape closes the window.
The **Keyboard** button leaves the search field so arrow keys operate on the
result list; it does not set your character's combat focus target. Hover it for
the keyboard shortcuts.

Normal opening from `/monstrator` or left-clicking the minimap button starts in
your **current zone**, with **all entries**, no search/evidence filter and
**nearest first**. It follows you when you change zones. World/Region and
pinned-zone browsing remain available while the window is open; explicit zone,
region, subgroup, Favorites and Journal commands retain their requested view.
Window position, scale and collection/display preferences remain saved.
`/monstrator reset` (or **Reset window & filters** in Settings) restores the defaults.

### Navigation

Navigate sets a TomTom waypoint and arrow when TomTom is installed. Otherwise it
uses the built-in map pin. If neither is possible, a window shows the coordinates
to copy. Distances are real yards on the same continent and refresh twice a second;
other zones show as *Different zone*.

### Evidence labels

Every result says where it came from:

| Label | Meaning |
|---|---|
| **Monstrator DB** | Built-in database record |
| **Forever discovery** | Confirmed on the Forever server by players and shipped with the addon |
| **User confirmed** | A journal entry you reviewed and confirmed |
| **Pending review** | A journal encounter you have not reviewed yet |
| **Game map marker** | Flight node or landmark reported by the client's map |
| **Extracted client object** | An object position from the client files, checked against the live map |

## Item lookup and 3D viewer

Click **Items** (or `/mon items NAME`) to search about 15,000 items by name or ID.
Shift-click an item to link it in chat. For the selected item, tabs list who
**sells**, **drops**, **gathers** or **rewards** it, nearest first; hostile NPCs
are red. Left-click a source to navigate, right-click an NPC to see its model.
**Show sources in directory** filters the main window to every vendor and dropper.

**3D model** (Details pane, or `/mon model`) shows the selected NPC: drag to rotate,
scroll to zoom, or turn on auto-rotate. If the server never sends a model, the
viewer says so. **3D preview** in the item window tries wearable items on your
character.

## NPC scan

**NPC scan** (footer, or `/mon scan`) alerts you when a watched NPC appears on a
nameplate, as your target or mouseover, or as a minimap marker. **Rare alerts**
adds every rare, rare elite and world boss. An alert plays a sound (optional),
shows a raid warning and a popup with **Target**, **Waypoint** and **3D model**.
**Mark NPC with skull** places a visible raid-target icon over the sighted NPC
when clicked. It requires a matching live target, mouseover or nameplate and is
unavailable during combat. Existing marks on that NPC are preserved; raid
leader/assistant permission is required in raids. A minimap sighting alone
cannot mark an NPC that is no longer visible. Nothing is marked automatically.
Marking uses a secure raid-marker macro on your click, never a direct addon
call to the protected marker API. The button is hidden by a secure combat state
driver during combat and validates the sighted unit again before preparing the
out-of-combat click action.
Each NPC alerts at most once every five minutes; dead NPCs and players are ignored.

Add NPCs with **Watch for this NPC** in the Details pane, by ID or name in the
scan window, with **Watch target**, or with `/mon scan add ID|NAME`. Names the
database does not know are watched by name, which covers custom Forever NPCs.
The last 50 sightings are listed under **Recent sightings**; click one to go back.

## Discovery journal

Collection is **off by default**. Turn on **Local collection** in Settings (or
`/monstrator collect`) to record NPCs you talk to: vendors, trainers, gossip and
flight masters. **NPC discovery** (`/monstrator discover`) also records NPCs you
target or mouse over. `/monstrator capture` records your current target, and
`/monstrator landmark NAME` saves your position as a named landmark.

Recorded positions are **your** position at the time, not the NPC's exact spawn.
Every entry starts as *Pending review*: open **Review journal**, check the
location, category and tags, then confirm or delete it. Only confirmed entries
appear in the directory. **Manage journal** (`/monstrator journal`) edits
confirmed entries too.

The review form shows the capture source, NPC ID, sighting count and time,
client build/locale, and whether the submission seal still matches the record.
These details provide context for review; the seal is tamper-evident, not proof
that the encounter position is an exact spawn.

- `/monstrator audit` compares your journal with the database: new NPCs, moved
  spawns and new services.
- **NPC inventory** (`/monstrator npcs`) summarizes every known NPC by ID.
- The journal holds 1,000 entries by default (`/monstrator limit N`, up to
  100,000). When it is full, capture pauses; nothing is deleted automatically.

## Sharing discoveries

1. Collect and confirm some discoveries.
2. Run `/monstrator submit`, or click **Share discoveries** in Settings.
3. Press Ctrl+C to copy the whole block, from `MONSTRATOR SUBMISSION v1` to `END`.
4. Paste it into a new **Discovery submission** issue on the project page.

The block contains only NPC and location records, your client build and locale,
and a random anonymous ID; no character, realm or account names. Records are
sealed when captured, so edited text is detected. A maintainer reviews every
submission, and new data is accepted only when it matches the database or at
least two players report it. See [DATA_SCHEMA.md](DATA_SCHEMA.md#discovery-submissions).

## Map markers and client objects

**Static locations** also shows flight nodes and landmarks reported by the
client's map, and object positions extracted from the client files (signs,
meeting stones and similar) that pass a live check against the map. Choosing
**World** scope scans the world-zone maps in the background while the window is
open; `/monstrator sync` refreshes the current map and `/monstrator sync world`
rescans. These are labeled as map markers, never as NPC spawns. Sign names
describe the sign, not where it points.

After a beta client update, world scanning can discover zone IDs from the live
map hierarchy instead of depending on the older extracted catalog. Extracted
object coordinates remain build/locale-gated and are never blindly reused.
If neither a compatible catalog nor a live hierarchy is available, the footer
coverage tooltip and `/monstrator diagnostic` explain the limitation; an
explicit world scan reports it as well. Current-zone markers and the directory
database still work. This does not delete your journal, favorites or settings.

## Commands

`/mon` works everywhere `/monstrator` does.

| Command | Purpose |
|---|---|
| `/monstrator` | Open or close the directory |
| `/monstrator help` | Show the command list |
| `/monstrator zone [NAME]` | Browse a zone by full or partial name; no name follows you |
| `/monstrator region [NAME]` | Browse a continent, e.g. `kalimdor`; no name uses yours |
| `/monstrator find TEXT` | Open a matching sub-group, e.g. `fishing trainer`, `herbs` |
| `/monstrator items [NAME]` | Item lookup, optionally searching for a name or item ID |
| `/monstrator model` | 3D viewer for the selected NPC |
| `/monstrator scan` | NPC scan window |
| `/monstrator scan add\|remove ID/NAME` | Add or remove a watched NPC |
| `/monstrator scan list\|on\|off\|rares\|sound\|clear\|test` | List watches, toggle scanning, rare alerts or sound, clear the log, test an alert |
| `/monstrator collect` | Toggle local collection |
| `/monstrator discover` | Toggle target/mouseover NPC discovery |
| `/monstrator capture` | Record your current NPC target |
| `/monstrator landmark NAME` | Save your position as a named landmark |
| `/monstrator journal` | Manage pending and confirmed journal entries |
| `/monstrator audit` | Compare your journal with the database |
| `/monstrator npcs` | NPC inventory grouped by NPC ID |
| `/monstrator submit` | Create a sealed submission of your discoveries |
| `/monstrator export` | Copy your journal as text |
| `/monstrator tags` | List the tags accepted in journal review |
| `/monstrator limit N` | Set the journal limit (1 to 100,000) |
| `/monstrator sync [world]` | Refresh map markers for the current map or the whole world |
| `/monstrator reset` | Reset window position, scope, sort and filters |
| `/monstrator minimap` | Show or hide the minimap button |
| `/monstrator issues` | Show saved records that could not be loaded |
| `/monstrator diagnostic` | Client, database and memory information for bug reports |
| `/monstrator profile` | Time searches against the current data |
| `/monstrator debug` | Toggle extra capture messages |
| `/monstrator clear CONFIRM` | Erase the whole journal, including confirmed entries (favorites are kept) |

## Settings

Open **Settings** from the footer. It has:

Settings uses the native WoW portrait window, with journal options and display
options in separate panels. Checkboxes show the saved state directly; hover one
for its enabled/disabled status. Item Lookup and copy/export windows use the same
native window framing. Copy windows select all text for Ctrl+C and do not upload
anything. In Review Journal, **Review placement** opens the editor rather than
setting a waypoint. Sidebar database totals appear only in Directory.

- Local collection, NPC discovery and the journal limit.
- Text and window scale, high contrast and the minimap button.
- **Group NPC locations**, and the **Monstrator database** toggle (hides all database records).
- **Manage journal**, **Export journal**, **Share discoveries** and **Load map data**.
- **Reset window & filters**.

## Privacy and saved data

Monstrator saves three account-wide tables: `Monstrator_Settings`,
`Monstrator_Favorites` and `Monstrator_Observations`. It never records player
names, GUIDs, chat or credentials, and it never sends anything anywhere; sharing
is always a manual copy and paste. WoW writes saved data at logout or `/reload`.

Saved data from a newer or damaged version is preserved, not overwritten;
`/monstrator issues` lists records that could not be loaded.

## Languages

The interface and help are translated into English, German, French, Spanish
(Spain and Mexico), Brazilian Portuguese, Italian, Russian, Korean and Simplified
and Traditional Chinese. NPC, item and zone names come from the database and stay
in English; search keywords such as `food` and `repair` are English.

## Known limitations

- Database coordinates come from the imported base data and Forever discoveries.
  Forever-specific changes appear only as players discover and share them.
- Journal positions are where you stood, not exact spawn points.
- Search is not typo-tolerant, and NPC search is not accent-insensitive.
- Patrol paths and multi-step travel routes are not supported yet.

## Reporting bugs

Open an issue with the output of `/monstrator diagnostic`, the steps to reproduce,
and any Lua error text.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, tests, the database
toolchain and the release checklist, and [DATA_SCHEMA.md](DATA_SCHEMA.md) for the
data formats. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credits and license

Monstrator's code, interface, translations, tools and own data are released under
the [MIT License](LICENSE). The full build also contains imported base data; its
source, credits and terms are listed in the `CREDITS.md` file inside each release
zip. Imported data is credited, not relicensed.
