--
-- Redis协议解析工具类
-- 提供Redis协议请求解析和响应构建功能
--

local redis_protocol = {}

-- Redis协议解析器类
local RedisProtocolParser = {}
RedisProtocolParser.__index = RedisProtocolParser

function RedisProtocolParser:new()
    local obj = setmetatable({}, RedisProtocolParser)
    return obj
end

-- 解析Redis协议请求
function RedisProtocolParser:parse_request(buffer)
    if not buffer or #buffer == 0 then
        return nil, "empty buffer"
    end
    
    -- 检查是否是数组格式
    if buffer:sub(1, 1) ~= "*" then
        return nil, "invalid protocol format"
    end
    
    local args = {}
    local pos = 2
    
    -- 解析数组长度
    local line_end = buffer:find("\r\n", pos)
    if not line_end then
        return nil, "incomplete request"
    end
    
    local array_len = tonumber(buffer:sub(pos, line_end - 1))
    if not array_len or array_len < 0 then
        return nil, "invalid array length"
    end
    
    pos = line_end + 2
    
    -- 解析每个参数
    for i = 1, array_len do
        if buffer:sub(pos, pos) ~= "$" then
            return nil, "invalid bulk string format"
        end
        
        pos = pos + 1
        line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete bulk string length"
        end
        
        local str_len = tonumber(buffer:sub(pos, line_end - 1))
        if not str_len or str_len < 0 then
            return nil, "invalid string length"
        end
        
        pos = line_end + 2
        
        -- 检查是否有足够的数据
        if pos + str_len + 2 > #buffer then
            return nil, "incomplete bulk string data"
        end
        
        local arg = buffer:sub(pos, pos + str_len - 1)
        table.insert(args, arg)
        
        pos = pos + str_len + 2
    end
    
    return args, pos - 1
end

-- 构建Redis协议响应
function RedisProtocolParser:build_response(data)
    if type(data) == "table" then
        -- 数组响应
        local response = "*" .. #data .. "\r\n"
        for i, item in ipairs(data) do
            response = response .. "$" .. #tostring(item) .. "\r\n" .. tostring(item) .. "\r\n"
        end
        return response
    else
        -- 简单字符串响应
        return "+" .. tostring(data) .. "\r\n"
    end
end

-- 构建错误响应
function RedisProtocolParser:build_error(error_msg)
    return "-" .. tostring(error_msg) .. "\r\n"
end

-- 构建成功响应
function RedisProtocolParser:build_ok()
    return "+OK\r\n"
end

-- 构建批量字符串响应
function RedisProtocolParser:build_bulk_string(str)
    if str == nil then
        return "$-1\r\n"
    else
        return "$" .. #str .. "\r\n" .. str .. "\r\n"
    end
end

-- 构建整数响应
function RedisProtocolParser:build_integer(value)
    return ":" .. tostring(value) .. "\r\n"
end

-- 构建空数组响应
function RedisProtocolParser:build_empty_array()
    return "*0\r\n"
end

-- 构建空响应
function RedisProtocolParser:build_nil()
    return "$-1\r\n"
end

-- 解析Redis协议响应
function RedisProtocolParser:parse_response(buffer)
    if not buffer or #buffer == 0 then
        return nil, "empty buffer"
    end
    
    local first_char = buffer:sub(1, 1)
    local pos = 2
    
    if first_char == "+" then
        -- 简单字符串响应
        local line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete response"
        end
        local result = buffer:sub(pos, line_end - 1)
        return true, result
        
    elseif first_char == "-" then
        -- 错误响应
        local line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete error response"
        end
        local error_msg = buffer:sub(pos, line_end - 1)
        return false, error_msg
        
    elseif first_char == ":" then
        -- 整数响应
        local line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete integer response"
        end
        local int_str = buffer:sub(pos, line_end - 1)
        local result = tonumber(int_str)
        if not result then
            return nil, "invalid integer format"
        end
        return true, result
        
    elseif first_char == "$" then
        -- 批量字符串响应
        local line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete bulk string length"
        end
        
        local str_len = tonumber(buffer:sub(pos, line_end - 1))
        if not str_len then
            return nil, "invalid string length"
        end
        
        if str_len == -1 then
            -- nil响应
            return true, nil
        end
        
        pos = line_end + 2
        
        -- 检查是否有足够的数据
        if pos + str_len > #buffer then
            return nil, "incomplete bulk string data"
        end
        
        local result = buffer:sub(pos, pos + str_len - 1)
        
        -- 检查结尾的\r\n
        if buffer:sub(pos + str_len, pos + str_len + 1) ~= "\r\n" then
            return nil, "invalid bulk string format"
        end
        
        return true, result
        
    elseif first_char == "*" then
        -- 数组响应
        local line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete array length"
        end
        
        local array_len = tonumber(buffer:sub(pos, line_end - 1))
        if not array_len then
            return nil, "invalid array length"
        end
        
        if array_len == -1 then
            -- nil数组响应
            return true, nil
        end
        
        if array_len == 0 then
            -- 空数组响应
            return true, {}
        end
        
        pos = line_end + 2
        local results = {}
        
        -- 解析数组中的每个元素
        for i = 1, array_len do
            local success, element = self:parse_response(buffer:sub(pos))
            if not success then
                return nil, "failed to parse array element " .. i
            end
            table.insert(results, element)
            
            -- 计算已解析的字节数
            local element_end = buffer:find("\r\n", pos)
            if not element_end then
                return nil, "incomplete array element " .. i
            end
            
            -- 移动到下一个元素
            pos = element_end + 2
        end
        
        return true, results
        
    else
        return nil, "unknown response type"
    end
