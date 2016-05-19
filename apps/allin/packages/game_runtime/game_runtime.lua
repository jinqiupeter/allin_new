local string_format = string.format

local json = cc.import("#json")
local gbc = cc.import("#gbc")

local Game_Runtime = cc.class("Game_Runtime")

local _GAME_RUNTIME_SET        = "_GAME_RUNTIME_PLAYERS_"
local _GAME_RUNTIME_CHANNEL    = "_GAME_RUNTIME_CHANNEL"
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

return Game_Runtime
