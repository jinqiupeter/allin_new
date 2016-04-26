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


return DataAction
