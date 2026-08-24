-- GearInventory/Options/characters.lua
-- "Saved Characters" subcategory panel for the Settings UI.

local addonName, GI = ...
local L = GI.L

local charPanel
local CHAR_ROW_H       = 22
local MAX_SPECS_IN_ROW = 4

-- Slot geometry
local SPEC_ICON_W      = 14
local SPEC_ICON_CB_GAP = 2
local SPEC_CB_W        = 20
local SPEC_CB_SCALE    = 0.75
local SPEC_SLOT_GAP    = 6
local SPEC_ZONE_PAD    = 10
local DEL_BTN_SIZE     = 16
local DEL_ZONE_PAD     = 10
local EXP_BTN_SIZE     = 16
local EXP_ZONE_PAD     = 10
local LASTUPD_ZONE_PAD = 18
local LEVEL_ZONE_W     = 22  -- right-aligned level column at the row start, fits 3 digits

local HEADER_PAD = 6  -- 3px each side

local SPEC_CB_EFF = math.floor(SPEC_CB_W * SPEC_CB_SCALE)  -- effective cb width in parent coords

local function FormatTimestamp(ts)
  if not ts then return "--" end
  return date("%d.%m.%y %H:%M", ts)
end

-- Column widths, right to left: DELETE, EXPORT, RECOMMENDATIONS, LASTUPDATE.
-- Each is the wider of its content and its header text.
local function CalcColWidths(maxSpecs, recHeaderW, delHeaderW, expHeaderW, lastUpdHeaderW, lastUpdContentW)
  local n = math.max(1, math.min(maxSpecs, MAX_SPECS_IN_ROW))
  local specsW = n * (SPEC_ICON_W + SPEC_ICON_CB_GAP + SPEC_CB_EFF)
               + (n - 1) * SPEC_SLOT_GAP
               + SPEC_ZONE_PAD
  local colSpecsW   = math.max(specsW,  (recHeaderW   or 0) + HEADER_PAD)
  local colDeleteW  = math.max(DEL_BTN_SIZE + DEL_ZONE_PAD, (delHeaderW or 0) + HEADER_PAD)
  local colExportW  = math.max(EXP_BTN_SIZE + EXP_ZONE_PAD, (expHeaderW or 0) + HEADER_PAD)
  local colLastUpdW = math.max((lastUpdContentW or 0) + LASTUPD_ZONE_PAD, (lastUpdHeaderW or 0) + HEADER_PAD)
  return colSpecsW, colDeleteW, colExportW, colLastUpdW
end

-- ─── Refresh ──────────────────────────────────────────────────────────────────

