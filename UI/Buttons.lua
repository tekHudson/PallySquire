--[[ PallySquire — secure action buttons, layout, and visual refresh.

All UI built in Lua. Cast wiring uses SecureActionButtonTemplate: out of
combat we set each button's spell/unit attributes so a click performs a
single-target blessing. Player pop-out buttons (fixed unit) remain castable
in combat; class/auto buttons only re-arm out of combat. Pop-outs reveal on
hover via SecureHandlerEnterLeaveTemplate so hovering works mid-combat.
]]

local ADDON, ns = ...
local PS = ns.PS

local BW, BH = 116, 26       -- class button size
local PAD = 2
local SECURE = "SecureActionButtonTemplate,SecureHandlerEnterLeaveTemplate"

----------------------------------------------------------------------
-- Region builder: give a button an icon, label, count and timer text.
----------------------------------------------------------------------
local function decorate(btn, w, h)
	btn:SetSize(w, h)

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	btn.bg = bg

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(h - 4, h - 4)
	icon:SetPoint("LEFT", 2, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.icon = icon

	local bless = btn:CreateTexture(nil, "OVERLAY")
	bless:SetSize(h - 8, h - 8)
	bless:SetPoint("RIGHT", -2, 0)
	bless:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	btn.bless = bless

	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", icon, "RIGHT", 3, 4)
	btn.label = label

	local timer = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	timer:SetPoint("LEFT", icon, "RIGHT", 3, -7)
	btn.timer = timer

	return btn
end

----------------------------------------------------------------------
-- Create all buttons once.
----------------------------------------------------------------------
function PS:CreateButtons()
	local parent = PS.frame

	-- Auto-buff button (casts the next needed blessing across all classes)
	local auto = CreateFrame("Button", "PallySquireAuto", parent, SECURE)
	decorate(auto, BW, BH)
	auto.icon:SetTexture("Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
	auto.label:SetText(ns.L["Auto Buff"])
	auto:RegisterForClicks("AnyDown")
	auto:SetScript("PostClick", function() if not InCombatLockdown() then PS:UpdateLayout() end end)
	auto:SetScript("OnEnter", function(self)
		if PS.opt.hideTooltips then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ns.L["AUTO_TOOLTIP"], 1, 1, 1)
		GameTooltip:Show()
	end)
	auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PS.autoButton = auto

	-- Aura button (cast selected aura on self; wheel cycles selection)
	local aura = CreateFrame("Button", "PallySquireAura", parent, SECURE)
	decorate(aura, BW, BH)
	aura:RegisterForClicks("AnyDown")
	aura:EnableMouseWheel(true)
	aura:SetAttribute("unit", "player")
	aura:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		local n = ns.MAX_AURAS
		PS.opt.aura = ((PS.opt.aura - 1 + (delta > 0 and 1 or -1)) % n) + 1
		PS:UpdateLayout()
	end)
	PS.auraButton = aura

	-- Seal button (cast selected seal; wheel cycles; right-click toggles RF)
	local seal = CreateFrame("Button", "PallySquireSeal", parent, SECURE)
	decorate(seal, BW, BH)
	seal:RegisterForClicks("AnyDown")
	seal:EnableMouseWheel(true)
	seal:SetAttribute("unit", "player")
	seal:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		local n = #ns.SealDef
		PS.opt.seal = ((PS.opt.seal - 1 + (delta > 0 and 1 or -1)) % n) + 1
		PS:UpdateLayout()
	end)
	PS.sealButton = seal

	-- Class buttons + their player pop-outs
	PS.classButtons = {}
	PS.playerButtons = {}
	for c = 1, ns.MAX_CLASSES do
		local cb = CreateFrame("Button", "PallySquireClass" .. c, parent, SECURE)
		decorate(cb, BW, BH)
		cb.icon:SetTexture(ns.ClassIcons[c])
		cb:RegisterForClicks("AnyDown")
		cb:SetScript("PostClick", function() if not InCombatLockdown() then PS:UpdateLayout() end end)
		cb:Hide()
		cb:Execute([[childs = newtable()]])
		PS.classButtons[c] = cb

		local players = {}
		for p = 1, ns.MAX_PER_CLASS do
			local pb = CreateFrame("Button", "PallySquireClass" .. c .. "P" .. p, cb, "SecureActionButtonTemplate")
			decorate(pb, BW, BH - 2)
			pb:SetFrameStrata("DIALOG")
			pb:RegisterForClicks("AnyDown")
			pb:SetAttribute("Display", 0)
			pb:Hide()
			-- register as a child of the class button for the secure hover reveal
			SecureHandlerSetFrameRef(cb, "child", pb)
			SecureHandlerExecute(cb, [[
				local child = self:GetFrameRef("child")
				childs[#childs + 1] = child
			]])
			players[p] = pb
		end
		PS.playerButtons[c] = players

		-- Secure hover: show mapped pop-outs, auto-hide when cursor leaves chain.
		cb:SetAttribute("_onenter", [[
			local lead
			for _, child in ipairs(childs) do
				if child:GetAttribute("Display") == 1 then
					child:Show()
					if lead then
						lead:AddToAutoHide(child)
					else
						lead = child
						lead:RegisterAutoHide(0.75)
					end
				end
			end
			if lead then lead:AddToAutoHide(self) end
		]])
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

local function colorFor(missing, total)
	if total == 0 then return 0.25, 0.25, 0.25 end
	if missing == 0 then return unpack(ns.Color.good) end
	if missing >= total then return unpack(ns.Color.needsAll) end
	return unpack(ns.Color.needsSome)
end

----------------------------------------------------------------------
-- Layout: structural placement + secure attribute (re)arming. Out of combat.
----------------------------------------------------------------------
function PS:UpdateLayout()
	if not PS.classButtons then return end
	if InCombatLockdown() then
		ns.layoutPending = true
		PS:UpdateVisuals()
		return
	end
	ns.layoutPending = false

	local frame = PS.frame
	local y = -PAD
	local width = BW + PAD * 2

	-- Top control row: auto / aura / seal stacked.
	PS.autoButton:ClearAllPoints()
	PS.autoButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	local auto, autoSpell = ns.NextTarget()
	setCast(PS.autoButton, auto and autoSpell, auto and auto.unitid)
	y = y - (BH + PAD)

	-- Aura
	PS.auraButton:ClearAllPoints()
	PS.auraButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	local auraName = ns.AuraName[PS.opt.aura]
	PS.auraButton.icon:SetTexture(ns.AuraDef[PS.opt.aura] and ns.AuraDef[PS.opt.aura].icon)
	PS.auraButton.label:SetText(auraName or "")
	setCast(PS.auraButton, auraName, "player")
	y = y - (BH + PAD)

	-- Seal
	PS.sealButton:ClearAllPoints()
	PS.sealButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
	local sealName = ns.SealName[PS.opt.seal]
	PS.sealButton.icon:SetTexture(ns.SpellIcon(ns.SealDef[PS.opt.seal] and ns.SealDef[PS.opt.seal].id))
	PS.sealButton.label:SetText(sealName or "")
	setCast(PS.sealButton, sealName, "player")
	y = y - (BH + PAD)

	-- Class rows (only classes present)
	for c = 1, ns.MAX_CLASSES do
		local cb = PS.classButtons[c]
		local count = ns.classlist[c] or 0
		if count > 0 then
			cb:ClearAllPoints()
			cb:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, y)
			cb:Show()
			-- arm class button to the next-needed unit of this class
			local entry, spell = ns.NextTarget(c)
			setCast(cb, entry and spell, entry and entry.unitid)
			-- wire player pop-outs
			local players = PS.playerButtons[c]
			local entries = ns.classes[c]
			for p = 1, ns.MAX_PER_CLASS do
				local pb = players[p]
				local e = PS.opt.showPlayerButtons and entries[p] or nil
				if e then
					-- stack pop-outs vertically off the right edge of the class button
					pb:ClearAllPoints()
					pb:SetPoint("TOPLEFT", cb, "TOPRIGHT", PAD, -(p - 1) * (BH - 2 + PAD))
					pb.icon:SetTexture(ns.ClassIcons[c])
					pb.label:SetText(e.name)
					local pspell, punit = ns.PlayerCast(e)
					setCast(pb, pspell, punit or e.unitid)
					pb:SetAttribute("Display", 1)
				else
					pb:SetAttribute("Display", 0)
					pb:Hide()
				end
			end
			y = y - (BH + PAD)
		else
			cb:Hide()
			for p = 1, ns.MAX_PER_CLASS do
				local pb = PS.playerButtons[c][p]
				pb:SetAttribute("Display", 0)
				pb:Hide()
			end
		end
	end

	local height = -y + PAD
	frame:SetSize(width, math.max(height, 30))
	PS:UpdateVisuals()
end

----------------------------------------------------------------------
-- Visuals: colors / counts / timers. Safe to run in combat.
----------------------------------------------------------------------
local function fmtTime(remaining)
	if not remaining or remaining <= 0 then return "" end
	if remaining >= 60 then return string.format("%dm", math.floor(remaining / 60 + 0.5)) end
	return string.format("%ds", math.floor(remaining))
end

function PS:UpdateVisuals()
	if not PS.classButtons then return end
	for c = 1, ns.MAX_CLASSES do
		local cb = PS.classButtons[c]
		if cb:IsShown() then
			local missing, total = ns.ClassNeed(c)
			cb.bg:SetColorTexture(colorFor(missing, total))
			cb.label:SetText(string.format("%s  %d/%d", ns.ClassID[c], total - missing, total))

			-- assigned blessing icon (my class assignment)
			local slot = ns.GetAssign(PS.player, c)
			cb.bless:SetTexture(slot > 0 and ns.BlessingDef[slot] and ns.BlessingDef[slot].icon or nil)

			-- soonest expiry across the class
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
