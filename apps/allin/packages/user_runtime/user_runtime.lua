local string_split       = string.split

local json = cc.import("#json")
local gbc = cc.import("#gbc")

local Game_Runtime = cc.import("#game_runtime")
local User_Runtime = cc.class("User_Runtime")

local _USER_JOINED_GAMES        = "_USER_JOINED_GAMES_"

function User_Runtime:ctor(instance)
    self._instance  = instance
    self._redis     = instance:getRedis()
    self._game_runtime = Game_Runtime:new(instance)
end

function User_Runtime:joinGame(game_id)
    self._redis:initPipeline()
    cc.printdebug("Adddddddding user %s to game %s", self._instance:getCid(), game_id)
    self._redis:sadd(_USER_JOINED_GAMES .. self._instance:getCid(), game_id)
    self._redis:commitPipeline()
    self._game_runtime:addPlayer(game_id, self._instance:getCid())
end

function User_Runtime:leaveGame(game_id)
    self._redis:initPipeline()
    self._redis:srem(_USER_JOINED_GAMES .. self._instance:getCid(), game_id)
    self._redis:commitPipeline()
    self._game_runtime:removePlayer(game_id, self._instance:getCid())
end

function User_Runtime:leaveAllGames()
    local games = self:getJoinedGames()
    self._redis:initPipeline()
    for key, value in pairs(games) do
        cc.printdebug("removing user %s from game %s", self._instance:getCid(), value)
        self._redis:srem(_USER_JOINED_GAMES .. self._instance:getCid(), value)
        self._game_runtime:removePlayer(value, self._instance:getCid())
    end
    return self._redis:commitPipeline()
end

function User_Runtime:getJoinedGames()
    return self._redis:smembers(_USER_JOINED_GAMES .. self._instance:getCid())
end

function User_Runtime:getJoinedGamesCount()
    return self._redis:scard(_USER_JOINED_GAMES .. self._instance:getCid())
end

return User_Runtime
