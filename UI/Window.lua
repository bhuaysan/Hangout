local _, ns = ...

local Window = {}
ns.Window = Window

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 730, 440
local MIN_WIDTH, MIN_HEIGHT = 520, 260
local SIDEBAR_WIDTH = 240
local SIDEBAR_COLLAPSED_WIDTH = 56
local HEADER_HEIGHT = 54
local COMPOSER_HEIGHT = 60
local HEADER_BUTTON_SIZE = 28
local HEADER_ICON_SIZE = 17
local HEADER_AVATAR_SIZE = 30
local HEADER_AVATAR_LEFT = 42
local TITLE_LEFT_PLAIN = 42
local TITLE_LEFT_WITH_AVATAR = HEADER_AVATAR_LEFT + HEADER_AVATAR_SIZE + 10
local TITLE_RIGHT_RESERVE = 130
local BANNER_HEIGHT = 24
local RESIZE_REFRESH_DELAY = 0.1
local EDGE_LEVEL_OFFSET = 35
local GRIP_LEVEL_OFFSET = 40

local frame, title, subtitle, header, banner, messages, sidebar, emptyHint
local collapseButton, closeButton, settingsButton, muteButton, pinButton, avatar
local settingsOpen = false
local faded = false
local hiddenForCombat = false
local hiddenWithUI = false
local mouseState = {}

local refreshAfterResize = ns.Util.Debounced(RESIZE_REFRESH_DELAY, function()
	ns.MessageList.Refresh()
end)

function Window.IsFaded()
	return faded
end

function Window.IsVisible()
	return frame ~= nil and frame:IsVisible()
end

-- The one place the selected chat changes. Everything showing it listens for this.
local function SetSelection(key, firstUnreadAfterId, unreadCount)
	ns.selectedKey = key
	ns.Fire("SELECTION_CHANGED", key, firstUnreadAfterId, unreadCount)
end

local function SaveGeometry()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.Set("window", {
		point = point,
		relativePoint = relativePoint,
		x = x,
		y = y,
		width = frame:GetWidth(),
		height = frame:GetHeight(),
	})
end

local function RestoreGeometry()
	local saved = ns.Get("window")
	if saved then
		frame:SetSize(math.max(MIN_WIDTH, saved.width), math.max(MIN_HEIGHT, saved.height))
		frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
	else
		frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
		frame:SetPoint("CENTER")
	end
end

-- Messages only count as read while the window is really being looked at.
local function UpdateActive()
	local viewing = frame and frame:IsVisible() and not faded and ns.selectedKey or nil
	ns.activeKey = viewing
	if viewing then
		ns.Store.MarkRead(viewing)
	end
end

local function HeaderButton(icon, tooltip)
	return ns.Widgets.IconButton(header, icon, HEADER_BUTTON_SIZE, HEADER_ICON_SIZE, tooltip)
end

local function SetCollapsed(collapsed)
	ns.Set("sidebarCollapsed", collapsed)
	sidebar:SetWidth(collapsed and SIDEBAR_COLLAPSED_WIDTH or SIDEBAR_WIDTH)
	ns.Widgets.SetIcon(collapseButton.icon, collapsed and "expand" or "collapse")
	-- The profile bar's gear is hidden when collapsed, so Settings moves up here.
	settingsButton:SetShown(collapsed)
	muteButton:ClearAllPoints()
	muteButton:SetPoint("RIGHT", collapsed and settingsButton or closeButton, "LEFT", -2, 0)
	ns.Sidebar.SetCollapsed(collapsed)
	refreshAfterResize()
end

local function CreateResizeGrip()
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT")
	-- Above the Settings panel, which covers the rest of the window.
	grip:SetFrameLevel(frame:GetFrameLevel() + GRIP_LEVEL_OFFSET)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		SaveGeometry()
	end)
end

-- Sits above everything but the resize grip, and lets clicks through.
local function CreateFrameEdge()
	local edge = CreateFrame("Frame", nil, frame)
	edge:SetAllPoints()
	edge:SetFrameLevel(frame:GetFrameLevel() + EDGE_LEVEL_OFFSET)
	ns.Widgets.Border(edge, "edge")
end

local function ToggleField(field)
	local conv = ns.selectedKey and ns.Store.Get(ns.selectedKey)
	if conv then
		ns.Store.SetField(ns.selectedKey, field, not conv[field] or nil)
	end
end

