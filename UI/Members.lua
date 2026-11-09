local _, ns = ...
local L = ns.L

local Members = {}
ns.Members = Members

local PANEL_WIDTH = 200
local HEADER_HEIGHT = 26
local ROW_HEIGHT = 26
local CREST_SIZE = 20
local CREST_LEFT = 12
local TEXT_LEFT = CREST_LEFT + CREST_SIZE + 8
local DOT_SIZE = 10
local HEADER_LEFT = 12
local LIST_RIGHT_GAP = 8
local OFFLINE_ALPHA = 0.5
local REFRESH_DELAY = 0.25
local GUILD_REQUEST_INTERVAL = 10
local GUILD_STATUS_AFK = 1
local GUILD_STATUS_DND = 2
local MAX_PARTY_UNITS = 4
local MAX_RAID_UNITS = 40

-- The chat kinds that have a member list: guild and officer chat, and the group chats.
local GUILD_PREFIXES = { G = true, O = true }
local GROUP_PREFIXES = { P = true, R = true, I = true }

local panel, scrollBox
local lastGuildRequest

Members.PANEL_WIDTH = PANEL_WIDTH

local function PrefixOf(key)
	return key and key:sub(2, 2) == ":" and key:sub(1, 1) or nil
end

function Members.IsGuild(key)
	local prefix = PrefixOf(key)
	return prefix ~= nil and GUILD_PREFIXES[prefix] == true
end

function Members.Supports(key)
	local prefix = PrefixOf(key)
	return prefix ~= nil and (GUILD_PREFIXES[prefix] or GROUP_PREFIXES[prefix]) == true
end

-- Roster -------------------------------------------------------------------

local function GuildMembers()
	local list = {}
	for index = 1, GetNumGuildMembers() do
		-- name, rank, rankIndex, level, class, zone, note, officerNote, online, status, classFileName
		local name, rank, rankIndex, level, _, _, _, _, isOnline, status, classFile = GetGuildRosterInfo(index)
		-- Restricted values can't be shown or sorted, so such members are left out.
		if canaccessvalue(name) and canaccessvalue(isOnline) and name then
			local normalized = ns.Util.NormalizeName(name)
			if normalized then
				local readable = canaccessvalue(status)
				local afk = isOnline and readable and status == GUILD_STATUS_AFK
				local dnd = isOnline and readable and status == GUILD_STATUS_DND
				list[#list + 1] = {
					name = normalized,
					class = canaccessvalue(classFile) and classFile or nil,
					online = isOnline and true or false,
					status = (afk and "afk") or (dnd and "dnd") or nil,
					leader = canaccessvalue(rankIndex) and rankIndex == 0 or false,
					level = canaccessvalue(level) and level or nil,
					rank = canaccessvalue(rank) and rank or nil,
				}
			end
		end
	end
	return list
end

local function UnitMember(unit)
	if not UnitExists(unit) then return nil end
	-- This client splits a character's name into first name and surname.
	local first, surname = UnitName(unit)
	if not (canaccessvalue(first) and canaccessvalue(surname)) or not first then return nil end
	local name = ns.Util.NormalizeName(NameUtil.GetFullNameWithoutRealm(first, surname))
	if not name then return nil end

	local _, classFile = UnitClass(unit)
	local online = UnitIsConnected(unit) and true or false
	local afk = online and UnitIsAFK(unit)
	local dnd = online and UnitIsDND(unit)
	return {
		name = name,
		class = canaccessvalue(classFile) and classFile or nil,
		online = online,
		status = (afk and "afk") or (dnd and "dnd") or nil,
		leader = UnitIsGroupLeader(unit) and true or false,
		level = UnitLevel and UnitLevel(unit) or nil,
	}
end

