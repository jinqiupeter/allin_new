local string_format = string.format

local json = cc.import("#json")
local gbc = cc.import("#gbc")

local Game_Runtime = cc.class("Game_Runtime")

local _GAME_RUNTIME_SET        = "_GAME_RUNTIME_PLAYERS_"
local _GAME_RUNTIME_INFO    = "_GAME_RUNTIME_INFO_"
local _EVENT = table.readonly({
    ADD_PLAYER    = "ADD_PLAYER",
    REMOVE_PLAYER = "REMOVE_PLAYER",
})

function Game_Runtime:ctor(instance)
    self._instance  = instance
    self._redis     = instance:getRedis()
end

function Game_Runtime:setPlayers(game_id, players)
    if type(players) ~= "table" then
        cc.throw("players must be table of player id")
        return
    end

    self._redis:initPipeline()
    self._redis:del(_GAME_RUNTIME_SET .. game_id) -- empty the set before adding members
    for key, value in pairs(players) do
        self._redis:sadd(_GAME_RUNTIME_SET .. game_id, value)
    end
    return self._redis:commitPipeline()
end

function Game_Runtime:getPlayers(game_id)
    return self._redis:smembers(_GAME_RUNTIME_SET .. game_id)
end

function Game_Runtime:getPlayerCount(game_id)
    return self._redis:scard(_GAME_RUNTIME_SET .. game_id)
end

function Game_Runtime:isPlayer(game_id, player_id)
    return self._redis:sismember(_GAME_RUNTIME_SET .. game_id, player_id)
end

function Game_Runtime:setStartedAt(game_id, started_at)
    local redis = self._redis
    redis:initPipeline()
    redis:hset(_GAME_RUNTIME_INFO .. game_id, "started_at", started_at)
    return redis:commitPipeline()
end

function Game_Runtime:getStartedAt(game_id)
    local redis = self._redis
    local started_at, err = redis:hget(_GAME_RUNTIME_INFO .. game_id, "started_at")

    if not started_at then
        return nil, err
    end
    if started_at == redis.null then
        return nil, string_format("started_at not found in hash %s", _GAME_RUNTIME_INFO .. game_id)
    end

    return started_at
end

function Game_Runtime:setBlindAmount(game_id, blind_amount)
    local redis = self._redis
    redis:initPipeline()
    redis:hset(_GAME_RUNTIME_INFO .. game_id, "blind_amount", blind_amount)
    return redis:commitPipeline()
end

function Game_Runtime:getBlindAmount(game_id)
    local redis = self._redis
    local blind_amount, err = redis:hget(_GAME_RUNTIME_INFO .. game_id, "blind_amount")

    if not blind_amount then
        return nil, err
    end
    if blind_amount == redis.null then
        return nil, string_format("blind_amount not found in hash %s", _GAME_RUNTIME_INFO .. game_id)
    end

    return blind_amount
end

function Game_Runtime:setGameState(game_id, game_state)
    local redis = self._redis
    redis:initPipeline()
    redis:hset(_GAME_RUNTIME_INFO .. game_id, "game_state", game_state)
    return redis:commitPipeline()
end

function Game_Runtime:getGameState(game_id)
    local redis = self._redis
    local game_state, err = redis:hget(_GAME_RUNTIME_INFO .. game_id, "game_state")

    if not game_state then
        return nil, err
    end
    if game_state == redis.null then
        return nil, string_format("game_state not found in hash %s", _GAME_RUNTIME_INFO .. game_id)
    end

    return game_state
end

function Game_Runtime:deleteInfo(game_id)
    local redis = self._redis
    redis:initPipeline()
    redis:del(_GAME_RUNTIME_INFO .. game_id)
    return redis:commitPipeline()
end

return Game_Runtime
