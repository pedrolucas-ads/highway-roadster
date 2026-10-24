-- HIGHWAY ROADSTER · Servidor
-- Onde colar: ServerScriptService > Script (nome: HighwayServer)
-- Faz: ranking global (OrderedDataStore), recorde pessoal no placar (leaderstats)
-- e cria os RemoteFunctions que o cliente usa.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOARD_NAME = "HighwayRoadster_Best_v1"
local MAX_SCORE_PER_SECOND = 6000 -- trava anti-trapaça simples (pontuação impossível é ignorada)

local board
do
	local ok, ds = pcall(function()
		return DataStoreService:GetOrderedDataStore(BOARD_NAME)
	end)
	if ok then
		board = ds
	else
		warn("[Highway] DataStore indisponível (ative 'Enable Studio Access to API Services'):", ds)
	end
end

local remotes = Instance.new("Folder")
remotes.Name = "HighwayRemotes"
remotes.Parent = ReplicatedStorage

local submitScore = Instance.new("RemoteFunction")
submitScore.Name = "SubmitScore"
submitScore.Parent = remotes

local getTop = Instance.new("RemoteFunction")
getTop.Name = "GetTop"
getTop.Parent = remotes

local best = {} -- [userId] = melhor pontuação
local lastSubmit = {} -- [userId] = os.clock()
local nameCache = {}

local function getName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		nameCache[userId] = plr.DisplayName
		return plr.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("Player_" .. tostring(userId))
	return nameCache[userId]
end

local topCache, topTime = {}, -math.huge
local function fetchTop(force)
	if not board then
		return {}
	end
	if not force and os.clock() - topTime < 30 then
		return topCache
	end
	local ok, pages = pcall(function()
		return board:GetSortedAsync(false, 100)
	end)
	if not ok then
		warn("[Highway] GetSortedAsync falhou:", pages)
		return topCache
	end
	local list = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(list, { id = tonumber(entry.key), score = entry.value })
	end
	topCache, topTime = list, os.clock()
	return list
end

-- a corrida é controlada pelo HighwayClient: sem analógico/pulo padrão no celular
game:GetService("StarterPlayer").DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable

Players.PlayerAdded:Connect(function(plr)
	plr.DevTouchMovementMode = Enum.DevTouchMovementMode.Scriptable
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = plr
	local bestVal = Instance.new("IntValue")
	bestVal.Name = "Best"
	bestVal.Parent = stats

	if board then
		local ok, value = pcall(function()
			return board:GetAsync(tostring(plr.UserId))
		end)
		if ok and typeof(value) == "number" then
			best[plr.UserId] = value
			bestVal.Value = value
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	best[plr.UserId] = nil
	lastSubmit[plr.UserId] = nil
end)

submitScore.OnServerInvoke = function(plr, score, dist, combo, seconds)
	if typeof(score) ~= "number" or typeof(seconds) ~= "number" or score ~= score then
		return nil
	end
	local now = os.clock()
	if lastSubmit[plr.UserId] and now - lastSubmit[plr.UserId] < 2 then
		return nil
	end
	lastSubmit[plr.UserId] = now

	score = math.max(0, math.floor(score))
	seconds = math.max(1, seconds)
	if score > seconds * MAX_SCORE_PER_SECOND then
		return nil
	end

	local prev = best[plr.UserId] or 0
	local newRecord = score > prev
	if newRecord then
		best[plr.UserId] = score
		local stats = plr:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Best") then
			stats.Best.Value = score
		end
		if board then
			pcall(function()
				board:UpdateAsync(tostring(plr.UserId), function(old)
					old = old or 0
					if score > old then
						return score
					end
					return nil
				end)
			end)
		end
	end

	local list = fetchTop(newRecord)
	local higher = 0
	for _, e in ipairs(list) do
		if e.score > score then
			higher += 1
		end
	end
	local rank, toNext
	if higher < #list or #list < 100 then
		rank = higher + 1
		if rank > 1 and list[rank - 1] then
			toNext = list[rank - 1].score - score + 1
		end
	end

	return {
		best = math.max(prev, score),
		prevBest = prev,
		newRecord = newRecord,
		rank = rank,
		toNext = toNext,
		total = #list,
	}
end

getTop.OnServerInvoke = function(plr)
	local list = fetchTop(false)
	local out = {}
	for i = 1, math.min(10, #list) do
		local e = list[i]
		table.insert(out, { name = getName(e.id), score = e.score, me = e.id == plr.UserId })
	end
	return out
end
