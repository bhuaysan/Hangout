local _, ns = ...
local L = ns.L

-- A small card with everything Hangout knows about one person.
local ContactCard = {}
ns.ContactCard = ContactCard

local WIDTH = 320
local SIDE = 16
local HEAD_HEIGHT = 58
local AVATAR_SIZE = 46
local ROW_HEIGHT = 20
local MAX_ROWS = 8
local BUTTON_ROOM = 48
local LABEL_WIDTH = 120

local frame, avatar, nameText, subText
local rows = {}
local shownKey

local STATUS_LABEL = {
	online = L["Online"],
	afk = L["AFK"],
	dnd = L["Do Not Disturb"],
	offline = L["Offline"],
}

-- Pure: the facts to show, as a list of { label, value }, plus the headline.
function ContactCard.Info(key, conv, status, now)
	local messages = conv.m
	local sent, saved = 0, 0
	for _, message in ipairs(messages) do
		if message.o == 1 then sent = sent + 1 end
		if message.b then saved = saved + 1 end
	end

	local facts = {}
	local function add(label, value)
		if value then facts[#facts + 1] = { label = label, value = value } end
	end
	add(L["Status"], status and STATUS_LABEL[status] or nil)
	add(L["Note"], conv.note)
	add(L["Messages"], L["%d, of which %d from you"]:format(#messages, sent))
	add(L["Saved messages"], saved > 0 and tostring(saved) or nil)
	if messages[1] then
		add(L["Oldest saved message"], ns.Util.LongDate(messages[1].t, true))
		add(L["Last contact"], ns.Util.ShortTime(messages[#messages].t, now))
	end

	local real = ns.Util.DisplayName(conv.name or key:sub(3))
	return {
		title = ns.Store.LabelFor(key, conv),
		subtitle = conv.nick and real or nil,
		facts = facts,
	}
end

local function Render()
	local conv = shownKey and ns.Store.Get(shownKey)
	if not conv then
		frame:Hide()
		return
	end
	local status = ns.Identity.Status(shownKey)
	local info = ContactCard.Info(shownKey, conv, status, GetServerTime())

	ns.Widgets.ShowChatAvatar(avatar, { key = shownKey, class = conv.class, label = info.title, status = status })
	nameText:SetText(info.title)
	nameText:SetTextColor(ns.Theme.ClassColor(conv.class, "sidebar"))
	subText:SetText(info.subtitle or "")

	for index, row in ipairs(rows) do
		local fact = info.facts[index]
		row.label:SetShown(fact ~= nil)
		row.value:SetShown(fact ~= nil)
		if fact then
			row.label:SetText(fact.label)
			row.value:SetText(fact.value)
		end
	end
	frame:SetHeight(HEAD_HEIGHT + #info.facts * ROW_HEIGHT + BUTTON_ROOM + SIDE)
end

local function AddButton(text, width, anchor, onClick)
	local button = ns.Widgets.FlatButton(frame, text, width)
	if anchor then
		button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
	else
		button:SetPoint("BOTTOMRIGHT", -SIDE, 14)
	end
	button:SetScript("OnClick", onClick)
	return button
end

local function Create()
	frame = CreateFrame("Frame", "HangoutContactCard", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER")
	frame:SetWidth(WIDTH)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	-- Not in UISpecialFrames, for the same reason as the prompt.
	frame:EnableKeyboard(true)
	frame:SetScript("OnKeyDown", function(self, key)
		local safe = not InCombatLockdown()
		if key == "ESCAPE" then
			if safe then self:SetPropagateKeyboardInput(false) end
			self:Hide()
		elseif safe then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	ns.Widgets.RoundedFill(frame, "sidebar"):SetAllPoints()

	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(HEAD_HEIGHT)
	avatar = ns.Widgets.ChatAvatar(head, AVATAR_SIZE, 22)
	ns.Widgets.PlaceChatAvatar(avatar, "TOPLEFT", SIDE, -10)

	nameText = ns.Widgets.Text(head, "HangoutFontLargeBold", "text")
	nameText:SetPoint("TOPLEFT", SIDE + AVATAR_SIZE + 12, -14)
	nameText:SetPoint("TOPRIGHT", -SIDE, -14)
	nameText:SetWordWrap(false)
	subText = ns.Widgets.Text(head, "HangoutFontSmall", "muted")
	subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)

	for index = 1, MAX_ROWS do
		local top = -(HEAD_HEIGHT + (index - 1) * ROW_HEIGHT)
		local label = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
		label:SetPoint("TOPLEFT", SIDE, top)
		label:SetWidth(LABEL_WIDTH)
		label:SetWordWrap(false)
		local value = ns.Widgets.Text(frame, "HangoutFont", "text")
		value:SetPoint("TOPLEFT", SIDE + LABEL_WIDTH + 8, top + 1)
		value:SetPoint("TOPRIGHT", -SIDE, top + 1)
		value:SetWordWrap(false)
		rows[index] = { label = label, value = value }
	end

	local close = AddButton(L["Close"], 80, nil, function() frame:Hide() end)
	local whisper = AddButton(L["Whisper"], 80, close, function()
		frame:Hide()
		ns.Window.Reply(shownKey)
	end)
	AddButton(L["Edit note"], 110, whisper, function()
		local conv = ns.Store.Get(shownKey)
		if conv then ns.Sidebar.AskNote(shownKey, conv) end
	end)
end

function ContactCard.Show(key)
	if not ns.Store.Get(key) then return end
	if not frame then Create() end
	shownKey = key
	Render()
	if InCombatLockdown() then
		frame:EnableKeyboard(false)
	else
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	end
	frame:Show()
end

ns.On("CONV_CHANGED", function()
	if frame and frame:IsShown() then Render() end
end)
