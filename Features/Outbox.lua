local _, ns = ...
local L = ns.L

-- Messages written during a chat restriction. Sending needs a key press or
-- click, so they wait for one after the restriction ends. Memory only.
local Outbox = {}
ns.Outbox = Outbox

local MAX_WAITING = 20

local entries = {} -- oldest first: { key, notice, reply }

function Outbox.Count()
	return #entries
end

function Outbox.IsReady()
	return #entries > 0 and not ns.Lockdown.IsActive()
end

local function CanEverReceive(key)
	local category = ns.CategoryOf(key)
	return category ~= "live" and category ~= "nearby"
end

-- Returns true, or false and a reason in Send's vocabulary.
function Outbox.Add(key, text, reply)
	text = ns.Util.Trim(text)
	if not CanEverReceive(key) then return false, "restricted" end
	if #entries >= MAX_WAITING then return false, "restricted" end
	if not ns.Send.SplitMessage(text) then return false, "tooLong" end

	local notice = { kind = "queued", t = GetServerTime(), text = text }
	entries[#entries + 1] = { key = key, notice = notice, reply = reply }
	ns.Store.AddNotice(key, notice)
	ns.Fire("OUTBOX_CHANGED")
	return true
end

local function Remove(entry)
	for index, candidate in ipairs(entries) do
		if candidate == entry then
			table.remove(entries, index)
			break
		end
	end
	ns.Store.RemoveNotice(entry.key, entry.notice)
end

local function FindEntry(notice)
	for _, entry in ipairs(entries) do
		if entry.notice == notice then return entry end
	end
	return nil
end

-- Must be called from a click or key press, like Send.Text.
local function SendEntry(entry)
	local ok, reason = ns.Send.Text(entry.key, entry.notice.text, entry.reply)
	if ok then Remove(entry) end
	return ok, reason
end

function Outbox.SendNotice(notice)
	local entry = FindEntry(notice)
	if not entry then return end
	local ok, reason = SendEntry(entry)
	if not ok then ns.Print(ns.Send.ReasonText(reason)) end
	ns.Fire("OUTBOX_CHANGED")
end

function Outbox.Discard(notice)
	local entry = FindEntry(notice)
	if not entry then return end
	Remove(entry)
	ns.Fire("OUTBOX_CHANGED")
end

function Outbox.SendAll()
	local failure
	for _, entry in ipairs({ unpack(entries) }) do
		local ok, reason = SendEntry(entry)
		if not ok then failure = reason end
	end
	if failure then ns.Print(ns.Send.ReasonText(failure)) end
	ns.Fire("OUTBOX_CHANGED")
end

ns.On("LOCKDOWN_CHANGED", function(active)
	if not active and #entries > 0 then
		ns.Print(L["%d waiting messages can be sent now. Open Hangout and press Enter."]:format(#entries))
	end
	ns.Fire("OUTBOX_CHANGED")
end)
