local _, ns = ...
local L = ns.L

local Store = {}
ns.Store = Store

local TRIM_MARGIN = 50

-- Keys containing "?" have no stable identity, so they stay in memory.
-- Public channels stay in memory unless the chat was opted in to saving.
function Store.IsPersistent(key)
	if key:find("?", 1, true) or ns.CategoryOf(key) == "live" then
		return false
	end
	if ns.CategoryOf(key) == "channel" then
		local kept = ns.db.settings.keepChannels
		return kept ~= nil and kept[key] == true
	end
	return true
end

local function TableFor(key)
	if Store.IsPersistent(key) then
		return ns.db.conv
	end
	return ns.session.conv
end

function Store.Ensure(key, meta)
	local conversations = TableFor(key)
	local conv = conversations[key]
	if not conv then
		conv = { nextId = 0, m = {} }
		conversations[key] = conv
	end
	if meta then
		if meta.name then conv.name = meta.name end
		if meta.class then conv.class = meta.class end
		if meta.channelIndex then conv.channelIndex = meta.channelIndex end
		if meta.req then conv.req = true end
		if meta.stranger then conv.stranger = true end
	end
	return conv
end

function Store.Get(key)
	return TableFor(key)[key]
end

-- Newest messages are the likeliest targets, so search from the end.
function Store.FindMessage(conv, id)
	for position = #conv.m, 1, -1 do
		if conv.m[position].i == id then return conv.m[position] end
	end
	return nil
end

local function DropOldest(list, count)
	local size = #list
	for i = 1, size - count do
		list[i] = list[i + count]
	end
	for i = size - count + 1, size do
		list[i] = nil
	end
end

local function ClearRequest(key, conv)
	if not conv.req then return end
	conv.req = nil
	ns.Fire("REQUEST_ACCEPTED", key)
end

-- Public channels are too busy for unread counts to mean anything.
local function CountsUnread(key)
	return ns.CategoryOf(key) ~= "channel"
end

