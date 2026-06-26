--[[ PallySquire — addon comms, wire-compatible with PallyPower ("PLPWR").

Implements the exact message grammar PallyPower uses so the two interoperate
in a mixed raid:
  PPLEADER <name>
  REQ
  SELF <hex rank/talent x6>@<9 class-assignment chars>
  ASELF <hex rank/talent x7>@<aura-assignment>
  ASSIGN <name> <class> <slot>
  PASSIGN <name>@<9 chars>
  MASSIGN <name> <slot>
  NASSIGN <pally> <class> <target> <slot>@...
  AASSIGN <name> <aura>
  CLEAR [SKIP]
  FREEASSIGN YES|NO | SYMCOUNT <n> | COOLDOWNS:d:r:d:r

Outgoing messages go through a small native throttle queue (replaces
ChatThrottleLib). SoD has no Symbol of Kings, so SYMCOUNT is always 0.
]]

local ADDON, ns = ...
local PS = ns.PS

local AllPallys = {}
ns.AllPallys = AllPallys

local format, strsub, strfind, gmatch = string.format, string.sub, string.find, string.gmatch
local tinsert, tconcat = table.insert, table.concat

----------------------------------------------------------------------
-- Outgoing throttle queue
----------------------------------------------------------------------
local sendQueue = {}
local queueTicker
local lastMsg

local function pump()
	local sent = 0
	while sendQueue[1] and sent < 3 do
		local m = table.remove(sendQueue, 1)
		C_ChatInfo.SendAddonMessage(m.prefix, m.msg, m.channel, m.target)
		sent = sent + 1
	end
	if not sendQueue[1] and queueTicker then
		queueTicker:Cancel()
		queueTicker = nil
	end
end

local function enqueue(msg, channel, target)
	tinsert(sendQueue, { prefix = PS.commPrefix, msg = msg, channel = channel, target = target })
	if not queueTicker then
		queueTicker = C_Timer.NewTicker(0.15, pump)
	end
end

-- Pick the right group channel and send (whisper if a target is given).
function PS:SendMessage(msg, channel, target)
	if GetNumGroupMembers() == 0 then return end
	if msg == lastMsg and not target then return end -- de-dupe identical broadcasts
	lastMsg = msg
	if target then
		enqueue(msg, "WHISPER", target)
		return
	end
	if not channel then
		if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance() then
			channel = "INSTANCE_CHAT"
		elseif IsInRaid() then
			channel = "RAID"
		else
			channel = "PARTY"
		end
	end
	enqueue(msg, channel, target)
end

function PS:InitComm()
	-- nothing persistent; queue is created lazily
end

----------------------------------------------------------------------
-- Self scan: what blessings / auras do I know? (fills AllPallys[player])
----------------------------------------------------------------------
function PS:ScanSelf()
	if not PS.isPally then return end
	local me = AllPallys[PS.player] or {}
	AllPallys[PS.player] = me
	me.AuraInfo = me.AuraInfo or {}

	for slot = 1, 6 do
		local def = ns.BlessingDef[slot]
		me[slot] = ns.IsSpellKnown(def.id) and { rank = 1, talent = 0 } or nil
	end
	for slot = 1, ns.MAX_AURAS do
		local def = ns.AuraDef[slot]
		me.AuraInfo[slot] = (def and ns.IsSpellKnown(def.id)) and { rank = 1, talent = 0 } or nil
	end
	me.freeassign = PS.opt.freeassign
end

