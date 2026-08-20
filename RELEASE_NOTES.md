# GearInventory — Release Notes

---

## v12.1.0 `#0006`

---

## v12.1.0 `#0005`

### Season Update

- Version bumped for the new season (patch 12.1.0)
- TOC interface version updated to `120100`; legacy `120000`/`120001` dropped
- **Upgrade tracks updated to Season 2** — Adventurer `12817`, Veteran `12825`, Champion `12833`, Hero `12841`, Myth `12849`, 6 ranks each
- Season 1 bonusIDs removed; only the current season is tracked, past-season gear no longer resolves to a track

### Upgrade Track — Derived, Not Stored

- Upgrade track is now resolved from the saved item link on every render via `GI.GetSlotUpgrade` instead of being baked into the DB at scan time
- A season change now applies to every saved character immediately — no need to log into each alt to refresh their tracks
- Gear from a past season correctly shows no track instead of reporting a stale one
- `upTrack`, `upCur`, `upMax`, `upRank` removed from the slot schema; values written by older versions are stripped on the next warm-up pass
- Fixed the deferred item-load handler keeping a stale track: it only overwrote the stored values when a track was found, so an outdated one survived indefinitely

### Main Window — Settings Menu

- **Group by** submenu added to the title bar settings dropdown, next to Sort by — previously the only way to change grouping was right-clicking a group header, which was not discoverable
- Group-by option list extracted into a single shared builder used by both the settings dropdown and the group header context menu
- `Sorting` renamed to `Sort characters by` to match `Group characters by`

### Settings

- **General Options subcategory removed** — every setting it held is available from the main window's title bar settings dropdown, which is where they were actually used from
- `Options/general.lua` deleted; the addon no longer uses the legacy `UIDropDownMenu` system anywhere
- Saved Characters subcategory now carries an icon, matching the F.A.Q. entry
- Sidebar order is now F.A.Q. → Saved Characters
- Dropped locale keys `OPT_GENERAL`, `OPT_MINIMAP`, `OPT_ITEMS`, which existed only for that panel

### API Modernisation

- Replaced the deprecated `GetSpecialization` / `GetSpecializationInfo` globals with `C_SpecializationInfo.*`. Both were compatibility shims loaded only while the `loadDeprecationFallbacks` CVar is set, and Blizzard has them slated for removal — the addon would have broken outright without them
- Upgrade track parsing now reads exactly `numBonusIDs` entries from the item link instead of everything up to the end of the string. Trailing modifier values were being scanned as if they were bonusIDs and could have matched an upgrade track range by coincidence

### Import Validation

- Import strings are now validated before anything reaches the database. A valid `GI:v1:` header only proves the string claims to be ours; the decoded payload is checked for shape, and a malformed one is rejected outright rather than written in
- Character keys are checked for the `Name-Realm` form and rejected if they carry `|` escape sequences. Such a key used to be echoed into chat verbatim when the character was not in the database, where the sequences would be interpreted as markup
- The header version is parsed instead of being compared as one fixed string, so a string from another version is reported as such instead of as plain garbage

### Code Quality

- `GI.PlayerKey()` replaces eight copies of `UnitName("player").."-"..GetRealmName()` across `ui.lua`, `Options/characters.lua`, `exportimport.lua` and `main.lua`

### Saved Characters Panel

- **Character level** shown at the start of each row, right-aligned in a fixed zone so the numbers line up down the list, with the race and faction icons following it
- **Export button per row**, alongside the delete button in its own column. One click exports that character and opens the copy dialog — there is no per-spec export, so it needs no picker
- **Export all / Delete all buttons** in the panel header, on the title line. Both go through the same entry points as the main window settings dropdown, so the confirmations and messages are identical
- Column order, right to left, is now DELETE, EXPORT, RECOMMENDATIONS, LASTUPDATE, CHARACTERS. Delete stays rightmost so the destructive action does not move
- Export logic extracted into `GI.ShowExportCharacter` and `GI.ShowExportAll` in `ui.lua`, where the copy dialog lives, instead of being duplicated at each call site
- Settings dropdown entries shortened to `Export all...` and `Delete all...`

### Broker (LDB)

- **Stripped back to a plain launcher**: icon, addon name and a tooltip. The plate used to show the current character's item level, which had been broken since #0004 anyway — it read `d.avgIlvl`, a field that moved into `gear[specID]` back then, so it always rendered as `?`
- Removed `CurrentCharIlvl`, the `GI.OnCharacterDataUpdated` wrapper and the login sync timer that existed only to feed that number. `broker.lua` is 32 lines now
- Tooltip is identical to the minimap button tooltip, built by a shared `GI.BuildLauncherTooltip` so the two cannot drift apart. The character list that briefly lived here is gone — the main window is where that belongs
- Left click / right click hints name what they do. They previously showed a bare `Left click:` with nothing after it

