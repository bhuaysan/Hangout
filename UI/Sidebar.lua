local _, ns = ...

local Sidebar = {}
ns.Sidebar = Sidebar

local HEADER_HEIGHT = 26
local COLLAPSED_HEADER_HEIGHT = 8
local ROW_HEIGHT = 48
local RESULT_ROW_HEIGHT = 42
local SEARCH_HEIGHT = 44
local SEARCH_FIELD_HEIGHT = 28
local SEARCH_TEXT_LEFT = 26
local SEARCH_ICON_SIZE = 14
local NEW_CHAT_SIZE = 28
local CREST_LEFT = 14
local CREST_SIZE = 30
local ROW_TEXT_LEFT = CREST_LEFT + CREST_SIZE + 10
local HEADER_LEFT = 14
local ROW_INSET = 8
local COLLAPSED_ROW_INSET = 4
local LIST_RIGHT_GAP = 8
local ROOM_ICON_SIZE = 16
local BADGE_HEIGHT = 16
local BADGE_BASE_WIDTH = 10
local BADGE_DIGIT_WIDTH = 6
local BADGE_ROOM = 30
local REFRESH_DELAY = 0.05
local SEARCH_DELAY = 0.25
local MIN_SEARCH_LENGTH = 2

local SECTIONS = {
	{ label = "WHISPERS", prefixes = "WBL" },
	{ label = "GROUP", prefixes = "GOPRI" },
	{ label = "CHANNELS", prefixes = "C" },
}

local scrollBox, searchHolder, searchBox, searchPlaceholder, newChatButton
local collapsed = false
local searchResults = {}

local function RowFor(entry)
	local preview, lastTime = ns.Store.LastActivity(entry.key, entry.conv)
	return {
		kind = "row",
		key = entry.key,
		label = ns.Store.LabelFor(entry.key, entry.conv),
		preview = preview or "No messages yet",
		time = lastTime and ns.Util.ShortTime(lastTime, GetServerTime()) or "",
		class = entry.conv.class,
		muted = entry.conv.mute,
		note = entry.conv.note,
		unread = ns.Store.UnreadCount(entry.key, entry.conv),
		status = ns.Identity.Status(entry.key),
	}
end

