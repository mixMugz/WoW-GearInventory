-- GearInventory/Addons/Minimap.lua
-- Minimap button with two setup paths:
--   A) LibDBIcon-1.0 (bundled by SexyMap) — fully managed: positioning, styling,
--      saved angle, show/hide state all handled by the library.
--   B) Manual fallback — draggable button created directly on Minimap frame,
--      angle persisted in GearInventoryDB.config.minimapButton.angle.
--
-- Depends on: GI.dbicon (Addons/Libs.lua), GI.brokerObj (Addons/Broker.lua, may be nil),
--             GI.BuildCharacterTooltip (GearInventory.lua), GI.ToggleMainWindow (Addons/UI.lua)

local addonName, GI = ...
local L = GI.L

local ICON = GI.TEX.MINIMAP

-- Minimap shape → per-quadrant flag: true = circular arc, false = straight edge.
-- Quadrant order: [1]=right-bottom, [2]=left-bottom, [3]=right-top, [4]=left-top
-- Exact table from Wowhead Looter (WoW 12.0.1), verified working.
local MINIMAP_SHAPES = {
  ["ROUND"]                 = { true,  true,  true,  true  },
  ["SQUARE"]                = { false, false, false, false },
  ["CORNER-TOPLEFT"]        = { false, false, false, true  },
  ["CORNER-TOPRIGHT"]       = { false, false, true,  false },
  ["CORNER-BOTTOMLEFT"]     = { false, true,  false, false },
  ["CORNER-BOTTOMRIGHT"]    = { true,  false, false, false },
  ["SIDE-LEFT"]             = { false, true,  false, true  },
  ["SIDE-RIGHT"]            = { true,  false, true,  false },
  ["SIDE-TOP"]              = { false, false, true,  true  },
  ["SIDE-BOTTOM"]           = { true,  true,  false, false },
  ["TRICORNER-TOPLEFT"]     = { false, true,  true,  true  },
  ["TRICORNER-TOPRIGHT"]    = { true,  false, true,  true  },
  ["TRICORNER-BOTTOMLEFT"]  = { true,  true,  false, true  },
  ["TRICORNER-BOTTOMRIGHT"] = { true,  true,  true,  false },
}

-- ─── Custom Tooltip ───────────────────────────────────────────────────────────

local mmTip  -- lazy-created on first hover
local mmTipRows = {}

local function ShowMMTooltip(anchor)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  GameTooltip:ClearLines()
  GameTooltip:AddDoubleLine("|cFF00C9FFGear|r|cFFFFFFFFInventory|r", "|cFF555555v" .. GI.VERSION .. "|r")
  local vFS = _G["GameTooltipTextRight1"]
  if vFS then
    local font, _, flags = vFS:GetFont()
    vFS:SetFont(font, 9, flags)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L["TIP_CLICK"],       L["ACT_TOGGLE_WINDOW"], 1, 1, 1, 1, 0.82, 0)
  GameTooltip:AddDoubleLine(L["TIP_RIGHT_CLICK"], L["ACT_OPEN_SETTINGS"], 1, 1, 1, 1, 0.82, 0)
  GameTooltip:Show()
end

local function HideMMTooltip()
  GameTooltip:Hide()
end

-- ─── Path A: LibDBIcon ────────────────────────────────────────────────────────
-- LibDBIcon-1.0 may be bundled by SexyMap, HandyNotes, or other addons.
-- When present it handles button placement, shape masking, and hide/show state.

local function SetupLibDBIcon()
  -- brokerObj is set by Broker.lua; if LDB is absent there is no object to register
  if not GI.brokerObj then return false end

  GI.db.config.minimapButton = GI.db.config.minimapButton or { hide = false }

  GI.dbicon:Register("GearInventory", GI.brokerObj, GI.db.config.minimapButton)

  if GI.db.config.minimapButton.hide then
    GI.dbicon:Hide("GearInventory")
  end

  GI.minimapIconID = "GearInventory"

  -- Replace LibDBIcon tooltip with simplified version (no character list)
  local mmBtn = GI.dbicon:GetMinimapButton("GearInventory")
  if mmBtn then
    if mmBtn.icon then
      mmBtn.icon:SetTexture(GI.TEX.MINIMAP)
      mmBtn.icon:SetSize(20, 20)
    end
    mmBtn:SetScript("OnEnter", function(self) ShowMMTooltip(self) end)
    mmBtn:SetScript("OnLeave", function() HideMMTooltip() end)
  end

  return true
