local addonName, ns = ...

ns.addonName = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

local listeners = {}

function ns.On(message, callback)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[#list + 1] = callback
end

function ns.Fire(message, ...)
	local list = listeners[message]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

-- Never pass chat payloads here: they may be secret values.
function ns.Print(text)
	print("|cfff5c242Hangout|r: " .. text)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, loadedName)
	if event == "ADDON_LOADED" then
		if loadedName == addonName then
			ns.DB.Init()
			ns.Theme.Apply()
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		ns.Identity.Init()
		ns.DB.RegisterCharacter(ns.me)
		ns.DB.Prune(GetServerTime())
		ns.Lockdown.Init()
		ns.Capture.Start()
		ns.Protocol.Init()
		ns.Launcher.Init()
		ns.Later.Init()
		ns.Watch.Init()
		ns.Filter.Apply()
		ns.SettingsUI.Init()
	end
end)
