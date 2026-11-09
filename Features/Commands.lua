local _, ns = ...
local L = ns.L

-- Slash commands typed into the Hangout message box. They act on the open chat.
local Commands = {}
ns.Commands = Commands

local SECONDS = { m = 60, h = 3600 }
local TOMORROW = { tomorrow = true, morgen = true }

-- Seconds for "30m", "2h" or "tomorrow". nil if the text is none of those.
function Commands.ParseDuration(text, now)
	local lowered = ns.Util.Lower(text)
	if TOMORROW[lowered] then return ns.Util.NextMidnight(now) - now end
	local amount, unit = lowered:match("^(%d+)([mh])$")
	local count = tonumber(amount)
	if count and count > 0 then return count * SECONDS[unit] end
	return nil
end

local function IsPersonal(key)
	local prefix = key:sub(1, 1)
	return prefix == "W" or prefix == "B"
end

local function Personal(handler)
	return function(key, argument)
		if IsPersonal(key) then
			handler(key, argument)
		else
			ns.Print(L["That only works in whisper chats."])
		end
	end
end

local HANDLERS
local HELP = "/mute [30m|2h|tomorrow], /unmute, /pin, /unpin, /unread, /nick, /note, /card, /saved, /search"

HANDLERS = {
	mute = function(key, argument)
		if argument == "" then
			ns.Store.MuteFor(key, nil)
			return
		end
		local seconds = Commands.ParseDuration(argument, GetServerTime())
		if seconds then
			ns.Store.MuteFor(key, seconds)
		else
			ns.Print(L["Use /mute, /mute 30m, /mute 2h or /mute tomorrow."])
		end
	end,
	unmute = function(key) ns.Store.SetField(key, "mute", nil) end,
	pin = function(key) ns.Store.SetField(key, "pin", true) end,
	unpin = function(key) ns.Store.SetField(key, "pin", nil) end,
	unread = function(key) ns.Store.MarkUnread(key) end,
	nick = Personal(function(key, argument) ns.Store.SetField(key, "nick", argument) end),
	note = Personal(function(key, argument) ns.Store.SetField(key, "note", argument) end),
	card = Personal(function(key) ns.ContactCard.Show(key) end),
	saved = function() ns.Window.ShowSearch("is:saved") end,
	search = function(_, argument) ns.Window.ShowSearch(argument) end,
	help = function() ns.Print(HELP) end,
}

-- Returns true if the text was one of these commands.
function Commands.Run(key, text)
	local name, argument = text:match("^/(%S+)%s*(.-)%s*$")
	local handler = name and HANDLERS[ns.Util.Lower(name)]
	if not handler then return false end
	handler(key, argument)
	return true
end
