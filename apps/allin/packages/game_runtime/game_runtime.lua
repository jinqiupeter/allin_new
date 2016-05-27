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

function Game_Runtime:setGameInfo(game_id, field, value)
    local redis = self._redis
    redis:initPipeline()
    redis:hset(_GAME_RUNTIME_INFO .. game_id, field, value)
    return redis:commitPipeline()
end

function Game_Runtime:getGameInfo(game_id, field)
    local redis = self._redis
    local result, err = redis:hget(_GAME_RUNTIME_INFO .. game_id, field)

    if not result then
        return nil, err
    end
    if result == redis.null then
        return nil, string_format(field .. " not found in hash %s", _GAME_RUNTIME_INFO .. game_id)
    end

    return result
end


function Game_Runtime:deleteInfo(game_id)
    local redis = self._redis
    redis:initPipeline()
    redis:del(_GAME_RUNTIME_INFO .. game_id)
    return redis:commitPipeline()
end

return Game_Runtime
