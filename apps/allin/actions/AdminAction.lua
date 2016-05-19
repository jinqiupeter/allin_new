local string_split       = string.split
local Constants = cc.import(".Constants", "..")
local gbc = cc.import("#gbc")
local json = cc.import("#json")
local AdminAction = cc.class("AdminAction", gbc.ActionBase)
AdminAction.ACCEPTED_REQUEST_TYPE = "websocket"

-- public methods
function AdminAction:ctor(config)
    AdminAction.super.ctor(self, config)
end

function AdminAction:sendsystembroadcastAction(args)
    local data = args.data
    local content = data.content
    local result = {state_type = "action_state", data = {
        action = args.action}
    }

    local instance = self:getInstance()
    local mysql = instance:getMysql()
    if tonumber(instance:getCid()) ~= -1 then
        cc.printinfo("only admin user can send system broadcast")
        result.data.msg = "only admin user can send system broadcast"
        result.data.state = Constants.Error.PermissionDenied 
        return result
    end

    local online = instance:getOnline()
    local message = {state_type = "server_push", data = {push_type = "system.broadcast"}}
    message.data.message_type = "notification"
    message.data.message = content
    online:sendMessageToAll(json.encode(message))

    result.data.state = 0
    result.data.msg = "message sent"
    return result
end

return AdminAction
