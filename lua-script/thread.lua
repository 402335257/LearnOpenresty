local ngx = require 'ngx'


local function work3()
    local cpu_wait = 5
    local io_wait = 5
    while cpu_wait > 0 do
        -- 等待计算
        os.execute("sleep 1")
        cpu_wait = cpu_wait - 1
        -- 等待io,这里ngx.sleep是非阻塞的
        ngx.sleep(1)
        io_wait = io_wait - 1
    end
end

local start = ngx.time()
local t1 = ngx.thread.spawn(work3)
local t2 = ngx.thread.spawn(work3)
ngx.thread.wait(t1, t2)
ngx.log(ngx.INFO, "work3 cost seconds:", ngx.time() - start)