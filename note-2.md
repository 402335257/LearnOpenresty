## Socks5代理实现思路

- socks5相比http协议工作在更下面一层，通过tcp创建连接。所以选用stream-lua模块来实现。

- 协议认证，认证完之后与目标服务器建立连接

- 连接创建完成之后，创建两个轻线程用于数据的接收，收到数据后将数据转发到对应的socket。

客户端和服务端之间用长连接，这里ngx.req.socket(true)使用raw socket。

根据客户端的请求报文选择使用ngx.socket.tcp() ngx.socket.udp()

实现过程发现两个问题:
- cosocket的api不支持bind方法，所以只能实现connect。
- 因为socks5协议不需要关心数据格式，而在测试过程中发下cosocket里的receive会根据pattern '*l'来判断是否结束接收。而ngx.req.socket不支持receiveany方法。所以数据的接收比较麻烦，这里直接用了receive(1)，效率比较低。

```
local ngx = require 'ngx'

-- 设置为长连接
local sock = ngx.req.socket(true)

-- socks5认证相关

-- 认证成功后
while true do
    local data = sock:receive()
    ngx.log(ngx.INFO, "receive:", data)
    -- 获取请求报文，根据请求报文是tcp转发还是udp转发，使用对应的请求
    -- ngx.socket.tcp 或者 ngx.socket.udp
    -- 这里设置keepalive，放入内置的连接池后会保持连接。
    if data ~= nil then
        sock:send(data)
    else
        -- 断开连接
        break
    end
end
```


```
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
```