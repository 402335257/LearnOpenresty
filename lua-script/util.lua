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