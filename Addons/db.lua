-- GearInventory/Addons/db.lua
-- Database initialisation.

local addonName, GI = ...

-- ─── Init ─────────────────────────────────────────────────────────────────────

function GI.InitDB()
  if type(GearInventoryDB) ~= "table" then
    GearInventoryDB = { characters = {} }
  end
  if type(GearInventoryDB.characters) ~= "table" then
    GearInventoryDB.characters = {}
  end
  GI.db = GearInventoryDB

  -- Apply default config values (defined in Addons/core.lua)
  if GI.ApplyDefaults then
    GI.ApplyDefaults()
  end
end
