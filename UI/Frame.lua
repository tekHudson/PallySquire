--[[ PallySquire — main container frame + minimap button + UI orchestration.

Pure Lua (no XML). The container holds the stacked class buttons created in
UI/Buttons.lua. Dragging (when unlocked) moves it; right-click opens the
assignment config.
]]

local ADDON, ns = ...
local PS = ns.PS

ns.HEADER_H = 20   -- title/drag strip height; UI/Buttons offsets the stack below it

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

	-- Drag handle: a strip across the top that the cast buttons don't cover.
	local header = CreateFrame("Frame", "PallySquireHeader", f)
	header:SetPoint("TOPLEFT", 3, -3)
	header:SetPoint("TOPRIGHT", -3, -3)
	header:SetHeight(ns.HEADER_H)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")

	-- centered title (doubles as the drag label)
	local htitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	htitle:SetPoint("CENTER")
	htitle:SetText("PallySquire")

	-- gear button (top-left) opens options
	local gear = CreateFrame("Button", nil, header)
	gear:SetSize(16, 16)
	gear:SetPoint("LEFT", 1, 0)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	local gh = gear:CreateTexture(nil, "HIGHLIGHT")
	gh:SetAllPoints()
	gh:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
	gh:SetBlendMode("ADD")
	gear:SetScript("OnClick", function() PS:OpenOptions() end)
	gear:SetScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.L["Options"])
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- assignments button (top-right) opens the Assignments window
	local assign = CreateFrame("Button", nil, header)
	assign:SetSize(16, 16)
	assign:SetPoint("RIGHT", -1, 0)
	assign:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	local ah = assign:CreateTexture(nil, "HIGHLIGHT")
	ah:SetAllPoints()
	ah:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
	ah:SetBlendMode("ADD")
	assign:SetScript("OnClick", function() PS:ToggleConfig() end)
	assign:SetScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.L["Assignments"])
		GameTooltip:Show()
	end)
	assign:SetScript("OnLeave", function() GameTooltip:Hide() end)

	header:SetScript("OnDragStart", function()
		if not PS.opt.locked then f:StartMoving() end
	end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint()
		PS.opt.pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	header:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then PS:ToggleConfig() end
	end)
	header:SetScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("PallySquire")
		GameTooltip:AddLine(ns.L["DRAG_TOOLTIP"], 1, 1, 1)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.header = header

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
	icon:SetTexture("Interface\\AddOns\\PallySquire\\Icons\\Icon")
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
