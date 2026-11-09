local _, ns = ...
local L = ns.L

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
local DIM_ALPHA = 0.45
local SLIDE_IN_DISTANCE = 14
local SLIDE_IN_SECONDS = 0.25
local ROW_SLIDE_DISTANCE = 10
local ROW_SLIDE_SECONDS = 0.2
local FLASH_ALPHA = 0.28
local FLASH_SECONDS = 0.9
local BAR_WIDTH = 2
local BAR_LEFT = 3
local BREATHE_LOW_ALPHA = 0.3
local BREATHE_SECONDS = 1.4
local DEFAULT_X, DEFAULT_Y = 20, 290 -- just above the default chat window
local DRAG_CLICK_GUARD_SECONDS = 0.05

local frame, timer, fadeOut, slideIn, breathe
local rows = {}
local lines = {}
local dragEndedAt = 0
-- After a while the strip stays on screen, but quietly.
local dimmed = false

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

-- The mouse brings a dimmed strip back to full strength, so it can be read.
local function Brighten()
	if not dimmed then return end
	fadeOut:Stop()
	breathe:Stop()
	frame:SetAlpha(1)
end

local function StartDimming()
	fadeOut:Play()
	breathe:Play()
end

local function DimAgain()
	if dimmed and not frame:IsMouseOver() then
		StartDimming()
	end
end

-- Starts the region out of place and invisible, then eases it to where it belongs.
local function AddEntrance(group, offsetX, offsetY, seconds)
	local jump = group:CreateAnimation("Translation")
	jump:SetOffset(-offsetX, -offsetY)
	jump:SetDuration(0)
	jump:SetOrder(1)

	local hidden = group:CreateAnimation("Alpha")
	hidden:SetFromAlpha(0)
	hidden:SetToAlpha(0)
	hidden:SetDuration(0)
	hidden:SetOrder(1)

	local slide = group:CreateAnimation("Translation")
	slide:SetOffset(offsetX, offsetY)
	slide:SetDuration(seconds)
	slide:SetSmoothing("OUT")
	slide:SetOrder(2)

	local reveal = group:CreateAnimation("Alpha")
	reveal:SetFromAlpha(0)
	reveal:SetToAlpha(1)
	reveal:SetDuration(seconds)
	reveal:SetSmoothing("OUT")
	reveal:SetOrder(2)
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
	row:SetScript("OnEnter", function()
		hover:Show()
		Brighten()
	end)
	row:SetScript("OnLeave", function()
		hover:Hide()
		DimAgain()
	end)

	row.crest = ns.Widgets.ClassCrest(row, CREST_SIZE)
	row.crest:SetPoint("LEFT", CREST_LEFT, 0)

	row.name = ns.Widgets.Text(row, "HangoutFontBold", "text")
	row.name:SetWordWrap(false)

	row.body = ns.Widgets.Text(row, "HangoutFont", "text")
	row.time = ns.Widgets.Text(row, "HangoutFontSmall", "muted")
	row.time:SetPoint("RIGHT", -6, 0)

	row.body:SetPoint("LEFT", row.name, "RIGHT", 7, 0)
	row.body:SetPoint("RIGHT", row.time, "LEFT", -7, 0)
	row.body:SetWordWrap(false)

	-- A new line slides in and glows for a moment, so it stands out from the older ones.
	row.arrive = row:CreateAnimationGroup()
	AddEntrance(row.arrive, ROW_SLIDE_DISTANCE, 0, ROW_SLIDE_SECONDS)

	row.flash = ns.Widgets.Solid(row, "accent", "BACKGROUND")
	row.flash:SetAllPoints()
	row.flash:Hide()
	row.glow = row.flash:CreateAnimationGroup()
	local glow = row.glow:CreateAnimation("Alpha")
	glow:SetFromAlpha(FLASH_ALPHA)
	glow:SetToAlpha(0)
	glow:SetDuration(FLASH_SECONDS)
	row.glow:SetScript("OnFinished", function() row.flash:Hide() end)
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
	frame:SetScript("OnEnter", Brighten)
	frame:SetScript("OnLeave", DimAgain)
	frame:Hide()
	RestorePosition()

	ns.Widgets.RoundedFill(frame, "glance"):SetAllPoints()
	ns.Widgets.Border(frame, "edge")

	-- Stays quietly alive while the strip is dimmed, as a sign that something is waiting.
	local bar = ns.Widgets.Solid(frame, "accent", "ARTWORK")
	bar:SetPoint("TOPLEFT", BAR_LEFT, -PADDING)
	bar:SetPoint("BOTTOMLEFT", BAR_LEFT, PADDING)
	bar:SetWidth(BAR_WIDTH)
	breathe = bar:CreateAnimationGroup()
	breathe:SetLooping("BOUNCE")
	local pulse = breathe:CreateAnimation("Alpha")
	pulse:SetFromAlpha(1)
	pulse:SetToAlpha(BREATHE_LOW_ALPHA)
	pulse:SetDuration(BREATHE_SECONDS)
	pulse:SetSmoothing("IN_OUT")

	slideIn = frame:CreateAnimationGroup()
	AddEntrance(slideIn, 0, SLIDE_IN_DISTANCE, SLIDE_IN_SECONDS)

	for index = 1, MAX_LINES do
		rows[index] = CreateRow(index)
	end

	fadeOut = frame:CreateAnimationGroup()
	local alpha = fadeOut:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(DIM_ALPHA)
	alpha:SetDuration(FADE_SECONDS)
	fadeOut:SetToFinalAlpha(true)
	fadeOut:SetScript("OnFinished", function() frame:SetAlpha(DIM_ALPHA) end)
