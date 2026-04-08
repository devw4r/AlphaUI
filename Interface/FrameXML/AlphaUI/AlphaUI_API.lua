Main.API = {
	channelName = "_addonmain",
	channelPassword = "tP4hSCpd8vWaun",
	joinRetrySeconds = 5,
	requestRetrySeconds = 1,
	fallbackDelaySeconds = 3,
	maxSettingsPayloadLength = 72,
	requestSerial = 0,
	handshake = {
		timeoutSeconds = 5,
		sentAt = nil,
		pending = nil,
		completed = nil,
	},
	targetDistance = {
		requestRetrySeconds = 1,
	},
	unitAuras = {
		requestRetrySeconds = 1,
		states = {},
	},
	petActionBar = {
		requestRetrySeconds = 1,
		maxRetries = 5,
	},
}

local function Main_APICreateDefaultVersionMap()
	return {
		auras = 0,
		distance = 0,
		config = 0,
		guild = 0,
		pet = 0,
	}
end

local function Main_APIParseVersionMap(message)
	local versions
	local key
	local value
	local count

	if not message or not string.find(message, "^api,") then
		return nil
	end

	versions = Main_APICreateDefaultVersionMap()
	count = 0
	for key, value in string.gfind(message, "([A-Za-z_]+)=([^,]+)") do
		if versions[key] ~= nil then
			value = tonumber(value)
			if value then
				versions[key] = value
				count = count + 1
			end
		end
	end

	if count <= 0 then
		return nil
	end

	return versions
end

if Main.RegisterTransportChannel then
	Main.RegisterTransportChannel(Main.API.channelName)
end

function Main.API:CreateRequestToken()
	self.requestSerial = self.requestSerial + 1
	return tostring(self.requestSerial)
end

function Main.API:GetChannelNumber()
	local channelNum
	local now

	channelNum = GetChannelName(self.channelName)
	if channelNum and channelNum > 0 then
		self.joinLastAttempt = nil
		return channelNum
	end

	now = GetTime and GetTime() or 0
	if not self.joinLastAttempt or (now - self.joinLastAttempt) >= self.joinRetrySeconds then
		JoinChannelByName(self.channelName, self.channelPassword)
		self.joinLastAttempt = now
	end

	return nil
end

function Main.API:SendCommand(command, arg1, arg2)
	local channelNum
	local message

	channelNum = self:GetChannelNumber()
	if not channelNum or channelNum <= 0 then
		return nil
	end

	message = command
	if arg1 and arg1 ~= "" then
		message = message .. " " .. arg1
	end
	if arg2 and arg2 ~= "" then
		message = message .. " " .. arg2
	end

	SendChatMessage(message, "CHANNEL", nil, channelNum)
	return 1
end

function Main.API:BeginStartup()
	if self.startedAt then
		return
	end

	self.startedAt = GetTime and GetTime() or 0

	-- Join the channel now; the handshake will be sent from OnUpdate once the channel is ready.
	JoinChannelByName(self.channelName, self.channelPassword)
	self.joinLastAttempt = GetTime and GetTime() or 0
end

function Main.API:SendHandshake()
	local hs = self.handshake

	if hs.completed or hs.pending or self.configUnsupported then
		return nil
	end

	if self:SendCommand("getaddonapi") then
		hs.pending = 1
		hs.sentAt = GetTime and GetTime() or 0
		return 1
	end

	return nil
end

function Main.API:HandleHandshakeFailed()
	self.configUnsupported = 1
	self.handshake.pending = nil
	self.handshake.completed = nil

	if not Main.Initialized then
		Main_Start()
	end
end

function Main.API:GetServerApiVersion(apiName)
	if not self.serverApiVersions or not apiName then
		return 0
	end

	return tonumber(self.serverApiVersions[apiName]) or 0
end

function Main.API:IsServerApiSupported(apiName)
	return self:GetServerApiVersion(apiName) > 0 and 1 or nil
end

function Main.API:HandleAuraUnsupported()
	self.auraUnsupported = 1
	if not self.warnedAuraUnsupported then
		self.warnedAuraUnsupported = 1
		Main_Print("Server target aura API is unavailable.")
	end
