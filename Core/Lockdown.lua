local _, ns = ...

local Lockdown = {}
ns.Lockdown = Lockdown

local active = false
local simulated = false

function Lockdown.IsActive()
	return simulated or C_ChatInfo.InChatMessagingLockdown()
end

local function Refresh()
	local now = Lockdown.IsActive()
	if now ~= active then
		active = now
		ns.Fire("LOCKDOWN_CHANGED", active)
	end
end

-- For /hangout test: restrictions are hard to cause on demand.
function Lockdown.Simulate(enabled)
	simulated = enabled
	Refresh()
end

function Lockdown.IsSimulated()
	return simulated
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
