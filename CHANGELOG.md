# Changelog

## 1.0.0

- **Selected portrait consistency**: selected artwork retains its larger 48px size while sharing the helper and Auction House border style of 30px list artwork. Both surfaces crop NPC images inside the client's circular portrait so the artwork fills the square corners. Corrects the unintended Details icon size reduction.

- **Consistent entry icons**: use the Auction House's square border atlas and native proportions for NPC portraits, objects and fallbacks, removing separate gold portrait rings and masks. Replace the invalid generic treasure-chest asset with native box artwork, add chest/cooking/quest-object mappings, and distinguish six common herb nodes by object ID. Rejected entry/sidebar icon assets are reported once and replaced with a visible question mark, preserving static/portrait separation.

- **Screenshot readability follow-up**: widen and dynamically fit the player-position readout, allow category/count labels to wrap within their rows, and show evidence labels only for otherwise identical visible rows. Distinct database/client/confirmed records remain separate.

- **Native directory polish**: remove the map breadcrumb strip entirely; restore a simple subtitle and keep all area browsing in the sidebar/picker. Separate the parchment from a dark action tray, use native primary buttons for navigation/map preview, pack applicable actions without NPC-only gaps and add full-label action tooltips. Result paging uses native scrollbar arrows instead of text carets.

- **Quieter directory presentation**: use neutral native-highlight actions for filters, secondary entry actions and footer utilities. Increase the selected portrait/name, replace parchment heading bars with fine rules, reserve gold NPC names for selection, and move repeated evidence labels out of rows while retaining evidence badges/tooltips.

- **Area-browser screenshot polish**: All entries now exposes useful category/sub-group shortcuts. NPC browse counts match result rows. Move grouped placement counts out of names into Details/tooltips and remove redundant identity/command text from parchment. Use a tracking fallback rather than a misleading human head, activate the invisible portrait resolver while loading, and share the 3D viewer's creature-cache request before retrying.

- **Protected-action fix for NPC scan**: replace the direct raid-marker API call with a hardware-click secure macro button. The action validates the sighted GUID, preserves existing marks, clears rejected actions and uses a secure combat state driver to hide/clear marking during combat. Its top-level secure frame is independent of the alert's unprotected visibility.

- **Nearby landing view**: normal directory opening resets to the current zone, all entries and nearest-first sorting rather than restoring distant scopes or stale filters; explicit browsing and journal/favorite commands are preserved.

- **Coordinate map preview and screenshot corrections**: View on map in Details, or Shift-click a result, opens its zone on the native world map with a coordinate marker, without changing navigation or confirming encounters. Object icons and engine-generated NPC portraits now use separate textures so recycled rows cannot show delayed creature artwork on static locations. Appearance resolution waits for model completion before caching a display ID. Sidebar fitting measures full text width; empty/short content hides unnecessary paging and scroll controls.

- **Portrait lifecycle fix**: losing a live target restores the cached appearance or fallback instead of retaining stale artwork.

- **NPC portraits and screenshot fixes**: directory rows and selected entries use matching live-unit portraits or client-resolved creature display portraits, with a shared bounded loader and icon fallback for unavailable NPCs. Recycled rows ignore late portrait results. Unknown NPCs no longer default to a hostile-looking sword. Larger result text and explicit, unlimited parchment word wrapping prevent the Evidence section from overflowing horizontally.
- **Beta-update compatibility and clearer controls**: newer client builds can discover world-zone maps from the live hierarchy without reusing incompatible extracted object coordinates. Unavailable automatic scans expose a nonfatal coverage status instead of the misleading build-mismatch error. The former Focus button is now Keyboard, with shortcut help. Scan alerts can mark the actual sighted NPC with a skull on click, preserving existing marks and checking combat, visibility and raid permissions.

- **Compatibility fix**: icon-led sidebar controls hide their template artwork without passing nil to texture setters, which Forever rejects. Search callbacks ignore incomplete or replaced windows to prevent a follow-on error after failed construction.
- **Directory readability**: larger secondary row text, less repeated technical data, contextual service/quest-giver icons instead of generic keys, and neutral colors for faraway distances. NPC IDs and levels remain available in Details.
- **Research-led window redesign**: use Forever's native portrait frame and bottom list tabs, textured browsing surfaces and a quest-parchment entry page. More space for entry details, integrated section headings instead of nested boxes, and coverage/progress moved to the footer tooltip. Built-in templates and artwork are referenced directly; no addon dependency or copied assets.
- **Screenshot polish**: wider, wrapping distance labels for cross-world results; larger parchment body text with extra line spacing and no inherited dark font shadow.
- **Secondary windows**: native portrait framing for Settings, Item Lookup and copy/export dialogs. Settings groups journal and display options into two panels with stateful checkboxes and status tooltips. Copy dialogs have a larger, more readable text area. Journal entries use a clear Review placement action; Favorites and Journal no longer show unrelated directory totals in the sidebar.

First release for WoW Forever (interface 16001, client 1.60.1).

- **Directory**: three-column browser for NPCs, static locations and objects, with search across names, titles, IDs, zones, tags and service keywords. Includes zone/region/world scope, a zone picker, categories and sub-groups, distance sorting and keyboard navigation.
- **Navigation**: TomTom waypoints and arrows when TomTom is installed, the built-in map pin otherwise, plus a copyable `/way` command.
- **Built-in database**: 10,000+ NPCs, 6,500+ objects, 14,000+ items and 4,000+ quests. No other addon is required at runtime.
- **Item lookup and 3D viewer**: find who sells, drops, gathers or rewards an item, and preview NPC models.
- **NPC scan**: alerts for watched NPCs and rares (nameplate, target, mouseover, minimap), with a sighting log.
- **Journal**: opt-in local discovery with review before any placement is confirmed. Review now surfaces capture source, NPC ID, sighting history, build/locale and submission-seal status; favorites and database audits are also included.
- **Discovery submissions**: `/monstrator submit` creates a sealed, anonymous text block for the submission issue form. The maintainer `review` tool rejects tampered blocks and requires corroboration from independent reporters.
- **Localization**: the full UI and help are available in enUS, deDE, frFR, esES/esMX, ptBR, itIT, ruRU, koKR, zhCN and zhTW.
- **Interface**: a help window organized by topic, and scan alerts that always draw above other windows. If a new alert arrives during combat, the Target button reads "After combat" until it can safely switch NPCs.
- **Project**: a user guide (README), a contributor and release guide (CONTRIBUTING), and the MIT license. Translations with damaged characters were repaired, and tests now guard against that damage.
- **Native-style UI**: WoW dialog borders and close control, icon-led browse lists, service/profession icons with item-slot frames, and native selection highlights. Selection details are split into scrollable location, identity and evidence cards; long journal-review evidence also scrolls instead of clipping.