local function GroupMembers()
	local units = {}
	if IsInRaid() then
		for index = 1, math.min(GetNumGroupMembers(), MAX_RAID_UNITS) do
			units[#units + 1] = "raid" .. index
		end
	else
		units[1] = "player"
		for index = 1, math.min(GetNumGroupMembers() - 1, MAX_PARTY_UNITS) do
			units[#units + 1] = "party" .. index
		end
	end

	local list, seen = {}, {}
	for _, unit in ipairs(units) do
		local member = UnitMember(unit)
		if member and not seen[member.name] then
			seen[member.name] = true
			list[#list + 1] = member
		end
	end
	return list
end

-- The chat's members, or nil for a chat without a member list. A guild chat of
-- another guild or character has no roster to show, so it is empty.
function Members.Roster(key)
	if not Members.Supports(key) then return nil end
	if Members.IsGuild(key) then
		local prefix = key:sub(1, 1)
		if key:sub(3) ~= ns.Identity.GuildKey(prefix):sub(3) then return {} end
		return GuildMembers()
	end
	return GroupMembers()
end

-- Online first, the leader first among them, then by name. Offline members follow.
local function Before(a, b)
	if a.online ~= b.online then return a.online end
	if a.leader ~= b.leader then return a.leader end
	local nameA, nameB = a.name:lower(), b.name:lower()
	if nameA ~= nameB then return nameA < nameB end
	return a.name < b.name
end

function Members.Sort(list)
	table.sort(list, Before)
	return list
end

-- "12 online", with the guild's size added for a guild: "12 online  ·  340 members".
function Members.CountText(list, showTotal)
	if not list or #list == 0 then return "" end
	local online = 0
	for _, member in ipairs(list) do
		if member.online then online = online + 1 end
	end
	local text = L["%d online"]:format(online)
	if showTotal then
		text = text .. "  ·  " .. L["%d members"]:format(#list)
	end
	return text
end

-- The header's count for a chat, or "" when there is nothing to count.
function Members.SubtitleCount(key)
	return Members.CountText(Members.Roster(key), Members.IsGuild(key))
end

-- What the tooltip says about a member besides the name.
function Members.DetailText(member)
	local parts = {}
	if member.level then parts[#parts + 1] = L["Level %d"]:format(member.level) end
	if member.rank then parts[#parts + 1] = member.rank end
	if member.leader and not member.rank then parts[#parts + 1] = L["Leader"] end
	if not member.online then parts[#parts + 1] = L["Offline"] end
	return table.concat(parts, "  ·  ")
end

-- Asks the server for fresh guild data, at most once per interval, because
-- every guild window and addon shares the same request.
function Members.RequestGuildRoster()
	local now = GetTime()
	if lastGuildRequest and now - lastGuildRequest < GUILD_REQUEST_INTERVAL then return false end
	lastGuildRequest = now
	C_GuildInfo.GuildRoster()
	return true
end

-- Rows --------------------------------------------------------------------

function Members.BuildElements(list)
	local elements = { { kind = "header", label = L["MEMBERS"] } }
	for _, member in ipairs(list or {}) do
		elements[#elements + 1] = { kind = "member", member = member }
	end
	return elements
end

local function ExtentOf(_, element)
	return element.kind == "header" and HEADER_HEIGHT or ROW_HEIGHT
end

local function OnRowClick(self)
	local element = self.element
	if element and element.kind == "member" then
		ns.PlayerMenu.Show(self, element.member.name, element.member.class)
	end
end

local function OnRowEnter(self)
	local element = self.element
	if not element or element.kind ~= "member" then return end
	self.hover:Show()
	local detail = Members.DetailText(element.member)
	if detail ~= "" then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.Util.DisplayName(element.member.name))
		GameTooltip:AddLine(detail, 1, 1, 1)
		GameTooltip:Show()
	end
end

local function OnRowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function BuildRow(frame)
	frame.hover = ns.Widgets.RoundedFill(frame, "hover")
	frame.hover:SetPoint("TOPLEFT", 4, -1)
	frame.hover:SetPoint("BOTTOMRIGHT", 0, 1)
	frame.hover:Hide()

	frame.crest = ns.Widgets.ClassCrest(frame, CREST_SIZE)
	frame.crest:SetPoint("LEFT", CREST_LEFT, 0)

	frame.dot = frame:CreateTexture(nil, "OVERLAY", nil, 1) -- above the crest's ring
	frame.dot:SetSize(DOT_SIZE, DOT_SIZE)
	frame.dot:SetPoint("CENTER", frame.crest, "BOTTOMRIGHT", -1, 1)

	frame.text = ns.Widgets.Text(frame, "HangoutFont", "text")
	frame.text:SetWordWrap(false)

	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnClick", OnRowClick)
	frame:SetScript("OnEnter", OnRowEnter)
	frame:SetScript("OnLeave", OnRowLeave)
end

local function InitRow(frame, element)
	if not frame.text then BuildRow(frame) end
	frame.element = element
	frame.hover:Hide()
	frame.text:ClearAllPoints()

	if element.kind == "header" then
		frame:EnableMouse(false)
		frame:SetAlpha(1)
		frame.crest:Hide()
		frame.crest.ring:Hide()
		frame.dot:Hide()
		frame.text:SetPoint("LEFT", HEADER_LEFT, 0)
		frame.text:SetPoint("RIGHT", -6, 0)
		ns.Widgets.SetTextFont(frame.text, "HangoutFontSmall")
		frame.text:SetTextColor(ns.Theme.Color("muted"))
		frame.text:SetText(element.label)
		return
	end

	local member = element.member
	-- A faded window must not catch clicks, as with the message rows.
	frame:EnableMouse(not ns.Window.IsFaded())
	frame:SetAlpha(member.online and 1 or OFFLINE_ALPHA)
	ns.Widgets.SetClassCrest(frame.crest, member.class)

	local status = member.online and (member.status or "online") or nil
	frame.dot:SetShown(status ~= nil)
	if status then frame.dot:SetTexture(ns.Widgets.STATUS_ICON[status]) end

	frame.text:SetPoint("LEFT", TEXT_LEFT, 0)
	frame.text:SetPoint("RIGHT", -6, 0)
	ns.Widgets.SetTextFont(frame.text, "HangoutFont")
	frame.text:SetTextColor(ns.Theme.ClassColor(member.class, "sidebar"))
	frame.text:SetText(ns.Util.DisplayName(member.name))
end

-- Redraws the list for the selected chat while the panel is showing.
function Members.Refresh()
	if not scrollBox or not panel:IsShown() then return end
	local list = Members.Roster(ns.selectedKey) or {}
	Members.Sort(list)
	scrollBox:SetDataProvider(CreateDataProvider(Members.BuildElements(list)), ScrollBoxConstants.RetainScrollPosition)
end

-- Builds the panel as a child of parent. The window anchors it.
function Members.Create(parent)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetWidth(PANEL_WIDTH)
	panel:Hide()
	ns.Widgets.Fill(panel, "sidebar")
	local edge = ns.Widgets.Solid(panel, "edge", "ARTWORK")
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")

	local view = CreateScrollBoxListLinearView(4, 8, 0, 0, 0)
	view:SetElementInitializer("Button", InitRow)
	view:SetElementExtentCalculator(ExtentOf)

	local scrollBar
	scrollBox, scrollBar = ns.Widgets.ScrollList(panel, view)
	scrollBar:SetPoint("TOPRIGHT", -2, 0)
	scrollBar:SetPoint("BOTTOMRIGHT", -2, 4)
	scrollBox:SetPoint("TOPLEFT", 1, 0)
	scrollBox:SetPoint("BOTTOMRIGHT", -LIST_RIGHT_GAP, 0)
	return panel
end

-- Events ------------------------------------------------------------------

-- Joins, leaves, status and connection changes arrive in bursts.
local changedSoon = ns.Util.Debounced(REFRESH_DELAY, function()
	local key = ns.selectedKey
	if not Members.Supports(key) then return end
	Members.Refresh()
	ns.Fire("ROSTER_CHANGED", key)
end)

local events = CreateFrame("Frame")
for _, event in ipairs({ "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function() changedSoon() end)

ns.On("SELECTION_CHANGED", function(key)
	if Members.IsGuild(key) then
		Members.RequestGuildRoster()
	end
end)
ns.On("THEME_CHANGED", function() Members.Refresh() end)
