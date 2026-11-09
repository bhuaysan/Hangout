local _, ns = ...

local Composer = {}
ns.Composer = Composer

local MAX_TOTAL_BYTES = 1020

local REASON_TEXT = {
	restricted = "Chat is restricted right now, so Hangout can't send this. Your text is still here. For something urgent, use normal chat.",
	tooLong = "That message is too long to send.",
	slash = "Slash commands only work in normal chat.",
	unavailable = "This conversation can't receive messages right now.",
}

local FIELD_SIDE = 14
local FIELD_TOP = 8
local FIELD_BOTTOM = 12

local ROW_HEIGHT = 22
local POPUP_WIDTH = 220
local POPUP_PADDING = 4

local box, placeholder, fieldBorder
local popup
local popupRows = {}
-- The shortcode suggestions on show, the highlighted row and the partial they were built for.
local suggestions, selected, suggestedFor = {}, 1, nil
-- The name being cycled with Tab: where the word starts, the options and the one inserted.
local tabState

local function UpdatePlaceholder()
	placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
end

-- In a game the same keys cast spells, so typing must be obvious at a glance.
local function UpdateFocus()
	UpdatePlaceholder()
	fieldBorder:SetShown(box:HasFocus())
end

local function HidePopup()
	suggestedFor = nil
	suggestions = {}
	if popup then popup:Hide() end
end

function Composer.HidePopup()
	HidePopup()
end

