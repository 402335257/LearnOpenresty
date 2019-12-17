[toc]

## Openresty是什么
相比Nginx，增加了对Lua的支持，可以方便的扩展功能。

在此之前如果要在早期版本的nginx上加载模块，每次修改都需要重新编译。不能像
collectd之类的软件引入so文件加载。

新版本的nginx 1.9.11之后也支持动态加载模块了，但是需要在编译时指定类似如：—add-dynamic-module= <模块名>。 

如果nginx引入ngx_lua_module也能实现对Lua的支持。

## LuaJit

（Just In TIme）即时编译，效率比直接解释运行高，比静态编译灵活。

## LuaJit ffi

ffi是一个Lua库，可以在Lua中执行c代码。

## Openresty中默认集成的各种模块

array-var-nginx-module 支持数组变量操作

ngx_http_auth_request_module 鉴权用

ngx_coolkit 一些nginx小扩展的集合，例如改写请求，请求里的一些变量

echo-nginx-module 方便地输出一些信息 支持异步和同步

encrypted-session-nginx-module 变量加解密

form-input-nginx-module 读取表单信息放到nginx变量里

headers-more-nginx-module header修改

memc-nginx-module  memcached操作

rds-csv-nginx-module rds转换为csv格式

set-misc-nginx-module 各种set指令

srcache-nginx-module 构造location的请求

stream-lua-nginx-module 实现lua的tcp/udp服务器

xss-nginx-module 跨域请求

下面像是实现了lua的各种标准库

lua-cjson json库

lua-rds-parser  解析Resty-DBD-Streams 这些数据是ngx_drizzle  

和ngx_postgres返回的

lua-redis-parser redis操作库

lua-resty-core 一些基于ffi的常用api

lua-resty-dns dns解析的库

lua-resty-lock 锁

lua-resty-lrucache lrucache的实现

lua-resty-memcached lua操作memcached

lua-resty-mysql lua操作mysql

lua-resty-string lua字符串工具

lua-resty-upload 文件上传

lua-resty-upstream-healthcheck 健康检查

lua-resty-websocket websocket客户端

lua-resty-limit-traffic 限流

lua-resty-shell shell调用

lua-resty-signal linux下进程信号

lua-tablepool 实现了table池，频繁地申请临时table使用这个更合适

lua-upstream-nginx-module upstream api

## OPM

Openresty的模块管理器

用法和pip类似，命名规则为: 用户名/模块名
```
opm search

opm install

opm list
```

## 上手练习
利用stream-lua-nginx-module里的udp实现一个简单的DNS服务器。
(使用mysql模块的时候发现在stream里会报ngx_lua的版本问题，在http底下没问题。)

#### 先学习了DNS协议

DNS协议报文头部部分
- 2字节 会话标识， 请求和应答的id区分标识
- 2字节 标志，标志位含义为

标识 | 位数 | 含义
-|-|-
QR|1|0为查询 1为响应
opcode|4|0标准查询 1为反解 2是服务器状态请求
AA|1|授权回答
TC|1|可截断
RD|1|期望递归
RA|1|可用递归
rcode|4|0为正常
- 8字节     Questions、Answer RRs、Authority RRs、Additional RRs


DNS协议报文的正文部分

- Queries
  - 查询名称: 长度不定，最后为0
  - 查询类型： 就是常用的A，CNAME，TXT等记录类型
  - 查询类: 通常为1，标识Internet数据
    
- Answers
  - name 0xc00c 2字节
  - type 2字节
  - class 2字节
  - ttl 4字节
  - len 2字节
  - value len长度

这里有个报文域名压缩需要实现，c0+报文偏移量，这里简单的用zip_table保存偏移量了。

#### 实现
nginx.conf
```
worker_processes  1;
error_log logs/error.log info;
events {
    worker_connections 1024;
}
stream {
    lua_package_path 'lua-script/?.lua;;';
    server {
        listen 53 udp;
        lua_code_cache off;
        content_by_lua_file lua-script/udp.lua;
    }
}

http {
    lua_package_path 'lua-script/?.lua;;';

    server {
        listen 8080;
        server_name localhost;
        location /dns {
           lua_code_cache off;
           content_by_lua_file lua-script/mysql.lua;
        }
    }
}
```

- udp.lua

