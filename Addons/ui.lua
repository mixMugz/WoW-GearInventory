-- GearInventory/Addons/ui.lua
-- Main window, character list panel, gear slot panel, item tooltips.
-- All UI creation is deferred until GI.ToggleMainWindow() is first called.

local addonName, GI = ...
local L = GI.L

-- ─── Layout Constants ─────────────────────────────────────────────────────────

local DEFAULT_W   = 550
local FIXED_H     = 600
local CHAR_LIST_W = 180

-- Insets from the border art, written in the border's own units. The border
-- scales separately from the window, so they are converted before use -- see
-- GI.ApplyMainWindowScale.
local TITLE_H    = 30  -- depth of the title bar
local BODY_INSET = 6   -- left, right and bottom

local CHAR_ROW_H     = 28
local GROUP_HEADER_H = 14
local GEAR_ROW_H     = 28

-- Gap above the character list, and the gear list's own right inset.
local CHAR_LIST_TOP_PAD = 4
local GEAR_RIGHT_PAD    = 8

-- How far the info panel stops short of the border art on the sides: the kerb of
-- the NineSlice, in the border's units. Its top stops at the title bar, whose
-- height is asked of the widget rather than guessed -- the template sets it.
local PANEL_EDGE = 3

-- The gear list's own height, and the gap the ITEMS label keeps above it. The
-- info panel is measured against both: it stops clear of the label rather than
-- swallowing it.
local GEAR_LIST_H      = #GI.GEAR_SLOTS * GEAR_ROW_H
local ITEMS_LABEL_GAP  = 4
local PANEL_ITEMS_GAP  = 2  -- between the panel's bottom edge and the label

-- TEMPORARY. A flat colour standing in for the artwork that goes here later; it
-- is up mainly so the zone's edges are visible while the block is being laid
-- out. Strong enough to read as a shape, weak enough that the class-coloured
-- name still carries over it.
local INFO_BG_ALPHA = 0.30

-- FIXED_H is a stated number, not a sum of its parts: the title bar's depth is
-- measured in the border's units and does not add up with the rest. Whatever it
-- leaves over lands between the character info block and the gear list, which is
-- where art is going later -- the list itself is pinned to the bottom edge.

-- ─── Window Scale ─────────────────────────────────────────────────────────────
-- The window is two frames that scale apart from each other.
--
--   The base carries the size and everything in it. It follows the interface
--   slider, but bounded: never so small that a unit is worth less than
--   MIN_UNIT_PX, never so tall that it covers more than MAX_SCREEN_SHARE of the
--   screen. Between the bounds it takes a scale of 1 and behaves like any other
--   window in the game.
--
--   The border is laid over the base, anchored corner to corner rather than
--   sized, so it takes the window's dimensions and answers to the slider alone.
--   Neither bound applies to it: the bounds exist to keep the window a usable
--   size, and the border is not the window -- it is art stretched across
--   whatever size the window came out at.
--
-- The bounds are not equal partners. The ceiling wins outright, because a window
-- hanging over the edge of the screen is no use however sharply it is drawn; the
-- floor applies only in the room the ceiling leaves. A unit below a pixel is
-- what 1920x1080 at a 65% slider produces, and detail starts falling through the
-- grid there -- which is what these two frames were built to stop.
local MIN_UNIT_PX      = 1.4
local MAX_SCREEN_SHARE = 0.9

-- The base frame's own scale, and the effective scale that produces.
local function BoundedScale()
  local _, screenH = GetPhysicalScreenSize()
  local slider     = UIParent:GetEffectiveScale()

  local floorScale   = MIN_UNIT_PX * 768 / screenH
  local ceilingScale = MAX_SCREEN_SHARE * 768 / FIXED_H

  -- Floor first, ceiling last: wherever the two disagree, the ceiling is the one
  -- left standing.
  local effective = math.min(math.max(slider, floorScale), ceilingScale)
  return effective / slider, effective
end

