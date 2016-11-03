local string_split       = string.split
local Constants = cc.import(".Constants", "..")
local gbc = cc.import("#gbc")
local json = cc.import("#json")
local ClubAction = cc.class("ClubAction", gbc.ActionBase)
local string_format = string.format
local Helper = cc.import(".Helper", "..")
ClubAction.ACCEPTED_REQUEST_TYPE = "websocket"

-- public methods
function ClubAction:ctor(config)
    ClubAction.super.ctor(self, config)
end

function ClubAction:createclubAction(args)
    local data = args.data
    local name = data.name
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not name then
        cc.printinfo("argument not provided: \"name\"")
        result.data.msg = "name not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    local area = data.area
    if not area then
        cc.printinfo("argument not provided: \"area\"")
        result.data.msg = "area not provided"
        result.data.state = Constants.Error.ArgumentNotSet 
        return result
    end
    local description = data.description
    if not description then
        local nickname = self:getInstance():getNickname()
        description = nickname .. "'s club"
        cc.printinfo("club description set to default: %s", description)
    end


    local instance = self:getInstance()
    local mysql = instance:getMysql()

    -- check max. club limit
    local sql = " SELECT count(*) AS count FROM club WHERE deleted = 0 AND owner_id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local club_count = tonumber(dbres[1].count)
    local club_limit = tonumber(Helper:getSystemConfig(instance, "max_club_per_user"))
    if club_count >= club_limit then 
        result.data.msg = string_format(Constants.ErrorMsg.MaxClubExceeded, club_count, club_limit)
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    -- get next auto increment id
    local club_id, err = instance:getNextId("club")
    if not club_id then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "failed to get next_id for table club, err: %s" .. err
        return result
    end

    -- insert into db
    local sql = "INSERT INTO club (name, area, description, owner_id) "
                      .. " VALUES (" .. instance:sqlQuote(name) .. ", "
                               .. instance:sqlQuote(area) .. ", "
                               ..  instance:sqlQuote(description) .. ", "
                               .. instance:getCid() .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- join the club automatically
    sql = "INSERT INTO user_club (user_id, club_id) "
                      .. " VALUES (" .. instance:getCid() .. ", " .. club_id .. ") "
                      .. " ON DUPLICATE KEY UPDATE deleted = 0"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.club_id = club_id
    result.data.state = 0
    result.data.msg = "club created"
    return result
end

function ClubAction:clubinfoAction(args)
    local data = args.data
    local club_id = data.club_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT c.id , name, owner_id, area, level, level_expiring_on, upgraded_on, active, funds, description, nickname as owner_name" 
                .. " FROM club c, user u WHERE "
                .. " c.id = " .. club_id 
                .. " AND c.owner_id = u.id"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end

    table.merge(result.data, dbres)
    result.data.state = 0
    result.data.msg = "club found"
    return result
end

function ClubAction:listjoinedclubAction(args)
    local data = args.data
    local instance = self:getInstance()
    local user_id = data.user_id or instance:getCid()
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local user_clubs = instance:getClubIds(instance:getMysql())
    local condition = table.concat(user_clubs, ", ")
    local mysql = instance:getMysql()
    local sql = "SELECT a.id, a.name, a.owner_id, a.area, a.funds, a.level, a.description, count(b.user_id) as total_members, " 
                .. " SUM(b.user_id=" .. instance:getCid() .. " AND b.is_admin=1) AS is_admin, "
                .. " u.nickname AS owner_name FROM club a, user_club b, user u "
                .. " WHERE b.deleted = 0 AND "
                .. " a.deleted = 0 AND"
                .. " a.id = b.club_id AND "
                .. " u.id = a.owner_id AND"
                .. " b.club_id in (" .. condition .. " ) group by b.club_id "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local online = instance:getOnline()
    result.data.club_joined = dbres
    local index = 1
    while index <= #result.data.club_joined do
        local found_club_id = result.data.club_joined[index].id 
        
        -- get player count
        local online_count = online:getOnlineClubMemberCount(found_club_id)
        cc.printdebug("online player count for club %s: %s", found_club_id, online_count)
        result.data.club_joined[index].online_count = online_count

        index = index + 1
    end

    result.data.state = 0
    result.data.msg = #dbres .. " club(s) joined"
    return result
