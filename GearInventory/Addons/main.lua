-- GearInventory/Addons/main.lua
-- Shared utilities, DB management, gear data collection,
-- events, slash commands, loaded message.

local addonName, GI = ...

-- ─── Shared Utilities ─────────────────────────────────────────────────────────

-- Deferred-load tracing, toggled by /gi trace. Saved rather than held in a
-- global, because what it is for is the login sequence -- and a global does not
-- survive the reload that produces one.
--
-- Kept out of the options panel: a diagnostic, not a setting.
function GI.TraceEnabled()
  return GI.Config.Get("traceLoad") == true
end

function GI.Trace(fmt, ...)
  if not GI.TraceEnabled() then return end
  print("|cFF00C9FFGI|r " .. string.format(fmt, ...))
end

-- Returns r, g, b (0–1) for a class token. Uses WoW's built-in RAID_CLASS_COLORS.
function GI.ClassRGB(classToken)
  local c = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
  return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

-- Width of one space in a FontString's own font.
--
-- Measured as the difference between two strings rather than from a lone space,
-- which some fonts report as zero width. Cached per font, because the callers
-- measure in different ones and a space in a gear row is not a space in a
-- tooltip. The text is put back, so a live FontString can be used.
local spaceWidths = {}

function GI.SpaceWidth(fs)
  local path, size = fs:GetFont()
  local key = tostring(path) .. ":" .. tostring(size)

  local cached = spaceWidths[key]
  if cached then return cached end

  local prev = fs:GetText()
  fs:SetText("i i")
  local withGap = fs:GetStringWidth()
  fs:SetText("ii")
  local width = withGap - fs:GetStringWidth()
  fs:SetText(prev or "")

  if width <= 0 then width = 4 end
  spaceWidths[key] = width
  return width
end

-- Opening colour escape for an r,g,b triple. Colours are 0-1 floats throughout
-- the addon while the escape wants bytes, so the conversion lives here rather
-- than at each call site.
function GI.ColorCode(r, g, b)
  return string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
end

-- The same, wrapped around a piece of text.
function GI.Colorize(text, r, g, b)
  return GI.ColorCode(r, g, b) .. text .. "|r"
end

-- "Name-Realm" as shown to the player. GI.PlayerKey builds the same shape for
-- the character being played, but that one keys the database and must not pick
-- up placeholders.
function GI.DisplayName(ch)
  return (ch.name or "?") .. "-" .. (ch.realm or "?")
end

-- The same pair where a row carries both in one FontString: the name in class
-- colour, the realm behind it dimmed. Size cannot vary inside a single string,
-- so colour is the only way to push the realm back -- and it has to go back,
-- since at equal weight the realm reads as loudly as the name it repeats down
-- the whole list.
local REALM_DIM = "|cFF737373"

function GI.DisplayNameMarkup(ch, r, g, b)
  local name = GI.Colorize(ch.name or "?", r, g, b)
  if not ch.realm then return name end
  return name .. REALM_DIM .. "-" .. ch.realm .. "|r"
end

-- ─── Race Icons ───────────────────────────────────────────────────────────────
-- Cached per race+sex: every gear row, tooltip line and options row asks for
-- the same handful of combinations. Sex comes from UnitSex -- 1 is unknown,
-- 2 male, 3 female -- and anything but 3 is drawn male.
local raceIconCache = {}

-- race (from UnitRace) → atlas token override.
-- Used when the race file name does not match the texture atlas token.
local RACE_ATLAS_TOKEN = {
  ["harronir"]           = "haranir",
  ["earthendwarf"]       = "earthen",
  ["lightforgeddraenei"] = "lightforged",
  ["zandalaritroll"]     = "zandalari",
  ["highmountaintauren"] = "highmountain",
  ["scourge"]            = "undead",
}

