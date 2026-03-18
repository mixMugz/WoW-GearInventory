-- GearInventory/Addons/UI.lua
-- Main window, character list panel, gear slot panel, item tooltips.
-- All UI creation is deferred until GI.ToggleMainWindow() is first called.

local addonName, GI = ...
local L = GI.L

-- ─── Layout Constants ─────────────────────────────────────────────────────────

local DEFAULT_W   = 760
local DEFAULT_H   = 480
local MIN_W       = 640
local MIN_H       = 480
local TITLE_H     = 30
local CHAR_LIST_W = 200
local DIVIDER_X   = CHAR_LIST_W + 13  -- 213
local GEAR_X      = DIVIDER_X + 3     -- 216
local BODY_TOP_Y  = -(TITLE_H + 14)
local BODY_BOT_Y  = 12
local CHAR_ROW_H  = 28
local GEAR_ROW_H  = 26
local GEAR_HDR_H  = 52
local COL_HDR_H   = 20
local SB_PAD      = 22  -- right padding for gear scrollbar inside the window

-- ─── Quality Colors ───────────────────────────────────────────────────────────

local QUALITY_COLOR = {
  [0] = { 0.62, 0.62, 0.62 }, -- Poor
  [1] = { 1.00, 1.00, 1.00 }, -- Common
  [2] = { 0.12, 1.00, 0.00 }, -- Uncommon
  [3] = { 0.00, 0.44, 0.87 }, -- Rare
  [4] = { 0.64, 0.21, 0.93 }, -- Epic
  [5] = { 1.00, 0.50, 0.00 }, -- Legendary
  [6] = { 0.90, 0.80, 0.50 }, -- Artifact
  [7] = { 0.00, 0.80, 1.00 }, -- Heirloom
}

local function QColor(quality)
  local c = QUALITY_COLOR[quality] or QUALITY_COLOR[1]
  return c[1], c[2], c[3]
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

local charButtons = {}
local gearRows    = {}
local selectedKey = nil

-- ─── Character List Button ────────────────────────────────────────────────────

local function GetOrCreateCharButton(idx)
  if charButtons[idx] then return charButtons[idx] end

  local parent = GI.mainWindow.charScrollChild
  local btn    = CreateFrame("Button", nil, parent)
  btn:SetHeight(CHAR_ROW_H)
  btn:SetPoint("TOPLEFT", 0, -(idx - 1) * CHAR_ROW_H)
  btn:SetPoint("RIGHT",   0, 0)

  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(0.3, 0.55, 0.9, 0.2)

  local sel = btn:CreateTexture(nil, "BACKGROUND")
  sel:SetAllPoints()
  sel:SetColorTexture(0.2, 0.42, 0.8, 0.3)
  sel:Hide()
  btn.selBg = sel

  local raceIcon = btn:CreateTexture(nil, "ARTWORK")
  raceIcon:SetSize(18, 18)
  raceIcon:SetPoint("LEFT", 2, 0)
  btn.raceIcon = raceIcon

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("LEFT", 22, 0)
  btn.classIcon = icon

  local nameFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("LEFT", 46, 2)
  nameFS:SetPoint("RIGHT", -44, 0)
  nameFS:SetJustifyH("LEFT")
  btn.nameFS = nameFS

  local ilvlFS = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ilvlFS:SetPoint("RIGHT", -4, 0)
  ilvlFS:SetWidth(40)
  ilvlFS:SetJustifyH("RIGHT")
  btn.ilvlFS = ilvlFS

  btn:SetScript("OnClick", function(self)
    if not self.charKey then return end
    for _, b in ipairs(charButtons) do
      if b.selBg then b.selBg:Hide() end
    end
    self.selBg:Show()
    GI.ShowCharacterGear(self.charKey)
  end)

  charButtons[idx] = btn
  return btn
end

-- ─── Gear Row ─────────────────────────────────────────────────────────────────

