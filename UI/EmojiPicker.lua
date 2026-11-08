local _, ns = ...

local EmojiPicker = {}
ns.EmojiPicker = EmojiPicker

local COLUMNS = 14
local CELL = 28
local ICON = 22
local PADDING = 8

local panel

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(":" .. self.name .. ":")
	GameTooltip:Show()
end

local function OnEmojiClick(self)
	ns.Composer.Insert(":" .. self.name .. ": ")
	panel:Hide()
end

local function CreateEmojiButton(index, name)
	local button = CreateFrame("Button", nil, panel)
	button.name = name
	button:SetSize(CELL, CELL)
	local column = (index - 1) % COLUMNS
	local row = math.floor((index - 1) / COLUMNS)
	button:SetPoint("TOPLEFT", PADDING + column * CELL, -(PADDING + row * CELL))

	local texture = button:CreateTexture(nil, "ARTWORK")
	texture:SetSize(ICON, ICON)
	texture:SetPoint("CENTER")
	texture:SetTexture(ns.Emoji.ATLAS)
	texture:SetTexCoord(ns.Emoji.TexCoords(index))

	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", OnEmojiClick)
end

local function Create(anchor)
	local count = #ns.EmojiData
	local rows = math.ceil(count / COLUMNS)

	panel = CreateFrame("Frame", nil, anchor)
	panel:SetSize(COLUMNS * CELL + PADDING * 2, rows * CELL + PADDING * 2)
	panel:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -8, 4)
	panel:SetFrameLevel(anchor:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	ns.Widgets.Fill(panel, "sidebar")

	for index, name in ipairs(ns.EmojiData) do
		CreateEmojiButton(index, name)
	end
end

function EmojiPicker.Toggle(anchor)
	if not panel then Create(anchor) end
	panel:SetShown(not panel:IsShown())
end

function EmojiPicker.Hide()
	if panel then panel:Hide() end
end
