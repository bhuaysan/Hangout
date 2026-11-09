local _, ns = ...

local Alerts = {}
ns.Alerts = Alerts

local MIN_SOUND_INTERVAL = 1.5

local SOUND_KITS = {
	ping = "MAP_PING",
	battlenet = "UI_BNET_TOAST",
	whisper = "TELL_MESSAGE",
	ready = "READY_CHECK",
}

local CHOICES = {
	{ value = "off", label = "Off" },
	{ value = "ping", label = "Ping" },
	{ value = "battlenet", label = "Battle.net" },
	{ value = "whisper", label = "Whisper" },
	{ value = "ready", label = "Ready check" },
}

-- The game already plays a whisper sound, so "default" means Hangout adds none.
local WHISPER_CHOICES = { { value = "default", label = "Game default" } }
for _, choice in ipairs(CHOICES) do
	WHISPER_CHOICES[#WHISPER_CHOICES + 1] = choice
end

local lastSoundAt = 0
local recoveryAlerted = false
local needles

function Alerts.SoundChoices(category)
	return category == "Whisper" and WHISPER_CHOICES or CHOICES
end

local function IsWordCharacter(character)
	return character ~= "" and (character:find("%w") ~= nil or character:byte() >= 128)
end

local function ContainsWord(text, word)
	local from = 1
	while true do
		local first, last = text:find(word, from, true)
		if not first then return false end
		if not IsWordCharacter(text:sub(first - 1, first - 1))
			and not IsWordCharacter(text:sub(last + 1, last + 1)) then
			return true
		end
		from = first + 1
	end
end

local function Needles()
	if not needles then
		needles = { ns.me:match("^(%S+)"):lower() }
		for _, keyword in ipairs(ns.Get("keywords") or {}) do
			needles[#needles + 1] = keyword
		end
	end
	return needles
end

-- True if text contains the player's first name or a keyword as a whole word.
-- Item and spell links are ignored, so a linked item can't trigger a mention.
function Alerts.IsMention(text)
	local plain = text:gsub("|c[^|]*|H.-|h.-|h|r", ""):gsub("|H.-|h.-|h", ""):lower()
	for _, word in ipairs(Needles()) do
		if ContainsWord(plain, word) then return true end
	end
	return false
end

function Alerts.AddKeyword(word)
	word = ns.Util.Trim(word):lower()
	if word == "" then return end
	local keywords = {}
	for _, existing in ipairs(ns.Get("keywords") or {}) do
		if existing == word then return end
		keywords[#keywords + 1] = existing
	end
	keywords[#keywords + 1] = word
	ns.Set("keywords", keywords)
	needles = nil
end

-- Replaces all keywords from comma-separated text.
function Alerts.SetKeywords(text)
	local keywords = ns.Util.ParseList(text)
	ns.Set("keywords", #keywords > 0 and keywords or nil)
	needles = nil
end

function Alerts.RemoveKeyword(word)
	word = ns.Util.Trim(word):lower()
	local keywords = {}
	for _, existing in ipairs(ns.Get("keywords") or {}) do
		if existing ~= word then keywords[#keywords + 1] = existing end
	end
	ns.Set("keywords", #keywords > 0 and keywords or nil)
	needles = nil
end

local function CategoryName(key, mention)
	if mention then return "Mention" end
	local category = ns.CategoryOf(key)
	if category == "whisper" or category == "live" then return "Whisper" end
	if category == "group" then return "Group" end
	return nil -- public channels only alert on mentions
end

-- Returns what this message should do, or nil if it should stay silent.
-- Unread badges are separate and are never affected by this.
function Alerts.Decide(key, conv, mention)
	if conv.req then return nil end
	if conv.mute and not mention then return nil end
	if ns.Get("dnd") then return nil end
	-- Automatic quiet mode is silent like Do Not Disturb, badges still count.
	if ns.Quiet.IsActive() then return nil end
	if key == ns.activeKey then return nil end

	local category = CategoryName(key, mention)
	if not category then return nil end

	-- A whisper hidden from normal chat doesn't play the game's sound either.
	local sound = ns.Get("sound" .. category)
	if sound == "default" and ns.Get("hideWhispers") then
		sound = "whisper"
	end

	return {
		sound = sound,
		toast = ns.Get("toast" .. category) and not InCombatLockdown(),
		flash = ns.Get("flash" .. category),
		isWhisper = category == "Whisper",
	}
end

local function PlayChoice(choice)
	local kit = SOUND_KITS[choice]
	if kit then
		PlaySound(SOUNDKIT[kit], "Master")
	end
end

function Alerts.Preview(choice)
	PlayChoice(choice)
end

-- Whispers go to the glance strip, and only while Hangout is closed.
local function ShowPopup(key, conv, record, isWhisper)
	if not isWhisper then
		ns.Toast.Show(key, conv, record)
	elseif not ns.Window.IsVisible() then
		ns.Glance.Show(key, conv, record)
	end
end

local function PlayThrottled(choice)
	if not SOUND_KITS[choice] then return end -- silent choices must not start the throttle
	local now = GetTime()
	if now - lastSoundAt < MIN_SOUND_INTERVAL then return end
	lastSoundAt = now
	PlayChoice(choice)
end

-- Plays whatever this message should do. A popup needs a readable record.
-- Returns true if the message was allowed to alert.
local function Alert(key, mention, record)
	local conv = ns.Store.Get(key)
	local decision = conv and Alerts.Decide(key, conv, mention)
	if not decision then return false end

	if decision.sound then PlayThrottled(decision.sound) end
	if decision.flash then FlashClientIcon() end
	if decision.toast and record then ShowPopup(key, conv, record, decision.isWhisper) end
	return true
end

local function OnMessage(key, record, mention, recovered)
	if record.o == 1 then return end
	-- Recovered lines already alerted while locked, but a locked line can't be
	-- recognized as a mention. Those get one alert per recovery.
	if recovered and (not mention or recoveryAlerted) then return end
	if Alert(key, mention, record) and recovered then
		recoveryAlerted = true
	end
end

-- Locked messages can't be read, so they get no toast and can't be mentions.
local function OnLocked(key, element)
	if element.o ~= 1 then Alert(key, false) end
end

ns.On("MESSAGE_ADDED", OnMessage)
ns.On("LOCKED_ADDED", OnLocked)
ns.On("LIVE_CHANGED", function() recoveryAlerted = false end)
