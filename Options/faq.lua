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

local PAD        = 20  -- panel inset, left and right
local SCROLL_TOP = -56 -- below the title and its rule
local GAP_Q_A    = 4   -- question to its own answer
local GAP_BLOCK  = 18  -- answer to the next question

-- Height of the stacked entries, measured rather than assumed.
--
-- Only meaningful once the panel has been laid out: a wrapped FontString reports
-- no height before it knows its width, which is why this runs at OnShow and not
-- at build time. Width is not set here -- the view stretches the scroll target's
-- child to its own width, and this only has to say how tall it turns out.
local function LayoutContent()
  local box, content = faqPanel.scrollBox, faqPanel.content
  if box:GetWidth() <= 0 then return end

  local height = 0
  for i, block in ipairs(faqPanel.blocks) do
    height = height + block.q:GetStringHeight() + GAP_Q_A + block.a:GetStringHeight()
    if i < #faqPanel.blocks then
      height = height + GAP_BLOCK
    end
  end

  -- A zero-height scroll target leaves the scroll box with nothing to divide by.
  height = math.max(height, 1)
  if content:GetHeight() == height then return end

  content:SetHeight(height)
  box:FullUpdate(ScrollBoxConstants.UpdateImmediately)
end

local function BuildFAQPanel()
  faqPanel = CreateFrame("Frame")
  faqPanel.name = "F.A.Q. |A:quest-wrapper-turnin:14:14|a"

  local title = faqPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  title:SetText("F.A.Q.")

  local rule = faqPanel:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetColorTexture(0.3, 0.3, 0.4, 0.6)
  rule:SetPoint("TOPLEFT",  PAD, -44)
  rule:SetPoint("TOPRIGHT", -PAD, -44)

  -- Same scroll pair as the character lists, but a plain WowScrollBox: the
  -- entries are prose of differing heights, not rows of one shape, so there is
  -- no list view to drive. The box scrolls a single frame holding all of them.
  local box = CreateFrame("Frame", "GIFAQScrollBox", faqPanel, "WowScrollBox")
  box:SetPoint("TOPLEFT",     PAD,  SCROLL_TOP)
  box:SetPoint("BOTTOMRIGHT", -PAD, 5)

  -- Same offsets and scale as the Saved Characters list, so the two panels wear
  -- the same scrollbar in the same place.
  local bar = CreateFrame("EventFrame", "GIFAQScrollBar", faqPanel, "MinimalScrollBar")
  bar:SetPoint("TOPLEFT",    box, "TOPRIGHT",    7, -4)
  bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 7,  4)
  bar:SetScale(0.70)

  -- Parented to the box before the view is installed, and flagged scrollable:
  -- that flag is what makes the view adopt it as the frame it scrolls. The view
  -- also places and stretches it, so it needs no anchors of its own.
  local content = CreateFrame("Frame", nil, box)
  content.scrollable = true

  faqPanel.scrollBox = box
  faqPanel.content   = content
  faqPanel.blocks    = {}

  -- Each block is anchored under the one before it. Anchoring rather than
  -- measuring is deliberate: GetStringHeight is meaningless until the panel has
  -- been laid out, and a chain resolves itself whenever that happens.
  local anchor, anchorPoint, gap = content, "TOPLEFT", 0

  for _, entry in ipairs(FAQ_ENTRIES) do
    local q = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    q:SetPoint("TOPLEFT",  anchor, anchorPoint, 0, gap)
    q:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    q:SetJustifyH("LEFT")
    q:SetText(L[entry.q])

    local a = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    a:SetPoint("TOPLEFT",  q, "BOTTOMLEFT", 0, -GAP_Q_A)
    a:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    a:SetJustifyH("LEFT")
    a:SetText(L[entry.a])

    faqPanel.blocks[#faqPanel.blocks + 1] = { q = q, a = a }
    anchor, anchorPoint, gap = a, "BOTTOMLEFT", -GAP_BLOCK
  end

  local view = CreateScrollBoxLinearView()
  view:SetPanExtent(40)
  ScrollUtil.InitScrollBoxWithScrollBar(box, bar, view)
  ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)

  -- The settings frame sizes its panels when it shows them, so the measurement
  -- waits for that; the resize hook covers the window being resized after.
  --
  -- Hooked, not set: OnSizeChanged belongs to ScrollBoxBaseTemplate, and taking
  -- it over stops the box noticing its own size.
  faqPanel:SetScript("OnShow", LayoutContent)
  box:HookScript("OnSizeChanged", LayoutContent)

  return faqPanel
end

-- ─── Public ───────────────────────────────────────────────────────────────────

GI.BuildFAQPanel = BuildFAQPanel
