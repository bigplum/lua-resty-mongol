module("resty.mongol", package.seeall)

local mod_name = (...)

local assert , pcall = assert , pcall
local ipairs , pairs = ipairs , pairs
local setmetatable = setmetatable

local socket = ngx.socket.tcp

local connmethods = { }
local connmt = { __index = connmethods }

local dbmt = require ( mod_name .. ".dbmt" )
local bson = require ( mod_name .. ".bson" )
null = bson.bson_null

function connmethods:ismaster()
    local db = self:new_db_handle("admin")
    local r, err = db:cmd({ismaster = true}) 
    if not r then
        return nil, err
    end
    return r.ismaster, r.hosts
end

local function parse_host ( str )
    local host , port = str:match ( "([^:]+):?(%d*)" )
    port = port or 27017
    return host , port
end

function connmethods:getprimary ( searched )
    searched = searched or { [ self.host .. ":" .. self.port ] = true }

    local db = self:new_db_handle("admin")
    local r, err = db:cmd({ ismaster = true })
    if not r then
        return nil, "query admin failed: "..err
    elseif r.ismaster then return self 
    else
        for i , v in ipairs ( r.hosts ) do
            if not searched[v] then
                searched[v] = true
                local host, port = parse_host(v)
                local conn = new()
                local ok, err = conn:connect(host, port)
                if not ok then
                    return nil, "connect failed: "..err..v
                end

                local found = conn:getprimary(searched)
                if found then
                    return found
                end
            end
        end
    end
    return nil , "No master server found"
end

function connmethods:databases()
    local db = self:new_db_handle("admin")
    local r = assert ( db:cmd({ listDatabases = true } ))
    return r.databases
end

function connmethods:shutdown()
    local db = self:new_db_handle("admin")
    db:cmd({ shutdown = true } )
end

function connmethods:new_db_handle ( db )
    if not db then
        return nil
    end

    return setmetatable ( {
            conn = self ;
            db = db ;
        } , dbmt )
end

function connmethods:set_timeout(timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end

function connmethods:set_keepalive(...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:setkeepalive(...)
end

function connmethods:get_reused_times()
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end

function connmethods:connect(host, port)
    self.host = host or self.host
    self.port = port or self.port
    local sock = self.sock

    return sock:connect(self.host, self.port)
end

function connmethods:close()
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:close()
end

connmt.__call = connmethods.new_db_handle

function new(self)
    return setmetatable ( {
            sock = socket();
            host = "localhost";
            port = 27017;
        } , connmt )
end

-- to prevent use of casual module global variables
getmetatable(resty.mongol).__newindex = function (table, key, val)
    error('attempt to write to undeclared variable "' .. key .. '": '
            .. debug.traceback())
end
