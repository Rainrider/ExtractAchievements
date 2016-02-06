local addonName, ns = ...

local db
local Debug = function() end

local find = string.find
local lower = string.lower
local format = string.format
local huge = math.huge

local GetMapNameByID = GetMapNameByID

local GetAchievementCriteriaInfo = GetAchievementCriteriaInfo
local GetAchievementCriteriaInfoByID = GetAchievementCriteriaInfoByID
local GetAchievementInfo = GetAchievementInfo
local GetAchievementNumCriteria = GetAchievementNumCriteria
local GetCategoryNumAchievements = GetCategoryNumAchievements
local GetPreviousAchievement = GetPreviousAchievement

local EJ_GetEncounterInfo = EJ_GetEncounterInfo
local EJ_GetEncounterInfoByIndex = EJ_GetEncounterInfoByIndex
local EJ_GetInstanceByIndex = EJ_GetInstanceByIndex
local EJ_GetInstanceInfo = EJ_GetInstanceInfo
local EJ_GetNumTiers = EJ_GetNumTiers
local EJ_SelectInstance = EJ_SelectInstance
local EJ_SelectTier = EJ_SelectTier

--[[
	  168, -- Dungeons & Raids
	14808, -- Classic
	14805, -- The Burning Crusade
	14806, -- Lich King Dungeon
	14922, -- Lich King Raid
	15067, -- Cataclysm Dungeon
	15068, -- Cataclysm Raid
	15106, -- Pandaria Dungeon
	15107, -- Pandaria Raid
	15228, -- Draenor Dungeon
	15231, -- Draenor Raid
	15115, -- Dungeon Challenges
--]]

local tierIDToCategoryID = {
	[1] = { dungeons = 14808, raids = 14808 }, -- Classic
	[2] = { dungeons = 14805, raids = 14805 }, -- The Burning Crusade
	[3] = { dungeons = 14806, raids = 14922 }, -- Wrath of the Lich King
	[4] = { dungeons = 15067, raids = 15068 }, -- Cataclysm
	[5] = { dungeons = 15106, raids = 15107 }, -- Mists of Pandaria
	[6] = { dungeons = 15228, raids = 15231 }, -- Warlords of Draenor
}

local addon = CreateFrame("Frame", addonName)
addon:SetScript("OnEvent", function(self, event, ...)
	self[event](self, event, ...)
end)
addon:RegisterEvent("ADDON_LOADED")

function addon:ADDON_LOADED(_, name)
	if (name ~= addonName) then return end

	ExtractAchievementsDB = ExtractAchievementsDB or {}
	db = ExtractAchievementsDB

	if (AdiDebug) then
		Debug = AdiDebug:Embed(self, addonName)
	end

	_G["SLASH_"..addonName.."1"] = "/exach"
	SlashCmdList[addonName] = self.GetData

	self:UnregisterEvent("ADDON_LOADED")
end

--[[
	achievementsPerCategory = {
		[catID] = {
			[achievementID] = {
				name = "name",
				desc = "desc",
			},
		}
	}
]]
local achievementsPerCategory = {}

function addon:GetAchievementSeries(achievementID, numEntries, store)
	-- TODO: code repetition
	while true do
		achievementID = GetPreviousAchievement(achievementID)
		if (not achievementID) then break end
		local _, name, _, _, _, _, _, desc = GetAchievementInfo(achievementID)
		store[achievementID] = { name = lower(name), desc = lower(desc), criteria = {} }
		numEntries = numEntries + 1
		for i = 1, GetAchievementNumCriteria(achievementID) do
			local _, _, _, _, _, _, _, _, _, criteriaID = GetAchievementCriteriaInfo(achievementID, i)
			store[achievementID].criteria[i] = criteriaID
		end
	end

	return numEntries
end

