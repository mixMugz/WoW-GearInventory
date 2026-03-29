-- GearInventory/Addons/UI.lua
-- Main window, character list panel, gear slot panel, item tooltips.
-- All UI creation is deferred until GI.ToggleMainWindow() is first called.

local addonName, GI = ...
local L = GI.L

-- ─── Layout Constants ─────────────────────────────────────────────────────────

local DEFAULT_W   = 500
local CHAR_LIST_W = 180

local BODY_TOP_Y  = -30  -- just below title bar (no portrait)
local BODY_BOT_Y  = 12   -- bottom inset
local CHAR_ROW_H  = 28
local GEAR_ROW_H  = 28
local INFO_H      = 58   -- char info block + ITEMS label + gaps
-- Fixed height: title + info block + gear rows + bottom inset.
local FIXED_H = -BODY_TOP_Y + INFO_H
              + #GI.GEAR_SLOTS * GEAR_ROW_H + BODY_BOT_Y

-- ─── Empty Slot Icons ─────────────────────────────────────────────────────────
-- GetInventorySlotInfo(slotName) returns (slotID, emptyTexture) — same icons as
-- the character paperdoll frame uses for unequipped slots.

local EMPTY_SLOT_ICON = (function()
  local map = {
    [1]  = "HeadSlot",
    [2]  = "NeckSlot",
    [3]  = "ShoulderSlot",
    [15] = "BackSlot",
    [5]  = "ChestSlot",
    [9]  = "WristSlot",
    [10] = "HandsSlot",
    [6]  = "WaistSlot",
    [7]  = "LegsSlot",
    [8]  = "FeetSlot",
    [11] = "Finger0Slot",
    [12] = "Finger1Slot",
    [13] = "Trinket0Slot",
    [14] = "Trinket1Slot",
    [16] = "MainHandSlot",
    [17] = "SecondaryHandSlot",
  }
  local t = {}
  for slotID, slotName in pairs(map) do
    local _, tex = GetInventorySlotInfo(slotName)
    t[slotID] = tex
  end
  return t
end)()

-- ─── Colors ───────────────────────────────────────────────────────────────────

local function QColor(quality)
  local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1  -- fallback white
end

-- Returns color code for avgIlvl from stored per-character color (saved during scan).
-- Falls back to white if no color is stored (nil in DB).
local function IlvlColorCode(charData)
  local c = charData and charData.avgIlvlColor
  if c then
    return string.format("|cFF%02X%02X%02X", c.r * 255, c.g * 255, c.b * 255)
  end
  return "|cFFFFFFFF"
end

-- ─── Utilities ────────────────────────────────────────────────────────────────

local function FormatAge(ts)
  if not ts or ts == 0 then return L["NEVER"] end
  local d = time() - ts
  if d < 60      then return L["JUST_NOW"]
  elseif d < 3600  then return string.format(L["TIME_MIN"],  math.floor(d / 60))
  elseif d < 86400 then return string.format(L["TIME_HOUR"], math.floor(d / 3600))
  else                  return string.format(L["TIME_DAY"],  math.floor(d / 86400))
  end
end

local function ClassDisplayName(token)
  if not token then return "?" end
  return token:sub(1, 1) .. token:sub(2):lower()
end

-- ─── Widget Pools ─────────────────────────────────────────────────────────────

local gearRows    = {}
local selectedKey = nil

-- ─── Character Tooltip Helpers ────────────────────────────────────────────────

