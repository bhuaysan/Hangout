local _, ns = ...

local Widgets = {}
ns.Widgets = Widgets

-- Everything colored from a theme token, so a theme change can repaint it.
local painted = {}

local CREST_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local RING_TEXTURE = "Interface\\AddOns\\Hangout\\Media\\ring.png"
local RING_EXTRA_SIZE = 3
local SCROLL_BAR_ALPHA = 0.5
local MEDIA = "Interface\\AddOns\\Hangout\\Media\\"
-- The whole shape is rounded unless a panel only touches some window corners.
local ROUNDED_SHAPES = {
	all = MEDIA .. "bubble.png",
	left = MEDIA .. "corner-left.png",
	topRight = MEDIA .. "corner-topright.png",
	bottomLeft = MEDIA .. "corner-bottomleft.png",
	bottomRight = MEDIA .. "corner-bottomright.png",
	outline = MEDIA .. "outline.png",
}
local ROUNDED_SLICE_MARGIN = 8
local ICON_ATLAS = "Interface\\AddOns\\Hangout\\Media\\icons.png"
local ICON_COLUMNS = 4
local ICON_NAMES = {
	"search", "plus", "collapse", "expand",
	"close", "gear", "moon", "pin",
	"mute", "hash", "guild", "smile",
}
local STATUS_ICON = {
	[true] = "Interface\\FriendsFrame\\StatusIcon-Online",
	[false] = "Interface\\FriendsFrame\\StatusIcon-Offline",
}
local ICON_INDEX = {}
for index, name in ipairs(ICON_NAMES) do
	ICON_INDEX[name] = index
end

local function PaintRegion(entry)
	if entry.isText then
		entry.region:SetTextColor(ns.Theme.Color(entry.token))
	elseif entry.isTint then
		entry.region:SetVertexColor(ns.Theme.Color(entry.token))
	else
		entry.region:SetColorTexture(ns.Theme.Color(entry.token))
	end
end