local function RefreshCharPanel()
  if not charPanel or not GI.db or not charPanel.scrollBox then return end

  -- Find max saved spec count across all characters
  local maxSpecs = 0
  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    local count = 0
    if data.gear then
      for specID in pairs(data.gear) do
        if specID ~= 0 then count = count + 1 end
      end
    end
    if count > maxSpecs then maxSpecs = count end
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    return ((a.data.character and a.data.character.name) or "")
         < ((b.data.character and b.data.character.name) or "")
  end)

  -- Recompute column widths using real text sizes (fonts ready at OnShow time)
  local recHeaderW     = charPanel.hRec:GetStringWidth()
  local delHeaderW     = charPanel.hDel:GetStringWidth()
  local expHeaderW     = charPanel.hExp:GetStringWidth()
  local lastUpdHeaderW = charPanel.hLastUpdate:GetStringWidth()

  -- Measure widest lastUpdate content string
  local mFS = charPanel.measureFS
  local maxLastUpdW = 0
  for _, entry in ipairs(sorted) do
    local ch = entry.data.character or {}
    local activeSpecID = ch.specID
    local lastUpdate   = entry.data.gear and activeSpecID
                         and entry.data.gear[activeSpecID]
                         and entry.data.gear[activeSpecID].lastUpdate
    mFS:SetText(FormatTimestamp(lastUpdate))
    local lw = math.ceil(mFS:GetStringWidth())
    if lw > maxLastUpdW then maxLastUpdW = lw end
  end
  mFS:SetText("")

  local colSpecsW, colDeleteW, colExportW, colLastUpdW =
    CalcColWidths(maxSpecs, recHeaderW, delHeaderW, expHeaderW, lastUpdHeaderW, maxLastUpdW)

  charPanel.colSpecsW   = colSpecsW
  charPanel.colDeleteW  = colDeleteW
  charPanel.colExportW  = colExportW
  charPanel.colLastUpdW = colLastUpdW

  local SF_RIGHT_OFS = -20

  -- Headers are anchored right to left, each offset by the columns to its right.
  charPanel.hCharacters:ClearAllPoints()
  charPanel.hCharacters:SetPoint("TOPLEFT", 24, -52)
  charPanel.hCharacters:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT",
    SF_RIGHT_OFS - colDeleteW - colExportW - colSpecsW - colLastUpdW - 4, -52)

  charPanel.hLastUpdate:SetWidth(colLastUpdW)
  charPanel.hLastUpdate:ClearAllPoints()
  charPanel.hLastUpdate:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT",
    SF_RIGHT_OFS - colDeleteW - colExportW - colSpecsW, -52)

  charPanel.hRec:SetWidth(colSpecsW)
  charPanel.hRec:ClearAllPoints()
  charPanel.hRec:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT",
    SF_RIGHT_OFS - colDeleteW - colExportW, -52)

  charPanel.hExp:SetWidth(colExportW)
  charPanel.hExp:ClearAllPoints()
  charPanel.hExp:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS - colDeleteW, -52)

  charPanel.hDel:SetWidth(colDeleteW)
  charPanel.hDel:ClearAllPoints()
  charPanel.hDel:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS, -52)

  local provider = CreateDataProvider()
  for i, entry in ipairs(sorted) do
    entry.idx = i
    provider:Insert(entry)
  end
  charPanel.scrollBox:SetDataProvider(provider)
end

-- ─── Build ────────────────────────────────────────────────────────────────────

