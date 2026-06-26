--[[ PallySquire — assignment config window (pure Lua).

Single window, columnar. Aura + Seal pickers at top, then one COLUMN per class:
the column header holds the class icon + member count + the class-wide blessing
swatch; the rows beneath are that class's group/raid members, each with a
per-character override swatch (dimmed = inherited, bright = override; Clear
reverts to the class default).

Class assignments broadcast via PS:BroadcastAssign, overrides via
PS:BroadcastNormal (both over the PLPWR protocol).
]]

local ADDON, ns = ...
local PS = ns.PS

local ROW_H = 26
local COL_W = 116           -- width of one class column
local LEFT  = 14            -- left margin / aura-seal column
local NONE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local SLOT_BG   = "Interface\\Buttons\\UI-Quickslot2"

local tinsert = table.insert

----------------------------------------------------------------------
-- Generic icon flyout
----------------------------------------------------------------------
local function createFlyout(maxSlot, iconFn, nameFn)
	local size, pad = 28, 3
	local fly = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	fly:SetFrameStrata("FULLSCREEN_DIALOG")
	fly:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	fly:EnableMouse(true)
	fly:Hide()
	fly.iconSize, fly.iconPad, fly.maxSlot = size, pad, maxSlot
	fly.buttons = {}

	for i = 0, maxSlot do
		local btn = CreateFrame("Button", nil, fly)
		btn:SetSize(size, size)
		local tex = btn:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		tex:SetTexture(i == 0 and NONE_ICON or iconFn(i))
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.30)
		local sel = btn:CreateTexture(nil, "OVERLAY")
		sel:SetPoint("TOPLEFT", -2, 2)
		sel:SetPoint("BOTTOMRIGHT", 2, -2)
		sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
		sel:SetBlendMode("ADD")
		sel:Hide()
		btn.sel = sel
		btn.slot = i
		btn:SetScript("OnClick", function()
			if fly.onPick then fly.onPick(i) end
			fly:Hide()
			PS:RefreshConfig()
		end)
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(i == 0 and ns.L["Clear"] or (nameFn(i) or "?"))
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		fly.buttons[i] = btn
	end
	return fly
end

local function openFlyout(fly, anchor, current, isKnown, skipNone)
	if fly:IsShown() and fly.owner == anchor then
		fly:Hide()
		return
	end
	fly.owner = anchor
	local size, pad = fly.iconSize, fly.iconPad
	local shown = 0
	for i = 0, fly.maxSlot do
		local btn = fly.buttons[i]
		local include = (i == 0) and not skipNone or (i > 0 and isKnown(i))
		if include then
			btn:ClearAllPoints()
			btn:SetPoint("LEFT", pad + shown * (size + pad), 0)
			btn.sel:SetShown(i == current)
			btn:Show()
			shown = shown + 1
		else
			btn:Hide()
		end
	end
	fly:SetSize(pad + shown * (size + pad) + pad, size + pad * 2)
	fly:ClearAllPoints()
	fly:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
	fly:Show()
end

local function blessKnown(i) return ns.IsSpellKnown(ns.BlessingDef[i].id) end
local function auraKnown(i)  return ns.IsSpellKnown(ns.AuraDef[i].id) end
local function sealKnown(i)  return ns.IsSpellKnown(ns.SealDef[i].id) end

function PS:OpenBlessFlyout(classId, anchor)
	local fly = PS.blessFlyout
	fly.onPick = function(slot) PS:BroadcastAssign(PS.player, classId, slot) end
	openFlyout(fly, anchor, ns.GetAssign(PS.player, classId), blessKnown)
end

function PS:OpenOverrideFlyout(classId, target, anchor)
	local fly = PS.blessFlyout
	fly.onPick = function(slot) PS:BroadcastNormal(PS.player, classId, target, slot) end
	openFlyout(fly, anchor, ns.GetNormal(PS.player, classId, target) or 0, blessKnown)
end

