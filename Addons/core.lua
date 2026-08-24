-- GearInventory/Addons/core.lua
-- Shared addon-wide constants. Loaded early so all other modules can read them.
local addonName, GI = ...

-- ─── Locale ───────────────────────────────────────────────────────────────────
-- Populated by Locales/*.lua; falls back to the key itself for missing entries.
GI.L = setmetatable({}, { __index = function(_, k) return k end })

-- ─── Version ──────────────────────────────────────────────────────────────────
-- Taken from the TOC so a bump touches one file. The TOC entry is wrapped in
-- colour markup for Blizzard's addon list; that wrapping is stripped back off.
local tocVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
GI.VERSION = tocVersion:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", "")

-- The addon name as it is drawn everywhere: window title, chat prefix, tooltips,
-- broker plate. One copy so the branding cannot drift between them.
GI.NAME_MARKUP = "|cFF00C9FFGear|r|cFFFFFFFFInventory|r"

-- ─── Equipment Slots ──────────────────────────────────────────────────────────
-- Every slot the addon knows about, in the order the gear list draws them.
--
-- key resolves via GI.L (populated by Locales/*.lua after this file loads); inv
-- is Blizzard's own slot name, which GetInventorySlotInfo turns into the empty
-- slot artwork. Both live here so the slot list is written once.
GI.GEAR_SLOTS = {
  { id = 1,  key = "SLOT_HEAD",     inv = "HeadSlot"          },
  { id = 2,  key = "SLOT_NECK",     inv = "NeckSlot"          },
  { id = 3,  key = "SLOT_SHOULDER", inv = "ShoulderSlot"      },
  { id = 15, key = "SLOT_BACK",     inv = "BackSlot"          },
  { id = 5,  key = "SLOT_CHEST",    inv = "ChestSlot"         },
  { id = 9,  key = "SLOT_WRIST",    inv = "WristSlot"         },
  { id = 10, key = "SLOT_HANDS",    inv = "HandsSlot"         },
  { id = 6,  key = "SLOT_WAIST",    inv = "WaistSlot"         },
  { id = 7,  key = "SLOT_LEGS",     inv = "LegsSlot"          },
  { id = 8,  key = "SLOT_FEET",     inv = "FeetSlot"          },
  { id = 11, key = "SLOT_FINGER1",  inv = "Finger0Slot"       },
  { id = 12, key = "SLOT_FINGER2",  inv = "Finger1Slot"       },
  { id = 13, key = "SLOT_TRINKET1", inv = "Trinket0Slot"      },
  { id = 14, key = "SLOT_TRINKET2", inv = "Trinket1Slot"      },
  { id = 16, key = "SLOT_MAINHAND", inv = "MainHandSlot"      },
  { id = 17, key = "SLOT_OFFHAND",  inv = "SecondaryHandSlot" },
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
-- Class token → armor proficiency, as an Enum.ItemArmorSubclass value so the
-- name can come from the game rather than from a word written here.
--
-- Written out because the client does not expose the mapping: everything under
-- "Armor" in the API is either damage mitigation or IsItemPreferredArmorType,
-- which answers only for the player and needs a real item location. Blizzard
-- hardcodes the same thing in Lua where it needs it -- see
-- classDefaultProfessionMap in Blizzard_GlueXML/CharacterServices.lua, which is
-- cruder still: it lumps leather and mail together and has no Evoker.
--
-- Ordered by armor type, then by class, so a missing entry is easy to spot.
local ARMOR = Enum.ItemArmorSubclass

GI.CLASS_ARMOR = {
  MAGE        = ARMOR.Cloth,
  PRIEST      = ARMOR.Cloth,
  WARLOCK     = ARMOR.Cloth,

  DEMONHUNTER = ARMOR.Leather,
  DRUID       = ARMOR.Leather,
  MONK        = ARMOR.Leather,
  ROGUE       = ARMOR.Leather,

  EVOKER      = ARMOR.Mail,
  HUNTER      = ARMOR.Mail,
  SHAMAN      = ARMOR.Mail,

  DEATHKNIGHT = ARMOR.Plate,
  PALADIN     = ARMOR.Plate,
  WARRIOR     = ARMOR.Plate,
}

-- Localised name of a class's armor type, for the group-by-armor header.
function GI.ClassArmorName(class)
  local subclass = GI.CLASS_ARMOR[class]
  if not subclass then return nil end
  return C_Item.GetItemSubClassInfo(Enum.ItemClass.Armor, subclass)
end

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
  -- ilvl seeds the ceiling below; it is not kept per rank, because only the
  -- ceiling is ever compared against.
  local tracks = {
    { key = "TRACK_ADVENTURER", rank = 1, start = 12817, ilvl = 266, max = 6 },
    { key = "TRACK_VETERAN",    rank = 2, start = 12825, ilvl = 279, max = 6 },
    { key = "TRACK_CHAMPION",   rank = 3, start = 12833, ilvl = 292, max = 6 },
    { key = "TRACK_HERO",       rank = 4, start = 12841, ilvl = 305, max = 6 },
    { key = "TRACK_MYTH",       rank = 5, start = 12849, ilvl = 318, max = 6 },
  }
  for _, t in ipairs(tracks) do
    local ilvlMax = t.ilvl + (t.max - 1) * RANK_ILVL_STEP
    for i = 1, t.max do
      GI.UPGRADE_TRACKS[t.start + i - 1] = {
        key     = t.key,
        rank    = t.rank,
        cur     = i,
        max     = t.max,
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
-- Returns the shared GI.UPGRADE_TRACKS entry (key, rank, cur, max, ilvlMax) or
-- nil. It is shared, so callers must treat it as read-only.
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
  slot      = { "id", "link", "ilvl", "quality", "icon", "cached" },
}

-- ─── Textures & Atlases ───────────────────────────────────────────────────────
local ADDON_TEX = "Interface\\AddOns\\GearInventory\\Textures\\"

GI.TEX = {
  ICON               = ADDON_TEX .. "gi_icon",
  MINIMAP            = ADDON_TEX .. "gi_icon_minimap",
  LOGO               = ADDON_TEX .. "gi_logo",

  -- Upgrade progress bar. One filled star and one empty, both silver: the art is
  -- near enough to greyscale to take a tint, so the rank colour comes from
  -- SetVertexColor rather than from a texture per colour.
  STAR_EMPTY         = ADDON_TEX .. "star_empty_silver",
  STAR_FILLED_SILVER = ADDON_TEX .. "star_filled_silver",

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
-- Fills missing keys with defaults, then puts back anything holding a value it
-- should not. Called by Addons/db.lua once GI.db is assigned.

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

-- Settings needing more than a type check. A table lists the values a setting
-- may hold; a function repairs one instead, returning the corrected value or
-- nil to fall back to the default. Everything absent here is checked by type,
-- which is all the booleans need.
--
-- Saved variables outlive the build that wrote them: a setting can hold a value
-- this version dropped -- "shift" was a Show option for a while -- or one edited
-- in by hand. Repairing at load means the menu always shows what is actually in
-- force, and nothing downstream has to guard against a value it does not know.
local CONFIG_VALUES = {
  sortOrder           = { name = true, class = true, level = true, ilvl = true,
                          lastUpdated = true },
  secondarySort       = { none = true, name = true, class = true, level = true,
                          ilvl = true, lastUpdated = true },
  sortDir             = { asc = true, desc = true },
  secondarySortDir    = { asc = true, desc = true },
  groupBy             = { none = true, realm = true, faction = true, armor = true },
  recommendShow       = { none = true, always = true, ctrl = true, alt = true },
  recommendMinQuality = { [2] = true, [3] = true, [4] = true },

  -- An angle around the minimap. Out-of-range values already draw correctly --
  -- cos and sin do not care about the period -- but 1111 in the saved file
  -- reads as damage, so it is folded back into a full turn.
  minimapPos = function(value)
    if type(value) ~= "number" then return nil end
    return value % 360
  end,
}

local function ValidateTable(target, defaults)
  for k, default in pairs(defaults) do
    local value   = target[k]
    local allowed = CONFIG_VALUES[k]

    if type(allowed) == "function" then
      local fixed = allowed(value)
      if fixed == nil then fixed = default end
      target[k] = fixed
    elseif allowed then
      if not allowed[value] then target[k] = default end
    elseif type(default) == "table" then
      ValidateTable(target[k], default)
    elseif type(value) ~= type(default) then
      target[k] = default
    end
  end
end

function GI.ApplyDefaults()
  if not GI.db then return end
  ApplyTable(GI.db, GI.DEFAULTS)
  ValidateTable(GI.db.config, GI.DEFAULTS.config)
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
    sortOrder          = "ilvl", -- "name" | "class" | "level" | "ilvl" | "lastUpdated"
    secondarySort      = "none", -- "none" | "name" | "class" | "level" | "ilvl" | "lastUpdated"
    sortDir            = "desc", -- "asc" | "desc"
    secondarySortDir   = "asc",  -- "asc" | "desc", independent of sortDir
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
