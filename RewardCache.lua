-- RewardCache.lua
-- ModuleScript - ReplicatedStorage - BOTH places
-- Temporary cache for rewards (for Studio testing where TeleportData doesn't work)

local RewardCache = {}
local cache = {}

-- Store rewards for a player (called in Gameplay place before teleport)
function RewardCache:Store(userId, rewardData)
	cache[userId] = {
		Data = rewardData,
		Timestamp = os.time()
	}
	print("💾 RewardCache: Stored rewards for userId " .. userId)
	print("  Currency:", rewardData.Currency or 0)
	print("  NewTroops:", rewardData.NewTroops and #rewardData.NewTroops or 0)
end

-- Retrieve and clear rewards for a player (called in Lobby place after teleport)
function RewardCache:Retrieve(userId)
	local cached = cache[userId]
	if cached then
		-- Clear cache after retrieval
		cache[userId] = nil

		-- Check if data is too old (more than 5 minutes for endless mode)
		if os.time() - cached.Timestamp > 300 then
			warn("⚠ RewardCache: Data for userId " .. userId .. " is stale (over 5 min old)")
			return nil
		end

		print("✓ RewardCache: Retrieved rewards for userId " .. userId)
		return cached.Data
	end
	return nil
end

-- Check if player has cached rewards
function RewardCache:Has(userId)
	return cache[userId] ~= nil
end

-- Clear all old entries (cleanup)
function RewardCache:Cleanup()
	local now = os.time()
	local removed = 0

	for userId, cached in pairs(cache) do
		if now - cached.Timestamp > 300 then  -- 5 minutes
			cache[userId] = nil
			removed = removed + 1
		end
	end

	if removed > 0 then
		print("🧹 RewardCache: Cleaned up " .. removed .. " stale entries")
	end
end

return RewardCache