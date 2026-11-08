local _, ns = ...

local Send = {}
ns.Send = Send

local MAX_BYTES = 255
local MAX_PARTS = 4
local SPACE = 32
local PIPE = 124

local CHAT_TYPE_BY_PREFIX = {
	G = "GUILD",
	O = "OFFICER",
	P = "PARTY",
	R = "RAID",
	I = "INSTANCE_CHAT",
}

-- Returns the last byte of the unbreakable unit at position: a whole
-- hyperlink, or one UTF-8 character.
local function UnitEnd(text, position)
	local byte = text:byte(position)
	if byte == PIPE then
		local _, linkEnd = text:find("^|c[^|]*|H.-|h.-|h|r", position)
		if not linkEnd then
			_, linkEnd = text:find("^|H.-|h.-|h", position)
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
		local channelIndex = conv and conv.channelIndex
		if not channelIndex or not IsCurrentChannel(key, channelIndex) then return nil end
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

-- Must be called from a key press: channel messages require one.
-- Returns true, or false and a reason. Sent messages are recorded when the
-- server echoes them back, so they only appear once they were really sent.
function Send.Text(key, text)
	text = ns.Util.Trim(text)
	if text == "" then return false, "empty" end
	if text:sub(1, 1) == "/" then return false, "slash" end
	if ns.Lockdown.IsActive() then return false, "restricted" end

	local parts = Send.SplitMessage(text)
	if not parts then return false, "tooLong" end

	local deliver = SenderFor(key)
	if not deliver then return false, "unavailable" end

	for i = 1, #parts do
		deliver(parts[i])
	end
	return true
end
