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

-- ─── Main Panel ─────────────────────────────────────────────────────────────

local panel -- created once, reused on every open

local function BuildPanel()
  panel = CreateFrame("Frame")
  panel.name = L["OPT_PANEL_NAME"]

  -- Title
  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("|cFF00C9FFGear|r|cFFFFFFFFInventory|r  "
    .. "|cFF555555v" .. GI.VERSION .. "|r")

  -- ── General ──────────────────────────────────────────────────────────────────
  MakeRule(panel, -52)
  MakeLabel(panel, L["OPT_GENERAL"], 20, -60)

  -- Auto-select current character
  local cbAutoSelect = MakeCheckbox(panel, L["OPT_AUTO_SELECT"], 24, -82)
  cbAutoSelect:SetChecked(GI.Config.Get("autoSelect") ~= false)
  cbAutoSelect:SetScript("OnClick", function(self)
    GI.Config.Set("autoSelect", self:GetChecked())
  end)
  panel.cbAutoSelect = cbAutoSelect

  -- ── Sort Order ────────────────────────────────────────────────────────────────
  MakeRule(panel, -120)
  MakeLabel(panel, L["OPT_SORT_BY"], 20, -128)

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
    -- Refresh the character list immediately if the window is open
    if GI.mainWindow and GI.mainWindow:IsShown() then
      GI.RefreshCharacterList()
    end
  end

  for i, opt in ipairs(sortOptions) do
    local rb = MakeRadio(panel, opt.label, 24 + (i - 1) * 140, -150)
    rb.sortKey = opt.key
    rb:SetScript("OnClick", OnRadioClick)
    radioButtons[i] = rb
  end
  panel.radioButtons  = radioButtons
  panel.sortOptions   = sortOptions

  -- ── Minimap ───────────────────────────────────────────────────────────────────
  MakeRule(panel, -186)
  MakeLabel(panel, L["OPT_MINIMAP"], 20, -194)

  local cbMinimap = MakeCheckbox(panel, L["OPT_SHOW_MINIMAP"], 24, -216)
  cbMinimap:SetScript("OnClick", function(self)
    -- Sync the checkbox state back to GI.db before toggling
    local wantHidden = not self:GetChecked()
    if GI.db and GI.db.minimapButton then
      -- Only call toggle if state actually changed
      if GI.db.minimapButton.hide ~= wantHidden then
        GI.ToggleMinimapButton()
      end
    end
  end)
  panel.cbMinimap = cbMinimap

  return panel
end

-- Forward declaration: defined after BuildCharPanel, called from SyncPanel.
local RefreshCharPanel

-- ─── Sync Panel State ─────────────────────────────────────────────────────────
-- Called each time the panel is shown to reflect the current saved values.

local function SyncPanel()
  if not panel then return end

  panel.cbAutoSelect:SetChecked(GI.Config.Get("autoSelect") ~= false)

  local currentSort = GI.Config.Get("sortOrder") or "ilvl"
  for _, rb in ipairs(panel.radioButtons) do
    rb:SetChecked(rb.sortKey == currentSort)
  end

  local minimapHidden = GI.db and GI.db.minimapButton and GI.db.minimapButton.hide
  panel.cbMinimap:SetChecked(not minimapHidden)

  -- Заодно обновляем список персонажей в подкатегории: Settings может вызвать
  -- Show() на charPanel при регистрации (до реальных данных), поэтому
  -- дополнительно обновляем при каждом открытии основной вкладки.
  RefreshCharPanel()
end

-- ─── Characters Subcategory Panel ───────────────────────────────────────────

local charPanel     -- the subcategory frame
local charRows      = {}
local CHAR_ROW_H    = 24

local function GetOrCreateCharRow(parent, idx)
  if charRows[idx] then return charRows[idx] end

  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(CHAR_ROW_H)
  row:SetPoint("TOPLEFT", 0, -(idx - 1) * CHAR_ROW_H)
  row:SetPoint("TOPRIGHT", 0, -(idx - 1) * CHAR_ROW_H)

  local nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  nameFS:SetPoint("LEFT", 4, 0)
  nameFS:SetPoint("RIGHT", -28, 0)
  nameFS:SetJustifyH("LEFT")
  row.nameFS = nameFS

  local delBtn = CreateFrame("Button", nil, row)
  delBtn:SetSize(16, 16)
  delBtn:SetPoint("RIGHT", -4, 0)
  delBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  delBtn:SetHighlightTexture("Interface\\Buttons\\UI-StopButton")
  delBtn:GetHighlightTexture():SetVertexColor(1, 0.2, 0.2)
  delBtn:SetScript("OnClick", function()
    if row.charKey then
      GI.ConfirmDeleteCharacter(row.charKey)
    end
  end)
  row.delBtn = delBtn

  charRows[idx] = row
  return row
end

RefreshCharPanel = function()
  if not charPanel or not GI.db then return end

  local container = charPanel.charContainer
  local playerRealm = GetRealmName and GetRealmName() or ""
  local sorted = {}
  for key, data in pairs(GI.db.characters) do
    table.insert(sorted, { key = key, data = data })
  end
  table.sort(sorted, function(a, b)
    return (a.data.name or "") < (b.data.name or "")
  end)

  for _, row in ipairs(charRows) do row:Hide() end

  for i, entry in ipairs(sorted) do
    local row = GetOrCreateCharRow(container, i)
    local d = entry.data
    row.charKey = entry.key

    local r, g, b = GI.ClassRGB(d.class)
    local displayName = d.name or "?"
    if d.realm and d.realm ~= playerRealm then
      displayName = displayName .. "-" .. d.realm
    end
    row.nameFS:SetText(displayName)
    row.nameFS:SetTextColor(r, g, b)
    row:Show()
  end

  container:SetHeight(math.max(#sorted * CHAR_ROW_H, 1))
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

  local container = CreateFrame("Frame", nil, charPanel)
  container:SetPoint("TOPLEFT", 24, -74)
  container:SetPoint("TOPRIGHT", -24, -74)
  container:SetHeight(1)
  charPanel.charContainer = container

  charPanel:SetScript("OnShow", RefreshCharPanel)

  return charPanel
end

-- ─── Public: Refresh character list in Options ──────────────────────────────

GI.RefreshOptionsCharList = RefreshCharPanel

-- ─── Registration ─────────────────────────────────────────────────────────────
-- Settings API (Dragonflight+, required — legacy InterfaceOptions was removed).
-- Register on ADDON_LOADED so GI.db exists when the panel is first synced.

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("ADDON_LOADED")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function(self, event, arg1)

  if event == "PLAYER_LOGIN" then
    -- Populate the char list once the player is in the world and GI.db is
    -- fully ready (saved characters exist, realm name resolves correctly).
    RefreshCharPanel()
    self:UnregisterEvent("PLAYER_LOGIN")
    return
  end

  -- ADDON_LOADED
  if arg1 ~= addonName then return end

  BuildPanel()
  BuildCharPanel()

  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  GI.optionsCategory = category
  panel:SetScript("OnShow", SyncPanel)

  local subCategory = Settings.RegisterCanvasLayoutSubcategory(
      category, charPanel, charPanel.name)

  self:UnregisterEvent("ADDON_LOADED")
end)

-- ─── Public: Open Options Panel ───────────────────────────────────────────────
-- Called by /gi options  (slash handler in GearInventory.lua).

function GI.OpenOptions()
  if GI.optionsCategory then
    Settings.OpenToCategory(GI.optionsCategory:GetID())
  end
end
