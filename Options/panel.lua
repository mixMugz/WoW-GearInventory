-- GearInventory/Options/Panel.lua
-- Registers a settings panel in WoW Interface > AddOns (Settings API, TWW+).
-- Panel is created lazily on first open; GI.OpenOptions() is the public entry point.
--
-- Depends on: GI.Config (Options/Config.lua), GI.ToggleMinimapButton (Addons/Minimap.lua),
--             GI.RefreshCharacterList (Addons/UI.lua)

local addonName, GI = ...
local L = GI.L

-- ─── Widget Helpers ───────────────────────────────────────────────────────────

-- Creates a section label (bold separator text).
local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

-- Creates a horizontal rule.
local function MakeRule(parent, y)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetColorTexture(0.3, 0.3, 0.4, 0.6)
  line:SetPoint("TOPLEFT",  20, y)
  line:SetPoint("TOPRIGHT", -20, y)
  return line
end

-- Creates a checkbox with a text label to the right.
-- Returns the CheckButton frame.
local function MakeCheckbox(parent, label, x, y)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", x, y)
  cb:SetSize(26, 26)

  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(label)
  cb.label = fs

  return cb
end

-- Creates a radio button (round) with a text label to the right.
-- Returns the CheckButton frame.
local function MakeRadio(parent, label, x, y)
  local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
  rb:SetPoint("TOPLEFT", x, y)

  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
  fs:SetText(label)
  rb.label = fs

  return rb
end

-- ─── Main Panel (About) ──────────────────────────────────────────────────────

local panel -- created once, reused on every open

local function BuildPanel()
  panel = CreateFrame("Frame")
  -- Icon in the sidebar entry via |T| markup; explicit px size slightly larger than line height
  panel.name = "|T" .. GI.TEX.ICON .. ":18:18|t GearInventory"

  -- Title in panel body
  local titleFS = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  titleFS:SetPoint("TOPLEFT", 20, -20)
  titleFS:SetText("|cFF00C9FFGear|r|cFFFFFFFFInventory|r")

  -- Logo — 512x512 native, displayed at half size
  local logo = panel:CreateTexture(nil, "ARTWORK")
  logo:SetPoint("TOPLEFT", 20, -52)
  logo:SetSize(128, 128)
  logo:SetTexture(GI.TEX.LOGO)

  -- Info block (text filled in SyncPanel so dbVersion is read from live db)
  local infoFS = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  infoFS:SetPoint("TOPLEFT", 20, -52 - 128 - 16)
  infoFS:SetJustifyH("LEFT")
  panel.infoFS = infoFS

  return panel
end

-- ─── General Options Subcategory ─────────────────────────────────────────────

local genPanel -- created once