```
local ngx = require 'ngx'
local util = require 'util'
local http = require 'resty.http'
local cjson = require 'cjson'
local bytes_to_num = util.bytes_to_num
local insert_table = util.insert_table
local to_printable = util.to_printable
local num_to_bytes = util.num_to_bytes
local bytes_to_string = util.bytes_to_string
local string_to_bytes = util.string_to_bytes

local QTYPE = {
    A = 1,
    CNAME = 5
}

local function parse_header(bytes)
    local header = {}
    header['id'] = bytes_to_num(bytes,1,2)
    header['flag'] = bytes_to_num(bytes,3,2)
    header['questions'] = bytes_to_num(bytes, 5,2)
    header['answer_rrs'] = bytes_to_num(bytes, 7,2)
    header['authority_rrs'] = bytes_to_num(bytes, 9,2)
    header['additional_rrs'] = bytes_to_num(bytes, 11,2)
    return to_printable(header)
end

local function parse_query(bytes, start)
    local query = {}
    query['domain'] = {}
    query['offset_info'] = {}
    local len = bytes[start]
    while (len~=0)
    do
        local name = ''
        for i=start+1, start+len do
            name = name..string.char(bytes[i])
        end
        table.insert(query['domain'], name)
        table.insert(query['offset_info'], {
            part = name,
            offset = start - 1
        })
        start = start + len +1
        len = bytes[start]
    end
    start = start+1
    query['type'] = bytes_to_num(bytes, start, 2)
    query['class'] = bytes_to_num(bytes, start+2, 2)
    start = start + 3
    return to_printable(query), start
end

local function record_to_table(offset_info, record, type)
    local result = {}
    if type == QTYPE.A then
        result = util.split(record, '.')
        for i=1,#result do
            result[i] = tonumber(result[i])
        end
    else
        -- 替换可以压缩的域名
        record = util.split(record, '.')
        local offset = 12
        local break_index = #record
        for i=0, #offset_info-1 do
            if offset_info[#offset_info-i]['part'] == record[#record-i] then
                offset = offset_info[#offset_info-i]['offset']
            else
                break_index = #record-i
                break
            end
        end
        for i=1,break_index do
            table.insert(result, #record[i])
            for j=1, #record[i] do
                table.insert(result,string.byte(record[i], j))
            end
        end
        table.insert(result,192)
        table.insert(result,offset)
    end
    return result
end

local function find_answer(query)
    local domain = table.concat(query['domain'], '.')
    local offset_info = query['offset_info']
    local httpc = http:new()
    local res, err = httpc:request_uri('http://127.0.0.1:8080', {
        method='GET',
        path='/dns?domain='..domain
    })
    if not res then
        ngx.log(ngx.INFO, "find answer error:", err)
        return {}
    end
    ngx.log(ngx.INFO, "data", res.body)
    local answers = cjson.decode(res.body)
    for i=1,#answers do
        local answer = answers[i]
        answer['record_r'] = answer['record']
        answer['record'] =  record_to_table(offset_info, answer['record'], answer['type'])
        answer['data_len'] = #answer['record']
    end
    return answers
end

local function answer_to_bytes(zip_table, answer)
    local bytes = {}
    -- 报文域名压缩
    local name = {192, zip_table[answer['name']]}
    insert_table(bytes, name)
    insert_table(bytes, num_to_bytes(answer['type'], 2))
    insert_table(bytes, num_to_bytes(answer['class'], 2))
    insert_table(bytes, num_to_bytes(answer['ttl'], 4))
    insert_table(bytes, num_to_bytes(answer['data_len'], 2))
    insert_table(bytes, answer['record'])
    return bytes
end

local function build_answer(bytes, header, query, answers)
    header['flag'] = 129 * 256 + 128
    header['answer_rrs'] = #answers
    local result = num_to_bytes(header['flag'], 2)
    bytes[3] = result[1]
    bytes[4] = result[2]
    result = num_to_bytes(header['answer_rrs'], 2)
    bytes[7] = result[1]
    bytes[8] = result[2]
    local zip_table =  {}
    zip_table[table.concat(query['domain'], '.')] = 12
    for i=1,#answers do
        insert_table(bytes, answer_to_bytes(zip_table, answers[i]))
        zip_table[answers[i]['record_r']] = #bytes - answers[i]['data_len']
    end
end

local sock = ngx.req.socket()
local data = sock:receive()
local bytes = string_to_bytes(data)

-- 解析请求
local header = parse_header(bytes)
local query, cursor = parse_query(bytes, 13)
ngx.log(ngx.INFO, "receive header:", header)
ngx.log(ngx.INFO, "receive query:", query)

-- 域名解析
local answers = find_answer(query)

-- 构造响应包
local response = string_to_bytes(string.sub(data, 1, cursor))
build_answer(response, header, query, answers)
response = bytes_to_string(response)
sock:send(response)
```