local function AddSection(elements, label, rows)
	if #rows == 0 then return end
	elements[#elements + 1] = { kind = "header", label = label }
	for _, row in ipairs(rows) do
		elements[#elements + 1] = row
	end
end

local function BuildSearchElements(list, query, results)
	local elements = {}
	local needle = query:lower()
	local rows = {}
	for _, entry in ipairs(list) do
		if ns.Store.LabelFor(entry.key, entry.conv):lower():find(needle, 1, true) then
			rows[#rows + 1] = RowFor(entry)
		end
	end
	AddSection(elements, "CHATS", rows)

	local resultRows = {}
	for _, result in ipairs(results or {}) do
		resultRows[#resultRows + 1] = {
			kind = "result",
			key = result.key,
			id = result.id,
			label = result.label,
			snippet = result.snippet,
		}
	end
	AddSection(elements, "MESSAGES", resultRows)
	return elements
end

-- list comes from Store.List, so rows keep their most-recent-first order.
function Sidebar.BuildElements(list, query, results)
	if query and query ~= "" then
		return BuildSearchElements(list, query, results)
	end

	local elements = {}
	local pinned, requests = {}, {}
	for _, entry in ipairs(list) do
		if entry.conv.req then
			requests[#requests + 1] = RowFor(entry)
		elseif entry.conv.pin then
			pinned[#pinned + 1] = RowFor(entry)
		end
	end
	AddSection(elements, "PINNED", pinned)

	for _, section in ipairs(SECTIONS) do
		local rows = {}
		for _, entry in ipairs(list) do
			if not entry.conv.pin and not entry.conv.req
				and section.prefixes:find(entry.key:sub(1, 1), 1, true) then
				rows[#rows + 1] = RowFor(entry)
			end
		end
		AddSection(elements, section.label, rows)
	end
	AddSection(elements, "REQUESTS", requests)
	return elements
end

local function ExtentOf(_, element)
	if element.kind == "header" then
		return collapsed and COLLAPSED_HEADER_HEIGHT or HEADER_HEIGHT
	end
	return element.kind == "result" and RESULT_ROW_HEIGHT or ROW_HEIGHT
end

local function AskNickname(key, conv)
	ns.Prompt.AskText("Nickname for " .. ns.Util.DisplayName(conv.name or key), conv.nick, function(text)
		ns.Store.SetField(key, "nick", ns.Util.Trim(text))
	end)
end

local function AskNote(key, conv)
	ns.Prompt.AskText("Note for " .. ns.Store.LabelFor(key, conv), conv.note, function(text)
		ns.Store.SetField(key, "note", ns.Util.Trim(text))
	end)
end

local function ConfirmBlock(key, conv)
	local label = ns.Store.LabelFor(key, conv)
	ns.Prompt.Confirm("Block " .. label .. "? Your chat is deleted and their messages won't appear in Hangout.",
		"Block", function()
			ns.Filter.BlockPlayer(key:sub(3))
			ns.Store.Delete(key)
		end)
end

local function ConfirmDelete(key, conv)
	ns.Prompt.Confirm("Delete your chat with " .. ns.Store.LabelFor(key, conv) .. "? This can't be undone.",
		"Delete", function() ns.Store.Delete(key) end)
end

local function AddPersistentItems(root, key, conv)
	root:CreateButton(conv.pin and "Unpin" or "Pin", function()
		ns.Store.SetField(key, "pin", not conv.pin or nil)
	end)
	root:CreateButton(conv.mute and "Unmute" or "Mute", function()
		ns.Store.SetField(key, "mute", not conv.mute or nil)
	end)
end

local function AddChannelItem(root, key)
	local saved = ns.Store.IsPersistent(key)
	root:CreateButton(saved and "Stop saving history" or "Save history", function()
		ns.Store.SetChannelSaved(key, not saved)
	end)
end

local function ShowRowMenu(owner, key)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local conv = ns.Store.Get(key)
		if not conv then return end
		local prefix = key:sub(1, 1)
		local persistent = ns.Store.IsPersistent(key)

		if conv.req then
			root:CreateButton("Accept", function() ns.Store.AcceptRequest(key) end)
		end
		if persistent then
			AddPersistentItems(root, key, conv)
		end
		if prefix == "W" or prefix == "B" then
			root:CreateButton("Set nickname", function() AskNickname(key, conv) end)
			root:CreateButton("Edit note", function() AskNote(key, conv) end)
		end
		if ns.CategoryOf(key) == "channel" then
			AddChannelItem(root, key)
		end
		root:CreateButton("Mark as read", function() ns.Store.MarkRead(key) end)
		if prefix == "W" then
			root:CreateButton("Block", function() ConfirmBlock(key, conv) end)
		end
		if persistent then
			root:CreateButton("Delete chat", function() ConfirmDelete(key, conv) end)
		end
	end)
end

local function OnRowClick(self, button)
	local element = self.element
	if element.kind == "result" then
		ns.Window.JumpTo(element.key, element.id)
	elseif element.kind == "row" then
		if button == "RightButton" then
			ShowRowMenu(self, element.key)
		else
			ns.Window.Select(element.key)
		end
	end
end

local function OnRowEnter(self)
	local element = self.element
	if element.kind == "header" then return end
	self.hover:Show()
	if element.note then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(element.note, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end
end

local function OnRowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function BuildRow(frame)
	frame.hover = ns.Widgets.RoundedFill(frame, "hover")
	frame.hover:Hide()
	frame.selected = ns.Widgets.RoundedFill(frame, "selected")
	frame.selected:Hide()

	frame.avatar = ns.Widgets.ChatAvatar(frame, CREST_SIZE, ROOM_ICON_SIZE)

	frame.text = ns.Widgets.Text(frame, "HangoutFont", "text")
	frame.text:SetWordWrap(false)

	frame.time = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
	frame.time:SetJustifyH("RIGHT")

	frame.snippet = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
	frame.snippet:SetWordWrap(false)

	frame.badgePill = ns.Widgets.RoundedFill(frame, "accent", "ARTWORK")
	frame.badgePill:SetHeight(BADGE_HEIGHT)
	frame.badge = ns.Widgets.Text(frame, "HangoutFontSmallBold", "panel")
	frame.badge:SetPoint("CENTER", frame.badgePill)
	frame.badge:SetJustifyH("CENTER")

	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnClick", OnRowClick)
	frame:SetScript("OnEnter", OnRowEnter)
	frame:SetScript("OnLeave", OnRowLeave)
end

local function LayoutIcons(frame, element)
	if collapsed then
		ns.Widgets.PlaceChatAvatar(frame.avatar, "CENTER")
	else
		ns.Widgets.PlaceChatAvatar(frame.avatar, "LEFT", CREST_LEFT, 0)
	end
	ns.Widgets.ShowChatAvatar(frame.avatar, element.kind == "row" and element or nil)
end

local function LayoutHighlights(frame)
	local inset = collapsed and COLLAPSED_ROW_INSET or ROW_INSET
	local rightInset = collapsed and COLLAPSED_ROW_INSET or 0
	for _, fill in ipairs({ frame.hover, frame.selected }) do
		fill:ClearAllPoints()
		fill:SetPoint("TOPLEFT", inset, -1)
		fill:SetPoint("BOTTOMRIGHT", -rightInset, 1)
	end
end

-- The name and time on top, the newest message underneath.
local function LayoutChatRow(frame, element)
	frame.time:SetPoint("TOPRIGHT", -8, -9)
	frame.text:SetPoint("TOPLEFT", ROW_TEXT_LEFT, -8)
	frame.text:SetPoint("TOPRIGHT", frame.time, "TOPLEFT", -6, 1)
	frame.snippet:SetPoint("TOPLEFT", ROW_TEXT_LEFT, -27)
	frame.snippet:SetPoint("TOPRIGHT", element.unread > 0 and -BADGE_ROOM or -8, -27)
	frame.badgePill:SetPoint("TOPRIGHT", -8, -25)
end

local function LayoutText(frame, element)
	frame.text:ClearAllPoints()
	frame.time:ClearAllPoints()
	frame.snippet:ClearAllPoints()
	frame.badgePill:ClearAllPoints()
	frame.text:SetJustifyH("LEFT")
	if element.kind == "result" then
		frame.text:SetPoint("TOPLEFT", 14, -6)
		frame.text:SetPoint("TOPRIGHT", -8, -6)
		frame.snippet:SetPoint("TOPLEFT", 14, -23)
		frame.snippet:SetPoint("TOPRIGHT", -8, -23)
	elseif element.kind == "header" then
		frame.text:SetPoint("LEFT", HEADER_LEFT, 0)
		frame.text:SetPoint("RIGHT", -8, 0)
	elseif collapsed then
		frame.text:SetPoint("CENTER")
		frame.badgePill:SetPoint("TOPRIGHT", -2, -2)
	else
		LayoutChatRow(frame, element)
	end
end

local function InitRow(frame, element)
	if not frame.text then BuildRow(frame) end
	frame.element = element

	local isRow = element.kind == "row"
	local isResult = element.kind == "result"
	frame:EnableMouse((isRow or isResult) and not ns.Window.IsFaded())
	frame.selected:SetShown(isRow and element.key == ns.selectedKey)
	frame.hover:Hide()
	LayoutHighlights(frame)
	LayoutIcons(frame, element)
	LayoutText(frame, element)

	local label = element.label
	if collapsed and not isResult then
		label = ""
	end
	frame.text:SetText(label)
	ns.Widgets.SetTextFont(frame.text, (isRow or isResult) and "HangoutFont" or "HangoutFontSmall")
	if isRow and not element.muted then
		local overlay = element.key == ns.selectedKey and "selected" or nil
		frame.text:SetTextColor(ns.Theme.ClassColor(element.class, "sidebar", overlay))
	elseif isResult then
		frame.text:SetTextColor(ns.Theme.Color("text"))
	else
		frame.text:SetTextColor(ns.Theme.Color("muted"))
	end

	local showsPreview = isRow and not collapsed
	frame.time:SetShown(showsPreview)
	frame.snippet:SetShown(isResult or showsPreview)
	if isResult then
		frame.snippet:SetText(element.snippet)
		frame.snippet:SetTextColor(ns.Theme.Color("muted"))
	elseif showsPreview then
		frame.time:SetText(element.time)
		frame.snippet:SetText(element.preview)
		frame.snippet:SetTextColor(ns.Theme.Color(element.unread > 0 and "text" or "muted"))
	end

	local unread = isRow and element.unread or 0
	frame.badge:SetShown(unread > 0)
	frame.badgePill:SetShown(unread > 0)
	if unread > 0 then
		local text = tostring(ns.Util.BadgeText(unread))
		frame.badge:SetText(text)
		frame.badgePill:SetWidth(BADGE_BASE_WIDTH + #text * BADGE_DIGIT_WIDTH)
	end
end

local function CurrentQuery()
	return searchBox and ns.Util.Trim(searchBox:GetText()) or ""
end

function Sidebar.Refresh()
	if not scrollBox then return end
	local elements = Sidebar.BuildElements(ns.Store.List(), CurrentQuery(), searchResults)
	scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
end

local function RunSearch()
	local query = CurrentQuery()
	searchResults = {}
	if #query < MIN_SEARCH_LENGTH then
		ns.Search.Cancel()
		Sidebar.Refresh()
		return
	end
	ns.Search.Run(query, function(results)
		searchResults = results
		Sidebar.Refresh()
	end)
end

local runSearchSoon = ns.Util.Debounced(SEARCH_DELAY, RunSearch)

local function UpdateSearchPlaceholder()
	searchPlaceholder:SetShown(searchBox:GetText() == "" and not searchBox:HasFocus())
end

local function CreateSearchBox(parent)
	local field
	searchHolder, field = ns.Widgets.Field(parent, 1)
	searchHolder:SetPoint("TOPLEFT", 8, -8)
	searchHolder:SetPoint("TOPRIGHT", -(8 + NEW_CHAT_SIZE + 4), -8)
	searchHolder:SetHeight(SEARCH_FIELD_HEIGHT)
	field:SetPoint("TOPLEFT", SEARCH_TEXT_LEFT, 0)
	searchBox = field

	ns.Widgets.Icon(searchHolder, "search", SEARCH_ICON_SIZE, "muted"):SetPoint("LEFT", 7, 0)

	searchPlaceholder = ns.Widgets.Text(searchHolder, "HangoutFontSmall", "muted")
	searchPlaceholder:SetPoint("LEFT", SEARCH_TEXT_LEFT, 0)
	searchPlaceholder:SetText("Search")

	searchBox:SetScript("OnTextChanged", function()
		UpdateSearchPlaceholder()
		Sidebar.Refresh()
		runSearchSoon()
	end)
	searchBox:SetScript("OnEditFocusGained", UpdateSearchPlaceholder)
	searchBox:SetScript("OnEditFocusLost", UpdateSearchPlaceholder)
	searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
end

local function StartWhisper(text)
	local key = ns.Store.StartWhisper(text)
	if key then ns.Window.Reply(key) end
end

local function CreateNewChatButton(parent)
	newChatButton = ns.Widgets.IconButton(parent, "plus", NEW_CHAT_SIZE, 15, "New whisper")
	newChatButton:SetPoint("TOPRIGHT", -8, -8)
	ns.Widgets.RoundedFill(newChatButton, "selected"):SetAllPoints()
	newChatButton:SetScript("OnClick", function()
		ns.Prompt.AskText("Who do you want to whisper? Enter their full name.", "", StartWhisper, "Start")
	end)
end

function Sidebar.Create(parent)
	CreateSearchBox(parent)
	CreateNewChatButton(parent)
	ns.ProfileBar.Create(parent)

	local view = CreateScrollBoxListLinearView(4, 8, 0, 0, 0)
	view:SetElementInitializer("Button", InitRow)
	view:SetElementExtentCalculator(ExtentOf)

	local scrollBar
	scrollBox, scrollBar = ns.Widgets.ScrollList(parent, view)
	scrollBar:SetPoint("TOPRIGHT", -2, -SEARCH_HEIGHT)
	scrollBar:SetPoint("BOTTOMRIGHT", -2, ns.ProfileBar.HEIGHT + 4)
	scrollBox:SetPoint("TOPLEFT", 0, -SEARCH_HEIGHT)
	scrollBox:SetPoint("BOTTOMRIGHT", -LIST_RIGHT_GAP, ns.ProfileBar.HEIGHT)
end

function Sidebar.SetCollapsed(isCollapsed)
	collapsed = isCollapsed
	searchHolder:SetShown(not collapsed)
	newChatButton:SetShown(not collapsed)
	if collapsed then searchBox:SetText("") end
	scrollBox:SetPoint("TOPLEFT", 0, collapsed and 0 or -SEARCH_HEIGHT)
	scrollBox:SetPoint("BOTTOMRIGHT", collapsed and 0 or -LIST_RIGHT_GAP, ns.ProfileBar.HEIGHT)
	ns.ProfileBar.SetCollapsed(collapsed)
	Sidebar.Refresh()
end

function Sidebar.ClearSearchFocus()
	if searchBox then searchBox:ClearFocus() end
end

-- Opening the window refreshes the sidebar, so a closed one can skip this.
local refreshSoon = ns.Util.Debounced(REFRESH_DELAY, function()
	if ns.Window.IsVisible() then Sidebar.Refresh() end
end)

ns.On("SELECTION_CHANGED", function() Sidebar.Refresh() end)

for _, message in ipairs({ "MESSAGE_ADDED", "LOCKED_ADDED", "LIVE_CHANGED", "CONV_CHANGED", "THEME_CHANGED" }) do
	ns.On(message, refreshSoon)
end
