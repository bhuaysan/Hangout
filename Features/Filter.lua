local _, ns = ...

local Filter = {}
ns.Filter = Filter

local WHISPER_EVENTS = {
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
}

local MAX_REMEMBERED_REPEATS = 2000

local applied = false
local blockedCount = 0
local lastSeen = {}
local rememberedRepeats = 0

local function ContainsAny(lowerText, words)
	for _, word in ipairs(words) do
		if lowerText:find(word, 1, true) then return true end
	end
	return false
end

local function WordList(settingKey)
	return ns.Get(settingKey) or {}
end

local function IsPlayerBlocked(name)
	local lowerName = name:lower()
	for _, blocked in ipairs(WordList("blockedPlayers")) do
		if blocked == lowerName then return true end
	end
	return false
end

function Filter.BlocksWhisper(name, text, isStranger)
	if IsPlayerBlocked(name) then return true end
	return isStranger and ContainsAny(text:lower(), WordList("blockWords"))
end

local function IsRepeat(name, lowerText, now)
	local window = ns.Get("channelRepeatSeconds")
	if window <= 0 then return false end

	local key = name .. "\0" .. lowerText
	local previous = lastSeen[key]
	if not previous then
		rememberedRepeats = rememberedRepeats + 1
		if rememberedRepeats > MAX_REMEMBERED_REPEATS then
			lastSeen = {}
			rememberedRepeats = 1
		end
	end
	lastSeen[key] = now
	return previous ~= nil and now - previous < window
end

-- Plain text matching only: rules are never treated as Lua patterns.
function Filter.BlocksChannel(name, text, now)
	if IsPlayerBlocked(name) then return true end
	local lowerText = text:lower()
	if ContainsAny(lowerText, WordList("blockWords"))
		or ContainsAny(lowerText, WordList("channelHideWords")) then
		return true
	end

	local onlyWords = WordList("channelOnlyWords")
	if #onlyWords > 0 and not ContainsAny(lowerText, onlyWords) then return true end

	return IsRepeat(name, lowerText, now)
end

function Filter.CountBlocked()
	blockedCount = blockedCount + 1
end

function Filter.BlockedCount()
	return blockedCount
end

-- Replaces a rule list from comma-separated text.
function Filter.SetList(settingKey, text)
	local list = ns.Util.ParseList(text)
	if settingKey == "blockedPlayers" then
		for index, entry in ipairs(list) do
			list[index] = ns.Util.NormalizeName(entry) or entry
		end
	end
	ns.Set(settingKey, #list > 0 and list or nil)
end

function Filter.BlockPlayer(name)
	local list = {}
	local lowerName = name:lower()
	for _, blocked in ipairs(WordList("blockedPlayers")) do
		if blocked ~= lowerName then list[#list + 1] = blocked end
	end
	list[#list + 1] = lowerName
	ns.Set("blockedPlayers", list)
end

-- Game Master whispers must always stay visible in normal chat. The game skips
-- this filter for restricted messages, so those stay visible as well.
-- The default chat frame records the reply target only after the filters pass,
-- so a hidden whisper has to set it here or /r would have no one to answer.
local function HideWhisper(_, event, _, playerName, _, _, _, specialFlags)
	if specialFlags == "GM" then return false end
	if (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
		and canaccessvalue(playerName) and type(playerName) == "string" and playerName ~= "" then
		ChatFrameUtil.SetLastTellTarget(playerName, event:sub(10))
	end
	return true
end

Filter.HideWhisper = HideWhisper

function Filter.Apply()
	local wanted = ns.Get("hideWhispers")
	if wanted == applied then return end
	applied = wanted

	local change = wanted and ChatFrameUtil.AddMessageEventFilter or ChatFrameUtil.RemoveMessageEventFilter
	for _, event in ipairs(WHISPER_EVENTS) do
		change(event, HideWhisper)
	end
end
