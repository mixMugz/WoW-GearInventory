-- GearInventory/Addons/main.lua
-- Shared utilities, DB management, gear data collection,
-- events, slash commands, loaded message.

local addonName, GI = ...

-- ─── Shared Utilities ─────────────────────────────────────────────────────────

-- Returns r, g, b (0–1) for a class token. Used by UI, Broker, Minimap, Panel.
function GI.ClassRGB(classToken)
  local c = GI.CLASS_COLORS[classToken]
  return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

-- Returns an inline |T...|t texture string for a class icon (14×14 px).
-- Uses the shared class-icon atlas texture and CLASS_ICON_TCOORDS coordinates.
function GI.ClassIconMarkup(classToken)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
  if not coords then return "" end
  return string.format(
    "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:14:14:0:0:256:256:%d:%d:%d:%d|t",
    coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

-- Returns an inline |A:...:14:14|a atlas markup string for a race icon.
-- UnitSex() values: 1 = unknown, 2 = male, 3 = female.
-- Strategy:
--   1. GetRaceAtlas(raceFile, sex) — engine-provided atlas name.
--   2. Manual fallback — try several known atlas prefixes with C_Texture
--      validation: raceicon128-, raceicon64-, raceicon-.
--   3. Cache results per raceFile+sex combo.

local raceIconCache = {}

-- raceFile (from UnitRace) → atlas token override.
-- Used when the race file name does not match the texture atlas token.
local RACE_ATLAS_TOKEN = {
  ["harronir"]           = "haranir",
  ["earthendwarf"]       = "earthen",
  ["lightforgeddraenei"] = "lightforged",
  ["zandalaritroll"]     = "zandalari",
  ["highmountaintauren"] = "highmountain",
  ["scourge"]            = "undead",
}

-- Returns the atlas name for a race icon, or nil if unavailable.
-- Caches results per raceFile+sex combo.
function GI.RaceAtlas(raceFile, sex)
  if not raceFile then return nil end

  local cacheKey = raceFile .. (sex or 2)
  if raceIconCache[cacheKey] ~= nil then
    return raceIconCache[cacheKey] ~= "" and raceIconCache[cacheKey] or nil
  end

  local sexStr   = (sex == 3) and "female" or "male"
  local atlasToken = RACE_ATLAS_TOKEN[raceFile:lower()] or raceFile:lower()

  local function ValidAtlas(name)
    return name and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(name) and name or nil
  end

  -- 1. Engine-provided atlas (validated)
  local atlas = GetRaceAtlas and ValidAtlas(GetRaceAtlas(raceFile, sex or 2))

  -- 2. Manual fallback: try known atlas prefix patterns (validated)
  if not atlas then
    local token = atlasToken .. "-" .. sexStr
    local candidates = {
      "raceicon128-" .. token,
      "raceicon64-"  .. token,
      "raceicon-"    .. token,
      "raceicon128_" .. atlasToken .. "_" .. sexStr,
      token,
    }
    for _, candidate in ipairs(candidates) do
      atlas = ValidAtlas(candidate)
      if atlas then break end
    end
  end

  -- 3. Last resort: return best-guess atlas name unconditionally.
  --    C_Texture.GetAtlasInfo may not list newer race atlases,
  --    but SetAtlas silently does nothing if the atlas is missing.
  if not atlas then
    atlas = "raceicon-" .. atlasToken .. "-" .. sexStr
  end

  raceIconCache[cacheKey] = atlas or ""
  return atlas
end

function GI.RaceIconMarkup(raceFile, sex, size)
  local atlas = GI.RaceAtlas(raceFile, sex)
  if not atlas then return "" end
  size = size or 14
  return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a "
end

-- Fills a GameTooltip-compatible object with all saved characters (by avg ilvl).
-- Used by broker.lua (LDB OnTooltipShow) and minimap.lua (manual OnEnter).
function GI.BuildCharacterTooltip(tip)
  local L = GI.L
  tip:AddLine("|cFF00C9FFGear|r|cFFFFFFFFInventory|r")
  if not GI.db then return end

  local playerRealm = GetRealmName()
  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    return (a.data.avgIlvl or 0) > (b.data.avgIlvl or 0)
  end)

  if #sorted > 0 then
    tip:AddLine(" ")
    for _, entry in ipairs(sorted) do
      local d = entry.data
      local r, g, b = GI.ClassRGB(d.class)
      local icons = GI.RaceIconMarkup(d.raceFile, d.sex)
                 .. GI.ClassIconMarkup(d.class)
      local displayName = d.name or "?"
      if d.realm and d.realm ~= playerRealm then
        displayName = displayName .. "-" .. d.realm
      end
      local nameColored = string.format(
        "|cFF%02X%02X%02X%s|r",
        r * 255, g * 255, b * 255, displayName)
      local ready = GI.IsIlvlReady(entry.key)
      local ilvlText
      if d.avgIlvl ~= nil then
        local marker = not ready and " |cFF666666~|r" or ""
        ilvlText = string.format("|cFFFFD700" .. L["CHAR_AVG_ILVL"] .. "|r", d.avgIlvl) .. marker
      elseif not ready then
        ilvlText = "|cFF666666...|r"
      else
        ilvlText = ""
      end
      tip:AddDoubleLine(
        icons .. nameColored,
        ilvlText,
        1, 1, 1, 1, 1, 1)
    end
  end
