local string_split       = string.split
local gbc = cc.import("#gbc")
local json      = cc.import("#json")
local Constants  = cc.import(".Constants", "..")
local SocialAction = cc.class("SocialAction", gbc.ActionBase)
local Helper = cc.import(".Helper", "..")

SocialAction.ACCEPTED_REQUEST_TYPE = "websocket"

local json_encode = json.encode
local json_decode = json.decode
local Game_Runtime = cc.import("#game_runtime")
local User_Runtime = cc.import("#user_runtime")

-- public methods
function SocialAction:ctor(config)
    SocialAction.super.ctor(self, config)
end


function SocialAction:gametablechatAction(args)
    local data = args.data
    local game_id  = data.game_id
    local table_id = data.table_id
    local content  = data.content
    local target_id = data.target_id
    local content_type = data.content_type
    local result = {state_type = "action_state", data = {
        action = args.action}
    }
    local message = {state_type = "server_push", data = {push_type = "social.tablechat"}}

    if not game_id then
        cc.printinfo("argument not provided: \"game_id\"")
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not table_id then
        cc.printinfo("argument not provided: \"table_id\"")
        result.data.msg = "table_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not content then
        cc.printinfo("argument not provided: \"content\"")
        result.data.msg = "content not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not content_type then
        cc.printinfo("argument not provided: \"content_type\"")
        result.data.msg = "content_type not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local instance = self:getInstance()
    local redis = instance:getRedis()
    local mysql = instance:getMysql()
    if content_type == "animation" then
        local bought, err = Helper:buyAnimation(instance, content)
        if not bought then
            result.data.msg = Constants.ErrorMsg.FailedToBuyAnimation .. ": " .. err
            result.data.state = Constants.Error.PermissionDenied
            return result
        end 

        -- create animation buying history
        local sql = "INSERT INTO animation_purchase (name, from_user, to_user, game_id, table_id) VALUES ("
                    .. instance:sqlQuote(content) .. ", "
                    .. instance:getCid() .. ", "
                    .. target_id .. ", "
                    .. game_id .. ", "
                    .. table_id .. ")"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.msg = "数据库错误: " .. err
            result.data.state = Constants.Error.MysqlError
            return result
        end
    end


    message.data.content_type = content_type
    message.data.content = content
    message.data.sender_id  = instance:getCid()
    message.data.target_id  = target_id
	message.data.game_id = game_id

    local table_channel = Constants.TABLE_CHAT_CHANNEL_PREFIX .. tostring(game_id) .. "_" .. tostring(table_id)
    cc.printdebug("sending message to game: %s, table: %s, message: %s", game_id, table_id, json_encode(message))
    local ok, err = redis:publish(table_channel, _formatmsg(message))
    if not ok then
        cc.printerror("failed to publish message to redis: %s", err)
        result.data.msg = "failed to publish message to redis: " .. err
        result.data.state = Constants.Error.RedisError 
        return result
    end

    result.data.state = 0
    result.data.msg = "message sent successfully"
    result.data.content_type = content_type
    result.data.content = content
    result.data.game_id = game_id
    result.data.table_id = table_id
    result.data.sender_id  = instance:getCid()
    result.data.target_id  = target_id
    return result
end

function SocialAction:updateinstallationAction(args)
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = args.action, state = 0, msg = "installation updated"}
    }

    local user_id = data.user_id
    local installation = data.installation

    --parameter validity check
    if not user_id then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "user id not provided"
        return
    end
    if not installation then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "installation not provided"
        return
    end

    --check if phone is signed up
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "select * from user where id = ".. user_id .. ";"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "user id " .. user_id .. " not found"
        return result
    end

    local sql = "update user set installation = " .. instance:sqlQuote(installation) .. " where id = ".. user_id .. ";"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    return result
end