- mysql.lua
```
local ngx = require 'ngx'
local cjson = require 'cjson'
local mysql = require 'resty.mysql'
local resolver = require "resty.dns.resolver"

local db = mysql:new()
db:set_timeout(1000)
local conf = {
    host = "127.0.0.1",
    port = 3306,
    database = "dns",
    user = "root",
    password = "aabb1122"
}
local res, err, errno, sqlstate = db:connect(conf)
if not res then
    ngx.say('connect mysql failed',' ',err,' ',errno,' ', sqlstate)
    return
else
    ngx.log(ngx.INFO, 'connect mysql success')
end

local domain=ngx.req.get_uri_args()['domain']
if not domain then
    ngx.say('need domain')
    return
end

res, err, errno, sqlstate = db:query("select * from tb_dns where name="
    ..ngx.quote_sql_str(domain), 10)
if not res then
    ngx.say('sql error: ',err, ' ', errno, ' ', sqlstate)
    return
end

if #res ~= 0 then
    res = cjson.encode(res)
    ngx.say(res)
    return
end

local rs = resolver:new{
    nameservers = { "8.8.8.8" }
}
if not rs then
    ngx.say("failed to instantiate resolver: ", err)
    return
end

local ans = rs:tcp_query(domain, { qtype = rs.TYPE_A })
if not ans then
    ngx.say("failed to query: ", err)
    return
end

for i=1,#ans do
    ans[i]['section'] = nil
    if ans[i]['type'] == 5 then
        ans[i]['record'] = ans[i]['cname']
        ans[i]['cname'] = nil
    else
        ans[i]['record'] = ans[i]['address']
        ans[i]['address'] = nil
    end
end
ngx.say(cjson.encode(ans))
```

- util.lua
```
local bit = require 'bit'
local cjson = require 'cjson'
local lshift = bit.lshift
local rshift = bit.rshift
local band = bit.band
local _M = {}

function _M.to_printable(t)
    local nt = setmetatable(t, {
        __tostring = function(t1)
            return cjson.encode(t1)
        end
    })
    return nt
end

function _M.bytes_to_num(data, start, count)
    local num = 0
    for i=0, count-1, 1
    do
        num = lshift(num, 8) + data[start + i]
    end
    return num
end

function _M.num_to_bytes(num, count)
    local bytes = {}
    for i=count, 1, -1 do
        bytes[i] = band(num, 255)
        num = rshift(num, 8)
    end
    return bytes
end

function _M.bytes_to_string(bytes)
    for i=1,#bytes
    do
        bytes[i] = string.char(bytes[i])
    end
    return table.concat(bytes)
end

function _M.string_to_bytes(data)
    local bytes = {}
    for i=1,#data
    do
        table.insert(bytes, string.byte(data, i))
    end
    return _M.to_printable(bytes)
end

function _M.insert_table(t1, t2)
    for i=1,#t2 do
        table.insert(t1, t2[i])
    end
end

function _M.split(data, splitter)
    local result = {}
    string.gsub(data,  '[^'..splitter..']+', function (w) table.insert(result, w) end)
    return result
end

return _M
```

dig mydns @127.0.0.1

- dig结果

```
dig mydns @127.0.0.1

;; Warning: Message parser reports malformed message packet.

; <<>> DiG 9.11.3-1ubuntu1.11-Ubuntu <<>> mydns @127.0.0.1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 48533
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;mydns.				IN	A

;; ANSWER SECTION:
mydns.			60	IN	A	111.112.113.114

;; Query time: 11 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Sun Dec 15 14:25:17 CST 2019
;; MSG SIZE  rcvd: 39


dig www.baidu.com @127.0.0.1

;; Warning: Message parser reports malformed message packet.

; <<>> DiG 9.11.3-1ubuntu1.11-Ubuntu <<>> www.baidu.com @127.0.0.1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 61470
;; flags: qr rd ra; QUERY: 1, ANSWER: 3, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;www.baidu.com.			IN	A

;; ANSWER SECTION:
www.baidu.com.		946	IN	CNAME	www.a.shifen.com.
www.a.shifen.com.	50	IN	A	220.181.38.150
www.a.shifen.com.	50	IN	A	220.181.38.149

;; Query time: 109 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Sun Dec 15 14:25:51 CST 2019
;; MSG SIZE  rcvd: 90

```


##  学习火焰图

一般是通过systemtap收集数据，然后通过FlameGraph展示出来。

安装systemtap之后要安装对应内核版本的调试信息包，不然无法使用。

ubuntu官网上的教程安装失败，直接下载deb包安装。


