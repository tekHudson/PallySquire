--[[ PallySquire — bootstrap, shared namespace, utilities, event dispatch.

A clean, SoD-native reimagining of PallyPower. Single-target blessings only
(SoD has no Greater Blessings / Symbol of Kings), pure-Lua UI, no Ace3.
Stays wire-compatible with PallyPower via the "PLPWR" addon-message prefix.
]]

local ADDON, ns = ...

-- The public object. Modules hang methods off this; the event frame below
-- dispatches WoW events to same-named methods (e.g. PallySquire:GROUP_ROSTER_UPDATE).
local PS = {}
_G.PallySquire = PS
ns.PS = PS
ns.ADDON = ADDON

----------------------------------------------------------------------
-- Environment / constants
----------------------------------------------------------------------
PS.version   = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0"
PS.commPrefix = "PLPWR"          -- kept identical to PallyPower for raid interop
PS.player     = nil              -- set on login (name without realm)

-- SoD runs on the Classic Era client; we deliberately support only that.
-- Class indices, blessing/aura slot counts MUST match PallyPower's wire format.
ns.MAX_CLASSES   = 9
ns.MAX_PER_CLASS = 15
ns.MAX_AURAS     = 7
ns.MAX_BLESSINGS = 8   -- assignable blessing ids (1..8); 7 hex-rank slots synced

----------------------------------------------------------------------
-- Lightweight API shims (modern first, graceful fallback)
----------------------------------------------------------------------
local C_Spell = _G.C_Spell

-- Spell name from id, modern API with classic fallback.
function ns.SpellName(spellID)
	if not spellID then return nil end
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellID)
	end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
	if info then return info.name end
	return (GetSpellInfo(spellID))
end

-- Spell icon from id.
function ns.SpellIcon(spellID)
	if not spellID then return nil end
	if C_Spell and C_Spell.GetSpellTexture then
		return C_Spell.GetSpellTexture(spellID)
	end
	return (select(3, GetSpellInfo(spellID)))
end

-- Is a spell known/usable by the player right now?
function ns.IsSpellKnown(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	return IsSpellKnown and IsSpellKnown(spellID) or false
end

-- Find a helpful aura by name on a unit. Returns the aura data table or nil.
-- Used for "does this unit already have <blessing>?" and remaining-time display.
function ns.FindBuff(unit, name)
	if not name then return nil end
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		return C_UnitAuras.GetAuraDataBySpellName(unit, name, "HELPFUL")
	end
	if AuraUtil and AuraUtil.FindAuraByName then
		-- AuraUtil returns the unpacked aura fields; wrap the useful ones.
		local n, _, _, _, _, expiration, _, _, _, spellId = AuraUtil.FindAuraByName(name, unit, "HELPFUL")
		if n then
			return { name = n, expirationTime = expiration, spellId = spellId }
		end
	end
	return nil
end

-- Strip realm from "Name-Realm".
function ns.Short(name)
	if not name then return name end
	return (strsplit("-", name))
end

----------------------------------------------------------------------
-- Output helpers
----------------------------------------------------------------------
local PREFIX = "|cff66bbffPallySquire:|r "
function PS:Print(...)
	print(PREFIX .. strjoin(" ", tostringall(...)))
end

function PS:Debug(...)
	if PS.db and PS.db.profile and PS.db.profile.debug then
		print("|cffaaaaaa[PS dbg]|r " .. strjoin(" ", tostringall(...)))
	end
end

----------------------------------------------------------------------
-- Event dispatch: PS:RegisterEvent("X") -> calls PS:X(event, ...)
----------------------------------------------------------------------
local frame = CreateFrame("Frame", "PallySquireEventFrame")
ns.eventFrame = frame
local registered = {}

function PS:RegisterEvent(event)
	if not registered[event] then
		registered[event] = true
		frame:RegisterEvent(event)
	end
end

function PS:UnregisterEvent(event)
	if registered[event] then
		registered[event] = nil
		frame:UnregisterEvent(event)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = PS[event]
	if handler then
		handler(PS, event, ...)
	end
end)

-- Repeating ticker built on C_Timer (replaces AceTimer). Returns a handle
-- with :Cancel(). Used for the periodic UI/state refresh.
function ns.NewTicker(interval, callback)
	return C_Timer.NewTicker(interval, callback)
end

----------------------------------------------------------------------
-- Bootstrap lifecycle
----------------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

function PS:ADDON_LOADED(_, name)
	if name ~= ADDON then return end
	PS:UnregisterEvent("ADDON_LOADED")
	-- DB module fills in PS.db / saved-var tables.
	PS:InitDB()
end

function PS:PLAYER_LOGIN()
	PS.player = ns.Short(UnitName("player"))
	PS.isPally = select(2, UnitClass("player")) == "PALADIN"

	C_ChatInfo.RegisterAddonMessagePrefix(PS.commPrefix)

	PS:InitData()      -- build localized spell tables (needs spell data loaded)
	PS:InitComm()
	PS:InitRoster()
	PS:InitUI()        -- frame + secure buttons + minimap + options

	-- React to group / combat / aura changes.
	PS:RegisterEvent("GROUP_ROSTER_UPDATE")
	PS:RegisterEvent("PLAYER_REGEN_ENABLED")
	PS:RegisterEvent("PLAYER_REGEN_DISABLED")
	PS:RegisterEvent("CHAT_MSG_ADDON")
	PS:RegisterEvent("UNIT_AURA")
	PS:RegisterEvent("PLAYER_ENTERING_WORLD")
	if PS.isPally then
		PS:RegisterEvent("SPELLS_CHANGED")
	end

	PS:SetupSlash()
	PS:ScanSelf()
	PS:RequestSync()
	PS:UpdateRoster()
	PS:Print("v" .. PS.version .. " loaded. /ps for options.")
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
function PS:SetupSlash()
	SLASH_PALLYSQUIRE1 = "/pallysquire"
	SLASH_PALLYSQUIRE2 = "/ps"
	_G.SlashCmdList["PALLYSQUIRE"] = function(msg)
		msg = (msg or ""):lower():trim()
		if msg == "config" or msg == "assign" then
			PS:ToggleConfig()
		elseif msg == "reset" then
			PS:ResetPosition()
		elseif msg == "toggle" then
			PS:ToggleFrame()
		else
			PS:OpenOptions()
		end
	end
end
