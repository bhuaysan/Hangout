local _, ns = ...

local MessageList = {}
ns.MessageList = MessageList

local PAGE_SIZE = 200
local GROUP_WINDOW_SECONDS = 300
local SECONDS_PER_DAY = 86400
local SIDE_PADDING = 12
local CREST_SIZE = 26
local TEXT_LEFT = SIDE_PADDING + CREST_SIZE + 8
local HEADER_HEIGHT = 20
local ROW_GAP = 4
local LABEL_ROW_HEIGHT = 26
local LOCKED_MAX_LINES = 3
local REACTION_ROW_HEIGHT = 24
local PILL_HEIGHT = 20
local PILL_GAP = 4
local PILL_BASE_WIDTH = 32
local PILL_DIGIT_WIDTH = 6
local TOOLBAR_BUTTON_SIZE = 24
local TOOLBAR_PADDING = 3
local TOOLBAR_ICON_SIZE = 16
local TOOLBAR_OVERLAP = 6
local TOOLBAR_RAISE = 12
local OPENER_HEIGHT = 74
local OPENER_AVATAR_SIZE = 46
local QUICK_BAR = { "thumbsup", "heart", "joy" }
local FALLBACK_LINE_HEIGHT = 15
local CONTEXT_ROWS = 20

local BUBBLE_PAD_X = 10
local BUBBLE_PAD_Y = 6
local BUBBLE_MAX_SHARE = 0.72
local BUBBLE_MAX_WIDTH = 520 -- long lines are hard to read in a wide window
local BUBBLE_REACTION_HEIGHT = 24
local BUBBLE_TOP_HEAD = 8
local BUBBLE_TOP_FOLLOWING = 1
local BUBBLE_BOTTOM = 2
local BUBBLE_TIME_GAP = 6
local BUBBLE_TIME_ROOM = 40

local REACTION_NAMES = {
	thumbsup = "Thumbs up",
	heart = "Heart",
	joy = "Laughing",
	tada = "Celebrate",
	thinking = "Thinking",
	sob = "Crying",
}

-- Link types GameTooltip can show. Names, URLs and the like have no tooltip.
local TOOLTIP_LINKS = {
	item = true, spell = true, enchant = true, quest = true, achievement = true,
	talent = true, glyph = true, unit = true, currency = true, battlepet = true,
	battlePetAbil = true, garrfollower = true, instancelock = true, keystone = true,
	mount = true, transmogappearance = true, transmogillusion = true, transmogset = true,
	azessence = true, conduit = true, api = true, dungeonScore = true,
}
local NAME_BUTTON_HEIGHT = 16

local scrollBox, measure, jumpButton, jumpLabel
local newWhileAway = 0
local visibleLimit = PAGE_SIZE
local unreadAfterId
local highlightId
local shownElements = {}
local toolbar, toolbarRow

local function SenderOf(message, conv)
	if message.o == 1 then return ns.Store.AltName(message) or "You" end
	if message.s then return ns.Store.SenderLabel(message.s) end
	return conv.nick or ns.Util.DisplayName(conv.name or "?")
end

local function ClassOf(message, conv)
	if message.o == 1 then
		-- An alt's class isn't saved, so it gets the plain text color.
		if ns.Store.AltName(message) then return nil end
		return ns.myClass
	end
	if message.s then return message.k end
	return conv.class
end

-- The separator text for the day a message was sent.
function MessageList.DayLabel(timestamp, now)
	local day = date("%Y-%m-%d", timestamp)
	if day == date("%Y-%m-%d", now) then return "Today" end
	if day == date("%Y-%m-%d", now - SECONDS_PER_DAY) then return "Yesterday" end

	local label = date("%B ", timestamp) .. tonumber(date("%d", timestamp))
	if date("%Y", timestamp) ~= date("%Y", now) then
		label = label .. ", " .. date("%Y", timestamp)
	end
	return label
end

-- The character a message came from, for the player menu. Outgoing messages
-- are the player's own, and Battle.net chats have no character name.
local function AuthorOf(message, conv, key)
	if message.o == 1 then return nil end
	if message.s then return message.s end
	if key and key:sub(1, 2) ~= "W:" then return nil end
	return conv.name
end