end

function Main.API:HandleDistanceUnsupported()
	self.distanceUnsupported = 1
	if not self.warnedDistanceUnsupported then
		self.warnedDistanceUnsupported = 1
		Main_Print("Server target distance API is unavailable.")
	end
end

function Main.API:HandleConfigUnsupported()
	self.configUnsupported = 1
	if not self.warnedConfigUnsupported then
		self.warnedConfigUnsupported = 1
		Main_Print("Server addon settings API is unavailable. Using local defaults for this session.")
	end
	if not Main.Initialized then
		Main_Start()
	end
end

function Main.API:HandleGuildUnsupported()
	self.guildUnsupported = 1
	if not self.warnedGuildUnsupported then
		self.warnedGuildUnsupported = 1
		Main_Print("Server guild roster API is unavailable.")
	end
end

function Main.API:HandlePetUnsupported()
	self.petUnsupported = 1
end

function Main.API:HandleApiVersionMessage(message)
	local versions

	versions = Main_APIParseVersionMap(message)
	if not versions then
		self:HandleHandshakeFailed()
		return
	end

	self.handshake.pending = nil
	self.handshake.completed = 1
	self.serverApiVersions = versions

	self:RequestConfig(1)
end

function Main.API:RequestConfig(force)
	local now
	local token

	if self.configUnsupported or self.remoteLoaded then
		return nil
	end
	if self.handshake and self.handshake.completed and not self:IsServerApiSupported("config") then
		self:HandleConfigUnsupported()
		return nil
	end

	now = GetTime and GetTime() or 0
	if self.requestPending and not force then
		return nil
	end
	if not force and self.lastRequestAt and (now - self.lastRequestAt) < self.requestRetrySeconds then
		return nil
	end

	token = self:CreateRequestToken()
	if self:SendCommand("get_cfg", token) then
		self.requestToken = token
		self.requestPending = 1
		self.lastRequestAt = now
		return 1
	end

	return nil
end

function Main.API:SaveConfig()
	local flags
	local settingsPayload
	local requestToken
	local payload

	if self.configUnsupported or not self.remoteLoaded then
		return nil
	end
	if self.handshake and self.handshake.completed and not self:IsServerApiSupported("config") then
		self:HandleConfigUnsupported()
		return nil
	end

	flags, settingsPayload = Main.BuildRemoteConfigState()
	if settingsPayload and string.len(settingsPayload) > self.maxSettingsPayloadLength then
		if not self.warnedPayloadTooLong then
			self.warnedPayloadTooLong = 1
			Main_Print("Addon settings payload is too large to persist through chat transport.")
		end
		return nil
	end

	requestToken = self:CreateRequestToken()
	payload = tostring(floor(flags))
	if settingsPayload and settingsPayload ~= "" then
		payload = payload .. "|" .. settingsPayload
	else
		payload = payload .. "|-"
	end

	if self:SendCommand("set_cfg", requestToken, payload) then
		self.saveToken = requestToken
		self.savePending = 1
		return 1
	end

	return nil
end

function Main.API:HandleConfigMessage(message)
	local flagsText
	local requestToken
	local settingsPayload
	local flags

	_, _, flagsText, requestToken, settingsPayload = string.find(message, "^cfg,(%d+),([^,]+),?(.*)$")
	if not flagsText or not requestToken then
		return
	end

	flags = tonumber(flagsText) or 0
	settingsPayload = settingsPayload or ""

	if self.requestPending and requestToken == self.requestToken then
		self.requestPending = nil
		self.remoteLoaded = 1
		Main.ApplyRemoteConfig(flags, settingsPayload)
		if not Main.Initialized then
			Main_Start()
		end
		return
	end

	if self.savePending and requestToken == self.saveToken then
		self.savePending = nil
		return
	end
end

function Main.API:ResetTargetDistance()
	self.targetDistance.valueYards = nil
	self.targetDistance.unavailable = nil
	self.targetDistance.requestPending = nil
	self.targetDistance.requestToken = nil
	self.targetDistance.lastRequestAt = nil
end

