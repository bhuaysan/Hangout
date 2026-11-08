local _, ns = ...

-- Typing indicators, read receipts and reactions between Hangout users.
-- Addon messages are invisible to players without Hangout, and everything here
-- stays hidden until the other side has answered a hello.

local Protocol = {}
ns.Protocol = Protocol

local PREFIX = "Hangout"
local VERSION = "1"
local SEPARATOR = ";"
local MAX_FIELDS = 5
local MESSAGE_SEARCH_DEPTH = 100
local HASH_MODULUS = 4294967296

local TYPING_SEND_INTERVAL = 4
local TYPING_VISIBLE_SECONDS = 6
local READ_DELAY = 1
local RECENT_ACTIVITY_SECONDS = 300
local BUDGET_WINDOW = 10
local BUDGET_MESSAGES = 10
local BACKOFF_SECONDS = 5

local REACTION_MINE = 1
local REACTION_THEIRS = 2

Protocol.QUICK_REACTIONS = { "thumbsup", "heart", "joy", "tada", "thinking", "sob" }

local peers = {}
local lastHeard = {}
local helloSent = {}
local typingUntil = {}
local lastTypingSent = {}
local sendTimes = {}
local backoffUntil = 0
local readSenders = {}

-- Both sides see the same visible text, so a hash of it identifies a message
-- without needing shared message IDs.
function Protocol.Hash(text)
	local hash = 5381
	local visible = ns.Search.VisibleText(text)
	for position = 1, #visible do
		hash = (hash * 33 + visible:byte(position)) % HASH_MODULUS
	end
	return ("%08x"):format(hash)
end

