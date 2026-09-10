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

  -- Defaults live in Addons/core.lua, which the TOC loads before this file.
  GI.ApplyDefaults()
end