function Main.API:RequestTargetDistance(force)
	local state
	local now
	local token

	if self.distanceUnsupported then
		return nil
	end
	if not UnitExists or not UnitExists("target") then
		return nil
	end
	if self.handshake and self.handshake.completed and not self:IsServerApiSupported("distance") then
		self:HandleDistanceUnsupported()
		return nil
	end

	state = self.targetDistance
	now = GetTime and GetTime() or 0

	if state.requestPending and not force then
		return nil
	end
	if not force and state.lastRequestAt and (now - state.lastRequestAt) < state.requestRetrySeconds then
		return nil
	end
	token = self:CreateRequestToken()
	if self:SendCommand("get_target_dist", "target", token) then
		state.requestPending = 1
		state.requestToken = token
		state.lastRequestAt = now
		return 1
	end

	return nil
end

function Main.API:GetTargetDistanceYards()
	return self.targetDistance.valueYards
end

function Main.API:IsTargetDistanceUnavailable()
	return self.targetDistance.unavailable
end

function Main.API:GetUnitAuraState(unitId)
	local safeUnitId

	safeUnitId = string.lower(tostring(unitId or "target"))
	if not self.unitAuras.states[safeUnitId] then
		self.unitAuras.states[safeUnitId] = {
			entries = {},
		}
	end

	return self.unitAuras.states[safeUnitId]
end

function Main.API:ResetUnitAuras(unitId)
	local state

	state = self:GetUnitAuraState(unitId)
	state.entries = {}
	state.activeToken = nil
	state.requestPending = nil
	state.requestToken = nil
	state.lastRequestAt = nil
	state.unitGuid = nil
	state.unavailable = nil
	state.expectedCount = nil
	state.receivedCount = nil

	if self.unitAuras and self.unitAuras.activeUnitId == unitId then
		self.unitAuras.activeUnitId = nil
		self.unitAuras.activeToken = nil
	end
end

function Main.API:IsPlayerDead()
	if UnitIsDead and UnitIsDead("player") then
		return 1
	end

	if UnitHealth and UnitHealth("player") == 0 then
		return 1
	end

	return nil
end

function Main.API:RequestUnitAuras(unitId, force)
	local state
	local now
	local token
	local safeUnitId

	if self.auraUnsupported then
		return nil
	end

	safeUnitId = unitId or "target"
	if not UnitExists or not UnitExists(safeUnitId) then
		return nil
	end
	if self:IsPlayerDead() then
		self:ResetUnitAuras(safeUnitId)
		return nil
	end
	if self.handshake and self.handshake.completed and not self:IsServerApiSupported("auras") then
		self:HandleAuraUnsupported()
		return nil
	end

	state = self:GetUnitAuraState(unitId)
	now = GetTime and GetTime() or 0

	if state.requestPending and not force then
		return nil
	end
	if not force and state.lastRequestAt and (now - state.lastRequestAt) < self.unitAuras.requestRetrySeconds then
		return nil
	end

	token = self:CreateRequestToken()
	if self:SendCommand("get_auras", unitId, token) then
		state.requestPending = 1
		state.requestToken = token
		state.lastRequestAt = now
		return 1
	end

	return nil
end

function Main.API:GetUnitAuras(unitId)
	return self:GetUnitAuraState(unitId).entries
end

function Main.API:IsUnitAurasUnavailable(unitId)
	return self:GetUnitAuraState(unitId).unavailable
end

function Main.API:HandleTargetDistanceMessage(message)
	local unitId
	local distanceRaw
	local requestToken
	local distanceValue
	local state

	_, _, unitId, distanceRaw, requestToken = string.find(message, "^([^,]+),([^,]+),([^,]+)$")
	if not unitId or not distanceRaw or not requestToken then
		return nil
	end

	unitId = string.lower(string.gsub(unitId, "%s+", ""))
	if unitId ~= "target" then
		return nil
	end

	requestToken = string.gsub(requestToken, "%s+", "")
	state = self.targetDistance
	if state.requestToken and requestToken ~= state.requestToken then
		return 1
	end

	distanceValue = tonumber(string.gsub(distanceRaw, "%s+", ""))
	if not distanceValue then
		return nil
	end

	state.valueYards = floor(distanceValue + 0.5)
	state.unavailable = nil
	state.requestPending = nil
	state.requestToken = nil
	return 1