end

function ClubAction:leaveclubAction(args)
    local data = args.data
    local club_id = data.club_id

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local joined_clubs = instance:getClubIds(mysql)
    if not table.contains(joined_clubs, tonumber(club_id)) then
        result.data.msg = "you must be a member of the club before you can leave the club: " .. club_id
        result.data.state = Constants.Error.LogicError
        return result
    end

    local sql = "UPDATE user_club SET deleted = 1 "
                .. " WHERE deleted = 0 "
                .. " AND club_id = " .. club_id
                .. " AND user_id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.msg = "club left"
    return result
end

function ClubAction:listclubAction(args)
    local data = args.data
    local keyword = data.keyword
    local limit = data.limit or Constants.Limit.ListClubLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    if not keyword then
        result.data.msg = "keyword not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"keyword\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local word = '%' .. keyword .. '%'
    local sql = "SELECT c.id, name, owner_id, area, description, u.nickname as owner_name" 
                .. " FROM club c, user u WHERE c.owner_id = u.id"
                .. " AND c.id NOT IN (SELECT club_id FROM user_club WHERE user_id = " .. instance:getCid() .. " AND deleted = 0) "
                .. " AND c.deleted = 0"
                .. " AND (c.name LIKE " .. instance:sqlQuote(word) 
                .. " OR c.area LIKE " .. instance:sqlQuote(word) 
                .. " OR c.description LIKE " .. instance:sqlQuote(word) .. ")"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.clubs = dbres
    result.data.offset = offset
    result.data.state = 0
    result.data.msg = #dbres .. " club(s) found"
    return result
end

function ClubAction:listmembersAction(args)
    local data = args.data
    local club_id = data.club_id
    local limit = data.limit or Constants.Limit.ListClubLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT SQL_CALC_FOUND_ROWS u.id as user_id, u.nickname, uc.is_admin, u.last_login " 
                .. " FROM user u, user_club uc WHERE uc.deleted = 0"
                .. " AND uc.user_id = u.id "
                .. " AND uc.club_id = " .. club_id
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end


    result.data.users = dbres
    result.data.offset = offset
    result.data.state = 0

    sql = "SELECT FOUND_ROWS() as found_rows"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.users_found = dbres[1].found_rows
    result.data.msg = result.data.users_found .. " user(s) found"

    return result
end

function ClubAction:joinclubAction(args)
    local data = args.data
    local club_id = data.club_id
    local notes = data.notes or ""
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        cc.printinfo("argument not provided: \"club_id\"")
        return result
    end
    
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT id, owner_id, name FROM club WHERE id =" .. club_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club with club_id ".. club_id .. " not found"
        return result
    end
    local owner_id = dbres[1].owner_id
    local club_name = dbres[1].name

    local joined_clubs = instance:getClubIds(mysql)
    if table.contains(joined_clubs, tonumber(club_id)) then
        result.data.msg = "you have already joined this club: " .. club_id
        result.data.state = Constants.Error.LogicError
        return result
    end

    sql = "INSERT INTO club_application (user_id, club_id, notes ) "
                      .. " VALUES (" .. instance:getCid() .. ", " .. club_id .. ", " .. instance:sqlQuote(notes) .. ") "
                      .. " ON DUPLICATE KEY UPDATE status = 0, notes = " .. instance:sqlQuote(notes)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.msg = "applied"

    -- send to club owner for approval
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "club.application"}}
    message.data.user_id = instance:getCid()
    message.data.phone = instance:getPhone()
    message.data.nickname = instance:getNickname()
    message.data.club_id = club_id
    message.data.club_name = club_name
    message.data.notes = notes
    online:sendMessage(owner_id, json.encode(message), Constants.MessageType.Club_NewMemberApply)

    return result
end