end

-- ─── Database ─────────────────────────────────────────────────────────────────

local DB_VERSION = 1

local function InitDB()
  if type(GearInventoryDB) ~= "table" then
    GearInventoryDB = { version = DB_VERSION, characters = {} }
  end
  if type(GearInventoryDB.characters) ~= "table" then
    GearInventoryDB.characters = {}
  end
  GearInventoryDB.version = GearInventoryDB.version or DB_VERSION
  GI.db = GearInventoryDB

  -- Apply default config values (defined in Options/config.lua)
  if GI.ApplyDefaults then
    GI.ApplyDefaults()
  end
end

-- ─── Item Cache ───────────────────────────────────────────────────────────────
-- C_Item.GetItemInfo returns nil for items absent from the client cache.
-- Such items are queued here and resolved via ITEM_DATA_LOAD_RESULT.

local pendingItems    = {} -- { [itemID] = { charKey = "Name-Realm", slotID = N } }
local pendingScan     = false  -- true when a scan was requested during combat/death
local pendingLoginScan = false -- true after PLAYER_LOGIN, cleared by PLAYER_ENTERING_WORLD

local function HasPending()
  return next(pendingItems) ~= nil
end

local function HasPendingForChar(charKey)
  for _, p in pairs(pendingItems) do
    if p.charKey == charKey then return true end
  end
  return false
end

-- ilvl readiness: not persisted, defaults to true for previous-session data.
local ilvlReady = {}

function GI.IsIlvlReady(charKey)
  return ilvlReady[charKey] ~= false
end


-- ─── Avg ilvl ─────────────────────────────────────────────────────────────────

-- Returns the equipped average item level from the game engine.
-- GetAverageItemLevel / C_PaperDollInfo.GetAverageItemLevel both return
-- (overall, equipped [, pvp]) — we always want the second value (equipped).
local function FetchAvgIlvl()
  if C_PaperDollInfo and C_PaperDollInfo.GetAverageItemLevel then
    local _, equipped = C_PaperDollInfo.GetAverageItemLevel()
    if equipped and equipped > 0 then return math.floor(equipped) end
  end
  if GetAverageItemLevel then
    local _, equipped = GetAverageItemLevel()
    if equipped and equipped > 0 then return math.floor(equipped) end
  end
  return nil
end

-- ─── Gear Scan ────────────────────────────────────────────────────────────────

local eventFrame -- forward-declared; assigned below