end

function Main.API:HandleAuraMessage(message)
	local countValue
	local pendingState
	local unitId
	local countText
	local name
	local harmfulText
	local textureText
	local remainingText
	local requestToken
	local unitGuid
	local iconPath
	local state
	local remainingMs
	local now
	local entry

	_, _, unitId, requestToken, unitGuid, countText =
		string.find(message, "^au,([^,]+),([^,]+),([^,]*),([^,]+)$")
	if unitId and requestToken and countText then
		unitId = string.lower(string.gsub(unitId, "%s+", ""))
		requestToken = string.gsub(requestToken, "%s+", "")
		state = self:GetUnitAuraState(unitId)
		if state.requestToken and requestToken ~= state.requestToken then
			return 1
		end

		countValue = tonumber(string.gsub(countText, "%s+", ""))
		if countValue == nil then
			return nil
		end

		state.entries = {}
		state.activeToken = requestToken
		state.requestPending = nil
		state.requestToken = nil
		state.unitGuid = unitGuid or ""
		state.unavailable = nil
		state.expectedCount = countValue
		state.receivedCount = 0

		if countValue > 0 then
			self.unitAuras.activeUnitId = unitId
			self.unitAuras.activeToken = requestToken
		else
			self.unitAuras.activeUnitId = nil
			self.unitAuras.activeToken = nil
		end

		return 1
	end

	_, _, name, harmfulText, remainingText, iconPath =
		string.find(message, "^ae,([^,]*),([^,]+),([^,]+),?(.*)$")
	if harmfulText and remainingText then
		unitId = self.unitAuras and self.unitAuras.activeUnitId or nil
		requestToken = self.unitAuras and self.unitAuras.activeToken or nil
		if not unitId or not requestToken then
			return nil
		end

		state = self:GetUnitAuraState(unitId)
		if not state or state.activeToken ~= requestToken then
			return nil
		end

		remainingMs = tonumber(string.gsub(remainingText, "%s+", ""))
		if not remainingMs then
			return nil
		end

		now = GetTime and GetTime() or 0
		entry = {
			name = name or "",
			harmful = harmfulText == "1",
			iconPath = iconPath and iconPath ~= "" and iconPath or nil,
			remainingMs = remainingMs,
			receivedAt = now,
		}
		if remainingMs >= 0 then
			entry.expiresAt = now + (remainingMs / 1000)
		end

		state.entries[Main_ArrayCount(state.entries) + 1] = entry
		state.unavailable = nil
		state.receivedCount = (state.receivedCount or 0) + 1

		if state.expectedCount and state.receivedCount >= state.expectedCount then
			self.unitAuras.activeUnitId = nil
			self.unitAuras.activeToken = nil
		end

		return 1
	end

	countValue = tonumber(message)
	if countValue ~= nil then
		pendingState = nil

		Main_ForEach(self.unitAuras.states, function(unitId, state)
			if not pendingState and state and state.requestPending and state.requestToken then
				pendingState = state
			elseif pendingState and state and state.requestPending and state.requestToken then
				pendingState = nil
			end
		end)

		if pendingState and countValue <= 0 then
			pendingState.entries = {}
			pendingState.activeToken = pendingState.requestToken
			pendingState.requestPending = nil
			pendingState.requestToken = nil
			pendingState.unavailable = nil
		end

		return 1
	end

	_, _, unitId, name, harmfulText, textureText, remainingText, requestToken, unitGuid, iconPath =
		string.find(message, "^([^,]+),([^,]*),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),?(.*)$")
	if not unitId or not requestToken then
		return nil
	end

	unitId = string.lower(string.gsub(unitId, "%s+", ""))
	requestToken = string.gsub(requestToken, "%s+", "")
	state = self:GetUnitAuraState(unitId)
	if state.requestToken and requestToken ~= state.requestToken then
		return 1
	end

	if state.activeToken ~= requestToken or state.unitGuid ~= unitGuid then
		state.entries = {}
		state.activeToken = requestToken
		state.unitGuid = unitGuid
	end

	remainingMs = tonumber(string.gsub(remainingText, "%s+", ""))
	if not remainingMs then
		return nil
	end

	now = GetTime and GetTime() or 0
	entry = {
		name = name or "",
		harmful = harmfulText == "1",
		iconPath = iconPath and iconPath ~= "" and iconPath or nil,
		remainingMs = remainingMs,
		receivedAt = now,
	}
	if remainingMs >= 0 then
		entry.expiresAt = now + (remainingMs / 1000)
	end

	state.entries[Main_ArrayCount(state.entries) + 1] = entry
	state.unavailable = nil
	if state.requestPending and requestToken == state.requestToken then
		state.requestPending = nil
		state.requestToken = nil
	end

	return 1
