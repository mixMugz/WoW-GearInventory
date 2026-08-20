-- GearInventory/Addons/broker.lua
-- Creates the LibDataBroker launcher object consumed by Bazooka and other
-- LDB display addons. Does nothing if LibDataBroker-1.1 is unavailable.
--
-- Deliberately minimal: an icon, a name and the shared launcher tooltip. The
-- object carries no live data — the main window is where character information
-- belongs, and a broker plate that mirrors it only creates a second thing to
-- keep in sync.
--
-- Depends on: GI.ldb (Addons/libs.lua), GI.BuildLauncherTooltip (Addons/main.lua),
--             GI.ToggleMainWindow (Addons/ui.lua), GI.OpenOptions (Options/main.lua)

local addonName, GI = ...

if not GI.ldb then return end -- Bazooka (or another LDB display) not installed

GI.brokerObj = GI.ldb:NewDataObject("GearInventory", {
  type  = "launcher",
  label = "GearInventory",                              -- plain, for display menus
  text  = "|cFF00C9FFGear|r|cFFFFFFFFInventory|r",      -- shown on the plate
  icon  = GI.TEX.ICON,

  OnClick = function(_, button)
    if button == "LeftButton" then
      GI.ToggleMainWindow()
    elseif button == "RightButton" then
      GI.OpenOptions()
    end
  end,

  OnTooltipShow = GI.BuildLauncherTooltip,
})
