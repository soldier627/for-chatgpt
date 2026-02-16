-- InventoryHandler_V3.lua
-- ServerScript - ServerScriptService - LOBBY place
-- ✓ FIXED: Now auto-sends inventory data when player loads in

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataManager = require(ServerScriptService:WaitForChild("DataManager"))

-- Wait for remotes folder
local remotes = ReplicatedStorage:WaitForChild("GameRemotes", 10)
if not remotes then
	warn("GameRemotes not found!")
	return
end

-- Get or create RemoteEvents
local function getOrCreate(name)
	local e = remotes:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = remotes
	end
	return e
end

local requestInventoryEvent = getOrCreate("RequestInventoryData")
local equipTroopEvent       = getOrCreate("EquipTroop")
local unequipTroopEvent     = getOrCreate("UnequipTroop")

-- ─────────────────────────────────────────────
-- Helper: Send inventory data to client
-- ─────────────────────────────────────────────
local function sendInventoryData(player)
	local data = DataManager:GetData(player)
	if data then
		print("📦 Sending inventory data to " .. player.Name)
		print("  OwnedTroops:", data.OwnedTroops and "✓" or "✗")
		print("  EquippedLoadout:", data.EquippedLoadout and "✓" or "✗")

		requestInventoryEvent:FireClient(player, {
			OwnedTroops     = data.OwnedTroops or {},
			EquippedLoadout = data.EquippedLoadout or {},
			UnlockedSlots   = data.UnlockedSlots or 5,
			Currency        = data.Currency or 0
		})
		return true
	else
		warn("❌ No data available for", player.Name)
		return false
	end
end

-- ─────────────────────────────────────────────
-- Auto-send inventory when player joins
-- ─────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	-- Wait for data to load
	task.spawn(function()
		local attempts = 0
		local maxAttempts = 50

		while attempts < maxAttempts do
			local data = DataManager:GetData(player)
			if data then
				print("✓ Data loaded for " .. player.Name .. " (attempt " .. attempts .. ")")
				task.wait(0.5)  -- Small delay to ensure GUI loads
				sendInventoryData(player)
				break
			end

			attempts = attempts + 1
			task.wait(0.1)
		end

		if attempts >= maxAttempts then
			warn("⚠ Failed to load data for " .. player.Name .. " after " .. maxAttempts .. " attempts")
		end
	end)
end)

-- ─────────────────────────────────────────────
-- Request inventory data (manual refresh)
-- ─────────────────────────────────────────────
requestInventoryEvent.OnServerEvent:Connect(function(player)
	print("🔄 " .. player.Name .. " requested inventory refresh")
	sendInventoryData(player)
end)

-- ─────────────────────────────────────────────
-- Equip a troop to a hotbar slot
-- ─────────────────────────────────────────────
equipTroopEvent.OnServerEvent:Connect(function(player, slotNumber, troopType, rarity)
	-- Validate slot number
	if type(slotNumber) ~= "number" or slotNumber < 1 or slotNumber > 5 then
		warn("Invalid slot number:", slotNumber)
		equipTroopEvent:FireClient(player, false)
		return
	end

	local success = DataManager:EquipTroop(player, slotNumber, troopType, rarity)
	if success then
		print("✓", player.Name, "equipped", rarity, troopType, "to slot", slotNumber)
		equipTroopEvent:FireClient(player, true, slotNumber, troopType, rarity)
	else
		warn("❌ Failed to equip for", player.Name)
		equipTroopEvent:FireClient(player, false)
	end
end)

-- ─────────────────────────────────────────────
-- Unequip a troop from a hotbar slot
-- ─────────────────────────────────────────────
unequipTroopEvent.OnServerEvent:Connect(function(player, slotNumber)
	-- Validate slot number
	if type(slotNumber) ~= "number" or slotNumber < 1 or slotNumber > 5 then
		warn("Invalid slot to unequip:", slotNumber)
		unequipTroopEvent:FireClient(player, false)
		return
	end

	local data = DataManager:GetData(player)
	if not data then
		unequipTroopEvent:FireClient(player, false)
		return
	end

	-- Clear the slot
	data.EquippedLoadout[slotNumber] = nil
	print("✓", player.Name, "unequipped slot", slotNumber)

	-- Confirm to client
	unequipTroopEvent:FireClient(player, true, slotNumber)
end)

print("✓ InventoryHandler V3 loaded (auto-sends on join)")