local _, ns = ...
local L = ns.L

-- /hangout test: plays situations through the real chat path, for the ones
-- that are hard to cause alone. Everything goes to chats with made-up names.
local TestMode = {}
ns.TestMode = TestMode

local FRIEND = "Testa Freund"
local STRANGER = "Testo Fremder"
local FRIEND_KEY = "W:" .. FRIEND
local STRANGER_KEY = "W:" .. STRANGER

-- The same payload order as the client's chat events.
local function Fire(event, text, name)
	ns.Capture.OnChatEvent(nil, event, text, name, "", "", "", "", 0, 0, "", 0, 0, "", 0)
end

local function FromFriend(event, text)
	ns.Store.Ensure(FRIEND_KEY, { name = FRIEND })
	Fire(event, text, FRIEND)
end

local function NewestId(key)
	local conv = ns.Store.Get(key)
	local newest = conv and conv.m[#conv.m]
	return newest and newest.i
end

local SCENARIOS = {
	whisper = function() FromFriend("CHAT_MSG_WHISPER", "Hallo, das ist eine Testnachricht.") end,
	request = function()
		ns.Store.Delete(STRANGER_KEY)
		Fire("CHAT_MSG_WHISPER", "Hallo, wir kennen uns noch nicht.", STRANGER)
	end,
	mention = function()
		Fire("CHAT_MSG_GUILD", "Hey " .. (ns.me:match("^%S+") or ns.me) .. ", bist du da?", FRIEND)
	end,
	guild = function() Fire("CHAT_MSG_GUILD", "Eine ganz normale Gildennachricht.", FRIEND) end,
	party = function() Fire("CHAT_MSG_PARTY", "Eine Nachricht in der Gruppe.", FRIEND) end,
	-- The time keeps the repeat filter from swallowing a second try.
	say = function() Fire("CHAT_MSG_SAY", "Hallo zusammen! " .. date("%H:%M:%S"), STRANGER) end,
	afk = function() FromFriend("CHAT_MSG_AFK", "Bin gleich zurück.") end,
	dnd = function() FromFriend("CHAT_MSG_DND", "Bitte nicht stören.") end,
	failed = function()
		ns.Store.Ensure(FRIEND_KEY, { name = FRIEND })
		ns.Store.AddNotice(FRIEND_KEY, { kind = "failed", t = GetServerTime(), text = "Diese Nachricht kam nicht an." })
	end,
	online = function()
		local conv = ns.Store.Ensure(FRIEND_KEY, { name = FRIEND })
		ns.Alerts.ShowNotice(FRIEND_KEY, conv, { x = L["%s is now online."]:format(ns.Store.LabelFor(FRIEND_KEY, conv)) })
	end,
	reminder = function()
		FromFriend("CHAT_MSG_WHISPER", "An diese Nachricht wirst du erinnert.")
		ns.Later.Remind(FRIEND_KEY, NewestId(FRIEND_KEY), 0)
		ns.Later.Tick(GetServerTime())
	end,
	lockdown = function()
		local active = not ns.Lockdown.IsSimulated()
		ns.Lockdown.Simulate(active)
		ns.Print(active and L["Simulated restriction is on. Repeat the command to end it."]
			or L["Simulated restriction is off."])
	end,
	clear = function()
		ns.Store.Delete(FRIEND_KEY)
		ns.Store.Delete(STRANGER_KEY)
		if ns.Lockdown.IsSimulated() then ns.Lockdown.Simulate(false) end
		ns.Print(L["Test chats removed."])
	end,
}

function TestMode.Names()
	local names = {}
	for name in pairs(SCENARIOS) do names[#names + 1] = name end
	table.sort(names)
	return names
end

-- Returns whether the scenario exists.
function TestMode.Run(name)
	local scenario = SCENARIOS[ns.Util.Lower(ns.Util.Trim(name or ""))]
	if not scenario then
		ns.Print(L["/hangout test <situation>: %s"]:format(table.concat(TestMode.Names(), ", ")))
		return false
	end
	scenario()
	return true
end