```
uame -a 查看内核版本信息

wget http://ddebs.ubuntu.com/pool/main/l/linux/linux-image-unsigned-4.15.0-72-generic-dbgsym_4.15.0-72.81_amd64.ddeb

sudo dpkg -i linux-image-4.15.0-72-generic-dbgsym_4.15.0-72.81_adm64.ddeb

sudo stap -v -e 'probe begin { printf("Hello, World!\n"); exit() }'

sudo stap -v -e 'probe vfs.read {printf("read performed\n"); exit()}'
```


使用stapxx工具包,里面有lj-lua-stacks.sxx


执行samples/lj-lua-stacks.sxx报错

```

 ./samples/lj-lua-stacks.sxx --skip-badvars -x 11097 > /tmp/ngx_cpu.bt

semantic error: while processing function luajit_G

semantic error: unable to find member 'ptr32' for struct MRef (alternatives: ptr64): operator '->' at stapxx-U3mI95ou/luajit.stp:162:98

```
看github上的issue上是这个工具不支持最新的Openresty,新版本默认是GC64？

按照错误提示将luajit_gc64.sxx替换luajit.sxx

再执行， 执行成功但是文件为空......
```
Found exact match for libluajit: /usr/local/openresty/luajit/lib/libluajit-5.1.so.2.1.0
symbolmap: 00000001: invalid section
WARNING: Start tracing 11097 (/usr/local/openresty/nginx/sbin/nginx)
WARNING: Please wait for 5 seconds...
WARNING: Time's up. Quitting now...
WARNING: Found 0 JITted samples.
```

使用./samples/luajit21-gc64/lj-vm-states.sxx --arg time=5  -x 11097
vmstate输出都为-2，所以上面采集不到JITed的样本。

```
Start tracing 11097 (/usr/local/openresty/nginx/sbin/nginx)
Please wait for 5 seconds...

Observed 450 Lua-running samples and ignored 0 unrelated samples.
C Code (by interpreted Lua): 100% (450 samples)
```

google没发现什么类似的问题，后来发现应该和lua_code_cache off有关系，关掉了就能采集到了....，然后因为采样的方法，请求的量也不能太少。

```
0xffffffff94e6bef5
C:ngx_http_lua_socket_tcp_connect
@/usr/local/openresty/site/lualib/resty/mysql.lua:538
@/home/wang/project/openresty_dir/lua-script/mysql.lua:0
	47
0xffffffff94e6bef5
C:ngx_http_lua_socket_tcp_receive
@/usr/local/openresty/site/lualib/resty/mysql.lua:250
@/usr/local/openresty/site/lualib/resty/mysql.lua:538
@/home/wang/project/openresty_dir/lua-script/mysql.lua:0

```

使用fix-lua-bt工具转换,再生成svg
```
./fix-lua-bt a.bt flame.bt
./stackcollapse-stap.pl ../stapxx/flame.bt  > flame.cbt
./flamegraph.pl flame.cbt >flame.svg
```



## FFI使用

在lua里调用c代码，在某些场景可以提升效率。需要先将C代码编译成动态库(.so文件),然后通过ffi加载c模块，cdef声明函数之后就可以使用C函数了，与C的头文件声明一样。

C与Lua的变量存在对应关系，使用的时候需要转换。

counter.c

```
int count(char *str) {
    int c=0;
    char *p = str;
    while (*p != '\0')
    {
        c++;
        p++;
    }
    return c;
}

```

编译成动态库

```
gcc -g -o libcounter.so -fpic -shared counter.c
```

nginx.conf里指定了lua_package_cpath发现没有起作用，先扔到/usr/lib/底下测试，调用成功。

```
lua_package_cpath 'lua-so/?.so;;';
```

usec.lua
```
local ffi = require 'ffi'
local myffi = ffi.load('counter')

-- 定义函数
ffi.cdef[[
    int count(char *str);
]]

local data = ngx.req.get_uri_args()['data']

local data_c = ffi.new('char[?]', #data)
ffi.copy(data_c, data)
local count = myffi.count(data_c)

ngx.say(count)

```

回过头来看lua_package_cpath不生效的问题，在log里打印package.cpath,输出为

```
cpath:lua-so/?.so;/usr/local/openresty/site/lualib/?.so;/usr/local/openresty/lualib/?.so;./?.so;/usr/local/lib/lua/5.1/?.so;/usr/local/openresty/luajit/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so;
```

最后发现这个lua_package_cpath和ffi加载so库无关，只和系统的ldconfig有关系。

```
往/etc/ld.so.conf.d/***.conf里添加so库

执行ldconfig
```