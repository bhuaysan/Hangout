local _, ns = ...

local DB = {}
ns.DB = DB

DB.SCHEMA = 3

-- [n] upgrades a database from schema n to n + 1
DB.migrations = {
	-- Schema 1 only existed during early testing and treated surnames as realms.
	[1] = function(db)
		db.conv = {}
		db.chars = {}
	end,
	-- Schema 2 could hold results from a temporary diagnostic.
	[2] = function(db)
		db.debug = nil
	end,
}

local SECONDS_PER_DAY = 86400

local function NewDatabase()
	return {
		schema = DB.SCHEMA,
		settings = {},
		theme = { custom = {} },
		chars = {},
		conv = {},
	}
end

function DB.Init()
	ns.session = { conv = {}, live = {}, liveUnread = {} }
	ns.charIndex = 0

	if HangoutDB == nil then
		HangoutDB = NewDatabase()
	elseif type(HangoutDB) ~= "table" or type(HangoutDB.schema) ~= "number" then
		HangoutDB = NewDatabase()
		ns.Print("Your saved history couldn't be read and was reset.")
	end

	if HangoutDB.schema > DB.SCHEMA then
		-- Saved by a newer Hangout. Leave it untouched and run from memory.
		ns.readOnly = true
		ns.db = NewDatabase()
		ns.Print("Your saved history is from a newer version. It won't be changed, and this session won't be saved.")
		return
	end

	for version = HangoutDB.schema, DB.SCHEMA - 1 do
		DB.migrations[version](HangoutDB)
		HangoutDB.schema = version + 1
	end
	-- Migrations don't create these, so a damaged save could lack them.
	for _, field in ipairs({ "settings", "theme", "chars", "conv" }) do
		if type(HangoutDB[field]) ~= "table" then HangoutDB[field] = {} end
	end
	if type(HangoutDB.theme.custom) ~= "table" then HangoutDB.theme.custom = {} end
	ns.db = HangoutDB
end

function DB.RegisterCharacter(fullName)
	local chars = ns.db.chars
	for i = 1, #chars do
		if chars[i] == fullName then
			ns.charIndex = i
			return
		end
	end
	chars[#chars + 1] = fullName
	ns.charIndex = #chars
end

local function HasUserData(conv)
	return conv.pin or conv.mute or conv.nick or conv.note or (conv.draft and conv.draft ~= "")
end

local function RetentionSeconds(key)
	local category = ns.CategoryOf(key)
	local days
	if category == "whisper" then
		days = ns.Get("retentionWhisperDays")
	elseif category == "group" then
		days = ns.Get("retentionGroupDays")
	else
		days = ns.Get("retentionChannelDays")
	end
	return days * SECONDS_PER_DAY
end

-- Keeps messages for which keep(message) is true, preserving order.
-- Returns the number removed.
local function Filter(messages, keep)
	local write = 0
	local count = #messages
	for read = 1, count do
		local message = messages[read]
		if keep(message) then
			write = write + 1
			messages[write] = message
		end
	end
	for i = write + 1, count do
		messages[i] = nil
	end
	return count - write
end

local function PruneByAgeAndChatCap(key, conv, now)
	local messages = conv.m
	if not conv.pin then
		local cutoff = now - RetentionSeconds(key)
		Filter(messages, function(message) return message.t >= cutoff end)
	end

	local excess = #messages - ns.Get("perChatCap")
	if excess > 0 then
		local position = 0
		Filter(messages, function()
			position = position + 1
			return position > excess
		end)
	end
end

-- Eviction order when over the global cap: group and channel history first,
-- then whispers, and pinned chats only as a last resort.
local function EvictionTier(key, conv)
	if conv.pin then return 3 end
	if ns.CategoryOf(key) == "whisper" then return 2 end
	return 1
end

local function EvictTier(tier, excess)
	local times = {}
	for key, conv in pairs(ns.db.conv) do
		if EvictionTier(key, conv) == tier then
			for i = 1, #conv.m do
				times[#times + 1] = conv.m[i].t
			end
		end
	end
	if #times == 0 then return 0 end

	table.sort(times)
	local cutoff = times[math.min(excess, #times)]
	local removed = 0
	for key, conv in pairs(ns.db.conv) do
		if EvictionTier(key, conv) == tier then
			removed = removed + Filter(conv.m, function(message) return message.t > cutoff end)
		end
	end
	return removed
end

local function CountMessages()
	local total = 0
	for _, conv in pairs(ns.db.conv) do
		total = total + #conv.m
	end
	return total
end

function DB.Prune(now)
	if ns.readOnly then return end

	for key, conv in pairs(ns.db.conv) do
		PruneByAgeAndChatCap(key, conv, now)
	end

	local excess = CountMessages() - ns.Get("globalCap")
	for tier = 1, 3 do
		if excess <= 0 then break end
		excess = excess - EvictTier(tier, excess)
	end

	for key, conv in pairs(ns.db.conv) do
		if #conv.m == 0 and not HasUserData(conv) then
			ns.db.conv[key] = nil
		end
	end
end
