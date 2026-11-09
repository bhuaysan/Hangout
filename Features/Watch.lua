local _, ns = ...
local L = ns.L

-- Tells the player when a contact they chose comes online.
local Watch = {}
ns.Watch = Watch

local GRACE_SECONDS = 20 -- the rosters are still filling up right after login

local known = {}
local graceUntil = 0

-- Unknown counts as offline, because the guild roster can leave offline members out.
local function IsOnline(key)
	return ns.Identity.Presence(key) == true
end

function Watch.CanWatch(key, conv)
	return conv.watch == true or ns.Identity.Presence(key) ~= nil
end

function Watch.Set(key, enabled)
	if enabled then
		known[key] = IsOnline(key)
	else
		known[key] = nil
	end
	ns.Store.SetField(key, "watch", enabled or nil)
end

local function Notify(key, conv)
	if conv.mute then return end
	if not conv.vip and (ns.Get("dnd") or ns.Quiet.IsActive()) then return end
	if InCombatLockdown() then return end
	ns.Alerts.ShowNotice(key, conv, { x = L["%s is now online."]:format(ns.Store.LabelFor(key, conv)) })
end

function Watch.Check()
	-- Roster values are secret during a restriction and would all read as offline.
	if ns.Lockdown.IsActive() then return end
	local now = GetTime()
	for key, conv in pairs(ns.db.conv) do
		if conv.watch then
			local online = IsOnline(key)
			if online and known[key] == false and now >= graceUntil then
				Notify(key, conv)
			end
			known[key] = online
		end
	end
end

function Watch.Init()
	graceUntil = GetTime() + GRACE_SECONDS
end

ns.On("PRESENCE_CHANGED", Watch.Check)