local function BuildGenPanel()
  genPanel = CreateFrame("Frame")
  genPanel.name = L["OPT_GENERAL"]

  -- Title
  local title = genPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText(L["OPT_GENERAL"])

  -- ── Sort Order ────────────────────────────────────────────────────────────────
  MakeRule(genPanel, -52)
  MakeLabel(genPanel, L["OPT_SORT_BY"], 20, -60)

  local sortOptions = {
    { key = "ilvl",  label = L["OPT_SORT_ILVL"]  },
    { key = "name",  label = L["OPT_SORT_NAME"]  },
    { key = "class", label = L["OPT_SORT_CLASS"] },
  }
  local radioButtons = {}

  local function OnRadioClick(self)
    for _, rb in ipairs(radioButtons) do
      rb:SetChecked(rb == self)
    end
    GI.Config.Set("sortOrder", self.sortKey)
    if GI.mainWindow and GI.mainWindow:IsShown() then
      GI.RefreshCharacterList()
    end
  end

  for i, opt in ipairs(sortOptions) do
    local rb = MakeRadio(genPanel, opt.label, 24 + (i - 1) * 140, -120)
    rb.sortKey = opt.key
    rb:SetScript("OnClick", OnRadioClick)
    radioButtons[i] = rb
  end
  genPanel.radioButtons = radioButtons
  genPanel.sortOptions  = sortOptions

  -- ── Minimap ───────────────────────────────────────────────────────────────────
  MakeRule(genPanel, -156)
  MakeLabel(genPanel, L["OPT_MINIMAP"], 20, -164)

  local cbMinimap = MakeCheckbox(genPanel, L["OPT_SHOW_MINIMAP"], 24, -186)
  cbMinimap:SetScript("OnClick", function(self)
    local wantHidden = not self:GetChecked()
    if GI.db and GI.db.config and GI.db.config.minimapButton then
      if GI.db.config.minimapButton.hide ~= wantHidden then
        GI.ToggleMinimapButton()
      end
    end
  end)
  genPanel.cbMinimap = cbMinimap

  -- ── Items ─────────────────────────────────────────────────────────────────────
  MakeRule(genPanel, -220)
  MakeLabel(genPanel, L["OPT_ITEMS"], 20, -228)

  local cbColorUpgrade = MakeCheckbox(genPanel, L["OPT_COLOR_UPGRADE"], 24, -250)
  cbColorUpgrade:SetScript("OnClick", function(self)
    GI.Config.Set("colorUpgradeRank", self:GetChecked())
  end)
  genPanel.cbColorUpgrade = cbColorUpgrade

  local cbColorStars = MakeCheckbox(genPanel, L["OPT_COLOR_STARS"], 24, -276)
  cbColorStars:SetScript("OnClick", function(self)
    GI.Config.Set("colorUpgradeStars", self:GetChecked())
  end)
  genPanel.cbColorStars = cbColorStars

  return genPanel
end

-- ─── Sync General Panel State ─────────────────────────────────────────────────

local function SyncGenPanel()
  if not genPanel then return end

  local currentSort = GI.Config.Get("sortOrder") or "ilvl"
  for _, rb in ipairs(genPanel.radioButtons) do
    rb:SetChecked(rb.sortKey == currentSort)
  end

  local minimapHidden = GI.db and GI.db.config and GI.db.config.minimapButton and GI.db.config.minimapButton.hide
  genPanel.cbMinimap:SetChecked(not minimapHidden)

  genPanel.cbColorUpgrade:SetChecked(GI.Config.Get("colorUpgradeRank") ~= false)
  genPanel.cbColorStars:SetChecked(GI.Config.Get("colorUpgradeStars") ~= false)
end

-- ─── Sync About Panel State ───────────────────────────────────────────────────

local function SyncPanel()
  if panel and panel.infoFS then
    local dbVer = (GI.db and GI.db.config and GI.db.config.dbVersion) or "?"
    panel.infoFS:SetText(
      "|cFFFFD100" .. L["OPT_VERSION"] .. ":|r |cFFFFFFFF" .. GI.VERSION:gsub("(#%S+)$", "|r|cFF888888%1|r") .. "|r\n"
      .. "|cFFFFD100" .. L["OPT_DB"]    .. ":|r |cFFFFFFFF" .. dbVer .. "|r\n"
      .. "\n"
      .. "|cFFFFD100" .. L["OPT_AUTHOR"] .. ":|r |cFF00FF00mixMugz|r |cFFAAAAAA(a.k.a.|r |cFFFF7C0AМуади-Ревущийфьорд|r|cFFAAAAAA)|r"
    )
  end
  if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
end

-- Forward declaration: defined after BuildCharPanel, called from SyncPanel.
local RefreshCharPanel

-- ─── Characters Subcategory Panel ───────────────────────────────────────────

local charPanel
local CHAR_ROW_H       = 22
local MAX_SPECS_IN_ROW = 4

RefreshCharPanel = function()
  if not charPanel or not GI.db or not charPanel.scrollBox then return end

  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    return ((a.data.character and a.data.character.name) or "")
         < ((b.data.character and b.data.character.name) or "")
  end)

  local provider = CreateDataProvider()
  for i, entry in ipairs(sorted) do
    entry.idx = i
    provider:Insert(entry)
  end
  charPanel.scrollBox:SetDataProvider(provider)
end

