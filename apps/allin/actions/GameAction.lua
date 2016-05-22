local string_split       = string.split
local gbc = cc.import("#gbc")
local GameAction = cc.class("GameAction", gbc.ActionBase)
local WebSocketInstance = cc.import(".WebSocketInstance", "..")
local Constants = cc.import(".Constants", "..")
GameAction.ACCEPTED_REQUEST_TYPE = "websocket"

local Game_Runtime = cc.import("#game_runtime")

-- private
local snap = cc.import(".snap")

local _updateUserGameHistory = function (mysql, args)
    local user_id = args.user_id
    local game_id = args.game_id
    local game_state = args.game_state

    if tonumber(game_state) == Constants.GameState.GameStateWaiting then
        local sql = "INSERT INTO user_game_history (user_id, game_id, joined_at) "
                .. " VALUES (" .. user_id .. ", " 
                .. game_id .. ", " 
                .. " NOW())"
              .. " ON DUPLICATE KEY UPDATE joined_at = NOW()" 

        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.throw("db err: %s", err)
        end
    end
end

local _buyStake = function (required_stake, args)
    local required_stake = tonumber(required_stake)
    local instance = args.instance
    local mysql = args.mysql
    local game_id = args.game_id    -- create record in buying
    local blinds_start = args.blinds_start
    local gold_needed = args.gold_needed

    if not ignore_stake_left then
        -- check if user has already played the game, if yes then take stake left
        local sql = "SELECT stake, updated_at FROM game_stake WHERE "
                 .. " game_id = " .. game_id 
                 .. " AND user_id = " .. instance:getCid()
                 .. " ORDER BY updated_at DESC LIMIT 1"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("db err: %s", err)
            return {status = 1, stake_bought = 0, err = "db err: " .. err}
        end
        if #dbres ~= 0 then
            -- user has played the game
            local stake_left = dbres[1].stake
            if (tonumber(stake_left) > tonumber(blinds_start)) then
                cc.printdebug("stake left is larger than blinds_start, no need to buy")
                return {status = 0, stake_bought = stake_left}
            end
        end
    end

    local sql = "SELECT gold FROM user where id = " .. instance:getCid() 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end
    local gold_available = tonumber(dbres[1].gold)
    if gold_available < gold_needed then
        local err_mes = "user(" .. instance:getCid() .. ") gold needed(" .. gold_needed .. ") is larger than gold available(" .. gold_available .. ")"
        return {status = 1, stake_bought = 0, err = "err: " .. err}
    end

    -- update user.gold
    sql = "UPDATE user SET gold = " .. gold_available - gold_needed .. " WHERE id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end
    
    -- create record in buying
    sql = "INSERT INTO buying (user_id, game_id, gold, stake) "
          .. " VALUES ( " .. instance:getCid() .. ", "
          .. game_id .. ", "
          .. gold_needed .. ", "
          .. required_stake .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end

    return {status = 0, stake_bought = required_stake}
end

local _handlePSERVER, _handleSNAP, _handleGAMEINFO, _handleGAMELIST, _handlePLAYERLIST, _handleCLIENTINFO, _handleERR, _handleMSG, _handleOK

_handlePSERVER = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- // server command PSERVER <version> <client-id> <time>
    -- example: PSERVER 999 1 145148909, 999=server version, 1 = assigned client_id, 145148909=timestamp

    if #parts ~= 4 then
        result.data.state = Constants.Error.AllinError
        result.data.msg = "Invalid PSERVER response: " .. table.concat(parts, " ")
        return result
    end

    result.data.msg = "client version is valid"
    result.data.server_version = parts[2]
    return result
end