end

local function Render()
	frame:SetHeight(#lines * LINE_HEIGHT + PADDING * 2)
	for index, row in ipairs(rows) do
		local line = lines[index]
		row.line = line
		row:SetShown(line ~= nil)
		row.arrive:Stop()
		row.glow:Stop()
		row.flash:Hide()
		if line then
			row.time:SetText(line.time)
			local hasCrest = ns.Widgets.SetClassCrest(row.crest, line.class)
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", hasCrest and TEXT_LEFT_WITH_CREST or TEXT_LEFT, 0)
			row.name:SetText(line.name)
			row.name:SetTextColor(ns.Theme.ClassColor(line.class, "popup"))
			row.body:SetText(line.text)
		end
	end
end

-- Stays at full strength while the mouse is on it, then dims and waits to be dealt with.
local function StartTimer(seconds)
	if timer then timer:Cancel() end
	timer = C_Timer.NewTimer(seconds, function()
		if frame:IsMouseOver() then
			StartTimer(HOVER_RECHECK_SECONDS)
		else
			dimmed = true
			StartDimming()
		end
	end)
end

local function PlayNewLine(row)
	row.arrive:Play()
	row.flash:Show()
	row.glow:Play()
end

-- A nickname as given, otherwise only the first name, to leave room for the text.
local function ShortName(key, conv)
	local label = ns.Store.LabelFor(key, conv)
	return conv.nick and label or label:match("^%S+") or label
end

function Glance.Show(key, conv, record)
	if not frame then Create() end
	local name = ShortName(key, conv)
	if record.f == ns.Capture.FLAG_GM then name = name .. "  " .. L["GM"] end
	lines[#lines + 1] = {
		key = key,
		name = name,
		class = conv.class,
		text = ns.Emoji.Display(record.x),
		time = date("%H:%M", record.t),
	}
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end

	local alreadyShown = frame:IsShown()
	Render()
	fadeOut:Stop()
	breathe:Stop()
	dimmed = false
	frame:SetAlpha(1)
	frame:Show()
	if alreadyShown then
		PlayNewLine(rows[#lines])
	else
		slideIn:Play()
	end
	StartTimer(VISIBLE_SECONDS)
end

function Glance.Hide()
	lines = {}
	dimmed = false
	if not frame then return end
	if timer then timer:Cancel() end
	fadeOut:Stop()
	breathe:Stop()
	slideIn:Stop()
	frame:Hide()
end

-- The lines on show, oldest first.
function Glance.Lines()
	return lines
end

function Glance.IsDimmed()
	return dimmed
end

-- Drops a chat's lines once there is nothing left to be reminded of.
function Glance.Forget(key)
	local kept = {}
	for _, line in ipairs(lines) do
		if line.key ~= key then kept[#kept + 1] = line end
	end
	if #kept == #lines then return end
	lines = kept
	if #lines == 0 then
		Glance.Hide()
	elseif frame then
		Render()
	end
end

ns.On("CONV_READ", Glance.Forget)

-- Answering from normal chat counts too. A whisper to yourself also echoes
-- as outgoing, and must not take its own line away.
ns.On("MESSAGE_ADDED", function(key, record)
	if record.o == 1 and key ~= "W:" .. ns.me then Glance.Forget(key) end
end)

ns.On("THEME_CHANGED", function()
	if frame then Render() end
end)

local function HideForCombat()
	if not frame then return end
	if timer then timer:Cancel() end
	fadeOut:Stop()
	breathe:Stop()
	slideIn:Stop()
	frame:Hide()
end

local function ShowAfterCombat()
	if not frame or #lines == 0 then return end
	dimmed = true
	frame:SetAlpha(DIM_ALPHA)
	frame:Show()
	breathe:Play()
end

-- A strip that catches clicks has no place in a fight, but its lines wait for the end of it.
local combatEvents = CreateFrame("Frame")
combatEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
combatEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
combatEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		HideForCombat()
	else
		ShowAfterCombat()
	end
end)
