local _, ns = ...

local Sidebar = {}
ns.Sidebar = Sidebar

local HEADER_HEIGHT = 26
local COLLAPSED_HEADER_HEIGHT = 8
local ROW_HEIGHT = 28
local RESULT_ROW_HEIGHT = 42
local SEARCH_HEIGHT = 34
local NEW_CHAT_SIZE = 22
local CREST_LEFT = 8
local CREST_SIZE = 20
local PLAIN_TEXT_LEFT = 12
local PERSON_TEXT_LEFT = CREST_LEFT + CREST_SIZE + 6
local REFRESH_DELAY = 0.05
local SEARCH_DELAY = 0.25
local MIN_SEARCH_LENGTH = 2

local SECTIONS = {
	{ label = "WHISPERS", prefixes = "WBL" },
	{ label = "GROUP", prefixes = "GOPRI" },
	{ label = "CHANNELS", prefixes = "C" },
}

local STATUS_ICON = {
	[true] = "Interface\\FriendsFrame\\StatusIcon-Online",
	[false] = "Interface\\FriendsFrame\\StatusIcon-Offline",
}

local scrollBox, searchHolder, searchBox, searchPlaceholder, newChatButton
local collapsed = false
local searchResults = {}

local function RowFor(entry)
	return {
		kind = "row",
		key = entry.key,
		label = ns.Store.LabelFor(entry.key, entry.conv),
		class = entry.conv.class,
		muted = entry.conv.mute,
		note = entry.conv.note,
		unread = ns.Store.UnreadCount(entry.key, entry.conv),
		presence = ns.Identity.Presence(entry.key),
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
	frame.hover = ns.Widgets.Fill(frame, "hover")
	frame.hover:Hide()
	frame.selected = ns.Widgets.Fill(frame, "selected")
	frame.selected:Hide()

	frame.crest = frame:CreateTexture(nil, "ARTWORK")
	frame.crest:SetSize(CREST_SIZE, CREST_SIZE)

	frame.status = frame:CreateTexture(nil, "OVERLAY")

	frame.text = ns.Widgets.Text(frame, "GameFontHighlight", "text")
	frame.text:SetWordWrap(false)

	frame.snippet = ns.Widgets.Text(frame, "GameFontDisableSmall", "muted")
	frame.snippet:SetPoint("TOPLEFT", 12, -23)
	frame.snippet:SetPoint("TOPRIGHT", -8, -23)
	frame.snippet:SetWordWrap(false)

	frame.badge = ns.Widgets.Text(frame, "GameFontNormalSmall", "accent")
	frame.badge:SetJustifyH("RIGHT")

	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:SetScript("OnClick", OnRowClick)
	frame:SetScript("OnEnter", OnRowEnter)
	frame:SetScript("OnLeave", OnRowLeave)
end

-- Shows the class crest with the online dot on its corner, or the dot alone if
-- the class isn't known. Returns whether a crest is showing.
local function LayoutIcons(frame, element)
	local isRow = element.kind == "row"
	local hasCrest = ns.Widgets.SetClassCrest(frame.crest, isRow and element.class or nil)
	frame.crest:SetDesaturated(hasCrest and element.muted and true or false)
	frame.crest:ClearAllPoints()
	if collapsed then
		frame.crest:SetPoint("CENTER")
	else
		frame.crest:SetPoint("LEFT", CREST_LEFT, 0)
	end

	local hasStatus = isRow and element.presence ~= nil and not collapsed
	frame.status:SetShown(hasStatus)
	if hasStatus then
		frame.status:SetTexture(STATUS_ICON[element.presence])
		frame.status:ClearAllPoints()
		if hasCrest then
			frame.status:SetSize(12, 12)
			frame.status:SetPoint("CENTER", frame.crest, "BOTTOMRIGHT", -2, 2)
		else
			frame.status:SetSize(14, 14)
			frame.status:SetPoint("LEFT", CREST_LEFT + 3, 0)
		end
	end
	return hasCrest
end

-- People line up in one column whether or not their class is known yet.
local function TextLeftFor(element)
	local prefix = element.key and element.key:sub(1, 1)
	return (prefix == "W" or prefix == "B") and PERSON_TEXT_LEFT or PLAIN_TEXT_LEFT
end

local function LayoutText(frame, element)
	frame.text:ClearAllPoints()
	frame.badge:ClearAllPoints()
	if element.kind == "result" then
		frame.text:SetPoint("TOPLEFT", 12, -6)
		frame.text:SetPoint("TOPRIGHT", -8, -6)
		frame.text:SetJustifyH("LEFT")
	elseif collapsed then
		frame.text:SetPoint("CENTER")
		frame.text:SetJustifyH("CENTER")
		frame.badge:SetPoint("TOPRIGHT", -2, -2)
	else
		frame.text:SetPoint("LEFT", TextLeftFor(element), 0)
		frame.text:SetPoint("RIGHT", -30, 0)
		frame.text:SetJustifyH("LEFT")
		frame.badge:SetPoint("RIGHT", -8, 0)
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
	local hasCrest = LayoutIcons(frame, element)
	LayoutText(frame, element)

	local label = element.label
	if collapsed and not isResult then
		label = isRow and not hasCrest and ns.Util.FirstCharacter(label) or ""
	end
	frame.text:SetText(label)
	frame.text:SetFontObject((isRow or isResult) and "GameFontHighlight" or "GameFontDisableSmall")
	if isRow and not element.muted then
		local overlay = element.key == ns.selectedKey and "selected" or nil
		frame.text:SetTextColor(ns.Theme.ClassColor(element.class, "sidebar", overlay))
	elseif isResult then
		frame.text:SetTextColor(ns.Theme.Color("text"))
	else
		frame.text:SetTextColor(ns.Theme.Color("muted"))
	end

	frame.snippet:SetShown(isResult)
	if isResult then frame.snippet:SetText(element.snippet) end

	local unread = isRow and element.unread or 0
	frame.badge:SetShown(unread > 0)
	if unread > 0 then
		frame.badge:SetText(ns.Util.BadgeText(unread))
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
	searchBox = field

	searchPlaceholder = ns.Widgets.Text(searchHolder, "GameFontDisableSmall", "muted")
	searchPlaceholder:SetPoint("LEFT", 6, 0)
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
	newChatButton = ns.Widgets.TextButton(parent, "+", "GameFontHighlightLarge")
	newChatButton:SetSize(NEW_CHAT_SIZE, NEW_CHAT_SIZE)
	newChatButton:SetPoint("TOPRIGHT", -8, -8)
	ns.Widgets.Fill(newChatButton, "selected")
	newChatButton:SetScript("OnClick", function()
		ns.Prompt.AskText("Who do you want to whisper? Enter their full name.", "", StartWhisper, "Start")
	end)
	newChatButton:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("New whisper")
		GameTooltip:Show()
	end)
	newChatButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function Sidebar.Create(parent)
	CreateSearchBox(parent)
	CreateNewChatButton(parent)

	local view = CreateScrollBoxListLinearView(4, 8, 0, 0, 0)
	view:SetElementInitializer("Button", InitRow)
	view:SetElementExtentCalculator(ExtentOf)

	local scrollBar
	scrollBox, scrollBar = ns.Widgets.ScrollList(parent, view)
	scrollBar:SetPoint("TOPRIGHT", -2, -SEARCH_HEIGHT)
	scrollBar:SetPoint("BOTTOMRIGHT", -2, 4)
	scrollBox:SetPoint("TOPLEFT", 0, -SEARCH_HEIGHT)
	scrollBox:SetPoint("BOTTOMRIGHT", -12, 0)
end

function Sidebar.SetCollapsed(isCollapsed)
	collapsed = isCollapsed
	searchHolder:SetShown(not collapsed)
	newChatButton:SetShown(not collapsed)
	if collapsed then searchBox:SetText("") end
	scrollBox:SetPoint("TOPLEFT", 0, collapsed and 0 or -SEARCH_HEIGHT)
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