_handleGAMELIST = function (parts, args)
    local msgid = args.msgid
    local club_id = args.club_id
    local mysql = args.mysql
    local limit = args.limit
    local offset = args.offset
    local instance = args.instance

    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- tcp format: GAMELIST 1 2 3
    local game_ids = table.subrange(parts, 2, #parts)
    if #game_ids == 0 then
        game_ids[1] = -1
    end

    local game_id_condition = "(" .. table.concat(game_ids, ", ") .. ") "

    local club_id_condition = "(" .. club_id .. ")"
    if club_id == -1 then
        club_id_condition  = "(" .. table.concat(instance:getClubIds(mysql), ", ") .. ")"
    end

    local sql = "SELECT g.id, club_id, g.name, g.owner_id, g.max_players, g.created_at, c.name as club_name, blinds_start, game_mode, u.nickname "
                .. " FROM game g, club c, user u, user_game_history ug"
                .. " WHERE g.deleted != 1 "
                .. " AND g.id IN " .. game_id_condition 
                .. " AND g.id = ug.game_id "
                .. " AND g.club_id = c.id " 
                .. " AND g.owner_id = u.id"
                .. " AND g.club_id IN " .. club_id_condition
                .. " GROUP BY g.id"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("db err: %s", err)
    end

    result.data.msg = #dbres .. " games(s) found"
    result.data.games = dbres
    result.data.offset = offset

    -- check if current user has joined the games found, to support Cash Game and sitout/sitback
    local game_runtime = Game_Runtime:new(instance)
    local index = 1
    while index <= #result.data.games do
        local found_id = result.data.games[index].id 
        
        -- check if I am playing this game
        local is_playing = game_runtime:isPlayer(found_id, instance:getCid())
        result.data.games[index].is_playing = is_playing

        -- get player count
        local player_count = game_runtime:getPlayerCount(found_id)
        cc.printdebug("player count for %s: %s", found_id, player_count)
        result.data.games[index].player_count = player_count

        index = index + 1
    end

    return result
end

_handleGAMEINFO = function (parts, args)
    local msgid = args.msgid
    local instance = args.instance

    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }

    -- server response looks like: GAMEINFO 1 1:3:1:9:5:1:30:1500 20:20:300 "peter's game 1"
    result.data.game_id = parts[2]
    local info = string_split(parts[3], ":")
    result.data.game_type = info[1] -- 1: GameTypeHoldem 
    result.data.game_mode = info[2] -- 1: Cash game, 2: Tournament, 3: SNG
    result.data.game_state = info[3] -- 1: GameStateWaiting, 2: GameStateStarted, 3: GameStateEnded 
    --info[4] is combination of : GameInfoRegistered = 0x01, GameInfoPassword = 0x02, GameInfoRestart = 0x04, GameInfoOwner = 0x08, GameInfoSubscribed  = 0x10,
    result.data.is_player = 0
    if bit.band(0x01 ,tonumber(info[4])) > 0 then 
        result.data.is_player = 1
    end
    result.data.password_protected = 0
    if bit.band(0x02 ,tonumber(info[4])) > 0 then 
        result.data.password_protected = 1
    end
    result.data.auto_restart = 0
    if bit.band(0x04 ,tonumber(info[4])) > 0 then 
        result.data.auto_restart = 1
    end
    result.data.is_owner = 0
    if bit.band(0x08 ,tonumber(info[4])) > 0 then 
        result.data.is_owner = 1
    end
    result.data.is_spectator = 0
    if bit.band(0x10 ,tonumber(info[4])) > 0 then 
        result.data.is_spectator = 1
    end

    result.data.max_players         = info[5]
    result.data.player_count        = info[6]
    result.data.timeout             = info[7]

    result.data.stake               = info[8]
    _updateUserGameHistory(args.mysql, {game_id = result.data.game_id, 
                                        user_id = args.user_id, 
                                        game_state = result.data.game_state
                                        }
                          )

    info = string_split(parts[4], ":")
    result.data.blinds_start        = info[1]
    result.data.blinds_factor       = info[2]
    result.data.blinds_time         = info[3]

    result.data.name                = table.concat(table.subrange(parts, 5, #parts), " ")

    --[[
    -- send new game to all online users of the club
    cc.printdebug("sending new game info to all users in club %s", args.club_id)
    local message = {state_type = "server_push", data = {push_type = "game.newgame"}}
    message.data.name = result.data.name
    message.data.stake = result.data.stake
    message.data.blinds_time = result.data.blinds_time
    message.data.blinds_start = result.data.blinds_start
    message.data.blinds_factor = result.data.blinds_factor
    message.data.timeout = result.data.timeout
    message.data.max_players = result.data.max_players
    message.data.player_count = result.data.player_count
    message.data.password_protected = result.data.password_protected
    message.data.game_type = result.data.game_type
    message.data.game_id = result.data.game_id
    message.data.game_type = result.data.game_type
    message.data.auto_restart = result.data.auto_restart
    message.data.game_mode = result.data.game_mode
    message.data.created_by = args.user_id
    local online = args.instance:getOnline()
    online:sendClubMessage(args.club_id or 0, message)
    --]]

    return result
end

_handlePLAYERLIST = function (parts, args)
    local msgid = args.msgid
    local mysql = args.mysql
    local instance = args.instance
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {state_type = "server_push", data = {push_type = "game.playerlist"}}

    --server response looks like: PLAYERLIST 1 0   
    result.data.game_id = parts[2]

    local player_info = table.subrange(parts, 3, #parts) 
    local player_ids = {}
    local player_seats = {}
    local player_tables = {}
    for key, value in pairs(player_info) do
        local info = string_split(value, ":")
        local player_id = info[1]
        local table_id = info[2]
        local seat_id = info[3]
        table.insert(player_ids, player_id)
        player_tables["" .. player_id] = table_id
        player_seats["" .. player_id] = seat_id
    end

    local info = string_split(parts[2], ":")
    result.data.game_id = info[1] 
    result.data.table_id = info[2]

    -- add players to game runtime set, set is cleared before add
    local game_runtime = Game_Runtime:new(instance)
    game_runtime:setPlayers(result.data.game_id, player_ids)

    local player_id_condition = "(" .. table.concat(player_ids, ", ") .. ") "
    local sql = "SELECT id, nickname, phone FROM user where id in " .. player_id_condition
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.msg = #dbres .. " players(s) found"
    result.data.players = dbres
    local index = 1
    while index <= #result.data.players do
        local id_found = "" .. result.data.players[index].id
        result.data.players[index].table_no = player_tables[id_found]
        result.data.players[index].seat_no = player_seats[id_found]
        index = index + 1
    end

    return result
end

_handleSNAP = function (parts, args)
    return snap:handleSNAP(parts, args)
end

_handleOK = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.OK}
    }
    if parts[3] then
        result.data.game_id = parts[3]
    end

    return result
end

_handleMSG = function (parts, args)
    --MSG 957:1 table You cannot bet, there was already a bet!
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {state_type = "server_push", data = {push_type = "game.message"}}

    local info = string_split(parts[2], ":")
    result.data.game_id = info[1] 
    result.data.table_id = info[2]

    result.data.msg_type = parts[3]
    result.data.msg = "MSG: " .. table.concat(table.subrange(parts, 4, #parts), " ")

    return result
end

_handleERR = function (parts, args)
    local msgid = args.msgid
    if tonumber(parts[1]) ~= nil then
        msgid = parts[1]
        table.remove(parts, 1)
    end

    local result = {__id = msgid, state_type = "action_state", data = {
        action = args.action, state = Constants.Error.AllinError, msg = "ERR: " .. table.concat(table.subrange(parts, 3, #parts), " ")}
    }

    return result
end

local _serverCmdHandler = {
    PSERVER         = _handlePSERVER,
    SNAP            = _handleSNAP,
    GAMEINFO        = _handleGAMEINFO,
    GAMELIST        = _handleGAMELIST,
    PLAYERLIST      = _handlePLAYERLIST,
    CLIENTINFO      = _handleCLIENTINFO,
    OK              = _handleOK,
    MSG             = _handleMSG,
    ERR             = _handleERR
}
GameAction.ServerCmdHandler = _serverCmdHandler

-- public methods
function GameAction:ctor(config)
    GameAction.super.ctor(self, config)
    local allinMsgChannel = WebSocketInstance.EVENT.ALLIN_MESSAGE .. "_" .. self:getInstance():getConnectId()
    self:getInstance():addEventListener(allinMsgChannel, cc.handler(self, self.onAllinMessage))
    self:getInstance():addEventListener(WebSocketInstance.EVENT.DISCONNECT, cc.handler(self, self.onDisconnect))
end

function GameAction:versioncheckAction(args)
    local data = args.data
    local client_version = data.client_version
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }
    if not client_version then
        result.data.msg = "client_version not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --tcp msg format: PCLIENT 5 934a69ec-034a-4ced-81d7-4ba097157096
    local message = msgid .. " PCLIENT " .. client_version .. " " .. self:getInstance():getAllinSession() .. " " ..self:getInstance():getCid() .. "\n" -- '\n' is mandatory
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 
    
    return 
end

function GameAction:creategameAction(args)
    local data = args.data
    local msgid = args.__id

    local result = {state_type = "action_state", data = {
        action = args.action}
    }
    -- user input validity check
    local game_mode = data.game_mode
    local extra = {}
    if not game_mode then
        result.data.msg = "game_mode not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_mode\"")
        return result
    end

    if tonumber(game_mode) == Constants.GameMode.GameModeRingGame then -- 坐下即玩
        extra.duration = data.duration
        if not extra.duration then
            result.data.msg = "duration not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end
    elseif tonumber(game_mode) == Constants.GameMode.GameModeFreezeOut then -- MTT
        -- start at
        extra.start_at =  data.start_at
        if not extra.start_at then
            result.data.msg = "start_at not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- blind factor
        extra.blind_factor = data.blind_factor
        if not extra.blind_factor then
            result.data.msg = "blind_factor not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- blind time
        extra.blind_time = data.blind_time
        if not extra.blind_time then
            result.data.msg = "blind_time not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- is rebuy allowed?
        extra.allow_rebuy = data.allow_rebuy
        if not extra.allow_rebuy then
            result.data.msg = "allow_rebuy not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- how many times of rebuy allowed?
        extra.allow_rebuy_times = data.allow_rebuy_times
        if not extra.allow_rebuy_times then
            result.data.msg = "allow_rebuy_times not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- only allow rebuy before level
        extra.allow_rebuy_before_level = data.allow_rebuy_before_level
        if not extra.allow_rebuy_before_level then
            result.data.msg = "allow_rebuy_before_level not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- ante
        extra.ante = data.ante
        if not extra.ante then
            result.data.msg = "ante not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- maximum winner sharing pool
        extra.winner_pool_max = data.winner_pool_max
        if not extra.winner_pool_max then
            result.data.msg = "winner_pool_max not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- deny register after game's been started for $ seconds
        extra.deny_register_after = data.deny_register_after
        if not extra.deny_register_after then
            result.data.msg = "deny_register_after not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

    elseif tonumber(game_mode) == Constants.GameMode.GameModeSNG then -- SNG
        -- blind factor
        extra.blind_factor = data.blind_factor
        if not extra.blind_factor then
            result.data.msg = "blind_factor not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- blind time
        extra.blind_time = data.blind_time
        if not extra.blind_time then
            result.data.msg = "blind_time not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- is rebuy allowed?
        extra.allow_rebuy = data.allow_rebuy
        if not extra.allow_rebuy then
            result.data.msg = "allow_rebuy not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- how many times of rebuy allowed?
        extra.allow_rebuy_times = data.allow_rebuy_times
        if not extra.allow_rebuy_times then
            result.data.msg = "allow_rebuy_times not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- only allow rebuy before level
        extra.allow_rebuy_before_level = data.allow_rebuy_before_level
        if not extra.allow_rebuy_before_level then
            result.data.msg = "allow_rebuy_before_level not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end

        -- maximum winner sharing pool
        extra.winner_pool_max = data.winner_pool_max
        if not extra.winner_pool_max then
            result.data.msg = "winner_pool_max not provided"
            result.data.state = Constants.Error.ArgumentNotSet
            return result
        end
    end
        
    -- buying gold
    local buying_gold = data.buying_gold
    if not buying_gold then
        result.data.msg = "buying_gold not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    -- buying stake
    local buying_stake = data.buying_stake
    if not buying_stake then
        result.data.msg = "buying_stake not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    -- max players
    local max_players = data.max_players
    if not max_players then
        result.data.msg = "max_players not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    -- user action timeout
    local timeout = data.timeout -- user action timeout, in seconds
    if not timeout then
        result.data.msg = "timeout not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local blinds_start = data.blinds_start
    if not blinds_start then
        result.data.msg = "blinds_start not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    -- password
    local password = data.password or ""

    -- game name
    local name = data.name
    if not name then
        result.data.msg = "name not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    -- which club does this game belong to?
    local club_id = data.club_id
    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local game_id, err = instance:getNextId("game")
    if not game_id then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "failed to get next_id for table game, err: " .. err
        return result
    end

    --tcp msg format: CREATE game_id: 23 players:5 stake:1500 timeout:30 blinds_start:20 blinds_factor:20 blinds_time:300 password: "name:peter's game 1"
    local message = msgid .. " CREATE game_id:"         .. game_id
                                .. " type:"             .. game_mode 
                                .. " players:"          .. max_players 
                                .. " stake:"            .. buying_stake 
                                .. " timeout:"          .. timeout
                                .. " blinds_start:"     .. blinds_start
                                .. " blinds_factor:"    .. (extra.blinds_factor or 12)
                                .. " blinds_time:"      .. (extra.blinds_time or 30)
                                .. " password:"         .. password
                                .. " expire_in:"        .. (extra.duration or 0)
                                .. " \"name:"           .. name .. "\""
                                .. "\n" -- '\n' is mandatory
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    -- create record in table game
    local sql = "INSERT INTO game (max_players, timeout, blinds_start, password, name,  owner_id, club_id, game_mode, buying_gold, buying_stake) "
                      .. " VALUES (" .. max_players .. ", "
                               ..  timeout .. ", "
                               ..  blinds_start .. ", "
                               .. instance:sqlQuote(password) .. ", "
                               .. instance:sqlQuote(name) .. ", "
                               .. instance:getCid() .. ", "
                               .. club_id .. ", "
                               .. game_mode .. ", "
                               .. buying_gold .. ", "
                               .. buying_stake .. "); "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- create record in table game_extra
    local sql = "INSERT INTO game_extra (game_id, game_mode, duration, blind_factor, blind_time, start_at, allow_rebuy, allow_rebuy_times, allow_rebuy_before_level, ante, winner_pool_max, deny_register_after) "
                      .. " VALUES (" .. game_id .. ", "
                               ..  game_mode .. ", "
                               ..  (extra.duration or 0) .. ", "
                               ..  (extra.blind_factor or 0) .. ", "
                               ..  (extra.blind_time or 0) .. ", "
                               ..  (extra.start_at or 0) .. ", "
                               ..  (extra.allow_rebuy or 0) .. ", "
                               ..  (extra.allow_rebuy_times or 0) .. ", "
                               ..  (extra.allow_rebuy_before_level or 0) .. ", "
                               ..  (extra.ante or 0) .. ", "
                               ..  (extra.winner_pool_max or 0) .. ", "
                               ..  (extra.deny_register_after or 0) .. ") "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- add game owner to the channel
    if game_mode == Constants.GameMode.GameModeFreezeOut then
        local channel = "mtt_" .. tostring(game_id)
        local res, err = Leancloud:subscribeChannel({channel = channel, 
                                    installation = instance:getInstallation()
                                    })
        if not res then
            result.data.state = Constants.Error.LeanCloudError
            result.data.msg = "failed to subscribe to channel: " .. err
            return result
        end
    
        -- push reminder to all registered players 10 minutes before mtt game starts
        local message = "您报名的MTT大型赛事《" 
                        .. name 
                        .. "》即将在10分钟后（" 
                        .. os.date('%Y-%m-%d %H:%M', start_at) 
                        .. "）开始，请做好准备！"

        local args = {channel=channel, push_time = start_at - 10 * 60} 
        -- for test: local args = {channel=channel, push_time = os.time() + 60} 
        local res, err = Leancloud:push(args, message)
        if not res then
            result.data.state = Constants.Error.LeanCloudError
            result.data.msg = "failed to push message to channel: " .. err
            cc.printdebug("failed to push message: %s", err)
            return result
        end

    end

    return 
end

function GameAction:listgameAction(args)
    local data = args.data
    local club_id = data.club_id
    local limit = data.limit or Constants.Limit.ListGameLimit
    local offset = data.offset or 0
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    if limit > 50 then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListGameLimit .. " allowed in one query"
        result.data.state = PermissionDenied
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid
    self._club_id = club_id
    self._limit = limit
    self._offset = offset

    --send command to allin server, tcp format: REGISTER 1
    local message = msgid .. " REQUEST gamelist\n"
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:joingameAction(args)
    local data = args.data
    local game_id = data.game_id
    local password = data.password or ""
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    local user_clubs = instance:getClubIds(instance:getMysql())
    if not table.contains(user_clubs, tonumber(game.club_id)) then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not member of club with club_id: " .. game.club_id
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    -- buy required stake
    local required_stake  = game.buying_stake
    local res = _buyStake(required_stake, {instance = instance, 
                                                mysql = mysql, 
                                                game_id = game_id,
                                                blinds_start = game.blinds_start,
                                                gold_needed = game.buying_gold
                                                })
    if res.status ~= 0 then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "failed to buy stake: " .. res.err
        return result
    end
    local player_stake = res.stake_bought

    local message = msgid .. " REGISTER " .. game_id .. " " .. player_stake .. " " .. password .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    --TODO: add user to leancloud channel to receive reminder
    return 
end

function GameAction:rebuyAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]

    -- buy required stake no matter if user has stake left
    local required_stake  = game.buying_stake
    local res = _buyStake(required_stake, {instance = instance, 
                                                mysql = mysql, 
                                                game_id = game_id,
                                                ignore_stake_left = true,
                                                blinds_start = game.blinds_start,
                                                gold_needed = game.buying_gold
                                                })
    if res.status ~= 0 then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "failed to buy stake: " .. res.err
        return result
    end
    local rebuy_stake = res.stake_bought

    local message = msgid .. " REBUY " .. game_id .. " " .. rebuy_stake ..  "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:leavegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: UNREGISTER 1
    local message = msgid .. " UNREGISTER " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:requestgameinfoAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: REQUEST gameinfo 1
    local message = msgid .. " REQUEST gameinfo " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:onAllinMessage(event)
    -- This function is called in a seperate thread from /opt/gbc-core/src/packages/allin/NginxAllinLoop.lua
    local message = event.message
    local mysql   = event.mysql
    if not message then
        cc.printdebug("message not found in event")
    end
    if not mysql then
        cc.printdebug("mysql not found in event")
    end

    local websocket = event.websocket
    if not websocket then
        cc.printdebug("websocket not found in event")
    end

    websocket:sendMessage(self:processMessage(message, mysql))
end

function GameAction:requestplayerlistAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action

    --send command to allin server, tcp format: REQUEST gameinfo 1
    local message = msgid .. " REQUEST playerlist " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:requestplayerinfoAction(args)
    local data = args.data
    local user_id = data.user_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"user_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT id, phone, nickname, gold FROM user WHERE id = " .. user_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "player with user_id: " .. user_id .. " not found"
        return result
    end

    local player = dbres[1]
    result.data.id          = player.id
    result.data.phone       = player.phone
    result.data.nickname    = player.nickname
    result.data.gold        = player.gold
    result.data.state = Constants.OK
    return result
end

function GameAction:startgameAction(args)
    local data = args.data
    local game_id = data.game_id
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end


    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can start a game"
        return result
    end
    if game.game_mode == Constants.GameMode.GameModeFreezeOut then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "cannot start MTT games. MTT games will start automatically at scheduled time"
        return result
    end

    -- at least 2 players are required. user_game_history records are added in handleGameInfo
    local game_runtime = Game_Runtime:new(instance)
    local player_count = game_runtime:getPlayerCount(game_id)
    if tonumber(player_count) < 2 then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "there must be at least 2 players joined the game before the game can be started"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST start " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:pausegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local delay = data.delay   -- in seconds
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can pause a game"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST pause " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:resumegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local delay = data.delay   -- in seconds
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    -- check if current user is the game owner
    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT * FROM game WHERE id = " .. game_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg   = "game with id: " .. game_id .. " not found"
        return result
    end
    local game = dbres[1]
    if game.owner_id ~= user_id then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not game owner, only the game owner can resume a game"
        return result
    end

    --send command to allin server, tcp format: REQUEST start 1
    local message = msgid .. " REQUEST resume " .. game_id .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    return 
end

function GameAction:useractionAction(args)
    local data = args.data 
    local game_id = data.game_id 
    local msgid = args.__id 
    local user_action = data.user_action 
    local amount = data.amount or 0 
    local result = {state_type = "action_state", data = { action = args.action} }

    if not game_id then
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"game_id\"")
        return result
    end
    if not user_action then
        result.data.msg = "user_action not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"user_action\"")
        return result
    end

    self._currentAction = args.action
    self._msgid = msgid

    --send command to allin server, tcp format: ACTION <game_id> <action_name> <amount>
    local message = msgid .. " ACTION " .. game_id .. " " .. user_action .. " " .. amount .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        result.data.state = Constants.Error.AllinError
        result.data.msg = err
        cc.printwarn("failed to send message: %s", err)
        return result
    end 

    result.data.user_action = user_action
    result.data.state = 0
    result.data.msg = "user action sent"
    return result
end

function GameAction:processMessage(message, mysql)
    cc.printdebug("GameAction:processMessage processing message: %s", message)
    local parts = string_split(message, " ")
    local cmd = parts[1]

    if tonumber(cmd) ~= nil then
       cmd = parts[2] 
    end

    if not self.ServerCmdHandler[cmd] then
       return { err = "Unknown server response: " .. cmd }
    end
    
    return self.ServerCmdHandler[cmd](parts, {action = self._currentAction
                                            , msgid = self._msgid
                                            , club_id = self._club_id
                                            , limit = self._limit
                                            , offset = self._offset
                                            , mysql = mysql
                                            , user_id = self:getInstance():getCid()
                                            , instance = self:getInstance()
                                            })
end


function GameAction:onDisconnect(event)
    -- unregister all games user has registered
    local message = " UNREGISTER -1 " .. "\n";
    cc.printdebug("sending message to allin server: %s", message)
    local instance = self:getInstance()
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        local err = Constants.Error.AllinError
        cc.printwarn("failed to send message: %s", err)
    end 
end

return GameAction
