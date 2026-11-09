local _, ns = ...

local EmojiPicker = {}
ns.EmojiPicker = EmojiPicker

local COLUMNS = 14
local GRID_ROWS = 6
local CELL = 28
local ICON = 22
local PADDING = 8
local BAR_HEIGHT = 24
local GAP = 4
local TAB_LINE_HEIGHT = 2

-- How many emoji can be on show at once.
EmojiPicker.CAPACITY = COLUMNS * GRID_ROWS

local panel, searchBox, searchPlaceholder, emptyText
local cells = {}
local tabs = {}
local activeGroup = 1

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(":" .. self.name .. ":")
	GameTooltip:Show()
end

local function OnEmojiClick(self)
	ns.Composer.Insert(":" .. self.name .. ": ")
	panel:Hide()
end

local function CurrentQuery()
	return ns.Util.Trim(searchBox:GetText())
end

local function ShowEmoji(names)
	for index, cell in ipairs(cells) do
		local name = names[index]
		cell:SetShown(name ~= nil)
		if name then
			cell.name = name
			cell.texture:SetTexCoord(ns.Emoji.TexCoords(ns.Emoji.IndexOf(name)))
		end
	end
	emptyText:SetShown(#names == 0)
end

local function PaintTabs(isSearching)
	for index, tab in ipairs(tabs) do
		local isActive = not isSearching and index == activeGroup
		tab.line:SetShown(isActive)
		tab.label:SetTextColor(ns.Theme.Color(isActive and "accent" or "muted"))
	end
end

local function Refresh()
	local query = CurrentQuery()
	local isSearching = query ~= ""
	ShowEmoji(isSearching and ns.Emoji.Search(query) or ns.Emoji.GROUPS[activeGroup].names)
	PaintTabs(isSearching)
end

local function CreateSearch()
	local holder
	holder, searchBox = ns.Widgets.Field(panel, 1)
	holder:SetHeight(BAR_HEIGHT)
	holder:SetPoint("TOPLEFT", PADDING, -PADDING)
	holder:SetPoint("TOPRIGHT", -PADDING, -PADDING)

	searchPlaceholder = ns.Widgets.Text(holder, "HangoutFontSmall", "muted")
	searchPlaceholder:SetPoint("LEFT", 6, 0)
	searchPlaceholder:SetText("Search emoji")

	local function updatePlaceholder()
		searchPlaceholder:SetShown(searchBox:GetText() == "" and not searchBox:HasFocus())
	end
	searchBox:SetScript("OnTextChanged", function()
		updatePlaceholder()
		Refresh()
	end)
	searchBox:SetScript("OnEditFocusGained", updatePlaceholder)
	searchBox:SetScript("OnEditFocusLost", updatePlaceholder)
	searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
end

local function CreateTabs(top)
	local groups = ns.Emoji.GROUPS
	local width = COLUMNS * CELL / #groups
	for index, group in ipairs(groups) do
		local button, label = ns.Widgets.TextButton(panel, group.label, "HangoutFontSmall")
		button:SetSize(width, BAR_HEIGHT)
		button:SetPoint("TOPLEFT", PADDING + (index - 1) * width, top)
		-- The hover color must not stick to the tab that is selected.
		button:HookScript("OnLeave", Refresh)
		button:SetScript("OnClick", function()
			activeGroup = index
			searchBox:SetText("")
			searchBox:ClearFocus()
			Refresh()
		end)

		local line = ns.Widgets.Solid(button, "accent", "ARTWORK")
		line:SetPoint("BOTTOMLEFT")
		line:SetPoint("BOTTOMRIGHT")
		line:SetHeight(TAB_LINE_HEIGHT)
		tabs[index] = { label = label, line = line }
	end
end

local function CreateCell(index, top)
	local button = CreateFrame("Button", nil, panel)
	button:SetSize(CELL, CELL)
	local column = (index - 1) % COLUMNS
	local row = math.floor((index - 1) / COLUMNS)
	button:SetPoint("TOPLEFT", PADDING + column * CELL, top - row * CELL)

	button.texture = button:CreateTexture(nil, "ARTWORK")
	button.texture:SetSize(ICON, ICON)
	button.texture:SetPoint("CENTER")
	button.texture:SetTexture(ns.Emoji.ATLAS)

	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", OnEmojiClick)
	return button
end

local function Create(anchor)
	local tabsTop = -(PADDING + BAR_HEIGHT + GAP)
	local gridTop = tabsTop - BAR_HEIGHT - GAP

	panel = CreateFrame("Frame", nil, anchor)
	panel:SetSize(COLUMNS * CELL + PADDING * 2, -gridTop + GRID_ROWS * CELL + PADDING)
	panel:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -8, 4)
	panel:SetFrameLevel(anchor:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	ns.Widgets.RoundedFill(panel, "popup"):SetAllPoints()

	CreateSearch()
	CreateTabs(tabsTop)
	for index = 1, EmojiPicker.CAPACITY do
		cells[index] = CreateCell(index, gridTop)
	end

	emptyText = ns.Widgets.Text(panel, "HangoutFont", "muted")
	emptyText:SetPoint("CENTER", 0, gridTop / 2)
	emptyText:SetText("No emoji match that search.")

	-- A hidden search box must never keep hold of the keyboard.
	panel:SetScript("OnHide", function()
		if searchBox:HasFocus() then searchBox:ClearFocus() end
		searchBox:SetText("")
	end)
	Refresh()
end

function EmojiPicker.Toggle(anchor)
	if not panel then Create(anchor) end
	panel:SetShown(not panel:IsShown())
end

function EmojiPicker.Hide()
	if panel then panel:Hide() end
end

ns.On("THEME_CHANGED", function()
	if panel then Refresh() end
end)
