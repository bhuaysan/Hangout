local _, ns = ...

local ProfileBar = {}
ns.ProfileBar = ProfileBar

ProfileBar.HEIGHT = 54

local CREST_SIZE = 30
local CREST_LEFT = 14
local TEXT_LEFT = CREST_LEFT + CREST_SIZE + 10
local BUTTON_SIZE = 28
local ICON_SIZE = 17
local STATUSES = {
	online = { label = "Online", icon = "Interface\\FriendsFrame\\StatusIcon-Online" },
	afk = { label = "AFK", icon = "Interface\\FriendsFrame\\StatusIcon-Away" },
	dnd = { label = "Do Not Disturb", icon = "Interface\\FriendsFrame\\StatusIcon-DnD" },
}
local STATUS_ORDER = { "online", "afk", "dnd" }

local bar, crest, statusDot, nameText, statusText, statusButton, settingsButton

-- Both flags can be secret during a chat restriction.
local function ReadFlag(flag)
	return canaccessvalue(flag) and flag and true or false
end

local function IsGameAfk()
	return ReadFlag(UnitIsAFK("player"))
end

local function IsGameDnd()
	return ReadFlag(UnitIsDND("player"))
end

-- The saved value keeps alerts silent even while the game's flag can't be read.
function ProfileBar.CurrentStatus()
	if ns.Get("dnd") then return "dnd" end
	if IsGameAfk() then return "afk" end
	return "online"
end

-- Empty messages of these types toggle the status, just as /afk and /dnd do.
-- Whatever is being turned off goes first, so the order suits the server.
local function ApplyGameStatus(wantAfk, wantDnd)
	if ns.Lockdown.IsActive() then
		ns.Print("Chat is restricted right now, so your game status can't change. Use /afk or /dnd in normal chat.")
		return
	end
	local afk, dnd = IsGameAfk(), IsGameDnd()
	if afk and not wantAfk then C_ChatInfo.SendChatMessage("", "AFK") end
	if dnd and not wantDnd then C_ChatInfo.SendChatMessage("", "DND") end
	if wantAfk and not afk then C_ChatInfo.SendChatMessage("", "AFK") end
	if wantDnd and not dnd then C_ChatInfo.SendChatMessage("", "DND") end
end

function ProfileBar.SetStatus(status)
	ns.Launcher.ApplyDnd(status == "dnd")
	ApplyGameStatus(status == "afk", status == "dnd")
end

-- Picks up /dnd typed in chat. The game's flag is the truth whenever it's readable.
function ProfileBar.SyncFromGame()
	local flag = UnitIsDND("player")
	if canaccessvalue(flag) then
		ns.Launcher.ApplyDnd(flag and true or false)
	end
end

local function Refresh()
	if not bar then return end
	local status = STATUSES[ProfileBar.CurrentStatus()]
	ns.Widgets.SetClassCrest(crest, ns.myClass)
	statusDot:SetTexture(status.icon)
	nameText:SetText(ns.Util.DisplayName(ns.me or ""))
	nameText:SetTextColor(ns.Theme.ClassColor(ns.myClass, "sidebar", "dock"))
	statusText:SetText(status.label)
end

local function ShowStatusMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Status")
		for _, status in ipairs(STATUS_ORDER) do
			root:CreateRadio(STATUSES[status].label,
				function() return ProfileBar.CurrentStatus() == status end,
				function() ProfileBar.SetStatus(status) end)
		end
	end)
end

local function AnchorStatusButton(isCollapsed)
	statusButton:ClearAllPoints()
	statusButton:SetPoint("TOPLEFT", isCollapsed and 4 or 8, -4)
	if isCollapsed then
		statusButton:SetPoint("BOTTOMRIGHT", -4, 4)
	else
		statusButton:SetPoint("BOTTOMRIGHT", settingsButton, "BOTTOMLEFT", -4, -9)
	end
end

local function CreateStatusButton()
	statusButton = CreateFrame("Button", nil, bar)
	statusButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = ns.Widgets.RoundedFill(statusButton, "hover")
	hover:SetAllPoints()
	hover:Hide()
	statusButton:SetScript("OnEnter", function(self)
		hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Change your status")
		GameTooltip:Show()
	end)
	statusButton:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	statusButton:SetScript("OnClick", ShowStatusMenu)
	AnchorStatusButton(false)
end

function ProfileBar.Create(parent)
	bar = CreateFrame("Frame", nil, parent)
	bar:SetPoint("BOTTOMLEFT")
	bar:SetPoint("BOTTOMRIGHT")
	bar:SetHeight(ProfileBar.HEIGHT)
	ns.Widgets.RoundedFill(bar, "dock", nil, "bottomLeft"):SetAllPoints()

	crest = ns.Widgets.ClassCrest(bar, CREST_SIZE)
	crest:SetPoint("LEFT", CREST_LEFT, 0)

	statusDot = bar:CreateTexture(nil, "OVERLAY", nil, 1) -- above the crest's ring
	statusDot:SetSize(14, 14)
	statusDot:SetPoint("CENTER", crest, "BOTTOMRIGHT", -2, 2)

	settingsButton = ns.Widgets.IconButton(bar, "gear", BUTTON_SIZE, ICON_SIZE, "Settings")
	settingsButton:SetPoint("RIGHT", -8, 0)
	ns.Widgets.RoundedFill(settingsButton, "selected"):SetAllPoints()
	settingsButton:SetScript("OnClick", function() ns.SettingsUI.Toggle() end)

	nameText = ns.Widgets.Text(bar, "HangoutFont", "text")
	nameText:SetPoint("TOPLEFT", TEXT_LEFT, -11)
	nameText:SetPoint("TOPRIGHT", -(8 + BUTTON_SIZE + 10), -11)
	nameText:SetWordWrap(false)

	statusText = ns.Widgets.Text(bar, "HangoutFontSmall", "muted")
	statusText:SetPoint("TOPLEFT", TEXT_LEFT, -29)

	CreateStatusButton()
	Refresh()
end

-- The collapsed sidebar only has room for the crest.
function ProfileBar.SetCollapsed(isCollapsed)
	crest:ClearAllPoints()
	if isCollapsed then
		crest:SetPoint("CENTER")
	else
		crest:SetPoint("LEFT", CREST_LEFT, 0)
	end
	nameText:SetShown(not isCollapsed)
	statusText:SetShown(not isCollapsed)
	settingsButton:SetShown(not isCollapsed)
	AnchorStatusButton(isCollapsed)
end

ns.On("DND_CHANGED", Refresh)
ns.On("THEME_CHANGED", Refresh)

-- Catches /afk and /dnd typed in chat and the game marking the player idle.
local statusEvents = CreateFrame("Frame")
statusEvents:RegisterEvent("PLAYER_FLAGS_CHANGED")
statusEvents:SetScript("OnEvent", function()
	ProfileBar.SyncFromGame()
	Refresh()
end)
