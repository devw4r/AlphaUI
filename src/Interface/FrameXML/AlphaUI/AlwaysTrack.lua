local MainAlwaysTrack = {
	name = "Always Track",
	description = "Keeps Find Minerals, Find Herbs, and Find Treasure active when learned.",
}

local mainAlwaysTrackBookTypes = {
	BOOKTYPE_ABILITY or "ability",
	BOOKTYPE_SPELL or "spell",
}

local mainAlwaysTrackTrackedSpells = {
	{ label = "Find Herbs", spellName = "Find Herbs", spellId = 2383, textures = { "Interface\\Icons\\Spell_Nature_NatureTouchGrow" } },
	{ label = "Find Minerals", spellName = "Find Minerals", spellId = 2580, textures = { "Interface\\Icons\\Spell_Nature_Earthquake" } },
	{ label = "Find Treasure", spellName = "Find Treasure", spellId = 2481, textures = { "Interface\\Icons\\Racial_Dwarf_FindTreasure" } },
}

local mainAlwaysTrackKnownSpells = {}
local mainAlwaysTrackHasKnownSpell = nil
local mainAlwaysTrackRetryAt = nil
local MAIN_ALWAYS_TRACK_RETRY_BUFFER_SECONDS = 0.2
local MAIN_ALWAYS_TRACK_BUFF_FILTER = "HELPFUL|PASSIVE"
local MAIN_ALWAYS_TRACK_FIND_TREASURE_SPELL_ID = 2481
local MAIN_ALWAYS_TRACK_CAST_ERROR_WINDOW_SECONDS = 1
local mainAlwaysTrackLastCastSpellId = nil
local mainAlwaysTrackLastCastAt = nil
local mainAlwaysTrackFindTreasureNeedsStand = nil
local MainAlwaysTrack_EnsureTracking

local function MainAlwaysTrack_IsPlayerDead()
	if UnitIsDead and UnitIsDead("player") then
		return 1
	end

	if UnitHealth and UnitHealth("player") == 0 then
		return 1
	end

	return nil
end

local function MainAlwaysTrack_FindSpellByName(spellName)
	local bookIndex
	local bookType
	local slot
	local slotName
	local emptyCount
	local maxSpells

	if not spellName or not GetSpellName then
		return nil, nil, nil
	end

	maxSpells = MAX_SPELLS or 1024
	for bookIndex = 1, Main_ArrayCount(mainAlwaysTrackBookTypes) do
		bookType = mainAlwaysTrackBookTypes[bookIndex]
		emptyCount = 0
		for slot = 1, maxSpells do
			slotName = GetSpellName(slot, bookType)
			if slotName and slotName ~= "" then
				emptyCount = 0
				if slotName == spellName then
					return slot, bookType, GetSpellTexture and GetSpellTexture(slot, bookType) or nil
				end
			else
				emptyCount = emptyCount + 1
				if emptyCount >= 64 then
					break
				end
			end
		end
	end

	return nil, nil, nil
end

local function MainAlwaysTrack_RefreshKnownSpells()
	local spellIndex
	local spellInfo
	local slot
	local bookType
	local texture
	local hadKnownSpell
	local hasKnownSpell

	hadKnownSpell = mainAlwaysTrackHasKnownSpell and 1 or nil
	mainAlwaysTrackKnownSpells = {}
	hasKnownSpell = nil

	for spellIndex = 1, Main_ArrayCount(mainAlwaysTrackTrackedSpells) do
		spellInfo = mainAlwaysTrackTrackedSpells[spellIndex]
		slot, bookType, texture = MainAlwaysTrack_FindSpellByName(spellInfo.spellName)
		if slot and bookType then
			Main_ArrayInsert(mainAlwaysTrackKnownSpells, {
				label = spellInfo.label,
				spellId = spellInfo.spellId,
				slot = slot,
				bookType = bookType,
				texture = texture,
				textures = spellInfo.textures,
			})
			hasKnownSpell = 1
		end
	end

	mainAlwaysTrackHasKnownSpell = hasKnownSpell

	if hadKnownSpell ~= (mainAlwaysTrackHasKnownSpell and 1 or nil) and Main.ScheduleManagerRefresh then
		Main.ScheduleManagerRefresh()
	end
