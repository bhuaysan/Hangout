local _, ns = ...
local L = ns.L

local Send = {}
ns.Send = Send

local MAX_BYTES = 255
local MAX_PARTS = 4
local SPACE = 32
local PIPE = 124
local QUOTE_PREFIX_CHARS = 32
local QUOTE_SENDER_CHARS = 24
local PENDING_SECONDS = 10

local REASON_TEXT = {
	restricted = L["Chat is restricted right now, so Hangout can't send this. Your text is still here. For something urgent, use normal chat."],
	tooLong = L["That message is too long to send."],
	slash = L["Slash commands only work in normal chat."],
	unavailable = L["This conversation can't receive messages right now."],
}

-- Whispers sent but not yet echoed by the server, oldest first: { key, text, expires }.
local pending = {}

function Send.ReasonText(reason)
	return REASON_TEXT[reason]
end

local function DropExpired()
	local now = GetTime()
	local kept = {}
	for _, entry in ipairs(pending) do
		if entry.expires > now then kept[#kept + 1] = entry end
	end
	pending = kept
end

-- Must run before the message goes out: failure events can fire during the send.
local function TrackWhisper(key, text)
	local prefix = key:sub(1, 1)
	if prefix ~= "W" and prefix ~= "B" then return end
	DropExpired()
	pending[#pending + 1] = { key = key, text = text, expires = GetTime() + PENDING_SECONDS }
end

-- Removes and returns the oldest waiting whisper that matches.
local function TakePending(matches)
	DropExpired()
	for index, entry in ipairs(pending) do
		if matches(entry) then
			table.remove(pending, index)
			return entry
		end
	end
	return nil
end

local function MarkFailed(entry)
	if entry then
		ns.Store.AddNotice(entry.key, { kind = "failed", t = GetServerTime(), text = entry.text })
	end
end

function Send.OnDeliveryFailed(key)
	MarkFailed(TakePending(function(entry) return entry.key == key end))
end

-- The game reports an offline whisper target only as a system line. Only
-- whispers Hangout sent can match, so Hangout's own addon traffic stays silent.
function Send.OnSystemMessage(text)
	if #pending == 0 or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
	local lowered = ns.Util.Lower(text)
	MarkFailed(TakePending(function(entry)
		return entry.key:sub(1, 1) == "W"
			and lowered == ns.Util.Lower(ERR_CHAT_PLAYER_NOT_FOUND_S:format(entry.key:sub(3)))
	end))
end

ns.On("MESSAGE_ADDED", function(key, record)
	if record.o ~= 1 then return end
	TakePending(function(entry) return entry.key == key and entry.text == record.x end)
end)

local CHAT_TYPE_BY_PREFIX = {
	G = "GUILD",
	O = "OFFICER",
	P = "PARTY",
	R = "RAID",
	I = "INSTANCE_CHAT",
}

-- Returns the last byte of the unbreakable unit at position: a whole
-- hyperlink, an escaped pipe, or one UTF-8 character.
local function UnitEnd(text, position)
	local byte = text:byte(position)
	if byte == PIPE then
		if text:byte(position + 1) == PIPE then return position + 1 end -- an escaped pipe
		local _, linkEnd = text:find("^|c[^|]*|H.-|h.-|h|r", position)
		if not linkEnd then
			_, linkEnd = text:find("^|H.-|h.-|h", position)
		end
		if not linkEnd then
			-- Texture and atlas tags are just as unbreakable as links.
			_, linkEnd = text:find("^|T.-|t", position)
		end
		if not linkEnd then
			_, linkEnd = text:find("^|A.-|a", position)
		end
		if linkEnd then return linkEnd end
	end
	if byte >= 240 then return position + 3 end
	if byte >= 224 then return position + 2 end
	if byte >= 192 then return position + 1 end
	return position
end

-- Splits text into chat-sized parts, preferring to break at spaces and never
-- breaking inside a link or character. Returns nil if it can't fit.
function Send.SplitMessage(text)
	local parts = {}
	local function add(part)
		part = ns.Util.Trim(part)
		if part ~= "" then parts[#parts + 1] = part end
	end

	local start, position, lastSpace = 1, 1, nil
	local length = #text
	while position <= length do
		local unitEnd = math.min(UnitEnd(text, position), length)
		if unitEnd - start + 1 > MAX_BYTES then
			local cut = lastSpace or position - 1
			if cut < start then return nil end
			add(text:sub(start, cut))
			start = cut + 1
			position = start
			lastSpace = nil
		else
			if text:byte(position) == SPACE then lastSpace = position end
			position = unitEnd + 1
		end
	end
	add(text:sub(start))

	if #parts > MAX_PARTS then return nil end
	return parts
end

-- Channel numbers change when channels are left or rejoined, so the number
-- saved with a chat must still belong to that chat's channel.
local function IsCurrentChannel(key, channelIndex)
	local _, channelName = GetChannelName(channelIndex)
	if not canaccessvalue(channelName) or not channelName then return false end

	local wanted = key:sub(3):gsub("^%d+%. ", "")
	local actual = channelName:lower()
	return actual == wanted or actual:sub(1, #wanted + 3) == wanted .. " - "
end

-- GetChannelName also takes a channel name; it returns 0 when not joined.
local function ChannelIndexByName(name)
	local id = GetChannelName(name)
	if canaccessvalue(id) and type(id) == "number" and id > 0 then return id end
	return nil
end

local function SenderFor(key)
	local prefix = key:sub(1, 1)
	local rest = key:sub(3)

	if prefix == "W" then
		return function(part) C_ChatInfo.SendChatMessage(part, "WHISPER", nil, rest) end
	elseif prefix == "B" then
		local accountID = ns.Identity.AccountIdForTag(rest)
		if not accountID then return nil end
		return function(part) C_BattleNet.SendWhisper(accountID, part) end
	elseif prefix == "C" then
		local conv = ns.Store.Get(key)
		if not conv then return nil end
		local channelIndex = conv.channelIndex
		if not channelIndex or not IsCurrentChannel(key, channelIndex) then
			-- The number is stale, but the channel may still be joined under another one.
			-- A name saved without a base name carries its old number, which the lookup can't use.
			local name = (conv.name or key:sub(3)):gsub("^%d+%. ", "")
			channelIndex = ChannelIndexByName(name)
			if not channelIndex then return nil end
			conv.channelIndex = channelIndex
		end
		return function(part) C_ChatInfo.SendChatMessage(part, "CHANNEL", nil, channelIndex) end
	end

	local chatType = CHAT_TYPE_BY_PREFIX[prefix]
	if not chatType then return nil end
	-- History is account-wide, but the game only posts to this character's guild.
	if (prefix == "G" or prefix == "O") and key ~= ns.Identity.GuildKey(prefix) then
		return nil
	end
	return function(part) C_ChatInfo.SendChatMessage(part, chatType) end
end

-- A visible quote for chats whose members may not run Hangout.
function Send.QuotePrefix(sender, text)
	-- Textures and atlases carry pipes, and a cut inside any escape would make
	-- the server reject the whole message, so no pipe may survive.
	local visible = ns.Search.VisibleText(text):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|", "/")
	return "[" .. ns.Util.Truncate(sender, QUOTE_SENDER_CHARS) .. ": " .. ns.Util.Truncate(visible, QUOTE_PREFIX_CHARS) .. "] "
end

-- Must be called from a key press: channel messages require one.
-- Returns true, or false and a reason. Sent messages are recorded when the
-- server echoes them back, so they only appear once they were really sent.
-- reply, if given, is { key, id, sender, senderName, snippet }; senderName is
-- the real character name, as sender may read "You": Hangout users get a
-- structured link to the quoted message, everyone else a visible quote.
function Send.Text(key, text, reply)
	text = ns.Util.Trim(text)
	if text == "" then return false, "empty" end
	if text:sub(1, 1) == "/" then return false, "slash" end
	if ns.Lockdown.IsActive() then return false, "restricted" end

	local conv = reply and reply.key == key and ns.Store.Get(key)
	local quoted = conv and ns.Store.FindMessage(conv, reply.id)
	local asLink = quoted and ns.Protocol.CanReact(key)
	if quoted and not asLink then
		text = Send.QuotePrefix(reply.senderName or reply.sender, quoted.x) .. text
	end

	local parts = Send.SplitMessage(text)
	if not parts then return false, "tooLong" end

	local deliver = SenderFor(key)
	if not deliver then return false, "unavailable" end

	-- The echo of the first part is what the link attaches to.
	local transmitLink = asLink and ns.Protocol.PendingReply(key, parts[1], quoted)
	for i = 1, #parts do
		TrackWhisper(key, parts[i])
		deliver(parts[i])
	end
	if transmitLink then transmitLink() end
	return true
end

-- Must be called from a click or key press, like Send.Text. Prints why if it can't send.
function Send.Retry(key, notice)
	local ok, reason = Send.Text(key, notice.text)
	if ok then
		ns.Store.RemoveNotice(key, notice)
	else
		ns.Print(Send.ReasonText(reason))
	end
end
