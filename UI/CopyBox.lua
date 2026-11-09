local _, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

local WIDTH = 460
local HEIGHT = 340
local SIDE = 16
local SCROLL_WIDTH = WIDTH - SIDE * 2 - 8
local WHEEL_STEP = 40

local frame, title, edit, scroll
local original = ""

-- The text a player would see on screen, for pasting elsewhere. Links keep their
-- [bracketed] name, textures vanish and :emoji: shortcodes stay as typed.
function CopyBox.PlainText(text)
	text = ns.Search.VisibleText(text or "")
	return (text:gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

local function SelectAll()
	edit:SetFocus()
	edit:HighlightText()
end

local function Create()
	frame = CreateFrame("Frame", "HangoutCopyBox", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER")
	frame:SetSize(WIDTH, HEIGHT)
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

	title = ns.Widgets.Text(frame, "HangoutFontBold", "text")
	title:SetPoint("TOPLEFT", SIDE, -14)
	title:SetPoint("TOPRIGHT", -SIDE, -14)
	title:SetWordWrap(false)

	local well = CreateFrame("Frame", nil, frame)
	well:SetPoint("TOPLEFT", SIDE, -42)
	well:SetPoint("BOTTOMRIGHT", -SIDE, 76)
	ns.Widgets.RoundedFill(well, "selected"):SetAllPoints()

	scroll = CreateFrame("ScrollFrame", nil, well)
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local limit = math.max(0, self:GetVerticalScrollRange())
		self:SetVerticalScroll(math.min(limit, math.max(0, self:GetVerticalScroll() - delta * WHEEL_STEP)))
	end)

	edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(HangoutFont)
	edit:SetWidth(SCROLL_WIDTH)
	ns.Widgets.TrackText(edit, "text")
	scroll:SetScrollChild(edit)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	-- Read-only in effect: typing or pasting puts the original back.
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self:GetText() ~= original then
			self:SetText(original)
			self:HighlightText()
		end
	end)
	edit:SetScript("OnCursorChanged", function(self, _, y, _, height)
		-- Keeps the caret in view while the text is selected and scrolled by keyboard.
		local top = scroll:GetVerticalScroll()
		local visible = scroll:GetHeight()
		if -y < top then
			scroll:SetVerticalScroll(-y)
		elseif -y + height > top + visible then
			scroll:SetVerticalScroll(-y + height - visible)
		end
	end)

	local hint = ns.Widgets.Text(frame, "HangoutFontSmall", "muted")
	hint:SetPoint("BOTTOMLEFT", SIDE, 52)
	hint:SetText("Ctrl+C copies the selected text")

	local close = ns.Widgets.FlatButton(frame, "Close", 90)
	close:SetPoint("BOTTOMRIGHT", -SIDE, 14)
	close:SetScript("OnClick", function() frame:Hide() end)

	local selectAll = ns.Widgets.FlatButton(frame, "Select all", 90)
	selectAll:SetPoint("RIGHT", close, "LEFT", -8, 0)
	selectAll:SetScript("OnClick", SelectAll)
end

function CopyBox.Show(heading, text)
	if not frame then Create() end
	original = text or ""
	title:SetText(heading or "Copy")
	edit:SetText(original)
	scroll:SetVerticalScroll(0)
	-- Protected in combat; a frame that swallows keys there is worse than no Escape.
	if InCombatLockdown() then
		frame:EnableKeyboard(false)
	else
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	end
	frame:Show()
	SelectAll()
end
