-- GearInventory/Options/faq.lua
-- "F.A.Q." subcategory panel for the Settings UI.

local addonName, GI = ...

local faqPanel

local function BuildFAQPanel()
  faqPanel = CreateFrame("Frame")
  faqPanel.name = "F.A.Q. |A:quest-wrapper-turnin:14:14|a"

  local title = faqPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -20)
  title:SetText("F.A.Q.")

  local rule = faqPanel:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetColorTexture(0.3, 0.3, 0.4, 0.6)
  rule:SetPoint("TOPLEFT",  20, -44)
  rule:SetPoint("TOPRIGHT", -20, -44)

  return faqPanel
end

-- ─── Public ───────────────────────────────────────────────────────────────────

GI.BuildFAQPanel = BuildFAQPanel
