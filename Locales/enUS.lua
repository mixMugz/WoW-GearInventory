-- GearInventory/Locales/enUS.lua
-- English (US) locale — base language for all translatable strings.
-- Other locale files (ruRU.lua, deDE.lua, …) override only the keys they translate;
-- GI.L falls back to the key itself for any missing entry.

local addonName, GI = ...
local L = GI.L

-- ─── Addon Lifecycle ──────────────────────────────────────────────────────────

L["LOADED_MSG"]          = "loaded."
L["CMD_TOGGLE"]          = "|cFF00FF00/gi|r |cFFFFFFFF-|r |cFFFFD100%s|r"
L["CMD_OPTIONS"]         = "|cFF00FF00/gi options|r |cFFFFFFFF-|r |cFFFFD100%s|r"
L["CMD_MINIMAP"]         = "|cFF00FF00/gi minimap|r |cFFFFFFFF-|r |cFFFFD100%s|r"
L["ACT_TOGGLE_WINDOW"]   = "Toggle main window"
L["ACT_OPEN_SETTINGS"]   = "Open settings"
L["ACT_TOGGLE_MINIMAP"]  = "Toggle minimap icon"

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
L["CHAR_LEVEL_SHORT"]    = "Lvl"
L["TOOLTIP_AVG_ILVL"]    = "Avg ilvl"
L["TOOLTIP_UPDATED"]     = "Updated"
L["TOOLTIP_SAVED_SPECS"] = "Saved Specs:"

-- ─── Character List Panel ─────────────────────────────────────────────────────

L["PANEL_CHARACTERS"]    = "CHARACTERS"
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
L["OPT_GENERAL"]         = "General Options"
L["OPT_SORT_BY"]         = "Sort characters by"
L["OPT_SORT_ILVL"]       = "Item Level"
L["OPT_SORT_NAME"]       = "Name"
L["OPT_SORT_CLASS"]      = "Class"
L["OPT_MINIMAP"]         = "Minimap"
L["OPT_SHOW_MINIMAP"]    = "Show minimap button"
L["OPT_ITEMS"]           = "Items"
L["OPT_COLOR_UPGRADE"]   = "Colorize upgrade rank"
L["OPT_COLOR_STARS"]     = "Colorize upgrade stars"
L["OPT_CHARACTERS"]      = "Saved Characters"
L["OPT_CHARS_DESC"]      = "Checkbox — include in recommendations. X — remove character."
