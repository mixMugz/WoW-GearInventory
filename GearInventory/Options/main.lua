-- GearInventory/Options/main.lua
-- About panel (top-level settings category) + category registration.
-- Loaded last among Options files so all subcategory panels are already built.
--
-- Depends on: GI.BuildFAQPanel  (Options/faq.lua),
--             GI.BuildCharPanel (Options/characters.lua)
--
-- There is no general-settings panel: every option lives in the main window's
-- title bar settings dropdown (Addons/ui.lua).

local addonName, GI = ...
local L = GI.L

-- ─── About Panel ─────────────────────────────────────────────────────────────

local function BuildPanel()
  local panel = CreateFrame("Frame")
  panel.name = "|T" .. GI.TEX.ICON .. ":18:18|t GearInventory"

  local titleFS = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  titleFS:SetPoint("TOPLEFT", 20, -20)
  titleFS:SetText(GI.NAME_MARKUP)

  local logo = panel:CreateTexture(nil, "ARTWORK")
  logo:SetPoint("TOPLEFT", 20, -52)
  logo:SetSize(128, 128)
  logo:SetTexture(GI.TEX.LOGO)

  local infoFS = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  infoFS:SetPoint("TOPLEFT", 20, -52 - 128 - 16)
  infoFS:SetJustifyH("LEFT")
  panel.infoFS = infoFS

  return panel
end

local function SyncPanel(panel)
  if not (panel and panel.infoFS) then return end
  local dbVer = (GI.db and GI.db.config and GI.db.config.dbVersion) or "?"
  panel.infoFS:SetText(
    "|cFFFFD100" .. L["OPT_VERSION"] .. ":|r |cFFFFFFFF" .. GI.VERSION:gsub("(#%S+)$", "|r|cFF888888%1|r") .. "|r\n"
    .. "|cFFFFD100" .. L["OPT_DB"]    .. ":|r |cFFFFFFFF" .. dbVer .. "|r\n"
    .. "\n"
    .. "|cFFFFD100" .. L["OPT_AUTHOR"] .. ":|r |cFF00FF00mixMugz|r |cFFAAAAAA(a.k.a.|r |cFFFF7C0AМуади-Ревущийфьорд|r|cFFAAAAAA)|r"
  )
  if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
end

-- ─── Registration ─────────────────────────────────────────────────────────────

local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("ADDON_LOADED")
regFrame:RegisterEvent("PLAYER_LOGIN")
regFrame:SetScript("OnEvent", function(self, event, arg1)

  if event == "PLAYER_LOGIN" then
    if GI.RefreshOptionsCharList then GI.RefreshOptionsCharList() end
    self:UnregisterEvent("PLAYER_LOGIN")
    return
  end

  -- ADDON_LOADED
  if arg1 ~= addonName then return end

  local panel     = BuildPanel()
  local charPanel = GI.BuildCharPanel()
  local faqPanel  = GI.BuildFAQPanel()

  panel:SetScript("OnShow", function() SyncPanel(panel) end)

  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  GI.optionsCategory = category

  -- Sidebar order follows registration order.
  Settings.RegisterCanvasLayoutSubcategory(category, faqPanel,   faqPanel.name)
  Settings.RegisterCanvasLayoutSubcategory(category, charPanel,  charPanel.name)

  SyncPanel(panel)

  self:UnregisterEvent("ADDON_LOADED")
end)

-- ─── Public: Open Options Panel ───────────────────────────────────────────────

function GI.OpenOptions()
  if GI.optionsCategory then
    Settings.OpenToCategory(GI.optionsCategory:GetID())
  end
end
