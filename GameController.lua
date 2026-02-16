-- GameController.lua
-- !! ModuleScript - ServerScriptService - GAMEPLAY place !!
-- Required by GamePLay.lua
-- FIXED: Cash updates now fire properly, wave counter shows after countdown

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local TeleportService     = game:GetService("TeleportService")
local ServerScriptService = game:GetService("ServerScriptService")

local TroopManager = require(ServerScriptService:WaitForChild("TroopManager"))
local EnemyManager = require(ServerScriptService:WaitForChild("EnemyManager"))
local DataManager  = require(ServerScriptService:WaitForChild("DataManager"))  -- ✓ Load once at startup!

-- ─────────────────────────────────────────────
-- Configuration
-- ─────────────────────────────────────────────
local LOBBY_PLACE_ID    = 129064040936910
local TOTAL_WAVES       = 5
local WAVE_DELAY        = 10
local ENDLESS_MODE      = false
local PRE_GAME_DELAY    = 15   -- seconds of countdown before first wave

-- ─────────────────────────────────────────────
-- Remotes
-- ─────────────────────────────────────────────
local remotes               = ReplicatedStorage:WaitForChild("GameRemotes")
local updateHUDEvent        = remotes:WaitForChild("UpdateHUD")
local gameOverEvent         = remotes:WaitForChild("GameOver")
local returnLobbyEvent      = remotes:WaitForChild("ReturnToLobby")
local restartGameEvent      = remotes:WaitForChild("RestartGame")
local gameReadyEvent        = remotes:WaitForChild("GameReady")
local preGameCountdownEvent = remotes:WaitForChild("PreGameCountdown")

-- ─────────────────────────────────────────────
-- Session storage
-- ─────────────────────────────────────────────
local sessions = {}

-- ─────────────────────────────────────────────
-- Wait for MapLoader to finish cloning the map
-- ─────────────────────────────────────────────
local function waitForMap(timeoutSec)
	timeoutSec = timeoutSec or 30
	local elapsed = 0
	while elapsed < timeoutSec do
		local map = workspace:FindFirstChild("LoadedMap")
		if map then return map end
		task.wait(0.5)
		elapsed += 0.5
	end
	warn("waitForMap: timed out after", timeoutSec, "seconds")
	return nil
end

-- ─────────────────────────────────────────────
-- Get all four spawn points from the loaded map
-- ─────────────────────────────────────────────
local function getSpawnPoints()
	local map = workspace:FindFirstChild("LoadedMap")
	local root = map or workspace

	local troopSpawn = root:FindFirstChild("TroopSpawn", true)
	local enemySpawn = root:FindFirstChild("EnemySpawn", true)
	local troopGoal  = root:FindFirstChild("TroopGoal",  true)
	local enemyGoal  = root:FindFirstChild("EnemyGoal",  true)

	if not troopSpawn then warn("⚠ TroopSpawn missing") end
	if not enemySpawn then warn("⚠ EnemySpawn missing") end
	if not troopGoal  then warn("⚠ TroopGoal missing")  end
	if not enemyGoal  then warn("⚠ EnemyGoal missing")  end

	return troopSpawn, enemySpawn, troopGoal, enemyGoal
end

-- ─────────────────────────────────────────────
-- Find player spawn CFrame
-- ─────────────────────────────────────────────
local function getPlayerSpawnCFrame()
	local map = workspace:FindFirstChild("LoadedMap")
	if map then
		local part = map:FindFirstChild("PlayerSpawn", true)
		if part and part:IsA("BasePart") then
			return part.CFrame + Vector3.new(0, 5, 0)
		end
	end
	local spawnLoc = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLoc then
		return spawnLoc.CFrame + Vector3.new(0, 5, 0)
	end
	local troopSpawn = workspace:FindFirstChild("TroopSpawn", true)
	if troopSpawn then
		return troopSpawn.CFrame + Vector3.new(0, 5, 0)
	end
	return CFrame.new(0, 10, 0)
end