function SocialAction:updatenicknameAction(args)
    local data = args.data
    local result = {state_type = "action_state", data = {
        action = args.action, state = 0, msg = "nickname updated"}
    }

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local user_id = instance:getCid()
    local nickname = data.nickname

    if not nickname then
        result.data.state = Constants.Error.ArgumentNotSet
        result.data.msg = "nickname not provided"
        return
    end

    --check if phone is signed up
    local sql = "select * from user where id = ".. user_id .. ";"
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误" .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "user id " .. user_id .. " not found"
        return result
    end

    local sql = "update user set nickname = " .. instance:sqlQuote(nickname) .. " where id = ".. user_id .. ";"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.nickname = nickname
    return result
end

function _are_friends(user_a, user_b, mysql)
    local sql = "SELECT count(*) AS count FROM friends WHERE "
                .. " user_a = " .. user_a .. " AND user_b = " .. user_b .. " AND deleted = 0"
                .. " OR "
                .. " user_a = " .. user_b .. " AND user_b = " .. user_a .. " AND deleted = 0"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("database err: %s", err)
    end

    if #dbres == 0 then 
        return false
    end
    if tonumber(dbres[1].count) ~= 1 then 
        return false
    end

    return true
end

function SocialAction:addfriendAction(args)
    local data = args.data
    local target_id = data.target_id
    local notes = data.notes
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not target_id then
        cc.printinfo("argument not provided: \"target_id\"")
        result.data.msg = "target_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end


    local instance = self:getInstance()
    local mysql = instance:getMysql()
    if _are_friends(instance:getCid(), target_id, mysql) then
        result.data.state = Constants.Error.LogicError
        result.data.msg = "user " .. target_id .. " is already friend of user " .. instance:getCid()
        return result
    end

    local sql = "INSERT INTO friend_request (from_user, to_user, notes ) "
                      .. " VALUES (" .. instance:getCid() .. ", " .. target_id .. ", " .. instance:sqlQuote(notes) .. ") "
                      .. " ON DUPLICATE KEY UPDATE status = 0, notes = " .. instance:sqlQuote(notes)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    result.data.state = 0
    result.data.target_id = target_id
    result.data.msg = "friend requested, target user id: " .. target_id

    -- send to target_id for approval
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "social.friendrequest"}}
    message.data.user_id = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.notes = notes
    online:sendMessage(target_id, json.encode(message), Constants.MessageType.Personal_FriendRequest)

    return result
end

function SocialAction:sendprivatemessageAction(args)
    local data = args.data
    local target_id = data.target_id
    local content_type = data.content_type or "text" -- can be "text" or "voice", voice messages are uploaded as files
    local content = data.content
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not target_id then
        cc.printinfo("argument not provided: \"target_id\"")
        result.data.msg = "target_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT nickname FROM user where id = " .. target_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local target_name = dbres[1].nickname

    -- send message to target user
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "social.privatemessage"}}
    message.data.from_user = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.content = content
    message.data.content_type = content_type
    online:sendMessage(target_id, json.encode(message), Constants.MessageType.Personal_PrivateMessage)

    result.data.state = 0
	result.data.content_type = content_type
    result.data.target_id = target_id
    result.data.target_name = target_name
    result.data.msg = content
    result.data.from_user = instance:getCid()
    result.data.from = instance:getNickname()

    return result
end

function SocialAction:listfriendrequestAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListFriendRequestLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListFriendRequestLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListFriendRequestLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT a.id as user_id, a.phone, a.nickname, b.notes, b.requested_at "
                .. " FROM user a, friend_request b"
                .. " WHERE b.status = 0 "
                .. " AND b.to_user = " .. instance:getCid()
                .. " AND a.id = b.from_user"
                .. " ORDER BY b.requested_at"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    result.data.requests = dbres
    result.data.state = 0
    result.data.offset = offset
    result.data.msg = #dbres .. " requests found"
    return result
end

