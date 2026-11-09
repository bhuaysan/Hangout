local _, ns = ...
local L = ns.L

local Util = {}
ns.Util = Util

local MAX_BADGE = 99

local MONTHS_SHORT = { L["Jan"], L["Feb"], L["Mar"], L["Apr"], L["May"], L["Jun"],
	L["Jul"], L["Aug"], L["Sep"], L["Oct"], L["Nov"], L["Dec"] }
local MONTHS_LONG = { L["January"], L["February"], L["March"], L["April"], L["May"], L["June"],
	L["July"], L["August"], L["September"], L["October"], L["November"], L["December"] }

-- Fills a translated date template. The game's date() only knows English month
-- names, and German puts the day first.
local function FillDate(template, timestamp, months)
	return (template:gsub("{(%a+)}", {
		month = months[tonumber(date("%m", timestamp))],
		day = tonumber(date("%d", timestamp)),
		year = date("%Y", timestamp),
	}))
end

-- A date for labels. withYear is for dates from another year.
function Util.LongDate(timestamp, withYear)
	return FillDate(withYear and L["{month} {day}, {year}"] or L["{month} {day}"], timestamp, MONTHS_LONG)
end

-- Lua only changes the case of ASCII, so names and words with umlauts need
-- the two-byte Latin letters folded by hand. The byte length stays the same.
local UPPER_RANGE, LOWER_RANGE = "\195([\128-\158])", "\195([\160-\190])"
local MULTIPLY_SIGN, DIVISION_SIGN = 151, 183
local CASE_OFFSET = 32

function Util.Lower(text)
	return (text:lower():gsub(UPPER_RANGE, function(tail)
		if tail:byte() ~= MULTIPLY_SIGN then return "\195" .. string.char(tail:byte() + CASE_OFFSET) end
	end))
end

function Util.Upper(text)
	return (text:upper():gsub(LOWER_RANGE, function(tail)
		if tail:byte() ~= DIVISION_SIGN then return "\195" .. string.char(tail:byte() - CASE_OFFSET) end
	end))
end

-- Forever characters are "First Last" and realms are hidden. Chat events use
-- that form, but whisper targets and links can also use "First-Last".
-- Callers must only pass values that passed canaccessvalue.
function Util.NormalizeName(name)
	if not name or name == "" then return nil end
	if name:find(" ", 1, true) then
		return (name:match("^([^-]+)"))
	end
	return (name:gsub("-", " ", 1))
end

-- Battle.net names are stored as "Name#1234"; the number is noise in the UI.
function Util.DisplayName(name)
	return (name:gsub("#%d+$", ""))
end

-- A compact "when" for lists: the time today, otherwise the day.
function Util.ShortTime(timestamp, now)
	if date("%Y-%m-%d", timestamp) == date("%Y-%m-%d", now) then
		return date("%H:%M", timestamp)
	end
	if date("%Y-%m-%d", timestamp) == date("%Y-%m-%d", now - 86400) then
		return L["Yesterday"]
	end
	return FillDate(L["{month} {day}"], timestamp, MONTHS_SHORT)
end

function Util.Trim(text)
	return (text:match("^%s*(.-)%s*$"))
end

-- Cuts text to at most maxChars characters (not bytes, so UTF-8 stays intact),
-- collapsing line breaks so a quote always fits on one line.
function Util.Truncate(text, maxChars)
	text = text:gsub("%s+", " ")
	local count, position, length = 0, 1, #text
	while position <= length do
		if count == maxChars then
			return text:sub(1, position - 1) .. "\226\128\166"
		end
		local byte = text:byte(position)
		position = position + (byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1)
		count = count + 1
	end
	return text
end

-- Splits comma-separated text into a list of trimmed, lowercase entries.
function Util.ParseList(text)
	local list = {}
	for entry in text:gmatch("[^,]+") do
		entry = Util.Lower(Util.Trim(entry))
		if entry ~= "" then list[#list + 1] = entry end
	end
	return list
end

-- The text for an unread badge.
function Util.BadgeText(count)
	return count > MAX_BADGE and (MAX_BADGE .. "+") or tostring(count)
end

-- Returns the first UTF-8 character of text.
function Util.FirstCharacter(text)
	return text:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
end

-- Returns a function that runs callback once, delay seconds after the first
-- of any number of calls.
function Util.Debounced(delay, callback)
	local pending = false
	return function()
		if pending then return end
		pending = true
		C_Timer.After(delay, function()
			pending = false
			callback()
		end)
	end
end