-- a club owner needs to handle club applications
function ClubAction:listapplicationAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListClubApplicationListLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubApplicationListLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubApplicationListLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT a.id as user_id, a.phone, a.nickname, b.id as club_id, b.name as club_name, c.notes, c.applied_at from user a, club b, club_application c "
                .. " WHERE c.status = 0 "
                .. " AND b.id = c.club_id "
                .. " AND a.id = c.user_id "
                .. " AND b.owner_id = " .. instance:getCid()
                .. " ORDER BY b.id"
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    result.data.applications = dbres
    result.data.state = 0
    result.data.offset = offset
    result.data.msg = #dbres .. " applications found"
    return result
end

-- approve or reject the application
function ClubAction:handleapplicationAction(args)
    local data = args.data
    local club_id = data.club_id
    local user_id = data.user_id
    local status = data.status
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not user_id then
        result.data.msg = "user_id not provided"
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

    -- get club name and check if i am owner
    local sql = " SELECT * FROM club WHERE id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local club_name = dbres[1].name
    if tonumber(instance:getCid()) ~= tonumber(dbres[1].owner_id) then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "You are not authorized to handle requests for club " .. club_name
        return result
    end
    local current_level = tonumber(dbres[1].level)
        

    sql = " UPDATE club_application set status = " .. status 
                .. " WHERE user_id = " .. user_id
                .. " AND club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    if status == 1 then
        -- check if max_members exceeds
        sql = "SELECT COUNT(*) AS members_count FROM user_club WHERE club_id = " .. club_id .. " AND deleted = 0"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
        local members_count = tonumber(dbres[1].members_count)

        local level_info = self:_getLevel({level = current_level, mysql = mysql})
        if not level_info.found then
            result.data.state = Constants.Error.NotExist
            result.data.msg = "invalid level: " .. to_level
            return result
        end
        if level_info.max_members + 1 == members_count then -- include owner
            result.data.state = Constants.Error.PermissionDenied
            result.data.msg = string_format(Constants.ErrorMsg.MaxMembersExceeded, members_count, level)
            return result
        end

        sql = "INSERT INTO user_club (user_id, club_id) "
                          .. " VALUES (" .. user_id .. ", " .. club_id .. ") "
                          .. " ON DUPLICATE KEY UPDATE deleted = 0"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
    end
     
    -- send notification to applicant
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "club.clubhandle"}}
    message.data.club_id = club_id
    message.data.club_name = club_name
    message.data.notes = "user " .. instance:getNickname() .. " handled your club request for club " .. message.data.club_name
    message.data.status = status
    online:sendMessage(user_id, json.encode(message), Constants.MessageType.Club_NewMemberHandled)

    result.data.state = 0
    result.data.msg = "application handled"
    return result
end

-- remove a club member
function ClubAction:removememberAction(args)
    local data = args.data
    local club_id = data.club_id
    local user_id = data.user_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " UPDATE user_club set deleted = 1 "
                .. " WHERE user_id = " .. user_id
                .. " AND club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.club_id = club_id
    result.data.user_id = user_id
    result.data.msg = "user " .. user_id .. " removed from club " .. club_id
    return result
end

function ClubAction:disbandclubAction(args)
    local data = args.data
    local club_id = data.club_id
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = " SELECT owner_id FROM club where deleted = 0 and id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local owner_id = dbres[1].owner_id
    if owner_id ~= instance:getCid() then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not owner of club " .. club_id .. ". Only the club owner can disband the club"
        return result
    end

    -- delete the club
    sql = " UPDATE club set deleted = 1 where id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    -- remove all users
    sql = " UPDATE user_club set deleted = 1 where club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.msg = "club " .. club_id .. " disbanded"
    return result
end

