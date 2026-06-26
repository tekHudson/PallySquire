--[[ PallySquire — casting eligibility and auto-buff target selection.

Pure logic: given current roster/buff state, decide which unit should be
buffed next and with what spell. The UI layer applies the result to secure
action-button attributes (out of combat) so a click performs the cast.
]]

local ADDON, ns = ...
local PS = ns.PS

-- Can I usefully cast this unit's assigned blessing right now?
function ns.CanBuff(entry)
	if not entry or not entry.slot or entry.slot == 0 then return false end
	if entry.dead or not entry.online or not entry.visible then return false end
	if entry.hasbuff then return false end
	if not entry.inrange then return false end
	-- Must actually know the spell.
	local def = ns.BlessingDef[entry.slot]
	if not (def and ns.IsSpellKnown(def.id)) then return false end
	return true
end

-- Sort key: refresh the most-urgent first (no buff = 0, else time remaining).
local function urgency(entry)
	if not entry.hasbuff then return 0 end
	if entry.expiration then return entry.expiration - GetTime() end
	return math.huge
end

-- Next unit needing its blessing. Restrict to `classId` when given.
-- Returns entry, spellName.
function ns.NextTarget(classId)
	local best, bestUrg
	local from, to = 1, ns.MAX_CLASSES
	if classId then from, to = classId, classId end
	for c = from, to do
		for _, entry in ipairs(ns.classes[c] or {}) do
			if ns.CanBuff(entry) then
				local u = urgency(entry)
				if not bestUrg or u < bestUrg then
					best, bestUrg = entry, u
				end
			end
		end
	end
	if best then
		return best, ns.BlessingName[best.slot]
	end
end

-- The spell + unit to wire onto a single player's pop-out secure button.
-- Always its own assigned blessing (used for in-combat single-target rebuff).
function ns.PlayerCast(entry)
	if not entry or not entry.slot or entry.slot == 0 then return nil end
	local def = ns.BlessingDef[entry.slot]
	if not (def and ns.IsSpellKnown(def.id)) then return nil end
	return ns.BlessingName[entry.slot], entry.unitid
end