local function BuildCharPanel()
  charPanel = CreateFrame("Frame")
  charPanel.name = L["OPT_CHARACTERS"]

  local title = charPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText(L["OPT_CHARACTERS"])

  local desc = charPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  desc:SetPoint("TOPLEFT", 20, -44)
  desc:SetText("|cFF888888" .. L["OPT_CHARS_DESC"] .. "|r")

  MakeRule(charPanel, -62)

  -- WowScrollBoxList + MinimalScrollBar (same as main window)
  local sf = CreateFrame("Frame", "GIOptionsCharScrollBox", charPanel, "WowScrollBoxList")
  sf:SetPoint("TOPLEFT",     20, -74)
  sf:SetPoint("BOTTOMRIGHT", -10, 5)

  local sb = CreateFrame("EventFrame", "GIOptionsCharScrollBar", charPanel, "MinimalScrollBar")
  sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    2, -4)
  sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2,  4)
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

        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(18, 18)
        delBtn:SetPoint("RIGHT", -4, 0)
        delBtn:SetNormalAtlas("XMarksTheSpot")
        delBtn:SetHighlightAtlas("XMarksTheSpot")
        delBtn:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
        delBtn:SetScript("OnClick", function()
          if row.charKey then GI.ConfirmDeleteCharacter(row.charKey) end
        end)
        row.delBtn = delBtn

        row.specSlots = {}
        local prevAnchor = delBtn
        for i = 1, MAX_SPECS_IN_ROW do
          local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
          cb:SetSize(20, 20)
          cb:SetPoint("RIGHT", prevAnchor, "LEFT", -8, 0)
          local specFrame = CreateFrame("Frame", nil, row)
          specFrame:SetSize(14, 14)
          specFrame:SetPoint("RIGHT", cb, "LEFT", -2, 0)

          local icon = specFrame:CreateTexture(nil, "ARTWORK")
          icon:SetAllPoints()
          icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
          local specMask = specFrame:CreateMaskTexture()
          specMask:SetAllPoints(icon)
          specMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
          icon:AddMaskTexture(specMask)

          local specBorder = specFrame:CreateTexture(nil, "OVERLAY")
          specBorder:SetSize(16, 16)
          specBorder:SetPoint("CENTER")
          specBorder:SetAtlas("talents-node-circle-gray")

          row.specSlots[i] = { icon = icon, frame = specFrame, cb = cb }
          prevAnchor = specFrame
        end

        local raceFrame = CreateFrame("Frame", nil, row)
        raceFrame:SetSize(14, 14)
        raceFrame:SetPoint("LEFT", 4, 0)
        local raceIcon = raceFrame:CreateTexture(nil, "ARTWORK")
        raceIcon:SetAllPoints()
        raceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local raceMask = raceFrame:CreateMaskTexture()
        raceMask:SetAllPoints(raceIcon)
        raceMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
          "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        raceIcon:AddMaskTexture(raceMask)
        local raceBorder = raceFrame:CreateTexture(nil, "OVERLAY")
        raceBorder:SetSize(16, 16)
        raceBorder:SetPoint("CENTER")
        raceBorder:SetAtlas("talents-node-circle-gray")
        row.raceIcon   = raceIcon
        row.raceBorder = raceBorder

        local factionTex = row:CreateTexture(nil, "ARTWORK")
        factionTex:SetSize(14, 14)
        factionTex:SetPoint("LEFT", raceFrame, "RIGHT", 4, 0)
        row.factionTex = factionTex

        local nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        nameFS:SetJustifyH("LEFT")
        row.nameFS = nameFS
      end

      -- ── Data population ───────────────────────────────────────────────────
      if not nodeArg then return end
      local entry = nodeArg.GetData and nodeArg:GetData() or nodeArg
      local d  = entry.data
      local ch = d.character or {}
      row.charKey = entry.key

      local idx = entry.idx or 1
      if idx % 2 == 0 then
        row.bg:SetColorTexture(1, 1, 1, 0.08)
      else
        row.bg:SetColorTexture(0, 0, 0, 0)
      end

      local r, g, b = GI.ClassRGB(ch.class)
      row.nameFS:SetText((ch.name or "?") .. "-" .. (ch.realm or "?"))
      row.nameFS:SetTextColor(r, g, b)

      local raceAtlas = GI.RaceAtlas(ch.raceFile, ch.sex)
      if raceAtlas then row.raceIcon:SetAtlas(raceAtlas) row.raceIcon:Show()
      else row.raceIcon:Hide() end
      row.raceBorder:SetVertexColor(r, g, b)

      if ch.faction then
        row.factionTex:SetAtlas(ch.faction == "Horde"
          and GI.ATLAS.FACTION_HORDE or GI.ATLAS.FACTION_ALLIANCE)
        row.factionTex:Show()
      else
        row.factionTex:Hide()
      end

      local specs = {}
      if d.gear then
        for specID, bucket in pairs(d.gear) do
          if specID ~= 0 then
            local _, _, _, sIcon = GetSpecializationInfoByID(specID)
            table.insert(specs, { specID = specID, bucket = bucket, icon = sIcon })
          end
        end
        table.sort(specs, function(a, b2) return a.specID < b2.specID end)
      end

      local n = math.min(#specs, MAX_SPECS_IN_ROW)
      for i = 1, MAX_SPECS_IN_ROW do
        local slot = row.specSlots[i]
        local spec = specs[n - i + 1]
        if spec then
          slot.icon:SetTexture(spec.icon) slot.frame:Show()
          slot.cb:SetChecked(spec.bucket.incRecommend == true)
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

      row.nameFS:ClearAllPoints()
      row.nameFS:SetPoint("LEFT", row.factionTex, "RIGHT", 4, 0)
      if n > 0 then
        row.nameFS:SetPoint("RIGHT", row.specSlots[n].frame, "LEFT", -8, 0)
      else
        row.nameFS:SetPoint("RIGHT", row.delBtn, "LEFT", -8, 0)
      end
    end)
  end)

  ScrollUtil.InitScrollBoxListWithScrollBar(sf, sb, view)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(sf, sb)
  charPanel.scrollBox = sf

  charPanel:SetScript("OnShow", RefreshCharPanel)
  return charPanel
