-- GearInventory/Addons/core.lua
-- Shared addon-wide constants. Loaded early so all other modules can read them.
local addonName, GI = ...

-- ─── Locale ───────────────────────────────────────────────────────────────────
-- Populated by Locales/*.lua; falls back to the key itself for missing entries.
GI.L = setmetatable({}, { __index = function(_, k) return k end })

-- ─── Version ──────────────────────────────────────────────────────────────────
GI.VERSION = "1.0.0"

-- ─── Equipment Slots ──────────────────────────────────────────────────────────
GI.GEAR_SLOTS = {
  { id = 1,  name = "Head"      },
  { id = 2,  name = "Neck"      },
  { id = 3,  name = "Shoulder"  },
  { id = 15, name = "Back"      },
  { id = 5,  name = "Chest"     },
  { id = 9,  name = "Wrist"     },
  { id = 10, name = "Hands"     },
  { id = 6,  name = "Waist"     },
  { id = 7,  name = "Legs"      },
  { id = 8,  name = "Feet"      },
  { id = 11, name = "Finger 1"  },
  { id = 12, name = "Finger 2"  },
  { id = 13, name = "Trinket 1" },
  { id = 14, name = "Trinket 2" },
  { id = 16, name = "Main Hand" },
  { id = 17, name = "Off Hand"  },
}

-- ─── Class Colors ─────────────────────────────────────────────────────────────
GI.CLASS_COLORS = {
  DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
  DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
  DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
  EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
  HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
  MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
  MONK        = { r = 0.00, g = 1.00, b = 0.59 },
  PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
  PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
  ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
  SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
  WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
  WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

-- ─── Default Configuration ────────────────────────────────────────────────────
GI.DEFAULTS = {
  config = {
    sortOrder  = "ilvl", -- "ilvl" | "name" | "class"
    autoSelect = true,   -- auto-select current char when opening the window
  },
  minimapButton = {
    hide  = false,
    angle = 220, -- fallback angle when LibDBIcon is absent
  },
}
