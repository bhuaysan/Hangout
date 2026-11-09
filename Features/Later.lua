local _, ns = ...
local L = ns.L

-- Reminders for messages, and the clock that also ends timed mutes.
local Later = {}
ns.Later = Later

local TICK_SECONDS = 30
local REMINDER_TEXT_CHARS = 80

function Later.Remind(key, messageId, seconds)
	local list = {}
	for _, entry in ipairs(ns.Get("reminders") or {}) do
		list[#list + 1] = entry
	end
	list[#list + 1] = { key = key, id = messageId, at = GetServerTime() + seconds }
	ns.Set("reminders", list)
end

local function IsBusy()
	return ns.Get("dnd") or ns.Quiet.IsActive() or InCombatLockdown()
end

-- Shows one due reminder per tick, as there is only one popup to show it in.
-- While the player is busy they wait, instead of going off unnoticed.
local function ShowDueReminder(now)
	if IsBusy() then return end
	local kept = {}
	local shown = false
	for _, entry in ipairs(ns.Get("reminders") or {}) do
		local conv = ns.Store.Get(entry.key)
		local message = conv and ns.Store.FindMessage(conv, entry.id)
		if message then
			if entry.at <= now and not shown then
				shown = true
				local text = ns.Util.Truncate(ns.Search.VisibleText(message.x), REMINDER_TEXT_CHARS)
				ns.Alerts.ShowNotice(entry.key, conv, { x = L["Reminder: %s"]:format(text), jump = entry.id })
			else
				kept[#kept + 1] = entry
			end
		end
	end
	ns.Set("reminders", #kept > 0 and kept or nil)
end

function Later.Tick(now)
	ns.Store.ExpireMutes(now)
	ShowDueReminder(now)
end

function Later.Init()
	Later.Tick(GetServerTime())
	C_Timer.NewTicker(TICK_SECONDS, function() Later.Tick(GetServerTime()) end)
end