----------------------------------------------------------------------
-- Build & send my state
----------------------------------------------------------------------
function PS:SendSelf(target)
	if GetNumGroupMembers() == 0 then return end

	if PS:CheckLeader(PS.player) then
		PS:SendMessage("PPLEADER " .. PS.player)
	end
	if not PS.isPally then return end

	local me = AllPallys[PS.player]
	if not me then PS:ScanSelf(); me = AllPallys[PS.player] end

	-- SELF: 6 blessing knowledge slots + class assignments
	local s = ""
	for i = 1, 6 do
		local k = me[i]
		s = s .. (k and format("%x%x", k.rank, k.talent) or "nn")
	end
	s = s .. "@"
	for i = 1, ns.MAX_CLASSES do
		local a = ns.GetAssign(PS.player, i)
		s = s .. (a == 0 and "n" or tostring(a))
	end
	PS:SendMessage("SELF " .. s, nil, target)

	-- ASELF: 7 aura knowledge slots + aura assignment
	s = ""
	for i = 1, ns.MAX_AURAS do
		local k = me.AuraInfo[i]
		s = s .. (k and format("%x%x", k.rank, k.talent) or "nn")
	end
	s = s .. "@" .. ns.GetAura(PS.player)
	PS:SendMessage("ASELF " .. s, nil, target)

	-- NASSIGN: per-target overrides, batched 5 per message
	local list = {}
	local normals = ns.NormalAssignments[PS.player]
	if normals then
		for classId, targets in pairs(normals) do
			for tname, slot in pairs(targets) do
				tinsert(list, format("%s %s %s %s", PS.player, classId, tname, slot))
			end
		end
	end
	local n = #list
	local offset = 1
	while offset <= n do
		PS:SendMessage("NASSIGN " .. tconcat(list, "@", offset, math.min(offset + 4, n)), nil, target)
		offset = offset + 5
	end

	-- Free-assign flag (+ SoD-stubbed symbol count / cooldowns for compat)
	local flag = PS.opt.freeassign and "YES" or "NO"
	PS:SendMessage(format("FREEASSIGN %s | SYMCOUNT 0 | COOLDOWNS:n:n:n:n", flag), nil, target)
end

function PS:RequestSync()
	PS:SendMessage("REQ")
end

----------------------------------------------------------------------
-- Incoming
----------------------------------------------------------------------
function PS:CHAT_MSG_ADDON(_, prefix, message, _, sender)
	if prefix ~= PS.commPrefix then return end
	PS:ParseMessage(ns.Short(sender), message)
end

local function ensurePally(name)
	if not AllPallys[name] then AllPallys[name] = {} end
	return AllPallys[name]
end

