--[[ PallySquire — options panel via the modern Settings API.

A canvas panel grouped into sections (Bar buttons / Display / Behavior), with
checkboxes, a scale slider and a layout cycler. No AceConfig/AceGUI; falls
back to the legacy InterfaceOptions API on older clients.
]]

local ADDON, ns = ...
local PS = ns.PS

local function makeCheck(parent, label, get, set, y)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 24, y)
	cb.Text:SetText(label)
	cb:SetChecked(get())
	cb:SetScript("OnClick", function(self) set(self:GetChecked()) end)
	return cb
end

function PS:CreateOptions()
	local panel = CreateFrame("Frame", "PallySquireOptionsPanel", UIParent)
	panel.name = "PallySquire"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("PallySquire")

	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("SoD paladin blessing manager. /ps config for assignments.")

	local y = -58

	local function header(text)
		local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		h:SetPoint("TOPLEFT", 16, y)
		h:SetText(text)
		h:SetTextColor(1, 0.82, 0)
		local line = panel:CreateTexture(nil, "ARTWORK")
		line:SetSize(340, 1)
		line:SetPoint("TOPLEFT", 16, y - 16)
		line:SetColorTexture(1, 0.82, 0, 0.35)
		y = y - 28
	end
	local function check(label, get, set)
		makeCheck(panel, label, get, set, y)
		y = y - 26
	end

	------------------------------------------------------------------
	header("Bar buttons")
	check("Show Auto Buff button", function() return PS.opt.showAuto end,
		function(v) PS.opt.showAuto = v; PS:UpdateLayout() end)
	check("Show Aura button", function() return PS.opt.showAura end,
		function(v) PS.opt.showAura = v; PS:UpdateLayout() end)
	check("Show Seal button", function() return PS.opt.showSeal end,
		function(v) PS.opt.showSeal = v; PS:UpdateLayout() end)
	check("Show player pop-out buttons", function() return PS.opt.showPlayerButtons end,
		function(v) PS.opt.showPlayerButtons = v; PS:UpdateLayout() end)
	y = y - 8

	------------------------------------------------------------------
	header("Display")
	check("Show remaining-time text", function() return PS.opt.buffDuration end,
		function(v) PS.opt.buffDuration = v; PS:UpdateVisuals() end)
	check("Hide tooltips", function() return PS.opt.hideTooltips end,
		function(v) PS.opt.hideTooltips = v end)

	-- Scale slider
	local slider = CreateFrame("Slider", "PallySquireScaleSlider", panel, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", 26, y - 18)
	slider:SetMinMaxValues(0.5, 2.0)
	slider:SetValueStep(0.05)
	slider:SetObeyStepOnDrag(true)
	slider:SetValue(PS.opt.scale or 1.0)
	_G[slider:GetName() .. "Low"]:SetText("0.5")
	_G[slider:GetName() .. "High"]:SetText("2.0")
	_G[slider:GetName() .. "Text"]:SetText("Frame scale")
	slider:SetScript("OnValueChanged", function(_, value)
		PS.opt.scale = value
		if PS.frame then PS.frame:SetScale(value) end
	end)
	y = y - 56

	-- Class layout cycle (Grid 3-wide / Vertical / Horizontal)
	local LMODES = { "grid", "vertical", "horizontal" }
	local LLABEL = { grid = "Grid (3 wide)", vertical = "Vertical", horizontal = "Horizontal" }
	local layoutBtn = CreateFrame("Button", "PallySquireLayoutBtn", panel, "UIPanelButtonTemplate")
	layoutBtn:SetSize(220, 24)
	layoutBtn:SetPoint("TOPLEFT", 26, y)
	local function updLayoutText()
		layoutBtn:SetText("Class layout: " .. (LLABEL[PS.opt.layout] or LLABEL.grid))
	end
	updLayoutText()
	layoutBtn:SetScript("OnClick", function()
		local idx = 1
		for i, m in ipairs(LMODES) do if m == PS.opt.layout then idx = i end end
		PS.opt.layout = LMODES[(idx % #LMODES) + 1]
		updLayoutText()
		PS:UpdateLayout()
	end)
	y = y - 38

	------------------------------------------------------------------
	header("Behavior")
	check("Lock frame", function() return PS.opt.locked end,
		function(v) PS.opt.locked = v end)
	check("Smart blessing fallback", function() return PS.opt.smartBuffs end,
		function(v) PS.opt.smartBuffs = v end)
	check("Hide minimap button", function() return PS.opt.minimap.hide end,
		function(v) PS.opt.minimap.hide = v; if PS.minimap then PS.minimap:SetShown(not v) end end)
	check("Demo mode (preview a full raid)", function() return ns.demoActive end,
		function(v) PS:SetDemo(v) end)
	check("Debug messages", function() return PS.opt.debug end,
		function(v) PS.opt.debug = v end)

	-- Register with Settings API (modern) or legacy fallback.
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "PallySquire")
		category.ID = "PallySquire"
		Settings.RegisterAddOnCategory(category)
		PS.optionsCategory = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
	PS.optionsPanel = panel
end

function PS:OpenOptions()
	if Settings and Settings.OpenToCategory and PS.optionsCategory then
		Settings.OpenToCategory(PS.optionsCategory.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(PS.optionsPanel)
		InterfaceOptionsFrame_OpenToCategory(PS.optionsPanel)
	end
end