-- Rescales both frames and re-inset the body between them. Called at creation
-- and whenever the slider or the resolution moves.
function GI.ApplyMainWindowScale()
  local f = GI.mainWindow
  if not f then return end

  local own, effective = BoundedScale()
  f:SetScale(own)

  local chromeScale = UIParent:GetEffectiveScale()
  f.chrome:SetScale(chromeScale)

  -- Insets are written against the border art, in the border's units, so they
  -- are converted into the base's before being handed over: an offset is read in
  -- the units of the frame being anchored.
  local k = chromeScale / effective
  f.body:ClearAllPoints()
  f.body:SetPoint("TOPLEFT",     f, "TOPLEFT",      BODY_INSET * k, -TITLE_H * k)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -BODY_INSET * k, BODY_INSET * k)

  -- The info panel goes tight against the border instead, so its corners are
  -- measured off the art: the title bar's own height on top, the NineSlice kerb
  -- on the sides. Everything else about it is layout, in the base's units --
  -- where the character list ends, how tall the gear list is, where the ITEMS
  -- label sits above it.
  local titleH = f.chrome.TitleContainer:GetHeight()
  if not titleH or titleH <= 0 then titleH = TITLE_H end

  -- A font string measures as zero until it has been laid out, which is what an
  -- unshown frame reports, so the label falls back to its own point size.
  local labelH = f.itemsLabel:GetHeight()
  if not labelH or labelH <= 0 then labelH = select(2, f.itemsLabel:GetFont()) or 12 end

  local left   = BODY_INSET * k + (CHAR_LIST_W - 18) + 2 + (f.sbHalf or 0)
  local bottom = BODY_INSET * k + GEAR_LIST_H + ITEMS_LABEL_GAP + labelH + PANEL_ITEMS_GAP

  f.infoPanel:ClearAllPoints()
  f.infoPanel:SetPoint("TOPLEFT",     f, "TOPLEFT",      left,          -titleH * k)
  f.infoPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANEL_EDGE * k, bottom)
end

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
-- Grey used for an average whose gear is still resolving.
local COLD_ILVL_COLOR = "|cFF808080"

-- Items the panel is already waiting on, keyed by id. ContinueOnItemLoad fires
-- once and clears itself, so without this a redraw that still finds the item
-- cold would queue a second wait, and its callback a third.
local awaitingItem = {}

-- One redraw per batch of arrivals. A panel opened cold waits on every slot at
-- once, and the client answers them in the same tick or the next -- and the
-- first answer is usually enough to make the rest readable, so redrawing per
-- callback repeats the same full draw a dozen times over.
local redrawKeys, redrawScheduled = {}, false

local function ScheduleRedraw(charKey)
  if charKey then redrawKeys[charKey] = true end
  if redrawScheduled then return end
  redrawScheduled = true

  C_Timer.After(0, function()
    redrawScheduled = false
    local keys = redrawKeys
    redrawKeys = {}

    local w = GI.mainWindow
    if not (w and w:IsShown()) then return end

    GI.RefreshCharacterList()
    for key in pairs(keys) do
      if GI.IsMainWindowSelection(key) then
        GI.ShowCharacterGear(key)
        break
      end
    end
  end)
end

-- Waits for one item's data and redraws when it lands.
--
-- Blizzard's own path: the callback is registered against the item and fires
-- when ITEM_DATA_LOAD_RESULT reports it, with the request sent underneath. It
-- answers for itself, which the addon's queue could not always do -- an answer
-- that arrived with no matching queue entry left the row on "Loading..." until
-- something else redrew it.
local function AwaitItem(item, charKey)
  local id = item and item.id
  if not id or awaitingItem[id] then return end

  local obj
  if item.link then
    obj = Item:CreateFromItemLink(item.link)
  else
    obj = Item:CreateFromItemID(id)
  end
  if not obj or obj:IsItemEmpty() then return end

  awaitingItem[id] = true
  obj:ContinueOnItemLoad(function()
    awaitingItem[id] = nil
    GI.Trace("loaded id=%d", id)
    ScheduleRedraw(charKey)
  end)
end

-- The item's name if the client can produce one right now, else nil.
--
-- Asked every draw rather than remembered in the database: whether an item is
-- readable is a fact about this session's client cache, and a saved flag would
-- claim "loaded" on the next login while the cache is still cold.
--
-- The saved link is tried first because it carries the character's own bonuses;
-- the bare id is the fallback for a slot saved without one.
local function ItemNameNow(item)
  if not item then return nil end
  if item.link then
    local name = C_Item.GetItemInfo(item.link)
    if name then return name end
  end
  if item.id then
    return (C_Item.GetItemInfo(item.id))
  end
  return nil
end

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
local STAR_SIZE   = 7
local LEAD_SPACES = 2  -- spaces between the label and the first star