function PS:ParseMessage(sender, msg)
	if strfind(msg, "^PPLEADER") then
		local _, _, name = strfind(msg, "^PPLEADER (.*)")
		name = ns.Short(name)
		if PS:CheckLeader(name) then ns.leaderSeen = true end
	end

	if sender == PS.player or sender == nil then return end
	local leader = PS:CheckLeader(sender)
	local canControl = function(name)
		return name == sender or leader or PS.opt.freeassign
	end

	if msg == "REQ" then
		-- whisper our state back to the requester
		PS:SendSelf(sender)
		return
	end

	if strfind(msg, "^SELF") then
		ns.Assignments[sender] = {}
		AllPallys[sender] = {}
		ns.NormalAssignments[sender] = ns.NormalAssignments[sender] or {}
		PS:MarkPally(sender)
		local _, _, numbers, assign = strfind(msg, "SELF ([0-9a-fn]*)@([0-9n]*)")
		for i = 1, 6 do
			local rank = strsub(numbers, (i - 1) * 2 + 1, (i - 1) * 2 + 1)
			local talent = strsub(numbers, (i - 1) * 2 + 2, (i - 1) * 2 + 2)
			if rank ~= "n" and rank ~= "" then
				AllPallys[sender][i] = { rank = tonumber(rank, 16), talent = tonumber(talent) or 0 }
			end
		end
		if assign then
			for i = 1, ns.MAX_CLASSES do
				local c = strsub(assign, i, i)
				ns.Assignments[sender][i] = (c == "n" or c == "") and 0 or (tonumber(c) or 0)
			end
		end

	elseif strfind(msg, "^ASSIGN") then
		local _, _, name, class, slot = strfind(msg, "^ASSIGN (.*) (.*) (.*)")
		name = ns.Short(name)
		if not canControl(name) then return end
		ns.SetAssign(name, tonumber(class), tonumber(slot) or 0)

	elseif strfind(msg, "^PASSIGN") then
		local _, _, name, assign = strfind(msg, "^PASSIGN (.*)@([0-9n]*)")
		name = ns.Short(name)
		if not canControl(name) then return end
		if assign then
			for i = 1, ns.MAX_CLASSES do
				local c = strsub(assign, i, i)
				ns.SetAssign(name, i, (c == "n" or c == "") and 0 or (tonumber(c) or 0))
			end
		end

	elseif strfind(msg, "^MASSIGN") then
		local _, _, name, slot = strfind(msg, "^MASSIGN (.*) (.*)")
		name = ns.Short(name)
		if not canControl(name) then return end
		slot = tonumber(slot) or 0
		for i = 1, ns.MAX_CLASSES do ns.SetAssign(name, i, slot) end

	elseif strfind(msg, "^NASSIGN") then
		for pname, class, tname, slot in gmatch(strsub(msg, 9), "([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
			local name = ns.Short(pname)
			if not canControl(name) then return end
			ns.SetNormal(name, tonumber(class), tname, tonumber(slot) or 0)
		end

	elseif strfind(msg, "^ASELF") then
		local p = ensurePally(sender)
		p.AuraInfo = {}
		ns.SetAura(sender, 0)
		local _, _, numbers, assign = strfind(msg, "ASELF ([0-9a-fn]*)@([0-9n]*)")
		for i = 1, ns.MAX_AURAS do
			local rank = strsub(numbers, (i - 1) * 2 + 1, (i - 1) * 2 + 1)
			local talent = strsub(numbers, (i - 1) * 2 + 2, (i - 1) * 2 + 2)
			if rank ~= "n" and rank ~= "" then
				p.AuraInfo[i] = { rank = tonumber(rank, 16), talent = tonumber(talent) or 0 }
			end
		end
		if assign then
			ns.SetAura(sender, (assign == "n" or assign == "") and 0 or (tonumber(assign) or 0))
		end

	elseif strfind(msg, "^AASSIGN") then
		local _, _, name, aura = strfind(msg, "^AASSIGN (.*) (.*)")
		name = ns.Short(name)
		if not canControl(name) then return end
		ns.SetAura(name, tonumber(aura) or 0)

	elseif strfind(msg, "^CLEAR") then
		if leader then
			PS:ClearAssignments(sender, strfind(msg, "SKIP") ~= nil)
		elseif PS.opt.freeassign then
			PS:ClearAssignments(PS.player, strfind(msg, "SKIP") ~= nil)
		end
	end

	-- These three can ride along in a combined FREEASSIGN message.
	if strfind(msg, "FREEASSIGN YES") then
		local p = AllPallys[sender]; if p then p.freeassign = true end
	elseif strfind(msg, "FREEASSIGN NO") then
		local p = AllPallys[sender]; if p then p.freeassign = false end
	end

	PS:UpdateLayout()
end

----------------------------------------------------------------------
-- Clearing & broadcasting helpers
----------------------------------------------------------------------
function PS:ClearAssignments(pally, skipAuras)
	ns.Assignments[pally] = {}
	ns.NormalAssignments[pally] = {}
	if not skipAuras then ns.SetAura(pally, 0) end
	PS:UpdateLayout()
end

-- Broadcast a single class assignment change (used by the config UI).
function PS:BroadcastAssign(pally, classId, slot)
	ns.SetAssign(pally, classId, slot)
	PS:SendMessage(format("ASSIGN %s %d %d", pally, classId, slot))
	PS:UpdateLayout()
end

function PS:BroadcastAura(pally, slot)
	ns.SetAura(pally, slot)
	PS:SendMessage(format("AASSIGN %s %d", pally, slot))
	PS:UpdateLayout()
end

function PS:BroadcastNormal(pally, classId, target, slot)
	ns.SetNormal(pally, classId, target, slot)
	PS:SendMessage(format("NASSIGN %s %d %s %d", pally, classId, target, slot))
	PS:UpdateLayout()
end

function PS:BroadcastClear(skipAuras)
	PS:ClearAssignments(PS.player, skipAuras)
	PS:SendMessage("CLEAR" .. (skipAuras and " SKIP" or ""))
end