end

function Main.API:HandleErrorMessage(message)
	local errorCode
	local unitId
	local requestToken
	local state
	local auraState
	local configCommandFailed
	local configRequestFailed
	local configSaveFailed
	local targetDistanceFailed
	local auraRequestFailed
	local guildRequestFailed
	local petRequestFailed
	local petState

	_, _, errorCode, unitId, requestToken = string.find(message, "^(-?%d+),%s*([^,]+),?%s*(.*)$")
	if not errorCode then
		return
	end

	if unitId then
		unitId = string.lower(string.gsub(unitId, "%s+", ""))
	end
	if requestToken then
		requestToken = string.gsub(requestToken, "%s+", "")
	end

	configRequestFailed = self.requestPending and requestToken == self.requestToken
	configSaveFailed = self.savePending and requestToken == self.saveToken

	if configRequestFailed then
		self.requestPending = nil
	end
	if configSaveFailed then
		self.savePending = nil
	end

	state = self.targetDistance
	targetDistanceFailed = state.requestPending and requestToken == state.requestToken and unitId == "target"
	if targetDistanceFailed then
		state.requestPending = nil
		state.requestToken = nil
		state.valueYards = nil
		state.unavailable = 1
	end

	auraState = nil
	if unitId and self.unitAuras and self.unitAuras.states and self.unitAuras.states[unitId] then
		auraState = self.unitAuras.states[unitId]
	end
	auraRequestFailed = auraState and auraState.requestPending and requestToken == auraState.requestToken
	if auraRequestFailed then
		auraState.requestPending = nil
		auraState.requestToken = nil
		auraState.entries = {}
		if errorCode == "-2" then
			auraState.activeToken = requestToken
			auraState.unavailable = nil
		elseif errorCode == "-1" then
			auraState.activeToken = nil
			auraState.unavailable = 1
		else
			auraState.activeToken = nil
			auraState.unavailable = nil
		end
	end

	guildRequestFailed = self.guildRoster and self.guildRoster.requestPending and requestToken == self.guildRoster.requestToken
	if guildRequestFailed then
		self.guildRoster.requestPending = nil
		self.guildRoster.requestToken = nil
	end

	petState = self.petActionBar
	petRequestFailed = petState and petState.requestPending and requestToken == petState.requestToken and unitId == "pet"
	if petRequestFailed then
		petState.requestPending = nil
		petState.requestToken = nil
	end

	if errorCode == "-1" and targetDistanceFailed then
		self:HandleDistanceUnsupported()
	end

	if errorCode == "-1" and auraRequestFailed then
		self:HandleAuraUnsupported()
	end

	configCommandFailed = configRequestFailed or configSaveFailed
	if errorCode == "-1" and configCommandFailed then
		self:HandleConfigUnsupported()
	end

	if errorCode == "-1" and guildRequestFailed then
		self:HandleGuildUnsupported()
	end

	if errorCode == "-1" and petRequestFailed then
		self:HandlePetUnsupported()
	end
end

function Main.API:ResetGuildRoster()
	self.guildRoster = self.guildRoster or {}
	self.guildRoster.members = {}
	self.guildRoster.guildName = nil
	self.guildRoster.motd = nil
	self.guildRoster.onlineCount = 0
	self.guildRoster.totalCount = 0
	self.guildRoster.requestPending = nil
	self.guildRoster.requestToken = nil
	self.guildRoster.lastRequestAt = nil
	self.guildRoster.loaded = nil