-- Atlas name for a race icon. nil only when race itself is nil: the last resort
-- below builds a name whether or not the atlas exists, because SetAtlas draws
-- nothing rather than erroring on a name the client does not know.
--
-- The engine offers nothing for this. C_CreatureInfo.GetRaceInfo carries only
-- raceName, clientFileString and raceID, and Blizzard's own code never assembles
-- a raceicon name anywhere in the UI source, so the name is built by hand.
--
-- Exactly two spellings exist, measured with C_Texture.GetAtlasExists on human:
-- "raceicon128-<token>-<sex>" and "raceicon-<token>-<sex>". A "raceicon64-"
-- prefix, an underscore spelling and the bare token all answered false. The 128
-- variant is asked for first -- it scales down to the 14px the rows draw without
-- softening.
function GI.RaceAtlas(race, sex)
  if not race then return nil end

  local cacheKey = race .. (sex or 2)
  if raceIconCache[cacheKey] ~= nil then
    return raceIconCache[cacheKey] ~= "" and raceIconCache[cacheKey] or nil
  end

  local sexStr     = (sex == 3) and "female" or "male"
  local atlasToken = RACE_ATLAS_TOKEN[race:lower()] or race:lower()
  local token      = atlasToken .. "-" .. sexStr

  -- GetAtlasExists answers a plain boolean. GetAtlasInfo, which this used to
  -- call, builds a whole AtlasInfo table per candidate only to be tested for nil.
  local function ValidAtlas(name)
    return C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(name) and name or nil
  end

  local atlas = ValidAtlas("raceicon128-" .. token) or ValidAtlas("raceicon-" .. token)

  -- Last resort: hand back the name unvalidated. C_Texture may not list a race
  -- added after this build, and SetAtlas draws nothing on a name it does not know.
  if not atlas then
    atlas = "raceicon-" .. token
  end

  raceIconCache[cacheKey] = atlas or ""
  return atlas
end

-- Faction emblem atlas, or nil when the faction is unknown.
--
-- A Pandaren created without a side is "Neutral" until the starting experience
-- ends. The game draws no emblem for them at all, but a hole in a column that
-- every other row fills reads as a fault, so they get the free-for-all marker
-- from the same set instead -- it sits and scales like the other two.
function GI.FactionAtlas(faction)
  if faction == "Horde"    then return GI.ATLAS.FACTION_HORDE    end
  if faction == "Alliance" then return GI.ATLAS.FACTION_ALLIANCE end
  if faction == "Neutral"  then return GI.ATLAS.FACTION_NEUTRAL  end
  return nil
end

-- Faction tint, falling back to the neutral grey for a faction the table does
-- not know -- including nil, which is what a character saved before the field
-- existed reports.
function GI.FactionRGB(faction)
  local c = GI.FACTION_COLORS[faction] or GI.FACTION_COLORS.Neutral
  return c[1], c[2], c[3]
end

function GI.RaceIconMarkup(race, sex, size)
  local atlas = GI.RaceAtlas(race, sex)
  if not atlas then return "" end
  size = size or 14
  return "|A:" .. atlas .. ":" .. size .. ":" .. size .. "|a "
end

-- ─── Circular Icons ──────────────────────────────────────────────────────────
-- Race and specialization portraits are drawn the same way throughout: a square
-- icon rounded off by a mask, sitting inside a ring. Both halves live here so
-- the six places that draw one cannot drift apart.