### Slash Commands

- Login banner reworked: the version line now leads, followed by the command list between separators
- **`/gi minimap` removed** — the minimap button is toggled from the settings dropdown checkbox. The toggle message no longer advertises the command either
- **`/gi options` replaced by `/gi info`**, matching what the panel now holds. The old `options` and `config` spellings are gone
- Dropped locale keys `CMD_MINIMAP` and `ACT_TOGGLE_MINIMAP`

### Chat Messages

- **All addon chat output now goes through one gate** (`GI.Print` / `GI.PrintRaw`), replacing 20 scattered `print()` calls that each repeated the addon prefix by hand
- **New `Debug messages` option** in the title bar settings dropdown — on by default, stored in the DB. Switching it off silences every addon message: scan queued/complete/failed, import, export, deletions, the minimap toggle and the login banner
- A deferred scan now reports back when it finally runs, so a queued scan is never left unaccounted for. Ordinary scans stay silent — they fire on every gear and spec change
- Gear scans report an explicit failure line when the database is not ready

### Localisation

- Nine hardcoded English strings moved into locale keys: the main window `Items` label, the Saved Characters column headers, the delete picker title and its `Everything` button, and the two removal messages printed to chat
- Nothing in the addon is force-uppercased any more: column headers, the `Items` label and the character list group headers all render exactly as their text is written. `PANEL_CHARACTERS` is stored in normal case accordingly
- `PANEL_CHARACTERS` now doubles as the Characters column header instead of a second key saying the same word

### Code Comments

- File headers no longer name files that do not exist. `db.lua` pointed at the long-deleted `Options/config.lua` for the config defaults, which live in `Addons/core.lua`; `libs.lua` and `ui.lua` used old capitalised filenames
- The `OnCharacterDataUpdated` section header in `ui.lua` claimed the callback was invoked by `GearInventory.lua` and `Broker.lua`. There is no `GearInventory.lua`, and the broker stopped wrapping that callback when its item-level display was removed. Only `main.lua` calls it

### Bug Fixes

- Item-cache queue keys now include the character. Two saved characters holding the same item in the same slot shared one key, so `WarmUpAllCharacters` skipped the second and left its row on the `Loading...` placeholder until that character was logged into. The cache warm-up itself was never affected — `RequestLoadItemDataByID` fills a client-wide cache
- Fixed "Delete all characters" leaving the right panel showing a deleted alt's gear. `GI.ClearMainWindowSelection` was called without an argument and its guard compared that nil against the selection, so it returned immediately. The argument is now optional, and after the wipe the current character — the only one the rescan re-adds — is selected explicitly
- Fixed a queued scan being thrown away on death. Changing gear in combat defers the scan, but `PLAYER_DEAD` cleared the queue outright, so dying before combat ended dropped it with nothing left to retry — resurrecting fired no scan either. The queue now survives, and `PLAYER_UNGHOST` / `PLAYER_ALIVE` retry it alongside `PLAYER_REGEN_ENABLED`
- Gear pruning is now skipped when the specialization API returns nothing to compare against. Previously an empty list was treated as "this character has no specs" and every saved gear bucket for them was deleted
- Fixed the import result message on the no-conflict path reading `GI.ApplyImport`'s return values in the wrong order, so a successful single-character import printed a bare number instead of the character's name and a skipped one reported success. Both import paths now share one reporting function instead of duplicating it. That path also never triggered the item-cache warm-up for the newly imported data
- Fixed a pending-item entry leaking when `ITEM_DATA_LOAD_RESULT` reported success but the item still could not be resolved. The entry was only cleared inside the success branch, so it stayed queued forever and kept `ITEM_DATA_LOAD_RESULT` registered for the rest of the session
- Fixed the gear bucket of a character's initial specialization being pruned and rebuilt on every scan. The initial spec sits at an index past `GetNumSpecializations`, so it never appeared in the valid-spec list; the active spec is now always treated as valid. Its `incRecommend` setting could never be kept before this
- Fixed the spec-name fallbacks never firing: an unnamed spec comes back as an empty string rather than nil, and `""` is truthy in Lua. Spec lookups now go through `GI.SpecInfo`, which normalises the empty name to nil so callers' fallbacks work
- Fixed item level of level-scaling gear (heirlooms) showing the unscaled value — item level is now read from the equipped instance via `C_Item.GetCurrentItemLevel` before falling back to the link
- Replaced the deprecated `GetDetailedItemLevelInfo` global with `C_Item.GetDetailedItemLevelInfo`; dropped the `GetInventoryItemLevel` fallback, which is no longer part of the API
- Fixed the deferred item-load handler overwriting saved characters' item levels with a link-derived value on every login — item level is now only refreshed when the live equipped instance can be read, otherwise the value captured by that character's own scan is kept