-- NineSlice border pieces are Textures directly on GameTooltip (confirmed from error locals)
local TIP_BORDER_PIECES = {
  "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
  "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}
local function ColorTipBorder(r, g, b)
  for _, k in ipairs(TIP_BORDER_PIECES) do
    local t = GameTooltip[k]
    if t then t:SetVertexColor(r, g, b) end
  end
end

-- Overlay: circular race icon (24px), positioned outside the tooltip to the left.
local tipOverlay
local function GetTipOverlay()
  if tipOverlay then return tipOverlay end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(26, 26)
  f:SetFrameStrata("TOOLTIP")
  f:Hide()

  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local mask = f:CreateMaskTexture()
  mask:SetAllPoints(icon)
  mask:SetTexture(GI.TEX.PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  icon:AddMaskTexture(mask)
  local border = f:CreateTexture(nil, "OVERLAY")
  border:SetSize(28, 28)
  border:SetPoint("CENTER")
  border:SetAtlas(GI.ATLAS.RACE_BORDER)

  f.icon   = icon
  f.border = border
  tipOverlay = f
  return f
end


-- ─── Comparison Tooltip Suppression ──────────────────────────────────────────
-- ShoppingTooltip1/2 are triggered asynchronously via OnTooltipSetItem after
-- item data loads, so a simple Hide() call after SetHyperlink is not reliable.
-- Instead we hook OnShow once and suppress via a flag while our button is hovered.

local suppressCompare = false

do
  local function SuppressOnShow(self)
    if suppressCompare then self:Hide() end
  end
  if ShoppingTooltip1 then ShoppingTooltip1:HookScript("OnShow", SuppressOnShow) end
  if ShoppingTooltip2 then ShoppingTooltip2:HookScript("OnShow", SuppressOnShow) end
end

-- ─── Gear Row ─────────────────────────────────────────────────────────────────

local function GetOrCreateGearRow(idx)
  if gearRows[idx] then return gearRows[idx] end

  local parent = GI.mainWindow.gearScrollChild
  local row    = CreateFrame("Frame", nil, parent)
  row:SetHeight(GEAR_ROW_H)
  row:SetPoint("TOPLEFT", 0, -(idx - 1) * GEAR_ROW_H)
  row:SetPoint("RIGHT",   0, 0)

  -- Col 1: Icon button (sized to match border overlay)
  local iconBtn = CreateFrame("Button", nil, row)
  iconBtn:SetSize(26, 26)
  iconBtn:SetPoint("LEFT", 0, 0)

  local iconT = iconBtn:CreateTexture(nil, "ARTWORK")
  iconT:SetSize(22, 22)
  iconT:SetPoint("CENTER")
  iconT:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.iconT = iconT

  local iconBorder = iconBtn:CreateTexture(nil, "OVERLAY")
  iconBorder:SetAllPoints()
  iconBorder:SetAtlas(GI.ATLAS.ICON_FRAME)
  row.iconBorder = iconBorder

  iconBtn:SetScript("OnEnter", function(self)
    local link = self:GetParent().itemLink
    if not link then return end
    suppressCompare = true
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
  end)
  iconBtn:SetScript("OnLeave", function()
    suppressCompare = false
    GameTooltip:Hide()
  end)
  row.iconBtn = iconBtn

  -- iLvl badge (top-right of icon, outlined, small)
  local ilvlFS = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local font, size = ilvlFS:GetFont()
  ilvlFS:SetFont(font, size - 1, "OUTLINE")
  ilvlFS:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMLEFT", 2, 2)
  ilvlFS:SetJustifyH("LEFT")
  row.ilvlFS = ilvlFS

  -- Col 2: Slot name (line 1, small) + Item name (line 2), vertically centered on icon
  local textGroup = CreateFrame("Frame", nil, row)
  textGroup:SetPoint("LEFT", iconBtn, "RIGHT", 6, 0)
  textGroup:SetPoint("RIGHT", -6, 0)
  textGroup:SetPoint("TOP", iconBtn, "TOP", 0, 2)
  textGroup:SetPoint("BOTTOM", iconBtn, "BOTTOM", 0, 2)

  local slotFS = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local slotFont, slotSize = slotFS:GetFont()
  slotFS:SetFont(slotFont, slotSize - 1)
  slotFS:SetPoint("BOTTOMLEFT", textGroup, "LEFT", 0, 0)
  slotFS:SetPoint("RIGHT")
  slotFS:SetJustifyH("LEFT")
  slotFS:SetTextColor(0.5, 0.5, 0.5)
  row.slotFS = slotFS

  local nameFS = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("TOPLEFT", textGroup, "LEFT", 0, 0)
  nameFS:SetPoint("RIGHT")
  nameFS:SetJustifyH("LEFT")
  nameFS:SetWordWrap(false)
  row.nameFS = nameFS

  gearRows[idx] = row
  return row
end

-- ─── Main Window Creation ─────────────────────────────────────────────────────

local function CreateMainWindow()
  local f = CreateFrame("Frame", "GearInventoryMainFrame", UIParent, "PortraitFrameTemplate")
  f:SetSize(DEFAULT_W, FIXED_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop",  f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()

  -- ButtonFrameTemplate provides: f.TitleContainer.TitleText, f.PortraitContainer.portrait, f.CloseButton
  f.TitleContainer.TitleText:SetText("|cFF00C9FFGear|r|cFFFFFFFFInventory|r")
  f.PortraitContainer:Hide()
  -- Replace portrait corner with standard metal corner
  f.NineSlice.TopLeftCorner:SetAtlas(GI.ATLAS.WINDOW_CORNER_TL, true)
  -- Extend title bar to fill the space freed by the hidden portrait
  f.TitleContainer:ClearAllPoints()
  f.TitleContainer:SetPoint("TOPLEFT", 4, 0)
  f.TitleContainer:SetPoint("TOPRIGHT", -24, 0)
  f.CloseButton:SetScript("OnClick", function() f:Hide() end)

  local versionFS = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local vFont, vSize = versionFS:GetFont()
  versionFS:SetFont(vFont, vSize - 2)
  versionFS:SetPoint("RIGHT", f.CloseButton, "LEFT", -4, 0)
  versionFS:SetText("|cFF555555v" .. GI.VERSION .. "|r")

  tinsert(UISpecialFrames, "GearInventoryMainFrame")

  -- ── Background ─────────────────────────────────────────────────────────────
  if f.TopTileStreaks then f.TopTileStreaks:Hide() end
  f.Bg:Hide()
  local bgJourneys = f:CreateTexture(nil, "BACKGROUND", nil, -3)
  bgJourneys:SetAtlas(GI.ATLAS.WINDOW_BG)
  bgJourneys:SetSize(f:GetWidth() - 3, f:GetHeight() - 6)
  bgJourneys:SetPoint("CENTER", f, "CENTER")


  -- ── Left panel: Character list (full height) ───────────────────────────────

  -- Store-style: WowScrollBoxList + MinimalScrollBar (auto-hide)
  local charSF = CreateFrame("Frame", "GICharScrollBox", f, "WowScrollBoxList")
  charSF:SetPoint("TOPLEFT",    4, BODY_TOP_Y - 4)
  charSF:SetPoint("BOTTOMLEFT", 4, BODY_BOT_Y)
  charSF:SetWidth(CHAR_LIST_W - 18)

  local charSB = CreateFrame("EventFrame", "GICharScrollBar", f, "MinimalScrollBar")
  charSB:SetPoint("TOPLEFT",    charSF, "TOPRIGHT",    2, -4)
  charSB:SetPoint("BOTTOMLEFT", charSF, "BOTTOMRIGHT", 2,  4)
  charSB:SetScale(0.70)

  local charView = CreateScrollBoxListLinearView()
  charView:SetElementExtent(CHAR_ROW_H)
  charView:SetElementFactory(function(factory, node)
    -- GICharButtonTemplate — Button, определён в Addons/templates.xml
    factory("GICharButtonTemplate", function(btn, nodeArg)
      if not btn._gi_setup then
        btn._gi_setup = true

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.65, 0.45, 0.10, 0.18)

        local sel = btn:CreateTexture(nil, "BACKGROUND")
        sel:SetAllPoints()
        sel:SetColorTexture(0.55, 0.38, 0.08, 0.28)
        sel:Hide()
        btn.selBg = sel

        local raceFrame = CreateFrame("Frame", nil, btn)
        raceFrame:SetSize(18, 18)
        raceFrame:SetPoint("LEFT", 12, 0)

        local raceIcon = raceFrame:CreateTexture(nil, "ARTWORK")
        raceIcon:SetAllPoints()
        raceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local raceMask = raceFrame:CreateMaskTexture()
        raceMask:SetAllPoints(raceIcon)
        raceMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        raceIcon:AddMaskTexture(raceMask)

        local raceBorder = raceFrame:CreateTexture(nil, "OVERLAY")
        raceBorder:SetSize(20, 20)
        raceBorder:SetPoint("CENTER")
        raceBorder:SetAtlas("talents-node-circle-gray")

        btn.raceIcon = raceIcon
        btn.raceBorder = raceBorder
        btn.raceFrame = raceFrame


        local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("LEFT", 34, 0)
        nameFS:SetPoint("RIGHT", -54, 0)
        nameFS:SetPoint("BOTTOM", btn, "CENTER", 0, -2)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        btn.nameFS = nameFS

        local realmFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local rFont, rSize = realmFS:GetFont()
        realmFS:SetFont(rFont, rSize - 2)
        realmFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, 0)
        realmFS:SetPoint("RIGHT", -54, 0)
        realmFS:SetJustifyH("LEFT")
        realmFS:SetTextColor(0.45, 0.45, 0.45)
        btn.realmFS = realmFS

        local ilvlFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ilvlFS:SetPoint("RIGHT", -14, 0)
        ilvlFS:SetText("000")
        local minW = ilvlFS:GetStringWidth()
        ilvlFS:SetText("")
        ilvlFS:SetWidth(minW)
        ilvlFS:SetJustifyH("RIGHT")
        btn.ilvlFS = ilvlFS

        btn:SetScript("OnClick", function(self)
          if not self.charKey then return end
          selectedKey = self.charKey
          GI.ShowCharacterGear(self.charKey)
        end)

        btn:SetScript("OnEnter", function(self)
          if not self.charKey or not GI.db then return end
          local d = GI.db.characters[self.charKey]
          if not d then return end
          local ch = d.character or {}

          local r, g, b = GI.ClassRGB(ch.class)
          local cHex = string.format("%02X%02X%02X", r*255, g*255, b*255)

          -- Tooltip right edge at button left edge, vertically centered
          GameTooltip:SetOwner(self, "ANCHOR_NONE")
          GameTooltip:ClearAllPoints()
          GameTooltip:SetPoint("RIGHT", self, "LEFT", -4, 0)

          local className = ch.className or (GI.CLASS_DISPLAY and GI.CLASS_DISPLAY[ch.class]) or (ch.class or "?")

          -- Line 1: Name-Realm (same class color for both)
          GameTooltip:AddLine(
            "|cFF" .. cHex .. (ch.name or "?") .. "-" .. (ch.realm or "") .. "|r",
            1, 1, 1, true)

          -- Line 2: empty separator
          GameTooltip:AddLine(" ")

          -- Line 3: Level (light gray)  Race (white)  Class (class color)
          local raceName = ch.raceName or ch.raceFile or "?"
          GameTooltip:AddLine(
            "|cFFAAAAAA" .. (ch.level or "?") .. "|r "
            .. "|cFFFFFFFF" .. raceName .. "|r "
            .. "|cFF" .. cHex .. className .. "|r",
            1, 1, 1)

          -- Line 4: Faction icon + name
          if ch.faction then
            local factionName = ch.factionName or ch.faction
            local fAtlas = ch.faction == "Horde"
              and GI.ATLAS.FACTION_HORDE
              or  GI.ATLAS.FACTION_ALLIANCE
            GameTooltip:AddLine(
              "|A:" .. fAtlas .. ":14:14|a |cFFFFFFFF" .. factionName .. "|r",
              1, 1, 1)
          end

          -- Line 5: empty separator
          GameTooltip:AddLine(" ")

          -- Line 5: Spec (yellow label, role icon, spec icon, spec name class color)
          if ch.specID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(ch.specID)
            local specStr = sIcon and ("|T" .. sIcon .. ":14:14|t") or ""
            GameTooltip:AddLine(
              "|cFFFFD100Spec:|r " .. specStr .. " |cFF" .. cHex .. (sName or "?") .. "|r",
              1, 1, 1)
          end

          -- Line 6: Saved Specs (yellow label + spec icons)
          if d.gear then
            local specIcons = {}
            for specKey in pairs(d.gear) do
              if specKey ~= 0 then
                local _, _, _, sIcon = GetSpecializationInfoByID(specKey)
                if sIcon then
                  table.insert(specIcons, "|T" .. sIcon .. ":14:14|t")
                end
              end
            end
            if #specIcons > 1 then
              table.sort(specIcons)
              GameTooltip:AddLine(
                "|cFFFFD100" .. L["TOOLTIP_SAVED_SPECS"] .. "|r " .. table.concat(specIcons, " "),
                1, 1, 1)
            end
          end

          -- Line 7: Avg. iLvl (yellow label, colored value)
          local ilvlStr = ch.avgIlvl and (IlvlColorCode(ch) .. ch.avgIlvl .. "|r") or "|cFF888888?|r"
          GameTooltip:AddLine("|cFFFFD100Avg. iLvl:|r " .. ilvlStr, 1, 1, 1)

          GameTooltip:Show()

          -- Color border
          ColorTipBorder(r, g, b)

          -- Race icon overlay — outside tooltip to the left
          local overlay = GetTipOverlay()
          local raceAtlas = GI.RaceAtlas(ch.raceFile, ch.sex)
          if raceAtlas then
            overlay.icon:SetAtlas(raceAtlas)
            overlay.border:SetVertexColor(r, g, b)
            overlay:ClearAllPoints()
            overlay:SetPoint("TOPRIGHT", GameTooltip, "TOPLEFT", -2, -1)
            overlay:Show()
          else
            overlay:Hide()
          end

        end)

        btn:SetScript("OnLeave", function()
          ColorTipBorder(1, 1, 1)
          GetTipOverlay():Hide()
          GameTooltip:Hide()
        end)
      end

      -- nodeArg — DataProvider node, переданный WoW при каждом рендере
      if not nodeArg then return end
      local entry = nodeArg.GetData and nodeArg:GetData() or nodeArg
      if not entry or not entry.key then return end
      local d = entry.data
      local ch = d.character or {}
      btn.charKey = entry.key

      local r, g, b2    = GI.ClassRGB(ch.class)
      btn.nameFS:SetText(ch.name or "?")
      btn.nameFS:SetTextColor(r, g, b2)
      btn.raceBorder:SetVertexColor(r, g, b2)
      btn.realmFS:SetText(ch.realm or "")

      local ready = GI.IsIlvlReady(entry.key)
      if ch.avgIlvl ~= nil then
        local suffix = not ready and "|cFF666666~|r" or ""
        btn.ilvlFS:SetText(IlvlColorCode(ch) .. ch.avgIlvl .. "|r" .. suffix)
      elseif not ready then
        btn.ilvlFS:SetText("|cFF666666...|r")
      else
        btn.ilvlFS:SetText("|cFF666666?|r")
      end

      local raceAtlas = GI.RaceAtlas(ch.raceFile, ch.sex)
      if raceAtlas then
        btn.raceIcon:SetAtlas(raceAtlas)
        btn.raceIcon:Show()
      else
        btn.raceIcon:Hide()
      end


      btn.selBg:SetShown(entry.key == selectedKey)
    end)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(charSF, charSB, charView)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(charSF, charSB)
  f.charScrollBox = charSF

  -- ── Right panel: char info + gear list ──────────────────────────────────────

  local rightX = 14  -- offset from charSB right edge

  -- Character info block
  local charNameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  charNameFS:SetPoint("LEFT", charSB, "RIGHT", rightX, 0)
  charNameFS:SetPoint("TOP", f, "TOP", 0, BODY_TOP_Y - 4)
  charNameFS:SetPoint("RIGHT", -14, 0)
  charNameFS:SetJustifyH("LEFT")
  charNameFS:SetWordWrap(false)
  charNameFS:SetText("|cFF555555" .. L["HINT_SELECT_CHAR"] .. "|r")
  f.charNameFS = charNameFS

  local charInfoFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  charInfoFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
  charInfoFS:SetPoint("RIGHT", -14, 0)
  charInfoFS:SetJustifyH("LEFT")
  charInfoFS:SetWordWrap(false)
  charInfoFS:SetText("")
  f.charInfoFS = charInfoFS

  -- ITEMS label
  local itemsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  itemsLabel:SetPoint("TOPLEFT", charInfoFS, "BOTTOMLEFT", 0, -6)
  itemsLabel:SetText("|cFF8A6A30ITEMS|r")

  -- ── Gear rows container ────────────────────────────────────────────────────

  local gearSF = CreateFrame("Frame", "GIGearScrollFrame", f)
  gearSF:SetPoint("TOPLEFT", itemsLabel, "BOTTOMLEFT", 0, -4)
  gearSF:SetPoint("RIGHT",  -14, 0)
  gearSF:SetPoint("BOTTOM", 0, BODY_BOT_Y)

  local gearSC = CreateFrame("Frame", "GIGearScrollChild", gearSF)
  gearSC:SetAllPoints()
  f.gearScrollChild = gearSC

  GI.mainWindow = f
  return f
end

-- ─── Public: Refresh Character List ──────────────────────────────────────────

function GI.RefreshCharacterList()
  local w = GI.mainWindow
  if not w or not GI.db then return end

  local order = GI.db.config and GI.db.config.sortOrder or "ilvl"

  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    local ach = a.data.character or {}
    local bch = b.data.character or {}
    if order == "name" then
      return (ach.name or "") < (bch.name or "")
    elseif order == "class" then
      return (ach.class or "") < (bch.class or "")
    else
      return (ach.avgIlvl or 0) > (bch.avgIlvl or 0)
    end
  end)

  local scrollPct = w.charScrollBox:GetScrollPercentage()
  w.charScrollBox:SetDataProvider(CreateDataProvider(sorted))
  if scrollPct then
    w.charScrollBox:SetScrollPercentage(scrollPct, true)
  end
end

-- ─── Public: Show Gear for a Character ───────────────────────────────────────

function GI.ShowCharacterGear(charKey)
  selectedKey = charKey
  local w = GI.mainWindow
  if not w or not GI.db then return end

  local d = GI.db.characters[charKey]
  if not d then return end
  local ch = d.character or {}

  local r, g, b = GI.ClassRGB(ch.class)
  local rH = math.floor(r * 255)
  local gH = math.floor(g * 255)
  local bH = math.floor(b * 255)

  -- Character name — show realm suffix only if it differs from the current one
  local playerRealm = GetRealmName()
  local realmSuffix = ""
  if ch.realm and ch.realm ~= playerRealm then
    realmSuffix = "|cFF666666-" .. ch.realm .. "|r"
  end
  local raceMarkup = GI.RaceIconMarkup(ch.raceFile, ch.sex, 16)
  w.charNameFS:SetFormattedText(
    "%s|cFF%02X%02X%02X%s|r%s",
    raceMarkup, rH, gH, bH, ch.name or "?", realmSuffix)

  -- Character info line (class, level, avg ilvl, last update)
  local ready = GI.IsIlvlReady(charKey)
  local ilvlPart
  if ch.avgIlvl ~= nil then
    local marker = not ready and " |cFF666666~|r" or ""
    ilvlPart = "  " .. string.format(L["CHAR_AVG_ILVL"], IlvlColorCode(ch) .. ch.avgIlvl .. "|r") .. marker
  elseif not ready then
    ilvlPart = "  |cFF666666...|r"
  else
    ilvlPart = ""
  end
  local agePart = "  |cFF888888" .. FormatAge(ch.lastUpdate) .. "|r"
  w.charInfoFS:SetFormattedText(
    "|cFF%02X%02X%02X%s|r  |cFFFFFFFF\226\128\162 " .. L["CHAR_LEVEL"] .. "|r%s%s",
    rH, gH, bH, ClassDisplayName(ch.class),
    ch.level or 0, ilvlPart, agePart)


  -- Gear rows
  for _, row in ipairs(gearRows) do row:Hide() end

  local avgIlvl = ch.avgIlvl or 0
  local specIDKey = ch.specID or 0
  local specGear = d.gear and d.gear[specIDKey]

  for i, slot in ipairs(GI.GEAR_SLOTS) do
    local row  = GetOrCreateGearRow(i)
    local item = specGear and specGear[slot.id]

    row.slotData = slot
    row.avgIlvl  = avgIlvl
    if item then
      row.itemData = item
      row.itemLink = item.link

      row.iconT:SetTexture(item.icon or EMPTY_SLOT_ICON[slot.id])
      row.iconT:SetAlpha(item.cached == false and 0.45 or 1.0)

      row.nameFS:SetText(item.name or "?")
      if item.cached == false then
        row.nameFS:SetTextColor(0.5, 0.5, 0.5)
      else
        local qr, qg, qb = QColor(item.quality or 1)
        row.nameFS:SetTextColor(qr, qg, qb)
      end

      local qr, qg, qb = QColor(item.quality or 1)
      local qHex = string.format("%02X%02X%02X", qr * 255, qg * 255, qb * 255)

      -- iLvl badge on icon — colored by item quality
      if (item.ilvl or 0) > 0 then
        row.ilvlFS:SetText(tostring(item.ilvl))
        if not ready then
          row.ilvlFS:SetTextColor(0.45, 0.45, 0.45)
        else
          row.ilvlFS:SetTextColor(qr, qg, qb)
        end
      else
        row.ilvlFS:SetText("")
      end

      -- Icon border — colored by item quality
      row.iconBorder:SetVertexColor(qr, qg, qb)

      -- Upgrade track badge (top-left of icon) — "1/6" only
      -- Slot name + upgrade track
      if item.upTrack then
        local rank = item.upRank or 1
        local maxRank = 5
        -- Star texture by tier (if enabled): 1=iron, 2-3=bronze, 4=silver, 5=gold
        local filledTex
        if GI.Config.Get("colorUpgradeStars") ~= false then
          filledTex = rank == 1 and GI.TEX.STAR_FILLED_IRON
            or rank <= 3 and GI.TEX.STAR_FILLED_BRONZE
            or rank == 4 and GI.TEX.STAR_FILLED_SILVER
            or GI.TEX.STAR_FILLED_GOLD
        else
          filledTex = GI.TEX.STAR_FILLED_SILVER
        end
        local S = "|T" .. filledTex          .. ":10:10|t"
        local E = "|T" .. GI.TEX.STAR_EMPTY .. ":10:10|t"
        local allStars = {}
        for i = 1, maxRank do
          allStars[i] = (i <= rank) and S or E
        end
        local stars = table.concat(allStars, " ")
        local PROGRESS_COLORS = { "FF4444", "FF8000", "FFFF00", "00FF00", "0080FF", "FFFFFF" }
        local progressHex = GI.Config.Get("colorUpgradeRank") ~= false
          and (PROGRESS_COLORS[math.min(item.upCur, #PROGRESS_COLORS)] or "AAAAAA")
          or "AAAAAA"
        row.slotFS:SetText(L[slot.key] .. "  " .. stars .. "  |cFF" .. progressHex .. item.upCur .. "/" .. item.upMax .. "|r")
      else
        row.slotFS:SetText(L[slot.key])
      end

    else
      row.itemData = nil
      row.itemLink = nil

      row.iconT:SetTexture(EMPTY_SLOT_ICON[slot.id])
      row.iconT:SetAlpha(0.5)
      row.iconBorder:SetVertexColor(1, 1, 1)
      row.nameFS:SetText("|cFF3A3A3A" .. L["ITEM_EMPTY"] .. "|r")
      row.nameFS:SetTextColor(1, 1, 1)
      row.ilvlFS:SetText("")
      row.slotFS:SetText(L[slot.key])
    end

    row:Show()
  end

  GI.RefreshCharacterList()
end

-- ─── Delete Character ───────────────────────────────────────────────────────

StaticPopupDialogs["GEARINVENTORY_DELETE_CHAR"] = {
  text = L["DELETE_CONFIRM"],
  button1 = YES,
  button2 = NO,
  OnAccept = function(self)
    local charKey = self.data
    GI.DeleteCharacter(charKey)
    if selectedKey == charKey then
      selectedKey = nil
      local w = GI.mainWindow
      if w then
        w.charNameFS:SetText("|cFF555555" .. L["HINT_SELECT_CHAR"] .. "|r")
        w.charInfoFS:SetText("")

        for _, row in ipairs(gearRows) do row:Hide() end
      end
    end
    GI.RefreshCharacterList()
    if GI.RefreshOptionsCharList then
      GI.RefreshOptionsCharList()
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

function GI.ConfirmDeleteCharacter(charKey)
  local d = GI.db and GI.db.characters[charKey]
  if not d then return end
  local ch = d.character or {}
  local popup = StaticPopup_Show("GEARINVENTORY_DELETE_CHAR",
    (ch.name or "?") .. "-" .. (ch.realm or "?"))
  if popup then
    popup.data = charKey
  end
end

-- ─── Public: Toggle Window ────────────────────────────────────────────────────

-- Returns true if no visible same-strata frame of meaningful size has a higher
-- frame level than ours (i.e. nothing is covering the window).
-- Tracks whether the window was brought up by our toggle.
-- Reset by OnHide (X button, Escape) so the next toggle always shows+raises.
function GI.ToggleMainWindow()
  if not GI.mainWindow then
    CreateMainWindow()
  end

  local w = GI.mainWindow

  if not w:IsShown() then
    w:Show()
    w:Raise()
    GI.RefreshCharacterList()
    if selectedKey and GI.db and GI.db.characters[selectedKey] then
      GI.ShowCharacterGear(selectedKey)
    elseif GI.db then
      local key = UnitName("player") .. "-" .. GetRealmName()
      if GI.db.characters[key] then
        GI.ShowCharacterGear(key)
      end
    end
  else
    w:Hide()
  end
end

-- ─── Callback: invoked by GearInventory.lua and Broker.lua ───────────────────

GI.OnCharacterDataUpdated = function(charKey)
  -- Always refresh the Options char list (panel may be open even if main window is not).
  if GI.RefreshOptionsCharList then
    GI.RefreshOptionsCharList()
  end

  local w = GI.mainWindow
  if not w or not w:IsShown() then return end
  GI.RefreshCharacterList()
  if charKey == selectedKey then
    GI.ShowCharacterGear(charKey)
  end
end
