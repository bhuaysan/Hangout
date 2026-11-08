-- Minimal WoW API stubs for running Hangout's logic under LuaJIT (Lua 5.1 semantics).

local stubs = {}

-- A stand-in for a secret value. It traps length, indexing and arithmetic.
-- Lua can't trap truthiness or comparison with a string, so review of
-- Core/Capture.lua is still required for those.
local secretMeta = {}
local function trap() error("illegal operation on a secret value", 2) end
secretMeta.__len = trap
secretMeta.__index = trap
secretMeta.__newindex = trap
secretMeta.__add = trap
secretMeta.__sub = trap
secretMeta.__lt = trap
secretMeta.__le = trap
secretMeta.__concat = function() return setmetatable({}, secretMeta) end
secretMeta.__tostring = trap

function stubs.Secret()
	return setmetatable({}, secretMeta)
end

local function IsSecret(value)
	return getmetatable(value) == secretMeta
end

local SECONDS_PER_DAY = 86400

-- A widget stand-in: any method call succeeds and returns another stand-in.
local tolerantMeta = {}
local function Tolerant()
	return setmetatable({}, tolerantMeta)
end
tolerantMeta.__index = function()
	return function() return Tolerant() end
end
stubs.Tolerant = Tolerant

function stubs.Install()
	stubs.serverTime = 1000000
	stubs.lockdown = false
	stubs.printed = {}
	stubs.frames = {}
	stubs.sent = {}
	stubs.bnetSent = {}
	stubs.chatLines = {}
	stubs.inCombat = false
	stubs.addonSent = {}
	stubs.gameDataSent = {}
	stubs.addonResult = 0
	stubs.allStrangers = false
	stubs.profileMs = 0
	stubs.time = 1000
	stubs.played = {}
	stubs.flashes = 0
	stubs.friends = {}
	stubs.guildRoster = {}
	stubs.guildName = "Horde Heroes"
	stubs.channels = {}
	stubs.bnetTags = { [77] = "Friend#1234" }
	stubs.bnetFriends = { { battleTag = "Pal#5678", bnetAccountID = 55 } }

	_G.canaccessvalue = function(value) return not IsSecret(value) end
	_G.issecretvalue = IsSecret
	_G.GetServerTime = function() return stubs.serverTime end
	_G.GetNormalizedRealmName = function() return "Thunderstrike" end
	_G.UnitName = function() return "Me", "Self" end
	_G.NameUtil = {
		GetFullNameWithoutRealm = function(first, surname)
			return surname and (first .. " " .. surname) or first
		end,
	}
	_G.BNET_CLIENT_WOW = "WoW"
	_G.WOW_PROJECT_ID = 1
	_G.Enum = { SendAddonMessageResult = { Success = 0 } }
	_G.UnitInParty = function() return not stubs.allStrangers end
	_G.UnitInRaid = function() return false end
	_G.IsGuildMember = function() return false end
	_G.debugprofilestop = function() return stubs.profileMs end
	_G.UnitClass = function() return "Shaman", "SHAMAN" end
	_G.InCombatLockdown = function() return stubs.inCombat end
	_G.GetTime = function() return stubs.time end
	_G.PlaySound = function(kit) stubs.played[#stubs.played + 1] = kit end
	_G.FlashClientIcon = function() stubs.flashes = stubs.flashes + 1 end
	_G.SOUNDKIT = { MAP_PING = 1, UI_BNET_TOAST = 2, TELL_MESSAGE = 3, READY_CHECK = 4 }
	_G.Minimap = Tolerant()
	_G.Minimap.GetWidth = function() return 140 end
	_G.UIParent = Tolerant()
	_G.CreateFont = function() return Tolerant() end
	_G.ChatFontNormal = { GetFont = function() return "font.ttf", 14, "" end }
	_G.Settings = Tolerant()
	_G.ScrollBoxConstants = {}
	stubs.chatFilters = {}
	_G.ChatFrameUtil = {
		AddMessageEventFilter = function(event, filter) stubs.chatFilters[event] = filter end,
		RemoveMessageEventFilter = function(event) stubs.chatFilters[event] = nil end,
	}
	_G.C_FriendList = {
		ShowFriends = function() end,
		IsFriend = function() return false end,
		GetNumFriends = function() return #stubs.friends end,
		GetFriendInfoByIndex = function(index) return stubs.friends[index] end,
	}
	_G.C_GuildInfo = { GuildRoster = function() end }
	_G.GetNumGuildMembers = function() return #stubs.guildRoster end
	_G.GetGuildRosterInfo = function(index)
		local member = stubs.guildRoster[index]
		return member.name, nil, nil, nil, nil, nil, nil, nil, member.online
	end
	_G.GetGuildInfo = function() return stubs.guildName end
	_G.GetChannelName = function(index)
		local name = stubs.channels[index]
		if name then return index, name end
		return 0, nil
	end
	_G.GetPlayerInfoByGUID = function(guid)
		if guid == "Player-1-ABC" then return "Shaman", "SHAMAN" end
	end
	_G.BNGetNumFriends = function() return #stubs.bnetFriends end
	_G.print = function(text) stubs.printed[#stubs.printed + 1] = text end
	_G.date = function(format, time)
		if format == "%Y-%m-%d" then
			return "day" .. math.floor((time or 0) / SECONDS_PER_DAY)
		end
		return "12:00"
	end
	_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	_G.C_ChatInfo = {
		InChatMessagingLockdown = function() return stubs.lockdown end,
		ReplaceIconAndGroupExpressions = function(text) return text end,
		RegisterAddonMessagePrefix = function() end,
		SendAddonMessage = function(prefix, text, channel, target)
			stubs.addonSent[#stubs.addonSent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
			return stubs.addonResult
		end,
		IsValidChatLine = function(id) return stubs.chatLines[id] ~= nil end,
		GetChatLineText = function(id) return stubs.chatLines[id].text end,
		GetChatLineSenderName = function(id) return stubs.chatLines[id].name end,
		GetChatLineSenderGUID = function(id) return stubs.chatLines[id].guid end,
		SendChatMessage = function(text, chatType, language, target)
			stubs.sent[#stubs.sent + 1] = { text = text, chatType = chatType, target = target }
		end,
	}
	_G.C_BattleNet = {
		GetAccountInfoByID = function(id)
			local tag = stubs.bnetTags[id]
			return tag and { battleTag = tag, accountName = "Real Name" } or nil
		end,
		GetFriendAccountInfo = function(index) return stubs.bnetFriends[index] end,
		SendGameData = function(id, prefix, text)
			stubs.gameDataSent[#stubs.gameDataSent + 1] = { id = id, prefix = prefix, text = text }
		end,
		SendWhisper = function(id, text)
			stubs.bnetSent[#stubs.bnetSent + 1] = { id = id, text = text }
		end,
	}
	_G.C_Timer = {
		After = function(_, callback) callback() end,
		NewTicker = function() end,
		NewTimer = function() return { Cancel = function() end } end,
	}
	_G.RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
	_G.SlashCmdList = {}
	_G.HangoutDB = nil
	_G.CreateFrame = function()
		local frame = Tolerant()
		rawset(frame, "events", {})
		rawset(frame, "RegisterEvent", function(self, event) self.events[event] = true end)
		rawset(frame, "UnregisterEvent", function(self, event) self.events[event] = nil end)
		rawset(frame, "SetScript", function(self, name, handler) rawset(self, name, handler) end)
		rawset(frame, "GetFrameLevel", function() return 1 end)
		stubs.frames[#stubs.frames + 1] = frame
		return frame
	end
end

return stubs