end

local function MainAlwaysTrack_GetActiveBuffTextures()
	local buffIndex
	local activeBuffIndex
	local buffTexture
	local activeTextures

	activeTextures = {}
	if not GetPlayerBuff or not GetPlayerBuffTexture then
		return activeTextures
	end

	for buffIndex = 0, 15 do
		activeBuffIndex = GetPlayerBuff(buffIndex, MAIN_ALWAYS_TRACK_BUFF_FILTER)
		if activeBuffIndex and activeBuffIndex >= 0 then
			buffTexture = GetPlayerBuffTexture(activeBuffIndex)
			if buffTexture then
				activeTextures[buffTexture] = 1
			end
		end
	end

	return activeTextures
end

local function MainAlwaysTrack_IsSpellTextureActive(knownSpell, activeBuffTextures)
	local textureIndex
	local texture

	if not knownSpell or not activeBuffTextures then
		return nil
	end

	if knownSpell.texture and activeBuffTextures[knownSpell.texture] then
		return 1
	end

	if knownSpell.textures then
		for textureIndex = 1, Main_ArrayCount(knownSpell.textures) do
			texture = knownSpell.textures[textureIndex]
			if texture and activeBuffTextures[texture] then
				return 1
			end
		end
	end

	return nil
end

local function MainAlwaysTrack_GetMissingKnownSpells()
	local activeBuffTextures
	local missingSpells
	local spellIndex
	local knownSpell

	activeBuffTextures = MainAlwaysTrack_GetActiveBuffTextures()
	missingSpells = {}

	for spellIndex = 1, Main_ArrayCount(mainAlwaysTrackKnownSpells) do
		knownSpell = mainAlwaysTrackKnownSpells[spellIndex]
		if knownSpell and knownSpell.slot and knownSpell.bookType then
			if not MainAlwaysTrack_IsSpellTextureActive(knownSpell, activeBuffTextures) then
				Main_ArrayInsert(missingSpells, knownSpell)
			end
		end
	end

	return missingSpells
end

local function MainAlwaysTrack_ShouldMaintainTracking()
	if not Main.IsModuleEnabled("always_track") then
		mainAlwaysTrackRetryAt = nil
		return nil
	end

	if MainAlwaysTrack_IsPlayerDead() then
		mainAlwaysTrackRetryAt = nil
		return nil
	end

	if not mainAlwaysTrackHasKnownSpell then
		mainAlwaysTrackRetryAt = nil
		return nil
	end

	return 1
end

local function MainAlwaysTrack_GetReadyAt(knownSpell)
	local startTime
	local duration
	local enabled
	local now

	if not knownSpell or not knownSpell.slot or not knownSpell.bookType or not GetSpellCooldown then
		return 0
	end

	startTime, duration, enabled = GetSpellCooldown(knownSpell.slot, knownSpell.bookType)
	startTime = Main_ToNumber(startTime, 0) or 0
	duration = Main_ToNumber(duration, 0) or 0
	enabled = Main_ToNumber(enabled, 1)
	now = GetTime and GetTime() or 0

	if enabled == 0 then
		return now + 86400
	end

	if duration <= 0 then
		return 0
	end

	return startTime + duration + MAIN_ALWAYS_TRACK_RETRY_BUFFER_SECONDS
end

local function MainAlwaysTrack_IsNotStandingError(message)
	if not message or message == "" then
		return nil
	end

	if SPELL_FAILED_NOTSTANDING and message == SPELL_FAILED_NOTSTANDING then
		return 1
	end

	return nil
end

local function MainAlwaysTrack_OnErrorMessage()
	local message
	local now

	message = arg1
	if not MainAlwaysTrack_IsNotStandingError(message) then
		return
	end
	if mainAlwaysTrackLastCastSpellId ~= MAIN_ALWAYS_TRACK_FIND_TREASURE_SPELL_ID then
		return
	end

	now = GetTime and GetTime() or 0
	if mainAlwaysTrackLastCastAt and (now - mainAlwaysTrackLastCastAt) <= MAIN_ALWAYS_TRACK_CAST_ERROR_WINDOW_SECONDS then
		mainAlwaysTrackFindTreasureNeedsStand = 1
		mainAlwaysTrackRetryAt = nil
	end