local function ScanCharacterGear(isLoginScan)
  local L = GI.L
  if not GI.db then return end

  -- Defer scan if in combat or dead; PLAYER_REGEN_ENABLED will retry.
  if InCombatLockdown() or UnitIsDeadOrGhost("player") then
    if not pendingScan then
      pendingScan = true
      print("|cFF00C9FFGear|r|cFFFFFFFFInventory|r: " .. L["SCAN_QUEUED"])
    end
    return
  end
  pendingScan = false

  local charName          = UnitName("player")
  local realm             = GetRealmName()
  local key               = charName .. "-" .. realm
  local _, class          = UnitClass("player")
  local _, raceFile       = UnitRace("player")
  local sex               = UnitSex("player")

  local d = GI.db.characters[key]
  if not d then
    d = {
      name       = charName,
      realm      = realm,
      class      = class,
      raceFile   = raceFile,
      sex        = sex,
      level      = 0,
      gear       = {},
      avgIlvl    = 0,
      lastUpdate = 0,
    }
    GI.db.characters[key] = d
  end

  d.name       = charName
  d.realm      = realm
  d.class      = class
  d.raceFile   = raceFile
  d.sex        = sex
  d.level      = UnitLevel("player")
  d.lastUpdate = time()

  for _, slot in ipairs(GI.GEAR_SLOTS) do
    local itemID = GetInventoryItemID("player", slot.id)

    if not itemID then
      d.gear[slot.id] = nil
    else
      local itemLink = GetInventoryItemLink("player", slot.id)
      local name, _, quality, ilvl = C_Item.GetItemInfo(itemLink or itemID)

      if name then
        -- Effective ilvl priority:
        --   1. GetDetailedItemLevelInfo(link)  — parses bonus IDs from hyperlink,
        --      returns the actual displayed level including upgrade rank.
        --   2. GetInventoryItemLevel — engine fallback for the equipped slot.
        --   3. ilvl from GetItemInfo — base level, last resort.
        local effectiveIlvl
        if itemLink then
          effectiveIlvl = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemLink)
        end
        if not effectiveIlvl or effectiveIlvl <= 0 then
          effectiveIlvl = GetInventoryItemLevel("player", slot.id)
        end
        effectiveIlvl = effectiveIlvl or ilvl or 0

        d.gear[slot.id] = {
          id      = itemID,
          link    = itemLink,
          name    = name,
          ilvl    = effectiveIlvl,
          quality = quality or 1,
          icon    = C_Item.GetItemIconByID(itemID),
          cached  = true,
        }
        if isLoginScan then
          pendingItems[itemID] = { charKey = key, slotID = slot.id }
          C_Item.RequestLoadItemDataByID(itemID)
        end
      else
        -- Item data not yet in cache; queue for deferred resolution.
        d.gear[slot.id] = {
          id      = itemID,
          link    = itemLink,
          name    = L["ITEM_LOADING"],
          ilvl    = (d.gear[slot.id] and d.gear[slot.id].ilvl) or 0,
          quality = 1,
          icon    = C_Item.GetItemIconByID(itemID),
          cached  = false,
        }
        pendingItems[itemID] = { charKey = key, slotID = slot.id }
        C_Item.RequestLoadItemDataByID(itemID)
      end
    end
  end

  d.avgIlvl = FetchAvgIlvl() or d.avgIlvl or 0

  if HasPending() then
    eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  end

  -- avgIlvl is taken from C_PaperDollInfo.GetAverageItemLevel() which is
  -- server-authoritative and accurate immediately. Mark as ready so the ~
  -- indicator never shows; deferred loading only corrects per-slot display.
  ilvlReady[key] = true

  if GI.OnCharacterDataUpdated then
    GI.OnCharacterDataUpdated(key)
  end
end

-- Public entry point for the force-rescan button in ui.lua.
GI.ScanCurrentCharacter = ScanCharacterGear

function GI.DeleteCharacter(charKey)
  if not GI.db or not GI.db.characters[charKey] then return end
  GI.db.characters[charKey] = nil
  ilvlReady[charKey] = nil
end

-- ─── Events ───────────────────────────────────────────────────────────────────

