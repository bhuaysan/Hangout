local _, ns = ...

-- Makes web addresses in messages clickable. The game can't open a browser, so
-- a click offers the address for copying. Only the displayed text changes.
local Links = {}
ns.Links = Links

local LINK_TYPE = "hangouturl"
local TRAILING_PUNCTUATION = ".,;:!?'\">]"
local TRAILING_TYPOGRAPHY = "\226\128[\152-\159\166]$" -- curly quotes and the ellipsis
local PROTECTED = { H = "^|H.-|h.-|h", T = "^|T.-|t", A = "^|A.-|a" }

local function Count(text, pattern)
	local _, count = text:gsub(pattern, "")
	return count
end

-- Sentence punctuation isn't part of an address, but a closing bracket that
-- belongs to one, as in "wiki/Name_(game)", is.
local function TrimTrailing(url)
	while true do
		local trimmed = url:gsub(TRAILING_TYPOGRAPHY, "")
		local last = trimmed:sub(-1)
		local strayBracket = last == ")" and Count(trimmed, "%)") > Count(trimmed, "%(")
		if strayBracket or (last ~= "" and TRAILING_PUNCTUATION:find(last, 1, true)) then
			trimmed = trimmed:sub(1, -2)
		end
		if trimmed == url then return url end
		url = trimmed
	end
end

-- Where an address starts in a word without spaces, or nil.
local function UrlStart(token)
	local lowered = token:lower()
	local first = lowered:find("https?://[^/]")
	if first and (first == 1 or not token:sub(first - 1, first - 1):find("%w")) then
		return first
	end

	local afterOpening = #token:match("^[%(%[<\"']*") + 1
	if lowered:find("^www%.[%w%-]+%.%a", afterOpening) or lowered:find("^discord%.gg/.", afterOpening) then
		return afterOpening
	end
	return nil
end

local function LinkifyPlain(text, colorHex)
	return (text:gsub("[^%s|]+", function(token)
		local first = UrlStart(token)
		if not first then return nil end
		local url = TrimTrailing(token:sub(first))
		return token:sub(1, first - 1)
			.. "|cff" .. colorHex .. "|H" .. LINK_TYPE .. ":" .. url .. "|h" .. url .. "|h|r"
			.. token:sub(first + #url)
	end))
end

-- Wraps web addresses in a link. Game links, textures and atlases are left alone.
function Links.Decorate(text, colorHex)
	local lowered = text:lower()
	if not (lowered:find("://", 1, true) or lowered:find("www.", 1, true) or lowered:find("discord.gg", 1, true)) then
		return text
	end

	local output = {}
	local position = 1
	while true do
		local first = text:find("|[HTA]", position)
		if not first then
			output[#output + 1] = LinkifyPlain(text:sub(position), colorHex)
			break
		end
		local _, last = text:find(PROTECTED[text:sub(first + 1, first + 1)], first)
		-- An unclosed escape is ordinary text as far as links are concerned.
		local stop = last or first + 1
		output[#output + 1] = LinkifyPlain(text:sub(position, first - 1), colorHex)
		output[#output + 1] = text:sub(first, stop)
		position = stop + 1
	end
	return table.concat(output)
end

function Links.HasUrl(text)
	return Links.Decorate(text, "000000") ~= text
end

-- The address behind one of these links, or nil for any other link.
function Links.UrlFrom(link)
	return link:match("^" .. LINK_TYPE .. ":(.+)$")
end

-- The text as a message row shows it. Links go in before emoji so a ":word:"
-- inside an address stays part of the address.
function Links.Display(text)
	local hex = ns.Search.HexColor(ns.Theme.Color("accent"))
	return ns.Emoji.Render(Links.Decorate(C_ChatInfo.ReplaceIconAndGroupExpressions(text), hex))
end
