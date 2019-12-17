local ffi = require 'ffi'
local myffi = ffi.load('counter')
ngx.log(ngx.INFO, 'cpath:', package.cpath)

-- 定义函数
ffi.cdef[[
    int count(char *str);
]]

local data = ngx.req.get_uri_args()['data']

local data_c = ffi.new('char[?]', #data)
ffi.copy(data_c, data)
local count = myffi.count(data_c)

ngx.say(count)