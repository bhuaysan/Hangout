local _, ns = ...

local Identity = {}
ns.Identity = Identity

local PRESENCE_DELAY = 1
local ROSTER_REQUEST_INTERVAL = 60
local GUILD_STATUS_AFK = 1
local GUILD_STATUS_DND = 2

-- Session-only: Battle.net account IDs change between sessions.
local accountIdByTag = {}
local statusByName = {}
local statusByTag = {}
local gameAccountByTag = {}
local tagByGameAccount = {}
-- Kept across rescans, so a friend who logs off keeps their last class.
local classByTag = {}

-- Any status flag can be secret during a chat restriction.
local function IsSet(flag)
	return canaccessvalue(flag) and flag and true or false
end

local function StatusFrom(isOnline, isAfk, isDnd)
	if not isOnline then return "offline" end
	if isAfk then return "afk" end
	if isDnd then return "dnd" end
	return "online"
end

-- Addon data only reaches friends currently playing this same game.
local function RememberGameAccount(tag, game)
	local id = game.gameAccountID
	if not canaccessvalue(id) or not canaccessvalue(game.clientProgram)
		or not canaccessvalue(game.wowProjectID) then
		return
	end
	if game.isOnline and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID then
		gameAccountByTag[tag] = id
		tagByGameAccount[id] = tag
	end
end

-- Returns the class of the character a friend is playing, or nil outside WoW.
local function ClassOfGame(game)
	if not canaccessvalue(game.clientProgram) or game.clientProgram ~= BNET_CLIENT_WOW then
		return nil
	end
	local token = canaccessvalue(game.classFilename) and game.classFilename or nil
	if not token and canaccessvalue(game.classID) and game.classID then
		token = select(2, GetClassInfo(game.classID))
	end
	return token and CLASS_ICON_TCOORDS[token] and token or nil
end

local function RememberClass(tag, game)
	local class = ClassOfGame(game)
	if not class then return end
	classByTag[tag] = class
	local conv = ns.Store.Get("B:" .. tag)
	if conv then conv.class = class end
end

local function ScanBattleNet()
	for index = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(index)
		if info and canaccessvalue(info.battleTag) and info.battleTag then
			accountIdByTag[info.battleTag] = info.bnetAccountID
			local game = info.gameAccountInfo
			if game and canaccessvalue(game.isOnline) then
				statusByTag[info.battleTag] = StatusFrom(game.isOnline,
					IsSet(info.isAFK) or IsSet(game.isGameAFK),
					IsSet(info.isDND) or IsSet(game.isGameBusy))
				RememberGameAccount(info.battleTag, game)
				RememberClass(info.battleTag, game)
			end
		end
	end
end

local function ScanGuild()
	for index = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline, status = GetGuildRosterInfo(index)
		if canaccessvalue(name) and canaccessvalue(isOnline) then
			local normalized = ns.Util.NormalizeName(name)
			if normalized then
				local readable = canaccessvalue(status)
				statusByName[normalized] = StatusFrom(isOnline,
					readable and status == GUILD_STATUS_AFK,
					readable and status == GUILD_STATUS_DND)
			end
		end
	end
end

local function ScanFriends()
	for index = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(index)
		if info and canaccessvalue(info.name) and canaccessvalue(info.connected) then
			local normalized = ns.Util.NormalizeName(info.name)
			if normalized then
				statusByName[normalized] = StatusFrom(info.connected, IsSet(info.afk), IsSet(info.dnd))
			end
		end
	end
end

local function RebuildPresence()
	statusByName = {}
	statusByTag = {}
	gameAccountByTag = {}
	tagByGameAccount = {}
	ScanGuild()
	ScanFriends()
	ScanBattleNet()
	ns.Fire("PRESENCE_CHANGED")
	ns.Fire("CONV_CHANGED")
end

function Identity.Init()
	-- UnitName returns first name and surname on Forever.
	ns.me = ns.Util.NormalizeName(NameUtil.GetFullNameWithoutRealm(UnitName("player")))
	ns.myClass = select(2, UnitClass("player"))

	local rebuildSoon = ns.Util.Debounced(PRESENCE_DELAY, RebuildPresence)
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("FRIENDLIST_UPDATE")
	frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	frame:RegisterEvent("BN_CONNECTED")
	frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
	frame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
	frame:SetScript("OnEvent", rebuildSoon)

	C_FriendList.ShowFriends()
	C_GuildInfo.GuildRoster()
	C_Timer.NewTicker(ROSTER_REQUEST_INTERVAL, function()
		C_FriendList.ShowFriends()
		C_GuildInfo.GuildRoster()
	end)
	rebuildSoon()
end

-- Returns "online", "afk", "dnd" or "offline", or nil for people Hangout has
-- no information about.
function Identity.Status(key)
	local prefix = key:sub(1, 1)
	if prefix == "W" then
		return statusByName[key:sub(3)]
	elseif prefix == "B" then
		return statusByTag[key:sub(3)]
	end
	return nil
end

-- Returns true or false, or nil for people Hangout has no information about.
function Identity.Presence(key)
	local status = Identity.Status(key)
	if status == nil then return nil end
	return status ~= "offline"
end

function Identity.ClassForTag(tag)
	return classByTag[tag]
end

function Identity.GameAccountForTag(tag)
	return gameAccountByTag[tag]
end

function Identity.TagForGameAccount(gameAccountID)
	return tagByGameAccount[gameAccountID]
end

-- True for people the player has a real connection to: friends, guild, group.
function Identity.IsKnown(name, guid)
	if name == ns.me or statusByName[name] ~= nil then return true end
	if guid and guid ~= "" and (C_FriendList.IsFriend(guid) or IsGuildMember(guid)) then
		return true
	end
	return (UnitInParty(name) or UnitInRaid(name)) and true or false
end

-- Returns the BattleTag for an account ID and remembers the ID for this session.
-- The account's real name is deliberately never read or stored.
function Identity.BattleTag(bnetAccountID)
	local info = C_BattleNet.GetAccountInfoByID(bnetAccountID)
	local tag = info and info.battleTag
	if not canaccessvalue(tag) or not tag or tag == "" then
		return nil
	end
	accountIdByTag[tag] = bnetAccountID
	return tag
end

function Identity.AccountIdForTag(tag)
	if not accountIdByTag[tag] then
		ScanBattleNet()
	end
	return accountIdByTag[tag]
end

-- Returns the English class token for a readable GUID, or nil.
function Identity.ClassFromGUID(guid)
	if not guid or guid == "" then return nil end
	local _, classToken = GetPlayerInfoByGUID(guid)
	if canaccessvalue(classToken) and classToken then
		return classToken
	end
	return nil
end

-- The store is account-wide, so guild history is keyed by guild and realm.
-- Before guild data arrives this returns a memory-only key.
function Identity.GuildKey(prefix)
	local guildName = GetGuildInfo("player")
	-- The realm name can still be nil shortly after login.
	local realm = GetNormalizedRealmName()
	if canaccessvalue(guildName) and guildName and canaccessvalue(realm) and realm then
		return prefix .. ":" .. guildName .. "-" .. realm
	end
	return prefix .. ":?"
end