function ClubAction:addfundsAction(args)
    local data = args.data
    local club_id = data.club_id
    local amount = tonumber(data.amount)
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not amount then
        result.data.msg = "amount not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
        
    local instance = self:getInstance()
    local mysql = instance:getMysql()
    --[[ SELECT owner_id, nickname, gold FROM club a, user b where deleted = 0 and a.id = 304 and a.owner_id = b.id ]]--
    local sql = " SELECT owner_id, a.funds AS funds_left,  b.gold AS gold FROM club a, user b "
                .. " WHERE a.deleted = 0 AND a.id = " .. club_id
                .. " AND a.owner_id = b.id "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local owner_id = dbres[1].owner_id
    if owner_id ~= instance:getCid() then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not owner of club " .. club_id .. ". Only the club owner can add gold to club funds"
        return result
    end
    local gold_available = tonumber(dbres[1].gold)
    if amount > gold_available then
        result.data.state = Constants.Error.PermissionDenied
        local err_mes = string_format(Constants.ErrorMsg.GoldNotEnoughClubFunds, gold_available, amount)
        result.data.msg = err_mes
        return result
    end
    local funds_left = tonumber(dbres[1].funds_left)

    -- update club funds
    sql = " UPDATE club, user SET club.funds = club.funds + " .. amount 
        .. ", user.gold = user.gold - " .. amount
        .. " WHERE club.id = " .. club_id
        .. " AND club.owner_id = user.id" 
        .. " AND user.id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.funds_before = funds_left
    result.data.funds_after = funds_left + amount
    result.data.owner_gold_before = gold_available
    result.data.owner_gold_after = gold_available - amount
    result.data.msg = "funds updated"
    return result
end

function ClubAction:changeadminAction(args)
    local data = args.data
    local user_id = data.user_id
    local club_id = data.club_id
    local is_admin = tonumber(data.is_admin)
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not user_id then
        result.data.msg = "user_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not is_admin then
        result.data.msg = "is_admin not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()

        
    local sql = " SELECT owner_id, a.funds AS funds_left,  b.gold AS gold FROM club a, user b "
                .. " WHERE a.deleted = 0 AND a.id = " .. club_id
                .. " AND a.owner_id = b.id "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local owner_id = dbres[1].owner_id
    if owner_id ~= instance:getCid() then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "you are not owner of club " .. club_id .. ". Only the club owner can grant or revoke admin"
        return result
    end

    -- check if max_admin for current level exceeds
    if is_admin > 0 then
        local sql = "SELECT a.level, max_admins, sum(c.is_admin = 1) AS admin_count FROM club_level a, club b, user_club c " 
                    .. " WHERE a.level = b.level AND b.id = c.club_id AND b.id = " .. club_id
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
        local max_admin = tonumber(dbres[1].max_admins) + 1 -- include club owner
        local admin_count = tonumber(dbres[1].admin_count)
        local level = tonumber(dbres[1].level)
        if admin_count >= max_admin then 
            result.data.state = Constants.Error.PermissionDenied
            result.data.msg = string_format(Constants.ErrorMsg.MaxAdminExceeded, admin_count, level)
            return result
        end
    end

    -- update is_admin
    sql = " UPDATE user_club SET is_admin =  " .. is_admin 
          .. " WHERE club_id = " .. club_id
          .. " AND user_id = " .. user_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.msg = "is_admin updated"
    return result
end

function ClubAction:listcreatedclubsAction(args)
    local data = args.data
    local limit = data.limit or Constants.Limit.ListClubLimit
    local offset = data.offset or 0
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if limit > Constants.Limit.ListClubLimit then
        result.data.msg = "max number of record limit exceeded, only " .. Constants.Limit.ListClubLimit .. " allowed in one query"
        result.data.state = Constants.Error.PermissionDenied
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    local sql = "SELECT SQL_CALC_FOUND_ROWS a.id AS club_id, a.level, a.name, a.funds, a.area, COUNT(b.user_id) AS user_count FROM club a, user_club b "
                .. " WHERE a.id = b.club_id AND a.owner_id = " .. instance:getCid() 
                .. " AND b.deleted = 0"
                .. " group by a.id "
                .. " LIMIT " .. offset .. ", " .. limit
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end


    result.data.clubs = dbres
    result.data.offset = offset
    result.data.state = 0

    sql = "SELECT FOUND_ROWS() as found_rows"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    result.data.clubs_found = dbres[1].found_rows
    result.data.msg = result.data.clubs_found .. " club(s) found"

    return result
