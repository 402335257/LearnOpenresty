local ngx = require 'ngx'
local util = require 'util'
local byte = string.byte

local authdata = util.bytes_to_string({5, 0})
local connectdata = util.bytes_to_string({5, 0, 0, 1})

local function auth(sock)
    local data = sock:receive(2)
    local ver = byte(data, 1)
    local methods = byte(data, 2)
    sock:receive(methods)
    ngx.log(ngx.INFO, "version: ", ver, " methods: ", methods)
    if ver ~= 5 then
        return 'version error'
    end
    -- 不需要验证，只要版本号为即认证通过
    sock:send(authdata)
    return nil
end

local function connect(sock)
    local data = sock:receive(4)
    local command  = byte(data, 2)
    local addr_type = byte(data, 4)
    ngx.log(ngx.INFO, "command: ", command, " addr_type: ", addr_type)
    -- 根据地址类型读取目标地址，测试只考虑ipv4
    data = sock:receive(6)
    local dst = {}
    dst['addr'] = {}
    for i=1,4
    do
        table.insert(dst['addr'],''..string.byte(data, i))
    end
    dst['addr'] = table.concat(dst['addr'], '.')
    dst['port'] = byte(data, 5) * 256 + byte(data, 6)
    ngx.log(ngx.INFO, "dst: ", util.to_printable(dst))

    -- 只实现connect方法
    local dst_sock = ngx.socket.tcp()
    local ok, err = dst_sock:connect(dst['addr'], dst['port'])
    if not ok then
        return nil, err
    end
    -- 这里返回地址有点问题，没能获取到dst_sock的addr和port
    sock:send(connectdata..data)
    return dst_sock, nil
end


local function transfer(sock1, sock2, tag)
    while true do
        local data = sock1:receive(1)
        ngx.log(ngx.INFO, tag..' receive:', data)
        if data ~= nil then
            sock2:send(data)
        else
            -- 连接断开
            break
        end

    end
end


local err
local sock = ngx.req.socket(true)
local dst_sock

-- socks5认证相关
err = auth(sock)
if err ~= nil then
    ngx.log(ngx.INFO, "auth error, reason:", err)
    return
end

-- 创建连接
dst_sock, err = connect(sock)
if err ~= nil then
    ngx.log(ngx.INFO, "connect error, reason:", err)
    return
end

-- 创建两个轻线程互相转发数据

local t1 = ngx.thread.spawn(transfer, sock, dst_sock, 'client')
local t2 = ngx.thread.spawn(transfer, dst_sock, sock, 'remote')
ngx.thread.wait(t1, t2)
ngx.log(ngx.INFO, "stop connect")