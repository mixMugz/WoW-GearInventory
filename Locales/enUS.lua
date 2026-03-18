-- GearInventory/Locales/enUS.lua
-- English (US) locale — base language for all translatable strings.
-- Other locale files (ruRU.lua, deDE.lua, …) override only the keys they translate;
-- GI.L falls back to the key itself for any missing entry.

local addonName, GI = ...
local L = GI.L

-- ─── Addon Lifecycle ──────────────────────────────────────────────────────────

L["LOADED_MSG"]          = "v%s loaded"
L["CMD_TOGGLE"]          = "/gi             \226\128\148 Open / Close"
L["CMD_OPTIONS"]         = "/gi options     \226\128\148 Settings"
L["CMD_MINIMAP"]         = "/gi minimap     \226\128\148 Toggle minimap button"

-- ─── Item States ──────────────────────────────────────────────────────────────

L["ITEM_LOADING"]        = "Loading..."
L["ITEM_EMPTY"]          = "Empty"

-- ─── Time Labels (last-update display) ────────────────────────────────────────

L["NEVER"]               = "Never"
L["JUST_NOW"]            = "Just now"
L["TIME_MIN"]            = "%dm ago"
L["TIME_HOUR"]           = "%dh ago"
L["TIME_DAY"]            = "%dd ago"

-- ─── Character Info Bar ───────────────────────────────────────────────────────

L["CHAR_LEVEL"]          = "Level %d"
L["CHAR_AVG_ILVL"]       = "Avg ilvl: %d"

-- ─── Character List Panel ─────────────────────────────────────────────────────

L["PANEL_CHARACTERS"]    = "CHARACTERS"
L["HINT_SELECT_CHAR"]    = "\226\134\144 Select a character"  -- ← arrow (UTF-8)

-- ─── Gear Table Column Headers ────────────────────────────────────────────────

L["COL_SLOT"]            = "SLOT"
L["COL_ITEM_NAME"]       = "ITEM NAME"
L["COL_ILVL"]            = "ILVL"

-- ─── Scan Button ──────────────────────────────────────────────────────────────

L["BTN_RESCAN"]          = "Rescan"
L["SCAN_QUEUED"]         = "Scan queued — will run after combat ends"

-- ─── Character Delete ───────────────────────────────────────────────────────

L["DELETE_CONFIRM"]      = "Delete |cFFFF6666%s|r from Gear Inventory?"

-- ─── Tooltip Hints ────────────────────────────────────────────────────────────

L["TIP_CLICK"]           = "[Click] Open / Close"
L["TIP_RIGHT_CLICK"]     = "[Right-Click] Settings"
L["TIP_DRAG"]            = "[Drag]  Reposition"

-- ─── Minimap Toggle Output ────────────────────────────────────────────────────

L["MINIMAP_BUTTON"]      = "minimap button"
L["MINIMAP_HIDDEN"]      = "|cFFFF4444hidden|r"
L["MINIMAP_SHOWN"]       = "|cFF44FF44shown|r"

-- ─── Options Panel ────────────────────────────────────────────────────────────

L["OPT_PANEL_NAME"]      = "Gear Inventory"
L["OPT_GENERAL"]         = "General"
L["OPT_AUTO_SELECT"]     = "Auto-select current character on open"
L["OPT_SORT_BY"]         = "Sort characters by"
L["OPT_SORT_ILVL"]       = "Item Level"
L["OPT_SORT_NAME"]       = "Name"
L["OPT_SORT_CLASS"]      = "Class"
L["OPT_MINIMAP"]         = "Minimap"
L["OPT_SHOW_MINIMAP"]    = "Show minimap button"
L["OPT_CHARACTERS"]      = "Saved Characters"
L["OPT_CHARS_DESC"]      = "Click X to remove a character from the list"