local function CreateHeader()
	header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(HEADER_HEIGHT)
	ns.Widgets.RoundedFill(header, "raised", nil, "topRight"):SetAllPoints()

	collapseButton = HeaderButton("collapse", "Show or hide the sidebar")
	collapseButton:SetPoint("LEFT", 8, 0)
	collapseButton:SetScript("OnClick", function()
		SetCollapsed(not ns.Get("sidebarCollapsed"))
	end)

	avatar = ns.Widgets.ChatAvatar(header, HEADER_AVATAR_SIZE, 16)
	ns.Widgets.PlaceChatAvatar(avatar, "LEFT", HEADER_AVATAR_LEFT, 0)

	title = ns.Widgets.Text(header, "HangoutFontLargeBold", "text")
	title:SetWordWrap(false)

	subtitle = ns.Widgets.Text(header, "HangoutFontSmall", "muted")
	subtitle:SetWordWrap(false)

	closeButton = HeaderButton("close", "Close")
	closeButton:SetPoint("RIGHT", -8, 0)
	closeButton:SetScript("OnClick", function() frame:Hide() end)

	settingsButton = HeaderButton("gear", "Settings")
	settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
	settingsButton:SetScript("OnClick", function() ns.SettingsUI.Toggle() end)

	muteButton = HeaderButton("mute", "Mute this chat")
	muteButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
	muteButton:SetScript("OnClick", function() ToggleField("mute") end)

	pinButton = HeaderButton("pin", "Pin this chat")
	pinButton:SetPoint("RIGHT", muteButton, "LEFT", -2, 0)
	pinButton:SetScript("OnClick", function() ToggleField("pin") end)
end

local function CreateBanner()
	banner = CreateFrame("Frame", nil, frame)
	banner:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	banner:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -1)
	banner:SetHeight(BANNER_HEIGHT)
	ns.Widgets.Fill(banner, "notice")
	local bannerText = ns.Widgets.Text(banner, "HangoutFontSmall", "text")
	bannerText:SetPoint("LEFT", 12, 0)
	bannerText:SetPoint("RIGHT", -12, 0)
	bannerText:SetWordWrap(false)
	bannerText:SetText("Chat is restricted right now. Hangout can't send, and will catch up when it ends.")
end

local function Create()
	frame = CreateFrame("Frame", "HangoutWindow", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	RestoreGeometry()
	ns.Widgets.RoundedFill(frame, "bg"):SetAllPoints()

	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SaveGeometry()
	end)
	frame:SetScript("OnSizeChanged", refreshAfterResize)
	frame:SetScript("OnHide", function()
		-- Hidden but still "shown" means the whole UI went away, as with Alt-Z.
		hiddenWithUI = frame:IsShown()
		UpdateActive()
	end)
	frame:SetScript("OnShow", function()
		ns.Glance.Hide()
		if hiddenWithUI then
			hiddenWithUI = false
			ns.Sidebar.Refresh()
			if ns.selectedKey then Window.Select(ns.selectedKey) end
		end
	end)
	frame:Hide()
	tinsert(UISpecialFrames, "HangoutWindow")

	sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPLEFT")
	sidebar:SetPoint("BOTTOMLEFT")
	ns.Widgets.RoundedFill(sidebar, "sidebar", nil, "left"):SetAllPoints()
	ns.Sidebar.Create(sidebar)

	CreateHeader()
	SetCollapsed(ns.Get("sidebarCollapsed"))

	local headerLine = ns.Widgets.Solid(frame, "edge", "ARTWORK")
	headerLine:SetHeight(1)
	headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

	local composer = CreateFrame("Frame", nil, frame)
	composer:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")
	composer:SetPoint("BOTTOMRIGHT")
	composer:SetHeight(COMPOSER_HEIGHT)
	ns.Composer.Create(composer)

	CreateBanner()

	messages = CreateFrame("Frame", nil, frame)
	messages:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	messages:SetPoint("BOTTOMRIGHT", composer, "TOPRIGHT", 0, 1)
	ns.MessageList.Create(messages)

	emptyHint = ns.Widgets.Text(messages, "HangoutFont", "muted")
	emptyHint:SetPoint("LEFT", 24, 0)
	emptyHint:SetPoint("RIGHT", -24, 0)
	emptyHint:SetJustifyH("CENTER")
	emptyHint:SetText("Use the + next to Search to whisper someone. Chats also appear here when someone messages you.")
	emptyHint:Hide()

	ns.SettingsUI.Create(frame, header)
	CreateFrameEdge()
	CreateResizeGrip()
