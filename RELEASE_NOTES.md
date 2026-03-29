# GearInventory — Release Notes

---

## v12.0.1 `#0003`

### New Features

- **Per-spec recommendations** — `incRecommend` stored per `gear[specID]` bucket; enable/disable recommendations independently for each spec
- **Saved Specs in tooltip** — character tooltip shows spec icons for saved specializations (only when 2+ specs are stored)
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
- Fixed `MigrateV2` was called but never defined
- Fixed `GetNativeWidth` error on logo texture (WoW 12.0 API)
- Fixed `GameTooltipStatusBar` strip appearing under minimap tooltip

### DB

- Version **v4**
- `MigrateV3`: moves `incRecommend` from `character` block into each `gear[specID]` bucket
- `MigrateV2`: removes deprecated `db.version` field

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
- DB restructured: flat layout → `character` + `gear` blocks (`MigrateV1`)

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
