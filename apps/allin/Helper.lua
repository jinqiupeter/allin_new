local Helper = cc.class("Helper")
local Constants = cc.import(".Constants")
local string_split       = string.split
local string_format = string.format
local Game_Runtime = cc.import("#game_runtime")
local User_Runtime = cc.import("#user_runtime")

function Helper:getSystemConfig(instance, config_name)
    local mysql = instance:getMysql()
    if not mysql then
        cc.throw("not connected to mysql")
    end

    local sql = "SELECT CONVERT(SUBSTRING_INDEX(value,'-',-1),UNSIGNED INTEGER) AS value " 
                .. " FROM config WHERE name = " .. instance:sqlQuote(config_name) 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return nil
    end
    if next(dbres) == nil then
        return nil
    end
    
    return dbres[1].value;
end

function Helper:getStakeLeft(instance, args)
    local mysql = instance:getMysql()
    local game_id = args.game_id    

    local stake_left = 0

    local sql = "SELECT stake_available FROM buying WHERE "
         .. " game_id = " .. game_id 
         .. " AND user_id = " .. instance:getCid()
         .. " ORDER BY bought_at DESC LIMIT 1"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return 0
    end
    if #dbres ~= 0 then
        stake_left = tonumber(dbres[1].stake_available)
    end

    return stake_left
end

function Helper:buyStake(instance, required_stake, args)
    local required_stake = tonumber(required_stake)
    local mysql = instance:getMysql()
    local game_id = args.game_id    
    local blinds_start = args.blinds_start
    local gold_needed = args.gold_needed
    local ignore_stake_left = args.ignore_stake_left

    local sql = "SELECT stake_available FROM buying WHERE "
         .. " game_id = " .. game_id 
         .. " AND user_id = " .. instance:getCid()
         .. " ORDER BY bought_at DESC LIMIT 1"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end
    local stake_left = self:getStakeLeft(instance, {game_id = game_id})
    if not ignore_stake_left then
        -- user has already joined the game, take stake left
        cc.printdebug("stake_left: %s, blinds_start: %s", stake_left, blinds_start)
        if (tonumber(stake_left) > tonumber(blinds_start)) then
            cc.printdebug("stake left is larger than blinds_start, no need to buy")
            return {status = 0, stake_bought = stake_left}
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
    -- update user.gold
    local service_fee = gold_needed * 0.2
    if service_fee < 100 then
        service_fee = 100
    end
    local gold_to_charge = gold_needed + service_fee
    if gold_available < gold_to_charge then
        local err_mes = string_format(Constants.ErrorMsg.GoldNotEnough, gold_available, gold_to_charge)
        return {status = 1, stake_bought = 0, err = "err: " .. err_mes}
    end

    sql = "UPDATE user SET gold = " .. gold_available - gold_to_charge .. " WHERE id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end
    
    -- create record in buying
    sql = "INSERT INTO buying (user_id, game_id, gold_spent, stake_bought, stake_available ) "
          .. " VALUES ( " .. instance:getCid() .. ", "
          .. game_id .. ", "
          .. gold_needed .. ", "
          .. required_stake .. ", "
          .. tonumber(required_stake) + tonumber(stake_left).. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {status = 1, stake_bought = 0, err = "db err: " .. err}
    end

    return {status = 0, stake_bought = required_stake}
end

function Helper:buyTime(instance, args)
    local mysql = instance:getMysql()
    local purchase_count = args.purchase_count

    local config_name = "timeout_price_in_gold_1st"
    if tonumber(purchase_count) >= 1 then
        config_name = "timeout_price_in_gold_2nd"
    end
    local timeout_price = tonumber(Helper:getSystemConfig(instance, config_name))

    local sql = "SELECT gold FROM user where id = " .. instance:getCid() 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {bought = false, err = "db err: " .. err}
    end
    local gold_available = tonumber(dbres[1].gold)
    -- update user.gold
    local gold_to_charge = timeout_price
    if gold_available < gold_to_charge then
        local err_mes = string_format(Constants.ErrorMsg.GoldNotEnoughTime, gold_available, gold_to_charge)
        return {bought = false, err = "err: " .. err_mes}
    end

    sql = "UPDATE user SET gold = " .. gold_available - gold_to_charge .. " WHERE id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {bought = false, err = "db err: " .. err}
    end
    
    return {bought = true}