local function PaintPopup()
	for index, row in ipairs(popupRows) do
		local name = suggestions[index]
		row:SetShown(name ~= nil)
		if name then
			row.name = name
			row.icon:SetTexCoord(ns.Emoji.TexCoords(ns.Emoji.IndexOf(name)))
			row.label:SetText(":" .. name .. ":")
			row.highlight:SetShown(index == selected)
		end
	end
	popup:SetHeight(#suggestions * ROW_HEIGHT + POPUP_PADDING * 2)
end

-- Shows suggestions while the cursor sits right behind a ":partial".
local function UpdatePopup()
	if not popup then return end
	local text = box:GetText()
	local start, partial = ns.Complete.ShortcodeAt(text, box:GetCursorPosition())
	-- Browsing history must keep Up and Down for itself.
	if not start or not box:HasFocus() or ns.History.IsBrowsing() then
		HidePopup()
		return
	end
	if partial ~= suggestedFor then
		suggestedFor = partial
		suggestions = ns.Complete.ShortcodeMatches(partial)
		selected = 1
	end
	if #suggestions == 0 then
		popup:Hide()
		return
	end
	PaintPopup()
	popup:Show()
end

local function AcceptSuggestion(name)
	local text = box:GetText()
	local cursor = box:GetCursorPosition()
	local start = ns.Complete.ShortcodeAt(text, cursor)
	-- Without a shortcode behind the cursor there is nothing to accept; close the popup so Enter sends.
	if not start or not name then
		HidePopup()
		return false
	end
	local tail = text:sub(ns.Complete.CharToByte(text, cursor) + 1)
	-- Word characters right after the cursor belong to the same shortcode, as in ":sm|ile".
	tail = tail:gsub("^[%w_]*", "")
	local head = text:sub(1, start - 1) .. ":" .. name .. ": "
	box:SetText(head .. tail)
	box:SetCursorPosition(ns.Complete.CharCount(head))
	HidePopup()
	box:SetFocus()
end

local function MoveSelection(step)
	selected = (selected - 1 + step) % #suggestions + 1
	PaintPopup()
end

local function OnTabPressed()
	if popup and popup:IsVisible() then
		AcceptSuggestion(suggestions[selected])
		return
	end
	local conv = ns.selectedKey and ns.Store.Get(ns.selectedKey)
	if not conv then return end

	local text = box:GetText()
	local position = ns.Complete.CharToByte(text, box:GetCursorPosition())
	local before = text:sub(1, position)

	-- A second Tab right after a completion moves on to the next candidate for the same prefix.
	if tabState and before:sub(tabState.start) == tabState.list[tabState.index] then
		tabState.index = tabState.index % #tabState.list + 1
	else
		local start, word = before:match("()(%S+)$")
		if not start then tabState = nil return end
		local list = ns.Complete.Names(conv, word)
		if #list == 0 then tabState = nil return end
		tabState = { start = start, list = list, index = 1 }
	end

	local head = before:sub(1, tabState.start - 1) .. tabState.list[tabState.index]
	box:SetText(head .. text:sub(position + 1))
	box:SetCursorPosition(ns.Complete.CharCount(head))
end

local function OnKeyDown(self, key)
	if ns.Keys and ns.Keys.OnComposerKey and ns.Keys.OnComposerKey(self, key) then return end

	if popup and popup:IsVisible() then
		if key == "UP" then MoveSelection(-1) return end
		if key == "DOWN" then MoveSelection(1) return end
		return
	end

	local text = self:GetText()
	if key == "UP" then
		if ns.History.IsBrowsing() or text == "" or self:GetCursorPosition() == 0 then
			local older = ns.History.Older(text)
			if older then
				self:SetText(older)
				self:SetCursorPosition(ns.Complete.CharCount(older))
			end
		end
	elseif key == "DOWN" and ns.History.IsBrowsing() then
		local newer = ns.History.Newer()
		if newer then
			self:SetText(newer)
			self:SetCursorPosition(ns.Complete.CharCount(newer))
		end
	end
end

local function OnEscapePressed(self)
	if popup and popup:IsVisible() then
		HidePopup()
	else
		self:ClearFocus()
	end
end

local function OnTextChanged(_, userInput)
	UpdatePlaceholder()
	if userInput then
		ns.History.Reset()
		tabState = nil
	end
	UpdatePopup()
	local conv = ns.selectedKey and ns.Store.Get(ns.selectedKey)
	if not conv then return end

	local text = box:GetText()
	conv.draft = text ~= "" and text or nil
	if userInput and text ~= "" and text:sub(1, 1) ~= "/" then
		ns.Protocol.NotifyTyping(ns.selectedKey)
	end
end

local function OnEnterPressed(self)
	if not ns.selectedKey then return end
	if popup and popup:IsVisible() then
		AcceptSuggestion(suggestions[selected])
		return
	end
	local text = self:GetText()
	local ok, reason = ns.Send.Text(ns.selectedKey, text)
	if ok then
		ns.History.Push(text)
		self:SetText("")
	elseif reason == "empty" then
		self:ClearFocus()
	else
		ns.Print(REASON_TEXT[reason])
	end
end

local function CreateEmojiButton(parent, field)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(22, 22)
	button:SetPoint("RIGHT", field, "RIGHT", -8, 0)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(ns.Emoji.ATLAS)
	icon:SetTexCoord(ns.Emoji.TexCoords(1))
	button:SetAlpha(0.7)
	button:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
	button:SetScript("OnLeave", function(self) self:SetAlpha(0.7) end)
	button:SetScript("OnClick", function() ns.EmojiPicker.Toggle(parent) end)
end

local function CreateRow(index)
	local row = CreateFrame("Button", nil, popup)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", POPUP_PADDING, -POPUP_PADDING - (index - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", -POPUP_PADDING, -POPUP_PADDING - (index - 1) * ROW_HEIGHT)
	row.highlight = ns.Widgets.Solid(row, "selected", "BACKGROUND")
	row.highlight:SetAllPoints()
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 4, 0)
	row.icon:SetTexture(ns.Emoji.ATLAS)
	row.label = ns.Widgets.Text(row, "HangoutFont", "text")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row:SetScript("OnClick", function(self) AcceptSuggestion(self.name) end)
	return row
end

