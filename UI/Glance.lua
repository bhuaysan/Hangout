local _, ns = ...

local Glance = {}
ns.Glance = Glance

local WIDTH = 340
local LINE_HEIGHT = 26
local PADDING = 6
local MAX_LINES = 3
local CREST_SIZE = 18
local CREST_LEFT = 4
local TEXT_LEFT_WITH_CREST = CREST_LEFT + CREST_SIZE + 8
local TEXT_LEFT = 6
local VISIBLE_SECONDS = 10
local HOVER_RECHECK_SECONDS = 2
local FADE_SECONDS = 1
local DEFAULT_X, DEFAULT_Y = 20, 290 -- just above the default chat window
local DRAG_CLICK_GUARD_SECONDS = 0.05

local frame, timer, fadeOut
local rows = {}
local lines = {}
local dragEndedAt = 0

local function RestorePosition()
	local saved = ns.Get("glancePosition")
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved and saved.x or DEFAULT_X, saved and saved.y or DEFAULT_Y)
end

local function StartDrag()
	frame:StartMoving()
end

-- Saved by its bottom edge so new lines always grow upward.
local function StopDrag()
	frame:StopMovingOrSizing()
	dragEndedAt = GetTime()
	ns.Set("glancePosition", { x = frame:GetLeft(), y = frame:GetBottom() })
	RestorePosition()
end

local function OnRowClick(self, button)
	-- Letting go after a drag must not count as a click.
	if GetTime() - dragEndedAt < DRAG_CLICK_GUARD_SECONDS then return end
	local key = self.line and self.line.key
	Glance.Hide()
	if button == "LeftButton" and key then
		ns.Window.Reply(key)
	end
end

local function CreateRow(index)
	local top = -(PADDING + (index - 1) * LINE_HEIGHT)
	local row = CreateFrame("Button", nil, frame)
	row:SetHeight(LINE_HEIGHT)
	row:SetPoint("TOPLEFT", PADDING, top)
	row:SetPoint("TOPRIGHT", -PADDING, top)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", StartDrag)
	row:SetScript("OnDragStop", StopDrag)
	row:SetScript("OnClick", OnRowClick)

	local hover = ns.Widgets.Fill(row, "hover")
	hover:Hide()
	row:SetScript("OnEnter", function() hover:Show() end)
	row:SetScript("OnLeave", function() hover:Hide() end)

	row.crest = ns.Widgets.ClassCrest(row, CREST_SIZE)
	row.crest:SetPoint("LEFT", CREST_LEFT, 0)

	row.name = ns.Widgets.Text(row, "HangoutFontBold", "text")
	row.name:SetWordWrap(false)

	row.body = ns.Widgets.Text(row, "HangoutFont", "text")
	row.body:SetPoint("LEFT", row.name, "RIGHT", 7, 0)
	row.body:SetPoint("RIGHT", -6, 0)
	row.body:SetWordWrap(false)
	return row
end

local function Create()
	frame = CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetWidth(WIDTH)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", StartDrag)
	frame:SetScript("OnDragStop", StopDrag)
	frame:Hide()
	RestorePosition()

	ns.Widgets.RoundedFill(frame, "glance"):SetAllPoints()
	ns.Widgets.Border(frame, "edge")

	for index = 1, MAX_LINES do
		rows[index] = CreateRow(index)
	end

	fadeOut = frame:CreateAnimationGroup()
	local alpha = fadeOut:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetDuration(FADE_SECONDS)
	fadeOut:SetScript("OnFinished", function() Glance.Hide() end)
end

local function Render()
	frame:SetHeight(#lines * LINE_HEIGHT + PADDING * 2)
	for index, row in ipairs(rows) do
		local line = lines[index]
		row.line = line
		row:SetShown(line ~= nil)
		if line then
			local hasCrest = ns.Widgets.SetClassCrest(row.crest, line.class)
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", hasCrest and TEXT_LEFT_WITH_CREST or TEXT_LEFT, 0)
			row.name:SetText(line.name)
			row.name:SetTextColor(ns.Theme.ClassColor(line.class, "popup"))
			row.body:SetText(line.text)
		end
	end
end

-- Stays up while the mouse is on it, so a line can't vanish just before a click.
local function StartTimer(seconds)
	if timer then timer:Cancel() end
	timer = C_Timer.NewTimer(seconds, function()
		if frame:IsMouseOver() then
			StartTimer(HOVER_RECHECK_SECONDS)
		else
			fadeOut:Play()
		end
	end)
end

-- A nickname as given, otherwise only the first name, to leave room for the text.
local function ShortName(key, conv)
	local label = ns.Store.LabelFor(key, conv)
	return conv.nick and label or label:match("^%S+") or label
end

function Glance.Show(key, conv, record)
	if not frame then Create() end
	local name = ShortName(key, conv)
	if record.f == ns.Capture.FLAG_GM then name = name .. "  GM" end
	lines[#lines + 1] = {
		key = key,
		name = name,
		class = conv.class,
		text = ns.Emoji.Display(record.x),
	}
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end

	Render()
	fadeOut:Stop()
	frame:SetAlpha(1)
	frame:Show()
	StartTimer(VISIBLE_SECONDS)
end

function Glance.Hide()
	lines = {}
	if not frame then return end
	if timer then timer:Cancel() end
	fadeOut:Stop()
	frame:Hide()
end

-- The lines on show, oldest first.
function Glance.Lines()
	return lines
end

ns.On("THEME_CHANGED", function()
	if frame then Render() end
end)

-- A strip that catches clicks has no place in a fight.
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:SetScript("OnEvent", function() Glance.Hide() end)
