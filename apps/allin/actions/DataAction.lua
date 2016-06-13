local string_split       = string.split
local Constants = cc.import(".Constants", "..")
local gbc = cc.import("#gbc")
local json = cc.import("#json")
local DataAction = cc.class("DataAction", gbc.ActionBase)
DataAction.ACCEPTED_REQUEST_TYPE = "websocket"
-- public methods
function DataAction:ctor(config)
    DataAction.super.ctor(self, config)
end

function round(num, idp)
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

function DataAction:gamesplayedAction(args)
    local data = args.data
    local starting_date = data.starting_date
    local ending_date = data.ending_date
    local limit = data.limit or Constants.Limit.ListDataLimit
    local offset = data.offset or 0
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local user_id = data.user_id or instance:getCid()

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not starting_date then
        cc.printinfo("argument not provided: \"starting_date\"")
        result.data.msg = "starting_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not ending_date then
        cc.printinfo("argument not provided: \"ending_date\"")
        result.data.msg = "ending_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    starting_date = os.date('%Y-%m-%d %H:%M:%S', starting_date)
    ending_date = os.date('%Y-%m-%d %H:%M:%S', ending_date)

    local sub_query = " SELECT game_id, user_id, bought_at, MAX(updated_at) as updated_at, sum(stake_bought) as stake_bought FROM buying"
                       .. " WHERE updated_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
                       .. " AND user_id = " .. user_id 
                       .. " GROUP BY game_id " 
    local sql = "SELECT b.game_id, b.stake_available as stake_ended, b.updated_at as ended_at, d.name, a.stake_bought, (b.stake_available - a.stake_bought) as result FROM "
    .. "(" .. sub_query .. ") a,"
    .. " buying b, "
    .. "game d " 
    .. " WHERE d.id = b.game_id "
    .. " AND a.game_id = b.game_id "
    .. " AND a.user_id = b.user_id "
    .. " AND a.updated_at = b.updated_at"
    .. " GROUP BY b.game_id "
    .. " LIMIT " .. offset .. ", " .. limit

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.games = dbres
    result.data.game_played = #dbres
    local total_result = 0
    for key, value in pairs(result.data.games) do
        total_result = total_result + value.result
    end
    result.data.total_result = total_result
    result.data.offset = offset
    result.data.state = 0
    return result
end