-- ─────────────────────────────────────────────
-- Move a player's character to a CFrame
-- ─────────────────────────────────────────────
local function spawnPlayerAt(player, targetCFrame)
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local root = char:FindFirstChild("HumanoidRootPart")
			or char:WaitForChild("HumanoidRootPart", 5)
		if not root then
			warn("spawnPlayerAt: no HumanoidRootPart for", player.Name)
			return
		end
		char:PivotTo(targetCFrame)
		task.wait(0.15)
		char:PivotTo(targetCFrame)
		print("✓ Spawned", player.Name, "at", math.round(targetCFrame.Position.X), math.round(targetCFrame.Position.Y), math.round(targetCFrame.Position.Z))
	end)
end

-- ─────────────────────────────────────────────
-- Remove all troop/enemy models from workspace
-- ─────────────────────────────────────────────
local function cleanupAllUnits()
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Model") then
			local team = obj:GetAttribute("Team")
			if team == "Troop" or team == "Enemy" then
				obj:Destroy()
			end
		end
	end
end

-- ─────────────────────────────────────────────
-- Award in-session cash and update client HUD
-- ✓ FIXED: Now properly fires UpdateCash event
-- ─────────────────────────────────────────────
local function awardCash(player, amount)
	local session = sessions[player]
	if not session then return end
	session.cash = (session.cash or 0) + amount

	-- ✓ FIXED: Fire the UpdateCash event so client actually sees it
	updateHUDEvent:FireClient(player, "UpdateCash", { Cash = session.cash })
	print("💰 Awarded", amount, "cash to", player.Name, "| Total:", session.cash)
end

