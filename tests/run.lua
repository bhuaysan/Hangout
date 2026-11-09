-- Run from the addon root: luajit tests/run.lua

package.path = "tests/?.lua;" .. package.path
local stubs = require("stubs")

local SCHEMA = 3

local function TocFiles()
	local files = {}
	for line in io.lines("Hangout.toc") do
		if line ~= "" and not line:match("^#") then
			files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
		end
	end
	return files
end

local function Load()
	stubs.Install()
	local ns = {}
	for _, path in ipairs(TocFiles()) do
		assert(loadfile(path))("Hangout", ns)
	end
	return ns
end

-- Boots the addon the way the client does: ADDON_LOADED, then PLAYER_LOGIN.
local function Boot(existingDB)
	local ns = Load()
	HangoutDB = existingDB
	local bootFrame = stubs.frames[1]
	bootFrame.OnEvent(bootFrame, "ADDON_LOADED", "Hangout")
	bootFrame.OnEvent(bootFrame, "PLAYER_LOGIN")
	return ns
end

-- Fires a chat event with the client's payload order.
local function Chat(ns, event, fields)
	ns.Capture.OnChatEvent(nil, event, fields.text, fields.name, "", fields.channelName or "", "",
		fields.flags or "", 0, fields.channelIndex or 0, fields.base or "", 0, fields.lineID or 1,
		fields.guid or "", fields.bn or 0)
end

local function Message(t, text)
	return { i = 1, t = t, x = text or "hello" }
end

local function Conversation(messages, extra)
	local conv = { nextId = #messages, m = messages, lastT = 0 }
	for key, value in pairs(extra or {}) do conv[key] = value end
	return conv
end

local function Database(conversations, settings)
	return { schema = SCHEMA, settings = settings or {}, theme = { custom = {} }, chars = {}, conv = conversations }
end

local function Equal(actual, expected, label)
	if actual ~= expected then
		error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local tests = {}
local function Test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

Test("every TOC file exists and compiles", function()
	for _, path in ipairs(TocFiles()) do
		assert(loadfile(path), path)
	end
end)

Test("names normalize to First Last from every form the game uses", function()
	local ns = Boot()
	Equal(ns.Util.NormalizeName("Dvalin Ambossträger"), "Dvalin Ambossträger")
	Equal(ns.Util.NormalizeName("Dvalin-Ambossträger"), "Dvalin Ambossträger")
	Equal(ns.Util.NormalizeName("Dvalin Ambossträger-SomeRealm"), "Dvalin Ambossträger")
	Equal(ns.Util.NormalizeName("Dvalin"), "Dvalin")
	Equal(ns.Util.NormalizeName(""), nil)
end)

Test("the player's own name includes the surname", function()
	local ns = Boot()
	Equal(ns.me, "Me Self")
	Equal(ns.db.chars[1], "Me Self")
end)

Test("display names hide the BattleTag number", function()
	local ns = Boot()
	Equal(ns.Util.DisplayName("Friend#1234"), "Friend")
	Equal(ns.Util.DisplayName("Dvalin Ambossträger"), "Dvalin Ambossträger")
end)

Test("settings only store non-default values", function()
	local ns = Boot()
	ns.Set("perChatCap", 100)
	Equal(ns.db.settings.perChatCap, 100)
	Equal(ns.Get("perChatCap"), 100)
	ns.Set("perChatCap", 500)
	Equal(ns.db.settings.perChatCap, nil)
	Equal(ns.Get("perChatCap"), 500)
end)

Test("whispers are stored in both directions under one key", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Thrall Hellscream", guid = "Player-1-ABC" })
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "yo", name = "Thrall-Hellscream", guid = "Player-1-ABC" })
	local conv = ns.db.conv["W:Thrall Hellscream"]
	Equal(#conv.m, 2)
	Equal(conv.class, "SHAMAN")
	Equal(conv.m[1].o, nil)
	Equal(conv.m[2].o, 1)
	Equal(conv.m[2].i, 2)
end)

Test("Battle.net whispers key on BattleTag and never store the real name", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_BN_WHISPER", { text = "hey", name = "Real Name", bn = 77 })
	local conv = ns.db.conv["B:Friend#1234"]
	Equal(#conv.m, 1)
	Equal(conv.name, "Friend#1234")
	Equal(conv.m[1].s, nil)
end)

Test("Battle.net whispers without a tag stay in memory", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_BN_WHISPER", { text = "hey", name = "Real Name", bn = 99 })
	Equal(ns.db.conv["B:?99"], nil)
	Equal(#ns.session.conv["B:?99"].m, 1)
end)

Test("guild history is keyed by guild and marks own messages", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Me Self" })
	Chat(ns, "CHAT_MSG_GUILD", { text = "ty", name = "Other Person" })
	local conv = ns.db.conv["G:Horde Heroes-Thunderstrike"]
	Equal(conv.m[1].o, 1)
	Equal(conv.m[2].o, nil)
	Equal(conv.m[2].s, "Other Person")
end)

Test("guild chat before guild data arrives stays in memory", function()
	local ns = Boot()
	stubs.guildName = nil
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Other Person" })
	Equal(#ns.session.conv["G:?"].m, 1)
end)

Test("public channels stay in memory unless opted in", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wts", name = "A B", base = "Trade - City", channelIndex = 2 })
	Equal(ns.db.conv["C:trade - city"], nil)
	Equal(#ns.session.conv["C:trade - city"].m, 1)
	Equal(ns.session.conv["C:trade - city"].channelIndex, 2)

	ns.db.settings.keepChannels = { ["C:trade - city"] = true }
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wtb", name = "A B", base = "Trade - City" })
	Equal(#ns.db.conv["C:trade - city"].m, 1)
end)

Test("session channels are capped by the ring size", function()
	local ns = Boot()
	ns.Set("sessionRing", 3)
	for i = 1, 5 do
		Chat(ns, "CHAT_MSG_CHANNEL", { text = "m" .. i, name = "A B", base = "Trade" })
	end
	local messages = ns.session.conv["C:trade"].m
	Equal(#messages, 3)
	Equal(messages[1].x, "m3")
end)

Test("GM whispers are flagged", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "Game Master", flags = "GM" })
	Equal(ns.db.conv["W:Game Master"].m[1].f, ns.Capture.FLAG_GM)
end)

Test("secret whispers are live-only and never reach saved data", function()
	local ns = Boot()
	local secretText = stubs.Secret()
	Chat(ns, "CHAT_MSG_WHISPER", { text = secretText, name = stubs.Secret(), lineID = 42 })
	Equal(next(ns.db.conv), nil, "saved conversations")
	local live = ns.Store.GetLive(ns.Capture.LOCKED_KEY)
	Equal(#live, 1)
	Equal(rawequal(live[1].text, secretText), true, "text retained for display")
	Equal(live[1].lineID, 42)
end)

Test("a secret sender with readable text is still treated as locked", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "visible", name = stubs.Secret() })
	Equal(next(ns.db.conv), nil)
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 1)
end)

Test("secret group messages attach to their real conversation", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_PARTY", { text = stubs.Secret(), name = stubs.Secret() })
	Equal(#ns.Store.GetLive("P:party"), 1)
	Equal(#ns.db.conv["P:party"].m, 0)
end)

Test("a secret channel name falls back to the restricted conversation", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = stubs.Secret(), name = stubs.Secret(),
		base = stubs.Secret(), channelName = stubs.Secret() })
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 1)
end)

Test("per-chat overflow trims back to the cap", function()
	local ns = Boot()
	ns.Set("perChatCap", 10)
	for i = 1, 61 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "m" .. i, name = "A B" })
	end
	local conv = ns.db.conv["W:A B"]
	Equal(#conv.m, 10)
	Equal(conv.m[10].x, "m61")
	Equal(conv.m[1].x, "m52")
end)