end

-- ─── Path B: Manual Fallback ──────────────────────────────────────────────────

local function SetupManual()
  GI.db.config.minimapButton = GI.db.config.minimapButton or { hide = false, angle = 220 }

  local btn = CreateFrame("Button", "GearInventoryMinimapButton", Minimap)
  btn:SetSize(31, 31)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetHighlightTexture(GI.TEX.MM_HIGHLIGHT)

  -- Dark background circle
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(25, 25)
  bg:SetTexture(GI.TEX.MM_BG)
  bg:SetPoint("TOPLEFT", 2, -4)

  -- Gear icon
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(22, 22)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.25, 0.75, 0.25, 0.75)
  icon:SetPoint("TOPLEFT", 6, -6)

  -- Shape-aware positioning around the minimap ring
  local function UpdatePos()
    local rad   = math.rad(GI.db.config.minimapButton.angle or 220)
    local x, y  = math.cos(rad), math.sin(rad)
    local q     = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quad  = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES["ROUND"]
    local w     = (Minimap:GetWidth()  / 2) + 5
    local h     = (Minimap:GetHeight() / 2) + 5
    if quad[q] then
      x, y = x * w, y * h
    else
      local dw = math.sqrt(2) * w - 10
      local dh = math.sqrt(2) * h - 10
      x = math.max(-w, math.min(x * dw, w))
      y = math.max(-h, math.min(y * dh, h))
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end

  UpdatePos()

  -- Reposition when minimap zoom changes (affects GetWidth/GetHeight)
  local zoomFrame = CreateFrame("Frame")
  zoomFrame:RegisterEvent("MINIMAP_UPDATE_ZOOM")
  zoomFrame:SetScript("OnEvent", function() UpdatePos() end)

  -- Drag to reposition
  btn:RegisterForDrag("LeftButton")

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local s      = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      GI.db.config.minimapButton.angle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
      UpdatePos()
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
      GI.ToggleMainWindow()
    elseif button == "RightButton" then
      GI.OpenOptions()
    end
  end)

  btn:SetScript("OnEnter", function(self) ShowMMTooltip(self) end)
  btn:SetScript("OnLeave", function() HideMMTooltip() end)

  if GI.db.config.minimapButton.hide then btn:Hide() end

  GI.minimapButton = btn
end

-- ─── Public: Toggle Minimap Button ───────────────────────────────────────────
-- Called via /gi minimap (slash handler in GearInventory.lua).

function GI.ToggleMinimapButton()
  if not GI.db or not GI.db.config or not GI.db.config.minimapButton then return end

  local nowHidden = not GI.db.config.minimapButton.hide
  GI.db.config.minimapButton.hide = nowHidden

  if GI.minimapIconID and GI.dbicon then
    if nowHidden then GI.dbicon:Hide(GI.minimapIconID)
    else              GI.dbicon:Show(GI.minimapIconID) end
  elseif GI.minimapButton then
    if nowHidden then GI.minimapButton:Hide()
    else              GI.minimapButton:Show() end
  end

  print("|cFF00C9FFGear|r|cFFFFFFFFInventory|r: "
    .. L["MINIMAP_BUTTON"] .. " "
    .. (nowHidden and L["MINIMAP_HIDDEN"] or L["MINIMAP_SHOWN"])
    .. "  |cFFAAAAAA(/gi minimap)|r")
end

-- ─── Initialization ───────────────────────────────────────────────────────────
-- PLAYER_LOGIN fires after ADDON_LOADED, so GI.db is guaranteed to be set.
-- Broker.lua's brokerObj (if created) is also set by file-load time.

local minimapFrame = CreateFrame("Frame")
minimapFrame:RegisterEvent("PLAYER_LOGIN")
minimapFrame:SetScript("OnEvent", function(self)
  if GI.dbicon then
    SetupLibDBIcon()
  else
    SetupManual()
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
