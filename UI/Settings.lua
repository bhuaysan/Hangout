local _, ns = ...

local SettingsUI = {}
ns.SettingsUI = SettingsUI

local PANEL_NAME = "HangoutSettingsPanel"
local WINDOW_NAME = "HangoutWindow"
local ROW_HEIGHT = 28
local HEADER_HEIGHT = 30
local SECTION_PADDING = 10
local LEFT = 16
local CONTROL_X = 280
local CHOICE_WIDTH = 170
local SWATCH_WIDTH = 40
local CHECK_SIZE = 16
local CHECK_LABEL_GAP = 8
local FIELD_WIDTH = 300
local WHEEL_STEP = 60

local panel, scroller, root
local content -- the body of the section being built
local cursor = 0
local refreshers = {}
local sections = {}
local openSection

local function NextRow(height)
	local top = -cursor
	cursor = cursor + (height or ROW_HEIGHT)
	return top
end

local function RefreshAll()
	for i = 1, #refreshers do
		refreshers[i]()
	end
end

-- Stacks the section headers, with only the open section's rows between them.
local function LayoutSections()
	local top = 0
	for _, section in ipairs(sections) do
		local isOpen = section == openSection
		section.header:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
		section.header:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -top)
		section.marker:SetText(isOpen and "-" or "+")
		top = top + HEADER_HEIGHT

		section.body:SetShown(isOpen)
		if isOpen then
			section.body:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -top)
			section.body:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -top)
			section.body:SetHeight(section.height)
			top = top + section.height + SECTION_PADDING
		end
	end
	root:SetHeight(top)
	scroller:SetVerticalScroll(0)
end