end

function Main.API:RequestGuildRoster(force)
	local state
	local now
	local token

	if self.guildUnsupported then
		return nil
	end
	if self.handshake and self.handshake.completed and not self:IsServerApiSupported("guild") then
		self:HandleGuildUnsupported()
		return nil
	end

	self.guildRoster = self.guildRoster or {}
	state = self.guildRoster
	now = GetTime and GetTime() or 0

	if state.requestPending and not force then
		return nil
	end
	if not force and state.lastRequestAt and (now - state.lastRequestAt) < 2 then
		return nil
	end

	token = self:CreateRequestToken()
	if self:SendCommand("get_guild_roster", token) then
		state.requestPending = 1
		state.requestToken = token
		state.lastRequestAt = now
		return 1
	end

	return nil
end

function Main.API:NotifyReloadUI()
	if self.petUnsupported or not self.handshake or not self.handshake.completed then
		return nil
	end
	if not self:IsServerApiSupported("pet") then
		return nil
	end

	return self:SendCommand("notify_reloadui")
end

function Main.API:ResetPetActionBarRequestState(resetRetries)
	local state

	state = self.petActionBar
	if not state then
		return
	end

	state.requestPending = nil
	state.requestToken = nil
	state.lastRequestAt = nil

	if resetRetries then
		state.initialRequestSent = nil
		state.retryAttempts = 0
		state.retryExhausted = nil
	end
end

function Main.API:RequestPetActionBarRefresh(force)
	local state
	local now
	local token

	if self.petUnsupported then
		return nil
	end
	if not self.handshake or not self.handshake.completed then
		return nil
	end
	if not self:IsServerApiSupported("pet") then
		return nil
	end

	state = self.petActionBar
	if force then
		self:ResetPetActionBarRequestState(1)
	end

	if UnitExists and not UnitExists("pet") then
		self:ResetPetActionBarRequestState(1)
		return nil
	end
	if PetHasActionBar and PetHasActionBar() then
		self:ResetPetActionBarRequestState(1)
		return nil
	end

	now = GetTime and GetTime() or 0

	if state.retryExhausted and not force then
		return nil
	end
	if state.requestPending and not force then
		return nil
	end
	if not force and state.lastRequestAt and (now - state.lastRequestAt) < (state.requestRetrySeconds or 1) then
		return nil
	end
	if not force and state.initialRequestSent and
		(state.retryAttempts or 0) >= (state.maxRetries or 5) then
		state.retryExhausted = 1
		return nil
	end

	token = self:CreateRequestToken()
	if self:SendCommand("get_pet_bar", token) then
		if state.initialRequestSent then
			state.retryAttempts = (state.retryAttempts or 0) + 1
		else
			state.initialRequestSent = 1
			state.retryAttempts = 0
		end
		state.requestPending = 1
		state.requestToken = token
		state.lastRequestAt = now
		return 1
	end

	return nil
end

function Main.API:GetGuildRoster()
	self.guildRoster = self.guildRoster or {}
	return self.guildRoster
end

function Main.API:HandleGuildRosterHeader(message)
	local requestToken
	local guildName
	local motd
	local onlineCount
	local totalCount
	local state

	_, _, requestToken, guildName, motd, onlineCount, totalCount =
		string.find(message, "^gr,([^,]+),([^,]*),([^,]*),([^,]*),([^,]*)$")
	if not requestToken then
		return nil
	end

	self.guildRoster = self.guildRoster or {}
	state = self.guildRoster

	if state.requestToken and requestToken ~= state.requestToken then
		return 1
	end

	state.members = {}
	state.guildName = guildName or ""
	state.motd = motd or ""
	state.onlineCount = tonumber(onlineCount) or 0
	state.totalCount = tonumber(totalCount) or 0
	state.activeToken = requestToken
	state.requestPending = nil
	state.requestToken = nil
	state.loaded = 1

	return 1
end

