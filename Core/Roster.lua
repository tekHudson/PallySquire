--[[ PallySquire — group/raid roster scanning and per-unit buff state.

Builds ns.classes[classId] = { unit entries } for the grid, tracks who can
control assignments (leaders), and reads live buff state via C_UnitAuras so
remaining time reflects SoD's Enhanced Blessings automatically.
]]

local ADDON, ns = ...
local PS = ns.PS

local roster   = {}          -- flat list of unit entries
local classes  = {}          -- [classId] = { entries }
local classlist = {}         -- [classId] = count
local leaders  = {}          -- [name] = true
ns.roster, ns.classes, ns.classlist, ns.leaders = roster, classes, classlist, leaders

ns.SyncedPallys = {}         -- names we've heard SELF from (paladins running a compatible addon)

-- Unit token lists.
local party_units = { "player", "party1", "party2", "party3", "party4" }
local raid_units = {}
for i = 1, 40 do raid_units[i] = "raid" .. i end

local tinsert, twipe = table.insert, table.wipe

function PS:InitRoster()
	ns.refreshTicker = ns.NewTicker(0.5, function() PS:Tick() end)
end

function PS:MarkPally(name)
	ns.SyncedPallys[name] = true
end

-- Is `name` someone who can push assignments (raid lead/assist or party lead)?
function PS:CheckLeader(name)
	if not name then return false end
	return leaders[name] == true
end

----------------------------------------------------------------------
-- Roster rebuild (structure changes)
----------------------------------------------------------------------
function PS:UpdateRoster()
	for i = 1, ns.MAX_CLASSES do
		classlist[i] = 0
		classes[i] = classes[i] or {}
		twipe(classes[i])
	end
	twipe(roster)
	twipe(leaders)

	local inRaid = IsInRaid()
	local units = inRaid and raid_units or party_units

	for _, unitid in ipairs(units) do
		if UnitExists(unitid) then
			local isPet = unitid:find("pet") ~= nil
			if PS.opt.showPets or not isPet then
				local entry = {}
				entry.unitid = unitid
				entry.name = ns.Short(GetUnitName(unitid, true))
				local token = isPet and "PET" or (select(2, UnitClass(unitid)))
				entry.classToken = token
				entry.classId = ns.ClassIndex(token)

				if inRaid and not isPet then
					local n = tonumber(unitid:match("(%d+)"))
					local _, rank, subgroup = GetRaidRosterInfo(n)
					entry.rank = rank or 0
					entry.subgroup = subgroup or 1
				else
					entry.rank = UnitIsGroupLeader(unitid) and 2 or 0
					entry.subgroup = 1
				end

				if entry.name and entry.rank > 0 then
					leaders[entry.name] = true
				end
				if token == "PALADIN" and not isPet then
					ns.SyncedPallys[entry.name] = ns.SyncedPallys[entry.name] or false
				end

				if entry.classId then
					tinsert(roster, entry)
					tinsert(classes[entry.classId], entry)
					classlist[entry.classId] = classlist[entry.classId] + 1
				end
			end
		end
	end
	-- self is always leader-capable in a party of which we are leader, handled above
	PS:UpdateLayout()
end

----------------------------------------------------------------------
-- Per-unit buff state (called frequently; cheap)
----------------------------------------------------------------------

-- The blessing slot *I* should keep on this unit: per-target override first,
-- else the class-level assignment.
function ns.AssignedSlot(entry)
	local override = ns.GetNormal(PS.player, entry.classId, entry.name)
	if override then return override end
	return ns.GetAssign(PS.player, entry.classId)
end

-- Refresh hasbuff / expiration / liveness for one class.
function PS:ScanClass(classId)
	for _, entry in ipairs(classes[classId] or {}) do
		local unit = entry.unitid
		entry.dead    = UnitIsDeadOrGhost(unit)
		entry.online  = UnitIsConnected(unit)
		entry.visible = UnitIsVisible(unit)

		local slot = ns.AssignedSlot(entry)
		entry.slot = slot
		if slot and slot > 0 then
			local name = ns.BlessingName[slot]
			local aura = ns.FindBuff(unit, name)
			entry.hasbuff = aura ~= nil
			entry.expiration = aura and aura.expirationTime or nil
			entry.inrange = ns.SpellInRange(name, unit)
		else
			entry.hasbuff = true     -- nothing assigned => nothing needed
			entry.expiration = nil
			entry.inrange = true
		end
	end
end

function PS:ScanAllClasses()
	for i = 1, ns.MAX_CLASSES do PS:ScanClass(i) end
end

-- Spell range check, modern API with fallback. Returns boolean.
function ns.SpellInRange(name, unit)
	if not name then return true end
	if C_Spell and C_Spell.IsSpellInRange then
		local r = C_Spell.IsSpellInRange(name, unit)
		if r == nil then return true end
		return r
	end
	local r = IsSpellInRange(name, unit)
	if r == nil then return true end
	return r == 1
end

----------------------------------------------------------------------
-- Aggregate state for a class button: returns missing, total
----------------------------------------------------------------------
function ns.ClassNeed(classId)
	local missing, total = 0, 0
	for _, entry in ipairs(classes[classId] or {}) do
		if entry.slot and entry.slot > 0 and not entry.dead and entry.online then
			total = total + 1
			if not entry.hasbuff then missing = missing + 1 end
		end
	end
	return missing, total
end

----------------------------------------------------------------------
-- Periodic tick: refresh state + visuals
----------------------------------------------------------------------
function PS:Tick()
	if not ns.classes then return end
	PS:ScanAllClasses()
	PS:UpdateVisuals()
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------
function PS:GROUP_ROSTER_UPDATE()
	PS:UpdateRoster()
	PS:ScanSelf()
	PS:SendSelf()
	PS:RequestSync()
end

function PS:PLAYER_ENTERING_WORLD()
	PS:UpdateRoster()
end

function PS:UNIT_AURA(_, unit)
	-- Cheap: only rescan if the unit is one we track.
	if not unit then return end
	PS.auraDirty = true
end

function PS:SPELLS_CHANGED()
	PS:ScanSelf()
	PS:SendSelf()
end

function PS:PLAYER_REGEN_ENABLED()
	ns.inCombat = false
	PS:UpdateLayout()    -- re-arm secure casts that were deferred during combat
end

function PS:PLAYER_REGEN_DISABLED()
	ns.inCombat = true
end
