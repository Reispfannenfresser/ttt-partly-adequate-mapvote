PAM.extension_handler = {}
PAM.extensions = {}
local extension_indices = {}
PAM_EXTENSION = {}

local function RegisterExtension()
	local extension = PAM_EXTENSION

	-- cache name
	local extension_name = extension.name

	-- calculate id and set it
	local id = extension_indices[extension_name] or #PAM.extensions + 1
	extension.id = id

	-- Setting creation
	local enabled_setting = PAM.setting_namespace:AddChild(extension.name):AddSetting("enabled", pacoman.TYPE_BOOLEAN, extension.enabled, "enables/disables the '" .. extension_name .. "' extension")

	extension.enabled = enabled_setting:GetActiveValue()

	enabled_setting:AddCallback("extension handler", function(value)
		extension.enabled = (extension.CanEnable and extension:CanEnable() != false and value) or (!extension.CanEnable and value)

		if value then
			if extension.OnEnable then
				extension:OnEnable()
			end
		elseif extension.OnDisable then
			extension:OnDisable()
		end
	end)

	-- add extension to table of extensions
	PAM.extensions[id] = extension
	extension_indices[extension_name] = id

	if extension.Initialize then
		extension:Initialize()
	end

	if extension.CanEnable then
		-- Only disable if we return false, if nothing is returned we will assume it doesn't want to be turned off
		if extension:CanEnable() == false then
			extension.enabled = false
		end
	end

	if extension.enabled and extension.OnEnable then
		extension:OnEnable()
	end

	print("[PAM] Registered extension \"" .. extension_name .. "\" (" .. (extension.enabled and "enabled" or "disabled") .. ")")
end

function PAM.extension_handler.RunEvent(event_name, ...)
	hook.Run("PAM_" .. event_name, ...)

	for i = 1, #PAM.extensions do
		local extension = PAM.extensions[i]

		if extension.enabled and extension[event_name] then
			extension[event_name](extension, ...)
		end
	end
end

function PAM.extension_handler.RunReturningEvent(event_name, ...)
	local override = hook.Run("PAM_" .. event_name, ...)
	if override then return override end

	for i = 1, #PAM.extensions do
		local extension = PAM.extensions[i]

		if extension.enabled and extension[event_name] then
			local result = extension[event_name](extension, ...)

			if result then
				return result
			end
		end
	end
end

function PAM.extension_handler.RunAvalanchingEvent(event_name, combine, ...)
	local combined_result = hook.Run("PAM_" .. event_name, ...)

	for i = 1, #PAM.extensions do
		local extension = PAM.extensions[i]

		if extension.enabled and extension[event_name] then
			local result = extension[event_name](extension, ...)
			if result then
				combined_result = combined_result and combine(combined_result, result) or result
			end
		end
	end

	return combined_result
end

function PAM.extension_handler.GetExtension(name)
	for i = 1, #PAM.extensions do
		local extension = PAM.extensions[i]
		if extension.name == name then
			return extension
		end
	end
end

hook.Add("Initialize", "PAM_Initialize_Extensions", function()
	PAM.extension_handler.RunEvent("OnInitialize")
end)

if SERVER then
	local sv_extensions, _ = file.Find("pam/server/extensions/*.lua", "LUA")
	local cl_extensions, _ = file.Find("pam/client/extensions/*.lua", "LUA")
	for i = 1, #sv_extensions do
		PAM_EXTENSION = {}
		include("pam/server/extensions/" .. sv_extensions[i])
		if PAM_EXTENSION.name then
			RegisterExtension()
		end
	end

	for i = 1, #cl_extensions do
		AddCSLuaFile("pam/client/extensions/" .. cl_extensions[i])
	end
else
	local cl_extensions, _ = file.Find("pam/client/extensions/*.lua", "LUA")
	for i = 1, #cl_extensions do
		PAM_EXTENSION = {}
		include("pam/client/extensions/" .. cl_extensions[i])
		if PAM_EXTENSION.name then
			RegisterExtension()
		end
	end
end
