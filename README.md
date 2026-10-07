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

The window has three columns:

- **Browse** (left): scope, list, entry type and category.
  - **Zone**, **Region** (continent) or **World** scope. The button below them opens
    the zone picker; type to filter it, click a continent to browse the whole region.
  - **Directory**, **Favorites** or **Review journal**.
  - **All entries**, **NPCs** or **Static locations**, then a category with counts.
    The **>** button beside a category opens its sub-groups, for example each
    trainer class and profession, vendor types, services, level ranges and
    rare/elite ranks, or herbs, ore and chests.
- **Results** (middle): name and title, colour-coded distance, zone, coordinates
  and an evidence badge. Scroll with the mouse wheel.
- **Details** (right): everything known about the selection, with **Navigate**,
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

**Keyboard**: Tab and Shift+Tab move between controls, Enter activates, Up/Down
select rows when the search box is not focused, and Escape closes the window.

The scope, zone, sort, evidence filter and window position are remembered.
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
