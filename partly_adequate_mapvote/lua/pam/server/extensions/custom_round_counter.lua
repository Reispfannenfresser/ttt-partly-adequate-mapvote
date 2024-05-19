local name = "custom_round_counter"

PAM_EXTENSION.name = name
PAM_EXTENSION.enabled = false

local setting_namespace = PAM.setting_namespace:AddChild(name)
PAM_EXTENSION.round_limit = setting_namespace:AddSetting("round_limit", pacoman.TYPE_INTEGER, 6, "Determines how many rounds need to be played before a vote starts.")

local custom_round_counter = 0;

function PAM_EXTENSION:OnRoundEnded()
	PAM.extension_handler.RunEvent("SetRoundCounter", custom_round_counter + 1)

	if custom_round_counter >= self.round_limit:GetActiveValue() then
		PAM.Start()
	end
end

function PAM_EXTENSION:GetRoundCounter()
	return custom_round_counter
end

function PAM_EXTENSION:SetRoundCounter(value)
	if !isnumber(value) then
		ErrorNoHaltWithStack("Expected a number, but was " .. type(value) .. "\n")
		return
	end

	custom_round_counter = value
end
