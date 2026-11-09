local _, ns = ...
local L = ns.L

local Quiet = {}
ns.Quiet = Quiet

local INSTANCE_TYPES = { party = true, raid = true, pvp = true, arena = true }
local REASON_LABELS = { instance = L["instance"], raidCombat = L["raid combat"] }

local lastReason
-- The combat events fire before every API agrees that combat has started or
-- ended, so the event itself is trusted over InCombatLockdown.
local combatOverride

-- Pure decision: which automatic quiet rule applies, if any.
-- settings is a table with quietInInstance and quietInRaidCombat.
function Quiet.Evaluate(inInstance, instanceType, inCombat, inRaid, settings)
	if settings.quietInInstance and inInstance and INSTANCE_TYPES[instanceType] then
		return "instance"
	end
	if settings.quietInRaidCombat and inCombat and inRaid then
		return "raidCombat"
	end
	return nil
end

function Quiet.Reason()
	local inInstance, instanceType = IsInInstance()
	local inCombat = combatOverride
	if inCombat == nil then inCombat = InCombatLockdown() end
	return Quiet.Evaluate(inInstance, instanceType, inCombat, IsInRaid(), {
		quietInInstance = ns.Get("quietInInstance"),
		quietInRaidCombat = ns.Get("quietInRaidCombat"),
	})
end

function Quiet.IsActive()
	return Quiet.Reason() ~= nil
end

function Quiet.Label(reason)
	return REASON_LABELS[reason]
end

-- Announces only real changes, so listeners aren't refreshed on every roster event.
function Quiet.Update()
	local reason = Quiet.Reason()
	if reason ~= lastReason then
		lastReason = reason
		ns.Fire("QUIET_CHANGED", reason)
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		combatOverride = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		combatOverride = false
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- A loading screen can end combat without a regen event.
		combatOverride = nil
	end
	Quiet.Update()
end)
