--[[ PallySquire — secure action buttons, layout, and visual refresh.

Compact icon-only action bar built in Lua. Cast wiring uses
SecureActionButtonTemplate: out of combat we set each class button's two
actions — LEFT = Greater Blessing (cast on one in-range class member, the game
splashes it to the rest), RIGHT = Normal single-target blessing on the next
member who needs it. Buttons only re-arm out of combat.

Layout: row of controls (auto / aura / seal / RF), then a grid of class
buttons. Every button shares one dark background; class need-state is shown as
a colored BORDER plus a red icon tint when missing.
]]

local ADDON, ns = ...
local PS = ns.PS

local SIZE = 32
local PAD  = 3
local MARGIN = 6   -- inner padding between the backdrop edge and the buttons
-- All buttons cast via SecureActionButtonTemplate. The class buttons' right-
-- click pop-out toggle is handled in insecure PostClick (out of combat) so it
-- never collides with the secure OnClick cast handler.
local CONTROL_SECURE = "SecureActionButtonTemplate"

local AUTO_ICON = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings"
local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local BORDER_NEUTRAL = { 0.45, 0.37, 0.15 }  -- subtle gold frame

-- How many class columns before wrapping, per layout mode.
local function classColumns()
	local m = PS.opt.layout
	if m == "vertical" then return 1 end
	if m == "horizontal" then return ns.MAX_CLASSES end
	return 3  -- "grid" default
end

----------------------------------------------------------------------
-- Region builder: square button = border + dark bg + icon (+ corner glyphs).
----------------------------------------------------------------------
local function decorate(btn)
	btn:SetSize(SIZE, SIZE)

	local ring = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
	ring:SetPoint("TOPLEFT", -1, 1)
	ring:SetPoint("BOTTOMRIGHT", 1, -1)
	ring:SetColorTexture(unpack(BORDER_NEUTRAL))
	btn.ring = ring

	local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.85)
	btn.bg = bg

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = icon

	-- assigned-blessing glyph, bottom-right corner (class buttons only)
	local bless = btn:CreateTexture(nil, "OVERLAY")
	bless:SetSize(14, 14)
	bless:SetPoint("BOTTOMRIGHT", 1, -1)
	bless:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.bless = bless

	local timer = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timer:SetPoint("BOTTOMLEFT", 2, 1)
	local font, size = timer:GetFont()
	timer:SetFont(font, size, "THICKOUTLINE")     -- wide black stroke around the glyphs
	timer:SetShadowColor(0, 0, 0, 1)
	timer:SetShadowOffset(1, -1)
	btn.timer = timer

	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.20)
	return btn
end

-- Hook (not Set) so we never clobber any secure handler scripts on the frame.
local function tooltip(btn, getText)
	btn:HookScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(getText(self) or "")
		GameTooltip:Show()
	end)
	btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------
-- Create all buttons once.
----------------------------------------------------------------------
function PS:CreateButtons()
	local parent = PS.frame

	-- Auto-buff (casts the next needed blessing across all classes)
	local auto = CreateFrame("Button", "PallySquireAuto", parent, CONTROL_SECURE)
	decorate(auto)
	auto.icon:SetTexture(AUTO_ICON)
	auto.bless:Hide(); auto.timer:Hide()
	auto:RegisterForClicks("AnyDown")
	auto:SetScript("PostClick", function() if not InCombatLockdown() then PS:UpdateLayout() end end)
	tooltip(auto, function() return ns.L["Auto Buff"] .. "\n|cffaaaaaaLeft: Greater   Right: Normal|r" end)
	PS.autoButton = auto

	-- Aura (cast selected aura on self; wheel cycles selection)
	local aura = CreateFrame("Button", "PallySquireAura", parent, CONTROL_SECURE)
	decorate(aura)
	aura.bless:Hide(); aura.timer:Hide()
	aura:RegisterForClicks("AnyDown")
	aura:EnableMouseWheel(true)
	aura:SetAttribute("unit", "player")
	aura:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		-- cycle the (synced) aura assignment, staying within 1..MAX
		local cur = ns.GetAura(PS.player)
		cur = ((cur - 1 + (delta > 0 and 1 or -1)) % ns.MAX_AURAS) + 1
		PS:BroadcastAura(PS.player, cur)
	end)
	tooltip(aura, function()
		local a = ns.GetAura(PS.player)
		return a > 0 and ns.AuraName[a] or "No aura selected"
	end)
	PS.auraButton = aura

	-- Seal (cast selected seal; wheel cycles selection)
	local seal = CreateFrame("Button", "PallySquireSeal", parent, CONTROL_SECURE)
	decorate(seal)
	seal.bless:Hide(); seal.timer:Hide()
	seal:RegisterForClicks("AnyDown")
	seal:EnableMouseWheel(true)
	seal:SetAttribute("unit", "player")
	seal:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		PS.opt.seal = ((PS.opt.seal - 1 + (delta > 0 and 1 or -1)) % #ns.SealDef) + 1
		PS:UpdateLayout()
	end)
	tooltip(seal, function() return ns.SealName[PS.opt.seal] or "Seal" end)
	PS.sealButton = seal

	-- Righteous Fury (tank threat buff; border shows on/off)
	local rf = CreateFrame("Button", "PallySquireRF", parent, CONTROL_SECURE)
	decorate(rf)
	rf.bless:Hide(); rf.timer:Hide()
	rf:RegisterForClicks("AnyDown")
	rf:SetAttribute("unit", "player")
	tooltip(rf, function() return ns.RFName or "Righteous Fury" end)
	PS.rfButton = rf

	-- Class buttons: left-click casts the Greater Blessing (whole class),
	-- right-click casts the Normal single-target blessing on the next member.
	PS.classButtons = {}
	for c = 1, ns.MAX_CLASSES do
		local cb = CreateFrame("Button", "PallySquireClass" .. c, parent, CONTROL_SECURE)
		decorate(cb)
		cb.icon:SetTexture(ns.ClassIcons[c])
		cb:RegisterForClicks("AnyDown")
		cb:SetScript("PostClick", function() if not InCombatLockdown() then PS:UpdateLayout() end end)
		tooltip(cb, function() return ns.ClassID[c] .. "\n|cffaaaaaaLeft: Greater   Right: Normal|r" end)
		cb:Hide()
		PS.classButtons[c] = cb
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function setCast(btn, spell, unit)
	if InCombatLockdown() then return end
	btn:SetAttribute("type", spell and "spell" or nil)
	btn:SetAttribute("spell", spell or "")
	if unit then btn:SetAttribute("unit", unit) end
