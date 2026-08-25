# GearInventory — Release Notes

---

## v12.1.0 `#0006`

### Recommendations

- **New: item tooltips list which of your characters an item would upgrade.** Hovering an unbound item adds an `Upgrades` section — one line per character, with their level, race, faction, name, the specs it suits, and how much item level it would gain
- Only unbound gear qualifies. Bind-on-pickup, quest and bind-on-use items are skipped outright, and a bind-on-equip item that somebody already wore is caught by the `Soulbound` line in the tooltip — its bind type still reports "on equip" long after it bound. Account-bound items stay listed: they still travel between your own characters
- **Whether an item suits a character is now the game's own verdict.** `C_Item.DoesItemContainSpec` takes an explicit class and specialization and answers for that one rather than for whoever is looking — armor proficiency, weapon type and primary stat in a single call. An agility dagger no longer shows up for a warlock, and a trinket carrying all three primary stats at once correctly shows up for everybody
- It also knows things the addon never could. A tanking trinket is offered to tanks and a healing one to healers, which no rule here could have managed: nothing stored a specialization's role, and trinkets were treated as fitting anyone. One-handers are likewise turned down for two-handed specs
- With that in place the class comes straight off the character rather than out of `GI.SPEC_INFO`, and whether a specialization counts is asked of the game. A specialization Blizzard adds later keeps working with no edit here — under the old arrangement it would have vanished from recommendations silently, since the hand-written table of 38 would not have known it
- The addon's own armor, weapon and stat rules remain as a fallback for a class it does not recognise. They cannot answer the omni-stat case: `C_Item.GetItemStats` reports only the stat that suits the player, so an omni trinket looks like an agility trinket to a druid
- Suitability is real, not just item level: armor must match the class's proficiency, shields and off-hand holdables must be in the spec's off-hand list, and weapons are matched by subclass against the spec's own weapon list. Necks, rings, trinkets and cloaks carry no restriction
- Rings, trinkets and one-hand weapons are compared against the weaker of the two equipped, which is the one the item would actually displace
- A two-handed weapon fills the off-hand too, but the saved slot reads as empty. Judged as empty, it scored every one-hander as a gain of its whole item level — a 266 one-hander showed `+266` next to an equipped 256 two-hander instead of `+10`. The off-hand now falls back to whatever the main hand holds when a two-hander is in it
- **Characters below level 10 are left out.** Until then the game assigns an initial specialization, which carries no weapon or armor profile — there is nothing to compare an item against. Their checkbox in Saved Characters is greyed out and clear until a real specialization arrives, at which point it switches itself on
- The F.A.Q. panel, an empty placeholder since it was registered, now renders entries and explains that rule as its first one
- The `Recommendations` checkbox in the Saved Characters panel finally does something. It was written on every scan and read by nothing; it is now the one hard filter deciding whether a spec is considered
- A `Recommendations` submenu in the settings dropdown controls all of it. `Show` picks between never, always, or only while Ctrl or Alt is held; `Quality` sets the lowest item quality worth listing; `Ignore` toggles the item's level requirement and off-specs
- Holding a modifier rebuilds a tooltip that is already open, so the section appears and disappears as the key goes down and up rather than only counting at the moment of hover. Shift is deliberately not offered: it is Blizzard's own item-comparison modifier. The gate applies to hover tooltips only — a tooltip opened from a chat link always shows the section, since nothing would rebuild it afterwards
- Heirlooms never appear. Their item level scales with whoever wears them, so the one number a link reports cannot be compared against another character's gear
- **One line per specialization, not per character.** The character's line carries their current spec; any other spec the item would improve gets its own line underneath, without the name or the race and faction icons. Their gear differs, so their gain does too — a single shared number was a fiction
- `Ignore > Offspec` compares only against each character's last active specialization instead of every enabled one
- `Ignore > Bind on Equip` leaves plain bind-on-equip gear out. Bind on pickup is never listed and account-bound always is, but a bind-on-equip piece can be sold instead of handed on, so that one is a judgement call rather than a rule
- Warbound gear reports the same bind type as plain bind-on-equip, so the option was taking it down too. They are told apart by the tooltip's own binding line, matched against the client's `ITEM_BIND_ON_EQUIP` string rather than a hardcoded one, which keeps it working in every language
- A two-hander is judged against the average of both weapon slots rather than the main hand alone, since equipping one gives up the off-hand as well
- **Potential upgrades are listed too.** An item on a higher upgrade track can end up better than what a character wears even when it starts out worse, so a piece is now shown if it wins today *or* if its track ceiling beats theirs. A blue arrow and the track name mark that case — only that case, so the marker means one thing: behind today, further later. The item level difference shows three ways: green with an upward arrow, red with a downward one, and yellow with a ring when it is level for level — nothing moves, so nothing points anywhere
- Gear off a track cannot be pushed at all, so its ceiling is where it already stands — which is exactly why last season's gear ranks below a fresh piece of a lower track. An item that was upgraded past its own track's top keeps its real level as the ceiling
- The loot-toast arrow family ships no downward arrow and no red one, so the loss arrow is the orange one flipped and tinted. Orange rather than green: vertex colour multiplies, and green has no red channel to bring up
- `GI.CLASS_ARMOR`, whose only reader was the group-by-armor header, is now load-bearing
- **A Pandaren who has not picked a side was shown with the Alliance emblem.** The check was `faction == "Horde" and Horde or Alliance`, so anything that was not Horde fell through to Alliance -- including `Neutral`. Both panels now go through `GI.FactionAtlas`, which gives a neutral character the free-for-all marker from the same icon set — the game itself draws nothing there, but a hole in a column every other row fills reads as a fault. Grouping by faction labels them with the client's own `FACTION_NEUTRAL`
- The character level in the section is two points under the tooltip's small font. Even that font renders taller than the 10px race circle next to it, which left the least important number on the line as the loudest