end

-- ─── FAQ Panel ────────────────────────────────────────────────────────────────

local faqPanel

local function BuildFAQPanel()
  faqPanel = CreateFrame("Frame")
  faqPanel.name = "F.A.Q. |A:quest-wrapper-turnin:14:14|a"

  local title = faqPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("F.A.Q.")

  MakeRule(faqPanel, -44)

  return faqPanel
end

-- ─── Public: Refresh character list in Options ──────────────────────────────

GI.RefreshOptionsCharList = RefreshCharPanel

-- ─── Registration ─────────────────────────────────────────────────────────────

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("ADDON_LOADED")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function(self, event, arg1)

  if event == "PLAYER_LOGIN" then
    RefreshCharPanel()
    self:UnregisterEvent("PLAYER_LOGIN")
    return
  end

  -- ADDON_LOADED
  if arg1 ~= addonName then return end

  BuildPanel()
  BuildGenPanel()
  BuildCharPanel()
  BuildFAQPanel()

  -- Set OnShow BEFORE registering so it fires even during Settings' initial layout pass
  panel:SetScript("OnShow", SyncPanel)
  genPanel:SetScript("OnShow", SyncGenPanel)
  charPanel:SetScript("OnShow", RefreshCharPanel)

  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  GI.optionsCategory = category

  local genSubCategory = Settings.RegisterCanvasLayoutSubcategory(
      category, genPanel, genPanel.name)

  local charSubCategory = Settings.RegisterCanvasLayoutSubcategory(
      category, charPanel, charPanel.name)

  local faqSubCategory = Settings.RegisterCanvasLayoutSubcategory(
      category, faqPanel, faqPanel.name)

  -- Force sync after registration so first open shows correct values
  SyncPanel()
  SyncGenPanel()

  self:UnregisterEvent("ADDON_LOADED")
end)

-- ─── Public: Open Options Panel ───────────────────────────────────────────────

function GI.OpenOptions()
  if GI.optionsCategory then
    Settings.OpenToCategory(GI.optionsCategory:GetID())
  end
end
