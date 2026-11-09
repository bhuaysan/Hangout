local _, ns = ...

ns.Defaults = {
	retentionWhisperDays = 90,
	retentionGroupDays = 14,
	retentionChannelDays = 14, -- only applies to channels opted in to saving
	perChatCap = 500,
	globalCap = 12000,
	sessionRing = 200,
	combatMode = "fade", -- "fade", "hide" or "off"
	combatOpacity = 20,
	moveFade = true,
	moveFadeOpacity = 40,
	showNearby = true,
	messageSize = 14,
	windowOpacity = 97,
	hideWhispers = false,
	showMinimap = true,
	sidebarCollapsed = false,
	showMembers = false,
	minimapAngle = 215,
	requestsEnabled = true,
	sendTyping = true,
	sendReadReceipts = true,
	channelRepeatSeconds = 60,
	dnd = false,
	quietInInstance = false,
	quietInRaidCombat = false,
	soundWhisper = "default",
	soundGroup = "off",
	soundMention = "ping",
	toastWhisper = true,
	toastGroup = false,
	toastMention = true,
	flashWhisper = true,
	flashGroup = false,
	flashMention = true,
}

-- Only values that differ from the defaults are written to saved data.
function ns.Get(key)
	local value = ns.db.settings[key]
	if value == nil then
		return ns.Defaults[key]
	end
	return value
end

function ns.Set(key, value)
	if value == ns.Defaults[key] then
		value = nil
	end
	ns.db.settings[key] = value
end

local CATEGORY_BY_PREFIX = {
	W = "whisper",
	B = "whisper",
	G = "group",
	O = "group",
	P = "group",
	R = "group",
	I = "group",
	C = "channel",
	L = "live",
	N = "nearby",
}

function ns.CategoryOf(key)
	return CATEGORY_BY_PREFIX[key:sub(1, 1)]
end
