local _, ns = ...

local Identity = {}
ns.Identity = Identity

local PRESENCE_DELAY = 1
local GUILD_REQUEST_INTERVAL = 60

-- Session-only: Battle.net account IDs change between sessions.
local accountIdByTag = {}
local onlineByName = {}
local onlineByTag = {}
local gameAccountByTag = {}
local tagByGameAccount = {}

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

local function ScanBattleNet()
	for index = 1, BNGetNumFriends() do
		local info = C_BattleNet.GetFriendAccountInfo(index)
		if info and info.battleTag and canaccessvalue(info.battleTag) then
			accountIdByTag[info.battleTag] = info.bnetAccountID
			local game = info.gameAccountInfo
			if game and canaccessvalue(game.isOnline) then
				onlineByTag[info.battleTag] = game.isOnline
				RememberGameAccount(info.battleTag, game)
			end
		end
	end
end

local function ScanGuild()
	for index = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(index)
		if name and canaccessvalue(name) and canaccessvalue(isOnline) then
			onlineByName[ns.Util.NormalizeName(name)] = isOnline and true or false
		end
	end
end

local function ScanFriends()
	for index = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(index)
		if info and canaccessvalue(info.name) and canaccessvalue(info.connected) then
			onlineByName[ns.Util.NormalizeName(info.name)] = info.connected
		end
	end
end

local function RebuildPresence()
	onlineByName = {}
	onlineByTag = {}
	gameAccountByTag = {}
	tagByGameAccount = {}
	ScanGuild()
	ScanFriends()
	ScanBattleNet()
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
	C_Timer.NewTicker(GUILD_REQUEST_INTERVAL, function() C_GuildInfo.GuildRoster() end)
	rebuildSoon()
end

-- Returns true or false, or nil for people Hangout has no information about.
function Identity.Presence(key)
	local prefix = key:sub(1, 1)
	if prefix == "W" then
		return onlineByName[key:sub(3)]
	elseif prefix == "B" then
		return onlineByTag[key:sub(3)]
	end
	return nil
end

function Identity.GameAccountForTag(tag)
	return gameAccountByTag[tag]
end

function Identity.TagForGameAccount(gameAccountID)
	return tagByGameAccount[gameAccountID]
end

-- True for people the player has a real connection to: friends, guild, group.
function Identity.IsKnown(name, guid)
	if name == ns.me or onlineByName[name] ~= nil then return true end
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
	if not tag or tag == "" or not canaccessvalue(tag) then
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
	if classToken and canaccessvalue(classToken) then
		return classToken
	end
	return nil
end

-- The store is account-wide, so guild history is keyed by guild and realm.
-- Before guild data arrives this returns a memory-only key.
function Identity.GuildKey(prefix)
	local guildName = GetGuildInfo("player")
	if guildName and canaccessvalue(guildName) then
		return prefix .. ":" .. guildName .. "-" .. GetNormalizedRealmName()
	end
	return prefix .. ":?"
end
