local string_format = string.format

local json = cc.import("#json")
local json_encode = json.encode
local json_decode = json.decode
local gbc = cc.import("#gbc")
local inspect = require("inspect")

local chunk_size = 4096
local Uploader = cc.class("Uploader")

local upload = require "resty.upload"
local chunk_size = 4096
local Mysql = require("resty.mysql")

local form, err = upload:new(chunk_size)
if not form then
    ngx.log(ngx.ERR, "failed to new upload: ", err)
    ngx.exit(500)
end

function getMysql(name) 
    local mysql, err = Mysql:new()
    if not mysql then
        return nil, "failed to init mysql: " .. err
    end

    local ok, err, errno, sqlstate = mysql:connect {
                                     path = "/var/mysqld/mysqld.socket",
                                     database = "allin",
                                     user = "allindbu",
                                     password = "Allin123" }
    if not ok then
        return nil, "failed to connect to mysql: " .. err
    end

    return mysql
end

function checkSession(user_id, session)
    if not user_id then
        return nil, "user_id not provided"
    end
    if not session then
        return nil, "session not provided"
    end

    local mysql, err = getMysql()
    if not mysql then
        return nil, "failed to init mysql: " .. err
    end
    
    local sql = "select session from user where id = " .. user_id
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return nil, "db err: " .. err
    end
    if next(dbres) == nil then
        return nil, "user with id: " .. user_id .. " not found"
    end

    local session_found = dbres[1].session
    if session_found ~= session then
        return nil, "session didnot match"
    end

    return true, "matched"
end

function checkOwner(user_id, club_id)
    if not user_id then
        return nil, "user_id not provided"
    end
    if not club_id then
        return nil, "club_id not provided"
    end

    local mysql, err = getMysql()
    if not mysql then
        return nil, "failed to init mysql: " .. err
    end
    
    local sql = "select club_id from user_club where user_id = " .. user_id
    local dbres, err, errno, sqlstate = mysql:query(sql)
    if not dbres then
        return nil, "db err: " .. err
    end
    if next(dbres) == nil then
        return nil, "user_id " .. user_id .. " and club_id " .. club_id .. " didnot matched"
    end
    local i = 1
    while dbres[i] ~= nil do
        if tonumber(dbres[i].club_id) == tonumber(club_id) then
            return true, "matched"
        end

        i = i + 1
    end

    return nil, "user_id " .. user_id .. " and club_id " .. club_id .. " didnot matched"
end
--[[
function getUserInfo(res)
    local found = ngx.re.match(res,'{{%s*user_id%s*=%s*(.+)%s*,%s*session%s*=%s*(.+)%s*}}')
    if found then
        return found[1], found[2]
    end
end
--]]

function uploadfile(path, args)
    local file = nil
    local authed = true
    local err
    local filepath = path
    local filename = args.filename or ""

    while true do
        local typ, res, err = form:read()
        if not typ then
            ngx.say("failed to read form: " .. err)
            return
        end

        local inspect = require("inspect")
        if typ == "header" then
            if res[1] ~= "Content-Type" then
                if args.check_user then
                    authed, err = checkSession(args.user_id, args.session)
                elseif args.check_owner then
                    authed, err = checkOwner(args.user_id, args.club_id)
                end
                if authed then
                    file, err = io.open(filepath,"w+")
                    if not file then
                        ngx.say("failed to open file: " .. filepath, " err: " .. err)
                        return
                    end
                else
                    ngx.say("auth failed: " .. err)
                    return
                end
            end
        elseif typ == "body" then
            if file then
                file:write(res)
            end
        elseif typ == "part_end" then
            if file then
                file:close()
                file = nil
                break
            end
        elseif typ == "eof" then
            break
        end
        ngx.say("read: ", inspect({typ, res})) 
    end
    
    if not err then
        ngx.say( filename .." uploaded")
    end

end

function uploadProfile()
    local user_id = ngx.var.arg_user_id
    local session = ngx.var.arg_session
    local filename = ngx.var.arg_filename or "".. user_id .. ".png"
    local filepath = "allin_root/profile/" .. filename 
    
    uploadfile(filepath, {check_user = true, 
                          user_id = user_id, 
                          session = session, 
                          filename = filename}
                          )
end

function uploadAudio()
    local filename = ngx.var.arg_filename

    ngx.say("filename : " , filename)
    if not filename then
        ngx.say("filename not provided")
        return
    end

    local filepath = "allin_root/audio/" .. filename
    
    uploadfile(filepath, { filename = filename})
end

function uploadClub()
    local club_id = ngx.var.arg_club_id
    local user_id = ngx.var.arg_user_id
    local typ     = ngx.var.arg_type  -- badge or banner

    if not club_id then
        ngx.say("club_id not provided")
        return
    end

    if not typ then
        ngx.say("type not provided")
        return
    end
    local filename = ngx.var.arg_filename or "".. club_id .. ".png"

    local filepath = "allin_root/club/" .. typ .. "/" .. filename
    
    uploadfile(filepath, {check_owner = true, 
                          user_id = user_id,
                          club_id = club_id,
                          filename = filename}
                          )
end

return Uploader