local function GetOrCreateGearRow(idx)
  if gearRows[idx] then return gearRows[idx] end

  local parent = GI.mainWindow.gearScrollChild
  local row    = CreateFrame("Frame", nil, parent)
  row:SetHeight(GEAR_ROW_H)
  row:SetPoint("TOPLEFT", 0, -(idx - 1) * GEAR_ROW_H)
  row:SetPoint("RIGHT",   0, 0)

  if idx % 2 == 0 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.14, 0.55)
  end

  local iconT = row:CreateTexture(nil, "ARTWORK")
  iconT:SetSize(20, 20)
  iconT:SetPoint("LEFT", 2, 0)
  iconT:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.iconT = iconT

  local slotFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slotFS:SetPoint("LEFT", 26, 0)
  slotFS:SetWidth(68)
  slotFS:SetJustifyH("LEFT")
  slotFS:SetTextColor(0.6, 0.6, 0.6)
  row.slotFS = slotFS

  local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameFS:SetPoint("LEFT", 98, 0)
  nameFS:SetPoint("RIGHT", -52, 0)  -- stretch with row; leaves room for ilvl
  nameFS:SetJustifyH("LEFT")
  row.nameFS = nameFS

  local ilvlFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ilvlFS:SetPoint("RIGHT", -4, 0)
  ilvlFS:SetWidth(44)
  ilvlFS:SetJustifyH("RIGHT")
  row.ilvlFS = ilvlFS

  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if self.itemLink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(self.itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  gearRows[idx] = row
  return row
end

-- ─── Main Window Creation ─────────────────────────────────────────────────────

local function CreateMainWindow()
  local f = CreateFrame("Frame", "GearInventoryMainFrame", UIParent, "BackdropTemplate")
  f:SetSize(DEFAULT_W, DEFAULT_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetResizeBounds(MIN_W, MIN_H)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop",  f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()

  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:SetBackdropColor(0.05, 0.05, 0.12, 0.97)

  tinsert(UISpecialFrames, "GearInventoryMainFrame")

  -- Title bar
  local titleBg = f:CreateTexture(nil, "ARTWORK")
  titleBg:SetPoint("TOPLEFT",  12, -12)
  titleBg:SetPoint("TOPRIGHT", -12, -12)
  titleBg:SetHeight(TITLE_H)
  titleBg:SetColorTexture(0.08, 0.1, 0.22, 0.9)

  local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFS:SetPoint("TOPLEFT", 22, -16)
  titleFS:SetText("|cFF00C9FFGear|r|cFFFFFFFFInventory|r")

  local verFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  verFS:SetPoint("LEFT", titleFS, "RIGHT", 6, 0)
  verFS:SetText("|cFF555555v" .. GI.VERSION .. "|r")

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- Resize grip (bottom-right corner)
  local resizeBtn = CreateFrame("Button", nil, f)
  resizeBtn:SetSize(16, 16)
  resizeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
  resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizeBtn:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
  end)
  resizeBtn:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

  -- Horizontal divider below title
  local hDiv = f:CreateTexture(nil, "ARTWORK")
  hDiv:SetHeight(1)
  hDiv:SetColorTexture(0.22, 0.22, 0.40, 1)
  hDiv:SetPoint("TOPLEFT",  14, BODY_TOP_Y + 1)
  hDiv:SetPoint("TOPRIGHT", -14, BODY_TOP_Y + 1)

  -- ── Left panel: Character list (mousewheel scroll, no visible scrollbar) ───

  local charLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  charLabel:SetPoint("TOPLEFT", 18, BODY_TOP_Y - 4)
  charLabel:SetText("|cFF888888" .. L["PANEL_CHARACTERS"] .. "|r")

  local charSF = CreateFrame("ScrollFrame", "GICharScrollFrame", f)
  charSF:SetPoint("TOPLEFT",    14, BODY_TOP_Y - 22)
  charSF:SetPoint("BOTTOMLEFT", 14, BODY_BOT_Y)
  charSF:SetWidth(CHAR_LIST_W - 2)
  charSF:EnableMouseWheel(true)
  charSF:SetScript("OnMouseWheel", function(self, delta)
    local cur  = self:GetVerticalScroll()
    local maxS = self:GetVerticalScrollRange()
    local step = CHAR_ROW_H * 3
    self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * step)))
  end)

  local charSC = CreateFrame("Frame", "GICharScrollChild", charSF)
  charSC:SetWidth(CHAR_LIST_W - 4)
  charSC:SetHeight(1)
  charSF:SetScrollChild(charSC)
  f.charScrollChild = charSC

  -- Vertical divider
  local vDiv = f:CreateTexture(nil, "ARTWORK")
  vDiv:SetWidth(1)
  vDiv:SetColorTexture(0.22, 0.22, 0.40, 1)
  vDiv:SetPoint("TOP",    f, "TOPLEFT",    DIVIDER_X, BODY_TOP_Y)
  vDiv:SetPoint("BOTTOM", f, "BOTTOMLEFT", DIVIDER_X, BODY_BOT_Y)

  -- ── Right panel: Character info header ─────────────────────────────────────

  local rX = GEAR_X

  local charNameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  charNameFS:SetPoint("TOPLEFT", rX, BODY_TOP_Y - 4)
  charNameFS:SetText("|cFF555555" .. L["HINT_SELECT_CHAR"] .. "|r")
  f.charNameFS = charNameFS

  local charInfoFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  charInfoFS:SetPoint("TOPLEFT", rX, BODY_TOP_Y - 28)
  charInfoFS:SetText("")
  f.charInfoFS = charInfoFS

  -- Rescan button (right-aligned, shown only for the current character)
  local scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scanBtn:SetSize(64, 22)
  scanBtn:SetPoint("TOPRIGHT", -14, BODY_TOP_Y - 4)
  scanBtn:SetText(L["BTN_RESCAN"])
  scanBtn:Hide()
  scanBtn:SetScript("OnClick", function()
    GI.ScanCurrentCharacter()
  end)
  f.scanBtn = scanBtn

  -- Last-update label (positioned to the left of the Rescan button)
  local lastUpdateFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  lastUpdateFS:SetPoint("RIGHT", scanBtn, "LEFT", -8, 0)
  lastUpdateFS:SetJustifyH("RIGHT")
  lastUpdateFS:SetText("")
  f.lastUpdateFS = lastUpdateFS

  -- ── Column headers ─────────────────────────────────────────────────────────

  local colY = BODY_TOP_Y - GEAR_HDR_H

  local slotHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slotHdr:SetPoint("TOPLEFT", rX + 26, colY)
  slotHdr:SetText("|cFF777777" .. L["COL_SLOT"] .. "|r")

  local nameHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameHdr:SetPoint("TOPLEFT", rX + 98, colY)
  nameHdr:SetText("|cFF777777" .. L["COL_ITEM_NAME"] .. "|r")

  local ilvlHdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ilvlHdr:SetPoint("TOPRIGHT", -(14 + SB_PAD + 4), colY)
  ilvlHdr:SetText("|cFF777777" .. L["COL_ILVL"] .. "|r")

  local colDiv = f:CreateTexture(nil, "ARTWORK")
  colDiv:SetHeight(1)
  colDiv:SetColorTexture(0.18, 0.18, 0.32, 0.9)
  colDiv:SetPoint("TOPLEFT",  rX,  colY - COL_HDR_H + 2)
  colDiv:SetPoint("TOPRIGHT", -14, colY - COL_HDR_H + 2)

  -- ── Gear scroll frame (scrollbar repositioned inside the window) ───────────

  local gearTopY = BODY_TOP_Y - GEAR_HDR_H - COL_HDR_H - 2

  local gearSF = CreateFrame("ScrollFrame", "GIGearScrollFrame", f,
    "UIPanelScrollFrameTemplate")
  gearSF:SetPoint("TOPLEFT",     rX, gearTopY)
  gearSF:SetPoint("BOTTOMRIGHT", -(14 + SB_PAD), BODY_BOT_Y)

  -- Move the template scrollbar inside the window border
  local scrollBar = _G["GIGearScrollFrameScrollBar"]
  if scrollBar then
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT",    gearSF, "TOPRIGHT", 4, -16)
    scrollBar:SetPoint("BOTTOMLEFT", gearSF, "BOTTOMRIGHT", 4, 16)
  end

  local gearSC = CreateFrame("Frame", "GIGearScrollChild", gearSF)
  gearSC:SetWidth(DEFAULT_W - GEAR_X - 14 - SB_PAD)
  gearSC:SetHeight(#GI.GEAR_SLOTS * GEAR_ROW_H)
  gearSF:SetScrollChild(gearSC)
  f.gearScrollChild = gearSC

  -- ── Resize callback ────────────────────────────────────────────────────────

  f:SetScript("OnSizeChanged", function(self, width, height)
    if f.gearScrollChild then
      f.gearScrollChild:SetWidth(math.max(width - GEAR_X - 14 - SB_PAD, 100))
    end
  end)

  GI.mainWindow = f
  return f
end

-- ─── Public: Refresh Character List ──────────────────────────────────────────

function GI.RefreshCharacterList()
  local w = GI.mainWindow
  if not w or not GI.db then return end

  local order       = GI.db.config and GI.db.config.sortOrder or "ilvl"
  local playerRealm = GetRealmName()

  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    if order == "name" then
      return (a.data.name or "") < (b.data.name or "")
    elseif order == "class" then
      return (a.data.class or "") < (b.data.class or "")
    else -- "ilvl"
      return (a.data.avgIlvl or 0) > (b.data.avgIlvl or 0)
    end
  end)

  for _, btn in ipairs(charButtons) do btn:Hide() end

  w.charScrollChild:SetHeight(math.max(#sorted * CHAR_ROW_H, 1))

  for i, entry in ipairs(sorted) do
    local btn = GetOrCreateCharButton(i)
    local d   = entry.data
    btn.charKey = entry.key

    local r, g, b = GI.ClassRGB(d.class)

    -- Append realm name only when it differs from the current server
    local displayName = d.name or "?"
    if d.realm and d.realm ~= playerRealm then
      displayName = displayName .. "-" .. d.realm
    end
    btn.nameFS:SetText(displayName)
    btn.nameFS:SetTextColor(r, g, b)

    local ready = GI.IsIlvlReady(entry.key)
    if d.avgIlvl ~= nil then
      local suffix = not ready and "|cFF666666~|r" or ""
      btn.ilvlFS:SetText("|cFFFFD700" .. d.avgIlvl .. "|r" .. suffix)
    elseif not ready then
      btn.ilvlFS:SetText("|cFF666666...|r")
    else
      btn.ilvlFS:SetText("|cFF666666?|r")
    end

    if d.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.class] then
      btn.classIcon:SetTexture(
        "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
      btn.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[d.class]))
    else
      btn.classIcon:SetTexture(nil)
    end

    local raceAtlas = GI.RaceAtlas(d.raceFile, d.sex)
    if raceAtlas then
      btn.raceIcon:SetAtlas(raceAtlas)
      btn.raceIcon:Show()
    else
      btn.raceIcon:Hide()
    end

    if entry.key == selectedKey then btn.selBg:Show() else btn.selBg:Hide() end

    btn:Show()
  end
