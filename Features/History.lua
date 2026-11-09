local _, ns = ...

-- A per-session ring of what the player sent, so Up/Down can bring it back.
local History = {}
ns.History = History

local MAX = 50

local ring = {}
-- Position being shown while browsing, or nil when not browsing.
local index
-- What the box held before browsing began, restored when walking back past the newest entry.
local draft = ""

function History.Reset()
	index = nil
	draft = ""
end

function History.IsBrowsing()
	return index ~= nil
end

function History.Clear()
	ring = {}
	History.Reset()
end

function History.Count()
	return #ring
end

function History.Push(text)
	History.Reset()
	if not text or text == "" or ring[#ring] == text then return end
	ring[#ring + 1] = text
	if #ring > MAX then table.remove(ring, 1) end
end

-- Returns the previous entry, or nil when there is nothing older to show.
function History.Older(current)
	if #ring == 0 then return nil end
	if not index then
		draft = current or ""
		index = #ring + 1
	end
	if index <= 1 then return nil end
	index = index - 1
	return ring[index]
end

-- Returns the next newer entry, ending with the text typed before browsing; nil when not browsing.
function History.Newer()
	if not index then return nil end
	index = index + 1
	if index > #ring then
		local text = draft
		History.Reset()
		return text
	end
	return ring[index]
end