function Main.API:HandleGuildRosterMember(message)
	local name
	local level
	local classId
	local rank
	local online
	local state
	local entry
	local count

	_, _, name, level, classId, rank, online =
		string.find(message, "^gm,([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
	if not name then
		return nil
	end

	self.guildRoster = self.guildRoster or {}
	state = self.guildRoster
	count = Main_ArrayCount(state.members)
	entry = {
		name = name,
		level = tonumber(level) or 0,
		classId = tonumber(classId) or 0,
		rank = tonumber(rank) or 0,
		online = online == "1",
	}
	state.members[count + 1] = entry
	state.loaded = 1

	return 1
end

function Main.API:HandleChannelMessage(message, sender, channelName)
	local playerName

	if not message or not channelName then
		return
	end

	if not string.find(string.lower(channelName), string.lower(self.channelName)) then
		return
	end

	playerName = UnitName("player")
	if playerName and sender and string.lower(sender) ~= string.lower(playerName) then
		return
	end

	if string.find(message, "^api,") then
		self:HandleApiVersionMessage(message)
	elseif string.find(message, "^cfg,") then
		self:HandleConfigMessage(message)
	elseif string.find(message, "^gr,") then
		self:HandleGuildRosterHeader(message)
	elseif string.find(message, "^gm,") then
		self:HandleGuildRosterMember(message)
	elseif string.sub(message, 1, 1) == "-" then
		self:HandleErrorMessage(message)
	elseif not self:HandleTargetDistanceMessage(message) then
		self:HandleAuraMessage(message)
	end
end

function Main.API:OnUpdate()
	local now
	local distanceState
	local unitId
	local auraState
	local hs
	local petState

	if not self.startedAt then
		return
	end

	now = GetTime and GetTime() or 0

	-- Handshake phase: wait for channel, send handshake, wait for response.
	hs = self.handshake
	if not hs.completed and not self.configUnsupported then
		-- Total timeout: if handshake hasn't completed within timeoutSeconds from startup, give up.
		if (now - self.startedAt) >= hs.timeoutSeconds then
			if not hs.completed then
				self:HandleHandshakeFailed()
			end
		elseif hs.pending then
			-- Handshake was sent, waiting for response (timeout handled above).
		else
			-- Channel not ready yet or handshake not sent; try to send.
			self:SendHandshake()
		end

		-- Start local features while waiting.
		if not Main.Initialized and (now - self.startedAt) >= self.fallbackDelaySeconds then
			Main_Start()
		end
		return
	end

	-- Fallback startup if config takes too long.
	if not Main.Initialized and (now - self.startedAt) >= self.fallbackDelaySeconds then
		Main_Start()
	end

	-- Config request retry (only after handshake succeeded).
	if self.requestPending and self.lastRequestAt and (now - self.lastRequestAt) >= self.requestRetrySeconds then
		self.requestPending = nil
	end

	if not self.configUnsupported and not self.remoteLoaded and not self.requestPending then
		self:RequestConfig()
	end

	-- Target distance timeout.
	distanceState = self.targetDistance
	if distanceState.requestPending and distanceState.lastRequestAt and
		(now - distanceState.lastRequestAt) >= distanceState.requestRetrySeconds then
		distanceState.requestPending = nil
		distanceState.requestToken = nil
	end

	-- Aura request timeouts.
	Main_ForEach(self.unitAuras.states, function(unitId, auraState)
		if auraState.requestPending and auraState.lastRequestAt and
			(now - auraState.lastRequestAt) >= self.unitAuras.requestRetrySeconds then
			auraState.requestPending = nil
			auraState.requestToken = nil
		end
	end)

	-- Guild roster request timeout.
	if self.guildRoster and self.guildRoster.requestPending and self.guildRoster.lastRequestAt and
		(now - self.guildRoster.lastRequestAt) >= 5 then
		self.guildRoster.requestPending = nil
		self.guildRoster.requestToken = nil
	end

	-- Pet action bar request timeout.
	petState = self.petActionBar
	if petState then
		if (UnitExists and not UnitExists("pet")) or (PetHasActionBar and PetHasActionBar()) then
			self:ResetPetActionBarRequestState(1)
		elseif petState.requestPending and petState.lastRequestAt and
			(now - petState.lastRequestAt) >= (petState.requestRetrySeconds or 1) then
			petState.requestPending = nil
			petState.requestToken = nil
		end
	end
end