### Import

- **Import no longer stores whatever the export string happened to contain.** Every character is rebuilt from the field lists in `GI.DB_FIELDS`, so a string written by an older build cannot put back a field the schema has dropped — or leave a renamed one under its old name, which broke the race icon until that character was logged into
- No v1 to v2 conversion goes with it: while the addon is unreleased the schema is still free to move, so an unknown field is discarded rather than translated. That conversion belongs here once the format is frozen
- **Importing no longer drops the character you are playing.** It used to skip them outright to protect live data, which meant their other specs — present only in the import — were lost. The active spec is still kept from the running game, but every other spec is merged in
- That was the likely cause of specs and gear seeming to vanish after an export, a wipe and an import: the wipe rescanned only the active spec, and the import then refused to restore the rest
- Merged characters are counted and reported separately, in yellow: `23 imported, 1 overwritten, 1 merged, 1 skipped.`
- The result line is assembled from fragments and lists only non-zero counts, instead of keeping one format string per combination of them
- Per-character write logic pulled out of the two near-identical branches in `GI.ApplyImport` into one function that reports `new` / `replaced` / `merged` / `skipped`

### Audit and Cleanup

- **Class names were never localised.** The character info line built its own display name from the class token, so a Russian client read `Paladin` instead of `Паладин`. It now uses the localised name captured on that character, falling back to `GI.CLASS_DISPLAY` — a table that was built at load time and then read by nothing
- The addon name markup lived in six places; it is now `GI.NAME_MARKUP` in `core.lua`
- `GI.TEX.PORTRAIT_MASK` and `GI.ATLAS.RACE_BORDER` were declared and then bypassed by eleven hardcoded copies of the same texture path and atlas name. The constants are now used
- Removed dead entries: `GI.ClassIconMarkup` and `GI.TEX.CLASS_ICONS`, left behind when the broker lost its character list; `GI.AUTHOR`, which the About page never read; `GI.TEX.MM_BORDER` and `GI.TEX.BTN_STOP`; and the iron star, unused since the progress bar settled on bronze, silver and gold
- **Item names are no longer stored, only resolved.** A saved name is in the language of whoever scanned the item, so a character exported from a Russian client and imported into a Spanish or English one showed Cyrillic in every gear row — and those clients' fonts have no Cyrillic glyphs, so it rendered as boxes rather than as text somebody could at least read
- The stored name did eventually correct itself, because the login warm-up re-resolves every saved slot through the local client — but only after it completed, and never for an item the client cannot resolve at all. The row now asks the client directly and shows `Loading...` until it answers, which is what the warm-up was already there to fix
- Item links keep their embedded name, but nothing displays it: tooltips are built by `C_TooltipInfo.GetHyperlink` from the item ID, in the viewer's own language. Deriving the row label from the link would have been worse than storing it — a stored link is never replaced once written, so the original scanner's language would have stuck permanently
- **Pre-translated names dropped from the database.** `raceName`, `factionName` and `className` all stored text already translated into the scanning client's language. `raceName` had no readers at all — the race is only ever drawn as an icon. The other two are now derived at display time from `FACTION_LABELS_FROM_STRING` and `LOCALIZED_CLASS_NAMES_MALE` / `_FEMALE`
- That also fixes imported characters: a stored name freezes the exporter's client, so a base from an English client showed `Horde` and `Shaman` next to translated rows. The globals resolve in the language of whoever is looking, and the class name still picks the gendered form from the saved sex
- `GI.CLASS_DISPLAY` went with them. It was built from `GetClassInfo`, which only ever returns the masculine form, so it could not have been the primary source anyway
- `raceFile` renamed to `race`: it holds the same kind of value as `class` and now reads like it
- The login line now colours the version yellow and the `#` white, so the build number reads as a separate part rather than a suffix on a grey string
- **No minimap button at all when a LibDBIcon host was installed without LibDataBroker.** `SetupLibDBIcon` reports failure by returning false, but the caller discarded it and never fell back to the manual button. The return value is now what decides
- **The minimap button jumped to a default position after being hidden and shown again.** SexyMap claims drag ownership of every LibDBIcon button and stores the angle in its own saved variables, so LibDBIcon's `minimapPos` never learned about the move and `:Show()` reapplied the library default. The stored angle is now read back from SexyMap before the toggle acts, in both directions — so hiding banks the real position and showing restores it
- That also means the position survives SexyMap being uninstalled, since our own copy is kept current. Every step of the lookup is guarded; if SexyMap changes its layout the sync quietly does nothing rather than breaking the button
- **The minimap button's saved angle was written under two different names.** The manual fallback used `angle`; LibDBIcon, handed the same config table, writes `minimapPos` and never looked at ours. Both now use `minimapPos`, so the button keeps its place when a LibDBIcon host is installed or removed. The positioning math was already identical — the fallback is a copy of the library's
- Default angle moved to 210 degrees, and the manual path now reads it from `GI.DEFAULTS` rather than carrying its own copy of the number
- Stale comments brought up to date: the Saved Characters column list gained EXPORT, and CLAUDE.md now records that spec slots are left-aligned rather than centred, why `gear[0]` cannot occur, and what a track entry carries