Test("prune removes expired messages by category", function()
	local now = 1000000 * 10
	local day = 86400
	local ns = Boot(Database({
		["W:A B"] = Conversation({ Message(now - 91 * day), Message(now - 89 * day) }),
		["G:X-R"] = Conversation({ Message(now - 15 * day), Message(now - 13 * day) }),
	}))
	ns.DB.Prune(now)
	Equal(#ns.db.conv["W:A B"].m, 1)
	Equal(#ns.db.conv["G:X-R"].m, 1)
end)

Test("pinned chats ignore age limits and empty chats are removed", function()
	local now = 1000000 * 10
	local old = now - 400 * 86400
	local ns = Boot(Database({
		["W:Pinned R"] = Conversation({ Message(old) }, { pin = true }),
		["W:Gone R"] = Conversation({ Message(old) }),
		["W:Noted R"] = Conversation({ Message(old) }, { note = "friend" }),
	}))
	ns.DB.Prune(now)
	Equal(#ns.db.conv["W:Pinned R"].m, 1)
	Equal(ns.db.conv["W:Gone R"], nil)
	Equal(#ns.db.conv["W:Noted R"].m, 0)
end)

Test("global cap evicts group history before whispers", function()
	local now = 1000000 * 10
	local recent = now - 1000
	local ns = Boot(Database({
		["W:A B"] = Conversation({ Message(recent + 1), Message(recent + 2), Message(recent + 3) }),
		["G:X-R"] = Conversation({ Message(recent + 4), Message(recent + 5), Message(recent + 6) }),
	}, { globalCap = 4 }))
	ns.DB.Prune(now)
	Equal(#ns.db.conv["W:A B"].m, 3)
	Equal(#ns.db.conv["G:X-R"].m, 1)
	Equal(ns.db.conv["G:X-R"].m[1].t, recent + 6)
end)

Test("global cap reaches whispers and pinned chats last", function()
	local now = 1000000 * 10
	local recent = now - 1000
	local ns = Boot(Database({
		["W:A B"] = Conversation({ Message(recent + 1), Message(recent + 2) }),
		["W:Pin R"] = Conversation({ Message(recent) }, { pin = true }),
	}, { globalCap = 1 }))
	ns.DB.Prune(now)
	Equal(ns.db.conv["W:A B"], nil)
	Equal(#ns.db.conv["W:Pin R"].m, 1)
end)

Test("schema 1 test data with wrong name keys is discarded", function()
	local saved = Database({ ["W:Dvalin-Realm"] = Conversation({ Message(1) }) })
	saved.schema = 1
	saved.chars = { "Dvalin-Realm" }
	local ns = Boot(saved)
	Equal(HangoutDB.schema, SCHEMA)
	Equal(next(HangoutDB.conv), nil)
	Equal(ns.db.chars[1], "Me Self")
end)

Test("migrations run in order and update the schema", function()
	local ns = Load()
	ns.DB.SCHEMA = 5
	local order = {}
	ns.DB.migrations[3] = function(db) order[#order + 1] = 3; db.a = true end
	ns.DB.migrations[4] = function(db) order[#order + 1] = 4; db.b = db.a end
	HangoutDB = Database({})
	ns.DB.Init()
	Equal(table.concat(order, ","), "3,4")
	Equal(HangoutDB.schema, 5)
	Equal(HangoutDB.b, true)
end)

Test("a database from a newer version is left untouched", function()
	local saved = Database({ ["W:A B"] = Conversation({ Message(1) }) })
	saved.schema = 99
	local ns = Boot(saved)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "new", name = "C D" })
	ns.DB.Prune(1000000000)
	Equal(HangoutDB.conv["W:C D"], nil)
	Equal(#HangoutDB.conv["W:A B"].m, 1)
	Equal(#ns.db.conv["W:C D"].m, 1)
end)

Test("characters are registered once", function()
	local ns = Boot()
	Equal(ns.charIndex, 1)
	ns.DB.RegisterCharacter("Alt Name")
	Equal(ns.charIndex, 2)
	ns.DB.RegisterCharacter("Me Self")
	Equal(ns.charIndex, 1)
	Equal(#ns.db.chars, 2)
end)

Test("conversation list is sorted by recent activity", function()
	local ns = Boot()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_WHISPER", { text = "a", name = "Old Friend" })
	stubs.serverTime = 200
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "b", name = "X Y", base = "Trade" })
	local list = ns.Store.List()
	Equal(list[1].key, "C:trade")
	Equal(list[2].key, "W:Old Friend")
end)

Test("lockdown changes fire once after the state settles", function()
	local ns = Boot()
	local fired = {}
	ns.On("LOCKDOWN_CHANGED", function(active) fired[#fired + 1] = active end)
	local frame
	for _, candidate in ipairs(stubs.frames) do
		if candidate.events.ADDON_RESTRICTION_STATE_CHANGED then frame = candidate end
	end
	stubs.lockdown = true
	frame.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED")
	frame.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED")
	stubs.lockdown = false
	frame.OnEvent(frame, "ADDON_RESTRICTION_STATE_CHANGED")
	Equal(#fired, 2)
	Equal(fired[1], true)
	Equal(fired[2], false)
end)

Test("short messages are sent as one part", function()
	local ns = Boot()
	local parts = ns.Send.SplitMessage("hello there")
	Equal(#parts, 1)
	Equal(parts[1], "hello there")
end)

Test("long messages split at spaces within the byte limit", function()
	local ns = Boot()
	local parts = ns.Send.SplitMessage(string.rep("word ", 100))
	Equal(#parts, 2)
	assert(#parts[1] <= 255)
	Equal(parts[1]:sub(-4), "word")
	Equal(parts[2]:sub(1, 4), "word")
end)

Test("splitting never breaks a UTF-8 character", function()
	local ns = Boot()
	local parts = ns.Send.SplitMessage(string.rep("ä", 200))
	Equal(#parts, 2)
	assert(#parts[1] % 2 == 0, "first part ends mid-character")
	assert(#parts[2] % 2 == 0, "second part ends mid-character")
end)

Test("splitting never breaks a link", function()
	local ns = Boot()
	local link = "|cffa335ee|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
	local parts = ns.Send.SplitMessage(string.rep("x", 240) .. link)
	Equal(#parts, 2)
	Equal(parts[2], link)
end)

Test("modern quality-coded links are also kept whole", function()
	local ns = Boot()
	local link = "|cnIQ4:|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r"
	local parts = ns.Send.SplitMessage(string.rep("x", 240) .. link)
	Equal(parts[2], link)
end)

Test("messages needing more than four parts are refused", function()
	local ns = Boot()
	Equal(ns.Send.SplitMessage(string.rep("x", 1100)), nil)
end)

Test("whispers are sent to the full name in the conversation key", function()
	local ns = Boot()
	Equal(ns.Send.Text("W:Dvalin Ambossträger", "  hi  "), true)
	Equal(stubs.sent[1].chatType, "WHISPER")
	Equal(stubs.sent[1].target, "Dvalin Ambossträger")
	Equal(stubs.sent[1].text, "hi")
end)

Test("group conversations use their chat types", function()
	local ns = Boot()
	ns.Send.Text("G:Horde Heroes-Thunderstrike", "a")
	ns.Send.Text("P:party", "b")
	ns.Send.Text("I:instance", "c")
	Equal(stubs.sent[1].chatType, "GUILD")
	Equal(stubs.sent[2].chatType, "PARTY")
	Equal(stubs.sent[3].chatType, "INSTANCE_CHAT")
end)

Test("channels send to the number seen in their latest message", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "x", name = "A B", base = "Trade", channelIndex = 5 })
	stubs.channels[5] = "Trade"
	Equal(ns.Send.Text("C:trade", "selling"), true)
	Equal(stubs.sent[1].chatType, "CHANNEL")
	Equal(stubs.sent[1].target, 5)
end)

Test("Battle.net sends resolve the account from the friend list", function()
	local ns = Boot()
	Equal(ns.Send.Text("B:Pal#5678", "hey"), true)
	Equal(stubs.bnetSent[1].id, 55)
end)

Test("sending is refused with a reason when it can't work", function()
	local ns = Boot()
	local function reason(key, text)
		local ok, why = ns.Send.Text(key, text)
		Equal(ok, false)
		return why
	end
	Equal(reason("W:A B", "   "), "empty")
	Equal(reason("W:A B", "/dance"), "slash")
	Equal(reason("W:A B", string.rep("x", 1100)), "tooLong")
	Equal(reason("B:Nobody#1", "hi"), "unavailable")
	Equal(reason("L:restricted", "hi"), "unavailable")
	stubs.lockdown = true
	Equal(reason("W:A B", "hi"), "restricted")
	Equal(#stubs.sent, 0)
end)

Test("messages group under one header until the sender or time changes", function()
	local ns = Boot()
	local base = 86400 * 100
	local conv = Conversation({
		{ t = base + 10, x = "one", s = "Ann B" },
		{ t = base + 20, x = "two", s = "Ann B" },
		{ t = base + 30, x = "three", s = "Cat D" },
		{ t = base + 400, x = "four", s = "Cat D" },
	})
	local elements = ns.MessageList.BuildElements(conv, 200)
	Equal(elements[1].kind, "day")
	Equal(elements[2].head, true)
	Equal(elements[3].head, false)
	Equal(elements[4].head, true)
	Equal(elements[5].head, true)
end)

Test("day separators use plain words for recent days", function()
	local ns = Boot()
	local noon = 86400 * 20000 + 43200
	local label = ns.MessageList.DayLabel
	Equal(label(noon, noon), "Today")
	Equal(label(noon - 86400, noon), "Yesterday")
	assert(not label(noon - 86400 * 2, noon):find("%-"), "an older day isn't shown as a numeric date")
	assert(label(noon - 86400 * 400, noon):find(", %d%d%d%d$"), "another year shows the year")
end)

Test("sidebar times are short and friendly", function()
	local ns = Boot()
	local noon = 86400 * 20000 + 43200
	Equal(ns.Util.ShortTime(noon, noon), "12:00")
	Equal(ns.Util.ShortTime(noon - 86400, noon), "Yesterday")
	Equal(ns.Util.ShortTime(noon - 86400 * 3, noon), "Nov 8")
end)

Test("a sidebar row previews the newest message", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello there", name = "Other Person" })
	Equal(ns.Sidebar.BuildElements(ns.Store.List())[2].preview, "hello there")
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "hi back", name = "Other Person" })
	Equal(ns.Sidebar.BuildElements(ns.Store.List())[2].preview, "You: hi back")
end)

Test("a group chat preview names who spoke, by first name", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Other Person" })
	local conv = ns.Store.List()[1]
	Equal(ns.Store.LastActivity(conv.key, conv.conv), "Other: gz")
end)

Test("a chat with no messages says so", function()
	local ns = Boot()
	ns.Store.StartWhisper("New Friend")
	Equal(ns.Sidebar.BuildElements(ns.Store.List())[2].preview, "No messages yet")
end)

Test("a locked message is never read for the preview", function()
	local ns = Boot()
	local conv = ns.Store.Ensure("W:Other Person", { name = "Other Person" })
	ns.session.live["W:Other Person"] = { { t = 2000000, text = stubs.Secret(), sender = stubs.Secret() } }
	local preview, time = ns.Store.LastActivity("W:Other Person", conv)
	Equal(preview, "Restricted message")
	Equal(time, 2000000)
end)

Test("Do Not Disturb announces every change", function()
	local ns = Boot()
	local changes = 0
	ns.On("DND_CHANGED", function() changes = changes + 1 end)
	ns.Launcher.SetDnd(true)
	Equal(ns.Get("dnd"), true)
	Equal(changes, 1)
end)

Test("the header line says what is known about a person", function()
	local ns = Boot()
	ns.Identity.Status = function() return "online" end
	Equal(ns.Window.SubtitleFor("W:A B", { class = "SHAMAN" }), "Online  ·  Schamane")
	Equal(ns.Window.SubtitleFor("W:A B", { class = "SHAMAN", note = "healer" }), "Online  ·  Schamane  ·  healer")
	ns.Identity.Status = function() return "afk" end
	Equal(ns.Window.SubtitleFor("W:A B", {}), "AFK")
	ns.Identity.Status = function() return nil end
	Equal(ns.Window.SubtitleFor("W:A B", {}), "")
end)

Test("the header line names group chats and channels", function()
	local ns = Boot()
	Equal(ns.Window.SubtitleFor("G:Horde Heroes", {}), "Group chat")
	Equal(ns.Window.SubtitleFor("C:trade", {}), "Channel")
end)

Test("the field color is solid so it hides what is behind it", function()
	local ns = Boot()
	local _, _, _, alpha = ns.Theme.Color("fieldSolid")
	Equal(alpha, 1)
end)

Test("reaction lists say whose reaction is whose", function()
	local ns = Boot()
	local list = ns.Protocol.ReactionList({ heart = 1, joy = 2, thumbsup = 3 })
	Equal(#list, 3)
	Equal(list[1].name, "heart")
	Equal(list[1].mine, true)
	Equal(list[1].count, 1)
	Equal(list[2].name, "joy")
	Equal(list[2].mine, false)
	Equal(list[3].count, 2)
	Equal(ns.Protocol.ReactionList(nil), nil)
	Equal(ns.Protocol.ReactionList({ heart = 0 }), nil, "nothing left to show")
end)

Test("the conversation opener speaks to who the chat is with", function()
	local ns = Boot()
	local whisper = ns.MessageList.OpenerFor("W:A B", { name = "A B", class = "SHAMAN" })
	Equal(whisper.kind, "opener")
	Equal(whisper.title, "A B")
	assert(whisper.text:find("A B", 1, true), "names the person")
	local channel = ns.MessageList.OpenerFor("C:trade", { name = "Trade" })
	assert(not channel.text:find("Trade", 1, true), "a channel gets the general line")
end)

Test("status follows the game's AFK flag", function()
	local ns = Boot()
	Equal(ns.ProfileBar.CurrentStatus(), "online")
	stubs.afk = true
	Equal(ns.ProfileBar.CurrentStatus(), "afk")
end)

Test("choosing Do Not Disturb sets the game's flag and silences alerts", function()
	local ns = Boot()
	ns.Launcher.SetDnd(true)
	Equal(ns.Get("dnd"), true)
	Equal(#stubs.sent, 1)
	Equal(stubs.sent[1].chatType, "DND")
	Equal(stubs.dnd, true)
	Equal(ns.ProfileBar.CurrentStatus(), "dnd")
end)

Test("switching from Do Not Disturb to AFK turns the old status off first", function()
	local ns = Boot()
	ns.Launcher.SetDnd(true)
	ns.ProfileBar.SetStatus("afk")
	Equal(ns.Get("dnd"), false)
	Equal(stubs.sent[2].chatType, "DND")
	Equal(stubs.sent[3].chatType, "AFK")
	Equal(stubs.dnd, false)
	Equal(stubs.afk, true)
end)

Test("switching from AFK to Do Not Disturb never leaves both on", function()
	local ns = Boot()
	ns.ProfileBar.SetStatus("afk")
	ns.ProfileBar.SetStatus("dnd")
	Equal(stubs.afk, false)
	Equal(stubs.dnd, true)
end)

Test("/dnd typed in chat silences Hangout too", function()
	local ns = Boot()
	stubs.dnd = true
	ns.ProfileBar.SyncFromGame()
	Equal(ns.Get("dnd"), true)
	stubs.dnd = false
	ns.ProfileBar.SyncFromGame()
	Equal(ns.Get("dnd"), false)
end)

Test("an unreadable game flag leaves the saved status alone", function()
	local ns = Boot()
	ns.Launcher.SetDnd(true)
	_G.UnitIsDND = function() return stubs.Secret() end
	ns.ProfileBar.SyncFromGame()
	Equal(ns.Get("dnd"), true)
end)

Test("choosing Online leaves AFK, and doesn't toggle when already online", function()
	local ns = Boot()
	ns.ProfileBar.SetStatus("online")
	Equal(#stubs.sent, 0, "already online")
	stubs.afk = true
	ns.ProfileBar.SetStatus("online")
	Equal(#stubs.sent, 1)
end)

Test("AFK can't be toggled during a chat restriction", function()
	local ns = Boot()
	stubs.lockdown = true
	ns.ProfileBar.SetStatus("afk")
	Equal(#stubs.sent, 0)
end)

Test("a new day adds a separator and restarts grouping", function()
	local ns = Boot()
	local base = 86400 * 100
	local conv = Conversation({
		{ t = base + 86300, x = "late", s = "Ann B" },
		{ t = base + 86500, x = "early", s = "Ann B" },
	})
	local elements = ns.MessageList.BuildElements(conv, 200)
	Equal(#elements, 4)
	Equal(elements[3].kind, "day")
	Equal(elements[4].head, true)
end)

Test("own messages show as You and older history is paged", function()
	local ns = Boot()
	local conv = Conversation({
		{ t = 1, x = "old" },
		{ t = 2, x = "mine", o = 1 },
	}, { name = "Friend#1234" })
	local elements = ns.MessageList.BuildElements(conv, 1)
	Equal(elements[1].kind, "older")
	Equal(elements[3].sender, "You")
	Equal(ns.MessageList.BuildElements(conv, 2)[2].sender, "Friend")
end)

Test("the sidebar groups conversations and omits empty sections", function()
	local ns = Boot()
	local elements = ns.Sidebar.BuildElements({
		{ key = "C:trade", conv = { name = "Trade" } },
		{ key = "W:A B", conv = { name = "A B" } },
		{ key = "B:Pal#5678", conv = { name = "Pal#5678" } },
	})
	Equal(elements[1].label, "WHISPERS")
	Equal(elements[2].key, "W:A B")
	Equal(elements[3].label, "Pal")
	Equal(elements[4].label, "CHANNELS")
	Equal(elements[5].key, "C:trade")
	Equal(#elements, 5)
end)

local function LockedChat(ns, event, lineID, fields)
	fields = fields or {}
	Chat(ns, event, { text = stubs.Secret(), name = stubs.Secret(), lineID = lineID,
		base = fields.base, channelIndex = fields.channelIndex, flags = fields.flags })
end

Test("recovered whispers are saved and the temporary chat disappears", function()
	local ns = Boot()
	stubs.serverTime = 500
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	stubs.chatLines[10] = { text = "hello", name = "Thrall Hellscream", guid = "Player-1-ABC" }
	stubs.serverTime = 900
	ns.Capture.Recover()
	local conv = ns.db.conv["W:Thrall Hellscream"]
	Equal(conv.m[1].x, "hello")
	Equal(conv.m[1].t, 500, "keeps the original time")
	Equal(conv.class, "SHAMAN")
	Equal(ns.Store.GetLive(ns.Capture.LOCKED_KEY), nil)
	Equal(ns.session.conv[ns.Capture.LOCKED_KEY], nil)
end)

Test("recovery runs when a restriction ends", function()
	local ns = Boot()
	stubs.lockdown = true
	ns.Fire("LOCKDOWN_CHANGED", true)
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	stubs.chatLines[10] = { text = "hello", name = "A B" }
	Equal(ns.db.conv["W:A B"], nil)
	ns.Fire("LOCKDOWN_CHANGED", false)
	Equal(#ns.db.conv["W:A B"].m, 1)
end)

Test("lines that are still secret or gone stay live-only", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	LockedChat(ns, "CHAT_MSG_WHISPER", 11)
	stubs.chatLines[10] = { text = stubs.Secret(), name = stubs.Secret() }
	ns.Capture.Recover()
	Equal(next(ns.db.conv), nil)
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 2)
	assert(ns.session.conv[ns.Capture.LOCKED_KEY])
end)

Test("outgoing whispers are saved under the partner", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_WHISPER_INFORM", 10)
	stubs.chatLines[10] = { text = "hey", name = "Thrall Hellscream" }
	ns.Capture.Recover()
	Equal(ns.db.conv["W:Thrall Hellscream"].m[1].o, 1)
end)

Test("an outgoing whisper naming only ourselves is never misfiled", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_WHISPER_INFORM", 10)
	stubs.chatLines[10] = { text = "hey", name = "Me Self" }
	ns.Capture.Recover()
	Equal(next(ns.db.conv), nil)
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 1)
end)

Test("Battle.net lines are not recovered", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_BN_WHISPER", 10)
	stubs.chatLines[10] = { text = "hey", name = "Real Name" }
	ns.Capture.Recover()
	Equal(next(ns.db.conv), nil)
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 1)
end)

Test("group lines recover into their chat with the sender", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_PARTY", 10)
	LockedChat(ns, "CHAT_MSG_PARTY", 11)
	stubs.chatLines[10] = { text = "pull", name = "Other Person" }
	stubs.chatLines[11] = { text = "ok", name = "Me Self" }
	ns.Capture.Recover()
	local messages = ns.db.conv["P:party"].m
	Equal(messages[1].s, "Other Person")
	Equal(messages[2].o, 1)
	Equal(ns.Store.GetLive("P:party"), nil)
end)

Test("channel lines recover to memory like other channel messages", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_CHANNEL", 10, { base = "Trade" })
	stubs.chatLines[10] = { text = "wts", name = "A B" }
	ns.Capture.Recover()
	Equal(ns.session.conv["C:trade"].m[1].x, "wts")
	Equal(ns.db.conv["C:trade"], nil)
end)

Test("recovered messages are placed in time order", function()
	local ns = Boot()
	stubs.serverTime = 100
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	stubs.chatLines[10] = { text = "older", name = "A B" }
	stubs.serverTime = 200
	Chat(ns, "CHAT_MSG_WHISPER", { text = "newer", name = "A B" })
	ns.Capture.Recover()
	local conv = ns.db.conv["W:A B"]
	Equal(conv.m[1].x, "older")
	Equal(conv.m[2].x, "newer")
	Equal(conv.lastT, 200)
end)

Test("locked rows are listed last without inspecting secret values", function()
	local ns = Boot()
	local conv = Conversation({ { t = 1, x = "old", s = "A B" } })
	local secretText = stubs.Secret()
	local elements = ns.MessageList.BuildElements(conv, 200, {
		{ t = 2, text = secretText, sender = stubs.Secret(), o = 1 },
	})
	local last = elements[#elements]
	Equal(last.kind, "locked")
	Equal(last.outgoing, true)
	Equal(rawequal(last.text, secretText), true)
end)

Test("incoming messages count as unread until the chat is read", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "one", name = "A B" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "two", name = "A B" })
	local conv = ns.db.conv["W:A B"]
	Equal(ns.Store.UnreadCount("W:A B", conv), 2)
	Equal(ns.Store.TotalUnread(), 2)
	ns.Store.MarkRead("W:A B")
	Equal(ns.Store.UnreadCount("W:A B", conv), 0)
	Equal(conv.readId, 2)
end)

Test("the chat being viewed never gains unread messages", function()
	local ns = Boot()
	ns.activeKey = "W:A B"
	Chat(ns, "CHAT_MSG_WHISPER", { text = "one", name = "A B" })
	local conv = ns.db.conv["W:A B"]
	Equal(ns.Store.UnreadCount("W:A B", conv), 0)
	Equal(conv.readId, 1)
end)

Test("replying clears a chat's unread count", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "one", name = "A B" })
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "yo", name = "A B" })
	Equal(ns.Store.UnreadCount("W:A B", ns.db.conv["W:A B"]), 0)
end)

Test("public channels never show unread counts", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wts", name = "A B", base = "Trade" })
	Equal(ns.Store.TotalUnread(), 0)
end)

Test("restricted messages count once, before and after recovery", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_PARTY", 10)
	Equal(ns.Store.TotalUnread(), 1)
	stubs.chatLines[10] = { text = "pull", name = "Other Person" }
	ns.Capture.Recover()
	Equal(ns.Store.TotalUnread(), 1)
end)

Test("pinned chats get their own section and leave their usual one", function()
	local ns = Boot()
	local elements = ns.Sidebar.BuildElements({
		{ key = "W:A B", conv = { name = "A B" } },
		{ key = "W:C D", conv = { name = "C D", pin = true } },
	})
	Equal(elements[1].label, "PINNED")
	Equal(elements[2].key, "W:C D")
	Equal(elements[3].label, "WHISPERS")
	Equal(elements[4].key, "W:A B")
	Equal(#elements, 4)
end)

Test("sidebar rows carry unread counts and class", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "a", name = "A B", guid = "Player-1-ABC" })
	local row = ns.Sidebar.BuildElements(ns.Store.List())[2]
	Equal(row.unread, 1)
	Equal(row.class, "SHAMAN")
end)

Test("presence combines friends, guild and Battle.net", function()
	local ns = Boot()
	stubs.friends = { { name = "Fri End", connected = true } }
	stubs.guildRoster = { { name = "Guild Mate-Realm", online = false } }
	stubs.bnetFriends = { { battleTag = "Pal#5678", bnetAccountID = 55,
		gameAccountInfo = { isOnline = true } } }
	local identityFrame
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then identityFrame = frame end
	end
	identityFrame.OnEvent()
	Equal(ns.Identity.Presence("W:Fri End"), true)
	Equal(ns.Identity.Presence("W:Guild Mate"), false)
	Equal(ns.Identity.Presence("B:Pal#5678"), true)
	Equal(ns.Identity.Presence("W:Stranger Here"), nil)
	Equal(ns.Identity.Presence("G:X-R"), nil)
end)

local function RescanPresence()
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then frame.OnEvent(frame) end
	end
end

local function BattleNetFriend(account, game)
	account.battleTag = account.battleTag or "Pal#5678"
	account.bnetAccountID = 55
	game.isOnline = game.isOnline ~= false
	account.gameAccountInfo = game
	stubs.bnetFriends = { account }
end

Test("a Battle.net friend's status follows the account and the game", function()
	local ns = Boot()
	local cases = {
		{ {}, {}, "online" },
		{ { isAFK = true }, {}, "afk" },
		{ {}, { isGameAFK = true }, "afk" },
		{ { isDND = true }, {}, "dnd" },
		{ {}, { isGameBusy = true }, "dnd" },
		{ { isAFK = true }, { isOnline = false }, "offline" },
		{ { isAFK = stubs.Secret() }, { isGameBusy = stubs.Secret() }, "online" },
	}
	for _, case in ipairs(cases) do
		BattleNetFriend(case[1], case[2])
		RescanPresence()
		Equal(ns.Identity.Status("B:Pal#5678"), case[3])
	end
	Equal(ns.Identity.Presence("B:Pal#5678"), true, "away still counts as online")
end)

Test("friends and guild members show AFK and busy too", function()
	local ns = Boot()
	stubs.friends = { { name = "Fri End", connected = true, afk = true },
		{ name = "Bus Y", connected = true, dnd = true } }
	stubs.guildRoster = { { name = "Guild Afk", online = true, status = 1 },
		{ name = "Guild Busy", online = true, status = 2 },
		{ name = "Guild Off", online = false, status = 1 } }
	RescanPresence()
	Equal(ns.Identity.Status("W:Fri End"), "afk")
	Equal(ns.Identity.Status("W:Bus Y"), "dnd")
	Equal(ns.Identity.Status("W:Guild Afk"), "afk")
	Equal(ns.Identity.Status("W:Guild Busy"), "dnd")
	Equal(ns.Identity.Status("W:Guild Off"), "offline")
end)

Test("a Battle.net chat keeps the class its friend was last seen playing", function()
	local ns = Boot()
	ns.Store.Ensure("B:Pal#5678", { name = "Pal#5678" })
	BattleNetFriend({}, { clientProgram = "WoW", classFilename = "SHAMAN" })
	RescanPresence()
	Equal(ns.Store.Get("B:Pal#5678").class, "SHAMAN")

	BattleNetFriend({}, { clientProgram = "App", isOnline = false })
	RescanPresence()
	Equal(ns.Store.Get("B:Pal#5678").class, "SHAMAN")
end)

Test("a Battle.net friend's class falls back to the class ID and ignores unusable values", function()
	local ns = Boot()
	ns.Store.Ensure("B:Pal#5678", { name = "Pal#5678" })
	BattleNetFriend({}, { clientProgram = "WoW", classFilename = stubs.Secret(), classID = 7 })
	RescanPresence()
	Equal(ns.Store.Get("B:Pal#5678").class, "SHAMAN")

	ns.Store.Get("B:Pal#5678").class = nil
	BattleNetFriend({}, { clientProgram = "WoW", classFilename = "NOT_A_CLASS" })
	RescanPresence()
	Equal(ns.Store.Get("B:Pal#5678").class, nil)
	BattleNetFriend({}, { clientProgram = "Pro", classFilename = "SHAMAN" })
	RescanPresence()
	Equal(ns.Store.Get("B:Pal#5678").class, nil, "only WoW has classes")
end)

Test("a new Battle.net chat starts with the friend's class", function()
	local ns = Boot()
	stubs.bnetTags[55] = "Pal#5678"
	BattleNetFriend({}, { clientProgram = "WoW", classFilename = "SHAMAN" })
	RescanPresence()
	Chat(ns, "CHAT_MSG_BN_WHISPER", { text = "hi", bn = 55 })
	Equal(ns.Store.Get("B:Pal#5678").class, "SHAMAN")
end)

Test("an avatar shows the Battle.net friends icon only for Battle.net friends without a class", function()
	local ns = Boot()
	local function Avatar()
		local avatar = {}
		for _, part in ipairs({ "crest", "slot", "icon", "letter", "status" }) do
			avatar[part] = {
				SetShown = function(self, shown) self.shown = shown end,
				SetTexture = function(self, path) self.path = path end,
				SetTexCoord = function() end, SetDesaturated = function() end,
				SetText = function() end, ClearAllPoints = function() end, SetPoint = function() end,
			}
		end
		return avatar
	end

	local avatar = Avatar()
	ns.Widgets.ShowChatAvatar(avatar, { key = "B:Pal#5678", label = "Pal", status = "afk" })
	assert(avatar.crest.path:find("Battlenet%-Portrait"), "uses the Battle.net friends icon")
	Equal(avatar.crest.shown, true)
	Equal(avatar.letter.shown, false)
	assert(avatar.status.path:find("StatusIcon%-Away"), "shows the away dot")

	avatar = Avatar()
	ns.Widgets.ShowChatAvatar(avatar, { key = "B:Pal#5678", label = "Pal", class = "SHAMAN" })
	assert(avatar.crest.path:find("UI%-CharacterCreate%-Classes"), "a known class wins")

	avatar = Avatar()
	ns.Widgets.ShowChatAvatar(avatar, { key = "W:Some One", label = "Some One" })
	Equal(avatar.crest.shown, false)
	Equal(avatar.letter.shown, true)
end)

Test("secret presence data is skipped safely", function()
	local ns = Boot()
	stubs.friends = { { name = stubs.Secret(), connected = stubs.Secret() } }
	stubs.guildRoster = { { name = stubs.Secret(), online = stubs.Secret() } }
	local identityFrame
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then identityFrame = frame end
	end
	identityFrame.OnEvent()
	Equal(ns.Identity.Presence("W:Anyone Here"), nil)
end)

Test("group senders keep their class and own messages use the player's", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_GUILD", { text = "hi", name = "Other Person", guid = "Player-1-ABC" })
	local conv = ns.db.conv["G:Horde Heroes-Thunderstrike"]
	Equal(conv.m[1].k, "SHAMAN")
	Equal(ns.MessageList.BuildElements(conv, 200)[2].class, "SHAMAN")
	local own = Conversation({ { t = 1, x = "me", o = 1 } })
	Equal(ns.MessageList.BuildElements(own, 200)[2].class, ns.myClass)
end)

Test("the new messages divider sits before the first unread message", function()
	local ns = Boot()
	local conv = Conversation({
		{ i = 1, t = 10, x = "read", s = "A B" },
		{ i = 2, t = 20, x = "mine", o = 1 },
		{ i = 3, t = 30, x = "new", s = "A B" },
		{ i = 4, t = 40, x = "newer", s = "A B" },
	})
	local elements = ns.MessageList.BuildElements(conv, 200, nil, 1)
	Equal(elements[4].kind, "unread")
	Equal(elements[5].head, true, "header restarts after the divider")
	Equal(elements[6].head, false)

	for _, element in ipairs(ns.MessageList.BuildElements(conv, 200)) do
		assert(element.kind ~= "unread", "no divider when nothing is unread")
	end
end)

Test("first characters respect UTF-8", function()
	local ns = Boot()
	Equal(ns.Util.FirstCharacter("Ärger"), "Ä")
	Equal(ns.Util.FirstCharacter("Dvalin"), "D")
	Equal(ns.Util.FirstCharacter(""), "")
end)

-- Boots with toasts captured instead of drawn.
local function BootForAlerts()
	local ns = Boot()
	local toasts = {}
	local function capture(key, conv, record) toasts[#toasts + 1] = { key = key, record = record } end
	ns.Toast.Show = capture
	ns.Glance.Show = capture
	return ns, toasts
end

Test("a whisper goes to the glance strip instead of a popup", function()
	local ns = Boot()
	local popups, glances = 0, 0
	ns.Toast.Show = function() popups = popups + 1 end
	ns.Glance.Show = function() glances = glances + 1 end
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	Equal(glances, 1)
	Equal(popups, 0)
end)

Test("the glance strip stays away while Hangout is open", function()
	local ns = Boot()
	local glances = 0
	ns.Glance.Show = function() glances = glances + 1 end
	ns.Window.IsVisible = function() return true end
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	Equal(glances, 0)
end)

Test("group alerts keep using popups", function()
	local ns = Boot()
	ns.Set("toastGroup", true)
	local popups, glances = 0, 0
	ns.Toast.Show = function() popups = popups + 1 end
	ns.Glance.Show = function() glances = glances + 1 end
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Other Person" })
	Equal(popups, 1)
	Equal(glances, 0)
end)

Test("the glance strip keeps the three newest whispers", function()
	local ns = Boot()
	for index = 1, 4 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "message " .. index, name = "Other Person" })
	end
	local lines = ns.Glance.Lines()
	Equal(#lines, 3)
	Equal(lines[1].text, "message 2")
	Equal(lines[3].text, "message 4")
	Equal(lines[3].name, "Other", "only the first name, to leave room for the text")
end)

Test("hiding the glance strip forgets its lines", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Other Person" })
	Equal(#ns.Glance.Lines(), 1)
	ns.Glance.Hide()
	Equal(#ns.Glance.Lines(), 0)
end)

Test("mentions match the first name and keywords as whole words", function()
	local ns = Boot()
	ns.Alerts.AddKeyword("  RAID ")
	Equal(ns.Alerts.IsMention("anyone seen Me?"), true)
	Equal(ns.Alerts.IsMention("some text"), false)
	Equal(ns.Alerts.IsMention("Anyone for raid tonight"), true)
	Equal(ns.Alerts.IsMention("raiders wanted"), false)
	Equal(ns.Alerts.IsMention("raidä"), false, "umlauts count as letters")
	ns.Alerts.RemoveKeyword("raid")
	Equal(ns.Alerts.IsMention("Anyone for raid tonight"), false)
	Equal(ns.Get("keywords"), nil)
end)

Test("linked items can't trigger a mention", function()
	local ns = Boot()
	ns.Alerts.AddKeyword("sword")
	Equal(ns.Alerts.IsMention("|cffa335ee|Hitem:1|h[Sword]|h|r"), false)
	Equal(ns.Alerts.IsMention("|cnIQ4:|Hitem:1|h[Sword]|h|r for sale"), false)
	Equal(ns.Alerts.IsMention("selling my sword"), true)
end)

Test("a whisper shows a popup and flashes, leaving the sound to the game", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	Equal(#toasts, 1)
	Equal(toasts[1].key, "W:A B")
	Equal(stubs.flashes, 1)
	Equal(#stubs.played, 0)
end)

Test("ordinary group chat stays quiet but still counts as unread", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Other Person" })
	Equal(#toasts, 0)
	Equal(#stubs.played, 0)
	Equal(ns.Store.TotalUnread(), 1)
end)

Test("a group mention plays a sound and shows a popup", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_GUILD", { text = "hey me", name = "Other Person" })
	Equal(#toasts, 1)
	Equal(stubs.played[1], SOUNDKIT.MAP_PING)
	Equal(stubs.flashes, 1)
end)

Test("a mention in a public channel alerts and counts as unread", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wts", name = "A B", base = "Trade" })
	Equal(#toasts, 0)
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "hi me", name = "A B", base = "Trade" })
	Equal(#toasts, 1)
	Equal(ns.Store.TotalUnread(), 1)
end)

Test("your own messages never alert or count as mentions", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_GUILD", { text = "this is me", name = "Me Self" })
	Equal(#toasts, 0)
	Equal(ns.Store.TotalUnread(), 0)
end)

Test("Do Not Disturb silences alerts but keeps badges", function()
	local ns, toasts = BootForAlerts()
	ns.Set("dnd", true)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	Equal(#toasts, 0)
	Equal(stubs.flashes, 0)
	Equal(ns.Store.TotalUnread(), 1)
end)

Test("muted chats only alert on a mention and leave the total alone", function()
	local ns, toasts = BootForAlerts()
	Chat(ns, "CHAT_MSG_GUILD", { text = "first", name = "A B" })
	local key = "G:Horde Heroes-Thunderstrike"
	ns.Store.SetField(key, "mute", true)
	Equal(ns.Store.TotalUnread(), 0)
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "A B" })
	Equal(#toasts, 0)
	Chat(ns, "CHAT_MSG_GUILD", { text = "hey me", name = "A B" })
	Equal(#toasts, 1)
end)

Test("the chat being viewed makes no alert", function()
	local ns, toasts = BootForAlerts()
	ns.activeKey = "W:A B"
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	Equal(#toasts, 0)
	Equal(stubs.flashes, 0)
end)

Test("popups are skipped in combat", function()
	local ns, toasts = BootForAlerts()
	stubs.inCombat = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	Equal(#toasts, 0)
	Equal(stubs.flashes, 1)
end)

Test("sounds are throttled during bursts", function()
	local ns = BootForAlerts()
	ns.Set("soundWhisper", "ping")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "one", name = "A B" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "two", name = "A B" })
	Equal(#stubs.played, 1)
	stubs.time = stubs.time + 2
	Chat(ns, "CHAT_MSG_WHISPER", { text = "three", name = "A B" })
	Equal(#stubs.played, 2)
end)

Test("restricted messages alert without a popup and recovery stays silent", function()
	local ns, toasts = BootForAlerts()
	ns.Set("soundWhisper", "ping")
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	Equal(#stubs.played, 1)
	Equal(stubs.flashes, 1)
	Equal(#toasts, 0)

	stubs.chatLines[10] = { text = "hello", name = "A B" }
	stubs.time = stubs.time + 10
	ns.Capture.Recover()
	Equal(#stubs.played, 1)
	Equal(#toasts, 0)
end)

Test("mention rows are flagged for highlighting", function()
	local ns = Boot()
	local conv = Conversation({
		{ t = 1, x = "hey me", s = "A B" },
		{ t = 2, x = "nothing", s = "A B" },
	})
	local elements = ns.MessageList.BuildElements(conv, 200)
	Equal(elements[2].mention, true)
	Equal(elements[3].mention, false)
end)

Test("shortcodes become emoji and unknown ones are left alone", function()
	local ns = Boot()
	local rendered = ns.Emoji.Render("hi :smile: and :notanemoji:")
	assert(rendered:find("|TInterface\\AddOns\\Hangout\\Media\\emoji.png:0:0:0:0:512:512:0:32:0:32|t", 1, true))
	assert(rendered:find(":notanemoji:", 1, true))
	Equal(ns.Emoji.Render("no colons here"), "no colons here")
end)

Test("emoji aliases and later atlas rows resolve", function()
	local ns = Boot()
	Equal(ns.Emoji.Render(":+1:"), ns.Emoji.Render(":thumbsup:"))
	local index = 17 -- first emoji of the second atlas row
	local left, right, top, bottom = ns.Emoji.TexCoords(index)
	Equal(left, 0)
	Equal(right, 32 / 512)
	Equal(top, 32 / 512)
	Equal(bottom, 64 / 512)
end)

Test("hyperlinks are never changed by emoji rendering", function()
	local ns = Boot()
	local link = "|cffa335ee|Hitem:19019:smile:|h[:smile:]|h|r"
	local rendered = ns.Emoji.Render(link .. " :smile:")
	assert(rendered:find(link, 1, true), "link stays intact")
	assert(rendered:find("|T", 1, true), "text after the link is still rendered")
end)

Test("every emoji name is unique and fits in the atlas", function()
	local ns = Boot()
	local seen = {}
	for _, name in ipairs(ns.EmojiData) do
		assert(not seen[name], name .. " is listed twice")
		seen[name] = true
	end
	assert(#ns.EmojiData <= 256, "more emoji than atlas cells")
end)

Test("themes export and import back to the same colors", function()
	local ns = Boot()
	ns.Theme.SetPreset("ember")
	ns.Theme.SetCustom("accent", 1, 0, 0)
	local exported = ns.Theme.Export()
	ns.Theme.SetPreset("midnight")
	Equal(ns.Theme.Import(exported), true)
	Equal(ns.Theme.ActiveName(), "ember")
	local r, g, b = ns.Theme.Color("accent")
	Equal(r, 1)
	Equal(g, 0)
	Equal(b, 0)
	Equal(ns.Theme.Export(), exported)
end)

Test("invalid theme strings are refused and change nothing", function()
	local ns = Boot()
	ns.Theme.SetPreset("ember")
	local before = ns.Theme.Export()
	Equal(ns.Theme.Import(""), false)
	Equal(ns.Theme.Import("something else"), false)
	Equal(ns.Theme.Import("Hangout1:nosuchpreset:bg=000000"), false)
	Equal(ns.Theme.Import("Hangout1:ember:evil=000000"), false)
	Equal(ns.Theme.Import("Hangout1:ember:bg=zzzzzz"), false)
	Equal(ns.Theme.Import("Hangout1:ember:bg=000000,accent=12"), false)
	Equal(ns.Theme.Export(), before)
end)

Test("choosing a preset clears custom colors", function()
	local ns = Boot()
	ns.Theme.SetCustom("accent", 1, 0, 0)
	ns.Theme.SetPreset("midnight")
	Equal(next(ns.db.theme.custom), nil)
	local r = ns.Theme.Color("accent")
	assert(r < 1)
end)

Test("window opacity applies to the background only", function()
	local ns = Boot()
	ns.Set("windowOpacity", 80)
	ns.Theme.Apply()
	local _, _, _, bgAlpha = ns.Theme.Color("bg")
	local _, _, _, textAlpha = ns.Theme.Color("text")
	Equal(bgAlpha, 0.8)
	Equal(textAlpha, 1)
end)

Test("a saved opacity below the minimum is raised to it", function()
	local ns = Boot()
	ns.Set("windowOpacity", 40)
	ns.Theme.Apply()
	Equal(ns.Get("windowOpacity"), ns.Theme.MIN_OPACITY)
	local _, _, _, panelAlpha = ns.Theme.Color("panel")
	Equal(panelAlpha, 1, "layers that cover content stay solid")
end)

-- WCAG contrast of a color against a plain surface color.
local function ContrastOf(r, g, b, surfaceR, surfaceG, surfaceB)
	local function linear(value)
		return value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(red, green, blue)
		return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
	end
	local a, b2 = luminance(r, g, b), luminance(surfaceR, surfaceG, surfaceB)
	return (math.max(a, b2) + 0.05) / (math.min(a, b2) + 0.05)
end

Test("class names are readable on every theme and surface", function()
	local ns = Boot()
	_G.RAID_CLASS_COLORS = {
		SHAMAN = { r = 0, g = 0.44, b = 0.87 },
		ROGUE = { r = 1, g = 0.96, b = 0.41 },
		PRIEST = { r = 1, g = 1, b = 1 },
	}
	for _, preset in ipairs(ns.Theme.PRESET_ORDER) do
		ns.Theme.SetPreset(preset)
		for class in pairs(RAID_CLASS_COLORS) do
			for _, surface in ipairs({ "bg", "sidebar" }) do
				local r, g, b = ns.Theme.ClassColor(class, surface)
				local sr, sg, sb = ns.Theme.Color(surface)
				assert(ContrastOf(r, g, b, sr, sg, sb) >= 4.5, preset .. " " .. class .. " on " .. surface)
			end
		end
	end
end)

Test("a class color that is already readable is left alone", function()
	local ns = Boot()
	_G.RAID_CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 } }
	ns.Theme.SetPreset("midnight")
	local r, g, b, a = ns.Theme.ClassColor("PRIEST")
	Equal(r, 1)
	Equal(g, 1)
	Equal(b, 1)
	Equal(a, 1)
end)

Test("every theme's accent is readable on its own surfaces", function()
	local ns = Boot()
	for _, preset in ipairs(ns.Theme.PRESET_ORDER) do
		ns.Theme.SetPreset(preset)
		local r, g, b = ns.Theme.Color("accent")
		for _, surface in ipairs({ "bg", "sidebar" }) do
			local sr, sg, sb = ns.Theme.Color(surface)
			assert(ContrastOf(r, g, b, sr, sg, sb) >= 4.5, preset .. " accent on " .. surface)
		end
	end
end)

Test("every emoji sits in exactly one picker tab", function()
	local ns = Boot()
	local seen = {}
	for _, group in ipairs(ns.Emoji.GROUPS) do
		assert(#group.names <= ns.EmojiPicker.CAPACITY, group.label .. " doesn't fit the grid")
		for _, name in ipairs(group.names) do
			assert(ns.Emoji.Has(name), name .. " isn't in the atlas")
			assert(not seen[name], name .. " is in two tabs")
			seen[name] = true
		end
	end
	for _, name in ipairs(ns.EmojiData) do
		assert(seen[name], name .. " is in no tab")
	end
end)

Test("the picker opens on the game-flavored emoji", function()
	local ns = Boot()
	Equal(ns.Emoji.GROUPS[1].label, "Adventure")
	Equal(ns.Emoji.GROUPS[1].names[1], "crossed_swords")
end)

Test("emoji search matches part of a name in any case", function()
	local ns = Boot()
	local matches = ns.Emoji.Search("SWORD")
	Equal(#matches, 1)
	Equal(matches[1], "crossed_swords")
	Equal(ns.Emoji.Search("crossed sw")[1], "crossed_swords", "a space stands for an underscore")
	Equal(#ns.Emoji.Search("nothing_like_this"), 0)
end)

Test("emoji search treats punctuation as plain text", function()
	local ns = Boot()
	Equal(#ns.Emoji.Search("%"), 0)
	Equal(#ns.Emoji.Search("["), 0)
end)

Test("the window edge stays dark whatever the accent color", function()
	local ns = Boot()
	ns.Theme.SetCustom("accent", 1, 0, 0)
	local r, g, b, a = ns.Theme.Color("edge")
	Equal(r, 0)
	Equal(g, 0)
	Equal(b, 0)
	assert(a > 0 and a < 1, "the edge stays subtle")
end)

Test("a crest's ring shows and hides with it", function()
	local ns = Boot()
	_G.CLASS_ICON_TCOORDS = { SHAMAN = { 0.25, 0.5, 0.25, 0.5 } }
	local ringShown
	local crest = {
		SetShown = function() end, SetTexture = function() end, SetTexCoord = function() end,
		ring = { SetShown = function(_, shown) ringShown = shown end },
	}
	ns.Widgets.SetClassCrest(crest, "SHAMAN")
	Equal(ringShown, true)
	ns.Widgets.SetClassCrest(crest, nil)
	Equal(ringShown, false)
end)

Test("the crest ring uses the quiet text color, not the accent", function()
	local ns = Boot()
	ns.Theme.SetCustom("accent", 0, 1, 0)
	ns.Theme.SetCustom("muted", 0.5, 0.25, 0.75)
	local r, g, b, a = ns.Theme.Color("crestRing")
	Equal(r, 0.5)
	Equal(g, 0.25)
	Equal(b, 0.75)
	assert(a > 0 and a < 1, "the ring stays subtle")
end)

Test("message rows record which side of a whisper they belong on", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Other Person" })
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "hello", name = "Other Person" })
	local conv = ns.Store.Get("W:Other Person")
	local elements = ns.MessageList.BuildElements(conv, 200)
	Equal(elements[2].outgoing, false)
	Equal(elements[3].outgoing, true)
end)

Test("text stays readable on the player's bubble in every theme", function()
	local ns = Boot()
	for _, preset in ipairs(ns.Theme.PRESET_ORDER) do
		ns.Theme.SetPreset(preset)
		for _, token in ipairs({ "bubbleMine", "bubbleMineHover", "bubbleTheirsHover" }) do
			local tintR, tintG, tintB, alpha = ns.Theme.Color(token)
			local baseR, baseG, baseB = ns.Theme.Color("panel")
			local r = baseR + (tintR - baseR) * alpha
			local g = baseG + (tintG - baseG) * alpha
			local b = baseB + (tintB - baseB) * alpha
			local textR, textG, textB = ns.Theme.Color("text")
			assert(ContrastOf(textR, textG, textB, r, g, b) >= 4.5, preset .. " text on " .. token)
		end
	end
end)

Test("a class crest shows only for a known class", function()
	local ns = Boot()
	_G.CLASS_ICON_TCOORDS = { SHAMAN = { 0.25, 0.5, 0.25, 0.5 } }
	local texture = {
		SetShown = function(self, shown) self.shown = shown end,
		SetTexture = function(self, path) self.path = path end,
		SetTexCoord = function(self, left) self.left = left end,
	}
	Equal(ns.Widgets.SetClassCrest(texture, "SHAMAN"), true)
	Equal(texture.shown, true)
	assert(texture.left > 0.25 and texture.left < 0.3, "trims the icon's bevel")
	assert(texture.path:find("UI%-CharacterCreate%-Classes"), "uses the square class icons")

	Equal(ns.Widgets.SetClassCrest(texture, nil), false)
	Equal(texture.shown, false)
	Equal(texture.ring, nil, "a bare texture needs no ring")
	Equal(ns.Widgets.SetClassCrest(texture, "NOT_A_CLASS"), false)
end)

Test("the selected row is accounted for when adjusting a name", function()
	local ns = Boot()
	_G.RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
	ns.Theme.SetPreset("midnight")
	local plainR = ns.Theme.ClassColor("SHAMAN", "sidebar")
	local selectedR = ns.Theme.ClassColor("SHAMAN", "sidebar", "selected")
	assert(selectedR > plainR, "a lighter row needs a lighter name")
end)

Test("starting a whisper creates a chat that sorts first", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "old", name = "Other Person" })
	stubs.serverTime = stubs.serverTime + 10
	local key = ns.Store.StartWhisper("  new friend ")
	Equal(key, "W:New Friend")
	Equal(ns.Store.Get(key).name, "New Friend")
	Equal(ns.Store.List()[1].key, key)
end)

Test("starting a whisper finds an existing chat however the name is typed", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Other Person" })
	Equal(ns.Store.StartWhisper("other-person"), "W:Other Person")
	Equal(ns.Store.StartWhisper("OTHER PERSON"), "W:Other Person")
	Equal(#ns.Store.List(), 1)
end)

Test("starting a whisper ignores blank input", function()
	local ns = Boot()
	Equal(ns.Store.StartWhisper("   "), nil)
	Equal(#ns.Store.List(), 0)
end)

Test("the reply key skips requests and muted chats", function()
	local ns = Boot()
	Equal(ns.Store.NewestUnreadKey(), nil)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "first", name = "Plain Chat" })
	stubs.serverTime = stubs.serverTime + 10
	Chat(ns, "CHAT_MSG_WHISPER", { text = "second", name = "Muted Chat" })
	ns.Store.SetField("W:Muted Chat", "mute", true)
	Equal(ns.Store.NewestUnreadKey(), "W:Plain Chat")
end)

Test("keywords can be replaced from comma-separated text", function()
	local ns = Boot()
	ns.Alerts.SetKeywords(" Raid, BOSS ,,")
	local keywords = ns.Get("keywords")
	Equal(#keywords, 2)
	Equal(keywords[1], "raid")
	Equal(keywords[2], "boss")
	Equal(ns.Alerts.IsMention("boss time"), true)
	ns.Alerts.SetKeywords("")
	Equal(ns.Get("keywords"), nil)
	Equal(ns.Alerts.IsMention("boss time"), false)
end)

Test("hiding whispers keeps Game Master whispers visible", function()
	local ns = Boot()
	Equal(stubs.chatFilters.CHAT_MSG_WHISPER, nil)
	ns.Set("hideWhispers", true)
	ns.Filter.Apply()
	local filter = stubs.chatFilters.CHAT_MSG_WHISPER
	Equal(filter, ns.Filter.HideWhisper)
	assert(stubs.chatFilters.CHAT_MSG_BN_WHISPER_INFORM)
	Equal(filter(nil, "CHAT_MSG_WHISPER", "hi", "A B", "", "", "", ""), true)
	Equal(filter(nil, "CHAT_MSG_WHISPER", "hi", "Game Master", "", "", "", "GM"), false)
	ns.Set("hideWhispers", false)
	ns.Filter.Apply()
	Equal(stubs.chatFilters.CHAT_MSG_WHISPER, nil)
end)

Test("hidden whispers play a sound because the game no longer does", function()
	local ns = BootForAlerts()
	ns.Set("hideWhispers", true)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	Equal(stubs.played[1], SOUNDKIT.TELL_MESSAGE)
end)

Test("saving a channel moves it to history and back", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wts", name = "A B", base = "Trade" })
	ns.Store.SetChannelSaved("C:trade", true)
	Equal(#ns.db.conv["C:trade"].m, 1)
	Equal(ns.session.conv["C:trade"], nil)
	Equal(ns.Store.IsPersistent("C:trade"), true)

	ns.Store.SetChannelSaved("C:trade", false)
	Equal(ns.db.conv["C:trade"], nil)
	Equal(#ns.session.conv["C:trade"].m, 1)
	Equal(ns.db.settings.keepChannels, nil)
end)

Test("a stranger's first whisper becomes a silent request", function()
	local ns, toasts = BootForAlerts()
	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "buy gold", name = "Spam Bot" })
	local conv = ns.db.conv["W:Spam Bot"]
	Equal(conv.req, true)
	Equal(#toasts, 0)
	Equal(stubs.flashes, 0)
	Equal(ns.Store.UnreadCount("W:Spam Bot", conv), 1)
	Equal(ns.Store.TotalUnread(), 0)
end)

Test("friends, your own whispers and known chats are not requests", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Party Member" })
	Equal(ns.db.conv["W:Party Member"].req, nil)

	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Me Self" })
	Equal(ns.db.conv["W:Me Self"].req, nil)

	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "hey", name = "Old Contact" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello back", name = "Old Contact" })
	Equal(ns.db.conv["W:Old Contact"].req, nil)
end)

Test("Game Masters are never treated as strangers", function()
	local ns = Boot()
	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "Game Master", flags = "GM" })
	Equal(ns.db.conv["W:Game Master"].req, nil)
end)

Test("replying accepts a request", function()
	local ns = Boot()
	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "hey", name = "New Person" })
	Equal(ns.db.conv["W:New Person"].req, nil)
end)

Test("requests can be turned off", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Set("requestsEnabled", false)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	Equal(ns.db.conv["W:New Person"].req, nil)
end)

Test("requests get their own sidebar section", function()
	local ns = Boot()
	local elements = ns.Sidebar.BuildElements({
		{ key = "W:Known X", conv = { name = "Known X" } },
		{ key = "W:Spam Bot", conv = { name = "Spam Bot", req = true } },
	})
	Equal(elements[1].label, "WHISPERS")
	Equal(elements[2].key, "W:Known X")
	Equal(elements[3].label, "REQUESTS")
	Equal(elements[4].key, "W:Spam Bot")
end)

Test("blocked players disappear from whispers and channels", function()
	local ns = Boot()
	ns.Filter.BlockPlayer("Spam Bot")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "buy gold", name = "Spam Bot" })
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "buy gold", name = "Spam Bot", base = "Trade" })
	Equal(ns.db.conv["W:Spam Bot"], nil)
	Equal(ns.session.conv["C:trade"], nil)
	Equal(ns.Filter.BlockedCount(), 2)
end)

Test("blocked words only apply to strangers", function()
	local ns = Boot()
	ns.Filter.SetList("blockWords", "gold, boost")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "got some gold", name = "Party Member" })
	Equal(#ns.db.conv["W:Party Member"].m, 1)

	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "Cheap GOLD here", name = "Spam Bot" })
	Equal(ns.db.conv["W:Spam Bot"], nil)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello there", name = "Polite Person" })
	Equal(#ns.db.conv["W:Polite Person"].m, 1)
end)

Test("rule words are plain text, never patterns", function()
	local ns = Boot()
	ns.Filter.SetList("channelHideWords", "100%, [wts")
	Equal(ns.Filter.BlocksChannel("A B", "100% sure", 1), true)
	Equal(ns.Filter.BlocksChannel("A B", "[WTS] sword", 2), true)
	Equal(ns.Filter.BlocksChannel("A B", "fine message", 3), false)
end)

Test("channel filters hide words and can require words", function()
	local ns = Boot()
	ns.Filter.SetList("channelHideWords", "wts")
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "WTS boots", name = "A B", base = "Trade" })
	Equal(ns.session.conv["C:trade"], nil)

	ns.Filter.SetList("channelOnlyWords", "lfg, tank")
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "hello all", name = "A B", base = "Trade" })
	Equal(ns.session.conv["C:trade"], nil)
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "LFG deadmines", name = "A B", base = "Trade" })
	Equal(#ns.session.conv["C:trade"].m, 1)
end)

Test("repeated channel spam is dropped inside the window", function()
	local ns = Boot()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "buy now", name = "A B", base = "Trade" })
	stubs.serverTime = 130
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "BUY NOW", name = "A B", base = "Trade" })
	stubs.serverTime = 131
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "buy now", name = "C D", base = "Trade" })
	stubs.serverTime = 300
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "buy now", name = "A B", base = "Trade" })
	Equal(#ns.session.conv["C:trade"].m, 3)
end)

Test("your own channel messages are never filtered", function()
	local ns = Boot()
	ns.Filter.SetList("channelHideWords", "wts")
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "wts boots", name = "Me Self", base = "Trade" })
	Equal(#ns.session.conv["C:trade"].m, 1)
end)

Test("secret messages skip all spam rules", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Filter.SetList("blockWords", "gold")
	Chat(ns, "CHAT_MSG_WHISPER", { text = stubs.Secret(), name = stubs.Secret() })
	Equal(#ns.Store.GetLive(ns.Capture.LOCKED_KEY), 1)
	Equal(ns.Filter.BlockedCount(), 0)
end)

Test("recovered whispers are screened like normal ones", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Filter.SetList("blockWords", "gold")
	LockedChat(ns, "CHAT_MSG_WHISPER", 10)
	LockedChat(ns, "CHAT_MSG_WHISPER", 11)
	stubs.chatLines[10] = { text = "buy gold", name = "Spam Bot" }
	stubs.chatLines[11] = { text = "hello", name = "New Person" }
	ns.Capture.Recover()
	Equal(ns.db.conv["W:Spam Bot"], nil)
	Equal(ns.db.conv["W:New Person"].req, true)
	Equal(ns.Store.GetLive(ns.Capture.LOCKED_KEY), nil)
end)

local function SearchList(ns)
	return ns.Store.List()
end

Test("search finds visible text across chats, newest first", function()
	local ns = Boot()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_WHISPER", { text = "the Boss is down", name = "A B" })
	stubs.serverTime = 200
	Chat(ns, "CHAT_MSG_WHISPER", { text = "next boss soon", name = "A B" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "nothing here", name = "A B" })
	local state = ns.Search.NewState("BOSS", SearchList(ns))
	Equal(ns.Search.Advance(state, function() return false end), true)
	Equal(#state.results, 2)
	Equal(state.results[1].snippet, "next boss soon")
	Equal(state.results[1].key, "W:A B")
end)

Test("search ignores hidden link data", function()
	local ns = Boot()
	Equal(ns.Search.VisibleText("|cffa335ee|Hitem:19019:boss:|h[Thunderfury]|h|r!"), "[Thunderfury]!")
	Equal(ns.Search.VisibleText("|cnIQ4:|Hitem:19019:boss:|h[Thunderfury]|h|r!"), "[Thunderfury]!")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "|cffa335ee|Hitem:19019:boss:|h[Thunderfury]|h|r", name = "A B" })
	local state = ns.Search.NewState("boss", SearchList(ns))
	ns.Search.Advance(state, function() return false end)
	Equal(#state.results, 0)
end)

Test("search resumes where it paused and stops at the result limit", function()
	local ns = Boot()
	for i = 1, 3 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "match " .. i, name = "A B" })
	end
	local state = ns.Search.NewState("match", SearchList(ns))
	Equal(ns.Search.Advance(state, function() return true end), false)
	Equal(#state.results, 1)
	Equal(ns.Search.Advance(state, function() return false end), true)
	Equal(#state.results, 3)

	ns.Set("perChatCap", 5000)
	for i = 1, 250 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "many " .. i, name = "C D" })
	end
	state = ns.Search.NewState("many", SearchList(ns))
	Equal(ns.Search.Advance(state, function() return false end), true)
	Equal(#state.results, 200)
end)

Test("the sidebar shows matching chats and message results while searching", function()
	local ns = Boot()
	local elements = ns.Sidebar.BuildElements({
		{ key = "W:Thrall H", conv = { name = "Thrall H", nick = "Warchief" } },
		{ key = "W:Jaina P", conv = { name = "Jaina P" } },
	}, "warch", { { key = "W:Jaina P", id = 4, label = "Jaina P", snippet = "warchief says hi" } })
	Equal(elements[1].label, "CHATS")
	Equal(elements[2].key, "W:Thrall H")
	Equal(elements[3].label, "MESSAGES")
	Equal(elements[4].kind, "result")
	Equal(elements[4].id, 4)
	Equal(#elements, 4)
end)

Test("nicknames replace names everywhere and empty text clears them", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Thrall Hellscream" })
	ns.Store.SetField("W:Thrall Hellscream", "nick", "Warchief")
	local conv = ns.db.conv["W:Thrall Hellscream"]
	Equal(ns.Store.LabelFor("W:Thrall Hellscream", conv), "Warchief")
	Equal(ns.MessageList.BuildElements(conv, 200)[2].sender, "Warchief")
	Equal(ns.Store.SenderLabel("Thrall Hellscream"), "Warchief")
	Equal(ns.Store.SenderLabel("Someone Else"), "Someone Else")

	ns.Store.SetField("W:Thrall Hellscream", "nick", "")
	Equal(conv.nick, nil)
	Equal(ns.Store.LabelFor("W:Thrall Hellscream", conv), "Thrall Hellscream")
end)

Test("notes keep an otherwise empty chat from being pruned", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Store.SetField("W:A B", "note", "met in Ironforge")
	ns.DB.Prune(stubs.serverTime + 400 * 86400)
	Equal(#ns.db.conv["W:A B"].m, 0)
	Equal(ns.db.conv["W:A B"].note, "met in Ironforge")
end)

Test("deleting a chat removes it completely", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Store.Delete("W:A B")
	Equal(ns.db.conv["W:A B"], nil)
	Equal(#ns.Store.List(), 0)
end)

Test("message elements carry ids so search can find them", function()
	local ns = Boot()
	local conv = Conversation({ { i = 7, t = 1, x = "hi", s = "A B" } })
	Equal(ns.MessageList.BuildElements(conv, 200)[2].id, 7)
end)

-- Delivers an addon message the way the game does.
local function AddonMessage(ns, sender, text, event, channel)
	for _, frame in ipairs(stubs.frames) do
		if frame.events.CHAT_MSG_ADDON then
			frame.OnEvent(frame, event or "CHAT_MSG_ADDON", "Hangout", text, channel or "WHISPER", sender)
		end
	end
end

-- A chat with someone who has already answered a hello.
local function BootWithPeer()
	local ns = Boot()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi there", name = "Pal Friend" })
	AddonMessage(ns, "Pal Friend", "1;H;0")
	return ns, "W:Pal Friend", ns.db.conv["W:Pal Friend"]
end

local function LastSent()
	return stubs.addonSent[#stubs.addonSent]
end

Test("protocol parsing accepts only this version and sane sizes", function()
	local ns = Boot()
	local parts = ns.Protocol.Parse("1;A;abc;heart")
	Equal(parts[2], "A")
	Equal(parts[4], "heart")
	Equal(ns.Protocol.Parse("2;A;abc"), nil)
	Equal(ns.Protocol.Parse("1"), nil)
	Equal(ns.Protocol.Parse("garbage"), nil)
	Equal(ns.Protocol.Parse("1;a;b;c;d;e;f"), nil)
end)

Test("message hashes are stable and ignore link data", function()
	local ns = Boot()
	Equal(ns.Protocol.Hash("hello"), ns.Protocol.Hash("hello"))
	assert(ns.Protocol.Hash("hello") ~= ns.Protocol.Hash("hello!"))
	Equal(#ns.Protocol.Hash(string.rep("long text ", 40)), 8)
	Equal(ns.Protocol.Hash("|cffa335ee|Hitem:1:2|h[Sword]|h|r"), ns.Protocol.Hash("|cffa335ee|Hitem:9:9|h[Sword]|h|r"))
end)

Test("opening a chat says hello once, to reachable people only", function()
	local ns = Boot()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Pal Friend" })
	ns.Protocol.OnOpened("W:Pal Friend")
	ns.Protocol.OnOpened("W:Pal Friend")
	Equal(#stubs.addonSent, 1)
	Equal(stubs.addonSent[1].text, "1;H;1")
	Equal(stubs.addonSent[1].target, "Pal Friend")

	stubs.serverTime = 100 + 301
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "x", name = "Old Friend" })
	stubs.serverTime = 100 + 900
	ns.Protocol.OnOpened("W:Old Friend")
	Equal(#stubs.addonSent, 1, "no hello to someone long inactive")
end)

Test("group chats and requests never get a hello", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_GUILD", { text = "hi", name = "A B" })
	ns.Protocol.OnOpened("G:Horde Heroes-Thunderstrike")
	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	ns.Protocol.OnOpened("W:New Person")
	Equal(#stubs.addonSent, 0)
end)

Test("a hello is answered once and marks the sender as a Hangout user", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Pal Friend" })
	Equal(ns.Protocol.IsPeer("W:Pal Friend"), false)
	AddonMessage(ns, "Pal Friend", "1;H;1")
	Equal(ns.Protocol.IsPeer("W:Pal Friend"), true)
	Equal(LastSent().text, "1;H;0")
	AddonMessage(ns, "Pal Friend", "1;H;0")
	Equal(#stubs.addonSent, 1, "an answer is not answered")
end)

Test("messages from strangers and unknown senders are ignored", function()
	local ns = Boot()
	AddonMessage(ns, "No Chat", "1;H;1")
	Equal(#stubs.addonSent, 0)
	Equal(ns.Protocol.IsPeer("W:No Chat"), false)

	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	AddonMessage(ns, "New Person", "1;H;1")
	Equal(#stubs.addonSent, 0)
	Equal(ns.Protocol.IsPeer("W:New Person"), false)
end)

Test("secret or foreign addon traffic is ignored", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Pal Friend" })
	AddonMessage(ns, stubs.Secret(), "1;H;1")
	AddonMessage(ns, "Pal Friend", stubs.Secret())
	AddonMessage(ns, "Pal Friend", "1;H;1", "CHAT_MSG_ADDON", "GUILD")
	Equal(#stubs.addonSent, 0)
end)

Test("typing shows until it expires or a message arrives", function()
	local ns, key = BootWithPeer()
	AddonMessage(ns, "Pal Friend", "1;T")
	Equal(ns.Protocol.IsTyping(key), true)
	stubs.time = stubs.time + 7
	Equal(ns.Protocol.IsTyping(key), false)

	AddonMessage(ns, "Pal Friend", "1;T")
	Equal(ns.Protocol.IsTyping(key), true)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "done typing", name = "Pal Friend" })
	Equal(ns.Protocol.IsTyping(key), false)
end)

Test("typing notices are throttled, need a peer and can be disabled", function()
	local ns, key = BootWithPeer()
	ns.Protocol.NotifyTyping("W:Someone Else")
	Equal(#stubs.addonSent, 0)

	ns.Protocol.NotifyTyping(key)
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, 1)
	stubs.time = stubs.time + 5
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, 2)

	stubs.time = stubs.time + 5
	ns.Set("sendTyping", false)
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, 2)
end)

Test("reading a chat sends a receipt for the newest incoming message", function()
	local ns, key = BootWithPeer()
	ns.Store.MarkRead(key)
	Equal(LastSent().text, "1;R;" .. ns.Protocol.Hash("hi there"))

	local before = #stubs.addonSent
	ns.Set("sendReadReceipts", false)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "another", name = "Pal Friend" })
	ns.Store.MarkRead(key)
	Equal(#stubs.addonSent, before)
end)

Test("a receipt marks your message as seen in the chat", function()
	local ns, key, conv = BootWithPeer()
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "first", name = "Pal Friend" })
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "second", name = "Pal Friend" })
	AddonMessage(ns, "Pal Friend", "1;R;" .. ns.Protocol.Hash("first"))
	Equal(conv.seenId, 2)

	local elements = ns.MessageList.BuildElements(conv, 200)
	local seenIndex
	for index, element in ipairs(elements) do
		if element.kind == "seen" then seenIndex = index end
	end
	Equal(elements[seenIndex - 1].id, 2)

	AddonMessage(ns, "Pal Friend", "1;R;" .. ns.Protocol.Hash("second"))
	Equal(conv.seenId, 3)
	AddonMessage(ns, "Pal Friend", "1;R;" .. ns.Protocol.Hash("first"))
	Equal(conv.seenId, 3, "an older receipt never moves it back")
end)

Test("reactions toggle locally and are sent to the other side", function()
	local ns, key, conv = BootWithPeer()
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(conv.m[1].r.heart, 1)
	Equal(LastSent().text, "1;A;" .. ns.Protocol.Hash("hi there") .. ";heart")
	Equal(ns.Protocol.HasMyReaction(key, 1, "heart"), true)

	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(conv.m[1].r, nil)
	Equal(LastSent().text, "1;X;" .. ns.Protocol.Hash("hi there") .. ";heart")
end)

Test("reactions from the other side combine with yours", function()
	local ns, key, conv = BootWithPeer()
	local ref = ns.Protocol.Hash("hi there")
	AddonMessage(ns, "Pal Friend", "1;A;" .. ref .. ";heart")
	Equal(conv.m[1].r.heart, 2)
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(conv.m[1].r.heart, 3)
	Equal(ns.Protocol.ReactionList(conv.m[1].r)[1].count, 2, "counts both people")

	AddonMessage(ns, "Pal Friend", "1;X;" .. ref .. ";heart")
	Equal(conv.m[1].r.heart, 1)
	AddonMessage(ns, "Pal Friend", "1;X;" .. ref .. ";heart")
	Equal(conv.m[1].r.heart, 1, "removing twice changes nothing")
end)

Test("unknown emoji and unknown messages are ignored", function()
	local ns, key, conv = BootWithPeer()
	local ref = ns.Protocol.Hash("hi there")
	AddonMessage(ns, "Pal Friend", "1;A;" .. ref .. ";notanemoji")
	AddonMessage(ns, "Pal Friend", "1;A;00000000;heart")
	AddonMessage(ns, "Pal Friend", "1;A")
	Equal(conv.m[1].r, nil)
end)

Test("nothing is sent while chat is restricted", function()
	local ns, key, conv = BootWithPeer()
	stubs.lockdown = true
	ns.Protocol.NotifyTyping(key)
	ns.Store.MarkRead(key)
	Equal(ns.Protocol.CanReact(key), false)
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(#stubs.addonSent, 0)
	Equal(conv.m[1].r, nil, "a reaction that wasn't sent isn't shown")
end)

Test("leftover diagnostic data is removed from saved history", function()
	local saved = Database({})
	saved.schema = 2
	saved.debug = { { kind = "state" } }
	Boot(saved)
	Equal(HangoutDB.debug, nil)
	Equal(HangoutDB.schema, SCHEMA)
end)

Test("a throttled send backs off for a few seconds", function()
	local ns, key = BootWithPeer()
	stubs.addonResult = 3
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, 1)

	stubs.addonResult = 0
	stubs.time = stubs.time + 4.5
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, 1, "still backing off")
	stubs.time = stubs.time + 1
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(#stubs.addonSent, 2)
end)

Test("the global send budget caps bursts", function()
	local ns, key = BootWithPeer()
	for _ = 1, 30 do
		stubs.time = stubs.time + 0.01
		ns.Protocol.ToggleReaction(key, 1, "heart")
	end
	assert(#stubs.addonSent <= 10, "sent " .. #stubs.addonSent)
	stubs.time = stubs.time + 11
	local before = #stubs.addonSent
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(#stubs.addonSent, before + 1)
end)

Test("Battle.net friends in this game use game data, others are skipped", function()
	local ns = Boot()
	stubs.bnetFriends = {
		{ battleTag = "Pal#5678", bnetAccountID = 55,
			gameAccountInfo = { isOnline = true, gameAccountID = 900, clientProgram = "WoW", wowProjectID = 1 } },
		{ battleTag = "Retail#1111", bnetAccountID = 56,
			gameAccountInfo = { isOnline = true, gameAccountID = 901, clientProgram = "WoW", wowProjectID = 2 } },
	}
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then frame.OnEvent() end
	end
	stubs.bnetTags[55] = "Pal#5678"
	stubs.bnetTags[56] = "Retail#1111"
	Chat(ns, "CHAT_MSG_BN_WHISPER", { text = "hey", name = "x", bn = 55 })
	Chat(ns, "CHAT_MSG_BN_WHISPER", { text = "hey", name = "x", bn = 56 })

	ns.Protocol.OnOpened("B:Pal#5678")
	ns.Protocol.OnOpened("B:Retail#1111")
	Equal(#stubs.gameDataSent, 1)
	Equal(stubs.gameDataSent[1].id, 900)

	AddonMessage(ns, 900, "1;H;0", "BN_CHAT_MSG_ADDON", "WHISPER")
	Equal(ns.Protocol.IsPeer("B:Pal#5678"), true)
	AddonMessage(ns, 901, "1;H;0", "BN_CHAT_MSG_ADDON", "WHISPER")
	Equal(ns.Protocol.IsPeer("B:Retail#1111"), false)
end)

Test("an old guild chat can't post to this character's guild", function()
	local ns = Boot()
	for _, key in ipairs({ "G:Old Guild-Thunderstrike", "O:Old Guild-Thunderstrike" }) do
		local ok, why = ns.Send.Text(key, "hi")
		Equal(ok, false)
		Equal(why, "unavailable")
	end
	Equal(#stubs.sent, 0)
	Equal(ns.Send.Text("O:Horde Heroes-Thunderstrike", "hi"), true)
	Equal(stubs.sent[1].chatType, "OFFICER")
end)

Test("a channel number that now belongs to another channel is refused", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_CHANNEL", { text = "x", name = "A B", base = "Trade", channelIndex = 5 })
	stubs.channels[5] = "LookingForGroup"
	local ok, why = ns.Send.Text("C:trade", "selling")
	Equal(ok, false)
	Equal(why, "unavailable")
	stubs.channels[5] = nil
	Equal(ns.Send.Text("C:trade", "selling"), false, "the channel was left")
	Equal(#stubs.sent, 0)
	stubs.channels[5] = "Trade - City"
	Equal(ns.Send.Text("C:trade", "selling"), true, "a zone suffix is the same channel")
end)

-- Opens the real window and composer around stand-ins for the scrolling lists.
local function BootWithWindow()
	local ns = Boot()
	_G.tinsert = table.insert
	_G.UISpecialFrames = {}
	_G.hooksecurefunc = function() end
	local calls = { cleared = 0 }
	ns.Sidebar = {
		Create = function() end, SetCollapsed = function() end, Refresh = function() end,
		ClearSearchFocus = function() end,
	}
	ns.MessageList = { Create = function() end, Refresh = function() end }
	ns.On("SELECTION_CHANGED", function(key)
		calls.selected = key
		if not key then calls.cleared = calls.cleared + 1 end
	end)
	ns.SettingsUI = { Create = function() end, Hide = function() end }
	ns.EmojiPicker = { Hide = function() end }
	return ns, calls
end

local function ComposerEnter(ns)
	local box
	for _, frame in ipairs(stubs.frames) do
		if rawget(frame, "OnEnterPressed") then box = frame end
	end
	box.OnEnterPressed({ GetText = function() return "still typing" end, SetText = function() end })
end

Test("deleting the last chat leaves nothing to send to", function()
	local ns, calls = BootWithWindow()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Window.Open("W:A B")
	Equal(calls.selected, "W:A B")

	ns.Store.Delete("W:A B")
	Equal(calls.selected, nil)
	Equal(calls.cleared, 1)
	ComposerEnter(ns)
	Equal(#stubs.sent, 0, "Enter must not whisper the deleted chat")
end)

Test("a search survives its chat being trimmed while paused", function()
	local ns = Boot()
	for i = 1, 5 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "match " .. i, name = "A B" })
	end
	local state = ns.Search.NewState("match", SearchList(ns))
	Equal(ns.Search.Advance(state, function() return true end), false)

	local messages = ns.db.conv["W:A B"].m
	for i = #messages, 2, -1 do messages[i] = nil end
	Equal(ns.Search.Advance(state, function() return false end), true)
end)

Test("a silent group message doesn't use up the mention sound", function()
	local ns = BootForAlerts()
	Chat(ns, "CHAT_MSG_GUILD", { text = "gz", name = "Other Person" })
	Chat(ns, "CHAT_MSG_GUILD", { text = "hey me", name = "Other Person" })
	Equal(stubs.played[1], SOUNDKIT.MAP_PING)
end)

Test("blocked words also apply to public channels", function()
	local ns = Boot()
	ns.Filter.SetList("blockWords", "gold")
	Equal(ns.Filter.BlocksChannel("A B", "WTS GOLD cheap", 1), true)
	Equal(ns.Filter.BlocksChannel("A B", "wts sword", 2), false)
end)

Test("with Requests off, a stranger stays screened until you reply", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Set("requestsEnabled", false)
	ns.Filter.SetList("blockWords", "gold")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "buy gold", name = "New Person" })
	local conv = ns.db.conv["W:New Person"]
	Equal(#conv.m, 1, "the second whisper is blocked")

	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "who is this", name = "New Person" })
	Chat(ns, "CHAT_MSG_WHISPER", { text = "the gold run", name = "New Person" })
	Equal(#conv.m, 3, "replying trusts them")
end)

Test("an accepted request is no longer screened", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Filter.SetList("blockWords", "gold")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	ns.Store.AcceptRequest("W:New Person")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "the gold run", name = "New Person" })
	Equal(#ns.db.conv["W:New Person"].m, 2)
end)

Test("a Game Master keeps their exemption through recovery", function()
	local ns = Boot()
	stubs.allStrangers = true
	ns.Filter.SetList("blockWords", "gold")
	ns.Filter.SetList("channelHideWords", "gold")
	LockedChat(ns, "CHAT_MSG_WHISPER", 10, { flags = "GM" })
	LockedChat(ns, "CHAT_MSG_CHANNEL", 11, { flags = "GM", base = "Trade" })
	stubs.chatLines[10] = { text = "about your gold", name = "Game Master" }
	stubs.chatLines[11] = { text = "gold sellers beware", name = "Game Master" }
	ns.Capture.Recover()

	local whisper = ns.db.conv["W:Game Master"]
	Equal(whisper.m[1].f, ns.Capture.FLAG_GM)
	Equal(whisper.req, nil)
	Equal(ns.session.conv["C:trade"].m[1].f, ns.Capture.FLAG_GM)
end)

Test("lines that can't be recovered keep their unread count", function()
	local ns = Boot()
	LockedChat(ns, "CHAT_MSG_BN_WHISPER", 10)
	LockedChat(ns, "CHAT_MSG_WHISPER", 11)
	Equal(ns.session.liveUnread[ns.Capture.LOCKED_KEY], 2)
	stubs.chatLines[11] = { text = "hello", name = "Thrall Hellscream" }
	ns.Capture.Recover()
	Equal(ns.session.liveUnread[ns.Capture.LOCKED_KEY], 1)
end)

Test("nothing is sent to a peer who has gone offline, but a hello is answered", function()
	local ns, key = BootWithPeer()
	stubs.friends = { { name = "Pal Friend", connected = false } }
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then frame.OnEvent(frame) end
	end
	Equal(ns.Identity.Presence(key), false)

	local before = #stubs.addonSent
	ns.Protocol.NotifyTyping(key)
	ns.Protocol.ToggleReaction(key, 1, "heart")
	Equal(#stubs.addonSent, before)

	AddonMessage(ns, "Pal Friend", "1;H;1")
	Equal(#stubs.addonSent, before + 1)
	Equal(LastSent().text, "1;H;0")
end)

Test("addon traffic keeps a peer with unknown presence reachable", function()
	local ns, key = BootWithPeer()
	stubs.serverTime = 100 + 900
	AddonMessage(ns, "Pal Friend", "1;T")
	local before = #stubs.addonSent
	ns.Protocol.NotifyTyping(key)
	Equal(#stubs.addonSent, before + 1)
end)

Test("restricted rows never catch the mouse", function()
	local ns = Boot()
	local view = { SetElementResetter = function() end, SetElementExtentCalculator = function() end }
	local chooseRow
	view.SetElementFactory = function(_, chooser) chooseRow = chooser end
	_G.CreateScrollBoxListLinearView = function() return view end
	ns.Widgets.ScrollList = function() return stubs.Tolerant(), stubs.Tolerant() end
	ns.MessageList.Create(stubs.Tolerant())

	local initializer
	chooseRow(function(_, init) initializer = init end, { kind = "locked" })
	local mouse
	local row = {
		EnableMouse = function(_, enabled) mouse = enabled end,
		CreateFontString = function() return stubs.Tolerant() end,
	}
	initializer(row, { time = "12:00", sender = "A", text = "B" })
	Equal(mouse, false)
end)

-- The window's frame, made to remember whether it's shown.
local function TrackMainFrame(shown)
	local main
	for _, frame in ipairs(stubs.frames) do
		if rawget(frame, "OnHide") then main = frame end
	end
	local state = { shown = shown }
	rawset(main, "IsShown", function() return state.shown end)
	rawset(main, "IsVisible", function() return state.shown end)
	rawset(main, "Show", function()
		state.shown = true
		main.OnShow(main)
	end)
	rawset(main, "Hide", function()
		state.shown = false
		main.OnHide(main)
	end)
	return main, state
end

local function FireCombat(event)
	for _, frame in ipairs(stubs.frames) do
		if frame.events.PLAYER_REGEN_DISABLED then frame.OnEvent(frame, event) end
	end
end

Test("closing the window during combat keeps it closed afterwards", function()
	local ns = BootWithWindow()
	ns.Set("combatMode", "hide")
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Window.Open("W:A B")
	local _, state = TrackMainFrame(true)

	FireCombat("PLAYER_REGEN_DISABLED")
	Equal(state.shown, false)
	ns.Window.Toggle()
	ns.Window.Toggle()
	FireCombat("PLAYER_REGEN_ENABLED")
	Equal(state.shown, false)

	ns.Window.Toggle()
	FireCombat("PLAYER_REGEN_DISABLED")
	FireCombat("PLAYER_REGEN_ENABLED")
	Equal(state.shown, true, "a window hidden only by combat still comes back")
end)

Test("a chat hidden along with the whole UI isn't being read", function()
	local ns = BootWithWindow()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Window.Open("W:A B")
	Equal(ns.activeKey, "W:A B")

	local main = TrackMainFrame(true)
	local visible = false
	rawset(main, "IsVisible", function() return visible end)
	main.OnHide(main)
	Equal(ns.activeKey, nil)
	Chat(ns, "CHAT_MSG_WHISPER", { text = "still there?", name = "A B" })
	Equal(ns.db.conv["W:A B"].unread, 1)

	visible = true
	main.OnShow(main)
	Equal(ns.activeKey, "W:A B")
	Equal(ns.db.conv["W:A B"].unread, nil)
end)

Test("a window opened normally still shows what's new", function()
	local ns = BootWithWindow()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.Window.Open("W:A B")
	TrackMainFrame(true)
	ns.Window.Toggle()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "new", name = "A B" })

	local unreadWhenShown
	ns.On("SELECTION_CHANGED", function(_, _, count) unreadWhenShown = count end)
	ns.Window.Toggle()
	Equal(unreadWhenShown, 1, "the New messages line needs the count")
end)

Test("one alert covers all the mentions found by a recovery", function()
	local ns, toasts = BootForAlerts()
	LockedChat(ns, "CHAT_MSG_CHANNEL", 10, { base = "Trade" })
	LockedChat(ns, "CHAT_MSG_CHANNEL", 11, { base = "Trade" })
	stubs.chatLines[10] = { text = "hey me", name = "A B" }
	stubs.chatLines[11] = { text = "me again", name = "A B" }
	ns.Capture.Recover()
	Equal(#toasts, 1)
	Equal(stubs.played[1], SOUNDKIT.MAP_PING)

	LockedChat(ns, "CHAT_MSG_CHANNEL", 12, { base = "Trade" })
	stubs.chatLines[12] = { text = "me once more", name = "A B" }
	ns.Capture.Recover()
	Equal(#toasts, 2, "the next restriction alerts again")
end)

Test("Requests are never opened automatically", function()
	local ns, calls = BootWithWindow()
	stubs.serverTime = 100
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Old Friend" })
	stubs.allStrangers = true
	stubs.serverTime = 200
	Chat(ns, "CHAT_MSG_WHISPER", { text = "buy this", name = "New Person" })

	ns.Window.Toggle()
	local _, state = TrackMainFrame(false)
	ns.Window.Toggle()
	Equal(state.shown, true)
	Equal(calls.selected, "W:Old Friend")
	Equal(ns.db.conv["W:New Person"].unread, 1)
end)

Test("an open empty window doesn't select an incoming Request", function()
	local ns, calls = BootWithWindow()
	stubs.allStrangers = true
	ns.Window.Toggle()
	TrackMainFrame(false)
	ns.Window.Toggle()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "buy this", name = "New Person" })
	Equal(calls.selected, nil)
	Equal(ns.db.conv["W:New Person"].unread, 1)
end)

Test("accepting or answering a Request starts the handshake", function()
	local ns = Boot()
	stubs.allStrangers = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "New Person" })
	Equal(#stubs.addonSent, 0)
	ns.Store.AcceptRequest("W:New Person")
	Equal(ns.db.conv["W:New Person"].req, nil)
	Equal(#stubs.addonSent, 1)
	Equal(LastSent().text, "1;H;1")

	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "Other Person" })
	Equal(#stubs.addonSent, 1)
	Chat(ns, "CHAT_MSG_WHISPER_INFORM", { text = "hello", name = "Other Person" })
	Equal(#stubs.addonSent, 2)
	Equal(LastSent().target, "Other Person")
end)

Test("reactions land on the right copy of repeated text", function()
	local ns, key, conv = BootWithPeer()
	for _, text in ipairs({ "lol", "other", "lol" }) do
		Chat(ns, "CHAT_MSG_WHISPER", { text = text, name = "Pal Friend" })
	end
	local older, newer = conv.m[2], conv.m[4]
	local ref = ns.Protocol.Hash("lol")

	ns.Protocol.ToggleReaction(key, older.i, "heart")
	Equal(LastSent().text, "1;A;" .. ref .. ";heart;1")
	ns.Protocol.ToggleReaction(key, newer.i, "joy")
	Equal(LastSent().text, "1;A;" .. ref .. ";joy", "the newest copy needs no extra field")

	AddonMessage(ns, "Pal Friend", "1;A;" .. ref .. ";tada;1")
	Equal(older.r.tada ~= nil, true)
	Equal(newer.r.tada, nil)
	AddonMessage(ns, "Pal Friend", "1;A;" .. ref .. ";sob")
	Equal(newer.r.sob ~= nil, true, "older clients send no occurrence")
end)

Test("blocked players match however the name was typed", function()
	local ns = Boot()
	ns.Filter.SetList("blockedPlayers", "First-Last, Second Name")
	Equal(ns.Filter.BlocksWhisper("First Last", "hi", false), true)
	Equal(ns.Filter.BlocksWhisper("Second Name", "hi", false), true)
	Equal(ns.Filter.BlocksWhisper("Third Name", "hi", false), false)
end)

Test("a non-emoji between colons doesn't swallow the next shortcode", function()
	local ns = Boot()
	Equal(ns.Emoji.Render("at 10:30:heart:"), "at 10:30" .. ns.Emoji.Tag("heart"))
	Equal(ns.Emoji.Render(":nope::heart: a:b"), ":nope:" .. ns.Emoji.Tag("heart") .. " a:b")
	Equal(ns.Emoji.Render("a:b:c:d"), "a:b:c:d")
end)

Test("long messages never split an escaped pipe", function()
	local ns = Boot()
	local parts = ns.Send.SplitMessage(string.rep("a", 254) .. "||b")
	Equal(parts[1], string.rep("a", 254))
	Equal(parts[2], "||b")
end)

Test("an empty roster name can't abort the presence scan", function()
	local ns = Boot()
	stubs.friends = { { name = "", connected = true }, { name = "Fri End", connected = true } }
	stubs.guildRoster = { { name = "", online = true }, { name = "Guild Mate", online = true } }
	for _, frame in ipairs(stubs.frames) do
		if frame.events.FRIENDLIST_UPDATE then frame.OnEvent(frame) end
	end
	Equal(ns.Identity.Presence("W:Fri End"), true)
	Equal(ns.Identity.Presence("W:Guild Mate"), true)
end)

-- Replaces the game's scrolling list with one that counts rebuilds.
local function CountingScrollList(ns)
	_G.CreateScrollBoxListLinearView = function() return stubs.Tolerant() end
	_G.CreateDataProvider = function(elements) return elements end
	local counter = { rebuilds = 0 }
	local box = stubs.Tolerant()
	rawset(box, "SetDataProvider", function() counter.rebuilds = counter.rebuilds + 1 end)
	ns.Widgets.ScrollList = function() return box, stubs.Tolerant() end
	counter.visible = true
	ns.Window.IsVisible = function() return counter.visible end
	return counter
end

Test("a closed window doesn't rebuild its message list", function()
	local ns = Boot()
	local counter = CountingScrollList(ns)
	ns.MessageList.Create(stubs.Tolerant())
	ns.selectedKey = "W:A B"

	counter.visible = false
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	Equal(counter.rebuilds, 0)

	counter.visible = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "again", name = "A B" })
	Equal(counter.rebuilds, 1)
end)

Test("a closed window doesn't rebuild its sidebar", function()
	local ns = Boot()
	local counter = CountingScrollList(ns)
	local field = stubs.Tolerant()
	rawset(field, "GetText", function() return "" end)
	ns.Widgets.Field = function() return stubs.Tolerant(), field end
	ns.Sidebar.Create(stubs.Tolerant())

	counter.visible = false
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	Equal(counter.rebuilds, 0)

	counter.visible = true
	Chat(ns, "CHAT_MSG_WHISPER", { text = "again", name = "A B" })
	assert(counter.rebuilds > 0, "an open sidebar still updates")
end)

Test("a recovery rebuilds the message list once", function()
	local ns = Boot()
	local counter = CountingScrollList(ns)
	ns.MessageList.Create(stubs.Tolerant())
	ns.selectedKey = "W:A B"
	for lineID = 10, 14 do
		LockedChat(ns, "CHAT_MSG_WHISPER", lineID)
		stubs.chatLines[lineID] = { text = "line " .. lineID, name = "A B" }
	end
	ns.Capture.Recover()
	Equal(#ns.db.conv["W:A B"].m, 5)
	Equal(counter.rebuilds, 1)
end)

Test("a long search only reports when there's something new", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "match", name = "A B" })
	for i = 1, 4 do
		Chat(ns, "CHAT_MSG_WHISPER", { text = "other " .. i, name = "A B" })
	end
	local clock = 0
	_G.debugprofilestop = function()
		clock = clock + 5
		return clock
	end

	local reports, final = 0, nil
	ns.Search.Run("match", function(results)
		reports = reports + 1
		final = #results
	end)
	Equal(reports, 3, "the first step, the match, and the finish")
	Equal(final, 1)
end)

Test("an empty search still reports that it finished", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hello", name = "A B" })
	local reports = 0
	ns.Search.Run("nothing", function() reports = reports + 1 end)
	Equal(reports, 1)
end)

Test("messages sent from an alt are labelled with the alt", function()
	local ns = Boot()
	ns.db.chars[2] = "Alt Char"
	local conv = Conversation({
		{ i = 1, t = 1, x = "from this character", o = 1, c = ns.charIndex },
		{ i = 2, t = 2, x = "from the alt", o = 1, c = 2 },
		{ i = 3, t = 3, x = "from before characters were tracked", o = 1 },
	})
	local elements = ns.MessageList.BuildElements(conv, 200)
	Equal(elements[2].sender, "You")
	Equal(elements[2].class, "SHAMAN")
	Equal(elements[3].sender, "Alt Char")
	Equal(elements[3].class, nil, "an alt doesn't get this character's color")
	Equal(elements[3].head, true, "a different character starts a new group")
	Equal(elements[4].sender, "You")
end)

Test("pin and mute are set and cleared through SetField", function()
	local ns = Boot()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	local conv = ns.db.conv["W:A B"]
	ns.Store.SetField("W:A B", "pin", true)
	Equal(conv.pin, true)
	ns.Store.SetField("W:A B", "pin", false or nil)
	Equal(conv.pin, nil)
end)

Test("selecting a chat shows its draft and clears when nothing is selected", function()
	local ns = BootWithWindow()
	Chat(ns, "CHAT_MSG_WHISPER", { text = "hi", name = "A B" })
	ns.db.conv["W:A B"].draft = "half a thought"
	local box
	ns.Window.Open("W:A B")
	for _, frame in ipairs(stubs.frames) do
		if rawget(frame, "OnEnterPressed") then box = frame end
	end
	Equal(ns.selectedKey, "W:A B")

	local shownText
	rawset(box, "SetText", function(_, text) shownText = text end)
	ns.Window.Select("W:A B")
	Equal(shownText, "half a thought")

	ns.Store.Delete("W:A B")
	Equal(ns.selectedKey, nil)
	Equal(shownText, "")
end)

Test("unread badges cap their number", function()
	local ns = Boot()
	Equal(ns.Util.BadgeText(5), "5")
	Equal(ns.Util.BadgeText(99), "99")
	Equal(ns.Util.BadgeText(100), "99+")
end)

local failures = 0
for _, test in ipairs(tests) do
	local ok, err = xpcall(test.fn, debug.traceback)
	if ok then
		io.stdout:write("ok   ", test.name, "\n")
	else
		failures = failures + 1
		io.stdout:write("FAIL ", test.name, "\n", tostring(err), "\n")
	end
end
io.stdout:write(#tests - failures, "/", #tests, " passed\n")
os.exit(failures == 0 and 0 or 1)