end

local function MainAlwaysTrack_OnPlayerStand()
	if not mainAlwaysTrackFindTreasureNeedsStand then
		return
	end

	mainAlwaysTrackFindTreasureNeedsStand = nil
	MainAlwaysTrack_EnsureTracking()
end

MainAlwaysTrack_EnsureTracking = function()
	local now
	local missingSpells
	local spellIndex
	local knownSpell
	local readyAt
	local nextReadyAt
	local spellToCast

	if not MainAlwaysTrack_ShouldMaintainTracking() then
		return
	end

	missingSpells = MainAlwaysTrack_GetMissingKnownSpells()
	if Main_ArrayCount(missingSpells) <= 0 then
		mainAlwaysTrackRetryAt = nil
		return
	end

	now = GetTime and GetTime() or 0

	for spellIndex = 1, Main_ArrayCount(missingSpells) do
		knownSpell = missingSpells[spellIndex]
		readyAt = MainAlwaysTrack_GetReadyAt(knownSpell)
		if not readyAt or readyAt <= now then
			if knownSpell.spellId ~= MAIN_ALWAYS_TRACK_FIND_TREASURE_SPELL_ID or not mainAlwaysTrackFindTreasureNeedsStand then
				spellToCast = knownSpell
				break
			end
		end
		if not nextReadyAt or readyAt < nextReadyAt then
			nextReadyAt = readyAt
		end
	end

	if spellToCast then
		mainAlwaysTrackLastCastSpellId = spellToCast.spellId
		mainAlwaysTrackLastCastAt = now
		mainAlwaysTrackRetryAt = now + MAIN_ALWAYS_TRACK_RETRY_BUFFER_SECONDS
		CastSpell(spellToCast.slot, spellToCast.bookType)
		return
	end

	mainAlwaysTrackRetryAt = nextReadyAt
end

local function MainAlwaysTrack_OnWorldOrAuraChanged()
	MainAlwaysTrack_EnsureTracking()
end

local function MainAlwaysTrack_OnSpellsChanged()
	MainAlwaysTrack_RefreshKnownSpells()
	MainAlwaysTrack_EnsureTracking()
end

function MainAlwaysTrack:IsAvailable()
	return mainAlwaysTrackHasKnownSpell and true or false
end

function MainAlwaysTrack:Init()
	MainAlwaysTrack_RefreshKnownSpells()
	Main.RegisterEventHandler("PLAYER_ENTERING_WORLD", "always_track_entering_world", MainAlwaysTrack_OnWorldOrAuraChanged)
	Main.RegisterEventHandler("PLAYER_AURAS_CHANGED", "always_track_auras_changed", MainAlwaysTrack_OnWorldOrAuraChanged)
	Main.RegisterEventHandler("SPELLS_CHANGED", "always_track_spells_changed", MainAlwaysTrack_OnSpellsChanged)
	Main.RegisterEventHandler("UI_ERROR_MESSAGE", "always_track_ui_error", MainAlwaysTrack_OnErrorMessage)
	Main.RegisterEventHandler("PLAYER_STAND", "always_track_player_stand", MainAlwaysTrack_OnPlayerStand)
end

function MainAlwaysTrack:Enable()
	MainAlwaysTrack_RefreshKnownSpells()
	MainAlwaysTrack_EnsureTracking()
end

function MainAlwaysTrack:Disable()
	mainAlwaysTrackRetryAt = nil
	mainAlwaysTrackLastCastSpellId = nil
	mainAlwaysTrackLastCastAt = nil
	mainAlwaysTrackFindTreasureNeedsStand = nil
end

function MainAlwaysTrack:ApplyConfig()
	MainAlwaysTrack_RefreshKnownSpells()
	MainAlwaysTrack_EnsureTracking()
end

function MainAlwaysTrack:ProcessDeferredRefresh()
	local now

	if not mainAlwaysTrackRetryAt then
		return
	end

	now = GetTime and GetTime() or 0
	if now < mainAlwaysTrackRetryAt then
		return
	end

	mainAlwaysTrackRetryAt = nil
	MainAlwaysTrack_EnsureTracking()
end

Main.RegisterModule("always_track", MainAlwaysTrack)