-- Ranks not yet earned are drawn as a dimmed copy of the filled star rather than
-- from the outline art: at this size the outline is a hairline, and on a 1080p
-- UI scale it lands under a pixel and all but disappears. A dimmed silhouette
-- keeps the bar's shape readable at any scale. Left silver rather than tinted
-- with the rank colour: an unearned rank has no colour to carry, and a dimmed
-- one only reads as a duller version of the ranks beside it.
local STAR_EMPTY_DIM   = 0.30
local STAR_EMPTY_ALPHA = 0.85

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
        star:SetTexture(GI.TEX.STAR)
        if i <= cur then
          star:SetVertexColor(r, g, b)
          star:SetAlpha(1)
        else
          star:SetVertexColor(STAR_EMPTY_DIM, STAR_EMPTY_DIM, STAR_EMPTY_DIM)
          star:SetAlpha(STAR_EMPTY_ALPHA)
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

-- Width the item level column falls back to when its own text cannot be measured.
local ILVL_COL_FALLBACK_W = 28

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
    -- Every link, cold ones included: GetHyperlink is what pulls the item's own
    -- data in, so filtering to the ones already readable would skip exactly the
    -- slots this is here to warm.
    if item.link then
      local data = C_TooltipInfo.GetHyperlink(item.link)
      if data then PrefetchLines(data.lines) end
    end
  end
end

-- ─── Custom Item Tooltip Renderer ────────────────────────────────────────────
-- Renders lines from C_TooltipInfo.GetHyperlink() manually so GameTooltip.Icon
-- is never set, avoiding the large icon shown above the tooltip frame.
-- GemSocket lines carry gemIcon directly in the data. SellPrice is dropped --
-- see the branch that handles it below.
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
    if parent.itemData and ItemNameNow(parent.itemData) then
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

    -- Built before the name and realm: both end where this column starts, so
    -- neither can run under the item level however long the realm is.
    local ilvlFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlFS:SetPoint("RIGHT", -10, 0)
    ilvlFS:SetText("0000")
    -- Four digits wide, or a fallback: an unshown frame measures its strings as
    -- zero, and a zero-width column would let the name run to the row's edge.
    local minW = ilvlFS:GetStringWidth()
    ilvlFS:SetText("")
    ilvlFS:SetWidth(minW > 0 and minW or ILVL_COL_FALLBACK_W)
    ilvlFS:SetJustifyH("RIGHT")
    btn.ilvlFS = ilvlFS

    local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameFS:SetPoint("LEFT", raceFrame, "RIGHT", 5, 4)
    nameFS:SetPoint("RIGHT", ilvlFS, "LEFT", -4, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    btn.nameFS = nameFS

    -- Realm reads as a subtitle, so its size is taken from the name's own font
    -- rather than from the small font object: locales ship their own sizes for
    -- both, and a fixed offset from the small one lands almost on the name in
    -- some of them. Never wrapped -- the row has no second line to wrap into,
    -- so a realm too wide for the column is truncated instead.
    local nFont, nSize, nFlags = nameFS:GetFont()
    local realmFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmFS:SetFont(nFont, math.max(8, math.floor(nSize * 0.72)), nFlags)
    realmFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, 0)
    realmFS:SetPoint("RIGHT", ilvlFS, "LEFT", -4, 0)
    realmFS:SetJustifyH("LEFT")
    realmFS:SetWordWrap(false)
    realmFS:SetTextColor(0.45, 0.45, 0.45)
    btn.realmFS = realmFS

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

  local listBucket = d.gear and ch.specID and d.gear[ch.specID]
  if listBucket and listBucket.avgIlvl ~= nil then
    -- Grey while items are still on their way, the usual tier colour once they
    -- have landed -- the row says at a glance whether its gear is ready to read.
    local loading = GI.IsCharLoading and GI.IsCharLoading(entry.key)
    local code    = loading and COLD_ILVL_COLOR or IlvlColorCode(listBucket)
    btn.ilvlFS:SetText(code .. listBucket.avgIlvl .. "|r")
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

