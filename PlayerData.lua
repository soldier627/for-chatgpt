-- PlayerData.lua
-- ModuleScript - ServerScriptService - BOTH Lobby AND Gameplay places
-- Defines player data structure with new 14-tier rarity system

local PlayerData = {}

-- ═════════════════════════════════════════════════════════════════════
-- Default data template for new players
-- ═════════════════════════════════════════════════════════════════════
PlayerData.Template = {
	-- Owned troops: { [TroopType] = { [Rarity] = quantity } }
	OwnedTroops = {
		["Zombie"] = {
			["Common"] = 1      -- Start with 1 common zombie
		},
		["FastZombie"] = {
			["Common"] = 1      -- Start with 1 common fast zombie
		}
	},

	-- Equipped loadout: { [slotNumber] = { TroopType, Rarity } }
	EquippedLoadout = {
		[1] = { TroopType = "Zombie", Rarity = "Common" },
		[2] = { TroopType = "FastZombie", Rarity = "Common" }
	},

	-- Progression
	UnlockedSlots = 5,  -- All 5 slots unlocked by default
	Currency = 0,

	-- Statistics
	Stats = {
		GamesPlayed = 0,
		GamesWon = 0,
		TotalKills = 0,
		HighestWave = 0,
		TotalCashEarned = 0
	},

	-- Settings
	Settings = {
		AutoDeploy = true
	}
}

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Add troops to inventory
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.AddTroop(data, troopType, rarity, amount)
	amount = amount or 1

	-- Initialize structure if it doesn't exist
	if not data.OwnedTroops[troopType] then
		data.OwnedTroops[troopType] = {}
	end
	if not data.OwnedTroops[troopType][rarity] then
		data.OwnedTroops[troopType][rarity] = 0
	end

	-- Add the troops
	data.OwnedTroops[troopType][rarity] = data.OwnedTroops[troopType][rarity] + amount

	return data.OwnedTroops[troopType][rarity]
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Remove troops from inventory
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.RemoveTroop(data, troopType, rarity, amount)
	amount = amount or 1

	if not data.OwnedTroops[troopType] or not data.OwnedTroops[troopType][rarity] then
		warn("Player doesn't own any", rarity, troopType)
		return false
	end

	if data.OwnedTroops[troopType][rarity] < amount then
		warn("Not enough troops to remove:", data.OwnedTroops[troopType][rarity], "available but trying to remove", amount)
		return false
	end

	data.OwnedTroops[troopType][rarity] = data.OwnedTroops[troopType][rarity] - amount
	return true
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Get troop count
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.GetTroopCount(data, troopType, rarity)
	if not data.OwnedTroops[troopType] or not data.OwnedTroops[troopType][rarity] then
		return 0
	end
	return data.OwnedTroops[troopType][rarity]
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Check if player owns a troop
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.OwnsTroop(data, troopType, rarity)
	return PlayerData.GetTroopCount(data, troopType, rarity) > 0
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Equip a troop to a slot
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.EquipTroop(data, slotNumber, troopType, rarity)
	-- Check if slot is unlocked
	if slotNumber > data.UnlockedSlots then
		warn("Slot", slotNumber, "is not unlocked!")
		return false
	end

	-- Check if player owns this troop
	if not PlayerData.OwnsTroop(data, troopType, rarity) then
		warn("Player doesn't own", rarity, troopType)
		return false
	end

	-- Equip it
	data.EquippedLoadout[slotNumber] = {
		TroopType = troopType,
		Rarity = rarity
	}

	return true
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Unequip a troop from a slot
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.UnequipTroop(data, slotNumber)
	-- Check if slot is unlocked
	if slotNumber > data.UnlockedSlots then
		warn("Slot", slotNumber, "is not unlocked!")
		return false
	end

	-- Clear the slot
	data.EquippedLoadout[slotNumber] = nil
	return true
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Get total troops owned (for inventory UI)
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.GetTotalTroopsOwned(data)
	local total = 0
	for troopType, rarities in pairs(data.OwnedTroops) do
		for rarity, count in pairs(rarities) do
			total = total + count
		end
	end
	return total
end

-- ═════════════════════════════════════════════════════════════════════
-- Helper: Get a deep copy of default template for new players
-- ═════════════════════════════════════════════════════════════════════
function PlayerData.GetDefault()
	-- Deep copy the template to avoid reference issues
	local function deepCopy(original)
		local copy = {}
		for key, value in pairs(original) do
			if type(value) == "table" then
				copy[key] = deepCopy(value)
			else
				copy[key] = value
			end
		end
		return copy
	end

	return deepCopy(PlayerData.Template)
end

return PlayerData