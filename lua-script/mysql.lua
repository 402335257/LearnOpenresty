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