function Protocol.Parse(text)
	local parts = {}
	for part in text:gmatch("[^" .. SEPARATOR .. "]+") do
		parts[#parts + 1] = part
	end
	if parts[1] ~= VERSION or #parts < 2 or #parts > MAX_FIELDS then
		return nil
	end
	return parts
end

local function WithinBudget(now)
	local kept = {}
	for _, sentAt in ipairs(sendTimes) do
		if now - sentAt < BUDGET_WINDOW then kept[#kept + 1] = sentAt end
	end
	sendTimes = kept
	return #sendTimes < BUDGET_MESSAGES
end

-- Returns true if the message was handed to the game.
local function Deliver(key, ...)
	local now = GetTime()
	if ns.Lockdown.IsActive() or now < backoffUntil or not WithinBudget(now) then
		return false
	end

	local payload = table.concat({ VERSION, ... }, SEPARATOR)
	local prefix = key:sub(1, 1)
	if prefix == "W" then
		local result = C_ChatInfo.SendAddonMessage(PREFIX, payload, "WHISPER", key:sub(3))
		if result and result ~= Enum.SendAddonMessageResult.Success then
			backoffUntil = now + BACKOFF_SECONDS
			return false
		end
	elseif prefix == "B" then
		local gameAccountID = ns.Identity.GameAccountForTag(key:sub(3))
		if not gameAccountID then return false end
		C_BattleNet.SendGameData(gameAccountID, PREFIX, payload)
	else
		return false
	end

	sendTimes[#sendTimes + 1] = now
	return true
end

-- Whispering an offline player prints an error in chat, so only try people
-- who are known to be online or were active a moment ago.
local function IsReachable(key, conv)
	local prefix = key:sub(1, 1)
	if prefix == "B" then
		return ns.Identity.GameAccountForTag(key:sub(3)) ~= nil
	end
	if prefix ~= "W" then return false end

	local presence = ns.Identity.Presence(key)
	if presence ~= nil then return presence end
	local latest = math.max(conv.lastT or 0, lastHeard[key] or 0)
	return key:sub(3) == ns.me or GetServerTime() - latest < RECENT_ACTIVITY_SECONDS
end

local function Transmit(key, ...)
	local conv = ns.Store.Get(key)
	if not conv or not IsReachable(key, conv) then return false end
	return Deliver(key, ...)
end

function Protocol.OnOpened(key)
	local conv = ns.Store.Get(key)
	if not conv or conv.req or helloSent[key] then return end
	if Transmit(key, "H", "1") then
		helloSent[key] = true
	end
end

function Protocol.IsPeer(key)
	return peers[key] == true
end

function Protocol.IsTyping(key)
	local untilTime = typingUntil[key]
	return untilTime ~= nil and GetTime() < untilTime
end

function Protocol.NotifyTyping(key)
	if not ns.Get("sendTyping") or not peers[key] then return end
	local now = GetTime()
	if lastTypingSent[key] and now - lastTypingSent[key] < TYPING_SEND_INTERVAL then return end
	lastTypingSent[key] = now
	Transmit(key, "T")
end

local function LastIncoming(conv)
	for position = #conv.m, 1, -1 do
		if conv.m[position].o ~= 1 then return conv.m[position] end
	end
	return nil
end

local function SendRead(key)
	if not ns.Get("sendReadReceipts") or not peers[key] then return end
	local conv = ns.Store.Get(key)
	local message = conv and LastIncoming(conv)
	if message then
		Transmit(key, "R", Protocol.Hash(message.x))
	end
end

-- Reading several messages quickly only sends one receipt.
local function SendReadSoon(key)
	if not readSenders[key] then
		readSenders[key] = ns.Util.Debounced(READ_DELAY, function() SendRead(key) end)
	end
	readSenders[key]()
end

-- Finds a recent message with this hash, skipping newer ones with the same
-- text when occurrence is given. onlyOwn limits it to ours. If the two chats
-- differ and there are too few matches, the oldest match is the best guess.
local function FindMessage(conv, ref, onlyOwn, occurrence)
	local remaining = occurrence or 0
	local found
	local oldest = math.max(1, #conv.m - MESSAGE_SEARCH_DEPTH + 1)
	for position = #conv.m, oldest, -1 do
		local message = conv.m[position]
		if (not onlyOwn or message.o == 1) and Protocol.Hash(message.x) == ref then
			found = message
			if remaining == 0 then return found end
			remaining = remaining - 1
		end
	end
	return found
end

-- How many newer recent messages have the same text as this one.
local function OccurrenceOf(conv, target, ref)
	local newer = 0
	local oldest = math.max(1, #conv.m - MESSAGE_SEARCH_DEPTH + 1)
	for position = #conv.m, oldest, -1 do
		local message = conv.m[position]
		if message == target then return newer end
		if Protocol.Hash(message.x) == ref then newer = newer + 1 end
	end
	return newer
end

local function FindById(conv, id)
	for position = #conv.m, 1, -1 do
		if conv.m[position].i == id then return conv.m[position] end
	end
	return nil
end

local function HasReaction(message, emoji, bit)
	local value = message.r and message.r[emoji] or 0
	return value % (bit * 2) >= bit
end

local function SetReaction(message, emoji, bit, enabled)
	if HasReaction(message, emoji, bit) == enabled then return end
	local reactions = message.r or {}
	local value = (reactions[emoji] or 0) + (enabled and bit or -bit)
	reactions[emoji] = value > 0 and value or nil
	message.r = next(reactions) and reactions or nil
end

-- The reaction line under a message, or nil if there are none.
function Protocol.ReactionText(reactions)
	if not reactions then return nil end
	local names = {}
	for name in pairs(reactions) do
		names[#names + 1] = name
	end
	table.sort(names)

	local parts = {}
	for _, name in ipairs(names) do
		local value = reactions[name]
		local count = value % 2 + math.floor(value / 2)
		parts[#parts + 1] = ns.Emoji.Tag(name) .. " " .. count
	end
	return table.concat(parts, "   ")
end

function Protocol.CanReact(key)
	return peers[key] == true and not ns.Lockdown.IsActive()
end

function Protocol.HasMyReaction(key, messageId, emoji)
	local conv = ns.Store.Get(key)
	local message = conv and FindById(conv, messageId)
	return message ~= nil and HasReaction(message, emoji, REACTION_MINE)
end

function Protocol.ToggleReaction(key, messageId, emoji)
	local conv = ns.Store.Get(key)
	local message = conv and FindById(conv, messageId)
	if not message then return end

	local enable = not HasReaction(message, emoji, REACTION_MINE)
	local ref = Protocol.Hash(message.x)
	local occurrence = OccurrenceOf(conv, message, ref)
	if not Transmit(key, enable and "A" or "X", ref, emoji, occurrence > 0 and occurrence or nil) then
		ns.Print("That reaction can't be sent right now.")
		return
	end
	SetReaction(message, emoji, REACTION_MINE, enable)
	ns.Fire("MESSAGES_CHANGED", key)
end

local function OnTyping(key)
	typingUntil[key] = GetTime() + TYPING_VISIBLE_SECONDS
	ns.Fire("TYPING_CHANGED")
	C_Timer.After(TYPING_VISIBLE_SECONDS + 0.1, function() ns.Fire("TYPING_CHANGED") end)
end

local function OnRead(key, conv, ref)
	local message = ref and FindMessage(conv, ref, true)
	if message and message.i > (conv.seenId or 0) then
		conv.seenId = message.i
		ns.Fire("MESSAGES_CHANGED", key)
	end
end

local function OnReaction(key, conv, ref, emoji, enabled, occurrence)
	if not ref or not emoji or not ns.Emoji.Has(emoji) then return end
	local message = FindMessage(conv, ref, false, occurrence)
	if message then
		SetReaction(message, emoji, REACTION_THEIRS, enabled)
		ns.Fire("MESSAGES_CHANGED", key)
	end
end

local function HandlePayload(key, text)
	local parts = Protocol.Parse(text)
	if not parts then return end

	-- Strangers and unknown senders get no reaction from Hangout at all.
	local conv = ns.Store.Get(key)
	if not conv or conv.req then return end

	peers[key] = true
	lastHeard[key] = GetServerTime()
	local kind = parts[2]
	if kind == "H" then
		-- They just sent this, so they're online even if a roster hasn't caught up.
		if parts[3] == "1" and Deliver(key, "H", "0") then
			helloSent[key] = true
		end
	elseif kind == "T" then
		OnTyping(key)
	elseif kind == "R" then
		OnRead(key, conv, parts[3])
	elseif kind == "A" or kind == "X" then
		OnReaction(key, conv, parts[3], parts[4], kind == "A", tonumber(parts[5]))
	end
end

local function OnEvent(_, event, prefix, text, channel, sender)
	if not canaccessvalue(prefix) or prefix ~= PREFIX then return end
	if not canaccessvalue(text) or not canaccessvalue(channel) or not canaccessvalue(sender) then return end

	if event == "CHAT_MSG_ADDON" then
		if channel ~= "WHISPER" then return end
		local name = ns.Util.NormalizeName(sender)
		if name then HandlePayload("W:" .. name, text) end
	else
		local tag = ns.Identity.TagForGameAccount(sender)
		if tag then HandlePayload("B:" .. tag, text) end
	end
end

function Protocol.Init()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_ADDON")
	frame:RegisterEvent("BN_CHAT_MSG_ADDON")
	frame:SetScript("OnEvent", OnEvent)
end

ns.On("MESSAGE_ADDED", function(key, record)
	if record.o == 1 then return end
	if typingUntil[key] then
		typingUntil[key] = nil
		ns.Fire("TYPING_CHANGED")
	end
	if key == ns.activeKey then SendReadSoon(key) end
end)

ns.On("CONV_READ", SendReadSoon)

-- A Request stays silent until it's accepted, so this is the first hello.
ns.On("REQUEST_ACCEPTED", Protocol.OnOpened)

ns.On("LOCKDOWN_CHANGED", function(active)
	if not active and ns.activeKey then SendReadSoon(ns.activeKey) end
end)
