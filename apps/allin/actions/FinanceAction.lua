local string_split       = string.split
local Constants = cc.import(".Constants", "..")
local gbc = cc.import("#gbc")
local json = cc.import("#json")
local json_encode = json.encode
local json_decode = json.decode
local uuid_generator = cc.import("#uuid")
local http = require("resty/http")
local httpc = http.new()
local FinanceAction = cc.class("FinanceAction", gbc.ActionBase)
FinanceAction.ACCEPTED_REQUEST_TYPE = "websocket"

-- public methods
function FinanceAction:ctor(config)
    FinanceAction.super.ctor(self, config)
end

function FinanceAction:requestorderidAction(args)
    local data = args.data
    local product_name = data.product_name
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT count(*) AS count FROM iap_product WHERE name = " .. instance:sqlQuote(product_name)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if tonumber(dbres[1].count) ~= 1 then
        result.data.msg = "Product " .. product_name .. " not found"
        result.data.state = Constants.Error.NotExist 
        return result
    end

    local uuid = uuid_generator();
    sql = "INSERT INTO iap_order (user_id, product_name, uuid) VALUES ( "
          .. user_id .. ", "
          .. instance:sqlQuote(product_name) .. ", "
          .. instance:sqlQuote(uuid) .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    
    result.data.state = 0
    result.data.product_name = product_name
    result.data.order_id = uuid
    return result
end

function FinanceAction:verifyreceiptAction(args)
    local data = args.data
    local order_id = data.order_id
    local receipt = data.receipt
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    if not order_id then
        result.data.msg = "order_id not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end
    if not receipt then
        result.data.msg = "receipt not provided"
        result.data.state = Constants.Error.ArgumentNotSet
        return result
    end

    local instance = self:getInstance()
    local user_id = instance:getCid()
    local mysql = instance:getMysql()
    local sql = "SELECT uuid, user_id FROM iap_order WHERE uuid = " .. instance:sqlQuote(order_id)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if not dbres[1].uuid  then
        result.data.msg = "Invalid order id: " .. order_id
        result.data.state = Constants.Error.NotExist 
        return result
    end

    sql = "SELECT count(*) AS count from iap_receipt WHERE "
          .. "uuid = " .. instance:sqlQuote(order_id) 
          .. "AND valid = 1"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    if tonumber(dbres[1].count) == 1 then
        result.data.msg = "receipt already verified"
        result.data.state = Constants.Error.PermissionDenied 
        return result
    end

    sql = "INSERT INTO iap_receipt (user_id, receipt, uuid) VALUES ( "
          .. user_id .. ", "
          .. instance:sqlQuote(receipt) .. ", "
          .. instance:sqlQuote(order_id) .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    
    local inspect = require("inspect")
    local url = "https://sandbox.itunes.apple.com/verifyReceipt"
    local body = { ["receipt-data"] = receipt }
    local json_body = json_encode(body)
    local verification_result, err = httpc:request_uri(url, {
        method = "POST",
        ssl_verify = false,
        body = json_body,
    })
    
    local decoded_body = json_decode(verification_result.body)
    cc.printdebug("receipt verification status: %s", decoded_body.status)
    -- alwasy update iap_receipt.verified = 1 no matter if receipt is valid or not
    if not err then local sql = "UPDATE iap_receipt set verified = 1 WHERE uuid = " ..instance:sqlQuote(order_id)
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            result.data.state = Constants.Error.MysqlError
            result.data.msg = "数据库错误: " .. err
            return result
        end
    end

    local valid = 0
    if tonumber(decoded_body.status) == 0 then
        valid = 1
    else
        cc.printdebug("verification_result: %s", inspect(body))
        result.data.state = 0
        result.data.is_valid = valid
        result.data.order_id = order_id
        result.data.verification_result = body
        result.data.msg = "is valid: " .. valid
        return result
    end
    
    -- update iap_receipt.valid
    local sql = "UPDATE iap_receipt set valid = " .. valid .. " WHERE uuid = " ..instance:sqlQuote(order_id)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- how much gold was bought
    local sql = "SELECT ip.gold FROM iap_product ip, iap_order io WHERE ip.name = io.product_name AND io.uuid = " .. instance:sqlQuote(order_id)
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local gold_bought = dbres[1].gold

    -- create record in iap
    local sql = "INSERT INTO iap (user_id, order_id, gold_bought) VALUES ( "
          .. user_id .. ", "
          .. instance:sqlQuote(order_id) .. ", "
          .. gold_bought .. ")"
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    -- update user.gold
    local sql = "UPDATE user set gold = gold + " .. gold_bought .. " WHERE id = " ..instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end

    local sql = "SELECT gold FROM user WHERE id = " ..instance:getCid()
    cc.printdebug("executing sql: %s", sql)
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        result.data.state = Constants.Error.MysqlError
        result.data.msg = "数据库错误: " .. err
        return result
    end
    local gold_available = dbres[1].gold
    
    result.data.state = 0
    result.data.is_valid = valid
    result.data.order_id = order_id
    result.data.gold_available = gold_available
    result.data.msg = "is valid: " .. valid
    return result
end

return FinanceAction
