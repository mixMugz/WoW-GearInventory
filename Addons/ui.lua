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
local CHAR_ROW_H        = 28
local GROUP_HEADER_H    = 14
local GEAR_ROW_H        = 28
local INFO_H            = 58   -- char info block + ITEMS label + gaps
local UPGRADE_STAR_COUNT = 5   -- stars per upgrade track (Iron→Bronze→Silver→Gold)

-- Upgrade rank progress colors (index = upCur rank, 1-based)
local PROGRESS_COLORS = { "FF4444", "FF8000", "FFFF00", "00FF00", "0080FF", "FFFFFF" }
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

-- ─── Sort / Group Helpers ─────────────────────────────────────────────────────

local function GetAvgIlvl(data)
  local ch = data.character or {}
  local bucket = data.gear and ch.specID and data.gear[ch.specID]
  return (bucket and bucket.avgIlvl) or 0
end

local function GetLastUpdated(data)
  local ch = data.character or {}
  local bucket = data.gear and ch.specID and data.gear[ch.specID]
  return (bucket and bucket.lastUpdate) or 0
end

-- Returns true/false if a < b by ord, nil if equal (enables primary→secondary chaining).
-- Direction is controlled by the global "sortDir" config: "asc" or "desc".
local function CompareBy(a, b, ord)
  local ach = a.data.character or {}
  local bch = b.data.character or {}
  local asc = GI.Config.Get("sortDir") == "asc"
  if ord == "name" then
    local av, bv = (ach.name or ""), (bch.name or "")
    if av ~= bv then if asc then return av < bv else return av > bv end end
  elseif ord == "class" then
    local av, bv = (ach.class or ""), (bch.class or "")
    if av ~= bv then if asc then return av < bv else return av > bv end end
  elseif ord == "level" then
    local av, bv = (ach.level or 0), (bch.level or 0)
    if av ~= bv then if asc then return av < bv else return av > bv end end
  elseif ord == "lastUpdated" then
    local av, bv = GetLastUpdated(a.data), GetLastUpdated(b.data)
    if av ~= bv then if asc then return av < bv else return av > bv end end
  else -- ilvl
    local av, bv = GetAvgIlvl(a.data), GetAvgIlvl(b.data)
    if av ~= bv then if asc then return av < bv else return av > bv end end
  end
  return nil
end

local function GetGroupKey(data, groupBy)
  local ch = data.character or {}
  if groupBy == "realm"   then return ch.realm or "Unknown" end
  if groupBy == "faction" then return ch.factionName or ch.faction or "Unknown" end
  if groupBy == "armor"   then return GI.CLASS_ARMOR[ch.class] or "Unknown" end
end

-- Group-by radio set, shared by the settings dropdown and the group header
-- context menu so the option list is defined once.
-- keepOpen: leave the menu open and refresh it after a pick, as the Sort submenu does.
local GROUP_BY_OPTIONS = {
  { "none",    "OPT_GROUP_NONE"    },
  { "realm",   "OPT_GROUP_REALM"   },
  { "faction", "OPT_GROUP_FACTION" },
  { "armor",   "OPT_GROUP_ARMOR"   },
}

local function AddGroupByRadios(description, keepOpen)
  local function getter(v) return (GI.Config.Get("groupBy") or "none") == v end
  local function setter(v)
    GI.Config.Set("groupBy", v)
    GI.RefreshCharacterList()
  end
  for _, opt in ipairs(GROUP_BY_OPTIONS) do
    local radio = description:CreateRadio(L[opt[2]], getter, setter, opt[1])
    if keepOpen then
      radio:SetResponder(function(data)
        setter(data)
        return MenuResponse.Refresh
      end)
    end
  end
end

-- ─── Widget Pools ─────────────────────────────────────────────────────────────

local gearRows       = {}
local selectedKey    = nil
local collapsedGroups = {}
local lvlFontSize     = nil  -- computed once from "00" on first render

-- ─── Tooltip Helpers ─────────────────────────────────────────────────────────

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

-- ─── Tooltip Data Prefetch ───────────────────────────────────────────────────
-- Called when gear is displayed for a character. Iterates all item links and
-- requests load for any items not yet in the client cache (gems, nested blocks),
-- so that C_TooltipInfo.GetHyperlink returns full data on the first hover.
local function PrefetchLines(lines)
  if not lines then return end
  for _, line in ipairs(lines) do
    local ltype = line.type
    if ltype == Enum.TooltipDataLineType.GemSocket
    or ltype == Enum.TooltipDataLineType.GemSocketEnchantment then
      if line.gemItemID and not line.gemIcon then
        C_Item.RequestLoadItemDataByID(line.gemItemID)
      end
    elseif ltype == Enum.TooltipDataLineType.NestedBlock then
      -- Recurse into nested blocks (e.g. set bonuses, special effects)
      PrefetchLines(line.lines)
    end
  end
end

local function PrefetchTooltipData(specSlots)
  if not specSlots then return end
  for _, item in pairs(specSlots) do
    if item.link and item.cached ~= false then
      local data = C_TooltipInfo.GetHyperlink(item.link)
      if data then PrefetchLines(data.lines) end
    end
  end