end

function ClubAction:_getLevel(args)
    local level = args.level
    local mysql = args.mysql

    local sql = "SELECT level, monthly_fee, max_members, max_admins FROM club_level WHERE level = " .. level
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return {found = false, err = "db err: " .. err}
    end
    
    return {found = true, level = dbres[1].level,
                          monthly_fee = dbres[1].monthly_fee,
                          max_members = dbres[1].max_members,
                          max_admins = dbres[1].max_admins
    }
end

function ClubAction:charge_monthly_fee(args) 
    local instance = args.instance
    local club_id = args.club_id
    local to_level = args.to_level
    local months = args.months or 1
    local count_months_left = args.count_months_left
    local mysql = instance:getMysql()

    local start_date
    local msg

    local sql = "SELECT a.gold, b.owner_id, b.level_expiring_on FROM user a, club b "
            .. " WHERE a.id = b.owner_id "
            .. " AND b.id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return {charged = 0, msg = err}
    end
    local gold_available = tonumber(dbres[1].gold)
    local owner_id = tonumber(dbres[1].owner_id)
    local expiring_on = dbres[1].level_expiring_on

    -- get monthly fee for target level
    local sql = "SELECT monthly_fee FROM club_level WHERE level = " .. to_level
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return {charged = 0, msg = err}
    end
    local fee = tonumber(dbres[1].monthly_fee)
    local to_charge = fee * months

    if count_months_left ~= 0 then
        start_date = instance:sqlQuote(expiring_on);
    else
        start_date = 'now()';
    end

    if owner_id ~= instance:getCid() then
        msg = "user " .. instance:getCid() .. "  is not owner of club " .. club_id
        return {charged = 0, msg = msg}
    elseif gold_available < to_charge then
        msg = string_format(Constants.ErrorMsg.GoldNotEnoughClubMonthlyFee, gold_available, to_charge)
        return {charged = 0, msg = msg}
    else 
        local sql = " UPDATE user , club  SET user.gold = user.gold - " .. to_charge
              .. " , club.level = " .. to_level 
              .. " , club.level_expiring_on = " .. start_date .. " +  interval " .. months .. " month"
              .. " , club.upgraded_on = now()"
              .. " WHERE user.id = ".. instance:getCid()
              .. " ANd club.id = " .. club_id
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("database err: " .. err)
            return {charged = 0, msg = err}
        end
    end

    return {charged = 1, msg = "charged " .. to_charge, gold_charged = to_charge}
end

function ClubAction:changelevelAction(args)
    local data = args.data
    local club_id = tonumber(data.club_id)
    local to_level = tonumber(data.to_level)
    local months = data.months or 1
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    local instance = self:getInstance()
    local mysql = instance:getMysql()

        
    local sql = "SELECT a.level AS current_level, count(b.user_id) as total_members FROM club a, user_club b"
                .. " WHERE a.id = " .. club_id
                .. " AND b.club_id = a.id "
                .. " AND b.deleted = 0 "
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local current_level = tonumber(dbres[1].current_level)
    local total_members = tonumber(dbres[1].total_members)

    if not to_level then
        to_level = current_level
    end
    local count_months_left = 0
    if to_level == current_level then
        count_months_left = 1
    end

    -- check if to_level is defined
    local level_info = self:_getLevel({level = to_level, mysql = mysql})
    if not level_info.found then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "invalid level: " .. to_level
        return result
    end

    -- check if current total members is greater than max members of to_level
    if level_info.max_members < total_members then
        result.data.state = Constants.Error.NotExist
        result.data.msg = string_format(Constants.ErrorMsg.CurrentMembersMoreThanTarget, total_members, to_level, level_info.max_members)
        return result
    end

    -- charge monthly fee
    local retval = self:charge_monthly_fee({instance = instance, club_id = club_id, to_level = to_level, months = months, count_months_left = count_months_left})
    if retval.charged == 0 then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = retval.msg
        return result
    end

    result.data.state = 0
    result.data.gold_charged = retval.gold_charged
    result.data.msg = retval.msg

    return result