local function BuildCharPanel()
  charPanel = CreateFrame("Frame")
  -- Icon trails the label, matching the F.A.Q. subcategory.
  charPanel.name = L["OPT_CHARACTERS"] .. " |A:" .. GI.ATLAS.OPT_CHARACTERS .. ":14:14|a"

  -- Initial column widths (no data yet — use MAX_SPECS_IN_ROW, zero content widths)
  local colSpecsW, colDeleteW, colExportW, colLastUpdW = CalcColWidths(MAX_SPECS_IN_ROW, 0, 0, 0, 0, 0)
  charPanel.colSpecsW   = colSpecsW
  charPanel.colDeleteW  = colDeleteW
  charPanel.colExportW  = colExportW
  charPanel.colLastUpdW = colLastUpdW

  local title = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText(L["OPT_CHARACTERS"])

  -- Panel-wide actions, aligned with the title. Both reuse the same entry points
  -- as the main window settings dropdown, so behaviour and confirmations match.
  local ACTION_BTN_W, ACTION_BTN_H = 90, 22

  local delAllBtn = CreateFrame("Button", nil, charPanel, "UIPanelButtonTemplate")
  delAllBtn:SetSize(ACTION_BTN_W, ACTION_BTN_H)
  delAllBtn:SetText(L["BTN_DELETE_ALL"])
  delAllBtn:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", -20, -18)
  delAllBtn:SetScript("OnClick", function()
    StaticPopup_Show("GEARINVENTORY_DELETE_ALL")
  end)

  local expAllBtn = CreateFrame("Button", nil, charPanel, "UIPanelButtonTemplate")
  expAllBtn:SetSize(ACTION_BTN_W, ACTION_BTN_H)
  expAllBtn:SetText(L["BTN_EXPORT_ALL"])
  expAllBtn:SetPoint("TOPRIGHT", delAllBtn, "TOPLEFT", -6, 0)
  expAllBtn:SetScript("OnClick", function()
    GI.ShowExportAll()
  end)

  local rule = charPanel:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetColorTexture(0.3, 0.3, 0.4, 0.6)
  rule:SetPoint("TOPLEFT",  20, -44)
  rule:SetPoint("TOPRIGHT", -20, -44)

  -- Hidden measure fontstring for dynamic column width computation at OnShow time
  local measureFS = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  measureFS:SetAlpha(0)
  measureFS:SetPoint("TOPLEFT", 0, 0)
  charPanel.measureFS = measureFS

  -- Column headers, left to right: CHARACTERS | LASTUPDATE | RECOMMENDATIONS | EXPORT | DELETE
  -- Right-side headers anchor from panel TOPRIGHT; SF_RIGHT_OFS = scrollbox right edge offset
  local SF_RIGHT_OFS = -20

  local hCharacters = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hCharacters:SetText(L["PANEL_CHARACTERS"])
  hCharacters:SetJustifyH("LEFT")
  hCharacters:SetPoint("TOPLEFT", 24, -52)
  hCharacters:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT",
    SF_RIGHT_OFS - colDeleteW - colSpecsW - colLastUpdW - 4, -52)
  charPanel.hCharacters = hCharacters

  local hLastUpdate = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hLastUpdate:SetText(L["COL_LAST_UPDATE"])
  hLastUpdate:SetJustifyH("CENTER")
  hLastUpdate:SetWidth(colLastUpdW)
  hLastUpdate:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS - colDeleteW - colSpecsW, -52)
  charPanel.hLastUpdate = hLastUpdate

  local hRec = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hRec:SetText(L["COL_RECOMMENDATIONS"])
  hRec:SetJustifyH("CENTER")
  hRec:SetWidth(colSpecsW)
  hRec:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS - colDeleteW - colExportW, -52)
  charPanel.hRec = hRec

  local hExp = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hExp:SetText(L["COL_EXPORT"])
  hExp:SetJustifyH("CENTER")
  hExp:SetWidth(colExportW)
  hExp:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS - colDeleteW, -52)
  charPanel.hExp = hExp

  local hDel = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hDel:SetText(L["COL_DELETE"])
  hDel:SetJustifyH("CENTER")
  hDel:SetWidth(colDeleteW)
  hDel:SetPoint("TOPRIGHT", charPanel, "TOPRIGHT", SF_RIGHT_OFS, -52)
  charPanel.hDel = hDel

  -- WowScrollBoxList + MinimalScrollBar
  local sf = CreateFrame("Frame", "GIOptionsCharScrollBox", charPanel, "WowScrollBoxList")
  sf:SetPoint("TOPLEFT",     20, -68)
  sf:SetPoint("BOTTOMRIGHT", -20, 5)

  local sb = CreateFrame("EventFrame", "GIOptionsCharScrollBar", charPanel, "MinimalScrollBar")
  sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    7, -4)
  sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 7,  4)
  sb:SetScale(0.70)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(CHAR_ROW_H)
  view:SetElementFactory(function(factory, node)
    factory("Frame", function(row, nodeArg)

      -- ── One-time widget setup ──────────────────────────────────────────────
      if not row._gi_setup then
        row._gi_setup = true

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        row.bg = bg

        -- Separators — positions updated in data population
        -- sep1: CHARS | LASTUPDATE
        local sep1 = row:CreateTexture(nil, "ARTWORK")
        sep1:SetWidth(1)
        sep1:SetColorTexture(0.3, 0.3, 0.4, 0.5)
        row.sep1 = sep1

        -- sep2: LASTUPDATE | RECOMMENDATIONS
        local sep2 = row:CreateTexture(nil, "ARTWORK")
        sep2:SetWidth(1)
        sep2:SetColorTexture(0.3, 0.3, 0.4, 0.5)
        row.sep2 = sep2

        -- sep3: RECOMMENDATIONS | EXPORT
        local sep3 = row:CreateTexture(nil, "ARTWORK")
        sep3:SetWidth(1)
        sep3:SetColorTexture(0.3, 0.3, 0.4, 0.5)
        row.sep3 = sep3

        -- sep4: EXPORT | DELETE
        local sep4 = row:CreateTexture(nil, "ARTWORK")
        sep4:SetWidth(1)
        sep4:SetColorTexture(0.3, 0.3, 0.4, 0.5)
        row.sep4 = sep4

        -- Export button — position updated in data population
        local expBtn = CreateFrame("Button", nil, row)
        expBtn:SetSize(EXP_BTN_SIZE, EXP_BTN_SIZE)
        expBtn:SetNormalAtlas("common-icon-exit")
        expBtn:SetHighlightAtlas("common-icon-exit")
        expBtn:GetHighlightTexture():SetVertexColor(0.4, 1, 0.4)
        expBtn:SetScript("OnClick", function()
          if row.charKey then GI.ShowExportCharacter(row.charKey) end
        end)
        row.expBtn = expBtn

        -- Delete button — position updated in data population
        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(DEL_BTN_SIZE, DEL_BTN_SIZE)
        delBtn:SetNormalAtlas("XMarksTheSpot")
        delBtn:SetHighlightAtlas("XMarksTheSpot")
        delBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
        delBtn:SetScript("OnClick", function(self)
          if row.charKey then GI.ShowDeletePicker(self, row.charKey) end
        end)
        row.delBtn = delBtn

        -- Spec slots — right to left, position updated in data population
        row.specSlots = {}
        for i = 1, MAX_SPECS_IN_ROW do
          local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          cb:SetSize(SPEC_CB_W, SPEC_CB_W)
          cb:SetScale(SPEC_CB_SCALE)

          -- Anchor set during data population, not here.
          local specFrame = GI.CreateCircleIcon(row, SPEC_ICON_W, 16)

          row.specSlots[i] = { icon = specFrame.icon, frame = specFrame, cb = cb }
        end

        -- Level, right-aligned in a fixed zone so the numbers line up down the list
        local lvlFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lvlFS:SetWidth(LEVEL_ZONE_W)
        lvlFS:SetJustifyH("RIGHT")
        lvlFS:SetTextColor(1, 1, 1)
        lvlFS:SetPoint("LEFT", 4, 0)
        row.lvlFS = lvlFS

        -- Race icon
        local raceFrame = GI.CreateCircleIcon(row, 14, 16)
        raceFrame:SetPoint("LEFT", lvlFS, "RIGHT", 5, 0)
        row.raceIcon   = raceFrame.icon
        row.raceBorder = raceFrame.border
        row.raceFrame  = raceFrame

        -- Faction icon
        local factionTex = row:CreateTexture(nil, "ARTWORK")
        factionTex:SetSize(14, 14)
        factionTex:SetPoint("LEFT", raceFrame, "RIGHT", 4, 0)
        row.factionTex = factionTex

        -- Name (Name-Realm format)
        local nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS

        -- Last update
        local lastUpdFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        lastUpdFS:SetJustifyH("LEFT")
        lastUpdFS:SetTextColor(0.75, 0.75, 0.75)
        lastUpdFS:SetWordWrap(false)
        row.lastUpdFS = lastUpdFS
      end

      -- ── Data population ───────────────────────────────────────────────────
      if not nodeArg then return end
      local entry = nodeArg.GetData and nodeArg:GetData() or nodeArg
      local d  = entry.data
      local ch = d.character or {}
      row.charKey = entry.key

      local cSW  = charPanel.colSpecsW
      local cDW  = charPanel.colDeleteW
      local cEW  = charPanel.colExportW
      local cLUW = charPanel.colLastUpdW

      -- Alternating row tint
      if (entry.idx or 1) % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.08)
      else
        row.bg:SetColorTexture(0, 0, 0, 0)
      end

      local r, g, b = GI.ClassRGB(ch.class)

      -- Separators
      row.sep1:ClearAllPoints()  -- CHARS | LASTUPDATE
      row.sep1:SetPoint("TOP",    row, "TOPRIGHT",    -(cDW + cEW + cSW + cLUW), 0)
      row.sep1:SetPoint("BOTTOM", row, "BOTTOMRIGHT", -(cDW + cEW + cSW + cLUW), 0)

      row.sep2:ClearAllPoints()  -- LASTUPDATE | RECOMMENDATIONS
      row.sep2:SetPoint("TOP",    row, "TOPRIGHT",    -(cDW + cEW + cSW), 0)
      row.sep2:SetPoint("BOTTOM", row, "BOTTOMRIGHT", -(cDW + cEW + cSW), 0)

      row.sep3:ClearAllPoints()  -- RECOMMENDATIONS | EXPORT
      row.sep3:SetPoint("TOP",    row, "TOPRIGHT",    -(cDW + cEW), 0)
      row.sep3:SetPoint("BOTTOM", row, "BOTTOMRIGHT", -(cDW + cEW), 0)

      row.sep4:ClearAllPoints()  -- EXPORT | DELETE
      row.sep4:SetPoint("TOP",    row, "TOPRIGHT",    -cDW, 0)
      row.sep4:SetPoint("BOTTOM", row, "BOTTOMRIGHT", -cDW, 0)

      -- CHARACTERS column
      local raceAtlas = GI.RaceAtlas(ch.race, ch.sex)
      if raceAtlas then row.raceIcon:SetAtlas(raceAtlas) row.raceIcon:Show()
      else row.raceIcon:Hide() end
      row.raceBorder:SetVertexColor(r, g, b)

      local factionAtlas = GI.FactionAtlas(ch.faction)
      if factionAtlas then
        row.factionTex:SetAtlas(factionAtlas)
        row.factionTex:Show()
      else
        row.factionTex:Hide()
      end

      row.nameFS:ClearAllPoints()
      row.nameFS:SetPoint("LEFT",  row.factionTex, "RIGHT", 4, 0)
      row.nameFS:SetPoint("RIGHT", row, "RIGHT", -(cDW + cEW + cSW + cLUW + 4), 0)
      if ch.level and ch.level > 0 then
        row.lvlFS:SetText(ch.level)
      else
        row.lvlFS:SetText("")
      end

      local nameText = ch.name or "?"
      if ch.realm then nameText = nameText .. "-" .. ch.realm end
      row.nameFS:SetText(nameText)
      row.nameFS:SetTextColor(r, g, b)

      -- LASTUPDATE column
      row.lastUpdFS:ClearAllPoints()
      row.lastUpdFS:SetPoint("LEFT",  row, "RIGHT", -(cDW + cEW + cSW + cLUW) + LASTUPD_ZONE_PAD / 2, 0)
      row.lastUpdFS:SetPoint("RIGHT", row, "RIGHT", -(cDW + cEW + cSW + 4), 0)
      local activeSpecID = ch.specID
      local lastUpdate   = d.gear and activeSpecID
                           and d.gear[activeSpecID]
                           and d.gear[activeSpecID].lastUpdate
      row.lastUpdFS:SetText(FormatTimestamp(lastUpdate))

      -- RECOMMENDATIONS column
      -- (spec slot positions and visibility set below, after specs are collected)

      -- EXPORT and DELETE columns
      row.expBtn:ClearAllPoints()
      row.expBtn:SetPoint("CENTER", row, "RIGHT", -(cDW + cEW / 2), 0)

      row.delBtn:ClearAllPoints()
      row.delBtn:SetPoint("CENTER", row, "RIGHT", -(cDW / 2), 0)

      -- Spec slots
      local specs = GI.SpecList(d)

      local n = math.min(#specs, MAX_SPECS_IN_ROW)

      -- Position spec slots left-aligned within RECOMMENDATIONS column.
      -- Both frame and cb anchored directly to row (no sibling dependency).
      do
        local slotW   = SPEC_ICON_W + SPEC_ICON_CB_GAP + SPEC_CB_EFF  -- 31
        local colLeft = -(cDW + cEW + cSW) + SPEC_ZONE_PAD / 2
        for i = 1, MAX_SPECS_IN_ROW do
          local slot      = row.specSlots[i]
          local j         = math.max(1, n - i + 1)
          local frameLeft = colLeft + (j - 1) * (slotW + SPEC_SLOT_GAP)
          slot.frame:ClearAllPoints()
          slot.frame:SetPoint("LEFT", row, "RIGHT", frameLeft, 0)
          slot.cb:ClearAllPoints()
          slot.cb:SetPoint("LEFT", slot.frame, "RIGHT", SPEC_ICON_CB_GAP, 0)
        end
      end

      for i = 1, MAX_SPECS_IN_ROW do
        local slot = row.specSlots[i]
        local spec = specs[n - i + 1]
        if spec then
          slot.icon:SetTexture(spec.icon) slot.frame:Show()

          -- A character who has not chosen a specialization yet carries the
          -- initial one, which recommendations cannot work with. The checkbox is
          -- greyed out and shown clear until a real spec replaces it, at which
          -- point the new bucket's own default turns it back on.
          local real = GI.IsRealSpec(spec.specID)
          slot.cb:SetChecked(real and spec.bucket.incRecommend == true)
          slot.cb:SetEnabled(real)
          slot.cb:SetScript("OnClick", function(self)
            if row.charKey and GI.db and GI.db.characters[row.charKey] then
              local bucket = GI.db.characters[row.charKey].gear[spec.specID]
              if bucket then bucket.incRecommend = self:GetChecked() end
            end
          end)
          slot.cb:Show()
        else
          slot.frame:Hide() slot.cb:Hide()
        end
      end
    end)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(sf, sb, view)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(sf, sb)
  charPanel.scrollBox = sf

  charPanel:SetScript("OnShow", RefreshCharPanel)
  return charPanel
end

-- ─── Delete Picker ────────────────────────────────────────────────────────────

local picker  -- singleton frame, created on first use

local pickerCatch  -- transparent full-screen frame to catch outside clicks

local function ClosePicker()
  if picker then picker:Hide() end
  if pickerCatch then pickerCatch:Hide() end
end

local PICKER_BTN_SIZE = 32
local PICKER_BTN_GAP  = 6
local PICKER_PAD      = 16

local function GetOrCreatePicker()
  if picker then return picker end

  -- Full-screen transparent catch frame — behind picker, closes on any click outside
  pickerCatch = CreateFrame("Frame", nil, UIParent)
  pickerCatch:SetFrameStrata("FULLSCREEN_DIALOG")
  pickerCatch:SetFrameLevel(1)
  pickerCatch:SetAllPoints(UIParent)
  pickerCatch:EnableMouse(true)
  pickerCatch:Hide()
  pickerCatch:SetScript("OnMouseDown", ClosePicker)

  picker = CreateFrame("Frame", "GIDeletePicker", UIParent, "ButtonFrameTemplate")
  picker:SetFrameStrata("FULLSCREEN_DIALOG")
  picker:SetFrameLevel(2)
  picker:SetClampedToScreen(true)
  picker:Hide()

  ButtonFrameTemplate_HidePortrait(picker)
  picker.TitleContainer.TitleText:SetText(L["DELETE_PICKER_TITLE"])

  picker.CloseButton:Hide()
  if picker.Inset then picker.Inset:Hide() end

  -- Absorb background clicks so they don't fall through to pickerCatch
  picker:SetScript("OnMouseDown", function() end)

  picker:SetScript("OnHide", function()
    picker.charKey = nil
    pickerCatch:Hide()
  end)
  picker:SetScript("OnShow", function() pickerCatch:Show() end)

  -- ESC closes via UISpecialFrames
  tinsert(UISpecialFrames, "GIDeletePicker")

  -- Spec buttons (positioned in ShowDeletePicker)
  picker.specBtns = {}
  for i = 1, MAX_SPECS_IN_ROW do
    local btn = CreateFrame("Button", nil, picker)
    btn:SetSize(PICKER_BTN_SIZE, PICKER_BTN_SIZE)

    local iconFrame = GI.CreateCircleIcon(btn, 24, 26)
    iconFrame:SetPoint("CENTER", 0, 6)

    -- Glow under icon
    local glow = iconFrame:CreateTexture(nil, "BACKGROUND")
    glow:SetSize(38, 38)
    glow:SetPoint("CENTER")
    glow:SetAtlas("ChallengeMode-KeystoneSlotFrameGlow")
    glow:Hide()

    -- Overlay on top of border
    local apex = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    apex:SetSize(26, 26)
    apex:SetPoint("CENTER")
    apex:SetAtlas("talents-node-choiceflyout-circle-yellow")
    apex:Hide()

    btn:SetScript("OnEnter", function() glow:Show() apex:Show() end)
    btn:SetScript("OnLeave", function() glow:Hide() apex:Hide() end)

    btn.icon = iconFrame.icon
    picker.specBtns[i] = btn
  end

  -- "Everything" button — standard WoW button
  local allBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
  allBtn:SetText(L["DELETE_EVERYTHING"])
  allBtn:SetScript("OnClick", function()
    local ck         = picker.charKey
    local cName      = picker.coloredName
    local rMarkup    = picker.raceMarkup
    ClosePicker()
    if not ck then return end
    local popup = StaticPopup_Show("GEARINVENTORY_DELETE_CHAR", cName)
    if popup then popup.data = { charKey = ck, coloredName = cName, raceMarkup = rMarkup } end
  end)
  picker.allBtn = allBtn

  return picker
end

local function ShowDeletePicker(anchorBtn, charKey)
  if not GI.db or not GI.db.characters[charKey] then return end
  local entry = GI.db.characters[charKey]
  local ch    = entry.character or {}

  local specs = GI.SpecList(entry)

  local displayName = GI.DisplayName(ch)
  local r, g, b     = GI.ClassRGB(ch.class)
  local coloredName = GI.Colorize(displayName, r, g, b)
  local raceMarkup  = GI.RaceIconMarkup(ch.race, ch.sex)

  -- 0 or 1 spec — go straight to "Are you sure?" without the picker
  if #specs <= 1 then
    GI.ConfirmDeleteCharacter(charKey)
    return
  end

  -- 2+ specs — show picker
  local p = GetOrCreatePicker()
  p.charKey         = charKey
  p.coloredName     = coloredName
  p.raceMarkup      = raceMarkup

  local n = math.min(#specs, MAX_SPECS_IN_ROW)

  local EVERYTHING_W = 90
  local EVERYTHING_H = 22

  -- Lay out spec buttons in one row, centered
  local rowW    = n * PICKER_BTN_SIZE + (n - 1) * PICKER_BTN_GAP
  local pickerW = math.max(rowW + PICKER_PAD * 2, EVERYTHING_W + PICKER_PAD * 2, 160)
  local startX  = (pickerW - rowW) / 2
  local btnY    = -(28 + 10)  -- below ButtonFrameTemplate titlebar

  for i = 1, MAX_SPECS_IN_ROW do
    local btn  = p.specBtns[i]
    local spec = specs[i]
    btn:ClearAllPoints()
    if spec and i <= n then
      btn:SetPoint("TOPLEFT", p, "TOPLEFT",
        startX + (i - 1) * (PICKER_BTN_SIZE + PICKER_BTN_GAP), btnY)
      btn.icon:SetTexture(spec.icon)
      btn:SetScript("OnClick", function()
        local sk    = p.charKey
        local cName = p.coloredName
        ClosePicker()

        local ent = GI.db and GI.db.characters[sk]
        GI.ConfirmDeleteSpec(sk, spec, ent and ent.character or {}, cName)
      end)
      btn:Show()
    else
      btn:Hide()
    end
  end

  -- "Everything" button — below spec icons, centered
  p.allBtn:SetSize(EVERYTHING_W, EVERYTHING_H)
  p.allBtn:ClearAllPoints()
  p.allBtn:SetPoint("TOP", p, "TOPLEFT", pickerW / 2,
    btnY - PICKER_BTN_SIZE)
  p.allBtn:Show()

  local pickerH = 28 + 10 + PICKER_BTN_SIZE + EVERYTHING_H + PICKER_PAD
  p:SetSize(pickerW, pickerH)

  p:ClearAllPoints()
  p:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
  p:Show()
  p:Raise()
end

GI.ShowDeletePicker = ShowDeletePicker

-- ─── Delete Dialogs ───────────────────────────────────────────────────────────

StaticPopupDialogs["GEARINVENTORY_DELETE_SPEC"] = {
  text = L["DELETE_SPEC_CONFIRM"],
  button1 = YES,
  button2 = NO,
  OnAccept = function(self)
    local charKey  = self.data.charKey
    local specID   = self.data.specID
    local specName = self.data.specName
    local specIcon = self.data.specIcon
    GI.DeleteSpec(charKey, specID)

    -- If this is the current character's active spec — rescan immediately
    local myKey     = GI.PlayerKey()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local mySpecID  = specIndex and select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if charKey == myKey and specID == mySpecID then
      GI.ScanCurrentCharacter()
    end

    GI.RefreshCharacterList()
    if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
    local raceMarkup = GI.RaceIconMarkup(self.data.race, self.data.sex)
    local iconMarkup = specIcon and ("|T" .. specIcon .. ":14:14|t ") or ""
    GI.Print(string.format(L["SPEC_REMOVED"],
      iconMarkup .. (self.data.coloredSpec or ("|cFFFF4444" .. (specName or "?") .. "|r")),
      raceMarkup .. (self.data.coloredName or ("|cFFFF4444" .. charKey .. "|r"))))
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs["GEARINVENTORY_DELETE_CHAR"] = {
  text = L["DELETE_CONFIRM"],
  button1 = YES,
  button2 = NO,
  OnAccept = function(self)
    local charKey     = type(self.data) == "table" and self.data.charKey or self.data
    local coloredName = type(self.data) == "table" and self.data.coloredName
    local raceMarkup  = (type(self.data) == "table" and self.data.raceMarkup) or ""
    local myKey   = GI.PlayerKey()
    local isCurrentChar = (charKey == myKey)
    local wasSelected = GI.IsMainWindowSelection and GI.IsMainWindowSelection(charKey)
    GI.DeleteCharacter(charKey)
    GI.ClearMainWindowSelection(charKey)
    if isCurrentChar then
      GI.ScanCurrentCharacter()
    end
    -- If the deleted character was selected, switch view to the current player.
    if wasSelected and myKey and GI.ShowCharacterGear then
      if GI.db and GI.db.characters[myKey] then
        GI.ShowCharacterGear(myKey)
      end
    end
    GI.Print(string.format(L["CHAR_REMOVED"],
      raceMarkup .. (coloredName or ("|cFFFF4444" .. charKey .. "|r"))))
    GI.RefreshCharacterList()
    if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

-- ─── Public ───────────────────────────────────────────────────────────────────

GI.BuildCharPanel         = BuildCharPanel
GI.RefreshOptionsCharList = RefreshCharPanel