function DataAction:analyzestyleAction(args)
    local data = args.data
    local starting_date = data.starting_date
    local ending_date = data.ending_date
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local user_id = data.user_id or instance:getCid()

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not starting_date then
        cc.printinfo("argument not provided: \"starting_date\"")
        result.data.msg = "starting_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not ending_date then
        cc.printinfo("argument not provided: \"ending_date\"")
        result.data.msg = "ending_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    starting_date = os.date('%Y-%m-%d %H:%M:%S', starting_date)
    ending_date = os.date('%Y-%m-%d %H:%M:%S', ending_date)
 
    -- biggest bet, total action, vpip, wtsd, pfr
    local sql = "SELECT " 
                .. " COALESCE(MAX(amount), 0) AS biggest_bet, "
                .. " COALESCE(COUNT(*), 0) as total_action , "
                .. " COALESCE(SUM(action_type IN (3, 4, 5, 6)), 0) as vpip, " -- voluntarily put $ in pot
                .. " COALESCE(SUM(bet_round = 3), 0) as wtsd, "     -- went to showdown
                .. " COALESCE(SUM(action_type in (4, 5)), 0) as total_bet_raise, "    
                .. " COALESCE(SUM(action_type =3), 0) as total_call, "     
                .. " COALESCE(SUM(action_type = 5 and bet_round = 0), 0) as pfr "    -- pre flop raise
                .. " FROM user_action WHERE "
                .. " user_id = " .. user_id
                .. " AND performed_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.biggest_bet     = dbres[1].biggest_bet
    result.data.total_action    = dbres[1].total_action
    result.data.vpip            = dbres[1].vpip 
    result.data.wtsd            = dbres[1].wtsd
    result.data.total_bet_raise = dbres[1].total_bet_raise
    result.data.total_call      = dbres[1].total_call 
    result.data.pfr             = dbres[1].pfr 
    if tonumber(result.data.vpip) == 0 then
        result.data.vpip_rate = "0%"
    else
        result.data.vpip_rate       = round(result.data.vpip / result.data.total_action  * 100, 1) .. "%"
    end
    if tonumber(result.data.total_call) == 0 then
        result.data.af = result.data.total_bet_raise
    else
        result.data.af              = result.data.total_bet_raise / result.data.total_call -- Aggression Factor
    end


    -- total_hands_played
    local total_hands_sql = "SELECT COALESCE(COUNT(hand_id), 0) AS total_hands FROM game_stake"
                            .. " WHERE user_id = " .. user_id
                            .. " AND updated_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    cc.printdebug("executing sql: %s", total_hands_sql)
    local dbres, err, errno, sqlstate = mysql:query(total_hands_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.total_hands = dbres[1].total_hands
    if tonumber(result.data.wtsd) == 0 then
        result.data.wtsd_rate = "0%"
    else 
        result.data.wtsd_rate = round(result.data.wtsd / result.data.total_hands * 100, 1)  .. "%"
    end
    if tonumber(result.data.pfr) == 0 then
        result.data.pfr_rate = "0%"
    else
        result.data.pfr_rate = round(result.data.pfr / result.data.total_hands * 100, 1)  .. "%"
    end

    -- total_hands_won
    local hands_won_sql = "SELECT COALESCE(COUNT(*), 0) AS hands_won FROM game_winners"
                            .. " WHERE winner_id = " .. user_id
                            .. " AND created_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    cc.printdebug("executing sql: %s", hands_won_sql)
    local dbres, err, errno, sqlstate = mysql:query(hands_won_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.hands_won = dbres[1].hands_won
    if tonumber(result.data.hands_won) == 0 then
        result.data.hands_won_rate = "0%"
    else
        result.data.hands_won_rate = round(result.data.hands_won / result.data.total_hands * 100, 1) .. "%"
    end


    -- wtsd and won
    local sub_query = "SELECT game_id, table_id, hand_id FROM user_action "
                      .. " WHERE bet_round = 3 "
                      .. " AND user_id = " .. user_id
                      .. " AND performed_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    local wtsd_won_sql = "SELECT COALESCE(COUNT(*), 0) AS wtsd_won FROM game_winners a join "
                            .. "(" .. sub_query .. ") b"
                            .. " ON (a.game_id = b.game_id AND a.table_id = b.table_id AND a.hand_id = b.hand_id) "
                            .. " WHERE a.winner_id = " .. user_id
                            .. " AND a.created_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    cc.printdebug("executing sql: %s", wtsd_won_sql)
    local dbres, err, errno, sqlstate = mysql:query(wtsd_won_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.wtsd_won        = dbres[1].wtsd_won
    if tonumber(result.data.wtsd_won) == 0 then
        result.data.wtsd_won_rate = "0%"
    else 
        result.data.wtsd_won_rate   = round(result.data.wtsd_won / result.data.wtsd * 100, 1).. "%"
    end

    result.data.state = 0
    return result
end


function DataAction:listallclubgamesAction(args)
    local data = args.data
    local starting_date = data.starting_date
    local ending_date = data.ending_date
    local limit = data.limit or Constants.Limit.ListDataLimit
    local offset = data.offset or 0

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not starting_date then
        cc.printinfo("argument not provided: \"starting_date\"")
        result.data.msg = "starting_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not ending_date then
        cc.printinfo("argument not provided: \"ending_date\"")
        result.data.msg = "ending_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    starting_date = os.date('%Y-%m-%d %H:%M:%S', starting_date)
    ending_date = os.date('%Y-%m-%d %H:%M:%S', ending_date)
    local sub_query = " SELECT game_id, user_id, bought_at, MAX(updated_at) as updated_at FROM buying"
                       .. " WHERE updated_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
                       .. " GROUP BY game_id "
    local sql = "SELECT c.id AS club_id, c.name AS club_name , c.area, COUNT(b.game_id = g.id and g.club_id = uc.club_id) as total_games "
    .. " FROM club c, user_club uc, (" .. sub_query .. ") b, game g"
    .. " WHERE uc.user_id = " .. instance:getCid()
    .. " AND uc.club_id = c.id "
    .. " AND b.user_id = uc.user_id "
    .. " AND b.game_id = g.id "
    .. " AND uc.club_id = g.club_id "
    .. " GROUP BY g.club_id "
    .. " ORDER BY total_games DESC "
    .. " LIMIT " .. offset .. ", " .. limit

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.clubs = dbres
    result.data.clubs_found = #dbres
    result.data.offset = offset
    result.data.state = 0
    return result
end

function DataAction:listgamesinclubAction(args)
    local data = args.data
    local starting_date = data.starting_date
    local ending_date = data.ending_date
    local club_id = data.club_id
    local limit = data.limit or Constants.Limit.ListDataLimit
    local offset = data.offset or 0

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        cc.printinfo("argument not provided: \"club_id\"")
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not starting_date then
        cc.printinfo("argument not provided: \"starting_date\"")
        result.data.msg = "starting_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not ending_date then
        cc.printinfo("argument not provided: \"ending_date\"")
        result.data.msg = "ending_date not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    starting_date = os.date('%Y-%m-%d %H:%M:%S', starting_date)
    ending_date = os.date('%Y-%m-%d %H:%M:%S', ending_date)

    local sub_query = "SELECT COUNT(DISTINCT user_id) AS players, MAX(updated_at) - MIN(bought_at) AS duration, "
                       .. " game_id, MIN(bought_at) AS started_at, MAX(updated_at) AS ended_at,  SUM(stake_bought) AS total_buying FROM buying"
                       .. " WHERE updated_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
                       .. " GROUP BY game_id "
    local sql = "SELECT b.game_id , g.name AS game_name, g.game_mode, b.ended_at, "
                .. " b.duration / 60 as duration,  b.players, "
                .. " b.total_buying "
                .. " FROM game g,  (" .. sub_query .. ") b"
                .. " WHERE g.club_id = " .. club_id
                .. " AND g.id = b.game_id "
                .. " GROUP BY b.game_id"
                .. " LIMIT " .. offset .. ", " .. limit

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.games = dbres
    result.data.games_found = #dbres
    result.data.offset = offset
    result.data.state = 0
    return result
end

function DataAction:showgamedataAction(args)
    local data = args.data
    local game_id = data.game_id
    local limit = data.limit or Constants.Limit.ListDataLimit
    local offset = data.offset or 0

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        cc.printinfo("argument not provided: \"game_id\"")
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()

    --
    local sub_query = " SELECT game_id, user_id, bought_at, MAX(updated_at) as updated_at, sum(stake_bought) as stake_bought FROM buying"
                       .. " WHERE game_id = " .. game_id
                       .. " GROUP BY user_id"
    local sql = "SELECT a.game_id, a.user_id, u.nickname, b.stake_available as stake_ended, "
                .. " a.stake_bought as total_buying, "
                .. " (b.stake_available - a.stake_bought) AS result"
                .. " FROM user u , "
                .. "(" .. sub_query .. ")  a,"
                .. " buying b "
                .. " WHERE "
                .. " a.user_id = b.user_id "
                .. " AND a.game_id = b.game_id "
                .. " AND a.updated_at = b.updated_at"
                .. " AND a.user_id = u.id "
                .. " GROUP BY a.user_id"
                .. " LIMIT " .. offset .. ", " .. limit

    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.player_data = dbres
    result.data.players_found = #dbres
    result.data.state = 0
    result.data.offset = offset
    result.data.game_id = game_id
    
    local game_runtime = instance:getGameRuntime()
    local started_at = game_runtime:getGameInfo(game_id, "StartedAt")
    local blind_amount = game_runtime:getGameInfo(game_id, "BlindAmount")
    local duration = game_runtime:getGameInfo(game_id, "Duration")
    local game_state = game_runtime:getGameInfo(game_id, "GameState")

    result.data.started_at = started_at
    result.data.blind_amount = blind_amount
    result.data.duration = duration
    if tonumber(game_state) == Constants.GameState.GameStateEnded then
        local started_str = os.date('%Y-%m-%d %H:%M:%S', started_at)
        local sql = " SELECT MAX(updated_at) - FROM_UNIXTIME(" .. started_str .. ") as time_elapsed FROM buying"
                       .. " WHERE game_id = " .. game_id
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end

        result.data.time_elapsed = dbres[1].time_elapsed
    else
        result.data.time_elapsed = os.time() - started_at
    end

    return result
end

function DataAction:analyzestyleingameAction(args)
    local data = args.data
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local user_id = data.user_id or instance:getCid()
    local game_id = data.game_id

    if not game_id then
        cc.printinfo("argument not provided: \"game_id\"")
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

 
    -- biggest bet, total action, vpip, wtsd, pfr
    local sql = "SELECT " 
                .. " COALESCE(MAX(amount), 0) AS biggest_bet, "
                .. " COALESCE(COUNT (*), 0) as total_action , "
                .. " COALESCE(SUM(action_type IN (3, 4, 5, 6)), 0) as vpip, " -- voluntarily put $ in pot
                .. " COALESCE(SUM(bet_round = 3), 0) as wtsd, "     -- went to showdown
                .. " COALESCE(SUM(action_type in (4, 5) ), 0) as total_bet_raise, "    
                .. " COALESCE(SUM(action_type =3), 0) as total_call, "     
                .. " COALESCE(SUM(action_type = 5 and bet_round = 0), 0) as pfr "    -- pre flop raise
                .. " FROM user_action WHERE "
                .. " user_id = " .. user_id
                .. " AND game_id = " .. game_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.biggest_bet     = dbres[1].biggest_bet 
    result.data.total_action    = dbres[1].total_action  
    result.data.vpip            = dbres[1].vpip 
    result.data.wtsd            = dbres[1].wtsd
    result.data.total_bet_raise = dbres[1].total_bet_raise
    result.data.total_call      = dbres[1].total_call
    result.data.pfr             = dbres[1].pfr
    if tonumber(result.data.vpip) == 0 then
        result.data.vpip_rate       = "0%"
    else
        result.data.vpip_rate       = round(result.data.vpip / result.data.total_action  * 100, 1) .. "%"
    end
    if tonumber(result.data.total_call) then
        result.data.af = result.data.total_bet_raise
    else 
        result.data.af              = result.data.total_bet_raise / result.data.total_call -- Aggression Factor
    end

    -- total_hands_played
    local total_hands_sql = "SELECT COALESCE(COUNT(hand_id), 0) AS total_hands FROM game_stake"
                            .. " WHERE user_id = " .. user_id
                            .. " AND game_id = " .. game_id
    cc.printdebug("executing sql: %s", total_hands_sql)
    local dbres, err, errno, sqlstate = mysql:query(total_hands_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.total_hands = dbres[1].total_hands
    if tonumber(result.data.wtsd) == 0 then
        result.data.wtsd_rate = "0%"
    else
        result.data.wtsd_rate = round(result.data.wtsd / result.data.total_hands * 100, 1)  .. "%"
    end
    if tonumber(result.data.pfr) == 0 then
        result.data.pfr_rate = "0%" 
    else
        result.data.pfr_rate = round(result.data.pfr / result.data.total_hands * 100, 1)  .. "%"
    end

    -- total_hands_won
    local hands_won_sql = "SELECT COALESCE(COUNT(*), 0) AS hands_won FROM game_winners"
                            .. " WHERE winner_id = " .. user_id
                            .. " AND game_id =  " .. game_id
    cc.printdebug("executing sql: %s", hands_won_sql)
    local dbres, err, errno, sqlstate = mysql:query(hands_won_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.hands_won = dbres[1].hands_won 
    cc.printdebug("result.data.hands_won: %s", result.data.hands_won)
    if tonumber(result.data.hands_won) == 0 then
        result.data.hands_won_rate = "0%"
        cc.printdebug("result.data.hands_won_rate111: %s", result.data.hands_won_rate)
    else
        result.data.hands_won_rate = round(result.data.hands_won / result.data.total_hands * 100, 1) .. "%"
        cc.printdebug("result.data.hands_won_rate222: %s", result.data.hands_won_rate)
    end


    -- wtsd and won
    local sub_query = "SELECT game_id, table_id, hand_id FROM user_action "
                      .. " WHERE bet_round = 3 "
                      .. " AND user_id = " .. user_id
                      .. " AND game_id = " .. game_id
    local wtsd_won_sql = "SELECT COALESCE(COUNT(*), 0) AS wtsd_won FROM game_winners a join "
                            .. "(" .. sub_query .. ") b"
                            .. " ON (a.game_id = b.game_id AND a.table_id = b.table_id AND a.hand_id = b.hand_id) "
                            .. " WHERE a.winner_id = " .. user_id
                            .. " AND a.game_id = " .. game_id
    cc.printdebug("executing sql: %s", wtsd_won_sql)
    local dbres, err, errno, sqlstate = mysql:query(wtsd_won_sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.wtsd_won        = dbres[1].wtsd_won
    if tonumber(result.data.wtsd_won) == 0 then
        result.data.wtsd_won_rate = "0%"
    else
        result.data.wtsd_won_rate   = round(result.data.wtsd_won / result.data.wtsd * 100, 1).. "%"
    end

    result.data.state = 0
    return result
end

return DataAction
