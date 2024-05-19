function PAM.Start(vote_type, vote_length_override, winner_callback_override)
	if PAM.state ~= PAM.STATE_DISABLED then return end

	PAM.vote_type = vote_type or PAM.extension_handler.RunReturningEvent("GetDefaultVoteType") or "map"
	PAM.winner_callback = winner_callback_override or PAM.type_callbacks[PAM.vote_type] or PAM.ChangeMap

	local vote_length = vote_length_override or PAM.extension_handler.RunReturningEvent("GetVoteLength", PAM.vote_type) or PAM.vote_length:GetActiveValue()

	PAM.options = {}
	PAM.votes = {}

	PAM.option_count = 0
	PAM.special_option_count = 0

	PAM.extension_handler.RunEvent("RegisterSpecialOptions")
	PAM.extension_handler.RunEvent("RegisterOptions")

	if PAM.option_count <= PAM.special_option_count then
		ErrorNoHalt("[PAM] Failed to start. No " .. PAM.vote_type .. "s found using current settings. \n")
		return
	end

	-- send start info to all clients
	net.Start("PAM_Start")
	-- transmit amount of maps
	net.WriteString(PAM.vote_type)
	net.WriteUInt(vote_length, 32)
	net.WriteUInt(PAM.special_option_count, 32)
	net.WriteUInt(PAM.option_count, 32)
	-- transmit map information
	for i = 1, PAM.option_count do
		net.WriteString(PAM.options[i].name)
		net.WriteUInt(PAM.GetPickCount(PAM.options[i].name), 32)
	end
	net.Broadcast()

	-- update state
	PAM.state = PAM.STATE_STARTED

	--timer for ending it after the vote time is over
	timer.Create("PAM_Vote_Timer", vote_length, 1, function()
		PAM.state = PAM.STATE_FINISHED

		local vote_results = {}

		local function Multiplier(number1, number2)
			return number1 * number2
		end

		for steam_id, option_id in pairs(PAM.votes) do
			if option_id and IsValid(player.GetBySteamID(steam_id)) then
				vote_results[option_id] = (vote_results[option_id] or 0) + (PAM.extension_handler.RunAvalanchingEvent("GetVotePower", Multiplier, steam_id) or 1)
			end
		end

		local winning_option

		-- select winning map
		winning_option = PAM.options[PAM.extension_handler.RunReturningEvent("GetWinningKey", vote_results)] or PAM.options[PAM.special_option_count + math.random(#PAM.options - PAM.special_option_count)]

		PAM.MakeOptionWin(winning_option)
	end)

	PAM.extension_handler.RunEvent("OnVoteStarted")

	return true
end

function PAM.RegisterOption(option_name, option_win_callback)
	PAM.option_count = PAM.option_count + 1

	local option = {
		name = option_name,
		id = PAM.option_count
	}

	if option_win_callback then
		PAM.special_option_count = PAM.special_option_count + 1
		option.is_special = true
		option.win_callback = option_win_callback
	end

	PAM.options[PAM.option_count] = option
end

function PAM.RegisterTypeHandler(vote_type, winner_callback)
	PAM.type_callbacks[vote_type] = winner_callback
end

function PAM.MakeOptionWin(option)
	PAM.winning_option = option

	-- notify clients
	net.Start("PAM_Announce_Winner")
	net.WriteUInt(option.id, 32)
	net.Broadcast()

	PAM.SetPickCount(option.name, PAM.GetPickCount(option.name) + 1)

	-- make the winning option take effect after 4 seconds
	timer.Simple(4, function()
		if option.win_callback then
			option.win_callback()
		else
			PAM.winner_callback(option)
		end
	end)

	PAM.extension_handler.RunEvent("OnOptionWon", option)
end

function PAM.ChangeGamemode(option)
	gamemode_name = option.name

	RunConsoleCommand("gamemode", gamemode_name)

	net.Start("PAM_Gamemode_Changed")
	net.WriteString(gamemode_name)
	net.Broadcast()

	PAM.extension_handler.RunEvent("OnGamemodeChanged", gamemode_name)
end

function PAM.EndRound()
	PAM.extension_handler.RunEvent("OnRoundEnded")
end

function PAM.ChangeMap(option)
	local map_name = option.name
	PAM.extension_handler.RunEvent("PreMapChanged", map_name)

	RunConsoleCommand("changelevel", map_name)
end

function PAM.Cancel()
	if PAM.state == PAM.STATE_DISABLED then return end

	PAM.state = PAM.STATE_DISABLED
	timer.Remove("PAM_Vote_Timer")

	net.Start("PAM_Cancel")
	net.Broadcast()

	PAM.extension_handler.RunEvent("OnVoteCanceled")
end

function PAM.AddVoter(ply, option_id)
	PAM.votes[ply:SteamID()] = option_id

	net.Start("PAM_Vote")
	net.WriteEntity(ply)
	net.WriteUInt(option_id, 32)
	net.Broadcast()

	PAM.extension_handler.RunEvent("OnVoterAdded", ply, option_id)
end

function PAM.RemoveVoter(ply)
	PAM.Votes[ply:SteamID()] = nil

	net.Start("PAM_UnVote")
	net.WriteEntity(ply)
	net.Broadcast()

	PAM.extension_handler.RunEvent("OnVoterRemoved", ply, option_id)
end

-- pick counter utility functions
function PAM.GetPickCount(option_name)
	local data = sql.Query("SELECT pickcount FROM pam_pickcounts WHERE id IS " .. sql.SQLStr(option_name))
	if data then
		return tonumber(data[1]["pickcount"])
	else
		return 0;
	end
end

function PAM.SetPickCount(option_name, pick_count)
	sql.Query("INSERT OR REPLACE INTO pam_pickcounts VALUES( " .. sql.SQLStr(option_name) .. ", " .. pick_count .. ")")
end