end

-- ─── Public: Show Gear for a Character ───────────────────────────────────────

function GI.ShowCharacterGear(charKey)
  selectedKey = charKey
  local w = GI.mainWindow
  if not w or not GI.db then return end

  local d = GI.db.characters[charKey]
  if not d then return end

  local r, g, b = GI.ClassRGB(d.class)
  local rH = math.floor(r * 255)
  local gH = math.floor(g * 255)
  local bH = math.floor(b * 255)

  -- Character name — show realm suffix only if it differs from the current one
  local playerRealm = GetRealmName()
  local realmSuffix = ""
  if d.realm and d.realm ~= playerRealm then
    realmSuffix = "|cFF666666-" .. d.realm .. "|r"
  end
  local raceMarkup = GI.RaceIconMarkup(d.raceFile, d.sex, 16)
  w.charNameFS:SetFormattedText(
    "%s|cFF%02X%02X%02X%s|r%s",
    raceMarkup, rH, gH, bH, d.name or "?", realmSuffix)

  -- Character info line (class, level, avg ilvl — NO last-update here)
  local ready = GI.IsIlvlReady(charKey)
  local ilvlPart
  if d.avgIlvl ~= nil then
    local marker = not ready and " |cFF666666~|r" or ""
    ilvlPart = string.format("  |cFFFFD700" .. L["CHAR_AVG_ILVL"] .. "|r", d.avgIlvl) .. marker
  elseif not ready then
    ilvlPart = "  |cFF666666...|r"
  else
    ilvlPart = ""
  end
  w.charInfoFS:SetFormattedText(
    "|cFF%02X%02X%02X%s|r  |cFFFFFFFF\226\128\162 " .. L["CHAR_LEVEL"] .. "|r%s",
    rH, gH, bH, ClassDisplayName(d.class),
    d.level or 0, ilvlPart)

  -- Last-update text + Rescan button positioning
  local currentKey = UnitName("player") .. "-" .. GetRealmName()
  if charKey == currentKey then
    w.scanBtn:Show()
    w.lastUpdateFS:ClearAllPoints()
    w.lastUpdateFS:SetPoint("RIGHT", w.scanBtn, "LEFT", -8, 0)
  else
    w.scanBtn:Hide()
    w.lastUpdateFS:ClearAllPoints()
    w.lastUpdateFS:SetPoint("TOPRIGHT", -14, BODY_TOP_Y - 8)
  end
  w.lastUpdateFS:SetText("|cFF555555" .. FormatAge(d.lastUpdate) .. "|r")

  -- Gear rows
  for _, row in ipairs(gearRows) do row:Hide() end

  local avgIlvl = d.avgIlvl or 0

  for i, slot in ipairs(GI.GEAR_SLOTS) do
    local row  = GetOrCreateGearRow(i)
    local item = d.gear and d.gear[slot.id]

    row.slotFS:SetText(slot.name)

    if item then
      row.iconT:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.iconT:SetAlpha(item.cached == false and 0.45 or 1.0)

      local qr, qg, qb = QColor(item.quality or 1)
      row.nameFS:SetText(item.name or "?")
      row.nameFS:SetTextColor(qr, qg, qb)

      if (item.ilvl or 0) > 0 then
        row.ilvlFS:SetText(tostring(item.ilvl))
        if not ready then
          row.ilvlFS:SetTextColor(0.45, 0.45, 0.45)
        elseif item.ilvl >= avgIlvl then
          row.ilvlFS:SetTextColor(0.0, 0.85, 0.0)
        else
          row.ilvlFS:SetTextColor(0.9, 0.3, 0.3)
        end
      else
        row.ilvlFS:SetText("")
      end

      row.itemLink = item.link
    else
      row.iconT:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      row.iconT:SetAlpha(0.2)
      row.nameFS:SetText("|cFF3A3A3A" .. L["ITEM_EMPTY"] .. "|r")
      row.nameFS:SetTextColor(1, 1, 1)
      row.ilvlFS:SetText("")
      row.itemLink = nil
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
        w.lastUpdateFS:SetText("")
        w.scanBtn:Hide()
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
  local popup = StaticPopup_Show("GEARINVENTORY_DELETE_CHAR",
    (d.name or "?") .. "-" .. (d.realm or "?"))
  if popup then
    popup.data = charKey
  end
end

-- ─── Public: Toggle Window ────────────────────────────────────────────────────

function GI.ToggleMainWindow()
  if not GI.mainWindow then
    CreateMainWindow()
  end

  local w = GI.mainWindow
  if w:IsShown() then
    w:Hide()
    return
  end

  w:Show()
  GI.RefreshCharacterList()

  local autoSelect = not GI.db or not GI.db.config
    or GI.db.config.autoSelect ~= false
  if autoSelect and GI.db then
    local key = UnitName("player") .. "-" .. GetRealmName()
    if GI.db.characters[key] then
      GI.ShowCharacterGear(key)
    end
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
