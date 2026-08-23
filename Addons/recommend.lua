-- GearInventory/Addons/recommend.lua
-- Appends an "Upgrades" section to item tooltips: which saved characters an
-- unbound item would improve, and by how much.
--
-- Bind on pickup is never listed: it cannot reach another character, so naming
-- who it would suit is noise. Account-bound always is -- it cannot be sold, so
-- an alt is the only thing to do with it. Plain bind on equip sits between the
-- two and is the player's call, since selling it is a real alternative -- and it
-- is told apart by the tooltip's binding line, because warbound gear reports the
-- same bind type.
--
-- Depends on: GI.SPEC_INFO, GI.CLASS_ARMOR, GI.TEX.PORTRAIT_MASK,
--             GI.ATLAS.RACE_BORDER, GI.ATLAS.FACTION_* (Addons/core.lua),
--             GI.ClassRGB, GI.RaceAtlas, GI.SpecInfo (Addons/main.lua)

local addonName, GI = ...
local L = GI.L

local ICON_SIZE      = 14  -- faction and spec icons, inline in the line text
local RACE_ICON_SIZE = 10  -- race circle, a real texture laid over the line
local ARROW_HEIGHT   = 12

-- Arrows from the loot-upgrade toast. The family ships blue, green, orange and
-- purple, and no downward one at all -- so the loss arrow is the orange one
-- flipped and tinted. Orange, not green: SetVertexColor multiplies, and green
-- has no red channel to bring up.
local ARROW_UP_ATLAS    = "loottoast-arrow-green"
local ARROW_DOWN_ATLAS  = "loottoast-arrow-orange"
local ARROW_TRACK_ATLAS = "loottoast-arrow-blue"
local ARROW_DOWN_TINT   = { 1, 0.35, 0.35 }

-- Level for level nothing moves, so the marker is a dot rather than an arrow.
-- Filled, not a ring: hollow read as an outline next to two solid arrows. Both
-- candidates are near-grey and take a tint cleanly; the first is resolved at
-- first use because SetAtlas draws nothing at all for a name that does not
-- exist, which is indistinguishable from a positioning mistake.
local SAME_ATLASES = { "QuestObjective", "common-radiobutton-dot" }
local SAME_SIZE    = ARROW_HEIGHT  -- same visual weight as the arrows it replaces
local SAME_TINT    = { 1, 0.82, 0 }

local sameAtlas

