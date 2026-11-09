local _, ns = ...

-- Pure helpers behind the composer's Tab and :emoji: completion.
local Complete = {}
ns.Complete = Complete

local MAX_SHORTCODE_MATCHES = 8

-- EditBox cursors count characters, but Lua strings count bytes, and names can hold umlauts.
function Complete.CharToByte(text, chars)
	local bytes, seen = 0, 0
	while seen < chars and bytes < #text do
		bytes = bytes + 1
		while bytes < #text do
			local nextByte = text:byte(bytes + 1)
			if nextByte >= 0x80 and nextByte < 0xC0 then bytes = bytes + 1 else break end
		end
		seen = seen + 1
	end
	return bytes
end

function Complete.CharCount(text)
	local _, continuation = text:gsub("[\128-\191]", "")
	return #text - continuation
end

local function FirstName(name)
	return name:match("^(%S+)") or name
end

-- Names worth completing in this chat, most relevant first.
local function Candidates(conv)
	local names, seen = {}, {}
	local function add(name)
		if not name or name == "" then return end
		local key = name:lower()
		if seen[key] then return end
		seen[key] = true
		names[#names + 1] = name
	end

	local messages = conv.m or {}
	-- Group and channel messages carry a sender; whisper messages do not.
	for i = #messages, 1, -1 do
		local m = messages[i]
		local sender = m.s
		-- Outgoing messages are stored with your own name, which is never worth completing.
		if sender and m.o ~= 1 and sender ~= ns.me then add(ns.Util.DisplayName(sender)) end
	end
	if #names == 0 and conv.name then
		add(conv.nick or ns.Util.DisplayName(conv.name))
	end
	return names
end

-- Full names whose full name or first name starts with the prefix, case-insensitively.
function Complete.Names(conv, prefix)
	local result = {}
	if not conv or not prefix or prefix == "" then return result end
	local needle = prefix:lower()
	for _, name in ipairs(Candidates(conv)) do
		local lower = name:lower()
		if lower:sub(1, #needle) == needle or FirstName(lower):sub(1, #needle) == needle then
			result[#result + 1] = name
		end
	end
	return result
end

-- Finds a ":partial" ending at the cursor (a character offset). Returns the byte index of the
-- colon and the partial, or nil. At least two characters are needed so "10:3" or ":)" stay quiet.
function Complete.ShortcodeAt(text, cursor)
	if not text or not cursor then return nil end
	local before = text:sub(1, Complete.CharToByte(text, cursor))
	local start, partial = before:match("()%:([%w_]+)$")
	if not start or #partial < 2 then return nil end
	-- A colon glued to a preceding word is a time or label, not a shortcode.
	if start > 1 and before:sub(start - 1, start - 1):match("[%w_]") then return nil end
	return start, partial
end

function Complete.ShortcodeMatches(partial)
	local all = ns.Emoji.Search(partial)
	-- Prefix matches come first so ":sm" offers "smile" before names that merely contain it.
	-- The needle is normalized the way Emoji.Search does it.
	local needle = partial:lower():gsub("[%s_]", "")
	local prefix, rest = {}, {}
	for _, name in ipairs(all) do
		local list = (name:gsub("_", "")):lower():sub(1, #needle) == needle and prefix or rest
		list[#list + 1] = name
	end
	local matches = {}
	for _, list in ipairs({ prefix, rest }) do
		for _, name in ipairs(list) do
			if #matches >= MAX_SHORTCODE_MATCHES then return matches end
			matches[#matches + 1] = name
		end
	end
	return matches
end
