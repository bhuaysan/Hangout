local _, ns = ...
local L = ns.L

local Launcher = {}
ns.Launcher = Launcher

local PREVIEW_LINES = 10
local MINIMAP_RADIUS_OFFSET = 5
local BADGE_DELAY = 0.1
local ICON = "Interface\\AddOns\\Hangout\\Media\\icon.png"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local PILL_HEIGHT = 15
local PILL_BASE_WIDTH = 9
local PILL_DIGIT_WIDTH = 6
local GLOW_LOW_ALPHA = 0.15
local GLOW_HIGH_ALPHA = 0.85
local GLOW_SECONDS = 0.9

local button, badge, badgePill, icon, glow, glowPulse

-- Minimap button ---------------------------------------------------------------

local function PlaceButton()
	local angle = math.rad(ns.Get("minimapAngle"))
	local radius = Minimap:GetWidth() / 2 + MINIMAP_RADIUS_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	local angle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
	ns.Set("minimapAngle", angle)
	PlaceButton()
end

-- What the button should say, or nil for nothing. Only whispers count: a busy
-- guild chat would keep it lit all evening. silent is for Do Not Disturb and
-- quiet mode: the count stays, the movement doesn't.
function Launcher.BadgeState(whispers, silent)
	if whispers == 0 then return nil end
	return { text = ns.Util.BadgeText(whispers), pulse = not silent }
end

local function UpdateBadge()
	if not badge then return end
	local state = Launcher.BadgeState(ns.Store.WhisperUnread(), ns.Get("dnd") or ns.Quiet.IsActive())

	local pulse = state ~= nil and state.pulse
	badge:SetShown(state ~= nil)
	badgePill:SetShown(state ~= nil)
	glow:SetShown(pulse)
	-- Every new message lands here, and must not restart a pulse already running.
	if pulse and not glowPulse:IsPlaying() then
		glowPulse:Play()
	elseif not pulse then
		glowPulse:Stop()
	end
	if state then
		badge:SetText(state.text)
		badgePill:SetWidth(PILL_BASE_WIDTH + #state.text * PILL_DIGIT_WIDTH)
		badge:SetTextColor(ns.Theme.Color("panel"))
	end
end

function Launcher.UpdateDndIcon()
	if icon then icon:SetDesaturated(ns.Get("dnd") or ns.Quiet.IsActive()) end
end

function Launcher.UpdateVisibility()
	if button then button:SetShown(ns.Get("showMinimap")) end
end

-- Records whether alerts are silenced, without touching the game's status.
-- Always announces: Settings saves the value before calling this, so a
-- "nothing changed" shortcut would leave the profile bar stale.
function Launcher.ApplyDnd(enabled)
	ns.Set("dnd", enabled)
	Launcher.UpdateDndIcon()
	ns.Fire("DND_CHANGED")
end

function Launcher.SetDnd(enabled)
	ns.ProfileBar.SetStatus(enabled and "dnd" or "online")
end

function Launcher.MarkAllRead()
	local count = ns.Store.MarkAllRead()
	ns.Print(count > 0 and (count == 1 and L["Marked 1 chat as read."] or L["Marked %d chats as read."]:format(count))
		or L["Nothing to mark as read."])
end

function Launcher.ShowMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Hangout")
		root:CreateCheckbox(L["Do Not Disturb"],
			function() return ns.Get("dnd") end,
			function() Launcher.SetDnd(not ns.Get("dnd")) end)
		root:CreateButton(L["Mark all as read"], Launcher.MarkAllRead)
		root:CreateButton(L["Settings"], function() ns.Window.OpenSettings() end)
	end)
end