-- approve or reject friend request
function SocialAction:handlefriendrequestAction(args)
    local data = args.data
    local from_user = data.from_user
    local status = data.status
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not from_user then
        result.data.msg = " from_user not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not status then
        result.data.msg = "status not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if status < 0 or status > 2 then
        result.data.msg = "status must be 0, 1 or 2"
        result.data.state = Constants.Error.LogicError
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " UPDATE friend_request set status = " .. status 
                .. " WHERE from_user = " .. from_user
                .. " AND to_user = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    if tonumber(status) == 1 then
        sql = "INSERT INTO friends (user_a, user_b) "
                          .. " VALUES (" .. instance:getCid() .. ", " .. from_user .. ") "
                          .. " ON DUPLICATE KEY UPDATE deleted = 0"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
    end

    -- send notification to from_user
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "social.friendhandle"}}
    message.data.user_id = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.notes = "user " .. message.data.nickname .. " handled your friend request"
    message.data.status = status
    online:sendMessage(from_user, json.encode(message), Constants.MessageType.Personal_FriendHandled)
     
    result.data.state = 0
    result.data.from_user = from_user
    result.data.msg = "request handled"
    return result
end

-- approve or reject rebuy request
function SocialAction:handlerebuyrequestAction(args)
    local data = args.data
    local game_id = data.game_id
    local amount = data.amount
    local player_id = data.for_player
    local status = data.status
    local msgid = args.__id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        result.data.msg = " game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not amount then
        result.data.msg = "amount not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not player_id then
        result.data.msg = "player_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not status then
        result.data.msg = "status not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if status < 0 or status > 1 then
        result.data.msg = "status must be 0 or 1 "
        result.data.state = Constants.Error.LogicError
        return result
    end

    local instance = self:getInstance()
    local redis = instance:getRedis()

    --  handlerebuyrequestAction is only available for SitAndGo games
    local game_runtime = Game_Runtime:new(instance, redis)
    local game_mode = game_runtime:getGameInfo(game_id, "GameMode")
    cc.printdebug("game_mode: %s", game_mode)
    if tonumber(game_mode) ~= Constants.GameMode.GameModeRingGame then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "handlerebuyrequestAction is only available for SitAndGo games"
        return result
    end
        
    local stake_bought = 0
    if tonumber(status) == 1 then
        local blind_amount = tonumber(game_runtime:getGameInfo(game_id, "BlindAmount"))
        local res = Helper:rebuy(instance, redis, amount, {
                                                    game_id = game_id,
                                                    ignore_stake_left = true,
                                                    blinds_start = blind_amount,
                                                    gold_needed = amount,
                                                    for_player = player_id,
                                                    msgid = msgid
                                                    })
        if res.status ~= 0 then
            result.data.state = Constants.Error.PermissionDenied
            result.data.msg = Constants.ErrorMsg.FailedToBuy .. ": " .. res.err
            return result
        end
        stake_bought = amount
    end

    -- send notification to from_user
    local from_user = player_id
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "game.applyrebuyhandle"}}
    message.data.user_id = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.stake_bought = stake_bought
    message.data.notes = "user " .. message.data.nickname .. " handled your rebuy request"
    message.data.status = status
    online:sendMessage(from_user, json.encode(message), Constants.MessageType.Game_RebuyHandled)
     
    result.data.state = 0
    result.data.from_user = from_user
    result.data.msg = "rebuy request handled"
    return result
end

-- unfriend a friend 
function _unfriend(user_a, user_b, mysql)
    local sql = "UPDATE friends set deleted = 1 WHERE "
                .. " user_a = " .. user_a .. " AND user_b = " .. user_b .. " AND deleted = 0"
                .. " OR "
                .. " user_a = " .. user_b .. " AND user_b = " .. user_a .. " AND deleted = 0"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.throw("database err: %s", err)
    end

    if tonumber(dbres.affected_rows) ~= 1 then 
        return false
    end

    return true
end

function SocialAction:unfriendAction(args)
    local data = args.data
    local target_id = data.target_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not target_id then
        result.data.msg = " target_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    if not _are_friends(instance:getCid(), target_id, mysql) then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "user " .. target_id .. " is not a friend of user " .. instance:getCid()
        return result
    end
    if not _unfriend(instance:getCid(), target_id, mysql) then
        result.data.state = Constants.Error.InternalError
        result.data.msg = "failed to unfriend"
        result.data.target_id = target_id
        return result
    end

    result.data.state = 0
    result.data.msg = "unfriended"
    result.data.target_id = target_id
    return result
