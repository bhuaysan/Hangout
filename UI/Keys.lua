local _, ns = ...

local Keys = {}
ns.Keys = Keys

-- Every chat that can be stepped to, in the sidebar's visual order. Requests are left out
-- because opening one marks it read; the player opens those on purpose.
local function Steppable(list)
	local entries = {}
	for _, group in ipairs(ns.Sidebar.Groups(list)) do
		for _, entry in ipairs(group.entries) do
			if not entry.conv.req then
				entries[#entries + 1] = entry
			end
		end
	end
	return entries
end

-- The chat after (direction 1) or before (-1) currentKey as the sidebar lists them,
-- wrapping around. With unreadOnly only chats with unread messages count. Returns nil
-- when there is nowhere else to go.
function Keys.NextKey(list, currentKey, direction, unreadOnly)
	local entries = Steppable(list)
	local count = #entries
	if count == 0 then return nil end

	local position
	for index, entry in ipairs(entries) do
		if entry.key == currentKey then
			position = index
			break
		end
	end
	-- A current chat that isn't in the list (a request, or none) starts just outside the ends.
	if not position then
		position = direction > 0 and 0 or count + 1
	end

	for step = 1, count do
		local entry = entries[(position - 1 + direction * step) % count + 1]
		if entry.key ~= currentKey and (not unreadOnly or ns.Store.UnreadCount(entry.key, entry.conv) > 0) then
			return entry.key
		end
	end
	return nil
end

-- Opens the neighbouring chat. Returns whether it moved. refocus puts the cursor back in
-- the composer, for when the player was typing there.
function Keys.StepChat(direction, unreadOnly, refocus)
	local key = Keys.NextKey(ns.Store.List(), ns.selectedKey, direction, unreadOnly)
	if not key then return false end
	ns.Window.Open(key)
	if refocus and not ns.Window.IsFaded() then
		ns.Composer.Focus()
	end
	return true
end

-- Called from the composer's OnKeyDown. Returns true when the key was a Hangout shortcut.
function Keys.OnComposerKey(_, key)
	if (key == "UP" or key == "DOWN") and IsAltKeyDown() then
		Keys.StepChat(key == "DOWN" and 1 or -1, IsShiftKeyDown(), true)
		return true
	end
	if key == "K" and IsControlKeyDown() then
		ns.QuickSwitch.Toggle()
		return true
	end
	return nil
end
