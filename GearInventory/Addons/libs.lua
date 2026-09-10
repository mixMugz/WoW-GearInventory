-- GearInventory/Addons/libs.lua
-- Picks up the broker libraries and hands them to broker.lua and minimap.lua,
-- so neither has to know where they came from.
--
--   GI.ldb    -- LibDataBroker-1.1
--   GI.dbicon -- LibDBIcon-1.0
--
-- Both ship in Libs/ and load from the TOC before this file, so both are
-- normally present. LibStub hands out whichever copy loaded first, which may
-- well be another addon's -- that is the point of it, and a newer copy winning
-- is fine.
--
-- Still guarded rather than assumed: an installation missing Libs/ altogether
-- leaves these nil, and the callers fall back to the manual minimap button.
--   if GI.ldb then ... end

local addonName, GI = ...

GI.ldb    = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true) or nil
GI.dbicon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0",     true) or nil
