--[[ PallySquire — saved variables with a tiny recursive defaults merge.

Replaces AceDB. One shared profile (settings) plus the cross-paladin
assignment tables, which are keyed by paladin name and kept identical in
shape to PallyPower's saved vars.
]]

local ADDON, ns = ...
local PS = ns.PS

----------------------------------------------------------------------
-- Defaults
----------------------------------------------------------------------
local DEFAULTS = {
	-- display / behavior
	locked        = false,
	scale         = 1.0,
	showPlayerButtons = true,
	buffDuration  = true,    -- show remaining-time text
	hideTooltips  = false,
	freeassign    = false,   -- let non-leaders change my assignment
	smartBuffs    = true,    -- auto-fall-back when a class can't take its blessing
	autobuff      = true,    -- enable the auto-buff button
	minimap       = { hide = false, angle = 200 },
	-- frame position (nil until first move -> centered)
	pos           = nil,
	-- personal selections
	aura          = 1,
	seal          = 1,
	rf            = false,
	debug         = false,
}

-- Recursively copy any missing keys from defaults into target.
local function applyDefaults(target, defaults)
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			applyDefaults(target[k], v)
		elseif target[k] == nil then
			target[k] = v
		end
	end
	return target
end
ns.applyDefaults = applyDefaults

----------------------------------------------------------------------
-- Init (called from ADDON_LOADED)
----------------------------------------------------------------------
function PS:InitDB()
	PallySquireDB = PallySquireDB or {}
	PallySquireDB.profile = applyDefaults(PallySquireDB.profile or {}, DEFAULTS)

	PS.db  = PallySquireDB
	PS.opt = PallySquireDB.profile

	-- Cross-paladin assignment state (keyed by paladin name).
	PallySquire_Assignments       = PallySquire_Assignments or {}
	PallySquire_NormalAssignments = PallySquire_NormalAssignments or {}
	PallySquire_AuraAssignments   = PallySquire_AuraAssignments or {}
	PallySquire_Presets           = PallySquire_Presets or {}

	ns.Assignments       = PallySquire_Assignments
	ns.NormalAssignments = PallySquire_NormalAssignments
	ns.AuraAssignments   = PallySquire_AuraAssignments
	ns.Presets           = PallySquire_Presets
end

----------------------------------------------------------------------
-- Assignment accessors (ensure tables exist, normalize 0/nil)
----------------------------------------------------------------------

-- Class-level blessing assignment for a paladin: ns.GetAssign(pally, classId)
function ns.GetAssign(pally, classId)
	local a = ns.Assignments[pally]
	return a and a[classId] or 0
end

function ns.SetAssign(pally, classId, slot)
	local a = ns.Assignments[pally]
	if not a then a = {}; ns.Assignments[pally] = a end
	a[classId] = slot or 0
end

-- Per-target override: ns.GetNormal(pally, classId, targetName)
function ns.GetNormal(pally, classId, target)
	local a = ns.NormalAssignments[pally]
	a = a and a[classId]
	return a and a[target] or nil
end

function ns.SetNormal(pally, classId, target, slot)
	local a = ns.NormalAssignments[pally]
	if not a then a = {}; ns.NormalAssignments[pally] = a end
	if not a[classId] then a[classId] = {} end
	if slot == 0 then slot = nil end
	a[classId][target] = slot
end

function ns.GetAura(pally)
	return ns.AuraAssignments[pally] or 0
end

function ns.SetAura(pally, slot)
	ns.AuraAssignments[pally] = slot or 0
end
