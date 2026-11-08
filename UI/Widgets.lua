local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-- Everything colored from a theme token, so a theme change can repaint it.
local painted = {}

local function PaintRegion(entry)
	if entry.isText then
		entry.region:SetTextColor(ns.Theme.Color(entry.token))
	else
		entry.region:SetColorTexture(ns.Theme.Color(entry.token))
	end
end

local function Track(region, token, isText)
	local entry = { region = region, token = token, isText = isText }
	painted[#painted + 1] = entry
	PaintRegion(entry)
end

function Widgets.Repaint()
	for i = 1, #painted do
		PaintRegion(painted[i])
	end
end

-- A themed texture the caller anchors.
function Widgets.Solid(frame, token, layer)
	local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
	Track(texture, token, false)
	return texture
end

function Widgets.Fill(frame, token, layer)
	local texture = Widgets.Solid(frame, token, layer)
	texture:SetAllPoints()
	return texture
end

function Widgets.Text(frame, fontObject, token)
	local text = frame:CreateFontString(nil, "OVERLAY", fontObject)
	Track(text, token, true)
	text:SetJustifyH("LEFT")
	return text
end

-- A flat text button that lightens on hover.
function Widgets.TextButton(parent, text, fontObject)
	local button = CreateFrame("Button", nil, parent)
	local label = Widgets.Text(button, fontObject or "GameFontHighlight", "muted")
	label:SetPoint("CENTER")
	label:SetJustifyH("CENTER")
	label:SetText(text)
	button:SetScript("OnEnter", function() label:SetTextColor(ns.Theme.Color("text")) end)
	button:SetScript("OnLeave", function() label:SetTextColor(ns.Theme.Color("muted")) end)
	return button, label
end

-- A filled button with centered text. Returns the button and its label.
function Widgets.FlatButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, 22)
	Widgets.Fill(button, "selected")
	local label = Widgets.Text(button, "GameFontHighlight", "text")
	label:SetPoint("CENTER")
	label:SetJustifyH("CENTER")
	label:SetText(text)
	return button, label
end

-- A filled single-line text field. Returns its holder and the EditBox.
function Widgets.Field(parent, width)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(width, 22)
	Widgets.Fill(holder, "selected")

	local field = CreateFrame("EditBox", nil, holder)
	field:SetPoint("TOPLEFT", 6, 0)
	field:SetPoint("BOTTOMRIGHT", -6, 0)
	field:SetFontObject(GameFontHighlight)
	field:SetAutoFocus(false)
	field:SetScript("OnEscapePressed", field.ClearFocus)
	return holder, field
end

-- Returns a virtualized list and its scroll bar. The caller anchors both.
function Widgets.ScrollList(parent, view)
	local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scrollBar:SetHideIfUnscrollable(true)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	return scrollBox, scrollBar
end
