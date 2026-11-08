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

local bar, crest, statusDot, nameText, statusText, dndButton, settingsButton

local function Refresh()
	if not bar then return end
	local isDnd = ns.Get("dnd") and true or false
	ns.Widgets.SetClassCrest(crest, ns.myClass)
	statusDot:SetTexture(isDnd and STATUS_DND or STATUS_ONLINE)
	nameText:SetText(ns.Util.DisplayName(ns.me or ""))
	nameText:SetTextColor(ns.Theme.ClassColor(ns.myClass, "sidebar", "dock"))
	statusText:SetText(isDnd and "Do Not Disturb" or "Online")
	ns.Widgets.SetIconButtonActive(dndButton, isDnd)
end

function ProfileBar.Create(parent)
	bar = CreateFrame("Frame", nil, parent)
	bar:SetPoint("BOTTOMLEFT")
	bar:SetPoint("BOTTOMRIGHT")
	bar:SetHeight(ProfileBar.HEIGHT)
	ns.Widgets.Fill(bar, "dock")

	crest = ns.Widgets.ClassCrest(bar, CREST_SIZE)
	crest:SetPoint("LEFT", CREST_LEFT, 0)

	statusDot = bar:CreateTexture(nil, "OVERLAY", nil, 1) -- above the crest's ring
	statusDot:SetSize(14, 14)
	statusDot:SetPoint("CENTER", crest, "BOTTOMRIGHT", -2, 2)

	settingsButton = ns.Widgets.IconButton(bar, "gear", BUTTON_SIZE, ICON_SIZE, "Settings")
	settingsButton:SetPoint("RIGHT", -8, 0)
	settingsButton:SetScript("OnClick", function() ns.SettingsUI.Toggle() end)

	dndButton = ns.Widgets.IconButton(bar, "moon", BUTTON_SIZE, ICON_SIZE, "Do Not Disturb")
	dndButton:SetPoint("RIGHT", settingsButton, "LEFT", -2, 0)
	dndButton:SetScript("OnClick", function() ns.Launcher.SetDnd(not ns.Get("dnd")) end)

	nameText = ns.Widgets.Text(bar, "GameFontHighlight", "text")
	nameText:SetPoint("TOPLEFT", TEXT_LEFT, -11)
	nameText:SetPoint("TOPRIGHT", dndButton, "TOPLEFT", -4, -3)
	nameText:SetWordWrap(false)

	statusText = ns.Widgets.Text(bar, "GameFontDisableSmall", "muted")
	statusText:SetPoint("TOPLEFT", TEXT_LEFT, -29)

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
	dndButton:SetShown(not isCollapsed)
	settingsButton:SetShown(not isCollapsed)
end

ns.On("DND_CHANGED", Refresh)
ns.On("THEME_CHANGED", Refresh)
