local _, ns = ...

local PlayerMenu = {}
ns.PlayerMenu = PlayerMenu

local function ConfirmBlockPlayer(name)
	ns.Prompt.Confirm("Block " .. ns.Util.DisplayName(name) .. "? Their messages won't appear in Hangout.",
		"Block", function()
			ns.Filter.BlockPlayer(name)
			if ns.Store.Get("W:" .. name) then ns.Store.Delete("W:" .. name) end
		end)
end

local function RunWho(name)
	local filter = 'n-"' .. name .. '"'
	if C_FriendList.SendWho then
		C_FriendList.SendWho(filter)
	elseif SendWho then
		SendWho(filter)
	end
end

local function IsWhisperWith(name)
	return ns.selectedKey ~= nil and ns.selectedKey:lower() == ("W:" .. name):lower()
end

-- What can be done with another player, from their name or crest in a message.
function PlayerMenu.Items(name)
	local items = {}
	local isMe = name == ns.me
	if not isMe then
		if not IsWhisperWith(name) then
			items[#items + 1] = { label = "Whisper", action = function() ns.Window.Select(ns.Store.StartWhisper(name)) end }
		end
		items[#items + 1] = { label = "Invite to group", action = function() C_PartyInfo.InviteUnit(name) end }
		items[#items + 1] = { label = "Add friend", action = function() C_FriendList.AddFriend(name) end }
		items[#items + 1] = { label = "Who", action = function() RunWho(name) end }
	end
	items[#items + 1] = { label = "Copy name", action = function() ns.CopyBox.Show("Copy name", name) end }
	if not isMe then
		items[#items + 1] = { divider = true }
		items[#items + 1] = { label = "Block", action = function() ConfirmBlockPlayer(name) end }
	end
	return items
end

function PlayerMenu.Show(owner, name, class)
	if not name then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(ns.Util.DisplayName(name))
		local className = class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
		if className then root:CreateTitle(className) end
		for _, item in ipairs(PlayerMenu.Items(name)) do
			if item.divider then
				root:CreateDivider()
			else
				root:CreateButton(item.label, item.action)
			end
		end
	end)
end
