local coroutine = require 'coroutine'
local ngx = require 'ngx'


-- 模拟一个任务，5秒计算，5秒等待io
-- 同时执行两个这样的任务，work1需要20秒，work2只需要10秒

local function work1()
    local cpu_wait = 5
    local io_wait = 5
    while cpu_wait > 0 do
        ngx.sleep(1)
        cpu_wait = cpu_wait - 1
        -- 等待io
        ngx.sleep(1)
        io_wait = io_wait - 1
    end
end

local function work2()
    local cpu_wait = 5
    local io_wait = 5
    while cpu_wait > 0 do
        -- 等待计算
        ngx.sleep(1)
        cpu_wait = cpu_wait - 1
        -- 等待io
        local r = coroutine.yield()
        ngx.log(ngx.INFO, "resume:", r)
        -- 这时候实际已经过去了1秒
        io_wait = io_wait - 1
    end
end

local start = ngx.time()
work1()
work1()
ngx.log(ngx.INFO, "work1 cost second: ", ngx.time() - start)

start = ngx.time()
local co1 = coroutine.create(work2)
local co2 = coroutine.create(work2)
while true do
    coroutine.resume(co1, 1)
    coroutine.resume(co2, 2)
    if coroutine.status(co1) == 'dead' and coroutine.status(co2) == 'dead' then
        break
    end
end
ngx.log(ngx.INFO, "work2 cost second: ", ngx.time() - start)