function PS:OpenAuraFlyout(anchor)
	local fly = PS.auraFlyout
	fly.onPick = function(slot) PS:BroadcastAura(PS.player, slot) end
	openFlyout(fly, anchor, ns.GetAura(PS.player), auraKnown)
end

function PS:OpenSealFlyout(anchor)
	local fly = PS.sealFlyout
	fly.onPick = function(slot) if slot > 0 then PS.opt.seal = slot; PS:UpdateLayout() end end
	openFlyout(fly, anchor, PS.opt.seal, sealKnown, true)
end

----------------------------------------------------------------------
-- Swatch helper (a small clickable blessing-icon button)
----------------------------------------------------------------------
local function makeSwatch(parent, size)
	local sw = CreateFrame("Button", nil, parent)
	sw:SetSize(size, size)
	local bg = sw:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", 1, -1)
	bg:SetTexture(SLOT_BG)
	local cur = sw:CreateTexture(nil, "ARTWORK")
	cur:SetAllPoints()
	cur:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local hl = sw:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.30)
	sw.cur = cur
	return sw
end

local function setSwatch(cur, slot, inherited)
	cur:SetTexture(slot > 0 and (ns.BlessingDef[slot] and ns.BlessingDef[slot].icon) or NONE_ICON)
	cur:SetDesaturated(slot == 0 or inherited)
end

-- An aura/seal row (icon-less label + selection swatch on the right)
local function makeTopRow(f, label, y, onClick)
	local row = CreateFrame("Button", nil, f)
	row:SetSize(COL_W + 30, ROW_H)
	row:SetPoint("TOPLEFT", LEFT, y)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("LEFT", 4, 0)
	name:SetText(label)
	local sw = makeSwatch(row, ROW_H - 4)
	sw:SetPoint("RIGHT", -2, 0)
	sw:SetScript("OnClick", function(self) onClick(self) end)
	row:SetScript("OnClick", function() onClick(sw) end)
	row.swatch, row.cur = sw, sw.cur
	return row
end

-- A character row inside a class column: name + override swatch.
local function makeCharRow(owner)
	local row = CreateFrame("Button", nil, owner)
	row:SetSize(COL_W - 6, ROW_H - 2)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("LEFT", 4, 0)
	name:SetWidth(COL_W - 6 - (ROW_H - 4) - 8)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	row.name = name
	local sw = makeSwatch(row, ROW_H - 6)
	sw:SetPoint("RIGHT", -2, 0)
	sw:SetScript("OnClick", function(self) PS:OpenOverrideFlyout(row.classId, row.target, self) end)
	row.swatch, row.cur = sw, sw.cur
	return row
end

local function nextCharRow(f, idx)
	local row = f.memberRows[idx]
	if not row then row = makeCharRow(f); f.memberRows[idx] = row end
	return row
end

-- A class column header: class icon + count + class-wide blessing swatch.
local function nextColHeader(f, idx)
	local h = f.headers[idx]
	if not h then
		h = CreateFrame("Frame", nil, f)
		h:SetSize(COL_W - 6, ROW_H)
		h.icon = h:CreateTexture(nil, "ARTWORK")
		h.icon:SetSize(ROW_H - 4, ROW_H - 4)
		h.icon:SetPoint("LEFT")
		h.count = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.count:SetPoint("LEFT", h.icon, "RIGHT", 3, 0)
		local sw = makeSwatch(h, ROW_H - 4)
		sw:SetPoint("RIGHT", -2, 0)
		sw:SetScript("OnClick", function(self) PS:OpenBlessFlyout(h.classId, self) end)
		h.swatch, h.cur = sw, sw.cur
		f.headers[idx] = h
	end
	return h
end

local function updateCharSwatch(row)
	local ov = ns.GetNormal(PS.player, row.classId, row.target)
	if ov and ov > 0 then
		setSwatch(row.cur, ov, false)
	else
		setSwatch(row.cur, ns.GetAssign(PS.player, row.classId), true)
	end
end

