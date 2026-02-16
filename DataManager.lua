-- DataManager.lua (Studio Compatible Version)
-- Put this in ServerScriptService (LOBBY place)
-- Works in BOTH Studio and Live Games

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local DataManager = {}
DataManager.Profiles = {} -- Stores active player profiles
DataManager.PendingRewardsStore = nil -- DataStore for cross-place rewards

-- Detect if we're in Studio
local IS_STUDIO = RunService:IsStudio()

-- Studio Mode: Use DataStoreService (actually saves!)
local StudioDataStore = nil
if IS_STUDIO then
	print("🔧 DataManager: Running in STUDIO mode (using DataStoreService)")
	pcall(function()
		StudioDataStore = DataStoreService:GetDataStore("PlayerData_Studio_V1")
		DataManager.PendingRewardsStore = DataStoreService:GetDataStore("PendingRewards_Studio_V1")
	end)
	if not StudioDataStore then
		warn("⚠️ DataStore API not enabled in Studio! Enable it in Game Settings > Security")
	end
else
	print("🌐 DataManager: Running in LIVE mode (using ProfileService)")
	-- Initialize PendingRewards DataStore for live mode too
	pcall(function()
		DataManager.PendingRewardsStore = DataStoreService:GetDataStore("PendingRewards_V1")
	end)
end

-- Live Mode: Use ProfileService
local ProfileService = nil
local ProfileStore = nil
if not IS_STUDIO then
	ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
	ProfileStore = ProfileService.GetProfileStore(
		"PlayerData_V1",
		PlayerData.Template
	)
end

-- ═════════════════════════════════════════════════════════════════════
-- STUDIO MODE: DataStore functions
-- ═════════════════════════════════════════════════════════════════════

