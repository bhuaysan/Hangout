local _, ns = ...

local ProfileBar = {}
ns.ProfileBar = ProfileBar

ProfileBar.HEIGHT = 54

local CREST_SIZE = 30
local CREST_LEFT = 14
local TEXT_LEFT = CREST_LEFT + CREST_SIZE + 10
local BUTTON_SIZE = 28
local ICON_SIZE = 17
local STATUS_ONLINE = "Interface\\FriendsFrame\\StatusIcon-Online"
local STATUS_DND = "Interface\\FriendsFrame\\StatusIcon-DnD"

local bar, crest, statusDot, nameText, statusText, statusButton, settingsButton

local function Refresh()
	if not bar then return end
	local isDnd = ns.Get("dnd") and true or false
	ns.Widgets.SetClassCrest(crest, ns.myClass)
	statusDot:SetTexture(isDnd and STATUS_DND or STATUS_ONLINE)
	nameText:SetText(ns.Util.DisplayName(ns.me or ""))
	nameText:SetTextColor(ns.Theme.ClassColor(ns.myClass, "sidebar", "dock"))
	statusText:SetText(isDnd and "Do Not Disturb" or "Online")
end

local function ShowStatusMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Status")
		root:CreateRadio("Online",
			function() return not ns.Get("dnd") end,
			function() ns.Launcher.SetDnd(false) end)
		root:CreateRadio("Do Not Disturb",
			function() return ns.Get("dnd") and true or false end,
			function() ns.Launcher.SetDnd(true) end)
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
