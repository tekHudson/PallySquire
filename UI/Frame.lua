--[[ PallySquire — main container frame + minimap button + UI orchestration.

Pure Lua (no XML). The container holds the stacked class buttons created in
UI/Buttons.lua. Dragging (when unlocked) moves it; right-click opens the
assignment config.
]]

local ADDON, ns = ...
local PS = ns.PS

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function PS:CreateMainFrame()
	local f = CreateFrame("Frame", "PallySquireFrame", UIParent, "BackdropTemplate")
	f:SetSize(120, 60)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop(BACKDROP)
	f:SetBackdropColor(0, 0, 0, 0.6)
	f:SetScale(PS.opt.scale or 1.0)

	-- position
	if PS.opt.pos then
		local p = PS.opt.pos
		f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
	else
		f:SetPoint("CENTER")
	end

	f:SetScript("OnDragStart", function(self)
		if not PS.opt.locked then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		PS.opt.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then PS:ToggleConfig() end
	end)
	f:SetScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("PallySquire")
		GameTooltip:AddLine(ns.L["DRAG_TOOLTIP"], 1, 1, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	PS.frame = f
end

function PS:ToggleFrame()
	if PS.frame:IsShown() then PS.frame:Hide() else PS.frame:Show() end
end

function PS:ResetPosition()
	PS.opt.pos = nil
	PS.frame:ClearAllPoints()
	PS.frame:SetPoint("CENTER")
end

----------------------------------------------------------------------
-- Minimap button (tiny, native — replaces LibDBIcon)
----------------------------------------------------------------------
function PS:CreateMinimap()
	local b = CreateFrame("Button", "PallySquireMinimap", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture("Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
	icon:SetPoint("TOPLEFT", 7, -6)

	local function reposition()
		local angle = math.rad(PS.opt.minimap.angle or 200)
		b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
	end
	reposition()

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then PS:ToggleConfig() else PS:OpenOptions() end
	end)
	b:RegisterForDrag("LeftButton")
	b:SetMovable(true)
	b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		PS.opt.minimap.angle = math.deg(math.atan2(py - my, px - mx))
		reposition()
	end) end)
	b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("PallySquire")
		GameTooltip:AddLine("Left-click: options", 1, 1, 1)
		GameTooltip:AddLine("Right-click: assignments", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	b:SetShown(not PS.opt.minimap.hide)
	PS.minimap = b
end

----------------------------------------------------------------------
-- Orchestration
----------------------------------------------------------------------
function PS:InitUI()
	PS:CreateMainFrame()
	PS:CreateButtons()
	PS:CreateMinimap()
	PS:CreateConfig()
	PS:CreateOptions()
	PS:UpdateLayout()

	-- Apply dirty aura flag on a light cadence so UNIT_AURA spam is cheap.
	C_Timer.NewTicker(0.2, function()
		if PS.auraDirty then
			PS.auraDirty = false
			PS:ScanAllClasses()
			PS:UpdateVisuals()
		end
	end)
end
