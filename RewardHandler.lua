-- RewardHandler_Lobby.lua
-- ServerScript - ServerScriptService - LOBBY place
-- Handles saving rewards when players return from a match
-- ✓ FIXED: Now uses RewardCache for Studio testing (TeleportData doesn't work in Studio)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("DataManager"))
local RewardCache = require(ReplicatedStorage:WaitForChild("RewardCache"))

Players.PlayerAdded:Connect(function(player)
	-- Wait for their data to load
	task.wait(2)

	local joinData     = player:GetJoinData()
	local teleportData = joinData.TeleportData
	local rewards = nil

	-- Priority 1: Check DataStore for pending rewards (UNLIMITED TIME!)
	if DataManager:HasPendingRewards(player.UserId) then
		rewards = DataManager:GetPendingRewards(player.UserId)
		print("✓ Got rewards from DataStore (unlimited time storage)")
		-- Priority 2: Try TeleportData (works in live game for immediate teleports)
	elseif teleportData and teleportData.Rewards then
		rewards = teleportData.Rewards
		print("✓ Got rewards from TeleportData (live game)")
		-- Priority 3: Fallback to RewardCache (legacy support)
	elseif RewardCache:Has(player.UserId) then
		rewards = RewardCache:Retrieve(player.UserId)
		print("✓ Got rewards from RewardCache (Studio fallback)")
	end

	if rewards then
		print("═════════════════════════════════════════")
		print("🎁 " .. player.Name .. " returned from match with rewards!")
		print("═════════════════════════════════════════")

		-- Save currency earned
		if rewards.Currency and rewards.Currency > 0 then
			local success = DataManager:AddCurrency(player, rewards.Currency)
			if success then
				print("  💰 Added " .. rewards.Currency .. " currency")
			else
				warn("  ❌ Failed to add currency!")
			end
		end

		-- Save dropped troops
		if rewards.NewTroops and type(rewards.NewTroops) == "table" then
			if #rewards.NewTroops > 0 then
				print("  🧟 Processing " .. #rewards.NewTroops .. " troop drops:")
				for _, troopData in ipairs(rewards.NewTroops) do
					local success = DataManager:AddTroops(
						player, 
						troopData.troopType,  -- ✅ Lowercase
						troopData.rarity,     -- ✅ Lowercase  
						troopData.amount or 1 -- ✅ Lowercase
					)
					if success then
						print("    ✓ Added " .. (troopData.Amount or 1) .. "x " .. troopData.Rarity .. " " .. troopData.TroopType)
					else
						warn("    ❌ Failed to add " .. troopData.Rarity .. " " .. troopData.TroopType)
					end
				end
			else
				print("  ℹ No troop drops this match")
			end
		else
			print("  ℹ No troop drops data received")
		end

		-- Update stats
		if rewards.Stats then
			local data = DataManager:GetData(player)
			if data then
				if rewards.Stats.Won then
					data.Stats.GamesWon = data.Stats.GamesWon + 1
					print("  🏆 Victory! Total wins: " .. data.Stats.GamesWon)
				else
					print("  💀 Defeat! Total games: " .. data.Stats.GamesPlayed + 1)
				end

				data.Stats.GamesPlayed = data.Stats.GamesPlayed + 1
				data.Stats.TotalKills  = data.Stats.TotalKills + (rewards.Stats.Kills or 0)

				if rewards.Stats.HighestWave and rewards.Stats.HighestWave > data.Stats.HighestWave then
					data.Stats.HighestWave = rewards.Stats.HighestWave
					print("  📊 New highest wave: " .. data.Stats.HighestWave)
				end

				print("  ⚔️ Total kills: " .. data.Stats.TotalKills)
			else
				warn("  ❌ Failed to get player data for stats update!")
			end
		end

		print("═════════════════════════════════════════")
		print("✅ Rewards saved successfully!")
		print("═════════════════════════════════════════")

		-- Force save data
		DataManager:SaveData(player)
	else
		print(player.Name .. " joined lobby (no rewards data)")
	end
end)

print("✓ RewardHandler loaded with enhanced logging + RewardCache support")