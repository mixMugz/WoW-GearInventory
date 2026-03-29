-- GearInventory/Options/Config.lua
-- Default configuration values and config management.
-- Loaded after Core.lua and Libs.lua; called from Core's ADDON_LOADED via GI.ApplyDefaults().
--
-- GI.db.config               — user preferences (sort order, auto-select, …)
-- GI.db.config.minimapButton — minimap button state (also consumed by LibDBIcon)

local addonName, GI = ...

-- ─── Apply Defaults ───────────────────────────────────────────────────────────
-- Recursively fills missing keys with default values; never overwrites existing data.
-- Called by Core.lua's InitDB() after GI.db is assigned.

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
  end
end