### Main Window — Upgrade Track

- Gear rows now read `Wrist :: Hero` followed by a star bar. The track is named instead of being encoded in the stars, and the stars show progress through it — filled for ranks earned, empty for ranks left
- The star bar spans the track's own length rather than a fixed five, so a track with a different number of ranks scales on its own
- The name is coloured by track rank, which lines up exactly with item quality — Adventurer white, Veteran green, Champion blue, Hero purple, Myth gold — so it reuses `ITEM_QUALITY_COLORS` rather than a palette of its own
- Track names are locale keys (`TRACK_*`). The client has no source for them: no global string holds one and they only arrive inside the tooltip line, which would leave a track unnamed unless the account owns an item of it
- The old `Colorize upgrade stars` setting became `Upgrade track > Colored`; its stored key changed with it, so that toggle returns to its default once
- `GI.ParseUpgradeTrack` and `GI.GetSlotUpgrade` now return the whole track entry instead of a four-value tuple, which stops the signature growing as fields are added
- Upgrade display settings moved into an **Upgrades** submenu in the gear dropdown, alongside Sort by and Group by, split into `Upgrade track` and `Upgrade rank` sections
- New `Show as stars` toggle: off, the rank reads `3/6` instead of the star bar, coloured by item quality shifted one step — 1/6 poor grey through 6/6 legendary. `ITEM_QUALITY_COLORS` is zero-indexed, so rank maps onto it directly
- The star bar is drawn as real textures rather than inline markup, so it can be tinted to the same six colours. Inline `|T|t` takes no colour at all; the bar tints the silver art, which is close enough to greyscale that `SetVertexColor` does not muddy the hue
- Stars sit directly after the label, spaced from it and from each other by one space measured in the label font rather than a guessed pixel gap
- With colouring off the track name and the rank fall back to yellow, which reads as deliberately plain against the dimmed grey of the line they sit in
- **Ranks not yet earned were all but invisible.** They were drawn from outline art, which is a hairline at this size — on a 1080p screen at 65% UI scale it lands under a pixel and disappears. An unearned rank is now the same filled star dimmed to silver, so the bar keeps its shape at any scale, and the stars went from 6px to 7px. Dimmed rather than tinted: an unearned rank has no colour of its own to carry
- The bar is one texture for every state, so the four other star textures — outlines and tints left over from earlier attempts at it — were deleted. The survivor is now `gi_star.tga`, named like the rest of the addon's art

