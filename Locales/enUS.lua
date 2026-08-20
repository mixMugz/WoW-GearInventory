-- GearInventory/Locales/enUS.lua
-- English (US) locale — base language for all translatable strings.
-- Other locale files (ruRU.lua, deDE.lua, …) override only the keys they translate;
-- GI.L falls back to the key itself for any missing entry.

local addonName, GI = ...
local L = GI.L

-- ─── Addon Lifecycle ──────────────────────────────────────────────────────────

L["LOADED_MSG"]          = "loaded."
L["CMD_TOGGLE"]          = "|cFF00FF00/gi|r |cFFFFFFFF-|r |cFFFFD100%s|r"
L["CMD_INFO"]            = "|cFF00FF00/gi info|r |cFFFFFFFF-|r |cFFFFD100%s|r"
L["ACT_TOGGLE_WINDOW"]   = "Toggle main window"
L["ACT_OPEN_INFO"]       = "Open the info panel"

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
L["CHAR_AVG_ILVL"]       = "Avg ilvl: %s"

-- ─── Character List Panel ─────────────────────────────────────────────────────

L["PANEL_CHARACTERS"]    = "Characters"
L["LABEL_ITEMS"]         = "Items"
L["HINT_SELECT_CHAR"]    = "\226\134\144 Select a character"  -- ← arrow (UTF-8)

-- ─── Equipment Slot Names ────────────────────────────────────────────────────

L["SLOT_HEAD"]           = "Head"
L["SLOT_NECK"]           = "Neck"
L["SLOT_SHOULDER"]       = "Shoulder"
L["SLOT_BACK"]           = "Back"
L["SLOT_CHEST"]          = "Chest"
L["SLOT_WRIST"]          = "Wrist"
L["SLOT_HANDS"]          = "Hands"
L["SLOT_WAIST"]          = "Waist"
L["SLOT_LEGS"]           = "Legs"
L["SLOT_FEET"]           = "Feet"
L["SLOT_FINGER1"]        = "Finger 1"
L["SLOT_FINGER2"]        = "Finger 2"
L["SLOT_TRINKET1"]       = "Trinket 1"
L["SLOT_TRINKET2"]       = "Trinket 2"
L["SLOT_MAINHAND"]       = "Main Hand"
L["SLOT_OFFHAND"]        = "Off Hand"

-- ─── Gear Scan ────────────────────────────────────────────────────────────────

L["SCAN_QUEUED"]         = "Scan queued — will run after combat ends."
L["SCAN_DONE"]           = "Queued scan complete."
L["SCAN_FAILED"]         = "|cFFFF4444Gear scan failed:|r database not ready."

-- ─── Character Delete ───────────────────────────────────────────────────────

L["DELETE_CONFIRM"]         = "Delete %s from Gear Inventory?"
L["DELETE_SPEC_CONFIRM"]    = "Remove %s spec data for %s?"
L["CTX_DELETE_CHAR"]        = "|cFFFF4444Delete...|r"
L["DELETE_ALL_CHARS"]       = "|cFFFF4444Delete all...|r"
L["DELETE_ALL_CONFIRM"]     = "Delete ALL saved characters from Gear Inventory? This cannot be undone."
L["DELETE_ALL_DONE"]        = "|cFFFF4444%d|r |cFFFFFFFFcharacter(s) deleted.|r"
L["DELETE_PICKER_TITLE"]    = "What to remove?"
L["DELETE_EVERYTHING"]      = "Everything"
L["SPEC_REMOVED"]           = "%s spec removed from %s."
L["CHAR_REMOVED"]           = "%s removed."

-- ─── Tooltip Hints ────────────────────────────────────────────────────────────

L["TIP_CLICK"]              = "Left click:"
L["TIP_RIGHT_CLICK"]        = "Right click:"

-- ─── Minimap Toggle Output ────────────────────────────────────────────────────

L["MINIMAP_BUTTON"]      = "minimap button"
L["MINIMAP_HIDDEN"]      = "|cFFFF4444hidden|r"
L["MINIMAP_SHOWN"]       = "|cFF44FF44shown|r"

-- ─── Options Panel ────────────────────────────────────────────────────────────


L["OPT_VERSION"]         = "Version"
L["OPT_DB"]              = "DB"
L["OPT_AUTHOR"]          = "Author"
L["OPT_SORT_BY"]         = "Sort characters by"
L["OPT_SORT_DIR"]        = "Direction"
L["OPT_SORT_ASC"]        = "Ascending"
L["OPT_SORT_DESC"]       = "Descending"
L["OPT_SORT_PRIMARY"]    = "Primary"
L["OPT_SORT_SECONDARY"]  = "Secondary"
L["OPT_SORT_NONE"]       = "None"
L["OPT_SORT_ILVL"]       = "Item Level"
L["OPT_SORT_NAME"]       = "Name"
L["OPT_SORT_CLASS"]      = "Class"
L["OPT_SORT_LEVEL"]      = "Level"
L["OPT_SORT_LAST_UPDATED"] = "Last Updated"
L["OPT_GROUP_BY"]        = "Group characters by"
L["OPT_GROUP_NONE"]      = "None"
L["OPT_GROUP_REALM"]     = "Realm"
L["OPT_GROUP_FACTION"]   = "Faction"
L["OPT_GROUP_ARMOR"]     = "Armor Type"
L["OPT_SHOW_MINIMAP"]    = "Show minimap button"
L["OPT_COLOR_UPGRADE"]   = "Colorize upgrade rank"
L["OPT_COLOR_STARS"]     = "Colorize upgrade stars"
L["OPT_DEBUG_MESSAGES"]  = "Debug messages"
L["OPT_CHARACTERS"]      = "Saved Characters"

-- ─── Saved Characters Panel Columns ──────────────────────────────────────────
-- Displayed as written; nothing uppercases them.

L["COL_LAST_UPDATE"]     = "Last update"
L["COL_RECOMMENDATIONS"] = "Recommendations"
L["COL_EXPORT"]          = "Export"
L["COL_DELETE"]          = "Delete"

-- ─── Export / Import ──────────────────────────────────────────────────────────

L["CTX_EXPORT_CHAR"]     = "Export Character"
L["EXPORT_ALL"]          = "Export all..."
L["BTN_EXPORT_ALL"]      = "Export all"
L["BTN_DELETE_ALL"]      = "Delete all"
L["IMPORT"]              = "Import..."
L["EXPORT_HINT"]         = "Select all and copy:"
L["IMPORT_HINT"]         = "Paste import string:"
L["IMPORT_OVERWRITE"]    = "%d character(s) already exist. Overwrite?"
L["IMPORT_INVALID"]      = "Invalid import string."
L["IMPORT_ERR_VERSION"]  = "Import string was made by a different version of the addon."
L["IMPORT_OK_FULL"]      = "|cFF00FF00%d|r |cFFFFFFFFimported,|r |cFF888888%d|r |cFFFFFFFFskipped.|r"
L["IMPORT_OK_FULL_OW"]   = "|cFF00FF00%d|r |cFFFFFFFFimported,|r |cFFFF8000%d|r |cFFFFFFFFoverwritten,|r |cFF888888%d|r |cFFFFFFFFskipped.|r"
L["IMPORT_OK_CHAR"]      = "%s imported."
L["IMPORT_SKIP_CURRENT"] = "Current character cannot be imported."
L["EXPORT_OK_FULL"]      = "All characters exported."
L["EXPORT_OK_CHAR"]      = "%s exported."
L["EXPORT_ERR"]          = "Export failed."
