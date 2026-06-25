--[[ PallySquire — options panel via the modern Settings API.

Builds a canvas panel of checkboxes + a scale slider (no AceConfig/AceGUI).
Falls back to the legacy InterfaceOptions API on older clients.
]]

local ADDON, ns = ...
local PS = ns.PS

local function makeCheck(parent, label, get, set, y)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb:SetPoint("TOPLEFT", 16, y)
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
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	sub:SetText("SoD paladin blessing manager. /ps config for assignments.")

	local y = -64
	local checks = {
		{ "Lock frame", function() return PS.opt.locked end, function(v) PS.opt.locked = v end },
		{ "Show player pop-out buttons", function() return PS.opt.showPlayerButtons end,
			function(v) PS.opt.showPlayerButtons = v; PS:UpdateLayout() end },
		{ "Show remaining-time text", function() return PS.opt.buffDuration end,
			function(v) PS.opt.buffDuration = v; PS:UpdateVisuals() end },
		{ "Hide tooltips", function() return PS.opt.hideTooltips end, function(v) PS.opt.hideTooltips = v end },
		{ "Enable auto-buff button", function() return PS.opt.autobuff end, function(v) PS.opt.autobuff = v end },
		{ "Smart blessing fallback", function() return PS.opt.smartBuffs end, function(v) PS.opt.smartBuffs = v end },
		{ "Hide minimap button", function() return PS.opt.minimap.hide end,
			function(v) PS.opt.minimap.hide = v; if PS.minimap then PS.minimap:SetShown(not v) end end },
		{ "Debug messages", function() return PS.opt.debug end, function(v) PS.opt.debug = v end },
	}
	for _, c in ipairs(checks) do
		makeCheck(panel, c[1], c[2], c[3], y)
		y = y - 26
	end

	-- Scale slider
	local slider = CreateFrame("Slider", "PallySquireScaleSlider", panel, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", 18, y - 12)
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
