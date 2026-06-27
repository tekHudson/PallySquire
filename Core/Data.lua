--[[ PallySquire — static SoD spell/class data + runtime name resolution.

SoD has NO Greater Blessings and NO Symbol of Kings: every blessing is cast
single-target. Slot indices below intentionally match PallyPower's Vanilla
ordering so the "PLPWR" wire format stays compatible.

Casting is done by spell *name*, which on the Classic client automatically
picks the highest rank the player knows — so we don't carry rank→id tables.
]]

local ADDON, ns = ...
local PS = ns.PS

----------------------------------------------------------------------
-- Class indexing (must match PallyPower Vanilla: 9 classes, PET at 9)
----------------------------------------------------------------------
ns.ClassID = {
	[1] = "WARRIOR", [2] = "ROGUE",   [3] = "PRIEST",
	[4] = "DRUID",   [5] = "PALADIN", [6] = "HUNTER",
	[7] = "MAGE",    [8] = "WARLOCK", [9] = "PET",
}

ns.ClassToID = {}
for id, token in pairs(ns.ClassID) do
	ns.ClassToID[token] = id
end

ns.ClassIcons = {
	[1] = "Interface\\Icons\\ClassIcon_Warrior",
	[2] = "Interface\\Icons\\ClassIcon_Rogue",
	[3] = "Interface\\Icons\\ClassIcon_Priest",
	[4] = "Interface\\Icons\\ClassIcon_Druid",
	[5] = "Interface\\Icons\\ClassIcon_Paladin",
	[6] = "Interface\\Icons\\ClassIcon_Hunter",
	[7] = "Interface\\Icons\\ClassIcon_Mage",
	[8] = "Interface\\Icons\\ClassIcon_Warlock",
	[9] = "Interface\\Icons\\Ability_Hunter_BeastTaming",
}

----------------------------------------------------------------------
-- Blessings — assignable slot 1..8 (single-target). Base spell id per slot.
-- Index order is the PallyPower wire contract; do not reorder.
----------------------------------------------------------------------
-- `gid` is the Greater Blessing spell id (class-wide splash, Symbol of Kings,
-- 15 min). Slots without a greater version (Sacrifice, Horn) omit it.
ns.BlessingDef = {
	[1] = { id = 19742,  gid = 25894, icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",   key = "Blessing of Wisdom" },
	[2] = { id = 19740,  gid = 25782, icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",  key = "Blessing of Might" },
	[3] = { id = 20217,  gid = 25898, icon = "Interface\\Icons\\Spell_Magic_MageArmor",     key = "Blessing of Kings" },
	[4] = { id = 1038,   gid = 25895, icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation",key = "Blessing of Salvation" },
	[5] = { id = 19977,  gid = 25890, icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02", key = "Blessing of Light" },
	[6] = { id = 20911,  gid = 25899, icon = "Interface\\Icons\\Spell_Nature_LightningShield", key = "Blessing of Sanctuary" },
	[7] = { id = 6940,   icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", key = "Blessing of Sacrifice" },
	[8] = { id = 425600, icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude", key = "Horn of Lordaeron" }, -- SoD
}

-- Auras — slot 1..7 (matches MAX_AURAS). Base spell id per slot.
ns.AuraDef = {
	[1] = { id = 465,   icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
	[2] = { id = 7294,  icon = "Interface\\Icons\\Spell_Holy_AuraOfLight" },
	[3] = { id = 19746, icon = "Interface\\Icons\\Spell_Holy_MindSooth" },
	[4] = { id = 19876, icon = "Interface\\Icons\\Spell_Shadow_SealOfKings" },
	[5] = { id = 19888, icon = "Interface\\Icons\\Spell_Frost_WizardMark" },
	[6] = { id = 19891, icon = "Interface\\Icons\\Spell_Fire_SealOfFire" },
	[7] = { id = 20218, icon = "Interface\\Icons\\Spell_Holy_MindVision" }, -- Sanctity Aura
}

-- Seals the wheel cycles through (base ids). SoD rune seals can be appended.
ns.SealDef = {
	[1] = { id = 21084 }, -- Seal of Righteousness
	[2] = { id = 21082 }, -- Seal of the Crusader
	[3] = { id = 20375 }, -- Seal of Command
	[4] = { id = 20164 }, -- Seal of Justice
	[5] = { id = 20165 }, -- Seal of Light
	[6] = { id = 20166 }, -- Seal of Wisdom
}

ns.RIGHTEOUS_FURY_ID  = 25780
ns.ENHANCED_BLESS_ID  = 435984  -- SoD passive: doubles blessing duration / halves mana

----------------------------------------------------------------------
-- Severity colors for the class buttons (good / some-missing / all-missing).
----------------------------------------------------------------------
ns.Color = {
	good       = { 0.0, 0.7, 0.0 },
	needsSome  = { 1.0, 1.0, 0.5 },
	needsAll   = { 1.0, 0.0, 0.0 },
	special    = { 0.0, 0.0, 1.0 },
}

----------------------------------------------------------------------
-- Runtime resolution: turn spell ids into localized names + name->slot maps.
-- Called once after PLAYER_LOGIN, when spell data is available.
----------------------------------------------------------------------
function PS:InitData()
	ns.BlessingName = {}        -- slot -> normal (single-target) name
	ns.GreaterName = {}         -- slot -> Greater Blessing name (nil if none)
	ns.BlessingSlotByName = {}  -- localized name -> slot
	for slot, def in ipairs(ns.BlessingDef) do
		local name = ns.SpellName(def.id) or def.key
		ns.BlessingName[slot] = name
		ns.BlessingSlotByName[name] = slot
		def.name = name
		if def.gid then
			ns.GreaterName[slot] = ns.SpellName(def.gid)
		end
	end

	ns.AuraName = {}
	ns.AuraSlotByName = {}
	for slot, def in ipairs(ns.AuraDef) do
		local name = ns.SpellName(def.id)
		if name then
			ns.AuraName[slot] = name
			ns.AuraSlotByName[name] = slot
			def.name = name
		end
	end

	ns.SealName = {}
	for slot, def in ipairs(ns.SealDef) do
		def.name = ns.SpellName(def.id)
		ns.SealName[slot] = def.name
	end

	ns.RFName = ns.SpellName(ns.RIGHTEOUS_FURY_ID)
	ns.hasEnhancedBlessings = ns.IsSpellKnown(ns.ENHANCED_BLESS_ID)
end

-- Class index from a class token ("MAGE" -> 7); nil if unknown.
function ns.ClassIndex(token)
	return ns.ClassToID[token]
end
