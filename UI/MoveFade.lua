local _, ns = ...

-- Makes the open window see-through while the character moves, so the world
-- stays visible. Only the look changes: the window can still be clicked, and
-- messages in it still count as read. Blizzard's movement fader can't be used
-- because it would overwrite the opacity of the combat fade.
local MoveFade = {}
ns.MoveFade = MoveFade

local FADE_OUT_SECONDS = 0.3
local FADE_IN_SECONDS = 0.15
local EPSILON = 0.001

local function TargetAlpha()
	local fade = ns.Get("moveFade") and IsPlayerMoving() and not InCombatLockdown()
	return fade and ns.Get("moveFadeOpacity") / 100 or 1
end

local function Step(current, target, elapsed)
	if target < current then
		return math.max(target, current - elapsed / FADE_OUT_SECONDS)
	end
	return math.min(target, current + elapsed / FADE_IN_SECONDS)
end

function MoveFade.Update(window, elapsed)
	-- The combat fade owns the window's opacity while it is active.
	if ns.Window.IsFaded() then return end

	local inUse = window:IsMouseOver() or ns.Composer.HasFocus() or ns.Sidebar.HasSearchFocus()
	local target = inUse and 1 or TargetAlpha()
	local current = window:GetAlpha()
	if math.abs(current - target) > EPSILON then
		window:SetAlpha(Step(current, target, elapsed))
	end
end

-- The driver is a child of the window, so it costs nothing while the window is closed.
function MoveFade.Attach(window)
	local driver = CreateFrame("Frame", nil, window)
	driver:SetScript("OnUpdate", function(_, elapsed) MoveFade.Update(window, elapsed) end)
end

-- A window closed while running opens solid again.
function MoveFade.Reset(window)
	if not ns.Window.IsFaded() then window:SetAlpha(1) end
end
