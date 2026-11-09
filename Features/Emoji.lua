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

-- The picker's tabs, with the game-flavored emoji first.
Emoji.GROUPS = {
	{ label = "Adventure", names = {
		"crossed_swords", "dagger", "shield", "bow", "hammer", "axe", "pick", "wrench", "bomb", "key", "lock",
		"scroll", "book", "alembic", "test_tube", "crystal_ball", "candle", "map", "compass", "tent", "castle",
		"moneybag", "coin", "gem", "crown", "trophy", "medal", "beer", "beers",
		"mage", "elf", "fairy", "genie", "vampire", "zombie", "skull", "ghost", "imp", "smiling_imp",
		"dragon", "dragon_face", "wolf", "bear", "boar", "horse", "unicorn", "owl", "eagle", "bat", "spider",
		"snake", "fish", "turtle", "sheep", "chicken", "cat", "dog", "pig",
		"fire", "zap", "snowflake", "droplet", "boom",
	} },
	{ label = "Smileys", names = {
		"smile", "grin", "smiley", "joy", "rofl", "sweat_smile", "laughing", "wink", "blush", "yum", "sunglasses",
		"heart_eyes", "kiss", "thinking", "neutral", "expressionless", "unamused", "roll_eyes", "smirk",
		"persevere", "disappointed", "worried", "angry", "rage", "cry", "sob", "scream", "flushed", "dizzy_face",
		"sleeping", "sleepy", "mask", "nerd", "clown", "cowboy", "partying", "pleading", "alien", "robot", "poop",
	} },
	{ label = "Hands", names = {
		"thumbsup", "thumbsdown", "ok_hand", "wave", "clap", "pray", "muscle", "fist", "v", "metal", "call_me",
		"point_up", "point_down", "point_left", "point_right", "raised_hand", "handshake", "crossed_fingers",
		"eyes", "brain",
	} },
	{ label = "Hearts", names = {
		"heart", "broken_heart", "orange_heart", "yellow_heart", "green_heart", "blue_heart", "purple_heart",
		"black_heart", "sparkling_heart", "two_hearts",
	} },
	{ label = "Things", names = {
		"star", "star2", "sparkles", "sunny", "moon", "cloud", "rainbow", "tada", "confetti", "balloon", "gift",
		"bell", "mega", "speech", "zzz", "anger", "question", "exclamation", "check", "x", "warning", "no_entry",
		"recycle", "hourglass", "wine", "cocktail", "coffee", "pizza", "burger", "meat", "croissant", "apple",
		"cake",
	} },
}

function Emoji.IndexOf(name)
	return indexByName[name]
end

-- Emoji whose name contains the query, in the same order as the tabs.
-- Spaces and underscores are ignored on both sides: "thumbs up" has to find "thumbsup".
function Emoji.Search(query)
	local needle = query:lower():gsub("[%s_]", "")
	local matches = {}
	for _, group in ipairs(Emoji.GROUPS) do
		for _, name in ipairs(group.names) do
			if (name:gsub("_", "")):find(needle, 1, true) then
				matches[#matches + 1] = name
			end
		end
	end
	return matches
end

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

-- gsub can't be used here: when ":30:" in "10:30:smile:" isn't an emoji, its
-- closing colon has to stay available to open the next shortcode.
local function RenderPlain(text)
	local output = {}
	local position = 1
	while true do
		local first, last, name = text:find(":([%w_+%-]+):", position)
		if not first then break end
		local tag = InlineTag(name)
		if tag then
			output[#output + 1] = text:sub(position, first - 1) .. tag
			position = last + 1
		else
			output[#output + 1] = text:sub(position, last - 1)
			position = last
		end
	end
	output[#output + 1] = text:sub(position)
	return table.concat(output)
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
