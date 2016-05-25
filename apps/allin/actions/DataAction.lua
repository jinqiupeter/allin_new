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

    local sub_query = "SELECT MAX(updated_at) AS updated_at FROM game_stake " 
                      .. " WHERE updated_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
                      .. " AND user_id = " .. instance:getCid() 
                      .. " GROUP BY game_id"
    local sql = "SELECT a.game_id, a.stake as stake_ended, c.ended_at, d.name, e.stake as stake_bought, (a.stake - e.stake) as result FROM "
    .. "game_stake a, "
    .. "(" .. sub_query .. ") b,"
    .. "user_game_history c, " 
    .. "game d, " 
    .. "buying e"
    .. " WHERE a.updated_at = b.updated_at "
    .. " AND a.game_id = c.game_id "
    .. " AND a.user_id = " .. instance:getCid()
    .. " AND c.user_id = " .. instance:getCid()
    .. " AND a.game_id = d.id"
    .. " AND a.game_id = e.game_id"
    .. " AND e.user_id = " .. instance:getCid()
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
                .. " MAX (amount) AS biggest_bet, "
                .. " COUNT (*) as total_action , "
                .. " SUM (action_type IN (3, 4, 5, 6)) as vpip, " -- voluntarily put $ in pot
                .. " SUM (bet_round = 3) as wtsd, "     -- went to showdown
                .. " SUM (action_type in (4, 5) ) as total_bet_raise, "    
                .. " SUM (action_type =3 ) as total_call, "     
                .. " SUM (action_type = 5 and bet_round = 0 ) as pfr "    -- pre flop raise
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
    result.data.vpip_rate       = round(result.data.vpip / result.data.total_action  * 100, 1) .. "%"
    result.data.af              = result.data.total_bet_raise / result.data.total_call -- Aggression Factor


    -- total_hands_played
    local total_hands_sql = "SELECT COUNT(hand_id) AS total_hands FROM game_stake"
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
    result.data.wtsd_rate = round(result.data.wtsd / result.data.total_hands * 100, 1)  .. "%"
    result.data.pfr_rate = round(result.data.pfr / result.data.total_hands * 100, 1)  .. "%"

    -- total_hands_won
    local hands_won_sql = "SELECT COUNT(*) AS hands_won FROM game_winners"
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
    result.data.hands_won_rate = round(result.data.hands_won / result.data.total_hands * 100, 1) .. "%"


    -- wtsd and won
    local sub_query = "SELECT game_id, table_id, hand_id FROM user_action "
                      .. " WHERE bet_round = 3 "
                      .. " AND user_id = " .. user_id
                      .. " AND performed_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
    local wtsd_won_sql = "SELECT COUNT(*) AS wtsd_won FROM game_winners a join "
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
    result.data.wtsd_won_rate   = round(result.data.wtsd_won / result.data.wtsd * 100, 1).. "%"

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

    local sql = "SELECT c.id AS club_id, c.name AS club_name , c.area, COUNT(ugh.game_id = g.id and g.club_id = uc.club_id) as total_games "
    .. " FROM club c, user_club uc, user_game_history ugh, game g"
    .. " WHERE uc.user_id = " .. instance:getCid()
    .. " AND uc.club_id = c.id "
    .. " AND ugh.user_id = uc.user_id "
    .. " AND ugh.game_id = g.id "
    .. " AND uc.club_id = g.club_id "
    .. " AND ugh.ended_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
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

    -- 'select ugh.game_id , g.name as game_name, g.game_mode, ugh.ended_at, ugh.ended_at - ugh.started_at as duration, count(ugh.user_id) as players  from game g, user_game_history ugh  where g.club_id = 329  and g.id = ugh.game_id and ugh.game_id in (select game_id from user_game_history where user_id = 5) group by ugh.game_id'
    --
    local sub_query = " SELECT game_id from user_game_history where user_id = " .. instance:getCid()
    local sql = "SELECT ugh.game_id , g.name AS game_name, g.game_mode, ugh.ended_at, "
                .. " ugh.ended_at - ugh.started_at AS duration, "
                .. " COUNT(distinct ugh.user_id) AS players, "
                .. " SUM(b.stake) / COUNT(distinct b.user_id) AS total_buying "
                .. " FROM game g, user_game_history ugh, buying b"
                .. " WHERE g.club_id = " .. club_id
                .. " AND g.id = ugh.game_id "
                .. " AND ugh.game_id in (" .. sub_query .. ")"
                .. " AND ugh.ended_at BETWEEN " .. instance:sqlQuote(starting_date) .. " AND " .. instance:sqlQuote(ending_date)
                .. " AND ugh.game_id = b.game_id "
                .. " GROUP BY ugh.game_id"
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

    -- select gs.stake as stake_ended_at, ugh.game_id, ugh.user_id, u.nickname, sum(b.stake) as total_buying from user u, (select * from game_stake where updated_at in (select  MAX(updated_at) AS updated_at FROM game_stake where game_id = 1514 group by user_id)) gs, buying b, user_game_history ugh where ugh.game_id = b.game_id and ugh.user_id = b.user_id and b.game_id = 1514 and b.user_id = u.id and gs.game_id = b.game_id and gs.user_id = b.user_id group by ugh.user_id
    --
    local sub_query = " SELECT * FROM game_stake WHERE updated_at IN ( "
                       .. " SELECT  MAX(updated_at) AS updated_at FROM game_stake WHERE game_id = " .. game_id .. " GROUP BY user_id " 
                       .. " ) "
    local sql = "SELECT ugh.game_id, ugh.user_id, u.nickname, gs.stake as stake_ended, "
                .. " SUM(b.stake) as total_buying, "
                .. " gs.stake - SUM(b.stake) AS result"
                .. " FROM user u , "
                .. "(" .. sub_query .. ") as gs,"
                .. " buying b, user_game_history ugh "
                .. " WHERE ugh.game_id = " .. game_id
                .. " AND ugh.user_id = b.user_id "
                .. " AND ugh.game_id = b.game_id "
                .. " AND ugh.user_id = u.id "
                .. " AND gs.game_id = b.game_id"
                .. " AND gs.user_id = b.user_id"
                .. " GROUP BY ugh.user_id"
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
                .. " MAX (amount) AS biggest_bet, "
                .. " COUNT (*) as total_action , "
                .. " SUM (action_type IN (3, 4, 5, 6)) as vpip, " -- voluntarily put $ in pot
                .. " SUM (bet_round = 3) as wtsd, "     -- went to showdown
                .. " SUM (action_type in (4, 5) ) as total_bet_raise, "    
                .. " SUM (action_type =3 ) as total_call, "     
                .. " SUM (action_type = 5 and bet_round = 0 ) as pfr "    -- pre flop raise
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
    result.data.vpip_rate       = round(result.data.vpip / result.data.total_action  * 100, 1) .. "%"
    result.data.af              = result.data.total_bet_raise / result.data.total_call -- Aggression Factor


    -- total_hands_played
    local total_hands_sql = "SELECT COUNT(hand_id) AS total_hands FROM game_stake"
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
    result.data.wtsd_rate = round(result.data.wtsd / result.data.total_hands * 100, 1)  .. "%"
    result.data.pfr_rate = round(result.data.pfr / result.data.total_hands * 100, 1)  .. "%"

    -- total_hands_won
    local hands_won_sql = "SELECT COUNT(*) AS hands_won FROM game_winners"
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
    result.data.hands_won_rate = round(result.data.hands_won / result.data.total_hands * 100, 1) .. "%"


    -- wtsd and won
    local sub_query = "SELECT game_id, table_id, hand_id FROM user_action "
                      .. " WHERE bet_round = 3 "
                      .. " AND user_id = " .. user_id
                      .. " AND game_id = " .. game_id
    local wtsd_won_sql = "SELECT COUNT(*) AS wtsd_won FROM game_winners a join "
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
    result.data.wtsd_won_rate   = round(result.data.wtsd_won / result.data.wtsd * 100, 1).. "%"

    result.data.state = 0
    return result
end

return DataAction
