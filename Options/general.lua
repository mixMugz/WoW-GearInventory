-- GearInventory/Options/general.lua
-- General Options subcategory panel.
-- Provides: GI.BuildGenPanel(), GI.SyncGenPanel()

local addonName, GI = ...
local L = GI.L

-- ─── Widget Helpers ───────────────────────────────────────────────────────────

local function MakeLabel(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
  return fs
end

local function MakeRule(parent, y)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetColorTexture(0.3, 0.3, 0.4, 0.6)
  line:SetPoint("TOPLEFT",  20, y)
  line:SetPoint("TOPRIGHT", -20, y)
  return line
end

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


-- ─── General Options Subcategory ─────────────────────────────────────────────

local genPanel

function GI.BuildGenPanel()
  genPanel = CreateFrame("Frame")
  genPanel.name = L["OPT_GENERAL"]

  local title = genPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText(L["OPT_GENERAL"])

  -- ── Sort Order ────────────────────────────────────────────────────────────
  MakeRule(genPanel, -44)
  MakeLabel(genPanel, L["OPT_SORT_BY"], 20, -52)

  local sortOptions = {
    { key = "ilvl",        label = L["OPT_SORT_ILVL"]         },
    { key = "name",        label = L["OPT_SORT_NAME"]         },
    { key = "class",       label = L["OPT_SORT_CLASS"]        },
    { key = "level",       label = L["OPT_SORT_LEVEL"]        },
    { key = "lastUpdated", label = L["OPT_SORT_LAST_UPDATED"] },
  }
  local secondaryOptions = {
    { key = "none",        label = L["OPT_SORT_NONE"]         },
    { key = "ilvl",        label = L["OPT_SORT_ILVL"]         },
    { key = "name",        label = L["OPT_SORT_NAME"]         },
    { key = "class",       label = L["OPT_SORT_CLASS"]        },
    { key = "level",       label = L["OPT_SORT_LEVEL"]        },
    { key = "lastUpdated", label = L["OPT_SORT_LAST_UPDATED"] },
  }

  MakeLabel(genPanel, L["OPT_SORT_SECONDARY"], 214, -52)
  MakeLabel(genPanel, L["OPT_GROUP_BY"],        408, -52)

  local sortDropdown = CreateFrame("Frame", "GISortOrderDropdown", genPanel, "UIDropDownMenuTemplate")
  sortDropdown:SetPoint("TOPLEFT", 16, -68)
  UIDropDownMenu_SetWidth(sortDropdown, 150)

  local secondaryDropdown = CreateFrame("Frame", "GISecondarySortDropdown", genPanel, "UIDropDownMenuTemplate")
  secondaryDropdown:SetPoint("TOPLEFT", 210, -68)
  UIDropDownMenu_SetWidth(secondaryDropdown, 150)

  UIDropDownMenu_Initialize(sortDropdown, function()
    local current = GI.Config.Get("sortOrder") or "ilvl"
    for _, opt in ipairs(sortOptions) do
      local info = UIDropDownMenu_CreateInfo()
      info.text    = opt.label
      info.value   = opt.key
      info.checked = (current == opt.key)
      info.func    = function()
        GI.Config.Set("sortOrder", opt.key)
        UIDropDownMenu_SetText(sortDropdown, opt.label)
        if GI.Config.Get("secondarySort") == opt.key then
          GI.Config.Set("secondarySort", "none")
          UIDropDownMenu_SetText(secondaryDropdown, L["OPT_SORT_NONE"])
        end
        if GI.mainWindow and GI.mainWindow:IsShown() then
          GI.RefreshCharacterList()
        end
      end
      UIDropDownMenu_AddButton(info)
    end
  end)

  UIDropDownMenu_Initialize(secondaryDropdown, function()
    local primary   = GI.Config.Get("sortOrder") or "ilvl"
    local current   = GI.Config.Get("secondarySort") or "none"
    for _, opt in ipairs(secondaryOptions) do
      local info = UIDropDownMenu_CreateInfo()
      info.text     = opt.label
      info.value    = opt.key
      info.checked  = (current == opt.key)
      info.disabled = (opt.key ~= "none" and opt.key == primary)
      info.func     = function()
        GI.Config.Set("secondarySort", opt.key)
        UIDropDownMenu_SetText(secondaryDropdown, opt.label)
        if GI.mainWindow and GI.mainWindow:IsShown() then
          GI.RefreshCharacterList()
        end
      end
      UIDropDownMenu_AddButton(info)
    end
  end)

  genPanel.sortDropdown      = sortDropdown
  genPanel.secondaryDropdown = secondaryDropdown
  genPanel.sortOptions       = sortOptions
  genPanel.secondaryOptions  = secondaryOptions

  local groupByOptions = {
    { key = "none",    label = L["OPT_GROUP_NONE"]    },
    { key = "realm",   label = L["OPT_GROUP_REALM"]   },
    { key = "faction", label = L["OPT_GROUP_FACTION"] },
    { key = "armor",   label = L["OPT_GROUP_ARMOR"]   },
  }

  local groupByDropdown = CreateFrame("Frame", "GIGroupByDropdown", genPanel, "UIDropDownMenuTemplate")
  groupByDropdown:SetPoint("TOPLEFT", 404, -68)
  UIDropDownMenu_SetWidth(groupByDropdown, 150)
  UIDropDownMenu_Initialize(groupByDropdown, function()
    local current = GI.Config.Get("groupBy") or "none"
    for _, opt in ipairs(groupByOptions) do
      local info = UIDropDownMenu_CreateInfo()
      info.text    = opt.label
      info.value   = opt.key
      info.checked = (current == opt.key)
      info.func    = function()
        GI.Config.Set("groupBy", opt.key)
        UIDropDownMenu_SetText(groupByDropdown, opt.label)
        if GI.mainWindow and GI.mainWindow:IsShown() then
          GI.RefreshCharacterList()
        end
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  genPanel.groupByDropdown = groupByDropdown
  genPanel.groupByOptions  = groupByOptions

  -- ── Minimap ───────────────────────────────────────────────────────────────
  MakeRule(genPanel, -108)
  MakeLabel(genPanel, L["OPT_MINIMAP"], 20, -116)

  local cbMinimap = MakeCheckbox(genPanel, L["OPT_SHOW_MINIMAP"], 24, -138)
  cbMinimap:SetScript("OnClick", function(self)
    local wantHidden = not self:GetChecked()
    if GI.db and GI.db.config and GI.db.config.minimapButton then
      if GI.db.config.minimapButton.hide ~= wantHidden then
        GI.ToggleMinimapButton()
      end
    end
  end)
  genPanel.cbMinimap = cbMinimap

  -- ── Items ─────────────────────────────────────────────────────────────────
  MakeRule(genPanel, -172)
  MakeLabel(genPanel, L["OPT_ITEMS"], 20, -180)

  local cbColorUpgrade = MakeCheckbox(genPanel, L["OPT_COLOR_UPGRADE"], 24, -202)
  cbColorUpgrade:SetScript("OnClick", function(self)
    GI.Config.Set("colorUpgradeRank", self:GetChecked())
  end)
  genPanel.cbColorUpgrade = cbColorUpgrade

  local cbColorStars = MakeCheckbox(genPanel, L["OPT_COLOR_STARS"], 24, -228)
  cbColorStars:SetScript("OnClick", function(self)
    GI.Config.Set("colorUpgradeStars", self:GetChecked())
  end)
  genPanel.cbColorStars = cbColorStars

  return genPanel
end

-- ─── Sync General Panel ───────────────────────────────────────────────────────

function GI.SyncGenPanel()
  if not genPanel then return end

  local currentSort = GI.Config.Get("sortOrder") or "ilvl"
  for _, opt in ipairs(genPanel.sortOptions) do
    if opt.key == currentSort then
      UIDropDownMenu_SetText(genPanel.sortDropdown, opt.label)
      break
    end
  end

  local currentSecondary = GI.Config.Get("secondarySort") or "none"
  for _, opt in ipairs(genPanel.secondaryOptions) do
    if opt.key == currentSecondary then
      UIDropDownMenu_SetText(genPanel.secondaryDropdown, opt.label)
      break
    end
  end

  local currentGroup = GI.Config.Get("groupBy") or "none"
  for _, opt in ipairs(genPanel.groupByOptions) do
    if opt.key == currentGroup then
      UIDropDownMenu_SetText(genPanel.groupByDropdown, opt.label)
      break
    end
  end

  local minimapHidden = GI.db and GI.db.config and GI.db.config.minimapButton and GI.db.config.minimapButton.hide
  genPanel.cbMinimap:SetChecked(not minimapHidden)

  genPanel.cbColorUpgrade:SetChecked(GI.Config.Get("colorUpgradeRank") ~= false)
  genPanel.cbColorStars:SetChecked(GI.Config.Get("colorUpgradeStars") ~= false)
end
