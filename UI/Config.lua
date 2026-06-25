--[[ PallySquire — assignment config window (pure Lua).

Lets you set which blessing you cast per class (broadcast to the raid), pick
your aura, toggle Free Assign, and clear. Leaders' changes propagate via the
PLPWR protocol exactly like PallyPower.
]]

local ADDON, ns = ...
local PS = ns.PS

local ROW_H = 24
local WIN_W = 240

local function cycleBlessing(slot, dir)
	-- 0 = none, then 1..MAX_BLESSINGS
	local n = ns.MAX_BLESSINGS
	slot = (slot + dir) % (n + 1)
	return slot
end

function PS:CreateConfig()
	local f = CreateFrame("Frame", "PallySquireConfig", UIParent, "BackdropTemplate")
	f:SetSize(WIN_W, ROW_H * (ns.MAX_CLASSES + 4) + 20)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	f:Hide()

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -12)
	title:SetText("PallySquire — " .. ns.L["Assignments"])

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	f.rows = {}
	local y = -40
	for c = 1, ns.MAX_CLASSES do
		local row = CreateFrame("Button", nil, f)
		row:SetSize(WIN_W - 30, ROW_H)
		row:SetPoint("TOPLEFT", 15, y)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		local icon = row:CreateTexture(nil, "ARTWORK")
		icon:SetSize(ROW_H - 4, ROW_H - 4)
		icon:SetPoint("LEFT")
		icon:SetTexture(ns.ClassIcons[c])

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		name:SetText(ns.ClassID[c])

		local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		value:SetPoint("RIGHT", -4, 0)
		row.value = value

		row:SetScript("OnClick", function(_, button)
			local cur = ns.GetAssign(PS.player, c)
			local dir = (button == "RightButton") and -1 or 1
			PS:BroadcastAssign(PS.player, c, cycleBlessing(cur, dir))
			PS:RefreshConfig()
		end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(ns.ClassID[c])
			GameTooltip:AddLine("Left-click: next blessing", 1, 1, 1)
			GameTooltip:AddLine("Right-click: previous", 1, 1, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)

		f.rows[c] = row
		y = y - ROW_H
	end

	-- Aura cycler
	local auraBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	auraBtn:SetSize(WIN_W - 30, ROW_H)
	auraBtn:SetPoint("TOPLEFT", 15, y)
	auraBtn:SetScript("OnClick", function()
		local cur = ns.GetAura(PS.player)
		PS:BroadcastAura(PS.player, (cur % ns.MAX_AURAS) + 1)
		PS:RefreshConfig()
	end)
	f.auraBtn = auraBtn
	y = y - ROW_H - 4

	-- Free Assign toggle
	local free = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	free:SetPoint("TOPLEFT", 15, y)
	local freeLabel = free:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	freeLabel:SetPoint("LEFT", free, "RIGHT", 2, 0)
	freeLabel:SetText(ns.L["Free Assign"])
	free:SetScript("OnClick", function(self)
		PS.opt.freeassign = self:GetChecked()
		PS:ScanSelf()
		PS:SendSelf()
	end)
	f.free = free
	y = y - ROW_H - 4

	-- Clear
	local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	clear:SetSize(WIN_W - 30, ROW_H)
	clear:SetPoint("TOPLEFT", 15, y)
	clear:SetText(ns.L["Clear"])
	clear:SetScript("OnClick", function() PS:BroadcastClear(false); PS:RefreshConfig() end)

	PS.configFrame = f
end

function PS:RefreshConfig()
	local f = PS.configFrame
	if not f or not f:IsShown() then return end
	for c = 1, ns.MAX_CLASSES do
		local slot = ns.GetAssign(PS.player, c)
		f.rows[c].value:SetText(slot > 0 and (ns.BlessingName[slot] or "?") or "|cff888888—|r")
	end
	local aura = ns.GetAura(PS.player)
	f.auraBtn:SetText(string.format("%s: %s", "Aura", aura > 0 and (ns.AuraName[aura] or "?") or "—"))
	f.free:SetChecked(PS.opt.freeassign)
end

function PS:ToggleConfig()
	local f = PS.configFrame
	if not f then return end
	if f:IsShown() then f:Hide() else f:Show(); PS:RefreshConfig() end
end