end

-- ─── Custom Item Tooltip Renderer ────────────────────────────────────────────
-- Renders lines from C_TooltipInfo.GetHyperlink() manually so GameTooltip.Icon
-- is never set, avoiding the large icon shown above the tooltip frame.
-- GemSocket lines carry gemIcon directly in the data; SellPrice is rebuilt
-- from line.price using GetCoinTextureString.
local function RenderItemTooltip(tooltip, link)
  local data = C_TooltipInfo.GetHyperlink(link)
  if not data or not data.lines then
    tooltip:SetHyperlink(link)
    return
  end
  tooltip:ClearLines()
  for _, line in ipairs(data.lines) do
    local lc    = line.leftColor
    local lr    = lc and lc.r or 1
    local lg    = lc and lc.g or 1
    local lb    = lc and lc.b or 1
    local ltype = line.type

    if ltype == Enum.TooltipDataLineType.ItemName then
      tooltip:AddDoubleLine(
        line.leftText or "", data.id and ("ID: " .. data.id) or "",
        lr, lg, lb,
        0.35, 0.35, 0.35
      )
      local rightFS = _G[tooltip:GetName() .. "TextRight" .. tooltip:NumLines()]
      if rightFS then
        local font, _, flags = rightFS:GetFont()
        rightFS:SetFont(font, 9, flags)
      end
    elseif ltype == Enum.TooltipDataLineType.SellPrice then
      -- Deliberately rendered as nothing: sell price is noise in a gear tooltip.
    elseif line.rightText and line.rightText ~= "" then
      local rc = line.rightColor
      tooltip:AddDoubleLine(
        line.leftText or "", line.rightText,
        lr, lg, lb,
        rc and rc.r or 1, rc and rc.g or 1, rc and rc.b or 1
      )
    else
      if ltype == Enum.TooltipDataLineType.GemSocket then
        local icon = line.gemIcon or "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"
        tooltip:AddLine("|T" .. icon .. ":14:14|t  " .. (line.leftText or ""), lr, lg, lb, line.wrapText or false)
      else
        tooltip:AddLine(line.leftText or "", lr, lg, lb, line.wrapText or false)
      end
    end
  end
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
    local parent = self:GetParent()
    local link   = parent.itemLink
    if not link then return end
    suppressCompare = true
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if parent.itemData and parent.itemData.cached ~= false then
      RenderItemTooltip(GameTooltip, link)
      local qr, qg, qb = QColor(parent.itemData.quality or 1)
      ColorTipBorder(qr, qg, qb)
    else
      GameTooltip:SetHyperlink(link)
    end
    GameTooltip:Show()
  end)
  iconBtn:SetScript("OnLeave", function()
    suppressCompare = false
    ColorTipBorder(1, 1, 1)
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
  slotFS:SetTextColor(0.65, 0.65, 0.65)
  row.slotFS = slotFS

  local nameFS = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("TOPLEFT", textGroup, "LEFT", 0, 0)
  nameFS:SetPoint("RIGHT", 10, 0)
  nameFS:SetJustifyH("LEFT")
  nameFS:SetWordWrap(false)
  row.nameFS = nameFS

  gearRows[idx] = row
  return row
end

-- ─── Character List Element Factories ────────────────────────────────────────

local function CharList_GroupHeader(btn, nodeArg)
  if not btn._gi_setup then
    btn._gi_setup = true

    local bgT = btn:CreateTexture(nil, "BACKGROUND")
    bgT:SetAllPoints()
    bgT:SetAtlas("Options_List_Hover")
    btn.bgT = bgT

    local labelFS = btn:CreateFontString(nil, "OVERLAY")
    labelFS:SetFont(GameFontNormalSmall:GetFont(), 9)
    labelFS:SetPoint("LEFT", 8, 0.5)
    labelFS:SetTextColor(0.9, 0.8, 0.5)
    btn.labelFS = labelFS

    local arrowT = btn:CreateTexture(nil, "ARTWORK")
    arrowT:SetSize(12, 12)
    arrowT:SetPoint("RIGHT", -6, 0)
    btn.arrowT = arrowT

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function(self) self.bgT:SetAtlas("Options_List_Active") end)
    btn:SetScript("OnLeave", function(self) self.bgT:SetAtlas("Options_List_Hover")  end)
    btn:SetScript("OnClick", function(self, mouseButton)
      if not self.groupKey then return end
      if mouseButton == "RightButton" then
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
          rootDescription:CreateTitle(L["OPT_GROUP_BY"])
          AddGroupByRadios(rootDescription)
        end)
        return
      end
      -- Left click: collapse/expand
      collapsedGroups[self.groupKey] = not collapsedGroups[self.groupKey]
      GI.RefreshCharacterList()
    end)
  end

  if not nodeArg then return end
  local entry = nodeArg.GetData and nodeArg:GetData() or nodeArg
  if not entry then return end
  btn.groupKey = entry.groupKey
  local collapsed = collapsedGroups[entry.groupKey]
  btn.arrowT:SetAtlas(collapsed and "glues-characterSelect-icon-plus" or "glues-characterSelect-icon-minus")
  btn.labelFS:SetText(entry.label:upper() .. " (" .. (entry.count or 0) .. ")")
