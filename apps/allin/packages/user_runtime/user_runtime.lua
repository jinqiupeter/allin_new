local string_split       = string.split

local json = cc.import("#json")
local gbc = cc.import("#gbc")

local Game_Runtime = cc.import("#game_runtime")
local User_Runtime = cc.class("User_Runtime")

local _USER_JOINED_GAMES        = "_USER_JOINED_GAMES_"
local _USER_RESPITE_        = "_USER_RESPITE_"

function User_Runtime:ctor(instance)
    self._instance  = instance
    self._redis     = instance:getRedis()
    self._game_runtime = Game_Runtime:new(self._instance)
end

function User_Runtime:joinGame(game_id)
    self._redis:sadd(_USER_JOINED_GAMES .. self._instance:getCid(), game_id)
    self._game_runtime:addPlayer(game_id, self._instance:getCid())
end

function User_Runtime:leaveGame(game_id)
    self._redis:srem(_USER_JOINED_GAMES .. self._instance:getCid(), game_id)
    self._game_runtime:removePlayer(game_id, self._instance:getCid())
end

function User_Runtime:leaveAllGames()
    local games = self:getJoinedGames()
    for key, value in pairs(games) do
        cc.printdebug("removing user %s from game %s", self._instance:getCid(), value)
        self._redis:srem(_USER_JOINED_GAMES .. self._instance:getCid(), value)
        self._game_runtime:removePlayer(value, self._instance:getCid())
    end
end

function User_Runtime:getJoinedGames()
    return self._redis:smembers(_USER_JOINED_GAMES .. self._instance:getCid())
end

function User_Runtime:getJoinedGamesCount()
    return self._redis:scard(_USER_JOINED_GAMES .. self._instance:getCid())
end

function User_Runtime:setRespiteCount(game_id, count)
    self._redis:hset(_USER_RESPITE_ .. self._instance:getCid(), ""..game_id, count)
end

function User_Runtime:getRespiteCount(game_id)
    return self._redis:hget(_USER_RESPITE_ .. self._instance:getCid(), ""..game_id) or 0
end
return User_Runtime
