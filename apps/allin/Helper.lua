local Helper = cc.class("Helper")

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

return Helper