-- record: { t = serverTime, x = text, o = 1 if outgoing, s = sender, k = class, f = flags }
-- recovered marks a message saved after a restriction, which has already had
-- any alert it could get without its text being readable.
function Store.Add(key, meta, record, recovered)
	local conv = Store.Ensure(key, meta)
	local mention = record.o ~= 1 and record.s ~= nil and ns.Alerts.IsMention(record.x)
	conv.nextId = conv.nextId + 1
	record.i = conv.nextId
	record.c = ns.charIndex

	-- Recovered messages can be older than the newest stored ones.
	local messages = conv.m
	local position = #messages + 1
	while position > 1 and messages[position - 1].t > record.t do
		messages[position] = messages[position - 1]
		position = position - 1
	end
	messages[position] = record
	conv.lastT = math.max(conv.lastT or 0, record.t)

	-- Replying to someone accepts their message request.
	if record.o == 1 then
		ClearRequest(key, conv)
		conv.stranger = nil
	end

	if record.o == 1 or key == ns.activeKey then
		conv.unread = nil
		conv.readId = conv.nextId
	elseif CountsUnread(key) or mention then
		conv.unread = (conv.unread or 0) + 1
	end

	if Store.IsPersistent(key) then
		local cap = ns.Get("perChatCap")
		if #messages > cap + TRIM_MARGIN then
			DropOldest(messages, #messages - cap)
		end
	else
		local ring = ns.Get("sessionRing")
		if #messages > ring then
			DropOldest(messages, #messages - ring)
		end
	end

	ns.Fire("MESSAGE_ADDED", key, record, mention, recovered)
end

-- Locked elements hold secret values, so they only ever live in memory.
-- Nothing may compare, measure or index element.text or element.sender.
function Store.AddLocked(key, meta, element)
	local conv = Store.Ensure(key, meta)
	conv.lastT = element.t

	local live = ns.session.live[key]
	if not live then
		live = {}
		ns.session.live[key] = live
	end
	live[#live + 1] = element

	local ring = ns.Get("sessionRing")
	if #live > ring then
		DropOldest(live, #live - ring)
	end

	if key ~= ns.activeKey and CountsUnread(key) then
		ns.session.liveUnread[key] = (ns.session.liveUnread[key] or 0) + 1
	end

	ns.Fire("LOCKED_ADDED", key, element)
end

function Store.GetLive(key)
	return ns.session.live[key]
end

-- Notices are status lines inside a chat: { t = serverTime, kind = "failed" or
-- "away", text = ... }. They aren't messages, so they stay in memory and out of
-- search, copies, unread counts and the Hangout protocol. "away" notices keep
-- only the newest of the same text, as every whisper gets the same auto-reply.
function Store.AddNotice(key, notice)
	local list = ns.session.notices[key]
	if not list then
		list = {}
		ns.session.notices[key] = list
	end
	if notice.kind == "away" then
		for index = #list, 1, -1 do
			if list[index].kind == "away" and list[index].text == notice.text then
				table.remove(list, index)
			end
		end
	end
	list[#list + 1] = notice
	local ring = ns.Get("sessionRing")
	if #list > ring then
		DropOldest(list, #list - ring)
	end
	ns.Fire("MESSAGES_CHANGED", key)
end

function Store.GetNotices(key)
	return ns.session.notices[key]
end

function Store.RemoveNotice(key, notice)
	local list = ns.session.notices[key]
	if not list then return end
	for index = #list, 1, -1 do
		if list[index] == notice then
			table.remove(list, index)
			break
		end
	end
	ns.Fire("MESSAGES_CHANGED", key)
end

-- What a sidebar row shows: the newest message's text and its time, or nil for
-- a chat with no messages. Locked text is secret, so it is never read here.
function Store.LastActivity(key, conv)
	local live = Store.GetLive(key)
	local newestLocked = live and live[#live]
	local messages = conv.m
	local last = messages and messages[#messages]
	if newestLocked and (not last or newestLocked.t >= last.t) then
		return L["Restricted message"], newestLocked.t
	end
	if not last then return nil end

	local text = ns.Emoji.Display(last.x)
	if last.o == 1 then
		return L["You: %s"]:format(text), last.t
	elseif last.s then
		local sender = Store.SenderLabel(last.s)
		return L["%s: %s"]:format(sender:match("^%S+") or sender, text), last.t
	end
	return text, last.t
end

-- Replaces the locked elements of every conversation after recovery.
-- Recovered messages were counted as unread when they were stored, so only
-- lines that are still locked keep a restricted unread count.
function Store.ReplaceLive(remaining)
	local stillUnread = {}
	for key, elements in pairs(remaining) do
		local count = math.min(ns.session.liveUnread[key] or 0, #elements)
		if count > 0 then stillUnread[key] = count end
	end
	ns.session.live = remaining
	ns.session.liveUnread = stillUnread
	for key, conv in pairs(ns.session.conv) do
		if ns.CategoryOf(key) == "live" and not remaining[key] and #conv.m == 0 then
			ns.session.conv[key] = nil
		end
	end
	ns.Fire("LIVE_CHANGED")
end

function Store.UnreadCount(key, conv)
	return (conv.unread or 0) + (ns.session.liveUnread[key] or 0)
end

-- The most recently active chat with unread messages, for the reply key.
-- Requests and muted chats are only opened on purpose.
function Store.NewestUnreadKey()
	for _, entry in ipairs(Store.List()) do
		local conv = entry.conv
		if not conv.mute and not conv.req and Store.UnreadCount(entry.key, conv) > 0 then
			return entry.key
		end
	end
	return nil
end

-- Finds or creates a whisper chat from a name the player typed. Returns its
-- key, or nil if the text isn't a name. The server reports names capitalized,
-- so a chat must not be split in two by how the name was typed.
function Store.StartWhisper(typedName)
	local name = ns.Util.NormalizeName(ns.Util.Trim(typedName))
	if not name then return nil end

	local wanted = ns.Util.Lower(name)
	for _, entry in ipairs(Store.List()) do
		if entry.key:sub(1, 2) == "W:" and ns.Util.Lower(entry.key:sub(3)) == wanted then
			return entry.key
		end
	end

	name = name:gsub("%S+", function(word)
		local first = ns.Util.FirstCharacter(word)
		return ns.Util.Upper(first) .. ns.Util.Lower(word:sub(#first + 1))
	end)
	local key = "W:" .. name
	local conv = Store.Ensure(key, { name = name })
	conv.lastT = GetServerTime() -- so it sorts to the top of the list
	ns.Fire("CONV_CHANGED")
	return key
end

-- Muted chats and requests keep their own badge but don't add to the total.
function Store.TotalUnread()
	local total = 0
	for _, conversations in ipairs({ ns.db.conv, ns.session.conv }) do
		for key, conv in pairs(conversations) do
			if not conv.mute and not conv.req then
				total = total + Store.UnreadCount(key, conv)
			end
		end
	end
	return total
end

-- Returns whether anything was unread, so callers can decide what to announce.
local function ClearUnread(key)
	local conv = Store.Get(key)
	if not conv then
		-- A chat can have live unread messages before any record of it is stored.
		if not ns.session.liveUnread[key] then return false end
		ns.session.liveUnread[key] = nil
		return true
	end
	if (conv.unread or 0) == 0 and not ns.session.liveUnread[key] then return false end
	conv.unread = nil
	conv.readId = conv.nextId
	ns.session.liveUnread[key] = nil
	return true
end

function Store.MarkRead(key)
	if not ClearUnread(key) then return end
	ns.Fire("CONV_CHANGED")
	ns.Fire("CONV_READ", key)
end

-- Reads every chat, requests and muted ones included. Requests stay requests:
-- reading them is not the same as accepting them. Returns how many chats changed.
function Store.MarkAllRead()
	local changed = {}
	for _, entry in ipairs(Store.List()) do
		if ClearUnread(entry.key) then changed[#changed + 1] = entry.key end
	end
	-- Live unread counts can belong to a chat that has no stored record yet.
	for key in pairs(ns.session.liveUnread) do
		if ClearUnread(key) then changed[#changed + 1] = key end
	end
	if #changed > 0 then
		ns.Fire("CONV_CHANGED")
		for _, key in ipairs(changed) do ns.Fire("CONV_READ", key) end
	end
	return #changed
end

function Store.AcceptRequest(key)
	local conv = Store.Get(key)
	if not conv then return end
	ClearRequest(key, conv)
	ns.Fire("CONV_CHANGED")
end

-- Sets nick, note, pin or mute. An empty value or nil clears the field.
function Store.SetField(key, field, value)
	local conv = Store.Get(key)
	if not conv then return end
	if value == "" then value = nil end
	conv[field] = value
	ns.Fire("CONV_CHANGED")
end

function Store.Delete(key)
	ns.db.conv[key] = nil
	ns.session.conv[key] = nil
	ns.session.live[key] = nil
	ns.session.liveUnread[key] = nil
	ns.session.notices[key] = nil
	ns.Fire("CONV_CHANGED")
end

-- The name to show for a conversation.
function Store.LabelFor(key, conv)
	return conv.nick or ns.Util.DisplayName(conv.name or key)
end

-- The player's other character that sent this outgoing message, or nil if it
-- was the character they're on now.
function Store.AltName(message)
	local name = message.c and ns.db.chars[message.c]
	if name and name ~= ns.me then return ns.Util.DisplayName(name) end
	return nil
end

-- The name to show for someone speaking in group chat or a channel.
function Store.SenderLabel(name)
	local whisper = ns.db.conv["W:" .. name]
	return whisper and whisper.nick or ns.Util.DisplayName(name)
end

-- Opting a public channel in or out moves its history between saved and memory.
function Store.SetChannelSaved(key, saved)
	local conv = Store.Get(key)
	local kept = ns.db.settings.keepChannels or {}
	kept[key] = saved or nil
	ns.db.settings.keepChannels = next(kept) and kept or nil
	if conv then
		local from = saved and ns.session.conv or ns.db.conv
		local to = saved and ns.db.conv or ns.session.conv
		from[key] = nil
		to[key] = conv
	end
	ns.Fire("CONV_CHANGED")
end

-- All conversations, most recently active first.
function Store.List()
	local result = {}
	local function collect(conversations)
		for key, conv in pairs(conversations) do
			result[#result + 1] = { key = key, conv = conv }
		end
	end
	collect(ns.db.conv)
	collect(ns.session.conv)
	table.sort(result, function(a, b)
		local at, bt = a.conv.lastT or 0, b.conv.lastT or 0
		if at ~= bt then return at > bt end
		return a.key < b.key
	end)
	return result
end

-- For callers that only need to know whether any conversation exists.
function Store.IsEmpty()
	return next(ns.db.conv) == nil and next(ns.session.conv) == nil
end