-- Members grouped by class -> { classId = { entries } }
local function membersByClass()
	local by = {}
	local units = ns.roster
	for _, e in ipairs(units) do
		if e.name and e.classId then
			by[e.classId] = by[e.classId] or {}
			tinsert(by[e.classId], e)
		end
	end
	for _, list in pairs(by) do
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	return by
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
function PS:CreateConfig()
	local f = CreateFrame("Frame", "PallySquireConfig", UIParent, "BackdropTemplate")
	f:SetSize(400, 300)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)   -- catch clicks; window re-centers itself on each render
	f:SetScript("OnHide", function()
		if PS.blessFlyout then PS.blessFlyout:Hide() end
		if PS.auraFlyout then PS.auraFlyout:Hide() end
		if PS.sealFlyout then PS.sealFlyout:Hide() end
	end)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	f:Hide()
	tinsert(UISpecialFrames, "PallySquireConfig")   -- Escape closes it
	PS.configFrame = f

	f.memberRows = {}
	f.headers = {}
	f.active = {}
	f.order = {}
	for c = 1, ns.MAX_CLASSES do f.order[#f.order + 1] = c end
	table.sort(f.order, function(a, b) return ns.ClassID[a] < ns.ClassID[b] end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT, -12)
	title:SetText(ns.L["Assignments"])

	PS.blessFlyout = createFlyout(ns.MAX_BLESSINGS,
		function(i) return ns.BlessingDef[i].icon end,
		function(i) return ns.BlessingName[i] or ns.BlessingDef[i].key end)
	PS.auraFlyout = createFlyout(ns.MAX_AURAS,
		function(i) return ns.AuraDef[i].icon end,
		function(i) return ns.AuraName[i] or "?" end)
	PS.sealFlyout = createFlyout(#ns.SealDef,
		function(i) return ns.SpellIcon(ns.SealDef[i].id) end,
		function(i) return ns.SealName[i] or "?" end)

	local y = -42
	f.auraRow = makeTopRow(f, "AURA", y, function(sw) PS:OpenAuraFlyout(sw) end); y = y - ROW_H
	f.sealRow = makeTopRow(f, "SEAL", y, function(sw) PS:OpenSealFlyout(sw) end); y = y - ROW_H - 2

	local divider = f:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", LEFT, y)
	divider:SetPoint("TOPRIGHT", -LEFT, y)
	divider:SetColorTexture(0.7, 0.6, 0.3, 0.5)
	f.divider = divider
	y = y - 10
	f.gridTop = y

	-- controls stacked in the top-right corner
	local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	closeBtn:SetSize(120, ROW_H)
	closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -LEFT, -12)
	closeBtn:SetText(CLOSE or "Close")
	closeBtn:SetScript("OnClick", function() f:Hide() end)
	f.close = closeBtn

	local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	clear:SetSize(120, ROW_H - 4)
	clear:SetPoint("TOPRIGHT", closeBtn, "BOTTOMRIGHT", 0, -4)
	clear:SetText(ns.L["Clear"])
	clear:SetScript("OnClick", function() PS:BroadcastClear(true); PS:RefreshConfig() end)
	f.clear = clear

	local free = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	free:SetPoint("TOPRIGHT", clear, "BOTTOMRIGHT", 0, -6)
	local freeLabel = free:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	freeLabel:SetPoint("RIGHT", free, "LEFT", -2, 0)   -- label on the left so it right-aligns
	freeLabel:SetText(ns.L["Free Assign"])
	free:SetScript("OnClick", function(self) PS.opt.freeassign = self:GetChecked(); PS:ScanSelf(); PS:SendSelf() end)
	f.free = free

	f.seps = {}
end

----------------------------------------------------------------------
-- Build the columnar grid
----------------------------------------------------------------------
local PER_ROW = 5   -- class columns per block-row (5 + 4 => 2 rows)
local ROWGAP  = 12

