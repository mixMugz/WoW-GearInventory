-- GearInventory/Addons/Broker.lua
-- Creates the LibDataBroker launcher object consumed by Bazooka and other
-- LDB display addons. Does nothing if LibDataBroker-1.1 is unavailable.
--
-- Depends on: GI.ldb (Addons/Libs.lua), GI.BuildCharacterTooltip (GearInventory.lua),
--             GI.ToggleMainWindow (Addons/UI.lua), GI.OnCharacterDataUpdated (Addons/UI.lua)

local addonName, GI = ...
local L = GI.L

if not GI.ldb then return end -- Bazooka (or another LDB display) not installed

-- ─── Current Character ilvl ───────────────────────────────────────────────────

local function CurrentCharIlvl()
  if not GI.db then return "?" end
  local key = UnitName("player") .. "-" .. GetRealmName()
  local d   = GI.db.characters[key]
  if not d then return "?" end
  local ready = GI.IsIlvlReady(key)
  if d.avgIlvl ~= nil then
    return tostring(d.avgIlvl) .. (not ready and "~" or "")
  end
  return not ready and "..." or "?"
end

-- ─── LDB Data Object ──────────────────────────────────────────────────────────

GI.brokerObj = GI.ldb:NewDataObject("GearInventory", {
  type  = "launcher",
  label = "GearInventory",
  icon  = GI.TEX.ICON,
  text  = "?",

  OnClick = function(_, button)
    if button == "LeftButton" then
      GI.ToggleMainWindow()
    elseif button == "RightButton" then
      GI.OpenOptions()
    end
  end,

  OnTooltipShow = function(tip)
    GI.BuildCharacterTooltip(tip)
    tip:AddLine(" ")
    tip:AddLine("|cFFAAAAAA" .. L["TIP_CLICK"]       .. "|r", 1, 1, 1)
    tip:AddLine("|cFFAAAAAA" .. L["TIP_RIGHT_CLICK"] .. "|r", 1, 1, 1)
  end,
})

-- ─── Keep Broker Text in Sync ─────────────────────────────────────────────────
-- Wraps GI.OnCharacterDataUpdated (set by UI.lua) to also update broker text.
-- This file loads after UI.lua so origCallback is already defined.

local origCallback = GI.OnCharacterDataUpdated

GI.OnCharacterDataUpdated = function(charKey)
  GI.brokerObj.text = CurrentCharIlvl()
  if origCallback then origCallback(charKey) end
end

-- Sync text after the PLAYER_LOGIN gear scan completes (+1 s buffer over Core's 2 s)
local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("PLAYER_LOGIN")
syncFrame:SetScript("OnEvent", function(self)
  C_Timer.After(3, function()
    GI.brokerObj.text = CurrentCharIlvl()
  end)
  self:UnregisterEvent("PLAYER_LOGIN")
end)