end

local function UpdateRestriction()
	if not frame then return end
	local active = ns.Lockdown.IsActive()
	banner:SetShown(active)
	messages:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, active and -(BANNER_HEIGHT + 1) or -1)
	refreshAfterResize()
end

local STATUS_LABEL = {
	online = "Online",
	afk = "AFK",
	dnd = "Do Not Disturb",
	offline = "Offline",
}

-- The small line under a chat's name.
function Window.SubtitleFor(key, conv)
	if ns.Protocol.IsTyping(key) then return "typing..." end

	local category = ns.CategoryOf(key)
	if category == "group" then return "Group chat" end
	if category == "channel" then return "Channel" end

	local parts = {}
	local status = ns.Identity.Status(key)
	if status then parts[#parts + 1] = STATUS_LABEL[status] end
	local className = conv.class and LOCALIZED_CLASS_NAMES_MALE[conv.class]
	if className then parts[#parts + 1] = className end
	if conv.note then parts[#parts + 1] = conv.note end
	return table.concat(parts, "  ·  ")
end

local function AnchorTitle(hasAvatar, hasSubtitle)
	local left = hasAvatar and TITLE_LEFT_WITH_AVATAR or TITLE_LEFT_PLAIN
	title:ClearAllPoints()
	subtitle:ClearAllPoints()
	if hasSubtitle then
		title:SetPoint("TOPLEFT", left, -10)
		title:SetPoint("TOPRIGHT", -TITLE_RIGHT_RESERVE, -10)
		subtitle:SetPoint("TOPLEFT", left, -31)
		subtitle:SetPoint("TOPRIGHT", -TITLE_RIGHT_RESERVE, -31)
	else
		title:SetPoint("LEFT", left, 0)
		title:SetPoint("RIGHT", -TITLE_RIGHT_RESERVE, 0)
	end
end

local function UpdateStatus()
	if not frame then return end
	local conv = not settingsOpen and ns.selectedKey and ns.Store.Get(ns.selectedKey)
	local text = conv and Window.SubtitleFor(ns.selectedKey, conv) or ""
	subtitle:SetText(text)
	subtitle:SetShown(text ~= "")
	AnchorTitle(conv and true or false, text ~= "")
end

-- The name on top, with the chat's note under it when there is one.
local function UpdateTitle()
	if not frame then return end
	local conv = ns.selectedKey and ns.Store.Get(ns.selectedKey)
	local hasChats = conv ~= nil or #ns.Store.List() > 0
	local showsChat = conv ~= nil and not settingsOpen

	if settingsOpen then
		title:SetText("Settings")
	elseif conv then
		title:SetText(ns.Store.LabelFor(ns.selectedKey, conv))
	else
		title:SetText(hasChats and "Select a conversation" or "No conversations yet")
	end
	emptyHint:SetShown(not hasChats)

	ns.Widgets.ShowChatAvatar(avatar, showsChat and {
		key = ns.selectedKey,
		class = conv.class,
		label = ns.Store.LabelFor(ns.selectedKey, conv),
		status = ns.Identity.Status(ns.selectedKey),
		muted = conv.mute,
	} or nil)

	local canPin = showsChat and ns.Store.IsPersistent(ns.selectedKey)
	pinButton:SetShown(canPin)
	muteButton:SetShown(canPin)
	if canPin then
		ns.Widgets.SetIconButtonActive(pinButton, conv.pin)
		ns.Widgets.SetIconButtonActive(muteButton, conv.mute)
	end
	UpdateStatus()
end

function Window.Select(key)
	ns.SettingsUI.Hide()
	ns.EmojiPicker.Hide()
	local conv = ns.Store.Get(key)
	local unreadCount = conv and conv.unread or 0
	local unreadAfterId = unreadCount > 0 and (conv.readId or 0) or nil
	SetSelection(key, unreadAfterId, unreadCount)
	UpdateTitle()
	UpdateStatus()
	UpdateActive()
	ns.Protocol.OnOpened(key)
end

local function SelectNewest()
	local list = ns.Store.List()
	-- A stranger's Request is only opened on purpose, because opening marks it read.
	for _, entry in ipairs(list) do
		if not entry.conv.req then
			Window.Select(entry.key)
			return
		end
	end

	SetSelection(nil)
	UpdateTitle()
	UpdateStatus()
	UpdateActive()
end

-- Combat ---------------------------------------------------------------------

-- Walks every child so a faded window can't catch clicks or the mouse wheel.
local function DisableMouse(widget)
	mouseState[widget] = {
		mouse = widget:IsMouseEnabled(),
		wheel = widget:IsMouseWheelEnabled(),
	}
	widget:EnableMouse(false)
	widget:EnableMouseWheel(false)
	for _, child in ipairs({ widget:GetChildren() }) do
		DisableMouse(child)
	end
end

local function RestoreMouse()
	for widget, state in pairs(mouseState) do
		widget:EnableMouse(state.mouse)
		widget:EnableMouseWheel(state.wheel)
	end
	mouseState = {}
end

local function Fade()
	faded = true
	frame:SetAlpha(ns.Get("combatOpacity") / 100)
	DisableMouse(frame)
	ns.Sidebar.Refresh()
	ns.MessageList.Refresh()
	UpdateActive()
end

local function Unfade()
	faded = false
	frame:SetAlpha(1)
	RestoreMouse()
	if frame:IsShown() and ns.selectedKey then
		Window.Select(ns.selectedKey)
	else
		UpdateActive()
	end
end

local function OnEnterCombat()
	if not frame or not frame:IsShown() or faded then return end
	local mode = ns.Get("combatMode")
	if mode == "off" then return end
	ns.Composer.ClearFocus()
	ns.Sidebar.ClearSearchFocus()
	ns.SettingsUI.Hide()
	ns.EmojiPicker.Hide()
	if mode == "hide" then
		hiddenForCombat = true
		frame:Hide()
	else
		Fade()
	end
end

-- Shows the window on key, or on the current selection if key is nil.
local function ShowWindow(key)
	hiddenForCombat = false
	frame:Show()
	UpdateRestriction()
	ns.Sidebar.Refresh()
	key = key or ns.selectedKey
	if key then
		Window.Select(key)
	else
		SelectNewest()
	end
	-- Opening the window on purpose in "hide" mode should still work.
	if InCombatLockdown() and ns.Get("combatMode") == "fade" then
		OnEnterCombat()
	end
end

local function OnLeaveCombat()
	if faded then
		Unfade()
	end
	if hiddenForCombat then
		hiddenForCombat = false
		ShowWindow()
	end
end

local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		OnEnterCombat()
	else
		OnLeaveCombat()
	end
end)

function Window.Open(key)
	if not frame then Create() end
	if not frame:IsShown() then
		ShowWindow(key)
	elseif key then
		Window.Select(key)
	end
end

-- Opens a chat ready to type in: key, or else the newest unread chat, or else
-- the current one. A faded window stays out of the way of the fight.
function Window.Reply(key)
	Window.Open(key or ns.Store.NewestUnreadKey() or ns.selectedKey)
	if not faded then
		ns.Composer.Focus()
	end
end

-- Opens a chat at one message, used by search results.
function Window.JumpTo(key, messageId)
	Window.Select(key)
	ns.MessageList.ShowAt(messageId)
end

function Window.OpenSettings()
	if not frame then Create() end
	if not frame:IsShown() then ShowWindow() end
	ns.SettingsUI.Show()
end

function Window.Toggle()
	if not frame then Create() end
	if frame:IsShown() then
		frame:Hide()
		if faded then Unfade() end
	else
		ShowWindow()
	end
end

-- The first message of a session gives an open, empty window something to show.
local function SelectIfEmpty(key)
	if not frame or not frame:IsShown() or ns.selectedKey then return end
	local conv = ns.Store.Get(key)
	if conv and not conv.req then
		Window.Select(key)
	end
end

ns.On("MESSAGE_ADDED", SelectIfEmpty)
ns.On("LOCKED_ADDED", SelectIfEmpty)
ns.On("LOCKDOWN_CHANGED", UpdateRestriction)
ns.On("TYPING_CHANGED", UpdateStatus)
ns.On("SETTINGS_TOGGLED", function(isOpen)
	settingsOpen = isOpen
	UpdateTitle()
	UpdateStatus()
end)

-- The selected chat can disappear: deleted, blocked, or a temporary
-- "During restriction" chat whose messages have been saved.
local function SelectNewestIfGone()
	if frame and ns.selectedKey and not ns.Store.Get(ns.selectedKey) then
		SelectNewest()
	end
end

ns.On("LIVE_CHANGED", SelectNewestIfGone)
ns.On("CONV_CHANGED", function()
	SelectNewestIfGone()
	UpdateStatus()
	UpdateTitle()
end)
