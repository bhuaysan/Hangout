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

local box, placeholder, fieldBorder

local function UpdatePlaceholder()
	placeholder:SetShown(box:GetText() == "" and not box:HasFocus())
end

-- In a game the same keys cast spells, so typing must be obvious at a glance.
local function UpdateFocus()
	UpdatePlaceholder()
	fieldBorder:SetShown(box:HasFocus())
end

local function OnTextChanged(_, userInput)
	UpdatePlaceholder()
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
	local ok, reason = ns.Send.Text(ns.selectedKey, self:GetText())
	if ok then
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
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnTextChanged", OnTextChanged)
	box:SetScript("OnEditFocusGained", UpdateFocus)
	box:SetScript("OnEditFocusLost", UpdateFocus)

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
	box:SetText(conv and conv.draft or "")
end)