-- The whole chat as plain text, oldest first, for the clipboard.
function MessageList.ConversationText(_, conv)
	local lines = {}
	for _, message in ipairs(conv.m) do
		lines[#lines + 1] = "[" .. date("%Y-%m-%d %H:%M", message.t) .. "] " .. SenderOf(message, conv)
			.. ": " .. ns.CopyBox.PlainText(message.x)
	end
	return table.concat(lines, "\n")
end

-- Turns stored messages into list rows: day separators, and messages that
-- only show a header when the sender changes or time has passed.
-- unreadAfterId, if set, marks where "New messages" begins. key tells whisper
-- chats from Battle.net ones; without it the conversation is taken as a whisper.
function MessageList.BuildElements(conv, limit, live, unreadAfterId, key)
	local elements = {}
	local messages = conv.m
	local first = math.max(1, #messages - limit + 1)
	if first > 1 then
		elements[1] = { kind = "older", label = "Load older messages" }
	end

	local now = GetServerTime()
	local previousDay, previous, previousSender
	local dividerPlaced = false
	local seenPosition
	for i = first, #messages do
		local message = messages[i]
		local day = date("%Y-%m-%d", message.t)
		if day ~= previousDay then
			elements[#elements + 1] = { kind = "day", label = MessageList.DayLabel(message.t, now) }
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
			outgoing = message.o == 1,
			gm = message.f == ns.Capture.FLAG_GM,
			sender = sender,
			name = AuthorOf(message, conv, key),
			raw = message.x,
			class = ClassOf(message, conv),
			mention = message.s ~= nil and message.o ~= 1 and ns.Alerts.IsMention(message.x),
			reactions = ns.Protocol.ReactionList(message.r),
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

-- Also records how wide the text really is, which sizes its bubble.
local function BodyHeight(element, width)
	if element.measuredWidth ~= width then
		measure:SetWidth(width)
		measure:SetText(element.display)
		element.bodyHeight = ReadableHeight(1)
		local textWidth = measure:GetStringWidth()
		element.bodyWidth = canaccessvalue(textWidth) and math.min(width, math.ceil(textWidth) + 2) or width
		element.measuredWidth = width
	end
	return element.bodyHeight
end

local function LineHeight()
	measure:SetWidth(200)
	measure:SetText("Xg")
	return ReadableHeight(1)
end

-- Reactions travel over whispers, so other chats have nothing to explain.
local function IsWhisper(key)
	local prefix = key and key:sub(1, 1)
	return prefix == "W" or prefix == "B"
end

-- Two people talking read best as bubbles. Busy channels keep the compact rows.
local function IsBubble(element)
	return element.kind == "message" and IsWhisper(ns.selectedKey)
end

local function BubbleTextWidth()
	local rowWidth = scrollBox:GetWidth()
	local largest = math.min(BUBBLE_MAX_WIDTH, math.floor(rowWidth * BUBBLE_MAX_SHARE),
		rowWidth - TEXT_LEFT - SIDE_PADDING - BUBBLE_TIME_ROOM)
	return largest - BUBBLE_PAD_X * 2
end

local function BubbleTop(element)
	return element.head and BUBBLE_TOP_HEAD or BUBBLE_TOP_FOLLOWING
end

local function ExtentOf(_, element)
	if IsBubble(element) then
		return BubbleTop(element) + BodyHeight(element, BubbleTextWidth()) + BUBBLE_PAD_Y * 2 + BUBBLE_BOTTOM
			+ (element.reactions and BUBBLE_REACTION_HEIGHT or 0)
	end
	if element.kind == "opener" then
		return OPENER_HEIGHT
	end
	if element.kind == "locked" then
		return HEADER_HEIGHT + LineHeight() * LOCKED_MAX_LINES + ROW_GAP
	end
	if element.kind ~= "message" then
		return LABEL_ROW_HEIGHT
	end
	local width = scrollBox:GetWidth() - TEXT_LEFT - SIDE_PADDING
	return (element.head and HEADER_HEIGHT or 0) + BodyHeight(element, width) + ROW_GAP
		+ (element.reactions and REACTION_ROW_HEIGHT or 0)
end

local function CopyConversation(key)
	local conv = ns.Store.Get(key)
	if not conv then return end
	ns.CopyBox.Show("Conversation with " .. ns.Store.LabelFor(key, conv), MessageList.ConversationText(key, conv))
end

local function ConfirmBlockPlayer(name)
	ns.Prompt.Confirm("Block " .. ns.Util.DisplayName(name) .. "? Their messages won't appear in Hangout.",
		"Block", function()
			ns.Filter.BlockPlayer(name)
			if ns.Store.Get("W:" .. name) then ns.Store.Delete("W:" .. name) end
		end)
end

local function RunWho(name)
	local filter = 'n-"' .. name .. '"'
	if C_FriendList.SendWho then
		C_FriendList.SendWho(filter)
	elseif SendWho then
		SendWho(filter)
	end
end

local function IsWhisperWith(name)
	return ns.selectedKey ~= nil and ns.selectedKey:lower() == ("W:" .. name):lower()
end

-- What can be done with another player, from their name or crest in a message.
function MessageList.PlayerMenuItems(name)
	local items = {}
	local isMe = name == ns.me
	if not isMe then
		if not IsWhisperWith(name) then
			items[#items + 1] = { label = "Whisper", action = function() ns.Window.Select(ns.Store.StartWhisper(name)) end }
		end
		items[#items + 1] = { label = "Invite to group", action = function() C_PartyInfo.InviteUnit(name) end }
		items[#items + 1] = { label = "Add friend", action = function() C_FriendList.AddFriend(name) end }
		items[#items + 1] = { label = "Who", action = function() RunWho(name) end }
	end
	items[#items + 1] = { label = "Copy name", action = function() ns.CopyBox.Show("Copy name", name) end }
	if not isMe then
		items[#items + 1] = { divider = true }
		items[#items + 1] = { label = "Block", action = function() ConfirmBlockPlayer(name) end }
	end
	return items
end

local function ShowPlayerMenu(owner, name, class)
	if not name then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(ns.Util.DisplayName(name))
		local className = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
		if className then root:CreateTitle(className) end
		for _, item in ipairs(MessageList.PlayerMenuItems(name)) do
			if item.divider then
				root:CreateDivider()
			else
				root:CreateButton(item.label, item.action)
			end
		end
	end)
end

-- Names in player: links open the same menu instead of the default chat's edit box.
local function OnHyperlinkClick(self, link, text, button)
	local playerName = link:match("^player:([^:]+)")
	-- Shift, Ctrl and Alt keep their default meanings (such as pasting the name into the chat box).
	if playerName and not IsModifierKeyDown() then
		ShowPlayerMenu(self, ns.Util.NormalizeName(playerName))
		return
	end
	SetItemRef(link, text, button, self)
end

local function OnHyperlinkEnter(self, link)
	local linkType = link:match("^(.-):")
	if not linkType or not TOOLTIP_LINKS[linkType] then return end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	-- A malformed link must not break hovering the rest of the row.
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		GameTooltip:Hide()
	end
end

local function OnHyperlinkLeave()
	GameTooltip:Hide()
end

local function AddReactionItems(root, messageId)
	root:CreateTitle("React")
	for _, emoji in ipairs(ns.Protocol.QUICK_REACTIONS) do
		local item = root:CreateCheckbox(ns.Emoji.Tag(emoji) .. "  " .. REACTION_NAMES[emoji],
			function() return ns.Protocol.HasMyReaction(ns.selectedKey, messageId, emoji) end,
			function() ns.Protocol.ToggleReaction(ns.selectedKey, messageId, emoji) end)
		item:SetResponse(MenuResponse.CloseAll)
	end
end

local function ShowReactionMenu(owner, messageId)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		AddReactionItems(root, messageId)
	end)
end

-- Says why instead of leaving the reactions out without a word.
local function AddReactionsUnavailable(root)
	local reason = ns.Lockdown.IsActive() and "Not available while chat is restricted"
		or "Only works with other Hangout users"
	root:CreateTitle("React")
	root:CreateButton(reason):SetEnabled(false)
end

local function ShowMessageMenu(owner, element)
	local key = ns.selectedKey
	MenuUtil.CreateContextMenu(owner, function(_, root)
		if ns.Protocol.CanReact(key) then
			AddReactionItems(root, element.id)
			root:CreateDivider()
		elseif IsWhisper(key) then
			AddReactionsUnavailable(root)
			root:CreateDivider()
		end
		root:CreateButton("Copy message", function()
			ns.CopyBox.Show("Copy message", ns.CopyBox.PlainText(element.raw))
		end)
		root:CreateButton("Copy conversation", function() CopyConversation(key) end)
	end)
end

local function OnRowMouseUp(self, button)
	local element = self.element
	if not element then return end
	if element.kind == "older" and button == "LeftButton" then
		visibleLimit = visibleLimit + PAGE_SIZE
		MessageList.Refresh()
	elseif element.kind == "message" and button == "RightButton" then
		ShowMessageMenu(self, element)
	end
end

local function HideToolbar()
	if toolbar then toolbar:Hide() end
	toolbarRow = nil
end

-- Sits on the outer top corner of a bubble, or at the end of a full-width row.
local function ShowToolbar(row, element)
	if not ns.Protocol.CanReact(ns.selectedKey) then return end
	toolbar:ClearAllPoints()
	if not IsBubble(element) then
		toolbar:SetPoint("TOPRIGHT", row, "TOPRIGHT", -SIDE_PADDING, TOOLBAR_RAISE)
	elseif element.outgoing then
		toolbar:SetPoint("BOTTOMRIGHT", row.bubble, "TOPRIGHT", 0, -TOOLBAR_OVERLAP)
	else
		toolbar:SetPoint("BOTTOMLEFT", row.bubble, "TOPLEFT", 0, -TOOLBAR_OVERLAP)
	end
	toolbarRow = row
	toolbar.messageId = element.id
	toolbar:Show()
end

local function CreateQuickButton(emoji, index)
	local button = CreateFrame("Button", nil, toolbar)
	button:SetSize(TOOLBAR_BUTTON_SIZE, TOOLBAR_BUTTON_SIZE)
	button:SetPoint("LEFT", TOOLBAR_PADDING + (index - 1) * TOOLBAR_BUTTON_SIZE, 0)

	local hover = ns.Widgets.RoundedFill(button, "hover", "ARTWORK")
	hover:SetAllPoints()
	hover:Hide()

	local icon = button:CreateTexture(nil, "OVERLAY")
	icon:SetSize(TOOLBAR_ICON_SIZE, TOOLBAR_ICON_SIZE)
	icon:SetPoint("CENTER")
	icon:SetTexture(ns.Emoji.ATLAS)
	icon:SetTexCoord(ns.Emoji.TexCoords(ns.Emoji.IndexOf(emoji)))

	button:SetScript("OnEnter", function(self)
		hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(REACTION_NAMES[emoji])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		hover:Hide()
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		ns.Protocol.ToggleReaction(ns.selectedKey, toolbar.messageId, emoji)
	end)
end

-- One shared bar that follows the mouse from message to message.
local function CreateToolbar(parent)
	toolbar = CreateFrame("Frame", nil, parent)
	local buttons = #QUICK_BAR + 1
	toolbar:SetSize(TOOLBAR_PADDING * 2 + buttons * TOOLBAR_BUTTON_SIZE, TOOLBAR_PADDING * 2 + TOOLBAR_BUTTON_SIZE)
	toolbar:SetFrameLevel(toolbar:GetFrameLevel() + 15)
	toolbar:EnableMouse(true)
	toolbar:Hide()

	ns.Widgets.RoundedFill(toolbar, "outline", "BACKGROUND"):SetAllPoints()
	local fill = ns.Widgets.RoundedFill(toolbar, "popup", "BORDER")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)

	for index, emoji in ipairs(QUICK_BAR) do
		CreateQuickButton(emoji, index)
	end

	local more = ns.Widgets.IconButton(toolbar, "smile", TOOLBAR_BUTTON_SIZE, 15, "More reactions")
	more:SetPoint("LEFT", TOOLBAR_PADDING + #QUICK_BAR * TOOLBAR_BUTTON_SIZE, 0)
	more:SetScript("OnClick", function()
		ShowReactionMenu(toolbarRow, toolbar.messageId)
	end)

	toolbar:SetScript("OnUpdate", function()
		local stillHovered = toolbarRow and (toolbarRow:IsMouseOver() or toolbar:IsMouseOver())
		if not stillHovered or ns.Window.IsFaded() then
			HideToolbar()
		end
	end)
end

local function PaintBubble(frame, element, isHovered)
	local token
	if element.outgoing then
		token = isHovered and "bubbleMineHover" or "bubbleMine"
	else
		token = isHovered and "bubbleTheirsHover" or "selected"
	end
	frame.bubble:SetVertexColor(ns.Theme.Color(token))
end

-- A bubble lights up by itself. Only full-width rows get the row highlight.
local function OnRowEnter(self)
	local element = self.element
	if not element or element.kind ~= "message" then return end
	if IsBubble(element) then
		PaintBubble(self, element, true)
	else
		self.hover:Show()
	end
	ShowToolbar(self, element)
end

local function OnRowLeave(self)
	self.hover:Hide()
	local element = self.element
	if element and IsBubble(element) then
		PaintBubble(self, element, false)
	end
end

local function OnNameClick(self)
	local row = self:GetParent()
	local element = row.element
	if element and element.name then
		ShowPlayerMenu(self, element.name, element.class)
	end
end

-- Stepping onto the button leaves the row, so the row's hover is kept up by hand.
local function OnNameEnter(self)
	OnRowEnter(self:GetParent())
end

local function OnNameLeave(self)
	local row = self:GetParent()
	if not row:IsMouseOver() then OnRowLeave(row) end
end

-- FontStrings and textures can't be clicked, so each gets a button over it.
local function CreateNameButton(frame)
	local button = CreateFrame("Button", nil, frame)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", OnNameClick)
	button:SetScript("OnEnter", OnNameEnter)
	button:SetScript("OnLeave", OnNameLeave)
	button:Hide()
	return button
end

local function BuildRow(frame)
	frame.crest = ns.Widgets.ClassCrest(frame, CREST_SIZE)

	frame.bubble = ns.Widgets.Rounded(frame, "BORDER")

	frame.sender = ns.Widgets.Text(frame, "HangoutFontBold", "text")
	frame.sender:SetPoint("TOPLEFT", TEXT_LEFT, -4)

	frame.gmTag = ns.Widgets.Text(frame, "HangoutFontSmallBold", "accent")
	frame.gmTag:SetText("GM")

	frame.time = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")

	frame.body = ns.Widgets.Text(frame, "HangoutMessageFont", "text")
	frame.body:SetWordWrap(true)

	frame.label = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
	frame.label:SetJustifyH("CENTER")

	frame.highlight = ns.Widgets.Fill(frame, "selected")
	frame.hover = ns.Widgets.Fill(frame, "hover")

	frame.pills = {}

	frame.openerAvatar = ns.Widgets.ChatAvatar(frame, OPENER_AVATAR_SIZE, 22)
	ns.Widgets.PlaceChatAvatar(frame.openerAvatar, "LEFT", SIDE_PADDING + 2, 0)
	frame.openerTitle = ns.Widgets.Text(frame, "HangoutFontLargeBold", "text")
	frame.openerTitle:SetPoint("TOPLEFT", SIDE_PADDING + OPENER_AVATAR_SIZE + 14, -17)
	frame.openerText = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
	frame.openerText:SetPoint("TOPLEFT", SIDE_PADDING + OPENER_AVATAR_SIZE + 14, -40)

	frame.mentionBar = ns.Widgets.Solid(frame, "accent", "ARTWORK")
	frame.mentionBar:SetPoint("TOPLEFT", 4, 0)
	frame.mentionBar:SetPoint("BOTTOMLEFT", 4, 0)
	frame.mentionBar:SetWidth(2)

	frame.senderButton = CreateNameButton(frame)
	frame.crestButton = CreateNameButton(frame)

	frame:SetHyperlinksEnabled(true)
	frame:SetScript("OnHyperlinkClick", OnHyperlinkClick)
	frame:SetScript("OnHyperlinkEnter", OnHyperlinkEnter)
	frame:SetScript("OnHyperlinkLeave", OnHyperlinkLeave)
	frame:SetScript("OnMouseUp", OnRowMouseUp)
	frame:SetScript("OnEnter", OnRowEnter)
	frame:SetScript("OnLeave", OnRowLeave)
end

-- A full-width row: crest and name on the left, with the text under the name.
local function LayoutPlainMessage(frame, element)
	local top = element.head and -HEADER_HEIGHT or 0
	frame.crest:ClearAllPoints()
	frame.crest:SetPoint("TOPLEFT", SIDE_PADDING, -4)

	frame.body:ClearAllPoints()
	frame.body:SetWidth(0)
	frame.body:SetPoint("TOPLEFT", TEXT_LEFT, top)
	frame.body:SetPoint("TOPRIGHT", -SIDE_PADDING, top)

	frame.gmTag:ClearAllPoints()
	frame.gmTag:SetPoint("LEFT", frame.sender, "RIGHT", 6, 0)
	frame.time:ClearAllPoints()
	frame.time:SetPoint("LEFT", element.gm and frame.gmTag or frame.sender, "RIGHT", 8, 0)

	if element.head then
		frame.sender:SetText(element.sender)
		frame.sender:SetTextColor(ns.Theme.ClassColor(element.class))
		frame.time:SetText(element.time)
	end
end

-- Only a plain row with a head and a known author has a name to click.
local function LayoutNameButtons(frame, element, isBubble)
	local clickable = element.kind == "message" and element.head and not isBubble and element.name ~= nil
		and not ns.Window.IsFaded()
	frame.senderButton:SetShown(clickable)
	frame.crestButton:SetShown(clickable)
	if not clickable then return end

	local width = frame.sender:GetStringWidth()
	frame.senderButton:ClearAllPoints()
	frame.senderButton:SetPoint("TOPLEFT", frame.sender, "TOPLEFT")
	frame.senderButton:SetSize(math.max(1, math.ceil(width)), NAME_BUTTON_HEIGHT)
	frame.crestButton:ClearAllPoints()
	frame.crestButton:SetAllPoints(frame.crest)
	frame.crestButton:SetShown(frame.crest:IsShown())
end

-- The other person's bubble on the left, the player's on the right. The window
-- title already names the other person, so bubbles carry no name.
local function LayoutBubble(frame, element)
	local outgoing = element.outgoing
	BodyHeight(element, BubbleTextWidth())
	local top = -BubbleTop(element)

	frame.bubble:ClearAllPoints()
	frame.bubble:SetPoint(outgoing and "TOPRIGHT" or "TOPLEFT", outgoing and -SIDE_PADDING or TEXT_LEFT, top)
	frame.bubble:SetSize(element.bodyWidth + BUBBLE_PAD_X * 2, element.bodyHeight + BUBBLE_PAD_Y * 2)
	PaintBubble(frame, element, false)

	frame.crest:ClearAllPoints()
	frame.crest:SetPoint("TOPLEFT", SIDE_PADDING, top)

	frame.body:ClearAllPoints()
	frame.body:SetWidth(element.bodyWidth)
	frame.body:SetPoint("TOPLEFT", frame.bubble, "TOPLEFT", BUBBLE_PAD_X, -BUBBLE_PAD_Y)

	frame.time:ClearAllPoints()
	if outgoing then
		frame.time:SetPoint("BOTTOMRIGHT", frame.bubble, "BOTTOMLEFT", -BUBBLE_TIME_GAP, 2)
	else
		frame.time:SetPoint("BOTTOMLEFT", frame.bubble, "BOTTOMRIGHT", BUBBLE_TIME_GAP, 2)
	end
	-- A message sent from another character still says which one.
	local timeText = outgoing and element.sender ~= "You" and (element.sender .. "  " .. element.time) or element.time
	frame.time:SetText(element.gm and ("GM  " .. timeText) or timeText)
end

local function OnPillClick(self)
	local element = self.row.element
	if element and element.id then
		ns.Protocol.ToggleReaction(ns.selectedKey, element.id, self.emoji)
	end
end

local function PillAt(frame, index)
	local pill = frame.pills[index]
	if not pill then
		pill = CreateFrame("Button", nil, frame)
		pill:SetHeight(PILL_HEIGHT)
		pill.row = frame
		pill.fill = ns.Widgets.Rounded(pill)
		pill.fill:SetAllPoints()
		pill.label = ns.Widgets.Text(pill, "HangoutFontSmall", "text")
		pill.label:SetPoint("CENTER")
		pill:SetScript("OnClick", OnPillClick)
		frame.pills[index] = pill
	end
	return pill
end

-- Reaction pills in a row under the anchor, growing away from the window's edge.
local function LayoutPills(frame, element, anchor, fromRight)
	local list = element.reactions or {}
	local canToggle = element.kind == "message" and ns.Protocol.CanReact(ns.selectedKey) and not ns.Window.IsFaded()
	for index, reaction in ipairs(list) do
		local pill = PillAt(frame, index)
		local count = tostring(reaction.count)
		pill.emoji = reaction.name
		pill:SetWidth(PILL_BASE_WIDTH + (#count - 1) * PILL_DIGIT_WIDTH)
		pill.fill:SetVertexColor(ns.Theme.Color(reaction.mine and "bubbleMine" or "selected"))
		pill.label:SetText(ns.Emoji.Tag(reaction.name) .. " " .. count)
		pill:ClearAllPoints()
		if index > 1 then
			pill:SetPoint(fromRight and "RIGHT" or "LEFT", frame.pills[index - 1], fromRight and "LEFT" or "RIGHT",
				fromRight and -PILL_GAP or PILL_GAP, 0)
		else
			pill:SetPoint(fromRight and "TOPRIGHT" or "TOPLEFT", anchor, fromRight and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -3)
		end
		pill:EnableMouse(canToggle and true or false)
		pill:Show()
	end
	for index = #list + 1, #frame.pills do
		frame.pills[index]:Hide()
	end
end

local function InitRow(frame, element)
	if not frame.body then BuildRow(frame) end
	if toolbarRow == frame then HideToolbar() end
	frame.element = element
	frame.senderButton:Hide()
	frame.crestButton:Hide()

	local isMessage = element.kind == "message"
	local isOpener = element.kind == "opener"
	ns.Widgets.ShowChatAvatar(frame.openerAvatar, isOpener and element or nil)
	frame.openerTitle:SetShown(isOpener)
	frame.openerText:SetShown(isOpener)
	local isBubble = IsBubble(element)
	frame.bubble:SetShown(isBubble)
	frame.body:SetShown(isMessage)
	frame.sender:SetShown(isMessage and element.head and not isBubble)
	frame.gmTag:SetShown(isMessage and element.head and not isBubble and element.gm)
	frame.time:SetShown(isMessage and element.head)
	local hasCrest = isMessage and element.head and not (isBubble and element.outgoing)
	ns.Widgets.SetClassCrest(frame.crest, hasCrest and element.class or nil)
	frame.label:SetShown(not isMessage and not isOpener)
	frame.mentionBar:SetShown(isMessage and element.mention)
	frame.highlight:SetShown(isMessage and element.id ~= nil and element.id == highlightId)
	frame.hover:Hide()
	frame:EnableMouse(not ns.Window.IsFaded())
	frame:SetHyperlinksEnabled(not ns.Window.IsFaded())

	if isOpener then
		LayoutPills(frame, element)
		frame.openerTitle:SetText(element.title)
		frame.openerText:SetText(element.text)
		return
	end

	if not isMessage then
		LayoutPills(frame, element)
		frame.label:ClearAllPoints()
		if element.kind == "seen" and IsWhisper(ns.selectedKey) then
			frame.label:SetPoint("RIGHT", -SIDE_PADDING, 0)
		else
			frame.label:SetPoint("CENTER")
		end
		frame.label:SetText(element.label)
		frame.label:SetTextColor(ns.Theme.Color(element.kind == "unread" and "accent" or "muted"))
		return
	end

	if isBubble then
		LayoutBubble(frame, element)
	else
		LayoutPlainMessage(frame, element)
	end
	LayoutNameButtons(frame, element, isBubble)
	frame.body:SetText(element.display)
	LayoutPills(frame, element, isBubble and frame.bubble or frame.body, isBubble and element.outgoing)
end

-- Locked rows use their own frame type so normal rows never receive a secret.
-- A FontString that has displayed a secret reports a secret size from then on,
-- so nothing here may measure these rows or anchor to their text.
local function InitLockedRow(frame, element)
	-- These rows have no click action, and must not catch clicks through a faded window.
	frame:EnableMouse(false)

	if not frame.lockedBody then
		frame.lockedMeta = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
		frame.lockedMeta:SetPoint("TOPLEFT", TEXT_LEFT, -4)

		frame.lockedBody = ns.Widgets.Text(frame, "HangoutMessageFont", "muted")
		frame.lockedBody:SetPoint("TOPLEFT", TEXT_LEFT, -HEADER_HEIGHT)
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

-- Hides a link tooltip that belongs to a message row, for when the window goes away under it.
function MessageList.HideTooltip()
	local owner = GameTooltip:GetOwner()
	if owner and owner.element ~= nil then GameTooltip:Hide() end
end

local function ResetRow(frame)
	-- A recycled row can't send OnHyperlinkLeave, so its tooltip would stay up.
	if GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
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

local JUMP_WIDTH = 140
local JUMP_RAISE = 8

-- The wording of the jump pill: plain until messages arrive while scrolled away.
function MessageList.JumpLabel(count)
	if not count or count <= 0 then return "Jump to latest" end
	if count == 1 then return "1 new message" end
	return count .. " new messages"
end

-- Whether the list sits at its end, where new messages are followed.
local function IsFollowing()
	return not scrollBox:HasScrollableExtent() or scrollBox:IsAtEnd()
end

-- Shows the pill only while the player is scrolled away from the end. Reaching
-- the end by any means also forgets the messages that were missed. The pill is
-- hidden in a faded window so it can't catch clicks meant for the game.
local function UpdateJumpButton()
	if not jumpButton then return end
	local away = not IsFollowing()
	if not away then newWhileAway = 0 end
	local show = away and not ns.Window.IsFaded()
	jumpButton:SetShown(show)
	jumpButton:EnableMouse(show)
	if show then
		jumpLabel:SetText(MessageList.JumpLabel(newWhileAway))
	end
end

local function CreateJumpButton(parent)
	jumpButton, jumpLabel = ns.Widgets.FlatButton(parent, MessageList.JumpLabel(0), JUMP_WIDTH)
	jumpButton:SetPoint("BOTTOM", scrollBox, "BOTTOM", 0, JUMP_RAISE)
	jumpButton:SetFrameLevel(jumpButton:GetFrameLevel() + 10)
	jumpButton:SetScript("OnClick", function()
		newWhileAway = 0
		scrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
		UpdateJumpButton()
	end)
	jumpButton:Hide()
	scrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, UpdateJumpButton, jumpButton)
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
	CreateToolbar(parent)
	CreateJumpButton(parent)
end

-- The first row of a chat whose whole history is on screen.
function MessageList.OpenerFor(key, conv)
	local label = ns.Store.LabelFor(key, conv)
	return {
		kind = "opener",
		key = key,
		class = conv.class,
		label = label,
		muted = conv.mute,
		title = label,
		text = IsWhisper(key) and ("This is the start of your saved history with " .. label .. ".")
			or "Your history for this chat starts here.",
	}
end

-- Rebuilds the rows, following new messages only if already at the bottom.
function MessageList.Refresh(jumpToEnd)
	if not scrollBox or not ns.selectedKey then return end

	local follow = jumpToEnd or scrollBox:IsAtEnd() or not scrollBox:HasScrollableExtent()
	local conv = ns.Store.Get(ns.selectedKey)
	local live = ns.Store.GetLive(ns.selectedKey)
	shownElements = conv and MessageList.BuildElements(conv, visibleLimit, live, unreadAfterId, ns.selectedKey) or {}
	if conv and (not shownElements[1] or shownElements[1].kind ~= "older") then
		table.insert(shownElements, 1, MessageList.OpenerFor(ns.selectedKey, conv))
	end
	scrollBox:SetDataProvider(CreateDataProvider(shownElements), ScrollBoxConstants.RetainScrollPosition)
	if follow then
		scrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
	end
	UpdateJumpButton()
end

-- Empties the list when no conversation is left to show.
local function Clear()
	unreadAfterId = nil
	highlightId = nil
	shownElements = {}
	newWhileAway = 0
	if scrollBox then
		scrollBox:SetDataProvider(CreateDataProvider(shownElements))
		UpdateJumpButton()
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
local function Show(firstUnreadAfterId, unreadCount)
	unreadAfterId = firstUnreadAfterId
	highlightId = nil
	newWhileAway = 0
	visibleLimit = math.max(PAGE_SIZE, (unreadCount or 0) + CONTEXT_ROWS)
	MessageList.Refresh(true)
	if firstUnreadAfterId then
		ScrollToFirst(function(element) return element.kind == "unread" end, ScrollBoxConstants.AlignBegin)
	end
end

-- Centers the selected chat on one message, for search results.
function MessageList.ShowAt(messageId)
	unreadAfterId = nil
	highlightId = messageId
	newWhileAway = 0

	local conv = ns.Store.Get(ns.selectedKey)
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

-- Opening the window rebuilds the list, and so does the end of a recovery, so
-- neither a closed window nor a recovered message needs a rebuild of its own.
local function RefreshIfCurrent(key, _, _, recovered)
	if key == ns.selectedKey and not recovered and ns.Window.IsVisible() then
		MessageList.Refresh()
	end
end

ns.On("SELECTION_CHANGED", function(key, firstUnreadAfterId, unreadCount)
	if key then
		Show(firstUnreadAfterId, unreadCount)
	else
		Clear()
	end
end)

-- Counts what arrives out of sight, so the jump pill can say how much was missed.
ns.On("MESSAGE_ADDED", function(key, record, mention, recovered)
	-- Your own messages are not news to you, so they never count as missed.
	if scrollBox and key == ns.selectedKey and not recovered and not (record and record.o == 1)
		and ns.Window.IsVisible() and not IsFollowing() then
		newWhileAway = newWhileAway + 1
	end
	RefreshIfCurrent(key, record, mention, recovered)
end)
ns.On("LOCKED_ADDED", RefreshIfCurrent)
ns.On("MESSAGES_CHANGED", RefreshIfCurrent)
ns.On("LIVE_CHANGED", function() MessageList.Refresh() end)
ns.On("THEME_CHANGED", function() MessageList.Refresh() end)
