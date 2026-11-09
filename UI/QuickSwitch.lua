local _, ns = ...
local L = ns.L

local QuickSwitch = {}
ns.QuickSwitch = QuickSwitch

local WIDTH = 360
local PADDING = 12
local FIELD_HEIGHT = 28
local ROW_HEIGHT = 40
local MAX_ROWS = 8
local CREST_SIZE = 26
local ROOM_ICON_SIZE = 14
local ROW_INSET = 4

local HINT_BY_PREFIX = {
	W = L["Whisper"],
	B = L["Battle.net"],
	G = L["Guild"],
	O = L["Officer"],
	P = L["Party"],
	R = L["Raid"],
	I = L["Instance"],
	C = L["Channel"],
	L = L["Restricted"],
}

function QuickSwitch.Hint(key)
	return HINT_BY_PREFIX[key:sub(1, 1)] or L["Chat"]
end

-- Ranks chats for a typed query and returns their keys. Matches the label, the raw name
-- and the nickname, case-insensitively; names that start with the query beat names that
-- merely contain it, and ties keep the list's most-recent-first order. An empty query
-- puts unread chats first. Requests are never offered.
function QuickSwitch.Rank(list, query)
	local needle = (query or ""):lower()
	local first, second = {}, {}
	for _, entry in ipairs(list) do
		local conv = entry.conv
		if not conv.req then
			if needle == "" then
				local unread = ns.Store.UnreadCount(entry.key, conv) > 0
				local bucket = unread and first or second
				bucket[#bucket + 1] = entry.key
			else
				local best
				local names = { ns.Store.LabelFor(entry.key, conv), conv.name or entry.key:sub(3), conv.nick }
				for _, name in pairs(names) do
					local at = name:lower():find(needle, 1, true)
					if at == 1 then
						best = 1
					elseif at and best ~= 1 then
						best = 2
					end
				end
				if best == 1 then
					first[#first + 1] = entry.key
				elseif best == 2 then
					second[#second + 1] = entry.key
				end
			end
		end
	end
	for _, key in ipairs(second) do
		first[#first + 1] = key
	end
	return first
end

-- The name to offer a fresh whisper to when the query reads like "First Last" and no
-- whisper with that name exists yet. Returns nil otherwise.
function QuickSwitch.NewWhisperName(list, query)
	local name = ns.Util.NormalizeName(ns.Util.Trim(query or ""))
	if not name or not name:find(" ", 1, true) then return nil end
	local wanted = name:lower()
	for _, entry in ipairs(list) do
		if entry.key:sub(1, 2) == "W:" and entry.key:sub(3):lower() == wanted then
			return nil
		end
	end
	return name
end

-- The rows to show: ranked chats, then the synthetic whisper row if it applies.
-- Each result is { key = } for a chat or { whisper = name } for a new one.
function QuickSwitch.Results(list, query)
	local keys = QuickSwitch.Rank(list, query)
	local whisper = QuickSwitch.NewWhisperName(list, query)
	local results = {}
	local limit = whisper and MAX_ROWS - 1 or MAX_ROWS
	for index = 1, math.min(#keys, limit) do
		results[index] = { key = keys[index] }
	end
	if whisper then
		results[#results + 1] = { whisper = whisper }
	end
	return results
end

-- UI ----------------------------------------------------------------------------

local frame, field, rows
local results, selected = {}, 1
local conversations = {}

local function InfoFor(result)
	if result.whisper then
		return { key = "W:" .. result.whisper, label = result.whisper }
	end
	local conv = conversations[result.key]
	return {
		key = result.key,
		label = ns.Store.LabelFor(result.key, conv),
		class = conv.class,
		muted = conv.mute,
		status = ns.Identity.Status(result.key),
	}
end

local function PaintRow(row, result, index)
	row.result = result
	row.index = index
	local info = InfoFor(result)
	ns.Widgets.ShowChatAvatar(row.avatar, info)
	row.label:SetText(result.whisper and L["Whisper %s"]:format(result.whisper) or info.label)
	if info.class and not info.muted then
		row.label:SetTextColor(ns.Theme.ClassColor(info.class, "sidebar"))
	else
		row.label:SetTextColor(ns.Theme.Color(info.muted and "muted" or "text"))
	end

	local hint = result.whisper and L["New"] or QuickSwitch.Hint(result.key)
	local unread = result.key and ns.Store.UnreadCount(result.key, conversations[result.key]) or 0
	if unread > 0 then
		hint = hint .. "  -  " .. L["%s unread"]:format(ns.Util.BadgeText(unread))
	end
	row.hint:SetText(hint)
end

local function UpdateSelection()
	for index, row in ipairs(rows) do
		row.selected:SetShown(row:IsShown() and index == selected)
	end
end

local function Choose(index)
	local result = results[index]
	if not result then return end
	QuickSwitch.Hide()
	local key = result.key
	if result.whisper then
		key = ns.Store.StartWhisper(result.whisper)
	end
	if key then
		-- Reply opens the chat and focuses the composer, unless combat has faded the window.
		ns.Window.Reply(key)
	end
end

local function CreateRow(index)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", PADDING, -(PADDING + FIELD_HEIGHT + 6 + (index - 1) * ROW_HEIGHT))
	row:SetPoint("TOPRIGHT", -PADDING, -(PADDING + FIELD_HEIGHT + 6 + (index - 1) * ROW_HEIGHT))

	row.selected = ns.Widgets.RoundedFill(row, "selected")
	row.selected:SetAllPoints()
	row.selected:Hide()

	row.avatar = ns.Widgets.ChatAvatar(row, CREST_SIZE, ROOM_ICON_SIZE)
	ns.Widgets.PlaceChatAvatar(row.avatar, "LEFT", ROW_INSET + 6, 0)

	row.label = ns.Widgets.Text(row, "HangoutFont", "text")
	row.label:SetWordWrap(false)
	row.hint = ns.Widgets.Text(row, "HangoutFontSmall", "muted")
	row.hint:SetJustifyH("RIGHT")
	row.hint:SetPoint("RIGHT", -ROW_INSET - 6, 0)
	row.label:SetPoint("LEFT", ROW_INSET + 6 + CREST_SIZE + 10, 0)
	row.label:SetPoint("RIGHT", row.hint, "LEFT", -8, 0)

	row:SetScript("OnEnter", function(self)
		selected = self.index
		UpdateSelection()
	end)
	row:SetScript("OnClick", function(self) Choose(self.index) end)
	return row
end

local function Refresh()
	local list = ns.Store.List()
	conversations = {}
	for _, entry in ipairs(list) do
		conversations[entry.key] = entry.conv
	end
	results = QuickSwitch.Results(list, field:GetText())
	if selected > #results then selected = 1 end
	if selected < 1 then selected = 1 end

	for index = 1, MAX_ROWS do
		local row = rows[index]
		local result = results[index]
		row:SetShown(result ~= nil)
		if result then PaintRow(row, result, index) end
	end
	frame:SetHeight(PADDING * 2 + FIELD_HEIGHT + (#results > 0 and 6 + #results * ROW_HEIGHT or 0))
	UpdateSelection()
end

local function MoveSelection(step)
	if #results == 0 then return end
	selected = (selected - 1 + step) % #results + 1
	UpdateSelection()
end

local function Create()
	frame = CreateFrame("Frame", "HangoutQuickSwitch", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetWidth(WIDTH)
	frame:EnableMouse(true)
	frame:Hide()
	-- Not in UISpecialFrames: the game hides every listed frame on one Escape, which
	-- would close the whole Hangout window along with this popup.
	frame:SetScript("OnKeyDown", function(self, key)
		local safe = not InCombatLockdown()
		if key == "ESCAPE" then
			if safe then self:SetPropagateKeyboardInput(false) end
			QuickSwitch.Hide()
		elseif safe then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	ns.Widgets.RoundedFill(frame, "sidebar"):SetAllPoints()
	ns.Widgets.Border(frame, "crestRing")

	local holder
	holder, field = ns.Widgets.Field(frame, 1)
	holder:SetPoint("TOPLEFT", PADDING, -PADDING)
	holder:SetPoint("TOPRIGHT", -PADDING, -PADDING)
	holder:SetHeight(FIELD_HEIGHT)

	local placeholder = ns.Widgets.Text(holder, "HangoutFontSmall", "muted")
	placeholder:SetPoint("LEFT", 8, 0)
	placeholder:SetText(L["Jump to a chat, or type a name to whisper"])
	field:SetScript("OnTextChanged", function(self)
		placeholder:SetShown(self:GetText() == "")
		selected = 1
		Refresh()
	end)
	field:SetScript("OnKeyDown", function(_, key)
		if key == "UP" then
			MoveSelection(-1)
		elseif key == "DOWN" then
			MoveSelection(1)
		end
	end)
	field:SetScript("OnEnterPressed", function() Choose(selected) end)
	-- The box takes Escape itself while focused, so the Hangout window stays open.
	field:SetScript("OnEscapePressed", function() QuickSwitch.Hide() end)

	rows = {}
	for index = 1, MAX_ROWS do
		rows[index] = CreateRow(index)
	end
end

function QuickSwitch.IsShown()
	return frame ~= nil and frame:IsShown()
end

function QuickSwitch.Show()
	-- The faded window ignores the mouse and keyboard in combat, so the switcher would be stuck.
	if ns.Window.IsFaded() then return end
	if not frame then Create() end
	frame:ClearAllPoints()
	local anchor = ns.Window.IsVisible() and _G.HangoutWindow or UIParent
	frame:SetPoint("CENTER", anchor, "CENTER")

	-- Protected in combat; the edit box still takes typing without it.
	if InCombatLockdown() then
		frame:EnableKeyboard(false)
	else
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	end

	selected = 1
	field:SetText("")
	Refresh()
	frame:Show()
	field:SetFocus()
end

function QuickSwitch.Hide()
	if not frame then return end
	field:ClearFocus()
	frame:Hide()
end

function QuickSwitch.Toggle()
	if QuickSwitch.IsShown() then
		QuickSwitch.Hide()
	else
		QuickSwitch.Show()
	end
end

ns.On("WINDOW_HIDDEN", QuickSwitch.Hide)