end

function ClubAction:transferfundsAction(args)
    local data = args.data
    local club_id = tonumber(data.club_id)
    local to_user = tonumber(data.to_user)
    local amount = tonumber(data.amount)
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not to_user then
        result.data.msg = "to_user t provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not amount then
        result.data.msg = "amount not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()

    -- check if to_user is memeber of club_id
    local sql = " SELECT SUM(deleted = 0 AND user_id = " .. to_user
                .. ") AS is_member FROM user_club WHERE club_id = " .. club_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if tonumber(dbres[1].is_member) == 0 then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = "user " .. to_user .. " is not member of club " .. club_id
        return result
    end

    -- check if i am admin
    local isadmin = Helper:isClubAdmin(instance, {club_id = club_id})
    if not isadmin then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = Constants.ErrorMsg.YouAreNotAdmin
        return result
    end

    -- check available club funds
    local sql = " SELECT funds FROM  club WHERE "
                .. " id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if next(dbres) == nil then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club not found: " .. club_id
        return result
    end
    local funds = tonumber(dbres[1].funds)
    if amount > funds then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = string_format(Constants.ErrorMsg.FundsNotEnough, funds)
        return result
    end

    sql = " UPDATE user , club  SET user.gold = user.gold + " .. amount
          .. " , club.funds = club.funds - " .. amount 
          .. " WHERE user.id = ".. to_user 
          .. " ANd club.id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.msg = "funds transfered"
    result.data.to_user = to_user
    result.data.amount = amount

    return result
end

function ClubAction:updatesettingAction(args)
    local data = args.data
    local club_id = tonumber(data.club_id)
    local newgame_control = tonumber(data.newgame_control)
    local allow_msg = tonumber(data.allow_msg)
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not newgame_control then
        result.data.msg = "newgame_control not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not allow_msg then
        result.data.msg = "allow_msg not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if newgame_control ~= 0 and newgame_control ~= 1 then
        result.data.msg = "newgame_control must be 0 or 1 "
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if allow_msg ~= 0 and allow_msg ~= 1 then
        result.data.msg = "allow_msg must be 0 or 1 "
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()

    local is_owner = Helper:isClubOwner(instance, {club_id = club_id})
    if not is_owner then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = Constants.ErrorMsg.YouAreNotOwner
        return result
    end

    local sql = " UPDATE club set newgame_control = " .. newgame_control
                .. " , allow_msg = " .. allow_msg
                .. " WHERE id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    result.data.state = 0
    result.data.msg = "club setting udpated"
    result.data.allow_msg = allow_msg
    result.data.newgame_control = newgame_control
    result.data.club_id = club_id

    return result
end

function ClubAction:announceAction(args)
    local data = args.data
    local club_id = tonumber(data.club_id)
    local announcement = data.announcement
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not club_id then
        result.data.msg = "club_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not announcement then
        result.data.msg = "announcement not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local instance = self:getInstance()
    local mysql = instance:getMysql()

    local sql = "SELECT id, owner_id, name FROM club WHERE id =" .. club_id 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
     
    if #dbres == 0 then
        result.data.state = Constants.Error.NotExist
        result.data.msg = "club with club_id ".. club_id .. " not found"
        return result
    end
    local club_name = dbres[1].name

    -- check if i am admin
    local isadmin = Helper:isClubAdmin(instance, {club_id = club_id})
    if not isadmin then
        result.data.state = Constants.Error.PermissionDenied
        result.data.msg = Constants.ErrorMsg.YouAreNotAdmin
        return result
    end

    -- send to club owner for approval
    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "club.announcement"}}
    message.data.club_id = club_id
    message.data.club_name = club_name
    message.data.announcement = announcement
    online:sendClubMessage(club_id, json.encode(message), Constants.MessageType.Club_Annoucement)

    result.data.state = 0
    result.data.msg = "announcement sent"
    result.data.announcement = announcement

    return result
end

return ClubAction
