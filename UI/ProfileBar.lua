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

local function IsGameAfk()
	local afk = UnitIsAFK("player")
	return canaccessvalue(afk) and afk and true or false
end

-- Do Not Disturb is chosen on purpose, so going idle in the game can't override it.
function ProfileBar.CurrentStatus()
	if ns.Get("dnd") then return "dnd" end
	if IsGameAfk() then return "afk" end
	return "online"
end

-- The game toggles AFK with an empty message of this type, just as /afk does.
local function SetGameAfk(wanted)
	if IsGameAfk() == wanted then return end
	if ns.Lockdown.IsActive() then
		ns.Print("Chat is restricted right now. Use /afk in normal chat.")
		return
	end
	C_ChatInfo.SendChatMessage("", "AFK")
end

function ProfileBar.SetStatus(status)
	ns.Launcher.SetDnd(status == "dnd")
	SetGameAfk(status == "afk")
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

	nameText = ns.Widgets.Text(bar, "GameFontHighlight", "text")
	nameText:SetPoint("TOPLEFT", TEXT_LEFT, -11)
	nameText:SetPoint("TOPRIGHT", -(8 + BUTTON_SIZE + 10), -11)
	nameText:SetWordWrap(false)

	statusText = ns.Widgets.Text(bar, "GameFontDisableSmall", "muted")
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

-- Also catches /afk typed in chat and the game marking the player idle.
local statusEvents = CreateFrame("Frame")
statusEvents:RegisterEvent("PLAYER_FLAGS_CHANGED")
statusEvents:SetScript("OnEvent", Refresh)
