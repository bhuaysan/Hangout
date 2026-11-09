local _, ns = ...

local Prompt = {}
ns.Prompt = Prompt

local WIDTH = 340
local FIELD_WIDTH = 308
local HEIGHT_WITH_FIELD = 118
local HEIGHT_WITHOUT_FIELD = 92

local frame, message, holder, field, accept, acceptLabel
local onAccept

local function Finish()
	frame:Hide()
	if onAccept then
		onAccept(field:GetText())
	end
end

local function Create()
	frame = CreateFrame("Frame", "HangoutPrompt", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER")
	frame:SetWidth(WIDTH)
	frame:EnableMouse(true)
	frame:Hide()
	-- Not in UISpecialFrames: the game hides every listed frame on one Escape,
	-- which would close the whole Hangout window along with this prompt.
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

	message = ns.Widgets.Text(frame, "HangoutFont", "text")
	message:SetPoint("TOPLEFT", 16, -14)
	message:SetPoint("TOPRIGHT", -16, -14)
	message:SetWordWrap(true)

	holder, field = ns.Widgets.Field(frame, FIELD_WIDTH)
	holder:SetPoint("BOTTOMLEFT", 16, 46)
	field:SetScript("OnEnterPressed", Finish)
	field:SetScript("OnEscapePressed", function() frame:Hide() end)

	accept, acceptLabel = ns.Widgets.FlatButton(frame, "OK", 90)
	accept:SetPoint("BOTTOMRIGHT", -16, 14)
	accept:SetScript("OnClick", Finish)

	local cancel = ns.Widgets.FlatButton(frame, "Cancel", 80)
	cancel:SetPoint("RIGHT", accept, "LEFT", -8, 0)
	cancel:SetScript("OnClick", function() frame:Hide() end)
end

local function Open(text, label, withField, initial, callback)
	if not frame then Create() end
	onAccept = callback
	message:SetText(text)
	acceptLabel:SetText(label)
	holder:SetShown(withField)
	field:SetText(initial or "")
	frame:SetHeight(withField and HEIGHT_WITH_FIELD or HEIGHT_WITHOUT_FIELD)
	-- Protected in combat; a frame that swallows keys there is worse than no Escape.
	if InCombatLockdown() then
		frame:EnableKeyboard(false)
	else
		frame:SetPropagateKeyboardInput(true)
		frame:EnableKeyboard(true)
	end
	frame:Show()
	if withField then
		field:SetFocus()
		field:HighlightText()
	end
end

-- callback receives the entered text. The button says "Save" unless given a label.
function Prompt.AskText(text, initial, callback, acceptText)
	Open(text, acceptText or "Save", true, initial, callback)
end

function Prompt.Confirm(text, label, callback)
	Open(text, label, false, nil, callback)
end
