local _, ns = ...

-- The only file that touches raw chat event payloads. Payload fields can be
-- secret values: comparing one, measuring it with #, or using it as a table
-- key raises a Lua error, so every field is checked before it is used.

local Capture = {}
ns.Capture = Capture

Capture.LOCKED_KEY = "L:restricted"
Capture.FLAG_GM = 1

local RECOVERY_DELAY = 1

local LOCKED_META = { name = "During restriction" }

local ROUTES = {
	CHAT_MSG_WHISPER = { kind = "whisper" },
	CHAT_MSG_WHISPER_INFORM = { kind = "whisper", out = true },
	CHAT_MSG_BN_WHISPER = { kind = "bnet" },
	CHAT_MSG_BN_WHISPER_INFORM = { kind = "bnet", out = true },
	CHAT_MSG_GUILD = { kind = "guild", prefix = "G", label = "Guild" },
	CHAT_MSG_OFFICER = { kind = "guild", prefix = "O", label = "Officer" },
	CHAT_MSG_PARTY = { kind = "group", key = "P:party", label = "Party" },
	CHAT_MSG_PARTY_LEADER = { kind = "group", key = "P:party", label = "Party" },
	CHAT_MSG_RAID = { kind = "group", key = "R:raid", label = "Raid" },
	CHAT_MSG_RAID_LEADER = { kind = "group", key = "R:raid", label = "Raid" },
	CHAT_MSG_RAID_WARNING = { kind = "group", key = "R:raid", label = "Raid" },
	CHAT_MSG_INSTANCE_CHAT = { kind = "group", key = "I:instance", label = "Instance" },
	CHAT_MSG_INSTANCE_CHAT_LEADER = { kind = "group", key = "I:instance", label = "Instance" },
	CHAT_MSG_CHANNEL = { kind = "channel" },
}

local function ChannelKey(channelName, channelBaseName)
	local name
	if canaccessvalue(channelBaseName) and channelBaseName and channelBaseName ~= "" then
		name = channelBaseName
	elseif canaccessvalue(channelName) and channelName and channelName ~= "" then
		name = channelName
	end
	if not name then return nil end
	return "C:" .. name:lower(), name
end

-- Conversation key and display name for types that don't depend on the sender.
local function RoomKey(route, channelName, channelBaseName)
	if route.kind == "guild" then
		return ns.Identity.GuildKey(route.prefix), route.label
	elseif route.kind == "group" then
		return route.key, route.label
	elseif route.kind == "channel" then
		return ChannelKey(channelName, channelBaseName)
	end
	return nil
end

-- Spam screening for an incoming character whisper with readable values.
-- Returns dropped, isNewRequest, isNewStranger. With Requests turned off, a
-- stranger's chat is marked so that their later whispers are still screened.
local function ScreenWhisper(name, guid, text)
	if name == ns.me then return false, false, false end
	local conv = ns.Store.Get("W:" .. name)
	local unaccepted = conv == nil or conv.req == true or conv.stranger == true
	local stranger = unaccepted and not ns.Identity.IsKnown(name, guid)
	if ns.Filter.BlocksWhisper(name, text, stranger) then
		ns.Filter.CountBlocked()
		return true, false, false
	end
	if not stranger or conv ~= nil then return false, false, false end
	local requests = ns.Get("requestsEnabled")
	return false, requests, not requests
end

local function ScreenChannel(name, text, now)
	if name == ns.me then return false end
	if ns.Filter.BlocksChannel(name, text, now) then
		ns.Filter.CountBlocked()
		return true
	end
	return false
end

local function HandleLocked(event, route, text, playerName, channelName, channelBaseName, lineID, specialFlags)
	local key, label = RoomKey(route, channelName, channelBaseName)
	local meta = key and { name = label } or LOCKED_META
	ns.Store.AddLocked(key or Capture.LOCKED_KEY, meta, {
		locked = true,
		t = GetServerTime(),
		o = route.out and 1 or nil,
		text = text,
		sender = playerName,
		lineID = lineID,
		event = event,
		gm = canaccessvalue(specialFlags) and specialFlags == "GM" or nil,
	})
end

local function HandleWhisper(route, text, playerName, guid, isGM)
	local name = ns.Util.NormalizeName(playerName)
	if not name then return end

	local isRequest, isStranger = false, false
	if not route.out and not isGM then
		local dropped
		dropped, isRequest, isStranger = ScreenWhisper(name, guid, text)
		if dropped then return end
	end

	ns.Store.Add("W:" .. name,
		{ name = name, class = ns.Identity.ClassFromGUID(guid), req = isRequest or nil, stranger = isStranger or nil },
		{
			t = GetServerTime(),
			x = text,
			o = route.out and 1 or nil,
			f = isGM and Capture.FLAG_GM or nil,
		})
end

local function HandleBattleNet(route, text, bnSenderID, isGM)
	local tag = bnSenderID and ns.Identity.BattleTag(bnSenderID)
	local key = tag and ("B:" .. tag) or ("B:?" .. tostring(bnSenderID))
	ns.Store.Add(key, { name = tag or "Battle.net friend" }, {
		t = GetServerTime(),
		x = text,
		o = route.out and 1 or nil,
		f = isGM and Capture.FLAG_GM or nil,
	})