-- Rounds a texture off with the portrait mask. Returns the mask, which callers
-- rarely need -- the texture keeps working on its own.
function GI.MaskCircle(parent, tex)
  local mask = parent:CreateMaskTexture()
  mask:SetAllPoints(tex)
  mask:SetTexture(GI.TEX.PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  tex:AddMaskTexture(mask)
  return mask
end

-- A framed circular icon, returned unanchored with .icon and .border on it.
-- The caller places the frame and gives .icon its texture or atlas; .border
-- takes SetVertexColor wherever the ring carries a class colour.
--
-- The texture coordinates trim the border baked into most icon art, which is
-- what stops the mask cutting through a visible frame.
function GI.CreateCircleIcon(parent, size, borderSize)
  borderSize = borderSize or size + 2

  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  GI.MaskCircle(f, icon)

  local border = f:CreateTexture(nil, "OVERLAY")
  border:SetSize(borderSize, borderSize)
  border:SetPoint("CENTER")
  border:SetAtlas(GI.ATLAS.RACE_BORDER)

  f.icon, f.border = icon, border
  return f
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

-- Every saved specialization of a character, as { specID, bucket, name, icon },
-- sorted by ID -- pairs() over the gear table has no order, and without sorting
-- the entries shuffle between openings.
--
-- name is nil for the initial specialization a character carries before
-- choosing one, so each caller puts in whatever suits its own layout.
function GI.SpecList(charData)
  local specs = {}
  if not (charData and charData.gear) then return specs end

  for specID, bucket in pairs(charData.gear) do
    if specID ~= 0 then
      local name, icon = GI.SpecInfo(specID)
      specs[#specs + 1] = { specID = specID, bucket = bucket, name = name, icon = icon }
    end
  end

  table.sort(specs, function(a, b) return a.specID < b.specID end)
  return specs
end

-- False for the initial spec a character carries before choosing one. That spec
-- has a real ID and a class icon, so nothing about it looks placeholder-like --
-- the empty name is the only thing the client gives us to tell them apart.
--
-- Such a character has no armor or weapon profile to judge gear against, so
-- recommendations skip them and the panel greys their checkbox out.
function GI.IsRealSpec(specID)
  return specID ~= nil and GI.SpecInfo(specID) ~= nil
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

-- ─── Tooltip Line Fonts ───────────────────────────────────────────────────────
-- GameTooltip pools its line FontStrings for the whole session, so a font set
-- on one is inherited by every later tooltip that reaches the same line index --
-- Blizzard's own included. Nothing resets it: an explicit SetFont outlives
-- ClearLines, SetHyperlink and SetUnit alike. So anything that shrinks a line
-- has to hand it back, and both callers here go through this pair.

local tooltipFonts = {}

-- A font object at the given size, derived from the tooltip's own font so it
-- keeps the player's face and outline. Cached: the font never changes.
function GI.TooltipFont(size)
  local font = tooltipFonts[size]
  if font then return font end

  font = CreateFont("GearInventoryTooltipFont" .. size)
  local path, _, flags = GameTooltipText:GetFont()
  if path then font:SetFont(path, size, flags) end

  tooltipFonts[size] = font
  return font
end

local borrowedLines = {}

-- Sets a tooltip line's font and remembers it for GI.RestoreTooltipFonts.
function GI.SetTooltipLineFont(fs, font)
  if not fs then return end
  borrowedLines[#borrowedLines + 1] = fs
  fs:SetFontObject(font)
end

-- Hands every borrowed line back to the tooltip's own font object. Cheap to
-- call when nothing was borrowed, so callers need not track that themselves.
function GI.RestoreTooltipFonts()
  for i = #borrowedLines, 1, -1 do
    borrowedLines[i]:SetFontObject(GameTooltipText)
    borrowedLines[i] = nil
  end
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
-- Initialisation lives in Addons/db.lua (GI.InitDB). There are no migrations.

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

-- The event frame is created at the bottom of the file, but the queue below
-- registers events on it, so the name has to exist by then.
local eventFrame

-- True while any of a character's slots is still waiting on the client. Drives
-- the greyed-out average in the list: asked once per row instead of walking
-- sixteen slots through C_Item.GetItemInfo on every redraw.
function GI.IsCharLoading(charKey)
  for _, p in pairs(pendingItems) do
    if p.charKey == charKey then return true end
  end
  return false
end

-- Opening the window queues every slot of every character, and each answer
-- would otherwise redraw the whole list on its own. Collect them and draw once
-- shortly after the flurry stops.
local REDRAW_DELAY   = 0.1
local dirtyChars     = {}
local dirtyScheduled = false

local function MarkCharDirty(charKey)
  if charKey then dirtyChars[charKey] = true end
  if dirtyScheduled then return end
  dirtyScheduled = true

  C_Timer.After(REDRAW_DELAY, function()
    dirtyScheduled = false
    local keys = dirtyChars
    dirtyChars = {}
    if not GI.OnCharacterDataUpdated then return end

    -- The callback redraws the whole list either way and only reads the key to
    -- decide whether the open gear panel needs rebuilding, so one call carrying
    -- the selected character covers the batch.
    local selected
    for key in pairs(keys) do
      if GI.IsMainWindowSelection and GI.IsMainWindowSelection(key) then
        selected = key
      end
    end
    GI.OnCharacterDataUpdated(selected)
  end)
end

-- Puts one slot in the queue and asks the client for its data. Returns true if
-- the request went out, false if that slot was already queued.
--
-- The event is registered before the request, never after: ITEM_DATA_LOAD_RESULT
-- fires synchronously for an item the client already holds, so a request sent
-- while the event is unregistered answers into nothing and strands its queue
-- entry for the rest of the session. Re-registering an event is a no-op.
--
-- The link is what gets asked for when there is one. RequestLoadItemDataByID
-- takes an ItemInfo, which is an id or a link, and the two are not the same
-- item to the client: an id loads the base item, while the panel reads names off
-- the saved link, bonuses and all, which loads separately. Warming the id and
-- reading the link left every character cold on its first open.
--
-- The queue stays keyed by id either way: the event reports an id, so that is
-- what the answer can be matched on.
local function QueueItem(charKey, itemID, slotID, specID, link)
  local pkey = PendingKey(charKey, itemID, slotID)
  if pendingItems[pkey] then return false end

  eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  pendingItems[pkey] = { charKey = charKey, slotID = slotID, itemID = itemID, specID = specID }
  C_Item.RequestLoadItemDataByID(link or itemID)
  GI.Trace("queue %s s%d id=%d by=%s", charKey, slotID, itemID, link and "link" or "id")
  return true
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
  local _, class          = UnitClass("player")
  local _, race           = UnitRace("player")
  local sex               = UnitSex("player")
  local faction           = UnitFactionGroup("player")
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
        race        = race,
        sex         = sex,
        faction     = faction,
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
  d.character.race        = race
  d.character.sex         = sex
  d.character.faction     = faction
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
      local name, _, quality, ilvl = C_Item.GetItemInfo(itemLink or itemID)

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
          ilvl    = effectiveIlvl,
          quality = finalQ,
          icon    = C_Item.GetItemIconByID(itemID),
        }
        GI.Trace("scan %s s%d id=%d READ ok", key, slot.id, itemID)
        if isLoginScan then
          QueueItem(key, itemID, slot.id, specIDKey, itemLink)
        end
      else
        -- Item data not yet in cache; queue for deferred resolution.
        specSlots[skey] = {
          id      = itemID,
          link    = itemLink,
          ilvl    = (specSlots[skey] and specSlots[skey].ilvl) or 0,
          quality = (specSlots[skey] and specSlots[skey].quality) or 1,
          icon    = C_Item.GetItemIconByID(itemID),
        }
        GI.Trace("scan %s s%d id=%d COLD link=%s", key, slot.id, itemID,
          itemLink and "y" or "n")
        QueueItem(key, itemID, slot.id, specIDKey, itemLink)
      end
    end
  end

  specBucket.avgIlvl = FetchAvgIlvl() or specBucket.avgIlvl or 0
  local cr, cg, cb = GetItemLevelColor()
  specBucket.avgIlvlColor = { r = cr, g = cg, b = cb }
  specBucket.lastUpdate   = time()

  -- Close the loop on a queued scan. Ordinary scans stay silent: they fire on
  -- every gear and spec change, and nobody asked for them.
  if wasQueued then
    GI.Print(L["SCAN_DONE"])
  end

  if GI.OnCharacterDataUpdated then
    GI.OnCharacterDataUpdated(key)
  end
end

-- Changing a full outfit fires PLAYER_EQUIPMENT_CHANGED once per slot, and a
-- timer each would run the same whole-character scan sixteen times over. Keep
-- one timer and push it back instead, so the scan runs once the changes stop.
local scanTimer

local function ScheduleScan()
  if scanTimer then scanTimer:Cancel() end
  scanTimer = C_Timer.NewTimer(0.5, function()
    scanTimer = nil
    ScanCharacterGear()
  end)
end

-- Public entry point for the force-rescan button in ui.lua.
GI.ScanCurrentCharacter = ScanCharacterGear

function GI.DeleteAllCharacters()
  if not GI.db then return end
  local count = 0
  for _ in pairs(GI.db.characters) do count = count + 1 end
  GI.db.characters = {}
  GI.Print(string.format(GI.L["DELETE_ALL_DONE"], count))
  GI.ScanCurrentCharacter()
end

-- An item the panel finds cold at draw time is waited on by the panel itself,
-- through ItemMixin:ContinueOnItemLoad -- see AwaitItem in ui.lua. The queue
-- here stays for the login warm-up and the scan, which resolve saved data
-- rather than draw it.

-- Queues C_Item.RequestLoadItemDataByID for all gear slots of all saved characters.
-- Needed so item tooltips (gems, enchants, etc.) resolve from the client cache.
function GI.WarmUpAllCharacters()
  if not GI.db or not GI.db.characters then return end

  local queued, total = 0, 0
  for charKey, d in pairs(GI.db.characters) do
    if d and d.gear then
      for specID, bucket in pairs(d.gear) do
        if bucket.slots then
          for skey, slot in pairs(bucket.slots) do
            if slot.id then
              total = total + 1
              if QueueItem(charKey, slot.id, tonumber(skey:sub(2)), specID, slot.link) then
                queued = queued + 1
              end
            end
          end
        end
      end
    end
  end
  GI.Trace("warmup: queued %d of %d slots", queued, total)
end

function GI.DeleteCharacter(charKey)
  if not GI.db or not GI.db.characters[charKey] then return end
  GI.db.characters[charKey] = nil
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

-- Opens the "remove this specialization?" confirmation.
--
-- Both entry points -- the character list context menu and the Saved Characters
-- picker -- come through here, because the dialog reads eight fields off
-- popup.data and two copies of that table drift apart quietly.
--
-- coloredName is passed in rather than built: the context menu heads its popup
-- with the character name alone, the picker with name and realm.
function GI.ConfirmDeleteSpec(charKey, spec, ch, coloredName)
  local specName    = spec.name or "?"
  local coloredSpec = GI.Colorize(specName, GI.ClassRGB(ch.class))

  local popup = StaticPopup_Show("GEARINVENTORY_DELETE_SPEC", coloredSpec, coloredName)
  if not popup then return end

  popup.data = {
    charKey     = charKey,
    specID      = spec.specID,
    specName    = specName,
    specIcon    = spec.icon,
    race        = ch.race,
    sex         = ch.sex,
    coloredName = coloredName,
    coloredSpec = coloredSpec,
  }
end

function GI.ConfirmDeleteCharacter(charKey)
  local d = GI.db and GI.db.characters[charKey]
  if not d then return end
  local ch = d.character or {}
  local r, g, b = GI.ClassRGB(ch.class)
  local displayName = GI.DisplayName(ch)
  local coloredName = GI.Colorize(displayName, r, g, b)
  local raceMarkup  = GI.RaceIconMarkup(ch.race, ch.sex)
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
eventFrame:RegisterEvent("UI_SCALE_CHANGED")       -- interface scale slider moved
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")   -- resolution or window size changed

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
    ScheduleScan()

  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    -- The window's own scale is derived from both, so it is recomputed rather
    -- than kept from login. Does nothing until the window has been built.
    if GI.ApplyMainWindowScale then GI.ApplyMainWindowScale() end

  elseif event == "PLAYER_REGEN_ENABLED"
      or event == "PLAYER_UNGHOST"
      or event == "PLAYER_ALIVE" then
    -- One of the two conditions that defer a scan has lifted: combat ended, or
    -- the player is no longer dead. ScanCharacterGear re-checks both itself and
    -- simply re-queues if the other one still holds.
    if pendingScan then
      ScheduleScan()
    end
    -- Combat ended: put the window back if combat was what took it down. Does
    -- nothing after a rez, which is the other way into this branch.
    if event == "PLAYER_REGEN_ENABLED" and GI.RestoreMainWindowAfterCombat then
      GI.RestoreMainWindowAfterCombat()
    end

  elseif event == "PLAYER_REGEN_DISABLED" then
    -- Entered combat: hide the main window, if the option asks for it.
    if GI.HideMainWindowForCombat then GI.HideMainWindowForCombat() end

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
        MarkCharDirty(p.charKey)
      end
      if not HasPending() then
        self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
      end
      return
    end

    local myKey = GI.PlayerKey()

    for pkey, pending in pairs(matched) do
      local charData   = GI.db and GI.db.characters[pending.charKey]
      local specBucket = charData and pending.specID and charData.gear[pending.specID]
      local specSlots  = specBucket and specBucket.slots
      local skey       = "s" .. pending.slotID
      local slotData   = specSlots and specSlots[skey]
      local lookupKey  = (slotData and slotData.id == itemID and slotData.link) or itemID
      local name, link, quality, ilvl = C_Item.GetItemInfo(lookupKey)
      local via = "link"
      if not name then
        name, link, quality, ilvl = C_Item.GetItemInfo(itemID)
        via = name and "id" or "none"
      end
      GI.Trace("result %s s%d id=%d resolved=%s via=%s", pending.charKey,
        pending.slotID, itemID, name and "y" or "n", via)
      if name then
        if charData and specSlots then
          local slot = specSlots[skey]
          if slot and slot.id == itemID then
            -- Prefer the freshly resolved link. A link captured while the
            -- item was still loading carries an empty name and a placeholder
            -- quality, and writing it back would keep that pushed into every
            -- tooltip and export from then on.
            local resolvedLink = link or slot.link
            -- This handler also fires for saved characters (WarmUpAllCharacters
            -- queues their slots too), so only refresh the item level when the
            -- live instance is readable -- i.e. this is the played character and
            -- they still have this exact item in that slot. For anyone else the
            -- value captured by their own scan is authoritative: a link-derived
            -- level would clobber it, and is plain wrong for level-scaling gear
            -- such as heirlooms.
            --
            -- The character has to be checked as well as the item. Equipment
            -- slots only ever answer for whoever is being played, and an alt can
            -- hold the same itemID in the same slot -- upgrading a track moves
            -- the bonusID, not the item -- so matching on the item alone writes
            -- the played character's level onto theirs.
            local location, isLiveSlot
            if pending.charKey == myKey then
              location   = ItemLocation:CreateFromEquipmentSlot(pending.slotID)
              isLiveSlot = C_Item.DoesItemExist(location)
                       and C_Item.GetItemID(location) == itemID
            end
            local effectiveIlvl
            if isLiveSlot then
              effectiveIlvl = C_Item.GetCurrentItemLevel(location)
              if (not effectiveIlvl or effectiveIlvl <= 0) and resolvedLink then
                effectiveIlvl = C_Item.GetDetailedItemLevelInfo(resolvedLink)
              end
            end

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
            -- FetchAvgIlvl() returns the current player's value only — skip for other chars.
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
      MarkCharDirty(pending.charKey)
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
  if cmd == "trace" then
    local on = not GI.TraceEnabled()
    GI.Config.Set("traceLoad", on)
    GI.Print(on and GI.L["TRACE_ON"] or GI.L["TRACE_OFF"])
  elseif cmd == "info" then
    GI.OpenOptions()        -- Options/main.lua
  else
    GI.ToggleMainWindow()   -- Addons/ui.lua
  end
end

local _L = GI.L
C_Timer.After(0.5, function()
  local _ver = GI.VERSION or ""
  local _base, _build = _ver:match("^(.-)#(.+)$")
  local _verStr
  if _base and _build then
    _verStr = "|cFFFFD100" .. _base .. "|r|cFFFFFFFF#|r|cFF888888" .. _build .. "|r"
  else
    _verStr = "|cFFFFD100" .. _ver .. "|r"
  end
  GI.PrintRaw(GI.NAME_MARKUP .. " " .. _verStr .. " |cFFFFFFFF" .. _L["LOADED_MSG"] .. "|r")
  GI.PrintRaw("|cFFFFFFFF---------|r")
  GI.PrintRaw("  " .. string.format(_L["CMD_TOGGLE"], _L["ACT_TOGGLE_WINDOW"]))
  GI.PrintRaw("  " .. string.format(_L["CMD_INFO"],   _L["ACT_OPEN_INFO"]))
  GI.PrintRaw("|cFFFFFFFF---------|r")
end)