### Main Window — Frame

- **The window is built inside out now, and its border scales apart from its contents.** A plain base carries the size, the position and everything in the window; the bordered frame is laid over it, anchored corner to corner rather than sized, so it takes the window's dimensions instead of setting them. The title bar, its buttons and the background art sit on the border and keep the interface scale; everything else sits in a body inset from it and keeps the window's
- **The window's own scale is bounded rather than inherited.** It follows the interface slider, except that a unit may not fall below 1.4 pixels and the window may not cover more than 90% of the screen height. Between the two it takes a scale of 1 and behaves like any other window. The ceiling wins where they disagree: a window hanging off the screen is no use however sharply it is drawn
- The floor is what the whole arrangement is for. At 1920x1080 with the slider at 65% a unit came to 0.91 pixels and the window drew smaller than it is written — hairlines landed under a pixel and outline art disappeared. It draws at 0.996 now, while the border stays at 0.65 with the rest of the interface
- Recomputed on `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED`. Without that the frames keep the scales they were given and the engine stretches what is already drawn, which only came right after closing and reopening the window
- The character info block sits on a panel of its own, between the border and the body: it claims the whole top-right zone — tight against the border on the top and both sides, left as far as the middle of the character list's scroll bar, stopping clear of the ITEMS label at the bottom. Static artwork goes on it, under the window's own text and widgets
- The window grew to 550x600 units. Its height is a stated number rather than a sum of its parts — the title bar is measured in the border's units and no longer adds up with the rest — so the layout has slack in it, and the gear list is pinned to the bottom edge and sized to its own rows to decide where that slack goes: above the list, between it and the character info block, which is where art is going later. Anchored the other way up the difference collected under the last row instead, and it varied with the scale the border happened to be drawn at
- **`Hide in combat` is an option now, on by default, and it puts the window back.** Combat used to close the window for good; it now remembers that it was open and reopens it when the fight ends. A window that was already down stays down. Switching the option off leaves the window alone in combat and lets it be opened there. Display only — scanning and item queries never depended on it

### Main Window — Character List

- **A realm too wide for the row wrapped onto a second line the row has no room for.** The realm is drawn on one line now and truncated when it does not fit
- Its size comes from the name's own font rather than an offset from the small font object: locales ship their own sizes for both, and on some of them the two ended up near enough to read as one
- The name and the realm now end where the item level column starts, so neither can run under it

