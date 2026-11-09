local _, ns = ...

-- A LibDataBroker feed for display addons such as Titan Panel, Bazooka and
-- ChocolateBar. Hangout embeds no libraries, so this stays idle unless one of
-- those addons has already loaded LibDataBroker.
local Broker = {}
ns.Broker = Broker

local MAX_TOOLTIP_CHATS = 5
local ICON = "Interface\\AddOns\\Hangout\\Media\\icon.png"
local UPDATE_DELAY = 0.1

local dataObject

-- Pure: the text shown in the display addon's bar.
function Broker.Text(total, dnd, quiet)
	local text = ns.Util.BadgeText(total)
	if dnd then
		text = text .. " (DND)"
	elseif quiet then
		text = text .. " (Quiet)"
	end
	return text
end

-- Pure: up to MAX_TOOLTIP_CHATS unread chats from a Store.List() result.
-- Returns { { name = ..., count = ... } }; the list is already newest first.
function Broker.TooltipLines(list)
	local lines = {}
	for _, entry in ipairs(list) do
		local conv = entry.conv
		if not conv.req then
			local count = ns.Store.UnreadCount(entry.key, conv)
			if count > 0 then
				lines[#lines + 1] = { name = conv.name or entry.key, count = count }
				if #lines == MAX_TOOLTIP_CHATS then break end
			end
		end
	end
	return lines
end

local function Update()
	if not dataObject then return end
	dataObject.text = Broker.Text(ns.Store.TotalUnread(), ns.Get("dnd"), ns.Quiet.IsActive())
end

local function ShowTooltip(tooltip)
	tooltip:AddLine("Hangout")
	local lines = Broker.TooltipLines(ns.Store.List())
	if #lines == 0 then
		tooltip:AddLine("No unread messages", 1, 1, 1)
	end
	for _, line in ipairs(lines) do
		tooltip:AddDoubleLine(line.name, line.count, 1, 1, 1, 1, 1, 1)
	end
	tooltip:AddLine("Click to open. Right-click for options.", 0.6, 0.6, 0.6)
end

-- Returns true if a data object was created. Safe without LibDataBroker.
function Broker.Init()
	if dataObject then return true end
	if not LibStub then return false end
	local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
	if not ldb then return false end

	dataObject = ldb:NewDataObject("Hangout", {
		type = "launcher",
		icon = ICON,
		label = "Hangout",
		text = "0",
		OnClick = function(frame, button)
			if button == "RightButton" then
				ns.Launcher.ShowMenu(frame)
			else
				ns.Window.Toggle()
			end
		end,
		OnTooltipShow = ShowTooltip,
	})
	Update()
	return true
end

local updateSoon = ns.Util.Debounced(UPDATE_DELAY, Update)
for _, message in ipairs({ "CONV_CHANGED", "MESSAGE_ADDED", "CONV_READ", "LIVE_CHANGED", "DND_CHANGED", "QUIET_CHANGED" }) do
	ns.On(message, updateSoon)
end
