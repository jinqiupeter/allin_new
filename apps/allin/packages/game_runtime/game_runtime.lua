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

function Game_Runtime:ctor(instance, redis)
    self._instance  = instance
    self._redis     = redis
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

function Game_Runtime:addPlayer(game_id, user_id)
    local res, err = self._redis:sadd(_GAME_RUNTIME_SET .. game_id, user_id)
    if not res then
        cc.throw("failed to add player %s to game %s: %s", user_id, game_id, err)
    end
    return res
end

function Game_Runtime:removePlayer(game_id, user_id)
    local res, err = self._redis:srem(_GAME_RUNTIME_SET .. game_id, user_id)
    if not res then
        cc.throw("failed to remove player %s from game %s: %s", user_id, game_id, err)
    end
    return res
end

function Game_Runtime:getPlayers(game_id)
    local res, err =  self._redis:smembers(_GAME_RUNTIME_SET .. game_id)
    if not res then
        cc.throw("failed to get players for game %s: %s", game_id, err)
    end
    return res
end

function Game_Runtime:getPlayerCount(game_id)
    return self._redis:scard(_GAME_RUNTIME_SET .. game_id) or 0
end

function Game_Runtime:isPlayer(game_id, player_id)
    return self._redis:sismember(_GAME_RUNTIME_SET .. game_id, player_id) or 0
end

function Game_Runtime:setGameInfo(game_id, field, value)
    local redis = self._redis
    return redis:hset(_GAME_RUNTIME_INFO .. game_id, field, ""..value) or nil
end

function Game_Runtime:getGameInfo(game_id, field)
    local redis = self._redis
    local result, err = redis:hget(_GAME_RUNTIME_INFO .. game_id, field)

    if not result then
        cc.printdebug("Error: redis hget error: %s", err)
        return nil, err
    end
    if result == redis.null then
        cc.printdebug("Error: redis hget %s null ", field)
        return nil, string_format(field .. " not found in hash %s", _GAME_RUNTIME_INFO .. game_id)
    end

    return result
end


function Game_Runtime:deleteInfo(game_id)
    local redis = self._redis
    return redis:del(_GAME_RUNTIME_INFO .. game_id)
end

return Game_Runtime