### Saved Characters Panel

- The realm is dimmed behind the class-coloured name instead of sharing its colour. Both live in one `FontString`, where the size cannot vary, so colour is all there is — and at equal weight the realm read as loudly as the name, down every row of the list. The same in the `Upgrades` tooltip section

### Item Data Loading

- **Every character needed a second click before its gear read properly.** The first click showed `Loading...` in every slot, the second showed the names. The load queue asked the client for items by their ID, while the panel reads names off the saved link — and to the client those are two different things: an ID loads the base item, a link loads the item with its bonuses. Everything is now asked for by link where there is one
- Items the panel finds cold are waited on through `ItemMixin:ContinueOnItemLoad`, Blizzard's own mechanism, rather than by matching load results against the addon's queue. A result that arrived with no matching queue entry used to leave the row on `Loading...` until something else happened to redraw it
- `ITEM_DATA_LOAD_RESULT` fires *synchronously* for an item the client already holds, and the event was being registered after the requests went out — so those answers landed nowhere and stranded their queue entries for the rest of the session. Registration now happens before the first request
- **Fixed saved characters being given the played character's item level.** The load handler read the equipped slot whenever the item ID and slot number matched, without checking who the entry belonged to. An alt holding the same item in the same slot got the player's number written over theirs — upgrading a track moves the bonus ID, not the item ID, so two characters wearing the same piece at different ranks collided. The equipped slot is now only read when the entry belongs to the played character
- A link captured while its item was still loading carries an empty name and a stand-in quality, and the handler preferred the stored link over the freshly resolved one — so that placeholder was written back and kept. The resolved link wins now
- **The stored `cached` flag is gone.** It recorded whether the client had the item at scan time, then went into saved variables and claimed "loaded" on the next login while the cache was cold. Whether an item can be read is asked at draw time instead, and the greyed-out average in the character list follows the load queue
- Changing a full outfit fires `PLAYER_EQUIPMENT_CHANGED` once per slot, and each event started its own timer — sixteen identical whole-character scans in a row. One timer now, pushed back by each event, so the scan runs once after the changes stop
- A panel opened cold waits on all sixteen slots at once and the client answers them in the same tick. Redraws are collected and run once per batch rather than once per item
- `/gi trace` toggles a trace of the load path through the chat frame: what a scan reads, what goes into the queue, what each result resolved, and how many slots were cold on a draw. Off by default and deliberately not in the options panel — it is a diagnostic

### Sorting

- **The secondary sort has its own direction.** Both levels shared one Ascending/Descending setting, so a list running item level high to low also ran its tied names Z to A. Secondary defaults to ascending, which is what a name used as a tiebreaker wants
- `Last Updated` was offered as a primary sort but missing from the config's list of accepted values, so choosing it worked until the next login and then silently reverted to item level

### F.A.Q.

- The panel scrolls, so entries can accumulate past the height of the window. Same scrollbar as the Saved Characters list

### Code Quality

- Shared helpers replace copies: `GI.SpaceWidth`, `GI.SpecList`, `GI.ConfirmDeleteSpec`, and `GI.ColorCode` / `GI.Colorize` / `GI.DisplayName` between them stood in for a space measurement written twice, a spec collection written three times, an identical eight-field popup written twice, nine hand-built colour escapes and five hand-built `Name-Realm` strings
- The two sort-order lists in one function became one `SORT_OPTIONS`; the secondary list just puts `None` in front of it
- `GI.GEAR_SLOTS` carries Blizzard's own slot name, so the empty-slot icon map is built from it instead of listing the same sixteen slots a second time
- `GI.VERSION` is read from the TOC, so a version bump touches one file
- Five comments described code that is not there: the race icon cache was headed by a description of a different function, the window toggle by frame-level machinery that never existed, and the tooltip renderer claimed to rebuild the sell price it actually drops. The dependency list in `recommend.lua` went stale twice and is now a statement of which files it leans on

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