end

-- 协议验证工具函数

-- 验证Redis命令格式
function redis_protocol.validate_command(args)
    if not args or #args == 0 then
        return false, "命令参数不能为空"
    end
    
    local command = string.upper(args[1])
    
    -- 检查命令长度
    if #command == 0 or #command > 32 then
        return false, "命令名称长度无效"
    end
    
    -- 检查命令格式（只允许字母和数字）
    if not string.match(command, "^[A-Z0-9]+$") then
        return false, "命令格式无效"
    end
    
    return true, command
end

-- 验证参数数量
function redis_protocol.validate_arg_count(args, min_count, max_count)
    local arg_count = #args
    
    if min_count and arg_count < min_count then
        return false, string.format("参数数量不足: 需要至少 %d 个参数", min_count)
    end
    
    if max_count and arg_count > max_count then
        return false, string.format("参数数量过多: 最多允许 %d 个参数", max_count)
    end
    
    return true
end

-- 命令处理工具函数

-- 创建命令处理器
function redis_protocol.create_command_handler()
    local handler = {
        commands = {},
        default_handler = nil
    }
    
    -- 注册命令
    function handler:register(command, callback, readonly)
        if not command or not callback then
            return false, "命令名称和回调函数不能为空"
        end
        
        local cmd_upper = string.upper(command)
        handler.commands[cmd_upper] = {
            callback = callback,
            readonly = readonly or false,
            name = command
        }
        
        return true
    end
    
    -- 设置默认处理器
    function handler:set_default(callback)
        handler.default_handler = callback
        return true
    end
    
    -- 处理命令
    function handler:process(command, args)
        if not command then
            return nil, "命令不能为空"
        end
        
        local cmd_upper = string.upper(command)
        local command_info = handler.commands[cmd_upper]
        
        if command_info then
            return command_info.callback(args)
        elseif handler.default_handler then
            return handler.default_handler(command, args)
        else
            return nil, "未知命令: " .. command
        end
    end
    
    -- 获取支持的命令列表
    function handler:get_supported_commands()
        local commands = {}
        
        for cmd_name, cmd_info in pairs(handler.commands) do
            table.insert(commands, {
                name = cmd_name,
                readonly = cmd_info.readonly,
                description = cmd_info.description or ""
            })
        end
        
        return commands
    end
    
    return handler
end

-- 响应格式化工具函数

-- 格式化错误响应
function redis_protocol.format_error_response(error_msg)
    return "-" .. tostring(error_msg) .. "\r\n"
end

-- 格式化成功响应
function redis_protocol.format_ok_response()
    return "+OK\r\n"
end

-- 格式化字符串响应
function redis_protocol.format_string_response(str)
    return "+" .. tostring(str) .. "\r\n"
end

-- 格式化整数响应
function redis_protocol.format_integer_response(value)
    return ":" .. tostring(value) .. "\r\n"
end

-- 格式化数组响应
function redis_protocol.format_array_response(array)
    if not array or type(array) ~= "table" then
        return "*0\r\n"
    end
    
    local response = "*" .. #array .. "\r\n"
    for _, item in ipairs(array) do
        if item == nil then
            response = response .. "$-1\r\n"
        else
            local str_item = tostring(item)
            response = response .. "$" .. #str_item .. "\r\n" .. str_item .. "\r\n"
        end
    end
    
    return response
end

-- 批量数据处理工具函数

-- 批量操作处理器类
local BatchProcessor = {}
BatchProcessor.__index = BatchProcessor

function BatchProcessor:new(batch_size, flush_callback)
    local obj = setmetatable({}, BatchProcessor)
    obj.batch_size = batch_size or 1000
    obj.flush_callback = flush_callback
    obj.batch_data = {}
    obj.current_size = 0
    return obj
end

-- 添加数据到批量处理器
function BatchProcessor:add_data(key, value, timestamp)
    table.insert(self.batch_data, {
        key = key,
        value = value,
        timestamp = timestamp or os.time()
    })
    self.current_size = self.current_size + 1
    
    if self.current_size >= self.batch_size then
        return self:flush()
    end
    
    return true
end

-- 刷新批量数据
function BatchProcessor:flush()
    if self.current_size == 0 then
        return true
    end
    
    local success = true
    
    if self.flush_callback then
        success = self.flush_callback(self.batch_data)
    end
    
    -- 清空批量数据
    self.batch_data = {}
    self.current_size = 0
    
    return success
end

-- 获取当前批量大小
function BatchProcessor:get_current_size()
    return self.current_size
end

-- 获取批量数据
function BatchProcessor:get_batch_data()
    return self.batch_data
end

-- 导出
redis_protocol.RedisProtocolParser = RedisProtocolParser
redis_protocol.BatchProcessor = BatchProcessor

return redis_protocol