-- e.g. Populate all achievements for Draenor Raid (catID 15231)
function addon:GetAchievementsForCategoryID(catID)
	achievementsPerCategory[catID] = achievementsPerCategory[catID] or {}
	local categoryAchievements = achievementsPerCategory[catID]

	if (not next(categoryAchievements)) then
		local numEntries = 0
		for i = 1, GetCategoryNumAchievements(catID) do
			local id, name, _, _, _, _, _, desc = GetAchievementInfo(catID, i)
			if (not id) then break end

			categoryAchievements[id] = { name = lower(name), desc = lower(desc), criteria = {} }
			numEntries = numEntries + 1
			for j = 1, GetAchievementNumCriteria(id) do
				local _, _, _, _, _, _, _, _, _, criteriaID = GetAchievementCriteriaInfo(id, j)
				categoryAchievements[id].criteria[j] = criteriaID
			end

			numEntries = self:GetAchievementSeries(id, numEntries, categoryAchievements)
		end

		if (numEntries == 0) then
			Debug("|cff0099CCCategory|r", "No achievements found for", catID)
		end
	end

	return categoryAchievements
end

local achievementsPerMap = {}
-- e.g. get all achievements for Hellfire Citadel (mapID 1026) from Draenor Raid (catID 15231)
function addon:GetCategoryAchievementsForMapID(catID, mapID, instanceID)
	achievementsPerMap[mapID] = achievementsPerMap[mapID] or {}
	local mapAchievements = achievementsPerMap[mapID]
	local mapName = lower(GetMapNameByID(mapID))
	local instanceName = lower(EJ_GetInstanceInfo(instanceID))
	if (mapName ~= instanceName) then
		Debug("MapName", "Map and instance name differ: ", mapName, instanceName)
	end

	if (not next(mapAchievements)) then
		local numEntries = 0
		local categoryAchievements = self:GetAchievementsForCategoryID(catID)

		for achievementID, data in pairs(categoryAchievements) do
			if (find(data.name, mapName, 1, true) or find(data.desc, mapName, 1, true)) then
				mapAchievements[achievementID] = data
				numEntries = numEntries + 1
			end
		end
		if (numEntries == 0) then
			Debug("|cff0099CCMap|r", "No achievements found for", mapName, mapID)
		end
	end

	return mapAchievements
end

local function CheckCriteria(encounterID, achievementID, criteria)
	for i = 1, #criteria do
		local _, assetType, _, _, _, _, _, assetID = GetAchievementCriteriaInfoByID(achievementID, criteria[i])
		if (assetID == encounterID) then
			return true
		end
	end
end

local encounterExceptions = {
	-- Argaloth
	[139] = { 5416 },
	-- Occu'thar
	[140] = { 6045 },
	-- Theralion and Valiona
	[157] = { 4852, 5117 },
	-- Nefarian's End
	[174] = { 4849, 5116, 5462 },
	-- Baleroc, the Gatekeeper
	[196] = { 5805, 5830 },
	-- Majordomo Staghelm
	[197] = { 5799, 5804 },
	-- Alizabal
	[339] = { 6108 },
	-- The Spirit Kings
	[687] = { 6722, 6687 },
	-- Chi-Ji
	[857] = { 8535 },
	-- Yu'lon
	[858] = { 8535 },
	-- Niuzao
	[859] = { 8535 },
	-- Xuen
	[860] = { 8535 },
}

