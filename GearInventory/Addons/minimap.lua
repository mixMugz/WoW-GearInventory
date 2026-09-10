-- GearInventory/Addons/minimap.lua
-- Minimap button with two setup paths:
--   A) LibDBIcon-1.0 (bundled by SexyMap) — fully managed: positioning, styling,
--      saved angle, show/hide state all handled by the library.
--   B) Manual fallback — draggable button created directly on Minimap frame,
--      angle persisted in GearInventoryDB.config.minimapButton.minimapPos.
--
-- Both paths persist the angle under the same key, so installing or removing a
-- LibDBIcon host keeps the button where the user left it. The positioning math
-- below is LibDBIcon's, kept identical for the same reason.
--
-- Depends on: GI.dbicon (Addons/libs.lua), GI.brokerObj (Addons/broker.lua, may be nil),
--             GI.ToggleMainWindow (Addons/ui.lua)

local addonName, GI = ...
local L = GI.L

local ICON = GI.TEX.MINIMAP

-- Fallback for the manual path only; the real default lives in GI.DEFAULTS
-- and is written by GI.ApplyDefaults before either setup path runs.
local DEFAULT_ANGLE = GI.DEFAULTS.config.minimapButton.minimapPos

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

-- ─── Tooltip ──────────────────────────────────────────────────────────────────

local function ShowMMTooltip(anchor)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  GameTooltip:ClearLines()
  GI.BuildLauncherTooltip(GameTooltip)
  GameTooltip:Show()
end

local function HideMMTooltip()
  GameTooltip:Hide()
end

-- ─── SexyMap Interop ──────────────────────────────────────────────────────────
-- SexyMap claims drag ownership of every LibDBIcon button (its "Let SexyMap
-- handle button dragging" option): it replaces the library's OnDragStart and
-- stores the angle in SexyMap2DB. LibDBIcon's own minimapPos is therefore never
-- updated, and lib:Show() reapplies it -- snapping the button to the library
-- default of 225 degrees.
--
-- Reading the angle back keeps our copy authoritative, so a hide/show cycle
-- restores where the button actually sits, and the position survives SexyMap
-- being uninstalled. Both stores measure the same angle from the minimap centre.
--
-- Every step is guarded: should SexyMap change its layout this quietly does
-- nothing, leaving the previously stored angle in place.
local function SyncPosFromSexyMap()
  if type(SexyMap2DB) ~= "table" then return end

  local btn  = GI.dbicon and GI.dbicon:GetMinimapButton("GearInventory")
  local name = btn and btn:GetName()
  if not name then return end

  -- SexyMap keys profiles by "Name-Realm", or stores the string "global" there
  -- to redirect to the shared profile.
  local profile = SexyMap2DB[GI.PlayerKey() or ""]
  if type(profile) == "string" then profile = SexyMap2DB.global end
  if type(profile) ~= "table" or type(profile.buttons) ~= "table" then return end

  local saved = profile.buttons.dragPositions
  local pos   = type(saved) == "table" and saved[name] or nil
  if type(pos) == "number" then
    GI.db.config.minimapButton.minimapPos = pos % 360
  end
end

-- ─── Path A: LibDBIcon ────────────────────────────────────────────────────────
-- LibDBIcon-1.0 may be bundled by SexyMap, HandyNotes, or other addons.
-- When present it handles button placement, shape masking, and hide/show state.

local function SetupLibDBIcon()
  -- brokerObj is set by broker.lua; if LDB is absent there is no object to register
  if not GI.brokerObj then return false end

  GI.db.config.minimapButton = GI.db.config.minimapButton or { hide = false }

  GI.dbicon:Register("GearInventory", GI.brokerObj, GI.db.config.minimapButton)

  if GI.db.config.minimapButton.hide then
    GI.dbicon:Hide("GearInventory")
  end

  GI.minimapIconID = "GearInventory"

  SyncPosFromSexyMap()

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
  GI.db.config.minimapButton = GI.db.config.minimapButton
    or { hide = false, minimapPos = DEFAULT_ANGLE }

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
    local rad   = math.rad(GI.db.config.minimapButton.minimapPos or DEFAULT_ANGLE)
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
      GI.db.config.minimapButton.minimapPos = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
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
-- Called from the settings dropdown checkbox in Addons/ui.lua.

function GI.ToggleMinimapButton()
  if not GI.db or not GI.db.config or not GI.db.config.minimapButton then return end

  -- Before the branch, so the angle is captured whichever way the toggle goes:
  -- on hide it is banked for the next login, on show it feeds LibDBIcon.
  SyncPosFromSexyMap()

  local nowHidden = not GI.db.config.minimapButton.hide
  GI.db.config.minimapButton.hide = nowHidden

  if GI.minimapIconID and GI.dbicon then
    if nowHidden then GI.dbicon:Hide(GI.minimapIconID)
    else              GI.dbicon:Show(GI.minimapIconID) end
  elseif GI.minimapButton then
    if nowHidden then GI.minimapButton:Hide()
    else              GI.minimapButton:Show() end
  end

  GI.Print(L["MINIMAP_BUTTON"] .. " "
    .. (nowHidden and L["MINIMAP_HIDDEN"] or L["MINIMAP_SHOWN"]) .. ".")
end

-- ─── Initialization ───────────────────────────────────────────────────────────
-- PLAYER_LOGIN fires after ADDON_LOADED, so GI.db is guaranteed to be set.
-- broker.lua's brokerObj (if created) is also set by file-load time.

local minimapFrame = CreateFrame("Frame")
minimapFrame:RegisterEvent("PLAYER_LOGIN")
minimapFrame:SetScript("OnEvent", function(self)
  -- SetupLibDBIcon bails out when there is no broker object to register, so its
  -- return value decides whether the manual button is still needed.
  if not (GI.dbicon and SetupLibDBIcon()) then
    SetupManual()
  end
  self:UnregisterEvent("PLAYER_LOGIN")
end)
