local _, ns = ...

local MessageList = {}
ns.MessageList = MessageList

local PAGE_SIZE = 200
local GROUP_WINDOW_SECONDS = 300
local SIDE_PADDING = 12
local HEADER_HEIGHT = 20
local ROW_GAP = 4
local LABEL_ROW_HEIGHT = 26
local LOCKED_MAX_LINES = 3
local REACTION_ROW_HEIGHT = 20
local FALLBACK_LINE_HEIGHT = 15
local CONTEXT_ROWS = 20

local scrollBox, measure
local currentKey
local visibleLimit = PAGE_SIZE
local unreadAfterId
local highlightId
local shownElements = {}

local function SenderOf(message, conv)
	if message.o == 1 then return "You" end
	if message.s then return ns.Store.SenderLabel(message.s) end
	return conv.nick or ns.Util.DisplayName(conv.name or "?")
end

local function ClassOf(message, conv)
	if message.o == 1 then return ns.myClass end
	if message.s then return message.k end
	return conv.class
end

-- Turns stored messages into list rows: day separators, and messages that
-- only show a header when the sender changes or time has passed.
-- unreadAfterId, if set, marks where "New messages" begins.
function MessageList.BuildElements(conv, limit, live, unreadAfterId)
	local elements = {}
	local messages = conv.m
	local first = math.max(1, #messages - limit + 1)
	if first > 1 then
		elements[1] = { kind = "older", label = "Load older messages" }
	end

	local previousDay, previous, previousSender
	local dividerPlaced = false
	local seenPosition
	for i = first, #messages do
		local message = messages[i]
		local day = date("%Y-%m-%d", message.t)
		if day ~= previousDay then
			elements[#elements + 1] = { kind = "day", label = day }
			previousDay = day
			previous = nil
		end

		if unreadAfterId and not dividerPlaced and message.i > unreadAfterId and message.o ~= 1 then
			elements[#elements + 1] = { kind = "unread", label = "New messages" }
			dividerPlaced = true
			previous = nil
		end

		local sender = SenderOf(message, conv)
		elements[#elements + 1] = {
			kind = "message",
			id = message.i,
			sender = sender,
			class = ClassOf(message, conv),
			mention = message.s ~= nil and message.o ~= 1 and ns.Alerts.IsMention(message.x),
			reactions = ns.Protocol.ReactionText(message.r),
			time = date("%H:%M", message.t),
			display = ns.Emoji.Display(message.x),
			head = previous == nil
				or sender ~= previousSender
				or message.t - previous.t > GROUP_WINDOW_SECONDS,
		}
		if message.o == 1 and conv.seenId and message.i <= conv.seenId then
			seenPosition = #elements
		end
		previous = message
		previousSender = sender
	end

	if seenPosition then
		table.insert(elements, seenPosition + 1, { kind = "seen", label = "Seen" })
	end

	-- Locked messages arrive while restricted, so they are always the newest.
	-- Their text and sender are secret: they may only be handed to a FontString.
	for _, element in ipairs(live or {}) do
		elements[#elements + 1] = {
			kind = "locked",
			time = date("%H:%M", element.t),
			outgoing = element.o == 1,
			text = element.text,
			sender = element.sender,
		}
	end
	return elements
end

-- Text size can come back secret during a restriction.
local function ReadableHeight(lines)
	local height = measure:GetStringHeight()
	if canaccessvalue(height) then
		return math.ceil(height)
	end
	return FALLBACK_LINE_HEIGHT * lines
end

local function BodyHeight(element, width)
	if element.measuredWidth ~= width then
		measure:SetWidth(width)
		measure:SetText(element.display)
		element.bodyHeight = ReadableHeight(1)
		element.measuredWidth = width
	end
	return element.bodyHeight
end

local function LineHeight()
	measure:SetWidth(200)
	measure:SetText("Xg")
	return ReadableHeight(1)
end

local function ExtentOf(_, element)
	if element.kind == "locked" then
		return HEADER_HEIGHT + LineHeight() * LOCKED_MAX_LINES + ROW_GAP
	end
	if element.kind ~= "message" then
		return LABEL_ROW_HEIGHT
	end
	local width = scrollBox:GetWidth() - SIDE_PADDING * 2
	return (element.head and HEADER_HEIGHT or 0) + BodyHeight(element, width) + ROW_GAP
		+ (element.reactions and REACTION_ROW_HEIGHT or 0)
end

local function OnHyperlinkClick(self, link, text, button)
	SetItemRef(link, text, button, self)
end

local function ShowReactionMenu(owner, messageId)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("React")
		for _, emoji in ipairs(ns.Protocol.QUICK_REACTIONS) do
			local active = ns.Protocol.HasMyReaction(currentKey, messageId, emoji)
			root:CreateButton(ns.Emoji.Tag(emoji) .. (active and "  Remove" or "  " .. emoji), function()
				ns.Protocol.ToggleReaction(currentKey, messageId, emoji)
			end)
		end
	end)
end

local function OnRowMouseUp(self, button)
	local element = self.element
	if not element then return end
	if element.kind == "older" and button == "LeftButton" then
		visibleLimit = visibleLimit + PAGE_SIZE
		MessageList.Refresh()
	elseif element.kind == "message" and button == "RightButton" and ns.Protocol.CanReact(currentKey) then
		ShowReactionMenu(self, element.id)
	end
end

local function BuildRow(frame)
	frame.sender = ns.Widgets.Text(frame, "GameFontNormal", "text")
	frame.sender:SetPoint("TOPLEFT", SIDE_PADDING, -4)

	frame.time = ns.Widgets.Text(frame, "GameFontDisableSmall", "muted")
	frame.time:SetPoint("LEFT", frame.sender, "RIGHT", 8, 0)

	frame.body = ns.Widgets.Text(frame, "HangoutMessageFont", "text")
	frame.body:SetWordWrap(true)

	frame.label = ns.Widgets.Text(frame, "GameFontDisableSmall", "muted")
	frame.label:SetPoint("CENTER")
	frame.label:SetJustifyH("CENTER")

	frame.highlight = ns.Widgets.Fill(frame, "selected")

	frame.reactions = ns.Widgets.Text(frame, "GameFontHighlightSmall", "muted")
	frame.reactions:SetPoint("TOPLEFT", frame.body, "BOTTOMLEFT", 0, -3)

	frame.mentionBar = ns.Widgets.Solid(frame, "accent", "ARTWORK")
	frame.mentionBar:SetPoint("TOPLEFT", 4, 0)
	frame.mentionBar:SetPoint("BOTTOMLEFT", 4, 0)
	frame.mentionBar:SetWidth(2)

	frame:SetHyperlinksEnabled(true)
	frame:SetScript("OnHyperlinkClick", OnHyperlinkClick)
	frame:SetScript("OnMouseUp", OnRowMouseUp)
end

local function InitRow(frame, element)
	if not frame.body then BuildRow(frame) end
	frame.element = element

	local isMessage = element.kind == "message"
	frame.body:SetShown(isMessage)
	frame.sender:SetShown(isMessage and element.head)
	frame.time:SetShown(isMessage and element.head)
	frame.label:SetShown(not isMessage)
	frame.mentionBar:SetShown(isMessage and element.mention)
	frame.highlight:SetShown(isMessage and element.id ~= nil and element.id == highlightId)
	frame.reactions:SetShown(isMessage and element.reactions ~= nil)
	if isMessage and element.reactions then
		frame.reactions:SetText(element.reactions)
	end
	frame:EnableMouse(not ns.Window.IsFaded())
	frame:SetHyperlinksEnabled(not ns.Window.IsFaded())

	if not isMessage then
		frame.label:SetText(element.label)
		frame.label:SetTextColor(ns.Theme.Color(element.kind == "unread" and "accent" or "muted"))
		return
	end

	local top = element.head and -HEADER_HEIGHT or 0
	frame.body:ClearAllPoints()
	frame.body:SetPoint("TOPLEFT", SIDE_PADDING, top)
	frame.body:SetPoint("TOPRIGHT", -SIDE_PADDING, top)
	frame.body:SetText(element.display)

	if element.head then
		frame.sender:SetText(element.sender)
		frame.sender:SetTextColor(ns.Theme.ClassColor(element.class))
		frame.time:SetText(element.time)
	end
end

-- Locked rows use their own frame type so normal rows never receive a secret.
-- A FontString that has displayed a secret reports a secret size from then on,
-- so nothing here may measure these rows or anchor to their text.
local function InitLockedRow(frame, element)
	-- These rows have no click action, and must not catch clicks through a faded window.
	frame:EnableMouse(false)

	if not frame.lockedBody then
		frame.lockedMeta = ns.Widgets.Text(frame, "GameFontDisableSmall", "muted")
		frame.lockedMeta:SetPoint("TOPLEFT", SIDE_PADDING, -4)

		frame.lockedBody = ns.Widgets.Text(frame, "HangoutMessageFont", "muted")
		frame.lockedBody:SetPoint("TOPLEFT", SIDE_PADDING, -HEADER_HEIGHT)
		frame.lockedBody:SetPoint("TOPRIGHT", -SIDE_PADDING, -HEADER_HEIGHT)
		frame.lockedBody:SetWordWrap(true)
		frame.lockedBody:SetMaxLines(LOCKED_MAX_LINES)
	end

	frame.lockedMeta:SetText(element.time .. "  Restricted")
	frame.lockedBody:ClearText()
	if element.outgoing then
		frame.lockedBody:SetText("You: " .. element.text)
	else
		frame.lockedBody:SetText(element.sender .. ": " .. element.text)
	end
end

local function ResetRow(frame)
	if frame.lockedBody then
		frame.lockedBody:ClearText()
	end
end

local function ChooseRow(factory, element)
	if element.kind == "locked" then
		factory("Button", InitLockedRow)
	else
		factory("Frame", InitRow)
	end
end

function MessageList.Create(parent)
	measure = parent:CreateFontString(nil, "OVERLAY", "HangoutMessageFont")
	measure:SetPoint("TOPLEFT")
	measure:SetAlpha(0)
	measure:SetWordWrap(true)

	local view = CreateScrollBoxListLinearView(4, 8, 0, 0, 0)
	view:SetElementFactory(ChooseRow)
	view:SetElementResetter(ResetRow)
	view:SetElementExtentCalculator(ExtentOf)

	local scrollBar
	scrollBox, scrollBar = ns.Widgets.ScrollList(parent, view)
	scrollBar:SetPoint("TOPRIGHT", -2, -4)
	scrollBar:SetPoint("BOTTOMRIGHT", -2, 4)
	scrollBox:SetPoint("TOPLEFT")
	scrollBox:SetPoint("BOTTOMRIGHT", -14, 0)
end

-- Rebuilds the rows, following new messages only if already at the bottom.
function MessageList.Refresh(jumpToEnd)
	if not scrollBox or not currentKey then return end

	local follow = jumpToEnd or scrollBox:IsAtEnd() or not scrollBox:HasScrollableExtent()
	local conv = ns.Store.Get(currentKey)
	local live = ns.Store.GetLive(currentKey)
	shownElements = conv and MessageList.BuildElements(conv, visibleLimit, live, unreadAfterId) or {}
	scrollBox:SetDataProvider(CreateDataProvider(shownElements), ScrollBoxConstants.RetainScrollPosition)
	if follow then
		scrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
	end
end

-- Empties the list when no conversation is left to show.
function MessageList.Clear()
	currentKey = nil
	unreadAfterId = nil
	highlightId = nil
	shownElements = {}
	if scrollBox then
		scrollBox:SetDataProvider(CreateDataProvider(shownElements))
	end
end

local function ScrollToFirst(matches, alignment)
	for _, element in ipairs(shownElements) do
		if matches(element) then
			scrollBox:ScrollToElementData(element, alignment, nil, ScrollBoxConstants.NoScrollInterpolation)
			return
		end
	end
end

-- Opens a chat at its first unread message, or at the end if there is none.
function MessageList.Show(key, firstUnreadAfterId, unreadCount)
	currentKey = key
	unreadAfterId = firstUnreadAfterId
	highlightId = nil
	visibleLimit = math.max(PAGE_SIZE, (unreadCount or 0) + CONTEXT_ROWS)
	MessageList.Refresh(true)
	if firstUnreadAfterId then
		ScrollToFirst(function(element) return element.kind == "unread" end, ScrollBoxConstants.AlignBegin)
	end
end

-- Opens a chat centered on one message, for search results.
function MessageList.ShowAt(key, messageId)
	currentKey = key
	unreadAfterId = nil
	highlightId = messageId

	local conv = ns.Store.Get(key)
	local messages = conv and conv.m or {}
	for position = #messages, 1, -1 do
		if messages[position].i == messageId then
			visibleLimit = math.max(PAGE_SIZE, #messages - position + 1 + CONTEXT_ROWS)
			break
		end
	end

	MessageList.Refresh(true)
	ScrollToFirst(function(element) return element.id == messageId end, ScrollBoxConstants.AlignCenter)
end

local function RefreshIfCurrent(key)
	if key == currentKey then
		MessageList.Refresh()
	end
end

ns.On("MESSAGE_ADDED", RefreshIfCurrent)
ns.On("LOCKED_ADDED", RefreshIfCurrent)
ns.On("MESSAGES_CHANGED", RefreshIfCurrent)
ns.On("LIVE_CHANGED", function() MessageList.Refresh() end)
ns.On("THEME_CHANGED", function() MessageList.Refresh() end)
