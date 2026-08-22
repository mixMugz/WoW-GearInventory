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

-- "Name-Realm" key of the character being played, matching how entries are keyed
-- in the DB. Returns nil when either half is unavailable, which the callers treat
-- as "no current character" rather than guessing.
function GI.PlayerKey()
  local name  = UnitName("player")
  local realm = GetRealmName()
  if not name or not realm then return nil end
  return name .. "-" .. realm
end

-- ─── Chat Output ──────────────────────────────────────────────────────────────
-- Every addon message goes through here, so the "debug messages" setting can
-- silence all of them from one place. Output stays on unless explicitly switched
-- off, which also means it works before the DB is initialised.

local CHAT_PREFIX = GI.NAME_MARKUP .. ": "

local function MessagesEnabled()
  return GI.Config.Get("debugMessages") ~= false
end

-- Prints an addon message behind the standard prefix.
function GI.Print(msg)
  if not MessagesEnabled() then return end
  print(CHAT_PREFIX .. msg)
end

-- Prints a line verbatim; the login banner builds its own layout.
function GI.PrintRaw(msg)
  if not MessagesEnabled() then return end
  print(msg)
end

-- Fills a GameTooltip-compatible object with the launcher tooltip: title plus
-- the click hints. Shared by the minimap button and the LDB broker so the two
-- cannot drift apart.
function GI.BuildLauncherTooltip(tip)
  local L = GI.L
  tip:AddLine(GI.NAME_MARKUP)
  tip:AddLine(" ")
  tip:AddLine("|cFFFFFFFF" .. L["TIP_CLICK"]       .. "|r " .. L["ACT_TOGGLE_WINDOW"], 1, 0.82, 0)
  tip:AddLine("|cFFFFFFFF" .. L["TIP_RIGHT_CLICK"] .. "|r " .. L["ACT_OPEN_INFO"],     1, 0.82, 0)
end

-- ─── Database ─────────────────────────────────────────────────────────────────
-- Initialisation and migrations live in Addons/db.lua (GI.InitDB).

-- ─── Item Cache ───────────────────────────────────────────────────────────────
-- C_Item.GetItemInfo returns nil for items absent from the client cache.
-- Such items are queued here and resolved via ITEM_DATA_LOAD_RESULT.

local pendingItems    = {} -- { [PendingKey()] = { charKey, slotID, itemID, specID } }
local pendingScan     = false  -- true when a scan was requested during combat/death
local pendingLoginScan = false -- true after PLAYER_LOGIN, cleared by PLAYER_ENTERING_WORLD

-- Queue key. The character has to be part of it: two saved characters can hold
-- the same item in the same slot, and a shared key would let the first one claim
-- the entry and leave the second stuck on its placeholder name.
local function PendingKey(charKey, itemID, slotID)
  return charKey .. ":" .. itemID .. ":" .. slotID
end

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
  if not GI.db then
    GI.Print(L["SCAN_FAILED"])
    return
  end

  -- Defer scan if in combat or dead; PLAYER_REGEN_ENABLED will retry.
  if InCombatLockdown() or UnitIsDeadOrGhost("player") then
    if not pendingScan then
      pendingScan = true
      GI.Print(L["SCAN_QUEUED"])
    end
    return
  end
  -- Remember whether this run is draining a deferred scan; only that case is
  -- worth announcing, since the user was told a scan was queued.
  local wasQueued = pendingScan
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

    -- An empty list means the spec API told us nothing, not that the character
    -- has no specs. Pruning against it would silently delete every saved bucket,
    -- so leave the data untouched and let a later scan do the work.
    if next(validSpecIDs) then
      for sid in pairs(d.gear) do
        if not validSpecIDs[sid] then
          d.gear[sid] = nil
        end
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
          local pkey = PendingKey(key, itemID, slot.id)
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
        local pkey = PendingKey(key, itemID, slot.id)
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

  -- Close the loop on a queued scan. Ordinary scans stay silent: they fire on
  -- every gear and spec change, and nobody asked for them.
  if wasQueued then
    GI.Print(L["SCAN_DONE"])
  end

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
  GI.Print(string.format(GI.L["DELETE_ALL_DONE"], count))
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
              local pkey   = PendingKey(charKey, itemID, slotID)
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
eventFrame:RegisterEvent("PLAYER_UNGHOST")         -- revived at the corpse
eventFrame:RegisterEvent("PLAYER_ALIVE")           -- resurrected without releasing

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

  elseif event == "PLAYER_REGEN_ENABLED"
      or event == "PLAYER_UNGHOST"
      or event == "PLAYER_ALIVE" then
    -- One of the two conditions that defer a scan has lifted: combat ended, or
    -- the player is no longer dead. ScanCharacterGear re-checks both itself and
    -- simply re-queues if the other one still holds.
    if pendingScan then
      C_Timer.After(0.5, ScanCharacterGear)
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Entered combat: close main window if open.
    if GI.mainWindow and GI.mainWindow:IsShown() then
      GI.mainWindow:Hide()
    end

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
            local myKey = GI.PlayerKey()
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
      end

      -- Clear the entry whichever way the lookup went. Nothing re-requests item
      -- data for it, so a pending entry kept past this point would never resolve
      -- and would hold ITEM_DATA_LOAD_RESULT registered for the whole session.
      pendingItems[pkey] = nil

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
  if cmd == "info" then
    GI.OpenOptions()        -- Options/main.lua
  else
    GI.ToggleMainWindow()   -- Addons/ui.lua
  end
end

local _L = GI.L
C_Timer.After(0.5, function()
  local _ver = GI.VERSION or ""
  local _base, _build = _ver:match("^(.-)#(.+)$")
  local _verStr = _base and _build
    and ("|cFFAAAAAA" .. _base .. "|r|cFF888888#" .. _build .. "|r")
    or  ("|cFFAAAAAA" .. _ver .. "|r")
  GI.PrintRaw(GI.NAME_MARKUP .. " " .. _verStr .. " |cFFFFFFFF" .. _L["LOADED_MSG"] .. "|r")
  GI.PrintRaw("|cFFFFFFFF---------|r")
  GI.PrintRaw("  " .. string.format(_L["CMD_TOGGLE"], _L["ACT_TOGGLE_WINDOW"]))
  GI.PrintRaw("  " .. string.format(_L["CMD_INFO"],   _L["ACT_OPEN_INFO"]))
  GI.PrintRaw("|cFFFFFFFF---------|r")
end)
