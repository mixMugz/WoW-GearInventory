-- GearInventory/Addons/ui.lua
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

-- Fixed height: title + info block + gear rows + bottom inset.
local FIXED_H = -BODY_TOP_Y + INFO_H
              + #GI.GEAR_SLOTS * GEAR_ROW_H + BODY_BOT_Y

-- ─── Empty Slot Icons ─────────────────────────────────────────────────────────
-- GetInventorySlotInfo(slotName) returns (slotID, emptyTexture) — same icons as
-- the character paperdoll frame uses for unequipped slots.

local EMPTY_SLOT_ICON = (function()
  local t = {}
  for _, slot in ipairs(GI.GEAR_SLOTS) do
    local _, tex = GetInventorySlotInfo(slot.inv)
    t[slot.id] = tex
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
    return GI.ColorCode(c.r, c.g, c.b)
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
-- Direction comes in as an argument: the two sort levels each have their own.
local function CompareBy(a, b, ord, asc)
  local ach = a.data.character or {}
  local bch = b.data.character or {}
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
  -- FACTION_LABELS_FROM_STRING localizes into the *viewer's* client language,
  -- so an imported character keeps a matching header instead of the exporter's.
  if groupBy == "faction" then
    if not ch.faction then return "Unknown" end
    -- A Pandaren who has not picked a side yet is "Neutral", which Blizzard's
    -- own table does not carry -- it holds Horde and Alliance only.
    return FACTION_LABELS_FROM_STRING[ch.faction] or FACTION_NEUTRAL or ch.faction
  end
  if groupBy == "armor"   then return GI.ClassArmorName(ch.class) or "Unknown" end
end

-- Colour used when the track or rank colouring is switched off. Not white: the
-- slot line is dimmed grey, and yellow reads as "deliberately plain" against it.
local PLAIN_HEX = "FFD100"
local PLAIN_R, PLAIN_G, PLAIN_B = 1, 0.82, 0

-- Rank star bar. The silver art is close enough to greyscale to tint cleanly:
-- SetVertexColor multiplies, so a coloured base would muddy every hue.
local STAR_SIZE   = 6
local LEAD_SPACES = 2  -- spaces between the label and the first star

-- Gap between the label and the bar, and between stars: one space in the label
-- font, so the bar is spaced exactly like the words in front of it.

-- Width the bar claims, reserved on the label so text can never run under it.
local function RankBarWidth(n, gap)
  if n <= 0 then return 0 end
  return LEAD_SPACES * gap + n * STAR_SIZE + (n - 1) * gap
end

-- Places the bar directly after the label text, which means measuring it — so
-- this must run after SetText. The offset is clamped to the label's own width:
-- a long slot and track name truncates rather than pushing the bar off the row.
-- Pass n = 0 to hide the bar.
local function LayoutRankStars(row, n, cur, r, g, b)
  local gap, offset = GI.SpaceWidth(row.slotFS), 0
  if n > 0 then
    offset = math.min(row.slotFS:GetStringWidth(), row.slotFS:GetWidth()) + LEAD_SPACES * gap
  end

  for i = 1, math.max(n, #row.stars) do
    local star = row.stars[i]
    if not star and i <= n then
      star = row.textGroup:CreateTexture(nil, "OVERLAY")
      star:SetSize(STAR_SIZE, STAR_SIZE)
      row.stars[i] = star
    end
    if star then
      if i > n then
        star:Hide()
      else
        star:ClearAllPoints()
        star:SetPoint("LEFT", row.slotFS, "LEFT", offset + (i - 1) * (STAR_SIZE + gap), 0)
        if i <= cur then
          star:SetTexture(GI.TEX.STAR_FILLED_SILVER)
          star:SetVertexColor(r, g, b)
        else
          star:SetTexture(GI.TEX.STAR_EMPTY)
          star:SetVertexColor(1, 1, 1)
        end
        star:Show()
      end
    end
  end
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

-- Sort orders, in menu order. The secondary list puts "none" in front of the
-- same set, which is why the set is written once.
local DIR_OPTIONS = {
  { "asc",  "OPT_SORT_ASC"  },
  { "desc", "OPT_SORT_DESC" },
}

local SORT_OPTIONS = {
  { "name",        "OPT_SORT_NAME"         },
  { "class",       "OPT_SORT_CLASS"        },
  { "level",       "OPT_SORT_LEVEL"        },
  { "ilvl",        "OPT_SORT_ILVL"         },
  { "lastUpdated", "OPT_SORT_LAST_UPDATED" },
}

-- Tooltip recommendation radios. Order is the menu order; the first value of
-- each pair is what lands in the config.
local REC_SHOW_OPTIONS = {
  { "none",   "OPT_REC_SHOW_NONE"   },
  { "always", "OPT_REC_SHOW_ALWAYS" },
  -- Shift is deliberately absent: it is Blizzard's default COMPAREITEMS
  -- modifier, so it already covers the screen in comparison tooltips.
  { "ctrl",   "OPT_REC_SHOW_CTRL"   },
  { "alt",    "OPT_REC_SHOW_ALT"    },
}

-- Minimum item quality, as Enum.ItemQuality values.
local REC_QUALITY_OPTIONS = {
  { 2, "OPT_REC_Q_UNCOMMON" },
  { 3, "OPT_REC_Q_RARE"     },
  { 4, "OPT_REC_Q_EPIC"     },
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
      -- The item ID rides along in small type. Registered rather than set
      -- outright: this is GameTooltipTextRight1, which every other tooltip in
      -- the session shares.
      GI.SetTooltipLineFont(
        _G[tooltip:GetName() .. "TextRight" .. tooltip:NumLines()],
        GI.TooltipFont(9))
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
    GI.RestoreTooltipFonts()
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

  row.textGroup = textGroup

  local slotFS = textGroup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local slotFont, slotSize = slotFS:GetFont()
  slotFS:SetFont(slotFont, slotSize - 1)
  slotFS:SetPoint("BOTTOMLEFT", textGroup, "LEFT", 0, 0)
  slotFS:SetJustifyH("LEFT")
  slotFS:SetWordWrap(false)
  slotFS:SetTextColor(0.65, 0.65, 0.65)
  row.slotFS = slotFS

  -- Rank stars are real textures, not inline markup: only a texture can be
  -- tinted, and the bar has to match the six quality colours the numeric form
  -- uses. Grown on demand and reused as rows scroll.
  row.stars = {}

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
  btn.labelFS:SetText(entry.label .. " (" .. (entry.count or 0) .. ")")
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

    local raceFrame = GI.CreateCircleIcon(btn, 22, 24)
    raceFrame:SetPoint("LEFT", 12, 0)

    btn.raceIcon   = raceFrame.icon
    btn.raceBorder = raceFrame.border
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
          local coloredName = GI.Colorize(ch.name or "?", GI.ClassRGB(ch.class))
          rootDescription:CreateTitle(coloredName)

          local specList = GI.SpecList(d)

          -- Export character
          rootDescription:CreateButton(L["CTX_EXPORT_CHAR"], function()
            GI.ShowExportCharacter(key)
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
              delSub:CreateButton(spec.name or tostring(spec.specID), function()
                GI.ConfirmDeleteSpec(key, spec, ch, coloredName)
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

  local raceAtlas = GI.RaceAtlas(ch.race, ch.sex)
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
  f.TitleContainer.TitleText:SetText(GI.NAME_MARKUP)
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

    -- Each level carries its own direction: an item level list running high to
    -- low still wants the names it falls back on to run A to Z.
    local function AddDirection(key, isEnabled)
      sortSub:CreateTitle(L["OPT_SORT_DIR"])
      local function getter(v) return GI.Config.Get(key) == v end
      local function setter(v) GI.Config.Set(key, v) GI.RefreshCharacterList() end
      for _, opt in ipairs(DIR_OPTIONS) do
        local radio = sortSub:CreateRadio(L[opt[2]], getter, setter, opt[1])
        radio:SetResponder(function(data)
          setter(data)
          return MenuResponse.Refresh
        end)
        if isEnabled then radio:SetEnabled(isEnabled) end
      end
    end

    sortSub:CreateTitle(L["OPT_SORT_PRIMARY"])
    local function sortGetter(v) return GI.Config.Get("sortOrder") == v end
    local function sortSetter(v)
      GI.Config.Set("sortOrder", v)
      if GI.Config.Get("secondarySort") == v then
        GI.Config.Set("secondarySort", "none")
      end
      GI.RefreshCharacterList()
    end
    for _, opt in ipairs(SORT_OPTIONS) do
      sortSub:CreateRadio(L[opt[2]], sortGetter, sortSetter, opt[1])
        :SetResponder(function(data)
          sortSetter(data)
          return MenuResponse.Refresh
        end)
    end

    AddDirection("sortDir")

    sortSub:CreateSpacer()
    sortSub:CreateTitle(L["OPT_SORT_SECONDARY"])
    local function secGetter(v) return GI.Config.Get("secondarySort") == v end
    local function secSetter(v) GI.Config.Set("secondarySort", v) GI.RefreshCharacterList() end
    -- An order already used as primary is greyed out here, so the two cannot be
    -- set to the same thing; "none" is always available.
    local function AddSecondary(value, label)
      local radio = sortSub:CreateRadio(label, secGetter, secSetter, value)
      radio:SetResponder(function(data)
        secSetter(data)
        return MenuResponse.Refresh
      end)
      if value ~= "none" then
        radio:SetEnabled(function() return GI.Config.Get("sortOrder") ~= value end)
      end
    end

    AddSecondary("none", L["OPT_SORT_NONE"])
    for _, opt in ipairs(SORT_OPTIONS) do
      AddSecondary(opt[1], L[opt[2]])
    end

    AddDirection("secondarySortDir", function()
      return GI.Config.Get("secondarySort") ~= "none"
    end)

    -- ── Group by ──────────────────────────────────────────────────────────────
    -- Also reachable by right-clicking a group header in the character list.
    local groupSub = rootDescription:CreateButton(L["OPT_GROUP_BY"])
    AddGroupByRadios(groupSub, true)

    -- ── Recommendations ───────────────────────────────────────────────────────
    -- Separate from Upgrades: that submenu is about drawing the track in this
    -- window, this one is about the section added to item tooltips.
    local recSub = rootDescription:CreateButton(L["OPT_RECOMMENDATIONS"])

    recSub:CreateTitle(L["OPT_REC_SHOW"])
    local function showGetter(v) return (GI.Config.Get("recommendShow") or "always") == v end
    local function showSetter(v) GI.Config.Set("recommendShow", v) end
    for _, opt in ipairs(REC_SHOW_OPTIONS) do
      recSub:CreateRadio(L[opt[2]], showGetter, showSetter, opt[1])
    end

    recSub:CreateSpacer()
    recSub:CreateTitle(L["OPT_REC_QUALITY"])
    local function qGetter(v) return (GI.Config.Get("recommendMinQuality") or 2) == v end
    local function qSetter(v) GI.Config.Set("recommendMinQuality", v) end
    for _, opt in ipairs(REC_QUALITY_OPTIONS) do
      recSub:CreateRadio(L[opt[2]], qGetter, qSetter, opt[1])
    end

    recSub:CreateSpacer()
    recSub:CreateTitle(L["OPT_REC_IGNORE"])
    recSub:CreateCheckbox(
      L["OPT_REC_IGNORE_LEVEL"],
      function() return GI.Config.Get("recommendIgnoreLevel") ~= false end,
      function() GI.Config.Set("recommendIgnoreLevel", GI.Config.Get("recommendIgnoreLevel") == false) end
    )
    recSub:CreateCheckbox(
      L["OPT_REC_IGNORE_OFFSPEC"],
      function() return GI.Config.Get("recommendIgnoreOffspec") == true end,
      function() GI.Config.Set("recommendIgnoreOffspec", GI.Config.Get("recommendIgnoreOffspec") ~= true) end
    )
    recSub:CreateCheckbox(
      L["OPT_REC_IGNORE_BOE"],
      function() return GI.Config.Get("recommendIgnoreBoE") == true end,
      function() GI.Config.Set("recommendIgnoreBoE", GI.Config.Get("recommendIgnoreBoE") ~= true) end
    )

    -- ── Upgrades ──────────────────────────────────────────────────────────────
    local upSub = rootDescription:CreateButton(L["OPT_UPGRADES"])

    upSub:CreateTitle(L["OPT_UPGRADE_TRACK"])
    upSub:CreateCheckbox(
      L["OPT_COLORED"],
      function() return GI.Config.Get("colorUpgradeTrack") ~= false end,
      function() GI.Config.Set("colorUpgradeTrack", GI.Config.Get("colorUpgradeTrack") == false) end
    )

    upSub:CreateSpacer()
    upSub:CreateTitle(L["OPT_UPGRADE_RANK"])
    upSub:CreateCheckbox(
      L["OPT_COLORED"],
      function() return GI.Config.Get("colorUpgradeRank") ~= false end,
      function() GI.Config.Set("colorUpgradeRank", GI.Config.Get("colorUpgradeRank") == false) end
    )
    upSub:CreateCheckbox(
      L["OPT_RANK_AS_STARS"],
      function() return GI.Config.Get("upgradeRankAsStars") ~= false end,
      function() GI.Config.Set("upgradeRankAsStars", GI.Config.Get("upgradeRankAsStars") == false) end
    )

    rootDescription:CreateSpacer()

    -- ── Minimap ───────────────────────────────────────────────────────────────
    rootDescription:CreateCheckbox(
      L["OPT_SHOW_MINIMAP"],
      function() return GI.db and GI.db.config and GI.db.config.minimapButton
                     and not GI.db.config.minimapButton.hide end,
      function() GI.ToggleMinimapButton() end
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

    rootDescription:CreateButton(L["EXPORT_ALL"], GI.ShowExportAll)

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

  GI.MaskCircle(charJumpBtn, cjBg)

  local cjIcon = charJumpBtn:CreateTexture(nil, "ARTWORK")
  cjIcon:SetSize(22, 22)
  cjIcon:SetPoint("CENTER")
  cjIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Textures sit on the button rather than in a GI.CreateCircleIcon frame: the
  -- pressed state nudges the icon a pixel, which a wrapper would absorb.
  GI.MaskCircle(charJumpBtn, cjIcon)

  -- Border stays fixed; recolored gold on hover via OnEnter/OnLeave
  local cjBorder = charJumpBtn:CreateTexture(nil, "OVERLAY")
  cjBorder:SetSize(26, 26)
  cjBorder:SetPoint("CENTER")
  cjBorder:SetAtlas(GI.ATLAS.RACE_BORDER)

  local cjClassR, cjClassG, cjClassB = 1, 1, 1  -- cached class color for hover restore

  local function RefreshCharJumpBtn()
    if not GI.db then charJumpBtn:Hide() return end
    local key = GI.PlayerKey()
    local d   = GI.db.characters[key]
    local ch  = d and d.character
    if not ch then charJumpBtn:Hide() return end
    cjClassR, cjClassG, cjClassB = GI.ClassRGB(ch.class)
    local atlas = GI.RaceAtlas(ch.race, ch.sex)
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
    local key = GI.PlayerKey()
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
  itemsLabel:SetText("|cFF8A6A30" .. L["LABEL_ITEMS"] .. "|r")

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
    if (key == "colorUpgradeRank" or key == "colorUpgradeTrack"
        or key == "upgradeRankAsStars") and selectedKey then
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
  local orderAsc  = GI.Config.Get("sortDir")          == "asc"
  local secAsc    = GI.Config.Get("secondarySortDir") == "asc"

  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end

  table.sort(sorted, function(a, b)
    local r = CompareBy(a, b, order, orderAsc)
    if r ~= nil then return r end
    if secondary ~= "none" and secondary ~= order then
      local r2 = CompareBy(a, b, secondary, secAsc)
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
  local raceMarkup = GI.RaceIconMarkup(ch.race, ch.sex, 16)
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
    rH, gH, bH, GI.ClassDisplayName(ch.class, ch.sex),
    ch.level or 0, ilvlPart, agePart)

  PrefetchTooltipData(specSlots)

  for _, row in ipairs(gearRows) do row:Hide() end

  for i, slot in ipairs(GI.GEAR_SLOTS) do
    local row  = GetOrCreateGearRow(i)
    local item = specSlots and specSlots["s" .. slot.id]

    if item then
      row.itemData = item
      row.itemLink = item.link

      row.iconT:SetTexture(item.icon or EMPTY_SLOT_ICON[slot.id])
      row.iconT:SetAlpha(item.cached == false and 0.45 or 1.0)

      local qr, qg, qb = QColor(item.quality or 1)

      -- Resolved from the client rather than stored: a saved name would be in
      -- the language of whoever scanned the item, and an imported character
      -- would show it verbatim -- unreadable in a client whose font has no
      -- glyphs for that script.
      row.nameFS:SetText(C_Item.GetItemInfo(item.link or item.id) or L["ITEM_LOADING"])
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

      -- Slot name, upgrade track, then the rank as a star bar. The track is
      -- resolved from the item link on every render (never read from the DB), so
      -- a season change applies to saved characters without rescanning them —
      -- see GI.GetSlotUpgrade.
      local up = GI.GetSlotUpgrade(item)
      if up then
        -- Track ranks run 1..5 and line up exactly with item quality: common,
        -- uncommon, rare, epic, legendary. No separate palette needed.
        local trackHex = PLAIN_HEX
        if GI.Config.Get("colorUpgradeTrack") ~= false then
          local tr, tg, tb = QColor(up.rank)
          trackHex = string.format("%02X%02X%02X", tr * 255, tg * 255, tb * 255)
        end
        local trackText = "|cFF" .. trackHex .. (GI.TrackName(item.link, up) or L[up.key]) .. "|r"

        -- Rank colour is item quality shifted by one: 1/6 poor grey, 2/6 common
        -- white, 3/6 uncommon green, 4/6 rare blue, 5/6 epic, 6/6 legendary.
        local rr, rg, rb = PLAIN_R, PLAIN_G, PLAIN_B
        if GI.Config.Get("colorUpgradeRank") ~= false then
          rr, rg, rb = QColor(up.cur - 1)
        end

        -- Bar spans the track's own length, so a track with a different number
        -- of ranks scales on its own.
        local asStars   = GI.Config.Get("upgradeRankAsStars") ~= false
        local starCount = asStars and up.max or 0
        local rankText  = ""
        if not asStars then
          rankText = string.format("  |cFF%02X%02X%02X%d/%d|r",
            rr * 255, rg * 255, rb * 255, up.cur, up.max)
        end

        -- Reserve the bar width first, set the text, then place the bar: it
        -- anchors off the rendered text width, so the order matters.
        -- Separator forced white — the fontstring itself is dimmed grey.
        local barW = RankBarWidth(starCount, GI.SpaceWidth(row.slotFS))
        row.slotFS:SetPoint("RIGHT", row.textGroup, "RIGHT", -barW, 0)
        row.slotFS:SetText(L[slot.key] .. " |cFFFFFFFF::|r " .. trackText .. rankText)
        LayoutRankStars(row, starCount, up.cur, rr, rg, rb)
      else
        -- Rows are recycled between characters, so the bar has to be cleared
        -- explicitly when the item has no track.
        LayoutRankStars(row, 0)
        row.slotFS:SetPoint("RIGHT", row.textGroup, "RIGHT", 0, 0)
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
      LayoutRankStars(row, 0)
      row.slotFS:SetPoint("RIGHT", row.textGroup, "RIGHT", 0, 0)
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

-- charKey is optional: given one, the selection is cleared only when it points at
-- that character; without one, it is cleared unconditionally.
function GI.ClearMainWindowSelection(charKey)
  if charKey and selectedKey ~= charKey then return end
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
      local key = GI.PlayerKey()
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

-- ─── Callback: invoked by main.lua ────────────────────────────────────────────

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
  local raceIcon    = GI.RaceIconMarkup(ch.race, ch.sex)
  return raceIcon .. GI.Colorize(GI.DisplayName(ch), r, g, b)
end

-- Exports a single character and opens the copy dialog. Shared by the character
-- row context menu and the Saved Characters panel, so the two cannot drift.
function GI.ShowExportCharacter(charKey)
  local str = GI.ExportCharacter(charKey)
  if not str then
    GI.Print(L["EXPORT_ERR"])
    return
  end
  GI.Print(string.format(L["EXPORT_OK_CHAR"], CharImportMarkup(charKey)))
  StaticPopup_Show("GEARINVENTORY_EXPORT", nil, nil, str)
end

-- Exports every saved character and opens the copy dialog.
function GI.ShowExportAll()
  local str = GI.ExportAll()
  if not str then
    GI.Print(L["EXPORT_ERR"])
    return
  end
  GI.Print(L["EXPORT_OK_FULL"])
  StaticPopup_Show("GEARINVENTORY_EXPORT", nil, nil, str)
end

-- Writes parsed import data and reports the outcome in chat.
-- Used by both import paths — the plain one and the overwrite confirmation — so
-- that neither can drift in how it reads what GI.ApplyImport returns.
local function ApplyImportAndPrint(importType, importData, skipExisting)
  local count, overwritten, merged, skipped, charKey, writtenKeys =
    GI.ApplyImport(importType, importData, skipExisting)

  if importType == "char" then
    if count == 0 and overwritten == 0 and merged == 0 then
      GI.Print(L["IMPORT_SKIP_CURRENT"])
    else
      GI.Print(string.format(L["IMPORT_OK_CHAR"], CharImportMarkup(charKey)))
    end
  else
    -- Assembled from fragments: only non-zero counts are listed, and "imported"
    -- always is, so an import that wrote nothing still says so.
    local parts = { string.format(L["IMPORT_N_IMPORTED"], count) }
    if overwritten > 0 then
      parts[#parts + 1] = string.format(L["IMPORT_N_OVERWRITTEN"], overwritten)
    end
    if merged > 0 then
      parts[#parts + 1] = string.format(L["IMPORT_N_MERGED"], merged)
    end
    if skipped > 0 then
      parts[#parts + 1] = string.format(L["IMPORT_N_SKIPPED"], skipped)
    end
    GI.Print(table.concat(parts, ", ") .. ".")
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
    -- Order matters: DeleteAllCharacters rescans the current character at the
    -- end, which re-adds them to a now-empty DB. Clear the old selection first,
    -- then select whoever survived, so the panel never shows deleted gear and
    -- never sits on the placeholder while a character is listed.
    GI.ClearMainWindowSelection()
    GI.DeleteAllCharacters()
    GI.RefreshCharacterList()
    local key = GI.PlayerKey()
    if GI.db and GI.db.characters[key] then
      GI.ShowCharacterGear(key)
    end
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
      -- Only the version mismatch is worth its own wording; everything else is
      -- indistinguishable to the user, who just needs to know the string is bad.
      if err == "version" then
        GI.Print(L["IMPORT_ERR_VERSION"])
      else
        GI.Print(L["IMPORT_INVALID"])
      end
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
