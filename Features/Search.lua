local _, ns = ...
local L = ns.L

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

-- Splits a query into filters and the words to look for. "from:Name" or
-- from:"First Last" limits who wrote the message, "in:this" limits the chat.
-- explicitScope tells whether the query chose a scope itself, so the sidebar's
-- toggle only applies when it didn't.
function Search.ParseQuery(text)
	local rest = " " .. (text or ""):lower() .. " "
	local parsed = { from = nil, scope = "all", explicitScope = false }

	rest = rest:gsub('%sfrom:"([^"]*)"', function(name)
		parsed.from = name ~= "" and ns.Util.Trim(name) or nil
		return " "
	end)
	rest = rest:gsub("%sfrom:(%S+)", function(name)
		parsed.from = name
		return " "
	end)
	rest = rest:gsub("%sin:(%S+)", function(scope)
		if scope == "this" or scope == "all" then
			parsed.scope = scope
			parsed.explicitScope = true
			return " "
		end
		-- An unknown scope stays in the text rather than silently vanishing.
		return " in:" .. scope
	end)

	parsed.needle = ns.Util.Trim((rest:gsub("%s+", " ")))
	return parsed
end

-- Wraps every occurrence of the needle in a color code so matches stand out.
-- colorHex is six hex digits, like "ffd100".
function Search.Highlight(text, needle, colorHex)
	if needle == "" then return text end
	local lowered = text:lower()
	local pieces, position = {}, 1
	while true do
		local first, last = lowered:find(needle, position, true)
		if not first then break end
		pieces[#pieces + 1] = text:sub(position, first - 1)
		pieces[#pieces + 1] = "|cff" .. colorHex .. text:sub(first, last) .. "|r"
		position = last + 1
	end
	pieces[#pieces + 1] = text:sub(position)
	return table.concat(pieces)
end

-- Converts 0..1 color floats to the hex digits a color code wants.
function Search.HexColor(r, g, b)
	local function channel(value)
		return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
	end
	return string.format("%02x%02x%02x", channel(r), channel(g), channel(b))
end

-- defaultScope is the sidebar toggle; an "in:" in the query overrides it.
function Search.NewState(query, list, selectedKey, defaultScope)
	local parsed = Search.ParseQuery(query)
	local scope = parsed.explicitScope and parsed.scope or defaultScope or parsed.scope
	if scope == "this" then
		local only = {}
		for _, entry in ipairs(list) do
			if entry.key == selectedKey then only[#only + 1] = entry end
		end
		list = only
	end
	return {
		needle = parsed.needle,
		from = parsed.from,
		scope = scope,
		list = list,
		conversationIndex = 1,
		messageIndex = nil,
		results = {},
	}
end

-- Whether the message's author matches a "from:" filter. Names match from the
-- start, so "from:thr" finds "Thrall Horde" and "from:jaina p" finds Jaina P.
local function SenderMatches(from, entry, message)
	if message.o == 1 then
		return from == "me" or from == "you"
	end
	local sender = message.s or entry.conv.name
	if not sender then return false end
	sender = sender:lower()
	if sender:sub(1, #from) == from then return true end
	return ns.Util.DisplayName(sender):lower():sub(1, #from) == from
end

local function SenderOf(entry, message)
	if message.o == 1 then return L["You"] end
	if message.s then return ns.Store.SenderLabel(message.s) end
	return ns.Store.LabelFor(entry.key, entry.conv)
end

local function CheckMessage(state, entry, message)
	if state.from and not SenderMatches(state.from, entry, message) then return end
	local visible = Search.VisibleText(message.x)
	if state.needle == "" or visible:lower():find(state.needle, 1, true) then
		state.results[#state.results + 1] = {
			key = entry.key,
			id = message.i,
			label = ns.Store.LabelFor(entry.key, entry.conv),
			sender = SenderOf(entry, message),
			time = message.t,
			needle = state.needle,
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
-- onResults gets the results so far and whether the search has finished.
function Search.Run(query, onResults, defaultScope)
	generation = generation + 1
	local mine = generation
	local state = Search.NewState(query, ns.Store.List(), ns.selectedKey, defaultScope)
	local reportedCount = -1

	local function step()
		if mine ~= generation then return end
		local started = debugprofilestop()
		local finished = Search.Advance(state, function()
			return debugprofilestop() - started >= FRAME_BUDGET_MS
		end)
		-- Showing results costs time outside the frame budget, so only do it for news.
		if finished or #state.results ~= reportedCount then
			reportedCount = #state.results
			onResults(state.results, finished)
		end
		if not finished then
			C_Timer.After(0, step)
		end
	end
	step()
end

function Search.Cancel()
	generation = generation + 1
end
