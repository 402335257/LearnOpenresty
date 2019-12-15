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