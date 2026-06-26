--[[ PallySquire — secure action buttons, layout, and visual refresh.

Compact icon-only action bar built in Lua. Cast wiring uses
SecureActionButtonTemplate: out of combat we set each button's spell/unit
attributes so a click performs a single-target blessing. Player pop-out
buttons (fixed unit) stay castable in combat; class/auto buttons only re-arm
out of combat. Right-clicking a class button toggles its player pop-outs (set
up out of combat; they persist into combat once shown).

Layout: row of controls (auto / aura / seal), then a row of class buttons.
Every button shares one dark background; class need-state is shown as a
colored BORDER, never a full fill, so the bar reads consistently.
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
	tooltip(auto, function() return ns.L["Auto Buff"] .. "\n" .. ns.L["AUTO_TOOLTIP"] end)
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

	-- Class buttons + their player pop-outs
	PS.classButtons = {}
	PS.playerButtons = {}
	for c = 1, ns.MAX_CLASSES do
		local cb = CreateFrame("Button", "PallySquireClass" .. c, parent, CONTROL_SECURE)
		decorate(cb)
		cb.icon:SetTexture(ns.ClassIcons[c])
		cb:RegisterForClicks("AnyDown")
		-- PostClick is insecure (runs after the cast): left re-arms, right toggles pop-outs.
		cb:SetScript("PostClick", function(_, button)
			if InCombatLockdown() then return end
			if button == "RightButton" then
				PS:TogglePopouts(c)
			else
				PS:UpdateLayout()
			end
		end)
		tooltip(cb, function() return ns.ClassID[c] end)
		cb:Hide()
		PS.classButtons[c] = cb

		local players = {}
		for p = 1, ns.MAX_PER_CLASS do
			local pb = CreateFrame("Button", "PallySquireClass" .. c .. "P" .. p, cb, "SecureActionButtonTemplate")
			decorate(pb)
			pb.bless:Hide()
			pb:SetFrameStrata("DIALOG")
			pb:RegisterForClicks("AnyDown")
			pb:SetAttribute("Display", 0)
			pb:Hide()
			pb.classId = c
			tooltip(pb, function(self) return self.unitName end)
			-- right-click a pop-out to set that character's blessing override
			pb:SetScript("PostClick", function(self, button)
				if button == "RightButton" and not InCombatLockdown() and self.unitName then
					PS:OpenOverrideFlyout(self.classId, self.unitName, self)
				end
			end)
			players[p] = pb
		end
		PS.playerButtons[c] = players
	end
end

-- Toggle a class's player pop-outs (out of combat; protected frames can't be
-- shown/hidden mid-combat from insecure code).
function PS:TogglePopouts(classId)
	if InCombatLockdown() then return end
	local cb = PS.classButtons[classId]
	cb.popoutsShown = not cb.popoutsShown
	for _, pb in ipairs(PS.playerButtons[classId]) do
		pb:SetShown(cb.popoutsShown and pb:GetAttribute("Display") == 1)
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

-- Class buttons: left-click casts, right-click is reserved for the fly-out
-- toggle (so it must NOT cast). Arm only the left button.
local function setClassCast(btn, spell, unit)
	if InCombatLockdown() then return end
	btn:SetAttribute("type", nil)
	btn:SetAttribute("type1", spell and "spell" or nil)
	btn:SetAttribute("spell1", spell or "")
	btn:SetAttribute("type2", nil)
	if unit then btn:SetAttribute("unit", unit) end
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
	for i, b in ipairs(controls) do
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", MARGIN + (i - 1) * STEP, top)
		b:Show()
	end
	local hasControls = #controls > 0

	if PS.opt.showAuto then
		local auto, autoSpell = ns.NextTarget()
		setCast(PS.autoButton, auto and autoSpell, auto and auto.unitid)
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

			-- Prefer the next member who needs the buff; if all are covered,
			-- still arm the button to refresh the first member so left-click
			-- always casts when a blessing is assigned to this class.
			local entry, spell = ns.NextTarget(c)
			if not entry then
				local slot = ns.GetAssign(PS.player, c)
				if slot > 0 and ns.IsSpellKnown(ns.BlessingDef[slot].id) then
					local first = ns.classes[c][1]
					if first then entry, spell = first, ns.BlessingName[slot] end
				end
			end
			setClassCast(cb, entry and spell, entry and entry.unitid)

			local players = PS.playerButtons[c]
			local entries = ns.classes[c]
			for p = 1, ns.MAX_PER_CLASS do
				local pb = players[p]
				local e = PS.opt.showPlayerButtons and entries[p] or nil
				if e then
					pb:ClearAllPoints()
					pb:SetPoint("TOP", cb, "BOTTOM", 0, -PAD - (p - 1) * STEP)
					pb.icon:SetTexture(ns.ClassIcons[c])
					pb.unitName = e.name
					local pspell, punit = ns.PlayerCast(e)
					setClassCast(pb, pspell, punit or e.unitid)  -- left casts; right = override flyout
					pb:SetAttribute("Display", 1)
					pb:SetShown(cb.popoutsShown and true or false)
				else
					pb:SetAttribute("Display", 0)
					pb:Hide()
				end
			end
		else
			cb:Hide()
			for p = 1, ns.MAX_PER_CLASS do
				local pb = PS.playerButtons[c][p]
				pb:SetAttribute("Display", 0)
				pb:Hide()
			end
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

-- Border for a self-buff control (aura / seal): green if active on you, red if not.
local function selfRing(btn, name)
	if name and ns.FindBuff("player", name) then
		btn.ring:SetColorTexture(unpack(ns.Color.good))
	else
		btn.ring:SetColorTexture(unpack(ns.Color.needsAll))
	end
end

function PS:UpdateVisuals()
	if not PS.classButtons then return end

	local selAura = ns.GetAura(PS.player)
	if selAura > 0 then
		selfRing(PS.auraButton, ns.AuraName[selAura])
	else
		PS.auraButton.ring:SetColorTexture(unpack(BORDER_NEUTRAL))  -- none selected: neutral
	end
	selfRing(PS.sealButton, ns.SealName[PS.opt.seal])

	for c = 1, ns.MAX_CLASSES do
		local cb = PS.classButtons[c]
		if cb:IsShown() then
			local missing, total = ns.ClassNeed(c)
			cb.ring:SetColorTexture(ringColor(missing, total))

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