-- A collapsible group of rows. build() adds its rows to the section.
local function AddSection(title, build)
	local section = {}
	sections[#sections + 1] = section

	local header = CreateFrame("Button", nil, root)
	header:SetHeight(HEADER_HEIGHT)
	section.header = header

	local hover = ns.Widgets.Fill(header, "hover")
	hover:Hide()
	header:SetScript("OnEnter", function() hover:Show() end)
	header:SetScript("OnLeave", function() hover:Hide() end)

	local line = ns.Widgets.Solid(header, "divider", "ARTWORK")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(1)

	local label = ns.Widgets.Text(header, "HangoutFontSmall", "muted")
	label:SetPoint("LEFT", LEFT, 0)
	label:SetText(title)

	section.marker = ns.Widgets.Text(header, "HangoutFont", "muted")
	section.marker:SetPoint("RIGHT", -LEFT, 0)

	header:SetScript("OnClick", function()
		openSection = openSection ~= section and section or nil
		LayoutSections()
	end)

	section.body = CreateFrame("Frame", nil, root)
	content = section.body
	cursor = 0
	build()
	section.height = cursor
end

local function Label(text, top)
	local label = ns.Widgets.Text(content, "HangoutFont", "text")
	label:SetPoint("LEFT", content, "TOPLEFT", LEFT, top - ROW_HEIGHT / 2)
	label:SetText(text)
	return label
end

local function Toggle(text, settingKey, onChange)
	local top = NextRow()
	local row = CreateFrame("Button", nil, content)
	row:SetPoint("LEFT", content, "TOPLEFT", LEFT, top - ROW_HEIGHT / 2)

	local outline = ns.Widgets.Solid(row, "outline", "BACKGROUND")
	outline:SetSize(CHECK_SIZE, CHECK_SIZE)
	outline:SetPoint("LEFT")

	local inner = ns.Widgets.Solid(row, "panel", "BORDER")
	inner:SetPoint("TOPLEFT", outline, "TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", outline, "BOTTOMRIGHT", -1, 1)

	local check = ns.Widgets.Solid(row, "accent", "ARTWORK")
	check:SetPoint("TOPLEFT", outline, "TOPLEFT", 3, -3)
	check:SetPoint("BOTTOMRIGHT", outline, "BOTTOMRIGHT", -3, 3)

	local label = ns.Widgets.Text(row, "HangoutFont", "text")
	label:SetPoint("LEFT", outline, "RIGHT", CHECK_LABEL_GAP, 0)
	label:SetText(text)
	-- The whole label is clickable, not only the box.
	row:SetSize(CHECK_SIZE + CHECK_LABEL_GAP + label:GetStringWidth(), ROW_HEIGHT)

	local function refresh()
		check:SetShown(ns.Get(settingKey) and true or false)
	end
	row:SetScript("OnClick", function()
		ns.Set(settingKey, not ns.Get(settingKey))
		refresh()
		if onChange then onChange() end
	end)
	refreshers[#refreshers + 1] = refresh
end

local function Stepper(text, settingKey, minimum, maximum, step, suffix, onChange)
	local top = NextRow()
	Label(text, top)
	local centerY = top - ROW_HEIGHT / 2

	local minus = ns.Widgets.TextButton(content, "-", "HangoutFontLarge")
	minus:SetSize(24, 24)
	minus:SetPoint("LEFT", content, "TOPLEFT", CONTROL_X, centerY)

	local value = ns.Widgets.Text(content, "HangoutFont", "text")
	value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
	value:SetWidth(72)
	value:SetJustifyH("CENTER")

	local plus = ns.Widgets.TextButton(content, "+", "HangoutFontLarge")
	plus:SetSize(24, 24)
	plus:SetPoint("LEFT", value, "RIGHT", 4, 0)

	local function refresh()
		value:SetText(ns.Get(settingKey) .. (suffix or ""))
	end
	local function change(delta)
		local updated = math.max(minimum, math.min(maximum, ns.Get(settingKey) + delta))
		ns.Set(settingKey, updated)
		refresh()
		if onChange then onChange() end
	end
	minus:SetScript("OnClick", function() change(-step) end)
	plus:SetScript("OnClick", function() change(step) end)
	refreshers[#refreshers + 1] = refresh
end

-- options: list of { value = ..., label = ... }
local function Choice(text, options, getter, setter)
	local top = NextRow()
	Label(text, top)

	local button = CreateFrame("Button", nil, content)
	button:SetSize(CHOICE_WIDTH, 22)
	button:SetPoint("LEFT", content, "TOPLEFT", CONTROL_X, top - ROW_HEIGHT / 2)
	ns.Widgets.RoundedFill(button, "selected"):SetAllPoints()
	local current = ns.Widgets.Text(button, "HangoutFont", "text")
	current:SetPoint("LEFT", 8, 0)
	current:SetPoint("RIGHT", -8, 0)
	current:SetWordWrap(false)

	local function refresh()
		local selected = getter()
		for _, option in ipairs(options) do
			if option.value == selected then current:SetText(option.label) end
		end
	end
	button:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			for _, option in ipairs(options) do
				root:CreateRadio(option.label,
					function() return getter() == option.value end,
					function()
						setter(option.value)
						refresh()
					end)
			end
		end)
	end)
	refreshers[#refreshers + 1] = refresh
end

local function SettingChoice(text, settingKey, options, onChange)
	Choice(text, options,
		function() return ns.Get(settingKey) end,
		function(value)
			ns.Set(settingKey, value)
			if onChange then onChange(value) end
		end)
end

local function ColorRow(entry)
	local top = NextRow()
	Label(entry.label, top)

	local swatch = CreateFrame("Button", nil, content)
	swatch:SetSize(SWATCH_WIDTH, 20)
	swatch:SetPoint("LEFT", content, "TOPLEFT", CONTROL_X, top - ROW_HEIGHT / 2)
	-- The outline keeps a swatch visible when its color matches the panel.
	ns.Widgets.Fill(swatch, "outline")
	local color = swatch:CreateTexture(nil, "ARTWORK")
	color:SetPoint("TOPLEFT", 1, -1)
	color:SetPoint("BOTTOMRIGHT", -1, 1)

	local function refresh()
		local r, g, b = ns.Theme.Color(entry.token)
		color:SetColorTexture(r, g, b, 1)
	end
	swatch:SetScript("OnClick", function()
		local r, g, b = ns.Theme.Color(entry.token)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			swatchFunc = function()
				local newR, newG, newB = ColorPickerFrame:GetColorRGB()
				ns.Theme.SetCustom(entry.token, newR, newG, newB)
				RefreshAll()
			end,
			cancelFunc = function()
				ns.Theme.SetCustom(entry.token, r, g, b)
				RefreshAll()
			end,
		})
	end)
	refreshers[#refreshers + 1] = refresh
end

local function ThemeStringRow()
	local top = NextRow()
	local holder, field = ns.Widgets.Field(content, FIELD_WIDTH)
	holder:SetPoint("LEFT", content, "TOPLEFT", LEFT, top - ROW_HEIGHT / 2)
	field:SetScript("OnEnterPressed", field.ClearFocus)

	local export = ns.Widgets.FlatButton(content, "Export", 64)
	export:SetPoint("LEFT", holder, "RIGHT", 8, 0)
	export:SetScript("OnClick", function()
		field:SetText(ns.Theme.Export())
		field:SetFocus()
		field:HighlightText()
	end)

	local import = ns.Widgets.FlatButton(content, "Import", 64)
	import:SetPoint("LEFT", export, "RIGHT", 6, 0)
	import:SetScript("OnClick", function()
		if ns.Theme.Import(field:GetText()) then
			RefreshAll()
			ns.Print("Theme imported.")
		else
			ns.Print("That isn't a valid Hangout theme string.")
		end
	end)
end

local function ListRow(text, settingKey, save)
	local top = NextRow()
	Label(text, top)
	local holder, field = ns.Widgets.Field(content, CHOICE_WIDTH + 90)
	holder:SetPoint("LEFT", content, "TOPLEFT", CONTROL_X - 90, top - ROW_HEIGHT / 2)

	field:SetScript("OnEnterPressed", function(self)
		save(self:GetText())
		self:ClearFocus()
	end)
	field:SetScript("OnEditFocusLost", function(self) save(self:GetText()) end)
	refreshers[#refreshers + 1] = function()
		field:SetText(table.concat(ns.Get(settingKey) or {}, ", "))
	end
end

local function RuleRow(text, settingKey)
	ListRow(text, settingKey, function(value) ns.Filter.SetList(settingKey, value) end)
end

local function Note(text)
	local note = ns.Widgets.Text(content, "HangoutFontSmall", "muted")
	note:SetPoint("TOPLEFT", LEFT, NextRow(18))
	note:SetPoint("RIGHT", content, "RIGHT", -LEFT, 0)
	note:SetText(text)
	return note
end

local function ThemeOptions()
	local options = {}
	for _, name in ipairs(ns.Theme.PRESET_ORDER) do
		options[#options + 1] = { value = name, label = ns.Theme.PresetLabel(name) }
	end
	return options
end

local function BuildAppearance()
	Choice("Theme", ThemeOptions(), ns.Theme.ActiveName, function(name)
		ns.Theme.SetPreset(name)
		RefreshAll()
	end)
	Stepper("Message text size", "messageSize", 10, 22, 1, nil, ns.Theme.Apply)
	Stepper("Window opacity", "windowOpacity", ns.Theme.MIN_OPACITY, 100, 5, "%", ns.Theme.Apply)
	for _, entry in ipairs(ns.Theme.CUSTOMIZABLE) do
		ColorRow(entry)
	end

	local top = NextRow()
	local reset = ns.Widgets.FlatButton(content, "Reset colors", 110)
	reset:SetPoint("LEFT", content, "TOPLEFT", LEFT, top - ROW_HEIGHT / 2)
	reset:SetScript("OnClick", function()
		ns.Theme.ResetCustom()
		RefreshAll()
	end)
	ThemeStringRow()
end

local function SoundChoice(text, category)
	local options = ns.Alerts.SoundChoices(category)
	SettingChoice(text, "sound" .. category, options, ns.Alerts.Preview)
end

local function BuildNotifications()
	Toggle("Do Not Disturb", "dnd", function() ns.Launcher.SetDnd(ns.Get("dnd")) end)
	SoundChoice("Whisper sound", "Whisper")
	SoundChoice("Group sound", "Group")
	SoundChoice("Mention sound", "Mention")
	Toggle("Glance strip for whispers", "toastWhisper")
	Toggle("Popups for group chat", "toastGroup")
	Toggle("Popups for mentions", "toastMention")
	Toggle("Flash taskbar on whispers", "flashWhisper")
	Toggle("Flash taskbar on group chat", "flashGroup")
	Toggle("Flash taskbar on mentions", "flashMention")
	ListRow("Extra words", "keywords", ns.Alerts.SetKeywords)
	Note("Your first name always counts as a mention. Separate extra words with commas.")
end

local function BuildSpamControl()
	Toggle("Put strangers' whispers in Requests", "requestsEnabled")
	RuleRow("Blocked words", "blockWords")
	RuleRow("Hide in channels", "channelHideWords")
	RuleRow("Only show in channels", "channelOnlyWords")
	Stepper("Ignore channel repeats within", "channelRepeatSeconds", 0, 300, 30, " sec")
	RuleRow("Blocked players", "blockedPlayers")
	Note("Separate entries with commas. Blocked words apply to strangers and public channels.")
	Note("These rules only affect Hangout. Normal chat still shows everything.")
	local counter = Note("")
	refreshers[#refreshers + 1] = function()
		counter:SetText("Filtered this session: " .. ns.Filter.BlockedCount())
	end
end

local function BuildBehavior()
	SettingChoice("In combat", "combatMode", {
		{ value = "fade", label = "Fade" },
		{ value = "hide", label = "Hide" },
		{ value = "off", label = "Stay visible" },
	})
	Stepper("Faded opacity", "combatOpacity", 5, 60, 5, "%")
	Toggle("Show others when I'm typing", "sendTyping")
	Toggle("Send read receipts", "sendReadReceipts")
	Toggle("Hide whispers from normal chat", "hideWhispers", function() ns.Filter.Apply() end)
	Toggle("Show minimap button", "showMinimap", function() ns.Launcher.UpdateVisibility() end)
end

local function BuildHistory()
	Stepper("Keep whispers for", "retentionWhisperDays", 30, 360, 30, " days")
	Stepper("Keep guild and group for", "retentionGroupDays", 7, 91, 7, " days")
	Stepper("Keep saved channels for", "retentionChannelDays", 7, 91, 7, " days")
	Stepper("Messages per chat", "perChatCap", 100, 5000, 100)
	Stepper("Messages in total", "globalCap", 2000, 50000, 2000)
	Note("Old messages are removed when you log in. Right-click a channel to save its history.")
end

local function BuildAbout()
	Note("Hangout " .. ns.version)
	Note("Emoji graphics by Twemoji contributors, licensed under CC-BY 4.0.")
	Note("See Media\\TWEMOJI-LICENSE.txt or creativecommons.org/licenses/by/4.0")
end

local function RemoveEscapeEntry(name)
	for index = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[index] == name then
			table.remove(UISpecialFrames, index)
		end
	end
end

-- The game hides every listed frame on one Esc press, so only the top layer
-- may be listed for Esc to step back from Settings to the chat.
local function UpdateEscapeTarget()
	RemoveEscapeEntry(PANEL_NAME)
	RemoveEscapeEntry(WINDOW_NAME)
	tinsert(UISpecialFrames, panel:IsVisible() and PANEL_NAME or WINDOW_NAME)
end

function SettingsUI.Create(window, header)
	panel = CreateFrame("Frame", PANEL_NAME, window)
	panel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
	panel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT")
	panel:SetFrameLevel(window:GetFrameLevel() + 30)
	panel:EnableMouse(true)
	panel:Hide()
	ns.Widgets.RoundedFill(panel, "panel", nil, "bottomRight"):SetAllPoints()
	panel:SetScript("OnShow", function()
		UpdateEscapeTarget()
		ns.Fire("SETTINGS_TOGGLED", true)
	end)
	panel:SetScript("OnHide", function()
		-- The game is still walking the Esc list when this runs, so wait a frame.
		C_Timer.After(0, UpdateEscapeTarget)
		ns.Fire("SETTINGS_TOGGLED", false)
	end)

	local scrollBar = ns.Widgets.ScrollBar(panel)
	scrollBar:SetPoint("TOPRIGHT", -2, -4)
	scrollBar:SetPoint("BOTTOMRIGHT", -2, 18)

	scroller = CreateFrame("ScrollFrame", nil, panel)
	scroller:SetPoint("TOPLEFT")
	scroller:SetPoint("BOTTOMRIGHT", -14, 0)
	scroller:EnableMouseWheel(true)
	ScrollUtil.InitScrollFrameWithScrollBar(scroller, scrollBar)
	scroller:SetPanExtent(WHEEL_STEP)

	root = CreateFrame("Frame", nil, scroller)
	root:SetSize(1, 1)
	scroller:SetScrollChild(root)
	scroller:SetScript("OnSizeChanged", function(self, width) root:SetWidth(width) end)

	AddSection("APPEARANCE", BuildAppearance)
	AddSection("NOTIFICATIONS", BuildNotifications)
	AddSection("SPAM CONTROL", BuildSpamControl)
	AddSection("BEHAVIOR", BuildBehavior)
	AddSection("HISTORY", BuildHistory)
	AddSection("ABOUT", BuildAbout)
	openSection = sections[1]
	LayoutSections()
end

function SettingsUI.Show()
	root:SetWidth(scroller:GetWidth())
	RefreshAll()
	panel:Show()
end

ns.On("DND_CHANGED", function()
	if panel then RefreshAll() end
end)

function SettingsUI.Hide()
	if panel then panel:Hide() end
end

function SettingsUI.Toggle()
	if panel:IsShown() then
		panel:Hide()
	else
		SettingsUI.Show()
	end
end

-- An entry in the game's own AddOns settings list that points to the real panel.
function SettingsUI.Init()
	local page = CreateFrame("Frame")
	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", 16, -16)
	open:SetText("Open Hangout settings")
	open:SetScript("OnClick", function()
		HideUIPanel(SettingsPanel)
		ns.Window.OpenSettings()
	end)
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, "Hangout"))
end
