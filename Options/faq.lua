-- GearInventory/Options/faq.lua
-- "F.A.Q." subcategory panel for the Settings UI.

local addonName, GI = ...
local L = GI.L

local faqPanel

-- Question and answer locale keys, in display order. Adding an entry is one row
-- here plus the two strings in Locales/enUS.lua.
local FAQ_ENTRIES = {
  { q = "FAQ_Q_SPEC_LEVEL", a = "FAQ_A_SPEC_LEVEL" },
}

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

  -- Each block is anchored under the one before it. Anchoring rather than
  -- measuring is deliberate: GetStringHeight is meaningless until the panel has
  -- been laid out, and a chain resolves itself whenever that happens.
  local anchor, anchorPoint, gap = rule, "BOTTOMLEFT", -16

  for _, entry in ipairs(FAQ_ENTRIES) do
    local q = faqPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    q:SetPoint("TOPLEFT",  anchor, anchorPoint, 0, gap)
    q:SetPoint("TOPRIGHT", faqPanel, "TOPRIGHT", -20, 0)
    q:SetJustifyH("LEFT")
    q:SetText(L[entry.q])

    local a = faqPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    a:SetPoint("TOPLEFT",  q, "BOTTOMLEFT", 0, -4)
    a:SetPoint("TOPRIGHT", faqPanel, "TOPRIGHT", -20, 0)
    a:SetJustifyH("LEFT")
    a:SetText(L[entry.a])

    anchor, anchorPoint, gap = a, "BOTTOMLEFT", -18
  end

  return faqPanel
end

-- ─── Public ───────────────────────────────────────────────────────────────────

GI.BuildFAQPanel = BuildFAQPanel
