-- GearInventory/Addons/main.lua
-- Shared utilities, DB management, gear data collection,
-- events, slash commands, loaded message.

local addonName, GI = ...

-- ─── Shared Utilities ─────────────────────────────────────────────────────────

-- Returns r, g, b (0–1) for a class token. Uses WoW's built-in RAID_CLASS_COLORS.
function GI.ClassRGB(classToken)
  local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
  return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

-- Returns an inline |T...|t texture string for a class icon (14×14 px).
-- Uses the shared class-icon atlas texture and CLASS_ICON_TCOORDS coordinates.
function GI.ClassIconMarkup(classToken)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
  if not coords then return "" end
  return string.format(
    "|T" .. GI.TEX.CLASS_ICONS .. ":14:14:0:0:256:256:%d:%d:%d:%d|t",
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

-- Returns the display name and icon of a specialization.
-- GetSpecializationInfoByID yields an empty string, not nil, for a spec that has
-- no name — the placeholder one a character carries before choosing a real spec.
-- Since "" is truthy in Lua, a bare `or` fallback at the call site can never fire,
-- so the empty string is normalised to nil here and the trap stays in one place.
-- Returns: name (nil when the spec has none), icon
function GI.SpecInfo(specID)
  local _, name, _, icon = GetSpecializationInfoByID(specID)
  if name == "" then name = nil end
  return name, icon
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
  local function GetSpecBucket(data)
    local ch = data.character or {}
    return data.gear and ch.specID and data.gear[ch.specID]
  end

  table.sort(sorted, function(a, b)
    local ab = GetSpecBucket(a.data)
    local bb = GetSpecBucket(b.data)
    return ((ab and ab.avgIlvl) or 0) > ((bb and bb.avgIlvl) or 0)
  end)

  if #sorted > 0 then
    tip:AddLine(" ")
    for _, entry in ipairs(sorted) do
      local d      = entry.data
      local ch     = d.character or {}
      local bucket = GetSpecBucket(d)
      local r, g, b = GI.ClassRGB(ch.class)
      local icons = GI.RaceIconMarkup(ch.raceFile, ch.sex)
                 .. GI.ClassIconMarkup(ch.class)
      local displayName = ch.name or "?"
      if ch.realm and ch.realm ~= playerRealm then
        displayName = displayName .. "-" .. ch.realm
      end
      local nameColored = string.format(
        "|cFF%02X%02X%02X%s|r",
        r * 255, g * 255, b * 255, displayName)
      local ready   = GI.IsIlvlReady(entry.key)
      local avgIlvl = bucket and bucket.avgIlvl
      local ilvlText
      if avgIlvl ~= nil then
        local marker = not ready and " |cFF666666~|r" or ""
        ilvlText = string.format("|cFFFFD700" .. L["CHAR_AVG_ILVL"] .. "|r", avgIlvl) .. marker
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
-- Initialisation and migrations live in Addons/db.lua (GI.InitDB).

-- ─── Item Cache ───────────────────────────────────────────────────────────────
-- C_Item.GetItemInfo returns nil for items absent from the client cache.
-- Such items are queued here and resolved via ITEM_DATA_LOAD_RESULT.

local pendingItems    = {} -- { ["itemID:slotID"] = { charKey, slotID, itemID } }
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
  local className, class  = UnitClass("player")
  local raceName, raceFile = UnitRace("player")
  local sex               = UnitSex("player")
  local faction, factionName = UnitFactionGroup("player")
  local specIndex         = C_SpecializationInfo.GetSpecialization()
  local specID            = specIndex
                            and select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
                            or nil

  local specIDKey = specID or 0

  local d = GI.db.characters[key]
  if not d then
    d = {
      character = {
        name        = charName,
        realm       = realm,
        class       = class,
        className   = className,
        raceFile    = raceFile,
        raceName    = raceName,
        sex         = sex,
        faction     = faction,
        factionName = factionName,
        specID      = specID,
        level       = 0,
      },
      gear = {},
    }
    GI.db.characters[key] = d
  end

  d.character.name        = charName
  d.character.realm       = realm
  d.character.class       = class
  d.character.className   = className
  d.character.raceFile    = raceFile
  d.character.raceName    = raceName
  d.character.sex         = sex
  d.character.faction     = faction
  d.character.factionName = factionName
  d.character.specID      = specID
  d.character.level       = UnitLevel("player")

  -- Prune gear entries for specs that no longer exist on this character
  do
    local validSpecIDs = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
      local sid = select(1, C_SpecializationInfo.GetSpecializationInfo(i))
      -- specId is documented non-nilable with a default of 0, and 0 is truthy in
      -- Lua, so the explicit zero check is what actually filters here.
      if sid and sid ~= 0 then validSpecIDs[sid] = true end
    end

    -- The initial spec a character carries before choosing one sits at an index
    -- past GetNumSpecializations (see Blizzard's IsInitialSpec), so the loop above
    -- never yields its ID and the bucket would be dropped and rebuilt on every
    -- scan — silently resetting its incRecommend each time. Whatever spec is
    -- active right now is valid by definition.
    if specID then validSpecIDs[specID] = true end

    for sid in pairs(d.gear) do
      if not validSpecIDs[sid] then
        d.gear[sid] = nil
      end
    end
  end

  -- Ensure gear bucket for current spec exists
  if not d.gear[specIDKey] then
    d.gear[specIDKey] = { slots = {}, incRecommend = true }
  elseif not d.gear[specIDKey].slots then
    d.gear[specIDKey].slots = {}
  end

  local specBucket = d.gear[specIDKey]
  local specSlots  = specBucket.slots

  for _, slot in ipairs(GI.GEAR_SLOTS) do
    local skey   = "s" .. slot.id
    local itemID = GetInventoryItemID("player", slot.id)

    if not itemID or itemID == 0 then
      specSlots[skey] = nil
    else
      local itemLink = GetInventoryItemLink("player", slot.id)
      local name, _, quality, ilvl, _, _, _, _, _, _, _, _, _, _, expacID = C_Item.GetItemInfo(itemLink or itemID)

      if name then
        -- Effective ilvl priority:
        --   1. C_Item.GetCurrentItemLevel on the equipped slot — the live value of
        --      this exact item instance. Required for level-scaling gear such as
        --      heirlooms, where the link alone reports the unscaled level.
        --   2. C_Item.GetDetailedItemLevelInfo(link) — link-derived, includes
        --      upgrade rank but ignores scaling.
        --   3. ilvl from C_Item.GetItemInfo — base level, last resort.
        local effectiveIlvl
        local location = ItemLocation:CreateFromEquipmentSlot(slot.id)
        if C_Item.DoesItemExist(location) then
          effectiveIlvl = C_Item.GetCurrentItemLevel(location)
        end
        if (not effectiveIlvl or effectiveIlvl <= 0) and itemLink then
          effectiveIlvl = C_Item.GetDetailedItemLevelInfo(itemLink)
        end
        effectiveIlvl = effectiveIlvl or ilvl or 0

        local prevSlot = specSlots[skey]
        local prevQ = prevSlot and prevSlot.id == itemID and prevSlot.quality or nil
        local finalQ = math.max(quality or 0, prevQ or 0)
        if finalQ == 0 then finalQ = 1 end

        -- Upgrade track is intentionally not stored — GI.GetSlotUpgrade derives
        -- it from the link at display time so a season change needs no rescan.
        specSlots[skey] = {
          id      = itemID,
          link    = itemLink,
          name    = name,
          ilvl    = effectiveIlvl,
          quality = finalQ,
          icon    = C_Item.GetItemIconByID(itemID),
          expac   = expacID,
          cached  = true,
        }
        if isLoginScan then
          local pkey = itemID .. ":" .. slot.id
          pendingItems[pkey] = { charKey = key, slotID = slot.id, itemID = itemID, specID = specIDKey }
          C_Item.RequestLoadItemDataByID(itemID)
        end
      else
        -- Item data not yet in cache; queue for deferred resolution.
        specSlots[skey] = {
          id      = itemID,
          link    = itemLink,
          name    = L["ITEM_LOADING"],
          ilvl    = (specSlots[skey] and specSlots[skey].ilvl) or 0,
          quality = (specSlots[skey] and specSlots[skey].quality) or 1,
          icon    = C_Item.GetItemIconByID(itemID),
          cached  = false,
        }
        local pkey = itemID .. ":" .. slot.id
        pendingItems[pkey] = { charKey = key, slotID = slot.id, itemID = itemID, specID = specIDKey }
        C_Item.RequestLoadItemDataByID(itemID)
      end
    end
  end

  specBucket.avgIlvl = FetchAvgIlvl() or specBucket.avgIlvl or 0
  local cr, cg, cb = GetItemLevelColor()
  specBucket.avgIlvlColor = { r = cr, g = cg, b = cb }
  specBucket.lastUpdate   = time()

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

function GI.DeleteAllCharacters()
  if not GI.db then return end
  local count = 0
  for _ in pairs(GI.db.characters) do count = count + 1 end
  GI.db.characters = {}
  ilvlReady = {}
  print("|cFF00C9FFGear|r|cFFFFFFFFInventory|r: " .. string.format(GI.L["DELETE_ALL_DONE"], count))
  GI.ScanCurrentCharacter()
end

-- Queues C_Item.RequestLoadItemDataByID for all gear slots of all saved characters.
-- Needed so item tooltips (gems, enchants, etc.) resolve from the client cache.
function GI.WarmUpAllCharacters()
  if not GI.db or not GI.db.characters then return end
  local queued = false
  for charKey, d in pairs(GI.db.characters) do
    if d and d.gear then
      for specID, bucket in pairs(d.gear) do
        if bucket.slots then
          for skey, slot in pairs(bucket.slots) do
            -- Upgrade track is derived on demand now; drop the values persisted
            -- by older versions so saved data matches the documented schema.
            slot.upTrack, slot.upCur, slot.upMax, slot.upRank = nil, nil, nil, nil
            local itemID = slot.id
            if itemID then
              local slotID = tonumber(skey:sub(2))
              local pkey   = itemID .. ":" .. slotID
              if not pendingItems[pkey] then
                pendingItems[pkey] = { charKey = charKey, slotID = slotID, itemID = itemID, specID = specID }
                C_Item.RequestLoadItemDataByID(itemID)
                queued = true
              end
            end
          end
        end
      end
    end
  end
  if queued then
    eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  end
end

function GI.DeleteCharacter(charKey)
  if not GI.db or not GI.db.characters[charKey] then return end
  GI.db.characters[charKey] = nil
  ilvlReady[charKey] = nil
end

function GI.DeleteSpec(charKey, specID)
  if not GI.db or not GI.db.characters[charKey] then return end
  local entry = GI.db.characters[charKey]
  if not entry.gear or not entry.gear[specID] then return end
  entry.gear[specID] = nil

  local ch = entry.character
  if ch and ch.specID == specID then
    -- Pick fallback spec with the most recent lastUpdate
    local fallback, fallbackTime = nil, 0
    for sid, bucket in pairs(entry.gear) do
      local t = bucket.lastUpdate or 0
      if t > fallbackTime then
        fallback     = sid
        fallbackTime = t
      end
    end
    ch.specID = fallback
  end
end

function GI.ConfirmDeleteCharacter(charKey)
  local d = GI.db and GI.db.characters[charKey]
  if not d then return end
  local ch = d.character or {}
  local r, g, b = GI.ClassRGB(ch.class)
  local displayName = (ch.name or "?") .. "-" .. (ch.realm or "?")
  local coloredName = string.format("|cFF%02X%02X%02X%s|r", r*255, g*255, b*255, displayName)
  local raceMarkup  = GI.RaceIconMarkup(ch.raceFile, ch.sex)
  local popup = StaticPopup_Show("GEARINVENTORY_DELETE_CHAR", coloredName)
  if popup then
    popup.data = { charKey = charKey, coloredName = coloredName, raceMarkup = raceMarkup }
  end
end

-- ─── Events ───────────────────────────────────────────────────────────────────

eventFrame = CreateFrame("Frame", "GearInventoryEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- left combat
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entered combat
eventFrame:RegisterEvent("PLAYER_DEAD")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)

  if event == "ADDON_LOADED" then
    if arg1 == addonName then
      GI.InitDB()
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
      C_Timer.After(0.5, function()
        ScanCharacterGear(true)
        GI.WarmUpAllCharacters()
      end)
    end

  elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
    C_Timer.After(0.5, ScanCharacterGear)

  elseif event == "PLAYER_REGEN_ENABLED" then
    -- Left combat: run the queued scan if one was deferred.
    if pendingScan then
      C_Timer.After(0.5, ScanCharacterGear)
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Entered combat: close main window if open.
    if GI.mainWindow and GI.mainWindow:IsShown() then
      GI.mainWindow:Hide()
    end

  elseif event == "PLAYER_DEAD" then
    -- Cancel any queued scan; no point scanning a dead character.
    pendingScan = false

  elseif event == "ITEM_DATA_LOAD_RESULT" then
    local itemID, success = arg1, arg2

    -- Collect all pending entries for this itemID
    local matched = {}
    for pkey, p in pairs(pendingItems) do
      if p.itemID == itemID then
        matched[pkey] = p
      end
    end
    if not next(matched) then return end

    if not success then
      for pkey, p in pairs(matched) do
        pendingItems[pkey] = nil
        if not HasPendingForChar(p.charKey) then
          ilvlReady[p.charKey] = true
        end
        if GI.OnCharacterDataUpdated then
          GI.OnCharacterDataUpdated(p.charKey)
        end
      end
      if not HasPending() then
        self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
      end
      return
    end

    for pkey, pending in pairs(matched) do
      local charData   = GI.db and GI.db.characters[pending.charKey]
      local specBucket = charData and pending.specID and charData.gear[pending.specID]
      local specSlots  = specBucket and specBucket.slots
      local skey       = "s" .. pending.slotID
      local slotData   = specSlots and specSlots[skey]
      local lookupKey  = (slotData and slotData.id == itemID and slotData.link) or itemID
      local name, link, quality, ilvl, _, _, _, _, _, _, _, _, _, _, expacID = C_Item.GetItemInfo(lookupKey)
      if not name then
        name, link, quality, ilvl, _, _, _, _, _, _, _, _, _, _, expacID = C_Item.GetItemInfo(itemID)
      end
      if name then
        if charData and specSlots then
          local slot = specSlots[skey]
          if slot and slot.id == itemID then
            local resolvedLink = slot.link or link
            -- This handler also fires for saved characters (WarmUpAllCharacters
            -- queues their slots too), so only refresh the item level when the
            -- live instance is readable — i.e. the current player still has this
            -- exact item in that slot. For anyone else the value captured by
            -- their own scan is authoritative: a link-derived level would clobber
            -- it, and is plain wrong for level-scaling gear such as heirlooms.
            local location   = ItemLocation:CreateFromEquipmentSlot(pending.slotID)
            local isLiveSlot = C_Item.DoesItemExist(location)
                           and C_Item.GetItemID(location) == itemID
            local effectiveIlvl
            if isLiveSlot then
              effectiveIlvl = C_Item.GetCurrentItemLevel(location)
              if (not effectiveIlvl or effectiveIlvl <= 0) and resolvedLink then
                effectiveIlvl = C_Item.GetDetailedItemLevelInfo(resolvedLink)
              end
            end

            slot.name    = name
            slot.link    = resolvedLink
            slot.quality = math.max(quality or 0, slot.quality or 0)
            if slot.quality == 0 then slot.quality = 1 end
            if effectiveIlvl and effectiveIlvl > 0 then
              slot.ilvl = effectiveIlvl
            elseif not slot.ilvl or slot.ilvl == 0 then
              -- Never scanned on that character; base level beats showing nothing.
              slot.ilvl = ilvl or 0
            end
            slot.icon    = C_Item.GetItemIconByID(itemID) or slot.icon
            slot.cached  = true
            slot.expac   = expacID or slot.expac
            -- FetchAvgIlvl() returns the current player's value only — skip for other chars.
            local myKey = UnitName("player") and GetRealmName()
              and (UnitName("player") .. "-" .. GetRealmName()) or nil
            if pending.charKey == myKey then
              local fresh = FetchAvgIlvl()
              if fresh then
                specBucket.avgIlvl = fresh
                local cr, cg, cb = GetItemLevelColor()
                specBucket.avgIlvlColor = { r = cr, g = cg, b = cb }
              end
            end
          end
        end
        pendingItems[pkey] = nil
      end

      if not HasPendingForChar(pending.charKey) then
        ilvlReady[pending.charKey] = true
      end

      if GI.OnCharacterDataUpdated then
        GI.OnCharacterDataUpdated(pending.charKey)
      end
    end

    if not HasPending() then
      self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
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
  print("|cFFFFFFFF---------|r")
  local _ver = GI.VERSION or ""
  local _base, _build = _ver:match("^(.-)#(.+)$")
  local _verStr = _base and _build
    and ("|cFFAAAAAA" .. _base .. "|r|cFF888888#" .. _build .. "|r")
    or  ("|cFFAAAAAA" .. _ver .. "|r")
  print("|cFF00C9FFGear|r|cFFFFFFFFInventory|r " .. _verStr .. " |cFFFFFFFF" .. _L["LOADED_MSG"] .. "|r")
  print("    " .. string.format(_L["CMD_TOGGLE"],  _L["ACT_TOGGLE_WINDOW"]))
  print("    " .. string.format(_L["CMD_OPTIONS"], _L["ACT_OPEN_SETTINGS"]))
  print("    " .. string.format(_L["CMD_MINIMAP"], _L["ACT_TOGGLE_MINIMAP"]))
  print("|cFFFFFFFF---------|r")
end)