eventFrame = CreateFrame("Frame", "GearInventoryEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- left combat
eventFrame:RegisterEvent("PLAYER_DEAD")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)

  if event == "ADDON_LOADED" then
    if arg1 == addonName then
      InitDB()
      self:UnregisterEvent("ADDON_LOADED")
    end

  elseif event == "PLAYER_LOGIN" then
    -- Mark that PLAYER_ENTERING_WORLD should run the initial login scan.
    -- Do not scan here: server item data is not yet available at this point.
    pendingLoginScan = true

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Fires after the loading screen; item data is fully available here.
    if pendingLoginScan then
      pendingLoginScan = false
      C_Timer.After(0.5, function() ScanCharacterGear(true) end)
    end

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    C_Timer.After(0.5, ScanCharacterGear)

  elseif event == "PLAYER_REGEN_ENABLED" then
    -- Left combat: run the queued scan if one was deferred.
    if pendingScan then
      C_Timer.After(0.5, ScanCharacterGear)
    end

  elseif event == "PLAYER_DEAD" then
    -- Cancel any queued scan; no point scanning a dead character.
    pendingScan = false

  elseif event == "ITEM_DATA_LOAD_RESULT" then
    local itemID, success = arg1, arg2
    local pending = pendingItems[itemID]
    if not pending then return end

    if not success then
      pendingItems[itemID] = nil
      if not HasPendingForChar(pending.charKey) then
        ilvlReady[pending.charKey] = true
      end
      if not HasPending() then
        self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
      end
      if GI.OnCharacterDataUpdated then
        GI.OnCharacterDataUpdated(pending.charKey)
      end
      return
    end

    local name, link, quality, ilvl = C_Item.GetItemInfo(itemID)
    if name then
      local charData = GI.db and GI.db.characters[pending.charKey]
      if charData then
        local slot = charData.gear[pending.slotID]
        if slot and slot.id == itemID then
          -- Prefer effective ilvl from the slot link (captured at scan time,
          -- contains player-specific bonus IDs / upgrade rank).
          -- Fall back to the generic link from GetItemInfo (base ilvl only).
          local effectiveIlvl
          local resolvedLink = slot.link or link
          if resolvedLink then
            effectiveIlvl = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(resolvedLink)
          end
          if not effectiveIlvl or effectiveIlvl <= 0 then
            local location = ItemLocation:CreateFromEquipmentSlot(pending.slotID)
            if C_Item.DoesItemExist(location) and C_Item.GetItemID(location) == itemID then
              effectiveIlvl = C_Item.GetCurrentItemLevel(location)
            end
          end

          slot.name    = name
          slot.link    = resolvedLink
          slot.quality = quality or 1
          slot.ilvl    = effectiveIlvl or ilvl or slot.ilvl or 0
          slot.icon    = C_Item.GetItemIconByID(itemID) or slot.icon
          slot.cached  = true
          local fresh = FetchAvgIlvl()
          if fresh then charData.avgIlvl = fresh end
        end
      end
      pendingItems[itemID] = nil
    end

    if not HasPendingForChar(pending.charKey) then
      ilvlReady[pending.charKey] = true
    end

    if not HasPending() then
      self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    end

    if GI.OnCharacterDataUpdated then
      GI.OnCharacterDataUpdated(pending.charKey)
    end
  end
end)

-- ─── Slash Commands ───────────────────────────────────────────────────────────

SLASH_GEARINVENTORY1 = "/gi"
SLASH_GEARINVENTORY2 = "/gearinventory"
SlashCmdList["GEARINVENTORY"] = function(msg)
  local cmd = msg and msg:lower():match("^%s*(.-)%s*$") or ""
  if cmd == "minimap" then
    GI.ToggleMinimapButton()  -- Addons/minimap.lua
  elseif cmd == "options" or cmd == "config" then
    GI.OpenOptions()          -- Options/panel.lua
  else
    GI.ToggleMainWindow()     -- Addons/ui.lua
  end
end

local _L = GI.L
C_Timer.After(0.5, function()
  print("|cFF00C9FFGear|r|cFFFFFFFFInventory|r " .. string.format(_L["LOADED_MSG"], GI.VERSION))
  print("|cFFFFFF99  " .. _L["CMD_TOGGLE"] .. "|r")
  print("|cFFFFFF99  " .. _L["CMD_OPTIONS"] .. "|r")
  print("|cFFFFFF99  " .. _L["CMD_MINIMAP"] .. "|r")
end)