function PS:RebuildConfigRows()
	local f = PS.configFrame
	for _, r in ipairs(f.memberRows) do r:Hide() end
	for _, h in ipairs(f.headers) do h:Hide() end
	for _, s in ipairs(f.seps) do s:Hide() end
	wipe(f.active)

	local byClass = membersByClass()
	local rowTop = f.gridTop
	local maxRowH = 0
	local rowIdx = 0
	local rowTops = {}              -- top y of each block-row

	for ci, c in ipairs(f.order) do
		local bc = (ci - 1) % PER_ROW
		if bc == 0 then
			if ci > 1 then rowTop = rowTop - maxRowH - ROWGAP; maxRowH = 0 end
			rowTops[#rowTops + 1] = rowTop
		end
		local x = LEFT + bc * COL_W
		local h = nextColHeader(f, ci)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", x, rowTop)
		h.icon:SetTexture(ns.ClassIcons[c])
		h.classId = c
		local mems = byClass[c] or {}
		h.count:SetText(#mems > 0 and tostring(#mems) or "")
		setSwatch(h.cur, ns.GetAssign(PS.player, c), false)
		h:Show()

		local listY = rowTop - ROW_H - 2
		for ri, e in ipairs(mems) do
			rowIdx = rowIdx + 1
			local row = nextCharRow(f, rowIdx)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", x, listY - (ri - 1) * (ROW_H - 2))
			row.classId, row.target = c, e.name
			row.name:SetText(e.name)
			updateCharSwatch(row)
			row:Show()
			f.active[#f.active + 1] = row
		end
		local blockH = ROW_H + 2 + #mems * (ROW_H - 2)
		if blockH > maxRowH then maxRowH = blockH end
	end

	local gridBottom = rowTop - maxRowH - 6
	local numCols = math.min(PER_ROW, #f.order)

	-- separators: vertical between columns, horizontal between block-rows
	local si = 0
	local function sep()
		si = si + 1
		local s = f.seps[si]
		if not s then s = f:CreateTexture(nil, "ARTWORK"); f.seps[si] = s end
		s:SetColorTexture(0.7, 0.6, 0.3, 0.22)
		s:ClearAllPoints()
		s:Show()
		return s
	end
	for bc = 1, numCols - 1 do
		local s = sep()
		s:SetPoint("TOPLEFT", LEFT + bc * COL_W - 4, f.gridTop)
		s:SetSize(1, f.gridTop - gridBottom)
	end
	for i = 2, #rowTops do
		local s = sep()
		s:SetPoint("TOPLEFT", LEFT, rowTops[i] + ROWGAP / 2)
		s:SetSize(numCols * COL_W - 8, 1)
	end

	local width = LEFT + numCols * COL_W + LEFT
	f:SetWidth(width)
	f:SetHeight(-gridBottom + 12)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER")   -- re-center for the current content size
	PS:RefreshConfig()
end

----------------------------------------------------------------------
-- Refresh swatch textures / checkbox (no repositioning)
----------------------------------------------------------------------
function PS:RefreshConfig()
	local f = PS.configFrame
	if not f then return end
	for _, h in ipairs(f.headers) do
		if h:IsShown() and h.classId then
			setSwatch(h.cur, ns.GetAssign(PS.player, h.classId), false)
		end
	end
	local aura = ns.GetAura(PS.player)
	f.auraRow.cur:SetTexture(aura > 0 and (ns.AuraDef[aura] and ns.AuraDef[aura].icon) or NONE_ICON)
	f.auraRow.cur:SetDesaturated(aura == 0)
	local seal = PS.opt.seal
	f.sealRow.cur:SetTexture(ns.SpellIcon(ns.SealDef[seal] and ns.SealDef[seal].id) or NONE_ICON)
	f.free:SetChecked(PS.opt.freeassign)
	for _, row in ipairs(f.active) do updateCharSwatch(row) end
end

function PS:ToggleConfig()
	local f = PS.configFrame
	if not f then return end
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		PS:RebuildConfigRows()
	end
end