local function CreatePopup(parent, field)
	popup = CreateFrame("Frame", nil, parent)
	popup:SetWidth(POPUP_WIDTH)
	popup:SetPoint("BOTTOMLEFT", field, "TOPLEFT", 0, 4)
	popup:SetFrameLevel(parent:GetFrameLevel() + 20)
	popup:EnableMouse(true)
	popup:Hide()
	ns.Widgets.RoundedFill(popup, "popup"):SetAllPoints()
	for index = 1, 8 do
		popupRows[index] = CreateRow(index)
	end
end

function Composer.Create(parent)
	-- The gold shows around the field's edge only while typing.
	fieldBorder = ns.Widgets.RoundedFill(parent, "accent", "BORDER")
	fieldBorder:SetPoint("TOPLEFT", FIELD_SIDE, -FIELD_TOP)
	fieldBorder:SetPoint("BOTTOMRIGHT", -FIELD_SIDE, FIELD_BOTTOM)
	fieldBorder:Hide()

	local field = ns.Widgets.RoundedFill(parent, "fieldSolid", "ARTWORK")
	field:SetPoint("TOPLEFT", fieldBorder, "TOPLEFT", 1, -1)
	field:SetPoint("BOTTOMRIGHT", fieldBorder, "BOTTOMRIGHT", -1, 1)

	box = CreateFrame("EditBox", nil, parent)
	box:SetPoint("TOPLEFT", field, "TOPLEFT", 12, 0)
	box:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -38, 0)
	box:SetFontObject(HangoutMessageFont)
	box:SetTextColor(ns.Theme.Color("text"))
	CreateEmojiButton(parent, field)
	box:SetAutoFocus(false)
	box:SetMaxBytes(MAX_TOTAL_BYTES)

	box:SetScript("OnEnterPressed", OnEnterPressed)
	box:SetScript("OnEscapePressed", OnEscapePressed)
	box:SetScript("OnTabPressed", OnTabPressed)
	box:SetScript("OnKeyDown", OnKeyDown)
	box:SetScript("OnTextChanged", OnTextChanged)
	box:SetScript("OnCursorChanged", UpdatePopup)
	box:SetScript("OnEditFocusGained", UpdateFocus)
	box:SetScript("OnEditFocusLost", function()
		UpdateFocus()
		HidePopup()
	end)
	CreatePopup(parent, field)

	placeholder = ns.Widgets.Text(box, "HangoutMessageFont", "muted")
	placeholder:SetPoint("LEFT")
	placeholder:SetText("Message...")

	hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
		if canaccessvalue(link) and link and box:HasFocus() then
			box:Insert(link)
		end
	end)
end

local function UpdateHint()
	if not placeholder then return end
	if not ns.selectedKey then
		placeholder:SetText("Pick a chat to start typing.")
	elseif ns.Lockdown.IsActive() then
		placeholder:SetText("Restricted right now. Use normal chat to reply.")
	elseif ns.selectedKey == ns.Capture.LOCKED_KEY then
		placeholder:SetText("Use normal chat to reply to these messages.")
	else
		local conv = ns.Store.Get(ns.selectedKey)
		placeholder:SetText("Message " .. (conv and ns.Store.LabelFor(ns.selectedKey, conv) or "..."))
	end
end

function Composer.ClearFocus()
	if box then box:ClearFocus() end
end

-- Waits a frame so the key that asked for this isn't typed into the box.
function Composer.Focus()
	C_Timer.After(0, function()
		if box and ns.selectedKey then box:SetFocus() end
	end)
end

function Composer.Insert(text)
	box:Insert(text)
	box:SetFocus()
end

ns.On("THEME_CHANGED", function()
	if box then box:SetTextColor(ns.Theme.Color("text")) end
end)

ns.On("LOCKDOWN_CHANGED", UpdateHint)

ns.On("SELECTION_CHANGED", function(key)
	UpdateHint()
	local conv = key and ns.Store.Get(key)
	ns.History.Reset()
	tabState = nil
	HidePopup()
	box:SetText(conv and conv.draft or "")
	-- A draft ending in ":smi" would otherwise open the popup on switching chats.
	HidePopup()
end)
ns.On("WINDOW_HIDDEN", HidePopup)