end

-- Dual-action cast: left button (1) = Greater, right button (2) = Normal.
-- Each has its own spell and unit; a nil spell disables that button.
local function setDualCast(btn, gSpell, gUnit, nSpell, nUnit)
	if InCombatLockdown() then return end
	btn:SetAttribute("type", nil)
	btn:SetAttribute("type1", gSpell and "spell" or nil)
	btn:SetAttribute("spell1", gSpell or "")
	btn:SetAttribute("unit1", gUnit)
	btn:SetAttribute("type2", nSpell and "spell" or nil)
	btn:SetAttribute("spell2", nSpell or "")
	btn:SetAttribute("unit2", nUnit)
end

-- Border color for a class button by buff coverage.
local function ringColor(missing, total)
	if total == 0 then return unpack(BORDER_NEUTRAL) end
	if missing == 0 then return unpack(ns.Color.good) end
	if missing >= total then return unpack(ns.Color.needsAll) end
	return unpack(ns.Color.needsSome)
end

----------------------------------------------------------------------
-- Layout: structural placement + secure attribute (re)arming. Out of combat.
----------------------------------------------------------------------
local STEP = SIZE + PAD

function PS:UpdateLayout()
	if not PS.classButtons then return end
	if InCombatLockdown() then
		ns.layoutPending = true
		PS:UpdateVisuals()
		return
	end
	ns.layoutPending = false

	local frame = PS.frame
	local top = -(ns.HEADER_H or 0) - MARGIN

	-- Row 1: controls (Auto Buff / Aura / Seal all toggleable)
	local controls = {}
	if PS.opt.showAuto then controls[#controls + 1] = PS.autoButton else PS.autoButton:Hide() end
	if PS.opt.showAura then controls[#controls + 1] = PS.auraButton else PS.auraButton:Hide() end
	if PS.opt.showSeal then controls[#controls + 1] = PS.sealButton else PS.sealButton:Hide() end
	if PS.opt.showRF   then controls[#controls + 1] = PS.rfButton   else PS.rfButton:Hide()   end
	for i, b in ipairs(controls) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN + (i - 1) * STEP, top)
		b:Show()
	end
	local hasControls = #controls > 0

	if PS.opt.showAuto then
		-- left = next class needing its Greater; right = next member needing Normal
		local gName, gUnit = ns.NextGreaterClass()
		local nEntry, nSpell = ns.NextTarget()
		setDualCast(PS.autoButton, gName, gUnit, nSpell, nEntry and nEntry.unitid)
	end
	if PS.opt.showAura then
		local aura = ns.GetAura(PS.player)
		local auraName = aura > 0 and ns.AuraName[aura] or nil
		PS.auraButton.icon:SetTexture(aura > 0 and ns.AuraDef[aura] and ns.AuraDef[aura].icon or NONE_ICON)
		PS.auraButton.icon:SetDesaturated(aura == 0)   -- greyed out when none selected
		setCast(PS.auraButton, auraName, "player")
	end
	if PS.opt.showSeal then
		local sealName = ns.SealName[PS.opt.seal]
		PS.sealButton.icon:SetTexture(ns.SpellIcon(ns.SealDef[PS.opt.seal] and ns.SealDef[PS.opt.seal].id))
		setCast(PS.sealButton, sealName, "player")
	end
	if PS.opt.showRF then
		PS.rfButton.icon:SetTexture(ns.SpellIcon(ns.RIGHTEOUS_FURY_ID))
		setCast(PS.rfButton, ns.RFName, "player")
	end

	-- Row 2+: class buttons (only classes present), wrapped into a grid
	local classTop = top - (hasControls and STEP or 0)
	local cols = classColumns()
	local shown = 0
	for c = 1, ns.MAX_CLASSES do
		local cb = PS.classButtons[c]
		if (ns.classlist[c] or 0) > 0 then
			local gridCol = shown % cols
			local gridRow = math.floor(shown / cols)
			cb:ClearAllPoints()
			cb:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN + gridCol * STEP, classTop - gridRow * STEP)
			cb:Show()
			shown = shown + 1

			-- Left = Greater on a valid in-range member (splash covers the class).
			-- Right = Normal on the next member who needs it (or a refresh target).
			local gName, gUnit = ns.GreaterCast(c)
			local entry, nSpell = ns.NextTarget(c)
			if not entry then entry, nSpell = ns.NextRefreshTarget(c) end
			setDualCast(cb, gName, gUnit, nSpell, entry and entry.unitid)
		else
			cb:Hide()
		end
	end

	-- Size frame: 1 control row + however many class-grid rows we used.
	local classRows = math.ceil(shown / cols)
	local usedCols = math.max(#controls, math.min(cols, math.max(shown, 1)))
	local width = 2 * MARGIN + usedCols * STEP - PAD
	local height = (ns.HEADER_H or 0) + 2 * MARGIN + ((hasControls and 1 or 0) + classRows) * STEP - PAD
	frame:SetSize(width, height)
	PS:UpdateVisuals()
end

----------------------------------------------------------------------
-- Visuals: border color / blessing glyph / timer. Safe to run in combat.
----------------------------------------------------------------------
local function fmtTime(remaining)
	if not remaining or remaining <= 0 then return "" end
	if remaining >= 60 then return string.format("%d", math.floor(remaining / 60 + 0.5)) .. "m" end
	return string.format("%d", math.floor(remaining)) .. "s"
end

-- A self-buff control (aura / seal / RF): green border if active, red border
-- AND a red icon tint if it's missing.
local function selfRing(btn, name)
	if name and ns.FindBuff("player", name) then
		btn.ring:SetColorTexture(unpack(ns.Color.good))
		btn.icon:SetVertexColor(1, 1, 1)
	else
		btn.ring:SetColorTexture(unpack(ns.Color.needsAll))
		btn.icon:SetVertexColor(1, 0.35, 0.35)
	end
end

function PS:UpdateVisuals()
	if not PS.classButtons then return end

	local selAura = ns.GetAura(PS.player)
	if selAura > 0 then
		selfRing(PS.auraButton, ns.AuraName[selAura])
	else
		PS.auraButton.ring:SetColorTexture(unpack(BORDER_NEUTRAL))  -- none selected: neutral
		PS.auraButton.icon:SetVertexColor(1, 1, 1)
	end
	selfRing(PS.sealButton, ns.SealName[PS.opt.seal])
	if PS.opt.showRF then selfRing(PS.rfButton, ns.RFName) end

	for c = 1, ns.MAX_CLASSES do
		local cb = PS.classButtons[c]
		if cb:IsShown() then
			local missing, total = ns.ClassNeed(c)
			cb.ring:SetColorTexture(ringColor(missing, total))
			-- tint the class icon red when one or more members need the blessing
			if total > 0 and missing > 0 then
				cb.icon:SetVertexColor(1, 0.35, 0.35)
			else
				cb.icon:SetVertexColor(1, 1, 1)
			end

			local slot = ns.demoActive and (ns.demoAssign[c] or 0) or ns.GetAssign(PS.player, c)
			if slot > 0 and ns.BlessingDef[slot] then
				cb.bless:SetTexture(ns.BlessingDef[slot].icon)
				cb.bless:Show()
			else
				cb.bless:Hide()
			end

			local soonest
			for _, e in ipairs(ns.classes[c] or {}) do
				if e.hasbuff and e.expiration then
					local r = e.expiration - GetTime()
					if not soonest or r < soonest then soonest = r end
				end
			end
			cb.timer:SetText(PS.opt.buffDuration and fmtTime(soonest) or "")
		end
	end
end
