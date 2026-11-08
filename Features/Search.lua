local _, ns = ...

local Search = {}
ns.Search = Search

local MAX_RESULTS = 200
local FRAME_BUDGET_MS = 3

local generation = 0

-- The text a player actually sees: no link data or color codes.
function Search.VisibleText(text)
	return (text:gsub("|H.-|h(.-)|h", "%1")
		:gsub("|c%x%x%x%x%x%x%x%x", "")
		:gsub("|cn[^:|]*:", "")
		:gsub("|r", ""))
end

function Search.NewState(query, list)
	return {
		needle = query:lower(),
		list = list,
		conversationIndex = 1,
		messageIndex = nil,
		results = {},
	}
end

local function CheckMessage(state, entry, message)
	local visible = Search.VisibleText(message.x)
	if visible:lower():find(state.needle, 1, true) then
		state.results[#state.results + 1] = {
			key = entry.key,
			id = message.i,
			label = ns.Store.LabelFor(entry.key, entry.conv),
			snippet = visible,
		}
	end
end

-- Scans newest messages first until done or outOfTime() says to pause.
-- Returns true when the search has finished.
function Search.Advance(state, outOfTime)
	while state.conversationIndex <= #state.list do
		local entry = state.list[state.conversationIndex]
		local messages = entry.conv.m
		-- The chat can be trimmed by new messages while a search is paused.
		state.messageIndex = math.min(state.messageIndex or #messages, #messages)

		while state.messageIndex >= 1 do
			CheckMessage(state, entry, messages[state.messageIndex])
			state.messageIndex = state.messageIndex - 1
			if #state.results >= MAX_RESULTS then return true end
			if outOfTime() then return false end
		end

		state.conversationIndex = state.conversationIndex + 1
		state.messageIndex = nil
	end
	return true
end

-- Runs a search over several frames so a big history can't stutter the game.
-- Starting a new search cancels the previous one.
function Search.Run(query, onResults)
	generation = generation + 1
	local mine = generation
	local state = Search.NewState(query, ns.Store.List())

	local function step()
		if mine ~= generation then return end
		local started = debugprofilestop()
		local finished = Search.Advance(state, function()
			return debugprofilestop() - started >= FRAME_BUDGET_MS
		end)
		onResults(state.results)
		if not finished then
			C_Timer.After(0, step)
		end
	end
	step()
end

function Search.Cancel()
	generation = generation + 1
end
