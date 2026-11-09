local _, ns = ...
local L = ns.L

-- Every party shares one history, so a line marks where a different group began.
local GroupSessions = {}
ns.GroupSessions = GroupSessions

local GAP_SECONDS = 3 * 3600
local MAX_SESSIONS = 30
local MAX_NAMES = 5
local GROUP_PREFIXES = { P = true, R = true, I = true }

-- Pure: whether these people, writing at time now, are a new group.
-- A group that gets a few replacements is still the same group.
function GroupSessions.IsNew(previous, others, now)
	if not previous or now - previous.last > GAP_SECONDS then return true end
	local before = {}
	for _, name in ipairs(previous.m) do before[name] = true end
	local staying = 0
	for _, name in ipairs(others) do
		if before[name] then staying = staying + 1 end
	end
	return staying * 2 < #others
end

function GroupSessions.Label(session)
	local names = {}
	for index, name in ipairs(session.m) do
		if index > MAX_NAMES then
			names[#names + 1] = "+" .. (#session.m - MAX_NAMES)
			break
		end
		names[#names + 1] = name:match("^%S+") or name
	end
	local list = table.concat(names, ", ")
	if session.z then return L["New group in %s: %s"]:format(session.z, list) end
	return L["New group: %s"]:format(list)
end

local function OtherMembers(key)
	local names = {}
	for _, member in ipairs(ns.Members.Roster(key) or {}) do
		if member.name ~= ns.me then names[#names + 1] = member.name end
	end
	return names
end

local function CurrentInstance()
	if not IsInInstance() then return nil end
	local name = GetInstanceInfo()
	return canaccessvalue(name) and name ~= "" and name or nil
end

ns.On("MESSAGE_ADDED", function(key, record, _, recovered)
	if recovered or not GROUP_PREFIXES[key:sub(1, 1)] then return end
	local conv = ns.Store.Get(key)
	local others = OtherMembers(key)
	if not conv or #others == 0 then return end

	local sessions = conv.groups or {}
	conv.groups = sessions
	local current = sessions[#sessions]
	if GroupSessions.IsNew(current, others, record.t) then
		-- One second early, so the line sorts in front of the message that started it.
		sessions[#sessions + 1] = { t = record.t - 1, last = record.t, m = others, z = CurrentInstance() }
		if #sessions > MAX_SESSIONS then table.remove(sessions, 1) end
	else
		current.last = record.t
	end
end)