end

function SocialAction:listfriendsAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListFriendsLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListFriendsLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListFriendsLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local cid = instance:getCid()
    local sub_sql = "SELECT CASE "
                .. " WHEN user_a = " .. cid .. " THEN user_b " 
                .. " WHEN user_b = " .. cid .. " THEN user_a "
                .. " END AS user_id FROM friends " 
                .. " WHERE user_a = " .. cid 
                .. " OR user_b = " .. cid 
                .. " AND deleted = 0 "
                .. " LIMIT " .. offset .. ", " .. limit
    local sql = "SELECT a.id as user_id, phone, nickname FROM user a JOIN "
                .. "(" .. sub_sql .. ") b ON a.id = b.user_id"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
        
    result.data.state = 0
    result.data.friends = dbres
    result.data.msg = #dbres .. " friends found"
    return result
end

-- private 
_formatmsg = function(message, format)
    format = format or Constants.MESSAGE_FORMAT_JSON
    if type(message) == "table" then
        if format == Constants.MESSAGE_FORMAT_JSON then
            message = json_encode(message)
        else
            -- TODO: support more message formats
        end
    end
    return tostring(message)
end

function SocialAction:invitegameAction(args)
    local data = args.data
    local game_id = data.game_id
    local user_id = data.user_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not game_id then
        cc.printinfo("argument not provided: \"game_id\"")
        result.data.msg = "game_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    if not user_id then
        cc.printinfo("argument not provided: \"user_id\"")
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
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
    local game_name = dbres[1].name
    local game_mode = dbres[1].game_mode
     
    -- send invitation to user
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "social.invitegame"}}
    message.data.sender_id = instance:getCid()
    message.data.sender_phone = instance:getPhone()
    message.data.sender_nickname = instance:getNickname()
    message.data.game_id = game_id
    message.data.game_name = game_name
    message.data.game_mode = game_mode
    message.data.notes = "user " .. message.data.sender_nickname .. " invited you to join game " .. message.data.game_name
    online:sendMessage(user_id, json.encode(message), Constants.MessageType.Club_JoinGameApply)

    result.data.state = 0
    result.data.game_id = game_id
    result.data.user_id = user_id
    result.data.msg = "game invided"
    return result
end

function SocialAction:listunreadmessageAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListUnreadMessage
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListUnreadMessage then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListUnreadMessage .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local club_id_condition  = "(" .. table.concat(instance:getClubIds(mysql), ", ") .. ")"
    local sql = "SELECT SQL_CALC_FOUND_ROWS id as message_id, type, from_id, to_id, sent_at,  content "
                .. " FROM message"
                .. " WHERE is_read = 0 "
                .. " AND ( "
                    .. " to_id =  " .. instance:getCid() 
                    .. " OR (to_id = 0  AND from_id in " .. club_id_condition .. ")" -- club message
                    .. " OR to_id = -1 " -- system broadcase message
                .. ")"  
                .. " AND id NOT IN (" 
                    .. " SELECT message_id AS id FROM message_read WHERE user_id = " .. instance:getCid()
                .. ")"
                .. " ORDER BY sent_at DESC"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    result.data.state = 0
    result.data.offset = offset
    -- decode json string
    local index = 1
    while index <= #dbres do
        local content_str = dbres[index].content
        local content = json_decode(content_str)
        dbres[index].content = content
        
        index = index + 1
    end
    result.data.messages = dbres

    sql = "SELECT FOUND_ROWS() as total_unread"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.total_unread = dbres[1].total_unread
    result.data.msg = result.data.total_unread .. " message(s) unread"

    return result
end

function SocialAction:markasreadAction(args)
    local data = args.data
    local message_id = tonumber(data.message_id)
    local is_read = tonumber(data.is_read) or 1
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not message_id then
        result.data.msg = " message_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " INSERT INTO message_read (message_id, user_id) VALUES ("
                .. message_id .. ","
                .. instance:getCid() .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.message_id = message_id
    result.data.msg = "message " .. message_id .. " is_read marked as " .. is_read
    return result
end
return SocialAction
