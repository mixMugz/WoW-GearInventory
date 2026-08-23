-- GearInventory/Addons/core.lua
-- Shared addon-wide constants. Loaded early so all other modules can read them.
local addonName, GI = ...

-- ─── Locale ───────────────────────────────────────────────────────────────────
-- Populated by Locales/*.lua; falls back to the key itself for missing entries.
GI.L = setmetatable({}, { __index = function(_, k) return k end })

-- ─── Version ──────────────────────────────────────────────────────────────────
GI.VERSION = "12.1.0#0006"

-- The addon name as it is drawn everywhere: window title, chat prefix, tooltips,
-- broker plate. One copy so the branding cannot drift between them.
GI.NAME_MARKUP = "|cFF00C9FFGear|r|cFFFFFFFFInventory|r"

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

-- ─── Class Colors & Display Names ────────────────────────────────────────────
-- Colors: WoW's built-in RAID_CLASS_COLORS — always up to date with new classes.

-- Localised class name for a class token, in the gendered form the client uses
-- for that character. Blizzard fills both tables before addons load.
--
-- Derived rather than stored: a saved name would freeze the language of whoever
-- scanned the character, so an imported base would show its exporter's client.
-- UnitSex returns 3 for female, 2 for male, 1 for unknown.
function GI.ClassDisplayName(class, sex)
  if not class then return "?" end
  local names = LOCALIZED_CLASS_NAMES_MALE
  if sex == 3 then names = LOCALIZED_CLASS_NAMES_FEMALE end
  return (names and names[class]) or class
end

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
-- Key = specID (from C_SpecializationInfo.GetSpecializationInfo).  Values:
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

-- ─── Upgrade Tracks (Midnight Season 2) ──────────────────────────────────────
-- BonusID → { track (EN), rank (1=lowest), cur, max }
-- Parsed from itemLink bonusIDs; independent of client locale.
-- Current season only — gear from past seasons resolves to no track by design.
-- When the season changes, replace the start bonusIDs below.
-- Verified in game against live items: Adventurer 12817 and Veteran 12825 at
-- rank 1, Veteran 2/6 as 12826, and Hero 3/6 as 12843. That measures both axes —
-- tracks 8 apart, ranks +1 — across three points spanning the whole range, so
-- Champion sits between confirmed neighbours and Myth continues the same run.
--
-- How to capture the numbers for a new season: bind this to a key (clicking it
-- with the mouse moves the pointer off the item and the tooltip closes), hover a
-- real equipped or bagged item, and press it. It prints the bare item string and
-- the tooltip's upgrade line, so the bonusID and the track line up.
--
--   /run local d=GameTooltip:GetPrimaryTooltipData() local _,h=TooltipUtil.GetDisplayedItem(GameTooltip) print(h:match("item[%d:%-]+")) for _,x in ipairs(d.lines) do if x.type==32 then print(x.leftText) end end
--
-- In the item string, the field right after itemContext is numBonusIDs; that many
-- values follow, and one of them is the track. Line type 32 is
-- Enum.TooltipDataLineType.ItemUpgradeLevel.
--
-- Adventure Guide links are useless for this: they carry a single placeholder
-- bonusID and get their upgrade line from the difficulty, not from the item.
--
-- The names here are internal keys the code matches on, so they stay English.
-- When a track name needs displaying, give it a locale key like every other
-- string in the addon.
--
-- Do not try to read the name from the client. Checked 2026-08-21: no global
-- string holds one, they only arrive from the server inside the tooltip line,
-- and a track could only ever be named if the account happens to own an item of
-- it. Five translated strings beat a parser with holes in it.
--
-- ilvl is the item level of a track at rank 1. Measured in game 2026-08-21 from
-- five live items: Veteran 1/6 = 279 and 2/6 = 282, Champion 2/6 = 295 and
-- 3/6 = 298, Hero 3/6 = 311. That fixes the step inside a track at +3 and the
-- gap between track bases at 13, both on two independent pairs; Adventurer and
-- Myth sit at the ends of that run.
--
-- Note that an item can exceed its own track ceiling — some upgrades push a
-- Myth item past 333. Anything comparing against ilvlMax must therefore treat
-- the item's current level as the floor, not assume ilvlMax is the larger one.
local RANK_ILVL_STEP = 3  -- item levels gained per rank inside a track

GI.UPGRADE_TRACKS = {}
do
  local tracks = {
    { name = "Adventurer", key = "TRACK_ADVENTURER", rank = 1, start = 12817, ilvl = 266, max = 6 },
    { name = "Veteran",    key = "TRACK_VETERAN",    rank = 2, start = 12825, ilvl = 279, max = 6 },
    { name = "Champion",   key = "TRACK_CHAMPION",   rank = 3, start = 12833, ilvl = 292, max = 6 },
    { name = "Hero",       key = "TRACK_HERO",       rank = 4, start = 12841, ilvl = 305, max = 6 },
    { name = "Myth",       key = "TRACK_MYTH",       rank = 5, start = 12849, ilvl = 318, max = 6 },
  }
  for _, t in ipairs(tracks) do
    local ilvlMax = t.ilvl + (t.max - 1) * RANK_ILVL_STEP
    for i = 1, t.max do
      GI.UPGRADE_TRACKS[t.start + i - 1] = {
        track   = t.name,
        key     = t.key,
        rank    = t.rank,
        cur     = i,
        max     = t.max,
        ilvl    = t.ilvl + (i - 1) * RANK_ILVL_STEP,
        ilvlMax = ilvlMax,
      }
    end
  end
end

-- Item string layout:
--   item:itemID:enchant:gem1:gem2:gem3:gem4:suffix:unique:linkLevel:specID:
--        modifiersMask:itemContext:numBonusIDs:bonusID1:...:bonusIDn:numModifiers:...
-- Eleven fields sit between itemID and numBonusIDs. The pattern matches on the
-- "item:" substring rather than anchoring at the start of the link: the colour
-- prefix (|cnIQ4:) contains a colon of its own and would shift every field by one.
local ITEM_BONUS_PATTERN = "item:%d+" .. string.rep(":[^:]*", 11) .. ":(%d+):(.*)"

-- Parses bonusIDs from an itemLink and returns upgrade track info.
-- Only the first numBonusIDs entries are considered — everything past them is
-- modifier data, whose values are unrelated to bonusIDs and could otherwise
-- collide with an upgrade track range by coincidence.
-- Returns the shared GI.UPGRADE_TRACKS entry (track, key, rank, cur, max, ilvl,
-- ilvlMax) or nil. It is shared, so callers must treat it as read-only.
function GI.ParseUpgradeTrack(itemLink)
  if not itemLink then return nil end

  local countStr, tail = itemLink:match(ITEM_BONUS_PATTERN)
  local count = tonumber(countStr)
  if not count or count < 1 or not tail then return nil end

  local seen = 0
  for idStr in tail:gmatch("(%d+)") do
    seen = seen + 1
    if seen > count then break end
    local info = GI.UPGRADE_TRACKS[tonumber(idStr)]
    if info then return info end
  end
  return nil
end

-- Localised name of a track. The client does hold translated track names, in
-- C_Item.GetItemUpgradeInfo's trackString -- but only once the item is loaded,
-- so the locale key stands in until then. A cold saved item therefore reads in
-- English and corrects itself on the next draw, while a hovered item, whose
-- tooltip is being shown, is always warm and always reads translated.
function GI.TrackName(link, track)
  if link then
    local up = C_Item.GetItemUpgradeInfo(link)
    if up and up.trackString and up.trackString ~= "" then
      return up.trackString
    end
  end
  if track and track.key then return GI.L[track.key] end
  return nil
end

-- Resolves the upgrade track of a stored gear slot from its saved itemLink.
-- Nothing about the track is persisted: deriving it on demand means a season
-- change (new bonusIDs in GI.UPGRADE_TRACKS above) applies to every saved
-- character at once, with no rescan, and gear from a past season correctly
-- resolves to no track instead of reporting a stale one.
-- Returns the shared, read-only GI.UPGRADE_TRACKS entry or nil.
function GI.GetSlotUpgrade(slot)
  if not slot or not slot.link then return nil end
  return GI.ParseUpgradeTrack(slot.link)
end

-- ─── Saved Character Schema ──────────────────────────────────────────────────
-- The fields a saved character actually consists of, listed so import can be
-- told what to keep. An export string produced by an older build still carries
-- whatever that build stored, and copying it in verbatim would resurrect fields
-- since dropped from the schema -- or leave a renamed one under its old name,
-- which is worse than junk: nothing reads it and the display breaks.
--
-- Keep these in step with what ScanCharacterGear writes. A field missing here
-- is silently dropped on import.
GI.DB_FIELDS = {
  character = { "name", "realm", "class", "race", "sex", "faction", "specID", "level" },
  -- avgIlvlColor is a nested { r, g, b } and is handled separately;
  -- slots is the table below.
  spec      = { "incRecommend", "avgIlvl", "lastUpdate" },
  slot      = { "id", "link", "ilvl", "quality", "icon", "expac", "cached" },
}

-- ─── Textures & Atlases ───────────────────────────────────────────────────────
local ADDON_TEX = "Interface\\AddOns\\GearInventory\\Textures\\"

GI.TEX = {
  ICON               = ADDON_TEX .. "gi_icon",
  MINIMAP            = ADDON_TEX .. "gi_icon_minimap",
  LOGO               = ADDON_TEX .. "gi_logo",

  -- Upgrade progress bar: bronze for the first two ranks, silver for the next
  -- two, gold for the last two.
  STAR_EMPTY         = ADDON_TEX .. "star_empty_silver",
  STAR_FILLED_BRONZE = ADDON_TEX .. "star_filled_bronze",
  STAR_FILLED_SILVER = ADDON_TEX .. "star_filled_silver",
  STAR_FILLED_GOLD   = ADDON_TEX .. "star_filled_gold",

  PORTRAIT_MASK      = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
  MM_HIGHLIGHT       = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
  MM_BG              = "Interface\\Minimap\\UI-Minimap-Background",
}

GI.ATLAS = {
  RACE_BORDER      = "talents-node-circle-gray",
  ICON_FRAME       = "UI-HUD-ActionBar-IconFrame",
  WINDOW_CORNER_TL = "UI-Frame-Metal-CornerTopLeft",
  WINDOW_BG        = "UI-Journeys-BG",
  FACTION_HORDE         = "UI-HUD-UnitFrame-Player-PVP-HordeIcon",
  FACTION_ALLIANCE      = "UI-HUD-UnitFrame-Player-PVP-AllianceIcon",
  FACTION_NEUTRAL       = "UI-HUD-UnitFrame-Player-PVP-FFAIcon",
  OPT_CHARACTERS        = "socialqueuing-icon-group",
}

-- ─── Default Configuration ────────────────────────────────────────────────────
-- Recursively fills missing keys with default values; never overwrites existing data.
-- Called by Addons/db.lua after GI.db is assigned.

local function ApplyTable(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = type(v) == "table" and {} or v
    end
    if type(v) == "table" and type(target[k]) == "table" then
      ApplyTable(target[k], v)
    end
  end
end

function GI.ApplyDefaults()
  if not GI.db then return end
  ApplyTable(GI.db, GI.DEFAULTS)
end

-- ─── Config Accessors ─────────────────────────────────────────────────────────
-- Convenience wrappers so other modules don't index GI.db.config directly.

GI.Config = {}

function GI.Config.Get(key)
  return GI.db and GI.db.config and GI.db.config[key]
end

function GI.Config.Set(key, value)
  if GI.db and GI.db.config then
    GI.db.config[key] = value
    if GI.OnConfigChanged then GI.OnConfigChanged(key) end
  end
end

GI.DEFAULTS = {
  config = {
    dbVersion          = "v1",   -- incremented on breaking schema changes
    sortOrder          = "ilvl", -- "name" | "class" | "level" | "ilvl"
    secondarySort      = "none", -- "none" | "name" | "class" | "level" | "ilvl" | "lastUpdated"
    sortDir            = "desc", -- "asc" | "desc"
    groupBy            = "none", -- "none" | "realm" | "faction" | "armor"
    colorUpgradeTrack  = true,   -- colorize the upgrade track name by its rank
    colorUpgradeRank   = true,   -- colorize the rank bar or text by progress tier
    upgradeRankAsStars = true,   -- rank as a star bar; false shows "3/6" instead
    -- "Upgrades" section in item tooltips:
    --   "none" | "always" | "ctrl" | "shift" | "alt"
    recommendShow        = "always",
    recommendMinQuality  = 2,      -- Enum.ItemQuality.Uncommon and above
    -- true ignores the item's required level, so a low alt still sees gear it
    -- will grow into; false hides characters who cannot equip it yet.
    recommendIgnoreLevel = true,
    -- true compares only against each character's last active spec
    recommendIgnoreOffspec = false,
    -- true skips bind-on-equip gear, which can be sold instead of handed on
    recommendIgnoreBoE = false,
    debugMessages      = true,   -- chat output; false silences every addon message
    minimapButton = {
      hide       = false,
      -- Angle in degrees around the minimap ring. Named after LibDBIcon's own
      -- field: the library is handed this very table and writes the key itself,
      -- so both setup paths share one value instead of drifting apart.
      minimapPos = 210,
    },
  },
}