local function CreateMinimapButton()
	button = CreateFrame("Button", "HangoutMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForDrag("LeftButton")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetHighlightTexture(HIGHLIGHT)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture(ICON)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	glow = button:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints()
	glow:SetTexture(HIGHLIGHT)
	glow:SetBlendMode("ADD")
	glow:Hide()
	glowPulse = glow:CreateAnimationGroup()
	glowPulse:SetLooping("BOUNCE")
	local fade = glowPulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(GLOW_LOW_ALPHA)
	fade:SetToAlpha(GLOW_HIGH_ALPHA)
	fade:SetDuration(GLOW_SECONDS)
	fade:SetSmoothing("IN_OUT")

	-- Its own layer, so the pill sits on top of the button's round border.
	local badgeLayer = CreateFrame("Frame", nil, button)
	badgeLayer:SetAllPoints()
	badgeLayer:SetFrameLevel(button:GetFrameLevel() + 2)

	badgePill = ns.Widgets.RoundedFill(badgeLayer, "accent", "ARTWORK")
	badgePill:SetHeight(PILL_HEIGHT)
	badgePill:SetPoint("TOPRIGHT", 4, 2)
	badgePill:Hide()

	badge = badgeLayer:CreateFontString(nil, "OVERLAY", "HangoutFontSmallBold")
	badge:SetPoint("CENTER", badgePill)
	badge:SetJustifyH("CENTER")
	badge:Hide()

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			Launcher.ShowMenu(self)
		else
			ns.Window.Toggle()
		end
	end)
	button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Hangout")
		ns.Broker.AddUnreadLines(GameTooltip, true)
		GameTooltip:AddLine(L["Click to open. Right-click for options. Drag to move."], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	PlaceButton()
end

function Launcher.Init()
	CreateMinimapButton()
	UpdateBadge()
	ns.ProfileBar.SyncFromGame()
	Launcher.UpdateDndIcon()
	Launcher.UpdateVisibility()
	ns.Broker.Init()
end

ns.On("QUIET_CHANGED", Launcher.UpdateDndIcon)

local updateBadgeSoon = ns.Util.Debounced(BADGE_DELAY, UpdateBadge)
for _, message in ipairs({ "MESSAGE_ADDED", "LOCKED_ADDED", "LIVE_CHANGED", "CONV_CHANGED", "DND_CHANGED",
	"QUIET_CHANGED", "THEME_CHANGED" }) do
	ns.On(message, updateBadgeSoon)
end

-- Global entry points for Bindings.xml and the addon compartment ---------------

BINDING_NAME_HANGOUT_TOGGLE = L["Open or close Hangout"]
BINDING_NAME_HANGOUT_REPLY = L["Reply to the newest message"]
BINDING_NAME_HANGOUT_NEXT_UNREAD = L["Open the next unread chat"]
BINDING_NAME_HANGOUT_QUICK_SWITCH = L["Quick switch to a chat"]

function Hangout_Toggle()
	ns.Window.Toggle()
end

function Hangout_Reply()
	ns.Window.Reply()
end

-- With nothing unread the keypress is quiet, except that it still brings up a closed window.
function Hangout_NextUnread()
	if not ns.Keys.StepChat(1, true) and not ns.Window.IsVisible() then
		ns.Window.Open()
	end
end

function Hangout_QuickSwitch()
	ns.QuickSwitch.Toggle()
end

function Hangout_OnCompartmentClick()
	ns.Window.Toggle()
end

-- Slash commands ---------------------------------------------------------------

local function PrintList()
	local list = ns.Store.List()
	ns.Print(L["%d conversations. Use /hangout show <number> to read one."]:format(#list))
	for i = 1, #list do
		local entry = list[i]
		local saved = ns.Store.IsPersistent(entry.key) and "" or L[" (not saved)"]
		local live = ns.Store.GetLive(entry.key)
		local locked = live and L[" +%d restricted"]:format(#live) or ""
		print(L["%d. %s: %d messages%s%s"]:format(i, entry.conv.name or entry.key, #entry.conv.m, locked, saved))
	end
end

local function PrintConversation(index)
	local entry = ns.Store.List()[index]
	if not entry then
		ns.Print(L["No conversation with that number."])
		return
	end
	local messages = entry.conv.m
	ns.Print(entry.conv.name or entry.key)
	for i = math.max(1, #messages - PREVIEW_LINES + 1), #messages do
		local message = messages[i]
		local who = message.o == 1 and (ns.Store.AltName(message) or L["You"]) or (message.s or entry.conv.name or "?")
		print(date("%m-%d %H:%M", message.t) .. " " .. who .. ": " .. message.x)
	end
end

local COMBAT_MODES = { fade = true, hide = true, off = true }

local function SetCombatMode(mode)
	if COMBAT_MODES[mode] then
		ns.Set("combatMode", mode)
		ns.Print(L["In combat the window will now: %s."]:format(mode))
	else
		ns.Print(L["Use /hangout combat fade, hide or off. Current: %s."]:format(ns.Get("combatMode")))
	end
end

local function HandleKeyword(argument)
	local action, word = argument:match("^(%S*)%s*(.-)$")
	if action == "add" then
		ns.Alerts.AddKeyword(word)
	elseif action == "remove" then
		ns.Alerts.RemoveKeyword(word)
	end
	local keywords = ns.Get("keywords") or {}
	ns.Print(L["Keywords: %s. Use /hangout keyword add <word> or remove <word>."]:format(
		#keywords > 0 and table.concat(keywords, ", ") or L["none"]))
end

SLASH_HANGOUT1 = "/hangout"
SlashCmdList.HANGOUT = function(input)
	local command, argument = input:match("^(%S*)%s*(.-)$")
	if command == "dnd" then
		Launcher.SetDnd(not ns.Get("dnd"))
		ns.Print(ns.Get("dnd") and L["Do Not Disturb is on."] or L["Do Not Disturb is off."])
	elseif command == "keyword" then
		HandleKeyword(argument)
	elseif command == "list" then
		PrintList()
	elseif command == "show" then
		PrintConversation(tonumber(argument) or 0)
	elseif command == "read" then
		Launcher.MarkAllRead()
	elseif command == "combat" then
		SetCombatMode(argument)
	else
		ns.Window.Toggle()
	end
end