end

local function CharList_CharButton(btn, nodeArg)
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
    raceFrame:SetSize(22, 22)
    raceFrame:SetPoint("LEFT", 12, 0)

    local raceIcon = raceFrame:CreateTexture(nil, "ARTWORK")
    raceIcon:SetAllPoints()
    raceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local raceMask = raceFrame:CreateMaskTexture()
    raceMask:SetAllPoints(raceIcon)
    raceMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    raceIcon:AddMaskTexture(raceMask)

    local raceBorder = raceFrame:CreateTexture(nil, "OVERLAY")
    raceBorder:SetSize(24, 24)
    raceBorder:SetPoint("CENTER")
    raceBorder:SetAtlas("talents-node-circle-gray")

    btn.raceIcon   = raceIcon
    btn.raceBorder = raceBorder
    btn.raceFrame  = raceFrame

    -- Level badge over race portrait (bottom-left, z-order above border)
    local lvlBadge = CreateFrame("Frame", nil, btn)
    lvlBadge:SetSize(16, 16)
    lvlBadge:SetPoint("BOTTOMLEFT", raceFrame, "BOTTOMLEFT", -6, -4)
    lvlBadge:SetFrameLevel(raceFrame:GetFrameLevel() + 2)

    local lvlBg = lvlBadge:CreateTexture(nil, "BACKGROUND")
    lvlBg:SetSize(16, 16)
    lvlBg:SetPoint("CENTER")
    lvlBg:SetAtlas("worldquest-Capstone-questmarker-epic-supertrack")

    local lvlFS = lvlBadge:CreateFontString(nil, "ARTWORK")
    lvlFS:SetFont(GameFontNormal:GetFont(), 9, "OUTLINE")
    lvlFS:SetTextColor(1, 1, 1)
    lvlFS:SetPoint("CENTER", 0.2, 0)
    btn.lvlFS    = lvlFS
    btn.lvlBadge = lvlBadge

    local lvlRing = lvlBadge:CreateTexture(nil, "BORDER")
    lvlRing:SetSize(16, 16)
    lvlRing:SetPoint("CENTER")
    lvlRing:SetAtlas("worldquest-tracker-ring")

    local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("LEFT", raceFrame, "RIGHT", 5, 4)
    nameFS:SetPoint("RIGHT", -30, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    btn.nameFS = nameFS

    local realmFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local rFont, rSize = realmFS:GetFont()
    realmFS:SetFont(rFont, rSize - 2)
    realmFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, 0)
    realmFS:SetPoint("RIGHT", -30, 0)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetTextColor(0.45, 0.45, 0.45)
    btn.realmFS = realmFS

    local ilvlFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlFS:SetPoint("RIGHT", -10, 0)
    ilvlFS:SetText("0000")
    local minW = ilvlFS:GetStringWidth()
    ilvlFS:SetText("")
    ilvlFS:SetWidth(minW)
    ilvlFS:SetJustifyH("RIGHT")
    btn.ilvlFS = ilvlFS

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnClick", function(self, mouseButton)
      if not self.charKey then return end
      if mouseButton == "RightButton" then
        local key = self.charKey
        local d   = GI.db and GI.db.characters[key]
        if not d then return end
        local ch = d.character or {}

        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
          local r, g, b = GI.ClassRGB(ch.class)
          local hex = string.format("%02X%02X%02X", r*255, g*255, b*255)
          local coloredName = "|cFF" .. hex .. (ch.name or "?") .. "|r"
          rootDescription:CreateTitle(coloredName)

          -- Count saved specs
          local specList = {}
          if d.gear then
            for specID in pairs(d.gear) do
              local specName, specIcon = GI.SpecInfo(specID)
              specList[#specList + 1] = { specID = specID, name = specName or tostring(specID), icon = specIcon }
            end
          end

          -- Export character
          rootDescription:CreateButton(L["CTX_EXPORT_CHAR"], function()
            local str, err = GI.ExportCharacter(key)
            if not str then
              GI.Print(L["EXPORT_ERR"])
              return
            end
            local raceIcon    = GI.RaceIconMarkup(ch.raceFile, ch.sex)
            local nameRealm   = (ch.name or "?") .. "-" .. (ch.realm or "?")
            local coloredFull = raceIcon .. "|cFF" .. string.format("%02X%02X%02X", r*255, g*255, b*255) .. nameRealm .. "|r"
            GI.Print(string.format(L["EXPORT_OK_CHAR"], coloredFull))
            StaticPopup_Show("GEARINVENTORY_EXPORT", nil, nil, str)
          end)

          rootDescription:CreateSpacer()

          if #specList <= 1 then
            -- Single spec: simple delete button
            rootDescription:CreateButton(L["CTX_DELETE_CHAR"], function()
              GI.ConfirmDeleteCharacter(key)
            end)
          else
            -- Multiple specs: submenu per spec + delete all
            local delSub = rootDescription:CreateButton(L["CTX_DELETE_CHAR"])
            for _, spec in ipairs(specList) do
              local sid  = spec.specID
              local sName = spec.name
              local sIcon = spec.icon
              delSub:CreateButton(sName, function()
                local coloredSpec = string.format("|cFF%02X%02X%02X%s|r", r*255, g*255, b*255, sName)
                local popup = StaticPopup_Show("GEARINVENTORY_DELETE_SPEC", coloredSpec, coloredName)
                if popup then
                  popup.data = {
                    charKey     = key,
                    specID      = sid,
                    specName    = sName,
                    specIcon    = sIcon,
                    raceFile    = ch.raceFile,
                    sex         = ch.sex,
                    coloredName = coloredName,
                    coloredSpec = coloredSpec,
                  }
                end
              end)
            end
            delSub:CreateDivider()
            delSub:CreateButton(L["CTX_DELETE_CHAR"], function()
              GI.ConfirmDeleteCharacter(key)
            end)
          end
        end)
        return
      end
      -- Left click: select character
      selectedKey = self.charKey
      GI.ShowCharacterGear(self.charKey)
    end)

  end

  -- Data population (runs every render)
  if not nodeArg then return end
  local entry = nodeArg.GetData and nodeArg:GetData() or nodeArg
  if not entry or not entry.key then return end
  local d  = entry.data
  local ch = d.character or {}
  btn.charKey = entry.key

  local r, g, b = GI.ClassRGB(ch.class)
  btn.nameFS:SetText(ch.name or "?")
  btn.nameFS:SetTextColor(r, g, b)
  btn.raceBorder:SetVertexColor(r, g, b)
  btn.realmFS:SetText(ch.realm or "")

  local ready      = GI.IsIlvlReady(entry.key)
  local listBucket = d.gear and ch.specID and d.gear[ch.specID]
  if listBucket and listBucket.avgIlvl ~= nil then
    local suffix = not ready and "|cFF666666~|r" or ""
    btn.ilvlFS:SetText(IlvlColorCode(listBucket) .. listBucket.avgIlvl .. "|r" .. suffix)
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

  -- Level badge: compute font size once from "00", cache in lvlFontSize
  do
    local font, _, flags = btn.lvlFS:GetFont()
    if not lvlFontSize then
      local maxPt   = 9
      local targetW = btn.lvlBadge:GetWidth() - 5
      btn.lvlFS:SetFont(font, maxPt, flags)
      btn.lvlFS:SetText("00")
      local w = btn.lvlFS:GetStringWidth()
      lvlFontSize = (w > 0 and w > targetW)
        and math.max(5, math.floor(maxPt * targetW / w) - 1)
        or  (maxPt - 1)
    end
    btn.lvlFS:SetFont(font, lvlFontSize, flags)
    btn.lvlFS:SetText(tostring(ch.level or ""))
  end

  btn.selBg:SetShown(entry.key == selectedKey)
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

  -- Settings gear dropdown (left of CloseButton)
  local settingsDropdown = CreateFrame("DropdownButton", nil, f, "UIPanelIconDropdownButtonTemplate")
  settingsDropdown:SetFrameLevel(f.CloseButton:GetFrameLevel() + 2)
  settingsDropdown:SetPoint("RIGHT", f.CloseButton, "LEFT", -4, 0)
  settingsDropdown:SetupMenu(function(_, rootDescription)
    rootDescription:SetTag("MENU_GI_SETTINGS")

    -- ── Sort by ───────────────────────────────────────────────────────────────
    local sortSub = rootDescription:CreateButton(L["OPT_SORT_BY"])

    sortSub:CreateTitle(L["OPT_SORT_DIR"])
    local function dirGetter(v) return GI.Config.Get("sortDir") == v end
    local function dirSetter(v) GI.Config.Set("sortDir", v) GI.RefreshCharacterList() end
    sortSub:CreateRadio(L["OPT_SORT_ASC"],  dirGetter, dirSetter, "asc")
      :SetResponder(function(data, _, _) dirSetter(data) return MenuResponse.Refresh end)
    sortSub:CreateRadio(L["OPT_SORT_DESC"], dirGetter, dirSetter, "desc")
      :SetResponder(function(data, _, _) dirSetter(data) return MenuResponse.Refresh end)

    sortSub:CreateSpacer()
    sortSub:CreateTitle(L["OPT_SORT_PRIMARY"])
    local function sortGetter(v) return GI.Config.Get("sortOrder") == v end
    local function sortSetter(v)
      GI.Config.Set("sortOrder", v)
      if GI.Config.Get("secondarySort") == v then
        GI.Config.Set("secondarySort", "none")
      end
      GI.RefreshCharacterList()
    end
    local primaryKeys = { "name", "class", "level", "ilvl", "lastUpdated" }
    local primaryLabels = {
      name        = L["OPT_SORT_NAME"],
      class       = L["OPT_SORT_CLASS"],
      level       = L["OPT_SORT_LEVEL"],
      ilvl        = L["OPT_SORT_ILVL"],
      lastUpdated = L["OPT_SORT_LAST_UPDATED"],
    }
    for _, v in ipairs(primaryKeys) do
      sortSub:CreateRadio(primaryLabels[v], sortGetter, sortSetter, v)
        :SetResponder(function(data, _, _)
          sortSetter(data)
          return MenuResponse.Refresh
        end)
    end

    sortSub:CreateSpacer()
    sortSub:CreateTitle(L["OPT_SORT_SECONDARY"])
    local function secGetter(v) return GI.Config.Get("secondarySort") == v end
    local function secSetter(v) GI.Config.Set("secondarySort", v) GI.RefreshCharacterList() end
    local secKeys = {
      { "none",        L["OPT_SORT_NONE"]         },
      { "name",        L["OPT_SORT_NAME"]         },
      { "class",       L["OPT_SORT_CLASS"]        },
      { "level",       L["OPT_SORT_LEVEL"]        },
      { "ilvl",        L["OPT_SORT_ILVL"]         },
      { "lastUpdated", L["OPT_SORT_LAST_UPDATED"] },
    }
    for _, opt in ipairs(secKeys) do
      local radio = sortSub:CreateRadio(opt[2], secGetter, secSetter, opt[1])
      radio:SetResponder(function(data, _, _)
        secSetter(data)
        return MenuResponse.Refresh
      end)
      if opt[1] ~= "none" then
        radio:SetEnabled(function() return GI.Config.Get("sortOrder") ~= opt[1] end)
      end
    end

    -- ── Group by ──────────────────────────────────────────────────────────────
    -- Also reachable by right-clicking a group header in the character list.
    local groupSub = rootDescription:CreateButton(L["OPT_GROUP_BY"])
    AddGroupByRadios(groupSub, true)

    rootDescription:CreateSpacer()

    -- ── Minimap ───────────────────────────────────────────────────────────────
    rootDescription:CreateCheckbox(
      L["OPT_SHOW_MINIMAP"],
      function() return GI.db and GI.db.config and GI.db.config.minimapButton
                     and not GI.db.config.minimapButton.hide end,
      function() GI.ToggleMinimapButton() end
    )

    -- ── Items ─────────────────────────────────────────────────────────────────
    rootDescription:CreateCheckbox(
      L["OPT_COLOR_UPGRADE"],
      function() return GI.Config.Get("colorUpgradeRank") ~= false end,
      function() GI.Config.Set("colorUpgradeRank", GI.Config.Get("colorUpgradeRank") == false) end
    )
    rootDescription:CreateCheckbox(
      L["OPT_COLOR_STARS"],
      function() return GI.Config.Get("colorUpgradeStars") ~= false end,
      function() GI.Config.Set("colorUpgradeStars", GI.Config.Get("colorUpgradeStars") == false) end
    )

    -- ── Messages ──────────────────────────────────────────────────────────────
    rootDescription:CreateCheckbox(
      L["OPT_DEBUG_MESSAGES"],
      function() return GI.Config.Get("debugMessages") ~= false end,
      function() GI.Config.Set("debugMessages", GI.Config.Get("debugMessages") == false) end
    )

    rootDescription:CreateSpacer()

    -- ── Export / Import ───────────────────────────────────────────────────────
    rootDescription:CreateButton(L["IMPORT"], function()
      StaticPopup_Show("GEARINVENTORY_IMPORT")
    end)

    rootDescription:CreateButton(L["EXPORT_ALL"], function()
      local str, err = GI.ExportAll()
      if not str then
        GI.Print(L["EXPORT_ERR"])
        return
      end
      GI.Print(L["EXPORT_OK_FULL"])
      StaticPopup_Show("GEARINVENTORY_EXPORT", nil, nil, str)
    end)

    rootDescription:CreateSpacer()

    rootDescription:CreateButton(L["DELETE_ALL_CHARS"], function()
      StaticPopup_Show("GEARINVENTORY_DELETE_ALL")
    end)

  end)

  -- Character jump button (left side of title bar) — selects the current player's character
  local charJumpBtn = CreateFrame("Button", nil, f)
  charJumpBtn:SetSize(28, 28)
  charJumpBtn:SetFrameLevel(f.CloseButton:GetFrameLevel() + 2)
  charJumpBtn:SetPoint("TOPLEFT", f, "TOPLEFT", -4, 2)
  charJumpBtn:Hide()

  local cjBg = charJumpBtn:CreateTexture(nil, "BACKGROUND")
  cjBg:SetSize(26, 26)
  cjBg:SetPoint("CENTER")
  cjBg:SetColorTexture(0, 0, 0, 1)

  local cjBgMask = charJumpBtn:CreateMaskTexture()
  cjBgMask:SetAllPoints(cjBg)
  cjBgMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  cjBg:AddMaskTexture(cjBgMask)

  local cjIcon = charJumpBtn:CreateTexture(nil, "ARTWORK")
  cjIcon:SetSize(22, 22)
  cjIcon:SetPoint("CENTER")
  cjIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local cjMask = charJumpBtn:CreateMaskTexture()
  cjMask:SetAllPoints(cjIcon)
  cjMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  cjIcon:AddMaskTexture(cjMask)

  -- Border stays fixed; recolored gold on hover via OnEnter/OnLeave
  local cjBorder = charJumpBtn:CreateTexture(nil, "OVERLAY")
  cjBorder:SetSize(26, 26)
  cjBorder:SetPoint("CENTER")
  cjBorder:SetAtlas("talents-node-circle-gray")

  local cjClassR, cjClassG, cjClassB = 1, 1, 1  -- cached class color for hover restore

  local function RefreshCharJumpBtn()
    if not GI.db then charJumpBtn:Hide() return end
    local key = UnitName("player") .. "-" .. GetRealmName()
    local d   = GI.db.characters[key]
    local ch  = d and d.character
    if not ch then charJumpBtn:Hide() return end
    cjClassR, cjClassG, cjClassB = GI.ClassRGB(ch.class)
    local atlas = GI.RaceAtlas(ch.raceFile, ch.sex)
    if atlas then
      cjIcon:SetAtlas(atlas)
      cjIcon:Show()
    else
      cjIcon:Hide()
    end
    cjBorder:SetVertexColor(cjClassR, cjClassG, cjClassB)
    charJumpBtn:Show()
  end

  -- Only icon shifts and darkens on press; border stays in place
  charJumpBtn:SetScript("OnMouseDown", function()
    cjIcon:SetPoint("CENTER", 1, -1)
    cjIcon:SetVertexColor(0.55, 0.55, 0.55)
  end)
  charJumpBtn:SetScript("OnMouseUp", function()
    cjIcon:SetPoint("CENTER", 0, 0)
    cjIcon:SetVertexColor(1, 1, 1)
  end)
  charJumpBtn:SetScript("OnEnter", function()
    cjBorder:SetVertexColor(1, 0.82, 0)
  end)
  charJumpBtn:SetScript("OnLeave", function()
    cjBorder:SetVertexColor(cjClassR, cjClassG, cjClassB)
  end)

  charJumpBtn:SetScript("OnClick", function()
    local key = UnitName("player") .. "-" .. GetRealmName()
    if not (GI.db and GI.db.characters[key]) then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    GI.ShowCharacterGear(key)
    GI.RefreshCharacterList()
    f.charScrollBox:ScrollToElementDataByPredicate(function(data)
      return not data.isHeader and data.key == key
    end, ScrollBoxConstants.AlignBegin, 0, true)
  end)

  f:HookScript("OnShow", RefreshCharJumpBtn)
  GI.RefreshCharJumpBtn = RefreshCharJumpBtn

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
  charView:SetElementExtentCalculator(function(_, node)
    return (node and node.isHeader) and GROUP_HEADER_H or CHAR_ROW_H
  end)
  charView:SetElementFactory(function(factory, node)
    if node and node.isHeader then
      factory("GIGroupHeaderTemplate", CharList_GroupHeader)
    else
      factory("GICharButtonTemplate",  CharList_CharButton)
    end
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(charSF, charSB, charView)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(charSF, charSB)
  f.charScrollBox = charSF

  -- ── Right panel: char info + gear list ──────────────────────────────────────

  local rightX = 10  -- offset from charSB right edge

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

  GI.OnConfigChanged = function(key)
    if (key == "colorUpgradeRank" or key == "colorUpgradeStars") and selectedKey then
      GI.ShowCharacterGear(selectedKey)
    end
  end

  return f
end

-- ─── Public: Refresh Character List ──────────────────────────────────────────

function GI.RefreshCharacterList()
  local w = GI.mainWindow
  if not w or not GI.db then return end

  local order     = GI.db.config and GI.db.config.sortOrder     or "ilvl"
  local secondary = GI.db.config and GI.db.config.secondarySort or "none"

  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end

  table.sort(sorted, function(a, b)
    local r = CompareBy(a, b, order)
    if r ~= nil then return r end
    if secondary ~= "none" and secondary ~= order then
      local r2 = CompareBy(a, b, secondary)
      if r2 ~= nil then return r2 end
    end
    return false
  end)

  local groupBy = GI.db.config and GI.db.config.groupBy or "none"

  local result = {}

  if groupBy == "none" then
    table.insert(result, { isHeader = true, groupKey = "_all", label = L["PANEL_CHARACTERS"], count = #sorted })
    if not collapsedGroups["_all"] then
      for _, entry in ipairs(sorted) do
        table.insert(result, entry)
      end
    end
  else
    local groups     = {}
    local groupOrder = {}
    for _, entry in ipairs(sorted) do
      local gk = GetGroupKey(entry.data, groupBy)
      if not groups[gk] then
        groups[gk] = {}
        table.insert(groupOrder, gk)
      end
      table.insert(groups[gk], entry)
    end
    table.sort(groupOrder)
    for _, gk in ipairs(groupOrder) do
      local members = groups[gk]
      table.insert(result, { isHeader = true, groupKey = gk, label = gk, count = #members })
      if not collapsedGroups[gk] then
        for _, entry in ipairs(members) do
          table.insert(result, entry)
        end
      end
    end
  end

  local scrollPct = w.charScrollBox:GetScrollPercentage()
  w.charScrollBox:SetDataProvider(CreateDataProvider(result))
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

  -- Gear rows
  local specIDKey  = ch.specID or 0
  local specBucket = d.gear and d.gear[specIDKey]
  local specSlots  = specBucket and specBucket.slots

  -- Character info line (class, level, avg ilvl, last update)
  local ready = GI.IsIlvlReady(charKey)
  local ilvlPart
  local avgIlvl = (specBucket and specBucket.avgIlvl) or 0
  if specBucket and specBucket.avgIlvl ~= nil then
    local marker = not ready and " |cFF666666~|r" or ""
    ilvlPart = "  " .. string.format(L["CHAR_AVG_ILVL"], IlvlColorCode(specBucket) .. specBucket.avgIlvl .. "|r") .. marker
  elseif not ready then
    ilvlPart = "  |cFF666666...|r"
  else
    ilvlPart = ""
  end
  local agePart = "  |cFF888888" .. FormatAge(specBucket and specBucket.lastUpdate) .. "|r"
  w.charInfoFS:SetFormattedText(
    "|cFF%02X%02X%02X%s|r  |cFFFFFFFF\226\128\162 " .. L["CHAR_LEVEL"] .. "|r%s%s",
    rH, gH, bH, ClassDisplayName(ch.class),
    ch.level or 0, ilvlPart, agePart)

  PrefetchTooltipData(specSlots)

  for _, row in ipairs(gearRows) do row:Hide() end

  for i, slot in ipairs(GI.GEAR_SLOTS) do
    local row  = GetOrCreateGearRow(i)
    local item = specSlots and specSlots["s" .. slot.id]

    row.slotData = slot
    row.avgIlvl  = avgIlvl
    if item then
      row.itemData = item
      row.itemLink = item.link

      row.iconT:SetTexture(item.icon or EMPTY_SLOT_ICON[slot.id])
      row.iconT:SetAlpha(item.cached == false and 0.45 or 1.0)

      local qr, qg, qb = QColor(item.quality or 1)

      row.nameFS:SetText(item.name or "?")
      if item.cached == false then
        row.nameFS:SetTextColor(0.5, 0.5, 0.5)
      else
        row.nameFS:SetTextColor(qr, qg, qb)
      end

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

      -- Slot name + upgrade track. The track is resolved from the item link on
      -- every render (never read from the DB), so a season change applies to
      -- saved characters without rescanning them — see GI.GetSlotUpgrade.
      local upTrack, upCur, upMax, upRank = GI.GetSlotUpgrade(item)
      if upTrack then
        local rank = upRank or 1
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
        for i = 1, UPGRADE_STAR_COUNT do
          allStars[i] = (i <= rank) and S or E
        end
        local stars = table.concat(allStars, " ")
        local progressHex = GI.Config.Get("colorUpgradeRank") ~= false
          and (PROGRESS_COLORS[math.min(upCur, #PROGRESS_COLORS)] or "AAAAAA")
          or "AAAAAA"
        row.slotFS:SetText(L[slot.key] .. "  " .. stars .. "  |cFF" .. progressHex .. upCur .. "/" .. upMax .. "|r")
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

-- Resets main window selection state when a character is deleted.
-- Called from StaticPopupDialogs["GEARINVENTORY_DELETE_CHAR"] in characters.lua.
function GI.IsMainWindowSelection(charKey)
  return selectedKey == charKey
end

function GI.ClearMainWindowSelection(charKey)
  if selectedKey ~= charKey then return end
  selectedKey = nil
  local w = GI.mainWindow
  if w then
    w.charNameFS:SetText("|cFF555555" .. L["HINT_SELECT_CHAR"] .. "|r")
    w.charInfoFS:SetText("")
    for _, row in ipairs(gearRows) do row:Hide() end
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
    if InCombatLockdown() then return end
    w:Show()
    w:Raise()
    -- Prefetch tooltip data for all saved characters so gem icons are ready on first hover
    if GI.db and GI.db.characters then
      for _, d in pairs(GI.db.characters) do
        local specID = d.character and d.character.specID
        local slots  = specID and d.gear and d.gear[specID] and d.gear[specID].slots
        PrefetchTooltipData(slots)
      end
    end
    GI.RefreshCharacterList()
    if selectedKey and GI.db and GI.db.characters[selectedKey] then
      GI.ShowCharacterGear(selectedKey)
      w.charScrollBox:ScrollToElementDataByPredicate(function(data)
        return not data.isHeader and data.key == selectedKey
      end, ScrollBoxConstants.AlignBegin, 0, true)
    elseif GI.db then
      local key = UnitName("player") .. "-" .. GetRealmName()
      if GI.db.characters[key] then
        GI.ShowCharacterGear(key)
        w.charScrollBox:ScrollToElementDataByPredicate(function(data)
          return not data.isHeader and data.key == key
        end, ScrollBoxConstants.AlignBegin, 0, true)
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
  if GI.RefreshCharJumpBtn then GI.RefreshCharJumpBtn() end
  if charKey == selectedKey then
    GI.ShowCharacterGear(charKey)
  end
end

-- ─── Export / Import Dialogs ─────────────────────────────────────────────────

-- Returns "[class icon] Name-Realm" colored by class for import/export print messages.
local function CharImportMarkup(charKey)
  local d  = GI.db and GI.db.characters[charKey]
  local ch = d and d.character
  if not ch then return "|cFFFFFFFF" .. charKey .. "|r" end
  local r, g, b     = GI.ClassRGB(ch.class)
  local raceIcon    = GI.RaceIconMarkup(ch.raceFile, ch.sex)
  local nameRealm   = (ch.name or "?") .. "-" .. (ch.realm or "?")
  return raceIcon .. "|cFF" .. string.format("%02X%02X%02X", r*255, g*255, b*255) .. nameRealm .. "|r"
end

-- Writes parsed import data and reports the outcome in chat.
-- Used by both import paths — the plain one and the overwrite confirmation — so
-- that neither can drift in how it reads GI.ApplyImport's five return values.
local function ApplyImportAndPrint(importType, importData, skipExisting)
  local count, overwritten, skipped, charKey, writtenKeys = GI.ApplyImport(importType, importData, skipExisting)
  if importType == "char" then
    if count == 0 and overwritten == 0 then
      GI.Print(L["IMPORT_SKIP_CURRENT"])
    else
      GI.Print(string.format(L["IMPORT_OK_CHAR"], CharImportMarkup(charKey)))
    end
  else
    if overwritten > 0 then
      GI.Print(string.format(L["IMPORT_OK_FULL_OW"], count, overwritten, skipped))
    else
      GI.Print(string.format(L["IMPORT_OK_FULL"], count, skipped))
    end
  end
  if writtenKeys and #writtenKeys > 0 and GI.WarmUpAllCharacters then
    GI.WarmUpAllCharacters()
  end
end

StaticPopupDialogs["GEARINVENTORY_DELETE_ALL"] = {
  text          = L["DELETE_ALL_CONFIRM"],
  button1       = YES,
  button2       = NO,
  OnAccept      = function()
    GI.DeleteAllCharacters()
    GI.ClearMainWindowSelection()
    GI.RefreshCharacterList()
    if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
  end,
  timeout       = 0,
  whileDead     = true,
  hideOnEscape  = true,
  preferredIndex = 3,
}

-- Shows the encoded string; user selects all and copies.
StaticPopupDialogs["GEARINVENTORY_EXPORT"] = {
  text     = L["EXPORT_HINT"],
  button1  = CLOSE,
  hasEditBox   = true,
  editBoxWidth = 360,
  OnShow   = function(self)
    self.EditBox:SetText(self.data or "")
    self.EditBox:HighlightText()
    self.EditBox:SetFocus()
  end,
  OnHide                  = function(self) self.EditBox:SetText("") end,
  EditBoxOnEscapePressed  = function(self) self:GetParent():Hide() end,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Accepts a pasted import string; parses and applies (with confirm if conflicts).
StaticPopupDialogs["GEARINVENTORY_IMPORT"] = {
  text     = L["IMPORT_HINT"],
  button1  = ACCEPT,
  button2  = CANCEL,
  hasEditBox   = true,
  editBoxWidth = 360,
  OnAccept = function(self)
    local str = self.EditBox:GetText()
    local importType, data, conflicts, err = GI.ParseImport(str)
    if err then
      GI.Print(L["IMPORT_INVALID"])
      return
    end
    if #conflicts > 0 then
      local d = { importType = importType, importData = data }
      C_Timer.After(0, function()
        local popup = StaticPopup_Show("GEARINVENTORY_IMPORT_CONFIRM", #conflicts)
        if popup then popup.data = d end
      end)
    else
      ApplyImportAndPrint(importType, data)
    end
  end,
  OnHide                  = function(self) self.EditBox:SetText("") end,
  EditBoxOnEscapePressed  = function(self) self:GetParent():Hide() end,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- Confirms overwrite when imported data collides with existing characters.
-- YES = overwrite existing; NO = import only new characters (skip existing).
StaticPopupDialogs["GEARINVENTORY_IMPORT_CONFIRM"] = {
  text     = L["IMPORT_OVERWRITE"],
  button1  = YES,
  button2  = NO,
  OnAccept = function(self)
    if not self.data then return end
    ApplyImportAndPrint(self.data.importType, self.data.importData, false)
  end,
  OnCancel = function(self)
    if not self.data then return end
    ApplyImportAndPrint(self.data.importType, self.data.importData, true)
  end,
  timeout      = 0,
  whileDead    = true,
  hideOnEscape = true,
  preferredIndex = 3,
}
