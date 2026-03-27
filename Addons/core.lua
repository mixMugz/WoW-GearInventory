-- GearInventory/Addons/core.lua
-- Shared addon-wide constants. Loaded early so all other modules can read them.
local addonName, GI = ...

-- ─── Locale ───────────────────────────────────────────────────────────────────
-- Populated by Locales/*.lua; falls back to the key itself for missing entries.
GI.L = setmetatable({}, { __index = function(_, k) return k end })

-- ─── Version ───────────────────────────────────────────────/───────────────────
GI.VERSION = "12.0.1#0002"
GI.AUTHOR  = "mixMugz (a.k.a. Муади-Ревущийфьорд)"

-- ─── Equipment Slots ──────────────────────────────────────────────────────────
-- name keys resolve via GI.L (populated by Locales/*.lua after this file loads).
GI.GEAR_SLOTS = {
  { id = 1,  key = "SLOT_HEAD"      },
  { id = 2,  key = "SLOT_NECK"      },
  { id = 3,  key = "SLOT_SHOULDER"  },
  { id = 15, key = "SLOT_BACK"      },
  { id = 5,  key = "SLOT_CHEST"     },
  { id = 9,  key = "SLOT_WRIST"     },
  { id = 10, key = "SLOT_HANDS"     },
  { id = 6,  key = "SLOT_WAIST"     },
  { id = 7,  key = "SLOT_LEGS"      },
  { id = 8,  key = "SLOT_FEET"      },
  { id = 11, key = "SLOT_FINGER1"   },
  { id = 12, key = "SLOT_FINGER2"   },
  { id = 13, key = "SLOT_TRINKET1"  },
  { id = 14, key = "SLOT_TRINKET2"  },
  { id = 16, key = "SLOT_MAINHAND"  },
  { id = 17, key = "SLOT_OFFHAND"   },
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

-- ─── Class Armor Types ───────────────────────────────────────────────────────
-- Static mapping: class token → armor proficiency (highest wearable type).
GI.CLASS_ARMOR = {
  WARRIOR     = "Plate",
  PALADIN     = "Plate",
  DEATHKNIGHT = "Plate",
  HUNTER      = "Mail",
  SHAMAN      = "Mail",
  EVOKER      = "Mail",
  ROGUE       = "Leather",
  DRUID       = "Leather",
  MONK        = "Leather",
  DEMONHUNTER = "Leather",
  MAGE        = "Cloth",
  WARLOCK     = "Cloth",
  PRIEST      = "Cloth",
}

-- ─── Specialization Info ─────────────────────────────────────────────────────
-- Key = specID (from GetSpecializationInfo).  Values:
--   class – class token
--   stat  – primary stat: "STR" | "AGI" | "INT"
--   mh    – equippable mainhand weapon subtypes
--   oh    – equippable offhand types (empty = 2H only, no offhand)
--
-- Weapon subtypes:
--   1H:    Sword, Axe, Mace, Dagger, Fist, Warglaive, Wand
--   2H:    Sword2H, Axe2H, Mace2H, Polearm, Staff
--   Ranged: Bow, Gun, Crossbow
--   OH:    Shield, Offhand

GI.SPEC_INFO = {
  -- ── Death Knight ──────────────────────────────────────────────────────────────
  -- Swords, axes, maces (1H+2H), polearms. No daggers, fist, staves, wands.
  [250] = { class = "DEATHKNIGHT", stat = "STR",                              -- Blood
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Sword", "Axe", "Mace" },
    oh = {},
  },
  [251] = { class = "DEATHKNIGHT", stat = "STR",                              -- Frost
    mh = { "Sword", "Axe", "Mace", "Sword2H", "Axe2H", "Mace2H", "Polearm" },
    oh = { "Sword", "Axe", "Mace" },
  },
  [252] = { class = "DEATHKNIGHT", stat = "STR",                              -- Unholy
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Sword", "Axe", "Mace" },
    oh = {},
  },

  -- ── Demon Hunter ──────────────────────────────────────────────────────────────
  -- Warglaives, 1H swords, axes, fist only
  [577]  = { class = "DEMONHUNTER", stat = "AGI",                             -- Havoc
    mh = { "Warglaive", "Sword", "Axe", "Fist" },
    oh = { "Warglaive", "Sword", "Axe", "Fist" },
  },
  [581]  = { class = "DEMONHUNTER", stat = "AGI",                             -- Vengeance
    mh = { "Warglaive", "Sword", "Axe", "Fist" },
    oh = { "Warglaive", "Sword", "Axe", "Fist" },
  },
  [1480] = { class = "DEMONHUNTER", stat = "INT",                             -- Aldrachi (healer)
    mh = { "Warglaive", "Sword", "Axe", "Fist" },
    oh = { "Warglaive", "Sword", "Axe", "Fist" },
  },

  -- ── Druid ─────────────────────────────────────────────────────────────────────
  -- Maces (1H+2H), daggers, fist, staves, polearms. No swords, axes, wands.
  [102] = { class = "DRUID", stat = "INT",                                    -- Balance
    mh = { "Staff", "Polearm", "Mace2H", "Mace", "Dagger", "Fist" },
    oh = { "Offhand" },
  },
  [103] = { class = "DRUID", stat = "AGI",                                    -- Feral
    mh = { "Staff", "Polearm", "Mace2H", "Mace", "Dagger", "Fist" },
    oh = {},
  },
  [104] = { class = "DRUID", stat = "AGI",                                    -- Guardian
    mh = { "Staff", "Polearm", "Mace2H", "Mace", "Dagger", "Fist" },
    oh = {},
  },
  [105] = { class = "DRUID", stat = "INT",                                    -- Restoration
    mh = { "Staff", "Polearm", "Mace2H", "Mace", "Dagger", "Fist" },
    oh = { "Offhand" },
  },

  -- ── Evoker ────────────────────────────────────────────────────────────────────
  -- Daggers, fist, 1H swords/axes/maces, staves
  [1467] = { class = "EVOKER", stat = "INT",                                  -- Devastation
    mh = { "Staff", "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = { "Offhand" },
  },
  [1468] = { class = "EVOKER", stat = "INT",                                  -- Preservation
    mh = { "Staff", "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = { "Offhand" },
  },
  [1473] = { class = "EVOKER", stat = "INT",                                  -- Augmentation
    mh = { "Staff", "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = { "Offhand" },
  },

  -- ── Hunter ────────────────────────────────────────────────────────────────────
  [253] = { class = "HUNTER", stat = "AGI",                                   -- Beast Mastery
    mh = { "Bow", "Gun", "Crossbow" },
    oh = {},
  },
  [254] = { class = "HUNTER", stat = "AGI",                                   -- Marksmanship
    mh = { "Bow", "Gun", "Crossbow" },
    oh = {},
  },
  [255] = { class = "HUNTER", stat = "AGI",                                   -- Survival
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Staff", "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = {},
  },

  -- ── Mage ──────────────────────────────────────────────────────────────────────
  -- 1H swords, daggers, staves, wands. No axes, maces, fist.
  [62] = { class = "MAGE", stat = "INT",                                      -- Arcane
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [63] = { class = "MAGE", stat = "INT",                                      -- Fire
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [64] = { class = "MAGE", stat = "INT",                                      -- Frost
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },

  -- ── Monk ──────────────────────────────────────────────────────────────────────
  -- Fist, 1H swords/maces/axes, staves, polearms. No daggers, wands.
  [268] = { class = "MONK", stat = "AGI",                                     -- Brewmaster
    mh = { "Staff", "Polearm", "Fist", "Sword", "Mace", "Axe" },
    oh = { "Fist", "Sword", "Mace", "Axe" },
  },
  [269] = { class = "MONK", stat = "AGI",                                     -- Windwalker
    mh = { "Staff", "Polearm", "Fist", "Sword", "Mace", "Axe" },
    oh = { "Fist", "Sword", "Mace", "Axe" },
  },
  [270] = { class = "MONK", stat = "INT",                                     -- Mistweaver
    mh = { "Staff", "Fist", "Sword", "Mace", "Axe" },
    oh = { "Offhand" },
  },

  -- ── Paladin ───────────────────────────────────────────────────────────────────
  -- Swords, axes, maces (1H+2H), polearms. No daggers, fist, staves, wands.
  [65] = { class = "PALADIN", stat = "INT",                                   -- Holy
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Sword", "Axe", "Mace" },
    oh = { "Shield", "Offhand" },
  },
  [66] = { class = "PALADIN", stat = "STR",                                   -- Protection
    mh = { "Sword", "Axe", "Mace" },
    oh = { "Shield" },
  },
  [70] = { class = "PALADIN", stat = "STR",                                   -- Retribution
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm" },
    oh = {},
  },

  -- ── Priest ────────────────────────────────────────────────────────────────────
  -- 1H maces, daggers, staves, wands. No swords, axes, fist.
  [256] = { class = "PRIEST", stat = "INT",                                   -- Discipline
    mh = { "Staff", "Mace", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [257] = { class = "PRIEST", stat = "INT",                                   -- Holy
    mh = { "Staff", "Mace", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [258] = { class = "PRIEST", stat = "INT",                                   -- Shadow
    mh = { "Staff", "Mace", "Dagger", "Wand" },
    oh = { "Offhand" },
  },

  -- ── Rogue ─────────────────────────────────────────────────────────────────────
  -- 1H swords, axes, maces, daggers, fist. No 2H, shields, wands.
  [259] = { class = "ROGUE", stat = "AGI",                                    -- Assassination
    mh = { "Dagger" },
    oh = { "Dagger" },
  },
  [260] = { class = "ROGUE", stat = "AGI",                                    -- Outlaw
    mh = { "Sword", "Axe", "Mace", "Fist" },
    oh = { "Sword", "Axe", "Mace", "Dagger", "Fist" },
  },
  [261] = { class = "ROGUE", stat = "AGI",                                    -- Subtlety
    mh = { "Dagger" },
    oh = { "Dagger" },
  },

  -- ── Shaman ────────────────────────────────────────────────────────────────────
  -- Maces, axes (1H+2H), daggers, fist, staves. No swords, wands, polearms.
  [262] = { class = "SHAMAN", stat = "INT",                                   -- Elemental
    mh = { "Staff", "Axe2H", "Mace2H", "Mace", "Axe", "Dagger", "Fist" },
    oh = { "Shield", "Offhand" },
  },
  [263] = { class = "SHAMAN", stat = "AGI",                                   -- Enhancement
    mh = { "Mace", "Axe", "Dagger", "Fist" },
    oh = { "Mace", "Axe", "Dagger", "Fist" },
  },
  [264] = { class = "SHAMAN", stat = "INT",                                   -- Restoration
    mh = { "Staff", "Axe2H", "Mace2H", "Mace", "Axe", "Dagger", "Fist" },
    oh = { "Shield", "Offhand" },
  },

  -- ── Warlock ───────────────────────────────────────────────────────────────────
  -- 1H swords, daggers, staves, wands. No axes, maces, fist.
  [265] = { class = "WARLOCK", stat = "INT",                                  -- Affliction
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [266] = { class = "WARLOCK", stat = "INT",                                  -- Demonology
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },
  [267] = { class = "WARLOCK", stat = "INT",                                  -- Destruction
    mh = { "Staff", "Sword", "Dagger", "Wand" },
    oh = { "Offhand" },
  },

  -- ── Warrior ───────────────────────────────────────────────────────────────────
  -- All melee: swords, axes, maces (1H+2H), daggers, fist, polearms, staves.
  -- No wands, warglaives.
  [71] = { class = "WARRIOR", stat = "STR",                                   -- Arms
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Staff" },
    oh = {},
  },
  [72] = { class = "WARRIOR", stat = "STR",                                   -- Fury (Titan's Grip)
    mh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = { "Sword2H", "Axe2H", "Mace2H", "Polearm", "Sword", "Axe", "Mace", "Dagger", "Fist" },
  },
  [73] = { class = "WARRIOR", stat = "STR",                                   -- Protection
    mh = { "Sword", "Axe", "Mace", "Dagger", "Fist" },
    oh = { "Shield" },
  },
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