function addon:GetAchievementsForEncounter(encounterID, mapID, instanceID, categoryID, store)
	local categoryAchievements = self:GetAchievementsForCategoryID(categoryID)
	self:GetCategoryAchievementsForMapID(categoryID, mapID, instanceID)

	local exceptions = encounterExceptions[encounterID]
	if (exceptions) then
		for i = 1, #exceptions do
			store[i] = exceptions[i]
		end
		return -- TODO: do not return here if not all exceptions are listed
	end

	local encounterName = lower(EJ_GetEncounterInfo(encounterID))

	for achievementID, data in pairs(categoryAchievements) do
		if (find(data.name, encounterName, 1, true) or find(data.desc, encounterName, 1, true) or CheckCriteria(encounterID, achievementID, data.criteria)) then
			store[#store + 1] = achievementID
		end
	end

	if (#store == 0) then
		Debug("|cff0099CCEncounter|r", "No achievements found for", encounterName, encounterID)
	end
end

function addon:GetAchievements(store) -- store is either db.encounters.raids or db.encounter.dungeons
	-- for tier = 1, #store do
	-- 	for instance = 1, #store[tier] do
	-- 		for boss = 1, #store[tier][instance] do
	-- 			local encounter = store[tier][instance][boss]
	-- 			self:GetAchievementsForEncounter(encounter.encounter, encounter.map, encounter.category, encounter.achievements)
	-- 		end
	-- 	end
	-- end

	for tier, instances in pairs(store) do
		for instance = 1, #instances do
			for boss = 1, #instances[instance] do
				local encounter = instances[instance][boss]
				self:GetAchievementsForEncounter(encounter.encounter, encounter.map, encounter.instance, encounter.category, encounter.achievements)
			end
		end
	end
end

function addon:GetEncountersByType(encounterType, fromTier, toTier, store)
	if (encounterType ~= "raids" and encounterType ~= "dungeons") then return end
	if (fromTier > toTier or fromTier < 1 or toTier > EJ_GetNumTiers()) then return end

	store[encounterType] = {}
	local encounters = store[encounterType]

	for tier = fromTier, toTier do
		EJ_SelectTier(tier)
		encounters[tier] = {}
		local currentTier = encounters[tier]

		for instance = 1, math.huge do
			local instanceID = EJ_GetInstanceByIndex(instance, encounterType == "raids")

			if (not instanceID) then break end
			-- need to do this, else mapID is sometimes -1
			EJ_SelectInstance(instanceID)
			local _, _, _, _, _, _, mapID = EJ_GetInstanceInfo(instanceID)

			currentTier[instance] = {}
			local currentInstance = currentTier[instance]
			local map = encounters[mapID]

			for encounter = 1, math.huge do
				local name, _, encounterID = EJ_GetEncounterInfoByIndex(encounter, instanceID)

				if (not name) then break end

				currentInstance[encounter] = {
					encounter = encounterID,
					name = name,
					map = mapID,
					instance = instanceID,
					category = tierIDToCategoryID[tier][encounterType],
					achievements = {}
				}
			end
		end
	end
end

function addon:GetData()
	db.encounters = {}
	--self:GetEncountersByType("raids", 1, EJ_GetNumTiers(), db.encounters)
	--self:GetEncountersByType("dungeons", 1, EJ_GetNumTiers(), db.encounters)

	--self:GetEncountersByType("raids", 4, 4, db.encounters)
	self:GetEncountersByType("dungeons", 3, 3, db.encounters)

	--self:GetAchievements(db.encounters.raids)
	self:GetAchievements(db.encounters.dungeons)

	self:VerifyCategories()
end

function addon:VerifyCategories()
	for catID, achievements in pairs(achievementsPerCategory) do
		local numEntries = 0
		for achievementID in pairs(achievements) do
			numEntries = numEntries + 1
		end
		Debug("Verify", "Category:", catID, "Achievements:", numEntries, "?=", (GetCategoryNumAchievements(catID, true)))
	end
end

function addon:GetAchievementFromCategory(achievementID, catID)
	local cat = achievementsPerCategory[catID]

	for id, data in pairs(cat) do
		if (id == achievementID) then
			return data
		end
	end
end

function addon:TestVanessa()
	local tier = 4 -- Cataclysm
	local instanceID = 63 -- Deadmines

	EJ_SelectTier(tier)
	EJ_SelectInstance(instanceID)

	for i = 1, math.huge do
		local name, _, encounterID = EJ_GetEncounterInfoByIndex(i, instanceID)
		if (not name) then
			print("Encounters found:", i - 1)
			break
		end
		print(name, encounterID)
	end
end
