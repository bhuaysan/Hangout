local _, ns = ...

local Lockdown = {}
ns.Lockdown = Lockdown

local active = false

function Lockdown.IsActive()
	return C_ChatInfo.InChatMessagingLockdown()
end

local function Refresh()
	local now = Lockdown.IsActive()
	if now ~= active then
		active = now
		ns.Fire("LOCKDOWN_CHANGED", active)
	end
end

function Lockdown.Init()
	active = Lockdown.IsActive()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	frame:SetScript("OnEvent", function()
		-- Restriction state is not settled while this event is dispatching.
		C_Timer.After(0, Refresh)
		C_Timer.After(1, Refresh)
	end)
end