-- ─────────────────────────────────────────────
-- End game — show win/lose screen with drops
-- ─────────────────────────────────────────────
local function endGame(player, won)
	local session = sessions[player]
	if not session or not session.active then return end
	session.active = false

	print("═══════════════════════════════════════════")
	print(won and "🏆 GAME WON!" or "💀 GAME LOST!")
	print("═══════════════════════════════════════════")
	print(player.Name, "| Cash:", session.cash, "| Kills:", session.kills)

	cleanupAllUnits()

	-- Process drops if won
	local droppedTroops = {}
	if won and session.enemiesKilled and #session.enemiesKilled > 0 then
		print("🎁 Processing drops from", #session.enemiesKilled, "enemies killed...")
		local DropSystem = require(ServerScriptService:WaitForChild("DropSystem"))
		droppedTroops = DropSystem.ProcessWaveDrops(session.enemiesKilled, session.currentWave)

		if #droppedTroops > 0 then
			print("✓ Drops calculated:", DropSystem.FormatDrops(droppedTroops))
		else
			print("ℹ No drops this match")
		end
	else
		if not won then
			print("ℹ No drops (game was lost)")
		elseif not session.enemiesKilled then
			warn("⚠ No enemiesKilled data!")
		else
			print("ℹ No enemies killed")
		end
	end

	-- ✓ STORE drops in session so ReturnToLobby can use them
	session.droppedTroops = droppedTroops
	session.won = won

	print("📊 Stored in session:")
	print("  droppedTroops:", #session.droppedTroops, "items")
	print("  won:", session.won)
	print("═══════════════════════════════════════════")

	gameOverEvent:FireClient(player, won, {
		CashEarned  = session.cash  or 0,
		TotalKills  = session.kills or 0,
		WaveReached = session.currentWave or 1,
		TotalWaves  = ENDLESS_MODE and session.currentWave or TOTAL_WAVES,
		NewTroops   = droppedTroops,
	})
end

-- ─────────────────────────────────────────────
-- Pre-game countdown (fires each second to client)
-- ─────────────────────────────────────────────
local function runPreGameCountdown(player, session)
	print("⏱ Pre-game countdown:", PRE_GAME_DELAY, "seconds")
	for i = PRE_GAME_DELAY, 1, -1 do
		if not session.active then return false end
		preGameCountdownEvent:FireClient(player, i)
		task.wait(1)
	end
	if not session.active then return false end
	preGameCountdownEvent:FireClient(player, 0)  -- tells client to show "GO!" and hide
	task.wait(0.8)
	return true
end

-- ─────────────────────────────────────────────
-- MAIN GAME LOOP
-- ─────────────────────────────────────────────
local function runGame(player, difficulty, loadout)
	local session = sessions[player]
	if not session then return end

	-- 1. Wait for map ─────────────────────────
	print("⏳ Waiting for map…")
	local map = waitForMap(30)
	if not map then
		warn("Map never loaded for", player.Name, "— aborting")
		return
	end
	print("✓ Map ready:", map.Name)

	-- 2. Get spawn points ─────────────────────
	local troopSpawn, enemySpawn, troopGoal, enemyGoal = getSpawnPoints()
	if not troopSpawn or not enemySpawn or not troopGoal or not enemyGoal then
		warn("Missing spawn points — aborting for", player.Name)
		return
	end

	-- 3. Move player to their spawn ───────────
	local spawnCF = getPlayerSpawnCFrame()
	spawnPlayerAt(player, spawnCF)

	-- 4. Set up managers ──────────────────────
	-- ✓ CORRECT: Troops walk to TroopGoal (enemy territory)
	--            Enemies walk to EnemyGoal (troop territory)
	TroopManager:Initialize(troopSpawn, troopGoal, player)
	EnemyManager:Initialize(enemySpawn, enemyGoal)

	-- 5. Send initial HUD data ────────────────
	-- Wave counter will slide down AFTER countdown ends
	updateHUDEvent:FireClient(player, "Initialize", {
		Loadout  = loadout,
		Wave     = 1,
		MaxWaves = TOTAL_WAVES,
		Cash     = 0,
	})

	-- 6. Spawn troops from loadout ─────────────
	if loadout then
		for slotNum, troopInfo in pairs(loadout) do
			if troopInfo and troopInfo.TroopType then
				TroopManager:SpawnTroop(
					troopInfo.TroopType,
					troopInfo.Rarity or "Common",
					slotNum
				)
			end
		end
	else
		warn("⚠ No loadout data — using default")
		TroopManager:SpawnTroop("Zombie", "Common", 1)
	end

	-- 7. Signal client: loading done ──────────
	task.wait(0.5)
	gameReadyEvent:FireClient(player)
	print("✓ GameReady fired to", player.Name)

	-- 8. Troop respawn update loop ─────────────
	task.spawn(function()
		while session.active do
			TroopManager:Update()
			task.wait(0.5)
		end
	end)

	-- 9. Pre-game countdown (15s) ──────────────
	local started = runPreGameCountdown(player, session)
	if not started then return end

	-- 10. Wave loop ────────────────────────────
	local waveNumber = 1
	while session.active do
		if not ENDLESS_MODE and waveNumber > TOTAL_WAVES then break end

		session.currentWave = waveNumber

		-- ✓ FIXED: Fire UpdateWave so wave counter shows and updates
		updateHUDEvent:FireClient(player, "UpdateWave", {
			CurrentWave = waveNumber,
			MaxWaves    = ENDLESS_MODE and "∞" or TOTAL_WAVES,
		})

		print("═══════════════════════")
		print("Wave", waveNumber, "|", difficulty)
		print("═══════════════════════")

		-- Spawn wave with cash reward callback
		EnemyManager:SpawnWave(waveNumber, difficulty, function(cashReward, enemyType, rarity)
			awardCash(player, cashReward)
			session.kills = (session.kills or 0) + 1

			-- Track enemy for drops
			table.insert(session.enemiesKilled, {
				EnemyType = enemyType,
				Rarity = rarity
			})
		end)

		-- Wait for wave to clear (max 2 min)
		local elapsed = 0
		while EnemyManager:GetActiveCount() > 0 and elapsed < 120 do
			if not session.active then return end
			task.wait(1)
			elapsed += 1
		end
		if not session.active then return end

		print("✓ Wave", waveNumber, "cleared!")

		-- Process drops for this wave
		-- (We'll calculate drops and show them in the win screen)

		if not ENDLESS_MODE and waveNumber >= TOTAL_WAVES then
			endGame(player, true)
			return
		end

		print("Next wave in", WAVE_DELAY, "s…")
		task.wait(WAVE_DELAY)
		waveNumber += 1
	end

	if session.active and not ENDLESS_MODE then
		endGame(player, true)
	end
end

-- ─────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────
local GameController = {}

function GameController:StartGame(player, difficulty, loadout)
	if sessions[player] then
		sessions[player].active = false
		cleanupAllUnits()
		task.wait(0.5)
	end

	sessions[player] = {
		difficulty  = difficulty,
		loadout     = loadout,
		cash        = 0,
		kills       = 0,
		currentWave = 1,
		active      = true,
		enemiesKilled = {},  -- Track killed enemies for drops
	}

	print("🎮 Starting game for", player.Name, "| Difficulty:", difficulty)
	task.spawn(runGame, player, difficulty, loadout)
end

-- ─────────────────────────────────────────────
-- Return to Lobby (✓ FIXED: Now includes drops + DEBUG LOGGING + RewardCache)
-- ─────────────────────────────────────────────
returnLobbyEvent.OnServerEvent:Connect(function(player)
	print("═══════════════════════════════════════════")
	print("🏠 RETURN TO LOBBY - " .. player.Name)
	print("═══════════════════════════════════════════")

	local session = sessions[player]
	if session then 
		print("📊 Session found:")
		print("  Cash:", session.cash or 0)
		print("  Kills:", session.kills or 0)
		print("  Wave:", session.currentWave or 0)
		print("  Won:", session.won or false)
		print("  Drops:", session.droppedTroops and #session.droppedTroops or 0)

		session.active = false 
	else
		warn("⚠ No session found for " .. player.Name)
	end

	cleanupAllUnits()

	local rewardData = {
		Currency  = session and session.cash or 0,
		NewTroops = session and session.droppedTroops or {},
		Stats     = { 
			Kills       = session and session.kills or 0, 
			Won         = session and session.won or false,
			HighestWave = session and session.currentWave or 1,
		},
	}

	print("📦 Teleporting with rewards:")
	print("  Currency:", rewardData.Currency)
	print("  NewTroops:", #rewardData.NewTroops, "items")
	print("  Stats.Won:", rewardData.Stats.Won)
	print("  Stats.Kills:", rewardData.Stats.Kills)

	-- ✓ STORE in DataStore for UNLIMITED TIME (persists forever!)
	DataManager:SavePendingRewards(player.UserId, rewardData)

	print("═══════════════════════════════════════════")

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ Rewards = rewardData })

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(LOBBY_PLACE_ID, {player}, options)
	end)
	if not ok then warn("ReturnToLobby failed:", err) end
end)

-- ─────────────────────────────────────────────
-- Restart Game
-- ─────────────────────────────────────────────
restartGameEvent.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if session then
		GameController:StartGame(player, session.difficulty, session.loadout)
	end
end)

-- ─────────────────────────────────────────────
-- Cleanup on leave (✓ AUTO-SAVE REWARDS FOR ENDLESS MODE)
-- ─────────────────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
	local session = sessions[player]

	-- If player has an active session, save their rewards before they leave
	if session and session.active then
		print("═══════════════════════════════════════════")
		print("💾 AUTO-SAVE: " .. player.Name .. " is leaving")
		print("═══════════════════════════════════════════")

		-- Process any drops from enemies killed so far
		local droppedTroops = {}
		if session.enemiesKilled and #session.enemiesKilled > 0 then
			print("🎁 Processing drops from", #session.enemiesKilled, "enemies killed...")
			local DropSystem = require(ServerScriptService:WaitForChild("DropSystem"))
			droppedTroops = DropSystem.ProcessWaveDrops(session.enemiesKilled, session.currentWave or 1)

			if #droppedTroops > 0 then
				print("✓ Drops calculated:", DropSystem.FormatDrops(droppedTroops))
			end
		end

		local rewardData = {
			Currency  = session.cash or 0,
			NewTroops = droppedTroops,
			Stats     = { 
				Kills       = session.kills or 0, 
				Won         = false,  -- They left mid-game, not a full win
				HighestWave = session.currentWave or 1,
			},
		}

		print("📦 Auto-saving rewards:")
		print("  Currency:", rewardData.Currency)
		print("  NewTroops:", #rewardData.NewTroops, "items")
		print("  HighestWave:", rewardData.Stats.HighestWave)

		-- ✓ STORE in DataStore for UNLIMITED TIME (not just 5 minutes!)
		DataManager:SavePendingRewards(player.UserId, rewardData)

		print("✅ Rewards auto-saved! Will be applied when player rejoins lobby (UNLIMITED TIME)")
		print("═══════════════════════════════════════════")

		session.active = false
	end

	sessions[player] = nil
end)

print("GameController (ModuleScript) loaded ✓")
return GameController