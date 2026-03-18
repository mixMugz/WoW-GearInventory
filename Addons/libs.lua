-- GearInventory/Addons/Libs.lua
-- Detects optional external libraries that may be loaded before this addon.
-- Sets GI.ldb and GI.dbicon so Broker.lua and Minimap.lua are library-agnostic.
--
--   GI.ldb    -- LibDataBroker-1.1  (bundled by Bazooka and most LDB displays)
--   GI.dbicon -- LibDBIcon-1.0      (bundled by SexyMap, HandyNotes, and others)
--
-- Both are nil when the respective library is absent; callers must guard with
--   if GI.ldb then ... end

local addonName, GI = ...

GI.ldb    = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) or nil
GI.dbicon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0",     true) or nil
