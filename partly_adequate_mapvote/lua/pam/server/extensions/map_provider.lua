local name = "map_provider"
PAM_EXTENSION.name = name
PAM_EXTENSION.enabled = true

local setting_namespace = PAM.setting_namespace:AddChild(name)

local populate_from_info_setting = setting_namespace:AddSetting("populate_from_info", pacoman.TYPE_BOOLEAN, true, "Should the map list be populated from the gamemode 'maps' section in the gamemode txt file.")
local prefixes_setting = setting_namespace:AddSetting("prefixes", pacoman.TYPE_STRING, "", "Maps where at least one of the prefixes fits, will be available for voting.")
local blacklist_setting = setting_namespace:AddSetting("blacklist", pacoman.TYPE_STRING, "", "Maps that are listed here, won't be available, even when a prefix fits.")
local whitelist_setting = setting_namespace:AddSetting("whitelist", pacoman.TYPE_STRING, "", "Maps that are listed here, will be available for voting, even when no prefix fits.")
local limit_setting = setting_namespace:AddSetting("limit", pacoman.TYPE_INTEGER, 20, "Determines how many maps this extension will provide.")
local cooldown_setting = setting_namespace:AddSetting("cooldown", pacoman.TYPE_INTEGER, 3, "Determines how many maps need to be played for a map to be available again.")

-- cooldown stuff
if not sql.TableExists("pam_map_cooldowns") then
	sql.Query("CREATE TABLE pam_map_cooldowns(id TEXT NOT NULL PRIMARY KEY, heat INTEGER NOT NULL)")
end

local function GetMapCooldown(mapname)
	local data = sql.Query("SELECT heat FROM pam_map_cooldowns WHERE id IS " .. sql.SQLStr(mapname))
	if data then
		return tonumber(data[1]["heat"])
	else
		return 0
	end
end

local function SetMapCooldown(mapname, cooldown)
	if cooldown <= 0 then
		sql.Query("DELETE FROM pam_map_cooldowns WHERE id IS " .. sql.SQLStr(mapname))
	else
		sql.Query("INSERT OR REPLACE INTO pam_map_cooldowns VALUES( " .. sql.SQLStr(mapname) .. ", " .. cooldown .. ")")
	end
end

-- Support per gamemode
PAM_EXTENSION.gamemode_maps_pattern = {}
function PAM_EXTENSION:UpdateGamemodeMaps(gamemode)
	-- If the data has previously been loaded, don't load it again
	if self.gamemode_maps_pattern[gamemode] then return end

	local info = file.Read("gamemodes/"..gamemode.."/"..gamemode..".txt", "GAME")

	-- Empty var, so even if it couldn't be loaded it's set
	self.gamemode_maps_pattern[gamemode] = {}
	if (info) then
		local info = util.KeyValuesToTable(info)
		if (info.maps) then
			self.gamemode_maps_pattern[gamemode] = string.Split(info.maps, "|")
		elseif (info.fretta_maps) then
			self.gamemode_maps_pattern[gamemode] = info.fretta_maps
		end
	end
end

function PAM_EXTENSION:OnGamemodeChanged(gamemode)
	-- Load maps for new gamemode
	self:UpdateGamemodeMaps(gamemode)
end

function PAM_EXTENSION:OnInitialize()
	self:UpdateGamemodeMaps(engine.ActiveGamemode())
end

local function mapMatchesPattern(map, pattern)
	for _, v in pairs(pattern) do
		if string.match(map, v) then return true end
	end
	return false
end

function PAM_EXTENSION:RegisterOptions()
	if PAM.vote_type ~= "map" then return end

	local all_maps = file.Find("maps/*.bsp", "GAME")
	local starting_option_count = PAM.option_count

	local prefixes = string.Split(prefixes_setting:GetActiveValue(), ",")
	local blacklist = blacklist_setting:GetActiveValue()
	local whitelist = whitelist_setting:GetActiveValue()
	local limit = limit_setting:GetActiveValue()

	-- In case the prefixes setting is an empty string, it will still populate it to have 1 item
	-- So if it's got an empty one, we remove it
	if #prefixes == 1 and prefixes[1] == "" then
		prefixes[1] = nil
	end
	
	-- Using the convar gamemode to get the active gamemode as the gamemode extension will change the gamemode convar
	local current_gamemode = gamemode_name or GetConVar("gamemode"):GetString() or engine.ActiveGamemode()
	
	-- Somehow gamemode maps are not loaded, let's try loading them
	if populate_from_info_setting:GetActiveValue() and not self.gamemode_maps_pattern[current_gamemode] then
		self:UpdateGamemodeMaps(current_gamemode)
	end

	for _, map in RandomPairs(all_maps) do
		map = map:sub(1, -5)

		-- don't add too many maps
		if limit ~= 0 && limit <= PAM.option_count - starting_option_count then
			break
		end

		-- don't add maps which were played recently
		if cooldown_setting:GetActiveValue() > 0 and GetMapCooldown(map) > 0 then
			continue
		end

		-- don't add blacklisted maps
		if string.find(blacklist, map) then
			continue
		end

		-- add whitelisted maps
		if string.find(whitelist, map) then
			PAM.RegisterOption(map)
			continue
		end

		if populate_from_info_setting:GetActiveValue() and
				self.gamemode_maps_pattern[current_gamemode] and #self.gamemode_maps_pattern[current_gamemode] > 0 and
				mapMatchesPattern(map, self.gamemode_maps_pattern[current_gamemode]) then
			PAM.RegisterOption(map)
			continue
		end

		-- add all maps when no prefix is selected
		if not (populate_from_info_setting:GetActiveValue() and self.gamemode_maps_pattern[current_gamemode] and #self.gamemode_maps_pattern[current_gamemode] > 0)
				and #prefixes == 0 then
			PAM.RegisterOption(map)
			continue;
		end

		-- add maps where at least one prefix fits
		for i = 1, #prefixes do
			if string.find(map, prefixes[i]) then
				PAM.RegisterOption(map)
				break
			end
		end
	end
end

function PAM_EXTENSION:OnOptionWon(option)
	if PAM.vote_type ~= "map" then return end
	if option.is_special then return end

	-- update the maps which are currently on cooldown
	local data = sql.Query("SELECT * FROM pam_map_cooldowns")
	if data then
		for _, heat_info in ipairs(data) do
			local mapname = heat_info["id"]
			SetMapCooldown(mapname, GetMapCooldown(mapname) - 1)
		end
	end

	-- set/reset the cooldown of the winning map
	SetMapCooldown(option.name, cooldown_setting:GetActiveValue())
end
