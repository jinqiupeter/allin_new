--[[

Copyright (c) 2015 gameboxcloud.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

]]

local string_format = string.format

local json = cc.import("#json")
local gbc = cc.import("#gbc")

local Online = cc.class("Online")

local _ONLINE_SET        = "_ONLINE_USERS"
local _ONLINE_SET_CLUB        = _ONLINE_SET .. "_"
local _ONLINE_CHANNEL    = "_ONLINE_CHANNEL"
local _EVENT = table.readonly({
    ADD_USER    = "ADD_USER",
    REMOVE_USER = "REMOVE_USER",
})
local _CONNECT_TO_USERNAME = "_CONNECT_TO_USERNAME"
local _USERNAME_TO_CONNECT = "_USERNAME_TO_CONNECT"

function Online:ctor(instance)
    self._instance  = instance
    self._redis     = instance:getRedis()
    self._mysql     = instance:getMysql()
    self._broadcast = gbc.Broadcast:new(self._redis, instance.config.app.websocketMessageFormat)
end

function Online:getAll()
    return self._redis:smembers(_ONLINE_SET)
end

function Online:getClubMembers(club_id)
    return self._redis:smembers(_ONLINE_SET_CLUB .. club_id)
end

function Online:getOnlineClubMemberCount(club_id)
    return self._redis:scard(_ONLINE_SET_CLUB .. club_id)
end

function Online:addToClub(user_id, club_id)
    local redis = self._redis
    redis:initPipeline()
    redis:sadd(_ONLINE_SET_CLUB .. club_id, user_id)
    return redis:commitPipeline()
end

function Online:removeFromClub(user_id, club_id)
    local redis = self._redis
    redis:initPipeline()
    redis:srem(_ONLINE_SET_CLUB .. club_id, user_id)
    return redis:commitPipeline()
end

function Online:add(username, connectId)
    local redis = self._redis
    redis:initPipeline()
    -- map username <-> connect id
    redis:hset(_CONNECT_TO_USERNAME, connectId, username)
    redis:hset(_USERNAME_TO_CONNECT, username, connectId)
    -- add username to set
    redis:sadd(_ONLINE_SET, username)

    -- send event to all clients
    redis:publish(_ONLINE_CHANNEL, json.encode({name = _EVENT.ADD_USER, username = username}))
    redis:commitPipeline()
    return
end

function Online:isOnline(user_id)
    local redis = self._redis
    local connectId, err = redis:hget(_USERNAME_TO_CONNECT, user_id)
    if not connectId then
        return false
    end
    if connectId == redis.null then
        return false
    end

    return connectId ~= nil
end

function Online:remove(username)
    local redis = self._redis
    local connectId, err = redis:hget(_USERNAME_TO_CONNECT, username)
    if not connectId then
        return nil, err
    end
    if connectId == redis.null then
        return nil, string_format("not found username '%s'", username)
    end

    redis:initPipeline()
    -- remove map
    redis:hdel(_CONNECT_TO_USERNAME, connectId)
    redis:hdel(_USERNAME_TO_CONNECT, username)
    -- remove username from set
    redis:srem(_ONLINE_SET, username)
    redis:publish(_ONLINE_CHANNEL, json.encode({name = _EVENT.REMOVE_USER, username = username}))
    local res, err = redis:commitPipeline()
    if not res then
        return nil, err
    end

    return self._broadcast:sendControlMessage(connectId, gbc.Constants.CLOSE_CONNECT)
end

function Online:getChannel()
    return _ONLINE_CHANNEL
end

function Online:sendMessage(recipient, event, message_type, club_id)
    local redis = self._redis
    local instance = self._instance

    if self:isOnline(recipient) then 
        cc.printdebug("sending message to online user %s: %s", recipient, event)
        -- user is online, send directly
        -- query connect id by recipient
        local connectId, err = redis:hget(_USERNAME_TO_CONNECT, recipient)
        if not connectId then
            return nil, err
        end
        if connectId == redis.null then
            return nil, string_format("not found recipient '%s'", recipient)
        end
        -- send message to connect id
        return self._broadcast:sendMessage(connectId, event)

    else 
        -- user is offline,  save to offline message
        cc.printdebug("saving message to offline user %s: %s", recipient, event)
        local mysql = self._mysql
        local from_id = instance:getCid()
        if recipient == 0 and club_id ~= nil then
            from_id = club_id
        end
            
        local typ = message_type or -1
        local sql = "INSERT INTO message (type, from_id, to_id, content) VALUES ( "
                .. typ .. ", "
                .. from_id .. ", "
                .. recipient .. ", "
                .. instance:sqlQuote(event) .. ")"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            return nil, err
        end
    end
end

function Online:sendClubMessage(club_id, message, messageType)
    local message_id, err = self._instance:getNextId("message")
    if not message_id then
        cc.printdebug("Failed to get next id for table: message")
        return nil
    end

    -- there will be only 1 message inserted for club_messages
    self:sendMessage(0, message, messageType, club_id)

    -- online club members
    local members = self:getClubMembers(club_id)
    local mysql = self._mysql
    for key, value in pairs(members) do
        cc.printdebug("sending message to user %s", value, messageType)
        self:sendMessage(value, message, messageType)

        -- make messages as read for online users
        local sql = "INSERT INTO message_read (message_id, user_id) VALUES ( "
                .. message_id .. ", "
                .. value .. ")"
        cc.printdebug("executing sql: %s", sql)
        local dbres, err, errno, sqlstate = mysql:query(sql)
        if not dbres then
            cc.printdebug("DB error: %s", err)
            return nil, err
        end
    end
end

function Online:sendMessageToAll(event)
    return self._broadcast:sendMessageToAll(event)
end

return Online