-- Base frame first, border laid over it, body between the two.
--
-- The base is a plain frame: it owns the size, the position and the name, so
-- Escape and every GI.mainWindow reader still reach the window itself. The
-- border is the templated frame, anchored to the base's corners rather than
-- sized -- it inherits the window's dimensions and scales on its own. Anything
-- that belongs to the title bar goes on the border so it keeps pace with the
-- art; everything else goes in the body, which is inset from the border and
-- scales with the window.
local function CreateMainWindow()
  local f = CreateFrame("Frame", "GearInventoryMainFrame", UIParent)
  f:SetSize(DEFAULT_W, FIXED_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:Hide()

  local chrome = CreateFrame("Frame", nil, f, "PortraitFrameTemplate")
  chrome:SetIgnoreParentScale(true)
  chrome:SetPoint("TOPLEFT",     f, "TOPLEFT")
  chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
  chrome:SetFrameLevel(f:GetFrameLevel() + 1)
  chrome:EnableMouse(true)
  chrome:RegisterForDrag("LeftButton")
  chrome:SetScript("OnDragStart", function() f:StartMoving() end)
  chrome:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
  f.chrome = chrome

  local body = CreateFrame("Frame", nil, f)
  body:SetFrameLevel(chrome:GetFrameLevel() + 5)
  f.body = body

  -- PortraitFrameTemplate provides: chrome.TitleContainer.TitleText,
  -- chrome.PortraitContainer.portrait, chrome.CloseButton
  chrome.TitleContainer.TitleText:SetText(GI.NAME_MARKUP)
  chrome.PortraitContainer:Hide()
  -- Replace portrait corner with standard metal corner
  chrome.NineSlice.TopLeftCorner:SetAtlas(GI.ATLAS.WINDOW_CORNER_TL, true)
  -- Extend title bar to fill the space freed by the hidden portrait
  chrome.TitleContainer:ClearAllPoints()
  chrome.TitleContainer:SetPoint("TOPLEFT", 4, 0)
  chrome.TitleContainer:SetPoint("TOPRIGHT", -24, 0)
  -- Closes the window, not the border it sits on
  chrome.CloseButton:SetScript("OnClick", function() f:Hide() end)

  -- Settings gear dropdown (left of CloseButton)
  local settingsDropdown = CreateFrame("DropdownButton", nil, chrome, "UIPanelIconDropdownButtonTemplate")
  settingsDropdown:SetFrameLevel(chrome.CloseButton:GetFrameLevel() + 2)
  settingsDropdown:SetPoint("RIGHT", chrome.CloseButton, "LEFT", -4, 0)
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

    -- ── Window ────────────────────────────────────────────────────────────────
    rootDescription:CreateCheckbox(
      L["OPT_HIDE_IN_COMBAT"],
      function() return GI.Config.Get("hideInCombat") ~= false end,
      function() GI.Config.Set("hideInCombat", GI.Config.Get("hideInCombat") == false) end
    )

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

  -- Character jump button (left side of title bar) — selects the current player's
  -- character. On the border with the rest of the title bar, so it keeps the
  -- title's scale rather than the window's.
  local charJumpBtn = CreateFrame("Button", nil, chrome)
  charJumpBtn:SetSize(28, 28)
  charJumpBtn:SetFrameLevel(chrome.CloseButton:GetFrameLevel() + 2)
  charJumpBtn:SetPoint("TOPLEFT", chrome, "TOPLEFT", -4, 2)
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
  -- On the border, along with the rest of the window art: anchored by its edges
  -- rather than sized, since the border's units are not the window's.
  if chrome.TopTileStreaks then chrome.TopTileStreaks:Hide() end
  chrome.Bg:Hide()
  local bgJourneys = chrome:CreateTexture(nil, "BACKGROUND", nil, -3)
  bgJourneys:SetAtlas(GI.ATLAS.WINDOW_BG)
  bgJourneys:SetPoint("TOPLEFT",      2, -3)
  bgJourneys:SetPoint("BOTTOMRIGHT", -2,  3)


  -- ── Left panel: Character list (full height) ───────────────────────────────

  -- Store-style: WowScrollBoxList + MinimalScrollBar (auto-hide)
  local charSF = CreateFrame("Frame", "GICharScrollBox", body, "WowScrollBoxList")
  charSF:SetPoint("TOPLEFT",    0, -CHAR_LIST_TOP_PAD)
  charSF:SetPoint("BOTTOMLEFT", 0, 0)
  charSF:SetWidth(CHAR_LIST_W - 18)

  local charSB = CreateFrame("EventFrame", "GICharScrollBar", body, "MinimalScrollBar")
  charSB:SetPoint("TOPLEFT",    charSF, "TOPRIGHT",    2, -CHAR_LIST_TOP_PAD)
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
  local charNameFS = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  charNameFS:SetPoint("LEFT", charSB, "RIGHT", rightX, 0)
  charNameFS:SetPoint("TOP", body, "TOP", 0, -4)
  charNameFS:SetPoint("RIGHT", -8, 0)
  charNameFS:SetJustifyH("LEFT")
  charNameFS:SetWordWrap(false)
  charNameFS:SetText("|cFF555555" .. L["HINT_SELECT_CHAR"] .. "|r")
  f.charNameFS = charNameFS

  local charInfoFS = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  charInfoFS:SetPoint("TOPLEFT", charNameFS, "BOTTOMLEFT", 0, -2)
  charInfoFS:SetPoint("RIGHT", -8, 0)
  charInfoFS:SetJustifyH("LEFT")
  charInfoFS:SetWordWrap(false)
  charInfoFS:SetText("")
  f.charInfoFS = charInfoFS

  -- ── Gear rows container ────────────────────────────────────────────────────
  -- Anchored to the bottom and sized to its rows rather than stretched down from
  -- the label above: the slack in the window has to end up in one place, and the
  -- place for it is above the list, not under it. The body's height moves with
  -- the border's scale -- a title bar drawn at 0.65 leaves more units behind than
  -- one drawn at 1.0 -- so anything anchored top-down puts that difference at the
  -- bottom edge, where it reads as the list floating off the frame.

  local gearSF = CreateFrame("Frame", "GIGearScrollFrame", body)
  gearSF:SetPoint("BOTTOMLEFT", charSB, "BOTTOMRIGHT", rightX, 0)
  gearSF:SetPoint("RIGHT", -GEAR_RIGHT_PAD, 0)
  gearSF:SetHeight(GEAR_LIST_H)

  -- ITEMS label, riding directly above the list
  local itemsLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  itemsLabel:SetPoint("BOTTOMLEFT", gearSF, "TOPLEFT", 0, ITEMS_LABEL_GAP)
  itemsLabel:SetText("|cFF8A6A30" .. L["LABEL_ITEMS"] .. "|r")
  f.itemsLabel = itemsLabel

  local gearSC = CreateFrame("Frame", "GIGearScrollChild", gearSF)
  gearSC:SetAllPoints()
  f.gearScrollChild = gearSC

  -- Panel behind the character info block, on its own frame between the border
  -- and the body: the text and icons sit over it, and static art laid on it
  -- later will too.
  --
  -- It claims the whole top-right zone, tight against the border art on the top
  -- and both sides, and stopping clear of the ITEMS label at the bottom. That is
  -- why it hangs off the base rather than the body: the body is inset by layout
  -- numbers, not by the thickness of the border, so anchoring to it left a gap.
  -- Its corners are placed by GI.ApplyMainWindowScale, which is where the
  -- border's units get converted.
  local infoPanel = CreateFrame("Frame", nil, f)
  infoPanel:SetFrameLevel(chrome:GetFrameLevel() + 2)

  -- Half the scroll bar's drawn width, from the bar itself rather than a guessed
  -- number: it is scaled down, so half of it is not half of what the template
  -- says. The panel's left edge runs down its middle.
  f.sbHalf = (charSB:GetWidth() or 0) * charSB:GetScale() / 2

  -- Flat fill standing in for the artwork that goes here later, which is also
  -- what makes the zone's edges visible while the block is being laid out.
  local infoBg = infoPanel:CreateTexture(nil, "BACKGROUND")
  infoBg:SetAllPoints()

  infoPanel:Hide()
  f.infoPanel = infoPanel
  f.infoBg    = infoBg

  GI.mainWindow = f
  GI.ApplyMainWindowScale()

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

  local fr, fg, fb = GI.FactionRGB(ch.faction)
  w.infoBg:SetColorTexture(fr, fg, fb, INFO_BG_ALPHA)
  w.infoPanel:Show()

  -- Gear rows
  local specIDKey  = ch.specID or 0
  local specBucket = d.gear and d.gear[specIDKey]
  local specSlots  = specBucket and specBucket.slots

  -- Character info line (class, level, avg ilvl, last update)
  local ilvlPart = ""
  if specBucket and specBucket.avgIlvl ~= nil then
    ilvlPart = "  " .. string.format(L["CHAR_AVG_ILVL"],
      IlvlColorCode(specBucket) .. specBucket.avgIlvl .. "|r")
  end
  local agePart = "  |cFF888888" .. FormatAge(specBucket and specBucket.lastUpdate) .. "|r"
  w.charInfoFS:SetFormattedText(
    "|cFF%02X%02X%02X%s|r  |cFFFFFFFF\226\128\162 " .. L["CHAR_LEVEL"] .. "|r%s%s",
    rH, gH, bH, GI.ClassDisplayName(ch.class, ch.sex),
    ch.level or 0, ilvlPart, agePart)

  PrefetchTooltipData(specSlots)

  for _, row in ipairs(gearRows) do row:Hide() end

  if GI.TraceEnabled() then
    local cold, total = 0, 0
    for _, slot in ipairs(GI.GEAR_SLOTS) do
      local item = specSlots and specSlots["s" .. slot.id]
      if item then
        total = total + 1
        if not ItemNameNow(item) then cold = cold + 1 end
      end
    end
    GI.Trace("show %s: %d of %d slots cold", charKey, cold, total)
  end

  for i, slot in ipairs(GI.GEAR_SLOTS) do
    local row  = GetOrCreateGearRow(i)
    local item = specSlots and specSlots["s" .. slot.id]

    if item then
      row.itemData = item
      row.itemLink = item.link

      -- Resolved from the client rather than stored: a saved name would be in
      -- the language of whoever scanned the item, and an imported character
      -- would show it verbatim -- unreadable in a client whose font has no
      -- glyphs for that script.
      --
      -- Anything the client cannot produce yet is requested here and draws as
      -- "Loading..."; the load result redraws the panel with the real name.
      local itemName = ItemNameNow(item)
      if not itemName then
        AwaitItem(item, charKey)
      end

      row.iconT:SetTexture(item.icon or EMPTY_SLOT_ICON[slot.id])
      row.iconT:SetAlpha(itemName and 1.0 or 0.45)

      local qr, qg, qb = QColor(item.quality or 1)

      row.nameFS:SetText(itemName or L["ITEM_LOADING"])
      if itemName then
        row.nameFS:SetTextColor(qr, qg, qb)
      else
        row.nameFS:SetTextColor(0.5, 0.5, 0.5)
      end

      -- iLvl badge on icon — colored by item quality
      if (item.ilvl or 0) > 0 then
        row.ilvlFS:SetText(tostring(item.ilvl))
        row.ilvlFS:SetTextColor(qr, qg, qb)
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
    w.infoPanel:Hide()
    for _, row in ipairs(gearRows) do row:Hide() end
  end
end

-- ─── Public: Toggle Window ────────────────────────────────────────────────────

-- Set while the window is down only because combat put it down, so leaving
-- combat can tell "the player had it open" from "the player never opened it".
-- Private to this file; main.lua goes through the two functions below.
local hiddenByCombat = false

-- Brings the window up and refreshes it. Shared by the toggle and by the
-- post-combat restore, so the two cannot drift apart.
--
-- It warms tooltip data for every saved character, so the first hover over a
-- socket is not an empty tooltip, then restores the previous selection -- or
-- the played character, when there was no previous one.
local function ShowMainWindow()
  local w = GI.mainWindow
  w:Show()
  w:Raise()
  -- No warm-up here. The client cache is filled once at login and stays
  -- filled for the session, so re-queueing every slot on each open would only
  -- flash the rows grey and the names through "Loading..." again.
  --
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
end

-- Shows the window, building it on the first call, or hides it if it is already
-- up. With "hide in combat" on, opening is skipped in combat -- there would be
-- nothing to see, the window is about to be hidden anyway.
function GI.ToggleMainWindow()
  if not GI.mainWindow then
    CreateMainWindow()
  end

  local w = GI.mainWindow

  if not w:IsShown() then
    if InCombatLockdown() and GI.Config.Get("hideInCombat") ~= false then return end
    hiddenByCombat = false
    ShowMainWindow()
  else
    -- A hand-closed window stays closed when combat ends.
    hiddenByCombat = false
    w:Hide()
  end
end

-- ─── Public: Combat Visibility ────────────────────────────────────────────────

-- Called by main.lua on entering combat. Only an open window is remembered:
-- one that was already down stays down when combat ends.
function GI.HideMainWindowForCombat()
  if GI.Config.Get("hideInCombat") == false then return end
  local w = GI.mainWindow
  if w and w:IsShown() then
    hiddenByCombat = true
    w:Hide()
  end
end

-- Called by main.lua on leaving combat. Puts back only what combat took down,
-- even if the option was switched off mid-fight -- the window was hidden under
-- the old setting, so it is owed a restore under it too.
function GI.RestoreMainWindowAfterCombat()
  if not hiddenByCombat then return end
  hiddenByCombat = false
  if GI.mainWindow then ShowMainWindow() end
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
  -- charKey is optional: a batched redraw passes it only when the selected
  -- character was one of the ones that changed. Both being nil is not a match.
  if charKey and charKey == selectedKey then
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