local function LoadDataStudio(player)
	if not StudioDataStore then
		warn("DataStore not available, using default data")
		return PlayerData.GetDefault()
	end

	local success, data = pcall(function()
		return StudioDataStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		print("✓ Loaded Studio data for", player.Name)
		-- Reconcile (fill in missing fields from template)
		for key, value in pairs(PlayerData.Template) do
			if data[key] == nil then
				data[key] = value
			end
		end
		return data
	else
		print("ℹ️ No Studio data found for", player.Name, "- using defaults")
		return PlayerData.GetDefault()
	end
end

local function SaveDataStudio(player, data)
	if not StudioDataStore then
		warn("DataStore not available, cannot save!")
		return false
	end

	local success, err = pcall(function()
		StudioDataStore:SetAsync("Player_" .. player.UserId, data)
	end)

	if success then
		print("💾 Saved Studio data for", player.Name)
		return true
	else
		warn("❌ Failed to save Studio data:", err)
		return false
	end
end

-- ═════════════════════════════════════════════════════════════════════
-- LIVE MODE: ProfileService functions
-- ═════════════════════════════════════════════════════════════════════

local function LoadDataLive(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile:ListenToRelease(function()
			DataManager.Profiles[player] = nil
			player:Kick("Your profile was loaded in another server")
		end)

		if player:IsDescendantOf(Players) then
			DataManager.Profiles[player] = profile
			print("✓ Loaded ProfileService data for", player.Name)
			return profile.Data
		else
			profile:Release()
		end
	else
		player:Kick("Failed to load your data. Please rejoin!")
		return nil
	end
end

-- ═════════════════════════════════════════════════════════════════════
-- UNIFIED API (works in both Studio and Live)
-- ═════════════════════════════════════════════════════════════════════

-- Load player data when they join
function DataManager:LoadPlayerData(player)
	if IS_STUDIO then
		local data = LoadDataStudio(player)
		DataManager.Profiles[player] = {Data = data, IsStudio = true}
		return data
	else
		return LoadDataLive(player)
	end
end

-- Get player's current data
function DataManager:GetData(player)
	local profile = DataManager.Profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

-- Save player data (Studio only - ProfileService auto-saves)
function DataManager:SaveData(player)
	if IS_STUDIO then
		local profile = DataManager.Profiles[player]
		if profile and profile.Data then
			return SaveDataStudio(player, profile.Data)
		end
	else
		-- ProfileService auto-saves, but we'll log it
		print("💾 ProfileService auto-saves (no manual save needed)")
	end
	return true
end

-- Release player data when they leave
function DataManager:ReleaseData(player)
	if IS_STUDIO then
		-- Save one final time
		self:SaveData(player)
		DataManager.Profiles[player] = nil
		print("Released data for", player.Name, "(Studio)")
	else
		local profile = DataManager.Profiles[player]
		if profile and not profile.IsStudio then
			profile:Release()
			DataManager.Profiles[player] = nil
			print("Released data for", player.Name, "(Live)")
		end
	end
end

-- Add troops to player's inventory (used after matches)
function DataManager:AddTroops(player, troopType, rarity, amount)
	local data = self:GetData(player)
	if data then
		local newCount = PlayerData.AddTroop(data, troopType, rarity, amount)
		print("Added", amount, rarity, troopType, "to", player.Name, "| New count:", newCount)

		-- Force save in Studio
		if IS_STUDIO then
			self:SaveData(player)
		end

		return true
	end
	return false
end

-- Remove troops from inventory (used in crafting)
function DataManager:RemoveTroops(player, troopType, rarity, amount)
	local data = self:GetData(player)
	if data then
		return PlayerData.RemoveTroop(data, troopType, rarity, amount)
	end
	return false
end

-- Add currency
function DataManager:AddCurrency(player, amount)
	local data = self:GetData(player)
	if data then
		data.Currency = data.Currency + amount
		print("Added", amount, "cash to", player.Name, "| New balance:", data.Currency)

		-- Force save in Studio
		if IS_STUDIO then
			self:SaveData(player)
		end

		return data.Currency
	end
	return nil
end

-- Equip a troop to a slot
function DataManager:EquipTroop(player, slotNumber, troopType, rarity)
	local data = self:GetData(player)
	if data then
		local success = PlayerData.EquipTroop(data, slotNumber, troopType, rarity)

		-- Force save in Studio
		if IS_STUDIO and success then
			self:SaveData(player)
		end

		return success
	end
	return false
end

-- Get player's equipped loadout
function DataManager:GetLoadout(player)
	local data = self:GetData(player)
	if data then
		return data.EquippedLoadout
	end
	return {}
end

-- Unequip a troop from a slot
function DataManager:UnequipTroop(player, slotNumber)
	local data = self:GetData(player)
	if data then
		local success = PlayerData.UnequipTroop(data, slotNumber)

		-- Force save in Studio
		if IS_STUDIO and success then
			self:SaveData(player)
		end

		return success
	end
	return false
end

-- ═════════════════════════════════════════════════════════════════════
-- PENDING REWARDS SYSTEM (for cross-place reward persistence)
-- ═════════════════════════════════════════════════════════════════════

-- Save pending rewards when player leaves gameplay (UNLIMITED TIME!)
function DataManager:SavePendingRewards(userId, rewardData)
	if not DataManager.PendingRewardsStore then
		warn("⚠️ PendingRewardsStore not available!")
		return false
	end

	local key = "PendingRewards_" .. userId
	local success, err = pcall(function()
		DataManager.PendingRewardsStore:SetAsync(key, {
			Data = rewardData,
			Timestamp = os.time()
		})
	end)

	if success then
		print("💾 Saved pending rewards for userId " .. userId .. " to DataStore (unlimited time)")
		return true
	else
		warn("❌ Failed to save pending rewards:", err)
		return false
	end
end

-- Retrieve and clear pending rewards when player joins lobby
function DataManager:GetPendingRewards(userId)
	if not DataManager.PendingRewardsStore then
		warn("⚠️ PendingRewardsStore not available!")
		return nil
	end

	local key = "PendingRewards_" .. userId
	local success, data = pcall(function()
		return DataManager.PendingRewardsStore:GetAsync(key)
	end)

	if success and data and data.Data then
		print("✓ Found pending rewards for userId " .. userId .. " (saved at " .. os.date("%X", data.Timestamp) .. ")")

		-- Clear the pending rewards after retrieval
		pcall(function()
			DataManager.PendingRewardsStore:RemoveAsync(key)
		end)

		return data.Data
	end

	return nil
end

-- Check if player has pending rewards (without clearing them)
function DataManager:HasPendingRewards(userId)
	if not DataManager.PendingRewardsStore then
		return false
	end

	local key = "PendingRewards_" .. userId
	local success, data = pcall(function()
		return DataManager.PendingRewardsStore:GetAsync(key)
	end)

	return success and data ~= nil
end

-- ═════════════════════════════════════════════════════════════════════
-- Auto-save loop (Studio only)
-- ═════════════════════════════════════════════════════════════════════

if IS_STUDIO then
	task.spawn(function()
		while true do
			task.wait(30) -- Save every 30 seconds
			for player, profile in pairs(DataManager.Profiles) do
				if profile.IsStudio and profile.Data then
					SaveDataStudio(player, profile.Data)
				end
			end
		end
	end)
	print("🔄 Studio auto-save enabled (every 30 seconds)")
end

-- ═════════════════════════════════════════════════════════════════════
-- Player join/leave handlers
-- ═════════════════════════════════════════════════════════════════════

Players.PlayerAdded:Connect(function(player)
	DataManager:LoadPlayerData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	DataManager:ReleaseData(player)
end)

return DataManager