---

## v12.0.1 `#0004`

### DB Structure Rework

- Gear slots now stored as `gear[specID].slots["s"..slotID]` — string keys prevent WoW serializer from collapsing the table into an ordered array, eliminating slot ID corruption
- `avgIlvl`, `avgIlvlColor`, `lastUpdate` moved from `character` block into `gear[specID]` — values are now per-spec accurate (avg item level reflects the spec's own gear)
- Removed fallback `gear[0]` bucket — no longer needed
- DB reset to `v1`; old SavedVariables must be cleared manually

### Main Window — Title Bar

- **Character jump button** — race portrait with class-coloured ring in the left corner of the title bar; click to instantly select the current character and scroll the list to their row; ring turns gold on hover; icon shifts and darkens on press

### Main Window — General

- Closes automatically on combat enter; cannot be opened while in combat
- On open, character list automatically scrolls to the selected character (current player)

### Main Window — Character List

- **Level badge** — level number displayed on a badge over the race portrait (bottom-left corner); font size auto-fits to badge bounds at any UI scale
- **Collapsible group headers** — character list can be grouped by Realm, Faction, or Armor Type; groups expand/collapse on click; header shows group name and character count
- **Sort by Level** added to sort options
- **Secondary Sort** — independent secondary sort criterion applied when primary produces equal results
- **Sort Direction** — global Ascending / Descending toggle in the Sort submenu; default Descending; applies to all sort fields
- Sort, direction, and group state persisted in config

### Settings — General Options

- Sort By, Secondary Sort, Sort Direction, and Group By available as dropdowns
- Secondary Sort automatically resets when it matches the newly selected Primary Sort
- Group By options: None, Realm, Faction, Armor Type
- Sort By options: Name, Class, Level, Item Level; Secondary adds None and Last Updated

### Settings — Saved Characters Panel

- Column RECOMMENDATIONS now dynamically sized using real header text width (`GetStringWidth`) instead of hardcoded constant — column shrinks correctly for 1–2 saved specs
- LASTUPDATE column width measured dynamically from actual content at panel open time; `GameFontNormalSmall` used for compact display
- Word wrap disabled for character name and last update columns — text clips instead of wrapping
- Spec checkboxes scaled to 0.75 (visually ~15px to match race/spec icon size)
- Spec slot group centered within RECOMMENDATIONS column based on actual spec count
- Row height set to 22px
- Left indent increased by 10px for characters list and name column header
- Delete button size reduced to 16px

### Settings — Structure

- `Options/panel.lua` split into `Options/general.lua` (sort/group/minimap/items) and `Options/main.lua` (about page, registration)
- `Options/config.lua` merged into `Addons/core.lua` — config defaults and `GI.Config.Get/Set` now loaded earlier in the stack

### Minimap Tooltip

- Tooltip width reduced — `AddDoubleLine` replaced with `AddLine` entries; no forced two-column layout
- Version removed from tooltip
- Version removed from main window title bar

### Code Quality

- `CharList_GroupHeader` and `CharList_CharButton` extracted from `CreateMainWindow` into named file-level functions
- `GetAvgIlvl`, `GetLastUpdated`, `CompareBy`, `GetGroupKey` moved to file level — no longer re-created on every `RefreshCharacterList` call
- `PROGRESS_COLORS` and `UPGRADE_STAR_COUNT` promoted to file-level constants
- Eliminated duplicate `QColor` call and dead `qHex` variable in `ShowCharacterGear`

### Export / Import

- **Export All Characters** — settings dropdown → encodes full DB into a copyable string (`GI:v1:FULL:...`)
- **Export Character** — right-click a character row → "Export Character" (`GI:v1:CHAR:...`)
- **Import** — settings dropdown; auto-detects full or single-character import; overwrites with confirmation; current player always skipped
- Encoding: CBOR → Deflate (OptimizeForSize) → Base64 via `C_EncodingUtil`; no external libraries

### Bug Fixes

- Fixed sort comparator using Lua `and/or` ternary — inconsistent result when ascending caused `table.sort` to pass `nil` as second argument and crash
- Fixed `DeleteSpec` fallback: when active spec is deleted, `character.specID` now switches to the spec with the most recent `lastUpdate` (previously used lowest specID)
- Fixed picker background clicks closing the picker window unintentionally
- Fixed `StaticPopupDialogs` for delete moved to `characters.lua`; `GI.ConfirmDeleteCharacter` moved to `main.lua`
- Fixed spec and character name coloring in delete confirmation dialogs and chat print — now uses class color
- ~~Fixed character tooltip `Spec:` line rendering in small font after minimap tooltip was shown — caused by `GameTooltip` FontString font size not being reset between tooltip uses~~
- Fixed class sort treating gendered class name variants as different values — now sorts on internal class token
- Fixed level badge rendering behind race portrait border — z-order corrected via `SetFrameLevel`

---

## v12.0.1 `#0003`

### New Features

- **Per-spec recommendations** — `incRecommend` stored per `gear[specID]` bucket; enable/disable recommendations independently for each spec
- ~~**Saved Specs in tooltip** — character tooltip shows spec icons for saved specializations (only when 2+ specs are stored)~~
- **F.A.Q.** subcategory — new section added to settings (placeholder for now)

### Settings Panel Rework

- **About page** — logo, version, DB version, author
- **General Options** subcategory — all settings (sorting, minimap, item display)
- **Saved Characters** subcategory — fully redesigned:
  - `WowScrollBoxList` + `MinimalScrollBar` replacing plain ScrollFrame (matches main window style)
  - Scrollbar auto-hides when the list fits without scrolling
  - Race icon (14×14, circular with mask) + faction icon (14×14) before character name
  - Spec icons in a circle (14×14) with `incRecommend` checkbox for each
  - Alternating row highlight
  - Realm always shown (`Name-Realm`)

### Minimap Tooltip

- Positioned via `GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")` + `SetPoint` — anchored precisely below the button
- Removed the `Drag: Reposition Button` line
- Single shared tooltip for both Path A (LibDBIcon) and Path B (Manual)

### Main Window

- Character list scrollbar auto-hides when not needed
- Icon removed from window title

### Changes

- Minimap: `gi_icon_minimap` for minimap button only; `gi_icon` everywhere else
- `star_empty` → `star_empty_silver`
- TOC: removed interface version `120005`
- Locale: removed unused keys `TIP_DRAG`, `ACT_REPOSITION`, `OPT_AUTO_SELECT`

### Bug Fixes

- Fixed `nil` in gear DB for empty offhand slot (2H weapon)
- Fixed General Options panel being empty on first open
- Fixed typo `incRecomend` → `incRecommend`
- ~~Fixed `MigrateV2` was called but never defined~~
- Fixed `GetNativeWidth` error on logo texture (WoW 12.0 API)
- Fixed `GameTooltipStatusBar` strip appearing under minimap tooltip

### DB

- ~~Version **v4**~~
- ~~`MigrateV3`: moves `incRecommend` from `character` block into each `gear[specID]` bucket~~
- ~~`MigrateV2`: removes deprecated `db.version` field~~

---

## v12.0.1 `#0002`

### New Features

- **Minimap button** — draggable button on minimap ring with left-click toggle, right-click settings, drag to reposition
- **LibDBIcon support** (Path A) — integrates with SexyMap / HandyNotes if LibDBIcon-1.0 is available
- **Manual fallback** (Path B) — custom button when LibDBIcon is absent
- **LDB Broker object** — compatible with broker display addons (Bazooka, etc.)
- **Options panel** — registered in WoW Settings UI with sidebar icon
- **Portrait mask** on character portrait in main window

### Changes

- Gear scan now supports multiple specializations per character (`gear[specID]`)
- ~~DB restructured: flat layout → `character` + `gear` blocks (`MigrateV1`)~~

### Bug Fixes

- Fixed minimap button icon size and texture coordinates
- Fixed overlay `TOPLEFT` anchor for minimap button shape masking

---

## v12.0.1 `#0001`

### New Features

- **Multi-character gear tracking** — scans and stores equipped gear for all your characters
- **Main window** — scrollable gear list with item level, quality colour and upgrade stars
- **Upgrade stars** — visual indicator (iron / bronze / silver / gold) based on upgrade track
- **Character tooltip** — hover minimap button or broker to see character summary with average ilvl
- **Class-coloured names** — character names coloured by class throughout the UI
- **Race & class icons** — displayed next to character name in tooltips and lists
- **Average ilvl** — calculated and stored per character, coloured by quality threshold
- **Localisation** — `enUS` locale, fallback to key name for missing strings

---

## v1.0.0

- Initial public release
- Basic gear inventory tracking for the current character
- Single-character support, no settings panel