local function Track(region, token, isText, isTint)
	local entry = { region = region, token = token, isText = isText, isTint = isTint }
	painted[#painted + 1] = entry
	PaintRegion(entry)
	return entry
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

-- A rounded shape that stretches cleanly. Color it with SetVertexColor.
function Widgets.Rounded(frame, layer, shape)
	local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
	texture:SetTexture(ROUNDED_SHAPES[shape or "all"])
	texture:SetTextureSliceMargins(ROUNDED_SLICE_MARGIN, ROUNDED_SLICE_MARGIN, ROUNDED_SLICE_MARGIN, ROUNDED_SLICE_MARGIN)
	texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
	return texture
end

-- A rounded shape in a theme color. The caller anchors it.
function Widgets.RoundedFill(frame, token, layer, shape)
	local texture = Widgets.Rounded(frame, layer, shape)
	Track(texture, token, false, true)
	return texture
end

-- Shows one icon from the addon's icon image on a texture.
function Widgets.SetIcon(texture, name)
	local index = ICON_INDEX[name] - 1
	local column = index % ICON_COLUMNS
	local row = math.floor(index / ICON_COLUMNS)
	local cell = 1 / ICON_COLUMNS
	texture:SetTexture(ICON_ATLAS)
	texture:SetTexCoord(column * cell, (column + 1) * cell, row * cell, (row + 1) * cell)
end

-- A themed icon the caller anchors.
function Widgets.Icon(frame, name, size, token, layer)
	local texture = frame:CreateTexture(nil, layer or "ARTWORK")
	texture:SetSize(size, size)
	Widgets.SetIcon(texture, name)
	local entry = Track(texture, token, false, true)
	return texture, entry
end

-- An icon that lightens on hover and names itself in a tooltip.
function Widgets.IconButton(parent, name, size, iconSize, tooltip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	local icon, entry = Widgets.Icon(button, name, iconSize, "muted")
	icon:SetPoint("CENTER")
	button.icon = icon
	button.iconEntry = entry

	button:SetScript("OnEnter", function(self)
		if entry.token ~= "accent" then
			icon:SetVertexColor(ns.Theme.Color("text"))
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		PaintRegion(entry)
		GameTooltip:Hide()
	end)
	return button
end

-- Turns an icon button gold while its setting is on.
function Widgets.SetIconButtonActive(button, isActive)
	button.iconEntry.token = isActive and "accent" or "muted"
	PaintRegion(button.iconEntry)
end

-- A chat's picture: its class crest, otherwise a first letter for a person or
-- an icon for a channel or group, with the online dot on the corner.
function Widgets.ChatAvatar(frame, size, iconSize)
	local avatar = {}
	avatar.crest = Widgets.ClassCrest(frame, size)
	avatar.slot = Widgets.RoundedFill(frame, "selected", "BORDER")
	avatar.slot:SetSize(size, size)
	avatar.icon = Widgets.Icon(frame, "hash", iconSize, "muted")
	avatar.icon:SetPoint("CENTER", avatar.slot)
	avatar.letter = Widgets.Text(frame, "GameFontHighlight", "muted")
	avatar.letter:SetPoint("CENTER", avatar.slot)
	avatar.status = frame:CreateTexture(nil, "OVERLAY", nil, 1) -- above the crest's ring
	avatar.status:SetSize(14, 14)
	return avatar
end

function Widgets.PlaceChatAvatar(avatar, ...)
	avatar.crest:ClearAllPoints()
	avatar.crest:SetPoint(...)
	avatar.slot:ClearAllPoints()
	avatar.slot:SetPoint(...)
end

-- info: { key, class, label, presence, muted }, or nil to show nothing.
function Widgets.ShowChatAvatar(avatar, info)
	local hasCrest = Widgets.SetClassCrest(avatar.crest, info and info.class or nil)
	avatar.crest:SetDesaturated(hasCrest and info.muted and true or false)

	local prefix = info and info.key:sub(1, 1)
	local isPerson = prefix == "W" or prefix == "B" or prefix == "L"
	local hasSlot = info ~= nil and not hasCrest
	avatar.slot:SetShown(hasSlot)
	avatar.letter:SetShown(hasSlot and isPerson)
	avatar.icon:SetShown(hasSlot and not isPerson)
	if hasSlot and isPerson then
		avatar.letter:SetText(ns.Util.FirstCharacter(info.label))
	elseif hasSlot then
		Widgets.SetIcon(avatar.icon, prefix == "C" and "hash" or "guild")
	end

	local hasStatus = info ~= nil and info.presence ~= nil
	avatar.status:SetShown(hasStatus)
	if hasStatus then
		avatar.status:SetTexture(STATUS_ICON[info.presence])
		avatar.status:ClearAllPoints()
		avatar.status:SetPoint("CENTER", hasCrest and avatar.crest or avatar.slot, "BOTTOMRIGHT", -2, 2)
	end
end

-- A thin themed outline that follows the rounded corners.
function Widgets.Border(frame, token)
	Widgets.RoundedFill(frame, token, "OVERLAY", "outline"):SetAllPoints()
end

-- A class crest texture with a themed ring around it. The caller anchors the
-- returned texture and fills it with SetClassCrest.
function Widgets.ClassCrest(frame, size)
	local crest = frame:CreateTexture(nil, "ARTWORK")
	crest:SetSize(size, size)

	local ring = frame:CreateTexture(nil, "OVERLAY", nil, 0)
	ring:SetTexture(RING_TEXTURE)
	ring:SetSize(size + RING_EXTRA_SIZE, size + RING_EXTRA_SIZE)
	ring:SetPoint("CENTER", crest)
	Track(ring, "crestRing", false, true)

	crest.ring = ring
	return crest
end

-- Shows a class's round crest on a texture, or hides the texture if the class
-- isn't known. Returns whether a crest is showing.
function Widgets.SetClassCrest(texture, classToken)
	local coords = classToken and CLASS_ICON_TCOORDS[classToken]
	texture:SetShown(coords ~= nil)
	if texture.ring then texture.ring:SetShown(coords ~= nil) end
	if coords then
		texture:SetTexture(CREST_TEXTURE)
		texture:SetTexCoord(unpack(coords))
	end
	return coords ~= nil
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
	Widgets.RoundedFill(button, "selected"):SetAllPoints()
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
	Widgets.RoundedFill(holder, "selected"):SetAllPoints()

	local field = CreateFrame("EditBox", nil, holder)
	field:SetPoint("TOPLEFT", 6, 0)
	field:SetPoint("BOTTOMRIGHT", -6, 0)
	field:SetFontObject(GameFontHighlight)
	field:SetAutoFocus(false)
	field:SetScript("OnEscapePressed", field.ClearFocus)
	return holder, field
end

-- A quiet scroll bar that only appears when there is something to scroll.
function Widgets.ScrollBar(parent)
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scrollBar:SetHideIfUnscrollable(true)
	scrollBar:SetAlpha(SCROLL_BAR_ALPHA)
	return scrollBar
end

-- Returns a virtualized list and its scroll bar. The caller anchors both.
function Widgets.ScrollList(parent, view)
	local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local scrollBar = Widgets.ScrollBar(parent)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	return scrollBox, scrollBar
end