end

local function HandleRoom(route, text, playerName, channelName, channelIndex, channelBaseName, guid, isGM)
	local key, label = RoomKey(route, channelName, channelBaseName)
	if not key then return end

	local sender = ns.Util.NormalizeName(playerName)
	local now = GetServerTime()
	if route.kind == "channel" and sender and not isGM and ScreenChannel(sender, text, now) then
		return
	end

	local meta = { name = label }
	if route.kind == "channel" and canaccessvalue(channelIndex) then
		meta.channelIndex = channelIndex
	end

	ns.Store.Add(key, meta, {
		t = now,
		x = text,
		o = sender ~= nil and sender == ns.me and 1 or nil,
		s = sender,
		k = ns.Identity.ClassFromGUID(guid),
		f = isGM and Capture.FLAG_GM or nil,
	})
end

local function HandleReadable(route, text, playerName, channelName, specialFlags, channelIndex, channelBaseName, guid, bnSenderID)
	if not text or text == "" then return end
	local isGM = canaccessvalue(specialFlags) and specialFlags == "GM"

	if route.kind == "whisper" then
		HandleWhisper(route, text, playerName, guid, isGM)
	elseif route.kind == "bnet" then
		HandleBattleNet(route, text, bnSenderID, isGM)
	else
		HandleRoom(route, text, playerName, channelName, channelIndex, channelBaseName, guid, isGM)
	end
end

local function OnChatEvent(_, event, text, playerName, _, channelName, _, specialFlags, _, channelIndex, channelBaseName, _, lineID, guid, bnSenderID)
	local route = ROUTES[event]
	if not route then return end

	if canaccessvalue(text) and canaccessvalue(playerName) and canaccessvalue(guid) and canaccessvalue(bnSenderID) then
		HandleReadable(route, text, playerName, channelName, specialFlags, channelIndex, channelBaseName, guid, bnSenderID)
	else
		HandleLocked(event, route, text, playerName, channelName, channelBaseName, lineID, specialFlags)
	end
end

local function RecoverWhisper(route, element, name, text, guid, class)
	-- If an outgoing line reports our own name, the partner is unknown.
	if route.out and name == ns.me then return false end

	local isRequest, isStranger = false, false
	if not route.out and not element.gm then
		local dropped
		dropped, isRequest, isStranger = ScreenWhisper(name, guid, text)
		if dropped then return true end
	end

	ns.Store.Add("W:" .. name, { name = name, class = class, req = isRequest or nil, stranger = isStranger or nil }, {
		t = element.t,
		x = text,
		o = route.out and 1 or nil,
		f = element.gm and Capture.FLAG_GM or nil,
	}, true)
	return true
end

local function RecoverRoom(route, element, key, name, text, class)
	if key == Capture.LOCKED_KEY then return false end
	if route.kind == "channel" and not element.gm and ScreenChannel(name, text, element.t) then
		return true
	end
	ns.Store.Add(key, nil, {
		t = element.t,
		x = text,
		s = name,
		k = class,
		o = name == ns.me and 1 or nil,
		f = element.gm and Capture.FLAG_GM or nil,
	}, true)
	return true
end

-- Asks the game for a locked message's real content. Returns true once it has
-- been dealt with. Anything uncertain stays a live-only row: losing a line from
-- history is better than filing it under the wrong person.
local function RecoverElement(key, element)
	local route = ROUTES[element.event]
	if route.kind == "bnet" then return false end
	if not C_ChatInfo.IsValidChatLine(element.lineID) then return false end

	local text = C_ChatInfo.GetChatLineText(element.lineID)
	local rawName = C_ChatInfo.GetChatLineSenderName(element.lineID)
	if not canaccessvalue(text) or not canaccessvalue(rawName) or not text or text == "" then
		return false
	end
	local name = ns.Util.NormalizeName(rawName)
	if not name then return false end

	local guid = C_ChatInfo.GetChatLineSenderGUID(element.lineID)
	if not canaccessvalue(guid) then guid = nil end
	local class = ns.Identity.ClassFromGUID(guid)

	if route.kind == "whisper" then
		return RecoverWhisper(route, element, name, text, guid, class)
	end
	return RecoverRoom(route, element, key, name, text, class)
end

function Capture.Recover()
	local remaining = {}
	for key, elements in pairs(ns.session.live) do
		for _, element in ipairs(elements) do
			if not RecoverElement(key, element) then
				remaining[key] = remaining[key] or {}
				table.insert(remaining[key], element)
			end
		end
	end
	ns.Store.ReplaceLive(remaining)
end

function Capture.Start()
	local frame = CreateFrame("Frame")
	for event in pairs(ROUTES) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", OnChatEvent)

	ns.On("LOCKDOWN_CHANGED", function(active)
		if not active then
			C_Timer.After(RECOVERY_DELAY, Capture.Recover)
		end
	end)
end

Capture.OnChatEvent = OnChatEvent
