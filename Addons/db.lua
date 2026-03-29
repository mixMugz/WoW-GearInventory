-- GearInventory/Addons/db.lua
-- Database initialisation and migrations.
-- Loaded after core.lua and Options/config.lua.

local addonName, GI = ...

-- ─── Migrations ───────────────────────────────────────────────────────────────

local function MigrateV1(db)
  -- v1 → v2:
  --   1. Move db.minimapButton → db.config.minimapButton
  --   2. Restructure each character entry:
  --      flat fields → entry.character = { name, realm, class, ... }
  --      entry.gear  = { [specID] = { [slotID] = itemData } }

  -- 1. Migrate minimapButton to config
  if db.minimapButton then
    if not db.config then db.config = {} end
    if not db.config.minimapButton then
      db.config.minimapButton = db.minimapButton
    end
    db.minimapButton = nil
  end

  -- 2. Migrate character entries
  local charFields = {
    "name", "realm", "class", "className", "raceFile", "raceName",
    "sex", "faction", "factionName", "specID", "level",
    "avgIlvl", "avgIlvlColor", "lastUpdate",
  }

  if db.characters then
    for key, entry in pairs(db.characters) do
      -- Only migrate entries that still use the old flat layout
      -- (detect by presence of "name" at root level)
      if entry.name ~= nil then
        -- Build character sub-table
        entry.character = entry.character or {}
        for _, field in ipairs(charFields) do
          if entry.character[field] == nil then
            entry.character[field] = entry[field]
          end
        end

        -- Wrap gear: old gear was { [slotID] = itemData }
        -- new gear is { [specID] = { [slotID] = itemData } }
        local specID = entry.specID or 0
        local oldGear = entry.gear or {}
        entry.gear = { [specID] = oldGear }

        -- Remove flat fields from root
        for _, field in ipairs(charFields) do
          entry[field] = nil
        end
      end
    end
  end

  db.config.dbVersion = "v2"
end

local function MigrateV2(db)
  -- v2 cleanup: remove legacy top-level db.version field (was set to 1 in old releases)
  db.version = nil
end

local function RunMigrations(db)
  local ver = db.config and db.config.dbVersion

  if not ver then
    if db.config then db.config.dbVersion = "v1" end
    ver = "v1"
  end

  if ver == "v1" then
    MigrateV1(db)  -- sets dbVersion = "v2"
    MigrateV2(db)
  elseif ver == "v2" then
    MigrateV2(db)
  end
  -- ver == "v2" (current) — nothing to do after cleanup
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

function GI.InitDB()
  if type(GearInventoryDB) ~= "table" then
    GearInventoryDB = { characters = {} }
  end
  if type(GearInventoryDB.characters) ~= "table" then
    GearInventoryDB.characters = {}
  end
  GI.db = GearInventoryDB

  -- Apply default config values (defined in Options/config.lua)
  if GI.ApplyDefaults then
    GI.ApplyDefaults()
  end

  RunMigrations(GI.db)
end
