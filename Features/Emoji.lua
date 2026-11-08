local _, ns = ...

local Emoji = {}
ns.Emoji = Emoji

local ATLAS = "Interface\\AddOns\\Hangout\\Media\\emoji.png"
local ATLAS_SIZE = 512
local CELL = 32
local COLUMNS = 16

local ALIASES = {
	["+1"] = "thumbsup",
	["-1"] = "thumbsdown",
}

local indexByName = {}
for index, name in ipairs(ns.EmojiData) do
	indexByName[name] = index
end
for alias, name in pairs(ALIASES) do
	indexByName[alias] = indexByName[name]
end

Emoji.ATLAS = ATLAS

local function CellBounds(index)
	local left = (index - 1) % COLUMNS * CELL
	local top = math.floor((index - 1) / COLUMNS) * CELL
	return left, left + CELL, top, top + CELL
end

-- Texture coordinates (0 to 1) for showing one emoji on a texture.
function Emoji.TexCoords(index)
	local left, right, top, bottom = CellBounds(index)
	return left / ATLAS_SIZE, right / ATLAS_SIZE, top / ATLAS_SIZE, bottom / ATLAS_SIZE
end

function Emoji.Has(name)
	return indexByName[name] ~= nil
end

local function InlineTag(name)
	local index = indexByName[name]
	if not index then return nil end
	local left, right, top, bottom = CellBounds(index)
	return ("|T%s:0:0:0:0:%d:%d:%d:%d:%d:%d|t"):format(
		ATLAS, ATLAS_SIZE, ATLAS_SIZE, left, right, top, bottom)
end

Emoji.Tag = InlineTag

local function RenderPlain(text)
	return (text:gsub(":([%w_+%-]+):", InlineTag))
end

-- Replaces :shortcodes: with emoji for display. Hyperlinks are left alone,
-- because their hidden data is full of colons. Stored text never changes.
function Emoji.Render(text)
	if not text:find(":", 1, true) then return text end

	local output = {}
	local position = 1
	while true do
		local first, last = text:find("|H.-|h.-|h", position)
		if not first then
			output[#output + 1] = RenderPlain(text:sub(position))
			break
		end
		output[#output + 1] = RenderPlain(text:sub(position, first - 1))
		output[#output + 1] = text:sub(first, last)
		position = last + 1
	end
	return table.concat(output)
end

-- The text as a chat row or popup should show it.
function Emoji.Display(text)
	return Emoji.Render(C_ChatInfo.ReplaceIconAndGroupExpressions(text))
end
