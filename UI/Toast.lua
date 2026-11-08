local _, ns = ...

local Toast = {}
ns.Toast = Toast

local WIDTH, HEIGHT = 300, 56
local VISIBLE_SECONDS = 6

local frame, title, body, timer
local currentKey
local wasDragged = false

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.Set("toastPosition", { point = point, relativePoint = relativePoint, x = x, y = y })
end

local function RestorePosition()
	local saved = ns.Get("toastPosition")
	if saved then
		frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -30)
	end
end

local function OnMouseUp(_, button)
	if wasDragged then
		wasDragged = false
		return
	end
	frame:Hide()
	if button == "LeftButton" and currentKey then
		ns.Window.Reply(currentKey)
	end
end

local function Create()
	frame = CreateFrame("Frame", "HangoutToast", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	RestorePosition()
	frame:Hide()

	frame:SetScript("OnDragStart", function()
		wasDragged = true
		frame:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
	frame:SetScript("OnMouseUp", OnMouseUp)

	ns.Widgets.Fill(frame, "sidebar")

	local bar = ns.Widgets.Solid(frame, "accent", "ARTWORK")
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("BOTTOMLEFT")
	bar:SetWidth(3)

	title = ns.Widgets.Text(frame, "GameFontNormal", "text")
	title:SetPoint("TOPLEFT", 12, -9)
	title:SetPoint("TOPRIGHT", -10, -9)
	title:SetWordWrap(false)

	body = ns.Widgets.Text(frame, "HangoutMessageFont", "muted")
	body:SetPoint("TOPLEFT", 12, -30)
	body:SetPoint("TOPRIGHT", -10, -30)
	body:SetWordWrap(false)
end

function Toast.Show(key, conv, record)
	if not frame then Create() end
	currentKey = key

	local name = ns.Store.LabelFor(key, conv)
	if record.s then
		name = name .. ": " .. ns.Store.SenderLabel(record.s)
		title:SetTextColor(ns.Theme.ClassColor(record.k, "sidebar"))
	else
		title:SetTextColor(ns.Theme.ClassColor(conv.class, "sidebar"))
	end
	title:SetText(name)
	body:SetText(ns.Emoji.Display(record.x))

	frame:Show()
	if timer then timer:Cancel() end
	timer = C_Timer.NewTimer(VISIBLE_SECONDS, function() frame:Hide() end)
end