local function SameAtlas()
  if sameAtlas then return sameAtlas end
  for i = 1, #SAME_ATLASES do
    if C_Texture.GetAtlasInfo(SAME_ATLASES[i]) then
      sameAtlas = SAME_ATLASES[i]
      return sameAtlas
    end
  end
  sameAtlas = SAME_ATLASES[#SAME_ATLASES]
  return sameAtlas
end

-- ─── Binding ──────────────────────────────────────────────────────────────────
-- The tooltip's own binding line is the authority here, because bindType is
-- wrong in both directions: warbound gear reports OnEquip exactly like a plain
-- bind-on-equip piece, and older account-bound gear reports OnAcquire exactly
-- like a bind-on-pickup one. Measured on six live items, all of which said
-- "bind to account" in the tooltip while reporting OnAcquire.
--
-- Comparisons go against the client's own globals rather than literals, so the
-- wording is whatever language the player runs.
--
-- bindType still stands in when an item shows no binding line at all.
local TRADEABLE_BIND = {
  [Enum.ItemBind.None]                       = true,
  [Enum.ItemBind.OnEquip]                    = true,
  [Enum.ItemBind.ToWoWAccount]               = true,
  [Enum.ItemBind.ToBnetAccount]              = true,
  [Enum.ItemBind.ToBnetAccountUntilEquipped] = true,
}

-- Text of the tooltip's binding line, or nil when it has none.
local function BindingLine(data)
  if not (data and data.lines) then return nil end
  for i = 1, #data.lines do
    local line = data.lines[i]
    if line.type == Enum.TooltipDataLineType.ItemBinding then
      return line.leftText
    end
  end
  return nil
end

-- True for plain bind-on-equip gear, which the Ignore option hides because it
-- can be sold instead of handed on. Warbound gear reports the same bindType, so
-- only the line tells them apart.
local function IsBindOnEquip(data)
  return BindingLine(data) == ITEM_BIND_ON_EQUIP
end

-- Bind on pickup is the only binding that rules an item out: everything else --
-- account-bound, warbound, warbound until used, bind on equip -- can still
-- reach another character.
local function BindingAllows(data, bindType)
  local text = BindingLine(data)
  if text then
    if ITEM_BIND_ON_PICKUP and text == ITEM_BIND_ON_PICKUP then return false end
    return true
  end
  return TRADEABLE_BIND[bindType] == true
end

-- ─── Equip location → equipment slot IDs ─────────────────────────────────────
-- Paired slots list both: the item is compared against whichever of the two is
-- weaker, since that is the one it would actually replace.
local EQUIP_SLOTS = {
  INVTYPE_HEAD            = { 1 },
  INVTYPE_NECK            = { 2 },
  INVTYPE_SHOULDER        = { 3 },
  INVTYPE_CHEST           = { 5 },
  INVTYPE_ROBE            = { 5 },
  INVTYPE_WAIST           = { 6 },
  INVTYPE_LEGS            = { 7 },
  INVTYPE_FEET            = { 8 },
  INVTYPE_WRIST           = { 9 },
  INVTYPE_HAND            = { 10 },
  INVTYPE_CLOAK           = { 15 },
  INVTYPE_FINGER          = { 11, 12 },
  INVTYPE_TRINKET         = { 13, 14 },
  INVTYPE_WEAPON          = { 16, 17 },
  INVTYPE_2HWEAPON        = { 16 },
  INVTYPE_WEAPONMAINHAND  = { 16 },
  INVTYPE_RANGED          = { 16 },
  INVTYPE_RANGEDRIGHT     = { 16 },
  INVTYPE_WEAPONOFFHAND   = { 17 },
  INVTYPE_SHIELD          = { 17 },
  INVTYPE_HOLDABLE        = { 17 },
}

-- Slots carrying no armor or weapon restriction: everyone wears necks, rings,
-- trinkets and cloaks whatever their proficiency.
local UNRESTRICTED_SLOT = {
  [2] = true, [11] = true, [12] = true, [13] = true, [14] = true, [15] = true,
}

-- ─── Item subclass → GI.SPEC_INFO vocabulary ─────────────────────────────────
-- GI.SPEC_INFO names weapons in its own words; these map Blizzard's subclass IDs
-- onto them. Anything absent is not equippable gear for a spec (fishing poles,
-- thrown, obsolete classes) and drops out on lookup.
local WEAPON_NAME = {
  [Enum.ItemWeaponSubclass.Axe1H]     = "Axe",
  [Enum.ItemWeaponSubclass.Axe2H]     = "Axe2H",
  [Enum.ItemWeaponSubclass.Bows]      = "Bow",
  [Enum.ItemWeaponSubclass.Guns]      = "Gun",
  [Enum.ItemWeaponSubclass.Mace1H]    = "Mace",
  [Enum.ItemWeaponSubclass.Mace2H]    = "Mace2H",
  [Enum.ItemWeaponSubclass.Polearm]   = "Polearm",
  [Enum.ItemWeaponSubclass.Sword1H]   = "Sword",
  [Enum.ItemWeaponSubclass.Sword2H]   = "Sword2H",
  [Enum.ItemWeaponSubclass.Warglaive] = "Warglaive",
  [Enum.ItemWeaponSubclass.Staff]     = "Staff",
  [Enum.ItemWeaponSubclass.Unarmed]   = "Fist",
  [Enum.ItemWeaponSubclass.Dagger]    = "Dagger",
  [Enum.ItemWeaponSubclass.Crossbow]  = "Crossbow",
  [Enum.ItemWeaponSubclass.Wand]      = "Wand",
}

-- Matches the values in GI.CLASS_ARMOR. Cosmetic, Libram, Idol and the rest are
-- absent on purpose: they are not armor a spec can be judged against.
local ARMOR_NAME = {
  [Enum.ItemArmorSubclass.Cloth]   = "Cloth",
  [Enum.ItemArmorSubclass.Leather] = "Leather",
  [Enum.ItemArmorSubclass.Mail]    = "Mail",
  [Enum.ItemArmorSubclass.Plate]   = "Plate",
}

-- ─── Primary stat ─────────────────────────────────────────────────────────────
-- C_Item.GetItemStats keys its table by the *name* of the global string rather
-- than its value, so these are the same in every locale.
local PRIMARY_STAT = {
  ITEM_MOD_STRENGTH_SHORT  = "STR",
  ITEM_MOD_AGILITY_SHORT   = "AGI",
  ITEM_MOD_INTELLECT_SHORT = "INT",
}

-- The primary stats an item carries, or nil when it carries none.
--
-- An agility dagger is no use to a warlock however well the class handles
-- daggers, which is what checking the weapon type alone kept missing.
--
-- Measured caveat: this answers for the player, not for the item. An omni-stat
-- trinket carrying agility, intellect and strength at once reported only agility
-- to a druid -- so the answer cannot be trusted for another character's spec.
-- SuitsSpec therefore uses it on armor and weapons only, where a fixed stat is
-- the rule and omni items are not.
--
-- Returning nil for "none found" also means a wrong key here degrades to the
-- old behaviour rather than quietly hiding every character.
local function PrimaryStats(link)
  local stats = C_Item.GetItemStats(link)
  if not stats then return nil end

  local found
  for key, value in pairs(stats) do
    local stat = PRIMARY_STAT[key]
    if stat and (tonumber(value) or 0) > 0 then
      found = found or {}
      found[stat] = true
    end
  end
  return found
end

-- ─── Suitability ──────────────────────────────────────────────────────────────

-- Class token -> numeric class ID, which is what DoesItemContainSpec wants.
-- Read from the game rather than written out, so a new class needs no edit here.
local classIDs

local function ClassID(token)
  if not classIDs then
    classIDs = {}
    for i = 1, GetNumClasses() do
      local _, file, id = GetClassInfo(i)
      if file then classIDs[file] = id end
    end
  end
  return classIDs[token]
end

local function Contains(list, value)
  if not list then return false end
  for i = 1, #list do
    if list[i] == value then return true end
  end
  return false
end

-- True when a spec could actually wear this item in that slot.
--
-- C_Item.DoesItemContainSpec is the authority: it takes an explicit class and
-- spec and answers for that one rather than for whoever is looking, which is
-- what nothing else here manages. Measured on a druid -- a druid weapon came
-- back true for feral and false for a warlock, while an omni-stat trinket came
-- back true for both. That single call covers armor proficiency, weapon type
-- and primary stat together, and gets the omni-stat case right, which reading
-- the stat table never could.
--
-- The rules below stand in only when the class token maps to no class ID, which
-- means the game has a class this addon has not met. They need GI.SPEC_INFO,
-- and a spec missing from it can only be dropped -- which is exactly why the
-- API path takes the class straight off the character instead: a specialization
-- Blizzard adds tomorrow keeps working without an edit here.
local function SuitsSpec(class, specID, slotID, item)
  local classID = ClassID(class)
  if classID and item.link then
    return C_Item.DoesItemContainSpec(item.link, classID, specID)
  end

  local spec = GI.SPEC_INFO[specID]
  if not spec then return false end

  if UNRESTRICTED_SLOT[slotID] then return true end
  if item.stats and not item.stats[spec.stat] then return false end

  local subclassID = item.subclassID
  classID = item.classID

  if classID == Enum.ItemClass.Armor then
    if subclassID == Enum.ItemArmorSubclass.Shield then
      return Contains(spec.oh, "Shield")
    end
    -- Off-hand holdables are Generic armor; only slot 17 reaches this line.
    if subclassID == Enum.ItemArmorSubclass.Generic then
      return Contains(spec.oh, "Offhand")
    end
    local armor = ARMOR_NAME[subclassID]
    if not armor then return false end
    return GI.CLASS_ARMOR[spec.class] == armor
  end

  if classID == Enum.ItemClass.Weapon then
    local name = WEAPON_NAME[subclassID]
    if not name then return false end
    if slotID == 17 then return Contains(spec.oh, name) end
    return Contains(spec.mh, name)
  end

  return false
end

-- ─── Evaluation ───────────────────────────────────────────────────────────────

-- Equip locations that fill the off-hand as well as the main hand.
local TWO_HANDED = {
  INVTYPE_2HWEAPON    = true,
  INVTYPE_RANGED      = true,
  INVTYPE_RANGEDRIGHT = true,
}

-- Highest item level a piece can still reach. Gear off an upgrade track cannot
-- be pushed at all, so its ceiling is where it already stands -- which is what
-- makes last season's gear rank below a fresh item of a lower track.
--
-- The ceiling is a floor as much as a cap: some upgrades push an item past its
-- own track's top, so ilvlMax is not always the larger of the two.
local function CeilingOf(ilvl, track)
  if not (track and track.ilvlMax) then return ilvl end
  if track.ilvlMax > ilvl then return track.ilvlMax end
  return ilvl
end

-- Item level in a slot and its ceiling, or 0, 0 if nothing is there.
--
-- A two-handed weapon leaves the off-hand reading as empty in the saved data,
-- but nothing can go there without taking the two-hander off. Counted as empty
-- it would score every one-hander as a gain of its entire item level, since the
-- pair is judged by its weaker half.
local function EquippedLevels(bucket, slotID)
  local slots = bucket.slots
  local slot  = slots and slots["s" .. slotID]

  if not (slot and slot.ilvl) and slotID == 17 and slots and slots.s16 and slots.s16.id then
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(slots.s16.id)
    if TWO_HANDED[equipLoc] then slot = slots.s16 end
  end

  if not (slot and slot.ilvl) then return 0, 0 end
  return slot.ilvl, CeilingOf(slot.ilvl, GI.GetSlotUpgrade(slot))
end

-- Walks one character's enabled specs and reports where the item would help.
-- Returns the best item level gained and the list of specs that would gain it,
-- or nil when it is no upgrade anywhere.
--
-- incRecommend is the only hard filter on a character: the checkbox in the
-- Saved Characters panel exists for exactly this. Absent means enabled, which is
-- what the scan writes for a new spec.
local function EvaluateCharacter(item, entry, slotIDs, activeSpecOnly)
  if not entry.gear then return nil end

  local matches, best = {}, nil
  local character  = entry.character or {}
  local activeSpec = character.specID
  local class      = character.class

  for specID, bucket in pairs(entry.gear) do
    -- The initial spec a character carries before choosing one has no armor or
    -- weapon profile to judge gear against, so it is skipped. Asked of the game
    -- rather than of GI.SPEC_INFO, so a specialization this addon has never
    -- heard of still counts.
    local usable = GI.IsRealSpec(specID)
    if activeSpecOnly and specID ~= activeSpec then usable = false end
    if usable and bucket.incRecommend ~= false then
      -- Weakest matching slot: for rings and trinkets that is the one the item
      -- would displace, and it is the biggest honest gain.
      --
      -- A two-hander is the exception. It fills both weapon slots, so it is
      -- judged against the average of what is in them -- putting one on gives up
      -- the off-hand as well. The average, not the sum: the column is in item
      -- levels, and a doubled figure would not be one.
      local base, baseCeiling
      if item.twoHand and SuitsSpec(class, specID, 16, item) then
        local mh,  mhCap = EquippedLevels(bucket, 16)
        local oh,  ohCap = EquippedLevels(bucket, 17)
        base, baseCeiling = (mh + oh) / 2, (mhCap + ohCap) / 2
      else
        for i = 1, #slotIDs do
          local slotID = slotIDs[i]
          if SuitsSpec(class, specID, slotID, item) then
            local ilvl, cap = EquippedLevels(bucket, slotID)
            if not base or ilvl < base then base, baseCeiling = ilvl, cap end
          end
        end
      end

      if base then
        -- Floored, so a half-item-level average never rounds in the item's
        -- favour and reports a gain that is not quite there.
        local gain    = math.floor(item.ilvl - base)
        local capGain = math.floor(item.ceiling - baseCeiling)

        -- Listed when it wins now, or when its track can still take it past
        -- what they have -- the second case is the whole point of showing a
        -- piece that is currently the worse of the two.
        if gain > 0 or capGain > 0 then
          matches[#matches + 1] = {
            specID   = specID,
            gain     = gain,
            -- Marked only when the item is behind on item level today. A piece
            -- that already wins needs no argument made for it, and the marker
            -- then means one thing only: worse now, further later.
            potential = gain <= 0 and capGain > 0,
            isActive  = (specID == activeSpec),
          }
          if not best or gain > best then best = gain end
        end
      end
    end
  end

  if #matches == 0 then return nil end

  -- The active spec leads: it goes on the line carrying the character, and the
  -- rest follow underneath. pairs() over the gear table is unordered anyway, so
  -- this also stops the order shuffling between hovers.
  table.sort(matches, function(a, b)
    if a.isActive ~= b.isActive then return a.isActive end
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.specID < b.specID
  end)

  return best, matches
end

-- ─── Measurement ──────────────────────────────────────────────────────────────
-- The row is built from real widgets, so its text has to reserve room for them
-- and its columns have to be sized from the widest entry in the list. Both need
-- measuring in the font the line will actually use.

local measureFS, measureSmallFS

local function TextWidth(text)
  if not measureFS then
    measureFS = UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    measureFS:Hide()
  end
  measureFS:SetText(text)
  return measureFS:GetStringWidth()
end

-- The level is drawn in the small font, so measuring it in the normal one would
-- overstate its column.
local function SmallTextWidth(text)
  if not measureSmallFS then
    measureSmallFS = UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipTextSmall")
    measureSmallFS:Hide()
  end
  measureSmallFS:SetText(text)
  return measureSmallFS:GetStringWidth()
end

-- Measured as the difference between two strings rather than from a lone space,
-- which some fonts report as zero width. Cached — the font never changes.
local spaceW

local function SpaceWidth()
  if not spaceW then
    spaceW = TextWidth("i i") - TextWidth("ii")
    if spaceW <= 0 then spaceW = 4 end
  end
  return spaceW
end

-- ─── Row widget pool ──────────────────────────────────────────────────────────
-- Everything except the character name is a real widget laid over the line.
-- Padding a tooltip line with spaces cannot produce columns: a space is not the
-- width of a digit or an icon, so anything aligned that way drifts row to row.
--
-- Each row frame spans from the line left FontString to its right one. The right
-- FontString is anchored to the tooltip inner right edge, so its RIGHT is at the
-- same x on every line -- which is what makes the right-hand columns line up.
-- Anchoring by LEFT and RIGHT also centres the row vertically for free.
--
-- One pool per tooltip: GameTooltip and ItemRefTooltip can be up at the same
-- time, and a shared pool would let one of them hide the other widgets.

local RACE_FACTION_GAP = 2
local COL_GAP          = 4
-- Gap between the faction emblem and the name. Reserved space is quantised to
-- whole spaces, so the drawn gap lands a pixel or three above this number.
local NAME_GAP         = 2
local RULE_INSET       = 10  -- how far the rule stops short of the tooltip edge

local pools = {}

-- FontStrings whose font we replaced, and must hand back. GameTooltip reuses its
-- lines between tooltips: leave one shrunk and the next tooltip inherits it.
local shrunkLines = {}

-- A line carrying nothing but a rule does not need full line height, and that
-- height is the only thing setting the distance between the rule and the text
-- above and below it. Built at runtime so the size stays a number we can tune.
local ruleFont

local function RuleFont()
  if ruleFont then return ruleFont end
  ruleFont = CreateFont("GearInventoryRuleFont")
  local path, _, flags = GameTooltipText:GetFont()
  if path then ruleFont:SetFont(path, 6, flags) end
  return ruleFont
end

local function RestoreLines()
  for i = #shrunkLines, 1, -1 do
    shrunkLines[i]:SetFontObject(GameTooltipText)
    shrunkLines[i] = nil
  end
end

local function GetPool(tooltip)
  local pool = pools[tooltip]
  if not pool then
    pool = { rows = {}, usedRows = 0, rules = {}, usedRules = 0 }
    pools[tooltip] = pool
    tooltip:HookScript("OnHide", function()
      for i = 1, #pool.rows  do pool.rows[i]:Hide()  end
      for i = 1, #pool.rules do pool.rules[i]:Hide() end
      pool.usedRows, pool.usedRules = 0, 0
      RestoreLines()
    end)
  end
  return pool
end

local function ReleaseIcons(tooltip)
  RestoreLines()
  local pool = pools[tooltip]
  if not pool then return end
  for i = 1, #pool.rows  do pool.rows[i]:Hide()  end
  for i = 1, #pool.rules do pool.rules[i]:Hide() end
  pool.usedRows, pool.usedRules = 0, 0
end

-- Race and spec icons share the look: a masked circle inside a ring. Only the
-- race ring is class-coloured; the spec one is left as the art ships.
local function CreateCircle(parent, size)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local mask = f:CreateMaskTexture()
  mask:SetAllPoints(icon)
  mask:SetTexture(GI.TEX.PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  icon:AddMaskTexture(mask)

  local border = f:CreateTexture(nil, "OVERLAY")
  border:SetSize(size + 2, size + 2)
  border:SetPoint("CENTER")
  border:SetAtlas(GI.ATLAS.RACE_BORDER)

  f.icon, f.border = icon, border
  return f
end

local function AcquireRow(tooltip)
  local pool = GetPool(tooltip)
  pool.usedRows = pool.usedRows + 1

  local f = pool.rows[pool.usedRows]
  if f then return f end

  f = CreateFrame("Frame", nil, tooltip)
  f:SetHeight(ICON_SIZE)

  -- Right-aligned in a column sized to the widest level in the list, so the
  -- digits end on the same x and the column grows only when it has to.
  f.levelFS = f:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
  f.levelFS:SetJustifyH("RIGHT")
  f.levelFS:SetPoint("LEFT", f, "LEFT", 0, 0)

  f.race = CreateCircle(f, RACE_ICON_SIZE)
  f.race:SetPoint("LEFT", f.levelFS, "RIGHT", COL_GAP, 0)

  f.factionTex = f:CreateTexture(nil, "OVERLAY")
  f.factionTex:SetSize(ICON_SIZE, ICON_SIZE)
  f.factionTex:SetPoint("LEFT", f.race, "RIGHT", RACE_FACTION_GAP, 0)

  f.trackArrow = f:CreateTexture(nil, "OVERLAY")
  f.trackArrow:SetAtlas(ARROW_TRACK_ATLAS)

  f.trackFS = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
  f.trackFS:SetJustifyH("RIGHT")

  f.arrowTex = f:CreateTexture(nil, "OVERLAY")
  f.spec     = CreateCircle(f, RACE_ICON_SIZE)

  pool.rows[pool.usedRows] = f
  return f
end

-- Thin rule fading out at both ends. A gradient has two stops, so a fade in and
-- back out takes two textures meeting in the middle -- the same arrangement
-- Blizzard uses for the nameplate health bar edges.
local function AcquireRule(tooltip)
  local pool = GetPool(tooltip)
  pool.usedRules = pool.usedRules + 1

  local r = pool.rules[pool.usedRules]
  if r then return r end

  r = CreateFrame("Frame", nil, tooltip)
  r:SetHeight(1)

  local mid  = CreateColor(1, 1, 1, 0.35)
  local none = CreateColor(1, 1, 1, 0)

  local lt = r:CreateTexture(nil, "OVERLAY")
  lt:SetColorTexture(1, 1, 1, 1)
  lt:SetPoint("TOPLEFT",     r, "TOPLEFT", 0, 0)
  lt:SetPoint("BOTTOMRIGHT", r, "BOTTOM",  0, 0)
  lt:SetGradient("HORIZONTAL", none, mid)

  local rt = r:CreateTexture(nil, "OVERLAY")
  rt:SetColorTexture(1, 1, 1, 1)
  rt:SetPoint("TOPLEFT",     r, "TOP",         0, 0)
  rt:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
  rt:SetGradient("HORIZONTAL", mid, none)

  pool.rules[pool.usedRules] = r
  return r
end

-- Rules are sized once the tooltip has been laid out: their width comes from the
-- tooltip, which is not final while lines are still being added.
local pendingRules = {}

local function AddRule(tooltip)
  tooltip:AddLine(" ")
  local fs = _G[tooltip:GetName() .. "TextLeft" .. tooltip:NumLines()]
  if not fs then return end

  fs:SetFontObject(RuleFont())
  shrunkLines[#shrunkLines + 1] = fs

  local r = AcquireRule(tooltip)
  r:ClearAllPoints()
  r:SetPoint("LEFT", fs, "LEFT", 0, 0)
  r:Show()

  pendingRules[#pendingRules + 1] = { frame = r, tooltip = tooltip }
end

local function SizeRules()
  for i = #pendingRules, 1, -1 do
    local p = pendingRules[i]
    p.frame:SetWidth(math.max(1, p.tooltip:GetWidth() - RULE_INSET * 2))
    pendingRules[i] = nil
  end
end

-- ─── Rendering ────────────────────────────────────────────────────────────────

-- Sized from the atlas so an arrow keeps its own aspect at the height we want.
local atlasW = {}

local function ArrowWidth(atlas)
  local w = atlasW[atlas]
  if w then return w end

  local info = C_Texture.GetAtlasInfo(atlas)
  if info and info.width and info.height and info.height > 0 then
    w = math.max(1, math.floor(ARROW_HEIGHT * (info.width / info.height) + 0.5))
  else
    w = ARROW_HEIGHT
  end

  atlasW[atlas] = w
  return w
end

-- Which of the three outcomes a difference is. Shared so the string that gets
-- drawn and the string the column is measured from can never disagree.
local function GainKey(gain)
  if gain > 0 then return "REC_GAIN" end
  if gain < 0 then return "REC_LOSS" end
  return "REC_SAME"
end

-- Width of the gain marker column. The three markers are different shapes -- two
-- narrow arrows and a round dot -- so they are centred in a shared column
-- instead of being hung off its right edge, where the widest one would stick
-- out to the left of the other two.
local function MarkerWidth()
  local w = ArrowWidth(ARROW_UP_ATLAS)
  local d = ArrowWidth(ARROW_DOWN_ATLAS)
  if d > w then w = d end
  if SAME_SIZE > w then w = SAME_SIZE end
  return w
end

-- Track name in the item-quality colour of its rank, the same language the gear
-- rows in the main window speak.
local function TrackText(track, link)
  if not track then return "" end
  local c = ITEM_QUALITY_COLORS[track.rank]
  local name = GI.TrackName(link, track) or L[track.key]
  if not c then return name end
  return string.format("|cFF%02X%02X%02X%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

-- One line per matching specialization. The first carries the character; the
-- rest are that character's other specs, listed underneath without the name or
-- the race and faction icons -- their gear differs, so their gain does too, and
-- a single shared number would have been a fiction.
--
-- levelW and gainW are the widest of each across the whole list, so every line
-- reserves the same space and the columns land under one another.
local function AddRow(tooltip, ch, match, cols, leadLine)
  local gap  = SpaceWidth()

  local text = string.format(L[GainKey(match.gain)], match.gain)

  -- The gain is the line's own right text, so it ends at the tooltip's inner
  -- right edge; the arrow before it and the spec circle after it are widgets,
  -- and the text has to reserve room for both.
  --
  -- The trailing reservation ends in a fully transparent full stop. Trailing
  -- whitespace is not reliably measured, but whitespace followed by a glyph is
  -- -- and an invisible glyph costs nothing but the three pixels it occupies.
  -- A space on top of the column gap, so the circle reads as separate from the
  -- number rather than tacked onto it.
  local specGap  = COL_GAP + gap
  local trailPad = math.ceil((RACE_ICON_SIZE + specGap) / gap)
  local trailW   = trailPad * gap + TextWidth(".")

  -- Everything left of the gain is a widget, so the text reserves room for the
  -- whole run: track arrow, track name, and the gain arrow.
  local leadW = ArrowWidth(ARROW_TRACK_ATLAS) + COL_GAP
    + cols.trackW + COL_GAP
    + MarkerWidth() + COL_GAP * 2

  local right = string.rep(" ", math.ceil(leadW / gap))
    .. text
    .. string.rep(" ", trailPad)
    .. "|c00000000.|r"

  -- Both kinds of line carry the same leading spaces. An off-spec line has no
  -- name to print, but an empty left text collapses the line height and the rows
  -- ride up over one another -- the reservation keeps every line the same size.
  local leftBlock = cols.levelW + COL_GAP + RACE_ICON_SIZE + RACE_FACTION_GAP + ICON_SIZE + NAME_GAP
  local left = string.rep(" ", math.ceil(leftBlock / gap))

  local r, g, b = GI.ClassRGB(ch.class)
  if leadLine then
    local nameRealm = (ch.name or "?") .. "-" .. (ch.realm or "?")
    left = left .. string.format("|cFF%02X%02X%02X%s|r", r * 255, g * 255, b * 255, nameRealm)
  end

  tooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)

  local n       = tooltip:NumLines()
  local leftFS  = _G[tooltip:GetName() .. "TextLeft"  .. n]
  local rightFS = _G[tooltip:GetName() .. "TextRight" .. n]
  if not (leftFS and rightFS) then return end

  local f = AcquireRow(tooltip)
  f:ClearAllPoints()
  f:SetPoint("LEFT",  leftFS,  "LEFT",  0, 0)
  f:SetPoint("RIGHT", rightFS, "RIGHT", 0, 0)

  if leadLine then
    f.levelFS:SetWidth(cols.levelW)
    f.levelFS:SetText(tostring(ch.level or 0))
    f.levelFS:Show()

    local atlas = GI.RaceAtlas(ch.race, ch.sex)
    if atlas then
      f.race.icon:SetAtlas(atlas)
      f.race.border:SetVertexColor(r, g, b)
      f.race:Show()
    else
      f.race:Hide()
    end

    local factionAtlas = GI.FactionAtlas(ch.faction)
    if factionAtlas then
      f.factionTex:SetAtlas(factionAtlas)
      f.factionTex:Show()
    else
      f.factionTex:Hide()
    end
  else
    f.levelFS:Hide()
    f.race:Hide()
    f.factionTex:Hide()
  end

  -- The gain text ends trailW short of the row's right edge, so everything to
  -- its left is placed by stepping further in from that edge. A loss uses the
  -- orange arrow upside down and tinted red: the family ships no downward one,
  -- and the green one cannot be tinted red because it has no red channel.
  if match.gain > 0 then
    f.arrowTex:SetAtlas(ARROW_UP_ATLAS)
    f.arrowTex:SetSize(ArrowWidth(ARROW_UP_ATLAS), ARROW_HEIGHT)
    f.arrowTex:SetTexCoord(0, 1, 0, 1)
    f.arrowTex:SetVertexColor(1, 1, 1)
  elseif match.gain < 0 then
    f.arrowTex:SetAtlas(ARROW_DOWN_ATLAS)
    f.arrowTex:SetSize(ArrowWidth(ARROW_DOWN_ATLAS), ARROW_HEIGHT)
    f.arrowTex:SetTexCoord(0, 1, 1, 0)
    f.arrowTex:SetVertexColor(unpack(ARROW_DOWN_TINT))
  else
    f.arrowTex:SetAtlas(SameAtlas())
    f.arrowTex:SetSize(SAME_SIZE, SAME_SIZE)
    f.arrowTex:SetTexCoord(0, 1, 0, 1)
    f.arrowTex:SetVertexColor(unpack(SAME_TINT))
  end
  -- Centred in the marker column rather than right-aligned, so a wide dot and a
  -- narrow arrow sit on the same axis.
  local markerMid = trailW + cols.gainW + COL_GAP + MarkerWidth() / 2
  f.arrowTex:ClearAllPoints()
  f.arrowTex:SetPoint("CENTER", f, "RIGHT", -markerMid, 0)
  f.arrowTex:Show()

  -- The track marker only appears when the item can outgrow what they have --
  -- on every row it would be noise rather than news.
  if match.potential and cols.trackW > 0 then
    f.trackFS:SetWidth(cols.trackW)
    f.trackFS:SetText(cols.trackText)
    f.trackFS:ClearAllPoints()
    f.trackFS:SetPoint("RIGHT", f, "RIGHT",
      -(trailW + cols.gainW + COL_GAP + MarkerWidth() + COL_GAP), 0)
    f.trackFS:Show()

    f.trackArrow:SetSize(ArrowWidth(ARROW_TRACK_ATLAS), ARROW_HEIGHT)
    f.trackArrow:ClearAllPoints()
    f.trackArrow:SetPoint("RIGHT", f.trackFS, "LEFT", -COL_GAP, 0)
    f.trackArrow:Show()
  else
    f.trackFS:Hide()
    f.trackArrow:Hide()
  end

  local _, icon = GI.SpecInfo(match.specID)
  if icon then
    f.spec.icon:SetTexture(icon)
    f.spec:ClearAllPoints()
    f.spec:SetPoint("LEFT", f, "RIGHT", -(trailW - specGap), 0)
    f.spec:Show()
  else
    f.spec:Hide()
  end

  f:Show()
end

-- ─── Show gate ────────────────────────────────────────────────────────────────

-- Shift is not offered: it is Blizzard's default COMPAREITEMS modifier, so
-- holding it already fills the screen with comparison tooltips.
local SHOW_MODIFIER = {
  ctrl = IsControlKeyDown,
  alt  = IsAltKeyDown,
}

-- Which MODIFIER_STATE_CHANGED keys belong to which mode. The event reports the
-- side it came from, so both have to be listened for.
local MODIFIER_KEYS = {
  ctrl = { LCTRL = true, RCTRL = true },
  alt  = { LALT  = true, RALT  = true },
}

-- The modifier gate covers the hover tooltip only. A chat-link tooltip is
-- opened by a click and then stays up on its own, and only GameTooltip is
-- rebuilt when a modifier changes — gating that one too would leave the section
-- permanently out of reach there.
local function ShouldShow(tooltip)
  local mode = GI.Config.Get("recommendShow") or "always"
  if mode == "none"   then return false end
  if mode == "always" then return true end
  if tooltip ~= GameTooltip then return true end

  local isDown = SHOW_MODIFIER[mode]
  if not isDown then return true end  -- unrecognised setting: fail open
  return isDown()
end

-- A tooltip is built once, on hover. Without this, pressing the modifier while
-- one is already up would do nothing, and releasing it would leave the section
-- behind — so the mode would only ever work if the key was held beforehand.
-- RefreshDataNextUpdate defers to the next frame and coalesces repeats, which
-- matters because MODIFIER_STATE_CHANGED fires on both press and release.
local modFrame = CreateFrame("Frame")
modFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modFrame:SetScript("OnEvent", function(_, _, key)
  local keys = MODIFIER_KEYS[GI.Config.Get("recommendShow") or ""]
  if not (keys and keys[key]) then return end
  if GameTooltip:IsShown() and GameTooltip.RefreshDataNextUpdate then
    GameTooltip:RefreshDataNextUpdate()
  end
end)

-- ─── Tooltip hook ─────────────────────────────────────────────────────────────

-- True when the tooltip itself says the item is already soulbound. bindType
-- alone cannot tell: a bind-on-equip item still reports OnEquip after somebody
-- has worn it. Account-bound wording is deliberately not matched — those still
-- travel between the player's own characters.
local function IsSoulbound(data)
  if not (data and data.lines) then return false end
  for i = 1, math.min(#data.lines, 6) do
    if data.lines[i].leftText == ITEM_SOULBOUND then return true end
  end
  return false
end

local function OnItemTooltip(tooltip, data)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if tooltip:IsForbidden() then return end

  if not ShouldShow(tooltip) then return end
  if not (GI.db and GI.db.characters) then return end

  local _, link = TooltipUtil.GetDisplayedItem(tooltip)
  if not link then return end

  local _, _, quality, _, minLevel, _, _, _, equipLoc, _, _, classID, subclassID, bindType =
    C_Item.GetItemInfo(link)
  if not equipLoc then return end

  if not BindingAllows(data, bindType) then return end

  if not quality then return end

  -- Heirlooms and artifacts are excluded outright rather than by threshold.
  -- Their item level is a property of the wearer, not of the item: the Heart of
  -- Azeroth reads 34 in its own tooltip while the link reports over 200, and
  -- neither figure means anything on somebody else. Any comparison against
  -- equipped gear would be invented.
  --
  -- Both also sort above epic in Enum.ItemQuality, so no minimum would catch them.
  if quality == Enum.ItemQuality.Heirloom or quality == Enum.ItemQuality.Artifact then
    return
  end

  local minQuality = GI.Config.Get("recommendMinQuality") or Enum.ItemQuality.Uncommon
  if quality < minQuality then return end

  local slotIDs = EQUIP_SLOTS[equipLoc]
  if not slotIDs or IsSoulbound(data) then return end
  if GI.Config.Get("recommendIgnoreBoE") == true and IsBindOnEquip(data) then return end

  local itemIlvl = C_Item.GetDetailedItemLevelInfo(link)
  if not itemIlvl or itemIlvl <= 0 then return end

  local itemTrack = GI.ParseUpgradeTrack(link)
  local item = {
    link       = link,
    ilvl       = itemIlvl,
    ceiling    = CeilingOf(itemIlvl, itemTrack),
    track      = itemTrack,
    classID    = classID,
    subclassID = subclassID,
    twoHand    = TWO_HANDED[equipLoc],
    stats      = PrimaryStats(link),
  }

  local checkLevel    = GI.Config.Get("recommendIgnoreLevel") == false
  local activeSpecOnly = GI.Config.Get("recommendIgnoreOffspec") == true

  local rows = {}
  for charKey, entry in pairs(GI.db.characters) do
    local ch = entry.character
    if ch and not (checkLevel and minLevel and (ch.level or 0) < minLevel) then
      local gain, matches = EvaluateCharacter(item, entry, slotIDs, activeSpecOnly)
      if gain then
        rows[#rows + 1] = { key = charKey, ch = ch, gain = gain, matches = matches }
      end
    end
  end

  if #rows == 0 then return end

  table.sort(rows, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.key < b.key
  end)

  -- Widest of each column across every line that will be drawn -- gains are per
  -- spec now, so the widest one may well belong to an off-spec line. A column
  -- only grows when something in the list needs it to, and the track column
  -- stays at zero unless some line actually shows one.
  local cols = { levelW = 0, gainW = 0, trackW = 0, trackText = TrackText(item.track, link) }

  for i = 1, #rows do
    local lw = SmallTextWidth(tostring(rows[i].ch.level or 0))
    if lw > cols.levelW then cols.levelW = lw end

    for j = 1, #rows[i].matches do
      local match = rows[i].matches[j]
      local gw    = TextWidth(string.format(L[GainKey(match.gain)], match.gain))
      if gw > cols.gainW then cols.gainW = gw end
      if match.potential and item.track then
        cols.trackW = TextWidth(cols.trackText)
      end
    end
  end

  tooltip:AddLine(" ")
  tooltip:AddLine(GI.NAME_MARKUP .. " |cFFFFD100" .. L["REC_HEADER"] .. "|r")
  AddRule(tooltip)
  for i = 1, #rows do
    local row = rows[i]
    for j = 1, #row.matches do
      AddRow(tooltip, row.ch, row.matches[j], cols, j == 1)
    end
  end
  AddRule(tooltip)

  tooltip:Show()  -- re-layout: the added lines change the tooltip's size
  SizeRules()     -- only now is the tooltip width final

end

-- Clearing is registered for every tooltip type, not just items: the tooltip is
-- often reused for a unit or a spell without hiding in between, and the item
-- handler would never run to take its circles down. TooltipDataHandler
-- dispatches AllTypes callbacks before type-specific ones, so this always
-- clears before OnItemTooltip draws.
TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip)
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if tooltip:IsForbidden() then return end
  ReleaseIcons(tooltip)
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