end

function Helper:buyAnimation(instance, animation_name)
    local mysql = instance:getMysql()

    local sql = "SELECT name, name_cn, price FROM animation WHERE "
         .. " name = " .. instance:sqlQuote(animation_name)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {bought = false, err = "db err: " .. err}
    end
    local price = 0
    if #dbres ~= 0 then
        price = tonumber(dbres[1].price)
    end

    local sql = "SELECT gold FROM user where id = " .. instance:getCid() 
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {bought = false, err = "db err: " .. err}
    end
    local gold_available = tonumber(dbres[1].gold)
    -- update user.gold
    local gold_to_charge = price
    if gold_available < gold_to_charge then
        local err_mes = string_format(Constants.ErrorMsg.GoldNotEnoughAnimation, gold_available, gold_to_charge)
        return {bought = false, err = "err: " .. err_mes}
    end

    sql = "UPDATE user SET gold = " .. gold_available - gold_to_charge .. " WHERE id = " .. instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        cc.printdebug("db err: %s", err)
        return {bought = false, err = "db err: " .. err}
    end
    
    return {bought = true, err = "animation bought successfully"}
end

function Helper:isClubAdmin(instance, args)
    local mysql = instance:getMysql()
    local club_id = args.club_id

    -- check if i am admin
    local sql = " SELECT a.is_admin, b.owner_id FROM user_club a, club b "
                .. " WHERE a.club_id = b.id"
                .. " AND b.deleted = 0 "
                .. " AND a.user_id = " .. instance:getCid() 
                .. " AND a.club_id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return false;
    end
    if next(dbres) == nil then
        return false;
    end
    local is_admin = tonumber(dbres[1].is_admin)
    local owner_id = tonumber(dbres[1].owner_id)
    if is_admin == 0 and owner_id ~= instance:getCid() then
        return false;
    end

    return true;
end

function Helper:isClubOwner(instance, args)
    local mysql = instance:getMysql()
    local club_id = args.club_id

    -- check if i am owner of a club
    local sql = " SELECT owner_id FROM club WHERE id = " .. club_id
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return false;
    end
    if next(dbres) == nil then
        return false;
    end
    local owner_id = tonumber(dbres[1].owner_id)
    if owner_id ~= instance:getCid() then
        return false;
    end

    return true;
end

function Helper:_getBetRound(instance, redis, game_id, table_id)
    local game_runtime = Game_Runtime:new(instance, redis)
    local table_betround = game_runtime:getGameInfo(game_id, "TableBetround_" .. table_id)
    local betround = -1
    if table_betround ~= nil then
        local info = string_split(table_betround, ":")
        betround = info[2]
    end
     
    return betround
end

function Helper:rebuy(instance, redis, required_stake, args)
    local game_id = args.game_id
    local res = self:buyStake(instance, required_stake, {
                                                game_id = args.game_id,
                                                ignore_stake_left = args.ignore_stake_left,
                                                blinds_start = args.blind_amount,
                                                gold_needed = args.gold_needed
                                                })
    if res.status ~= 0 then
        return {status = Constants.Error.PermissionDenied, err = res.err}
    end
    local rebuy_stake = res.stake_bought

    local msgid = args.msgid or 0
    local player_id = args.for_player or instance:getCid()
    local message = msgid .. " REBUY " .. game_id .. " " .. rebuy_stake .. " " .. player_id .."\n";
    cc.printdebug("sending message to allin server: %s", message)
    local allin = instance:getAllin()

    local bytes, err = allin:sendMessage(message)
    if not bytes then
        return {status = Constants.Error.AllinError, err = err}
    end 

    -- increase rebuy account
    local user_runtime = User_Runtime:new(instance, redis)
    local rebuy_count = tonumber(user_runtime:getRebuyCount(game_id)) or 0
    user_runtime:setRebuyCount(game_id, rebuy_count + 1)

    return {status = 0, stake_bought = rebuy_stake}
end

return Helper
