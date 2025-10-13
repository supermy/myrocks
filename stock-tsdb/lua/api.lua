--
-- Redis协议API实现
-- 提供兼容Redis的时间序列命令
--

local api = {}
local tsdb = require "tsdb"
local storage = require "storage"

-- 命令处理器
local command_handlers = {}

-- 时间序列命令
local TS_COMMANDS = {
    "TS.ADD", "TS.MADD", "TS.RANGE", "TS.MRANGE", 
    "TS.GET", "TS.MGET", "TS.DEL", "TS.INFO",
    "TS.CREATE", "TS.ALTER", "TS.DECRBY", "TS.INCRBY"
}

-- 通用Redis命令
local COMMON_COMMANDS = {
    "PING", "INFO", "CONFIG", "CLUSTER", "QUIT", "AUTH"
}

-- 帮助信息
local HELP_MESSAGES = {
    ["TS.ADD"] = "TS.ADD key timestamp value [data_type] [quality] - 添加数据点",
    ["TS.RANGE"] = "TS.RANGE key start end [data_type] - 查询时间范围数据",
    ["TS.GET"] = "TS.GET key timestamp [data_type] - 获取指定时间的数据点",
    ["TS.INFO"] = "TS.INFO key [data_type] - 获取时间序列信息",
    ["PING"] = "PING [message] - 测试连接",
    ["INFO"] = "INFO [section] - 获取服务器信息",
    ["CONFIG"] = "CONFIG GET|SET parameter [value] - 配置管理"
}

-- 工具函数
local function split_key(key)
    -- 解析Redis键格式
    -- 支持格式: stock:000001:price 或 stock:000001:price:20231201
    local parts = {}
    for part in string.gmatch(key, "([^:]+)") do
        table.insert(parts, part)
    end
    
    local symbol = nil
    local data_type = nil
    local date = nil
    
    if #parts >= 2 then
        if parts[1] == "stock" then
            symbol = parts[2]
            if #parts >= 3 then
                data_type = parts[3]
            end
            if #parts >= 4 then
                date = parts[4]
            end
        end
    end
    
    return symbol, data_type, date
end

local function parse_timestamp(timestamp_str)
    -- 解析时间戳
    -- 支持毫秒和微秒时间戳
    local timestamp = tonumber(timestamp_str)
    if not timestamp then
        return nil, "无效的时间戳格式"
    end
    
    -- 如果是毫秒时间戳，转换为微秒
    if timestamp < 1000000000000 then  -- 小于2001年的秒时间戳
        return nil, "时间戳格式不支持"
    elseif timestamp < 1000000000000000 then  # 毫秒时间戳
        timestamp = timestamp * 1000  -- 转换为微秒
    end
    
    return timestamp
end

local function format_timestamp(timestamp)
    -- 格式化时间戳为字符串
    -- 微秒时间戳转换为毫秒显示
    return tostring(math.floor(timestamp / 1000))
end

local function format_value(value)
    -- 格式化数值
    if type(value) == "number" then
        return string.format("%.6f", value)
    else
        return tostring(value)
    end
end

local function validate_symbol(symbol)
    -- 验证股票代码
    if not symbol or #symbol == 0 or #symbol > 8 then
        return false, "股票代码无效（长度1-8）"
    end
    
    -- 检查是否为有效的股票代码格式
    if not string.match(symbol, "^%d+$") and not string.match(symbol, "^%u+$") then
        return false, "股票代码格式无效（应为数字或大写字母）"
    end
    
    return true
end

local function validate_data_type(data_type)
    -- 验证数据类型
    local valid_types = {
        price = 0, volume = 1, bid = 2, ask = 3,
        open = 4, high = 5, low = 6, close = 7, turnover = 8
    }
    
    if not data_type then
        return 0  -- 默认为价格数据
    end
    
    local lower_type = string.lower(data_type)
    local type_code = valid_types[lower_type]
    
    if type_code == nil then
        return nil, string.format("无效的数据类型: %s", data_type)
    end
    
    return type_code
end

-- 命令处理器注册
local function register_command(name, handler, readonly)
    command_handlers[string.upper(name)] = {
        handler = handler,
        readonly = readonly or false,
        name = name
    }
end

-- 时间序列命令处理器
local function handle_ts_add(args)
    if #args < 3 then
        return {error = "ERR wrong number of arguments for 'TS.ADD' command"}
    end
    
    local key = args[1]
    local timestamp_str = args[2]
    local value_str = args[3]
    local data_type = args[4]
    local quality = args[5] and tonumber(args[5]) or 100
    
    -- 解析参数
    local symbol, type_name = split_key(key)
    if not symbol then
        return {error = "ERR invalid key format"}
    end
    
    local valid, error_msg = validate_symbol(symbol)
    if not valid then
        return {error = "ERR " .. error_msg}
    end
    
    local timestamp, error_msg = parse_timestamp(timestamp_str)
    if not timestamp then
        return {error = "ERR " .. error_msg}
    end
    
    local value = tonumber(value_str)
    if not value then
        return {error = "ERR invalid value"}
    end
    
    local data_type_code, error_msg = validate_data_type(data_type or type_name)
    if not data_type_code then
        return {error = "ERR " .. error_msg}
    end
    
    -- 写入数据
    local success, error_msg = tsdb.write_point(symbol, timestamp, value, data_type_code, quality)
    if not success then
        return {error = "ERR " .. error_msg}
    end
    
    return {ok = "OK"}
end

local function handle_ts_range(args)
    if #args < 3 then
        return {error = "ERR wrong number of arguments for 'TS.RANGE' command"}
    end
    
    local key = args[1]
    local start_str = args[2]
    local end_str = args[3]
    local data_type = args[4]
    
    -- 解析参数
    local symbol, type_name = split_key(key)
    if not symbol then
        return {error = "ERR invalid key format"}
    end
    
    local valid, error_msg = validate_symbol(symbol)
    if not valid then
        return {error = "ERR " .. error_msg}
    end
    
    local start_time, error_msg = parse_timestamp(start_str)
    if not start_time then
        return {error = "ERR " .. error_msg}
    end
    
    local end_time, error_msg = parse_timestamp(end_str)
    if not end_time then
        return {error = "ERR " .. error_msg}
    end
    
    if start_time > end_time then
        return {error = "ERR start time must be less than or equal to end time"}
    end
    
    local data_type_code, error_msg = validate_data_type(data_type or type_name)
    if not data_type_code then
        return {error = "ERR " .. error_msg}
    end
    
    -- 查询数据
    local points = tsdb.read_range(symbol, start_time, end_time, data_type_code)
    
    -- 格式化结果
    local result = {}
    for _, point in ipairs(points) do
        table.insert(result, {
            timestamp = format_timestamp(point.timestamp),
            value = format_value(point.value),
            quality = point.quality
        })
    end
    
    return {array = result}
end

local function handle_ts_get(args)
    if #args < 2 then
        return {error = "ERR wrong number of arguments for 'TS.GET' command"}
    end
    
    local key = args[1]
    local timestamp_str = args[2]
    local data_type = args[3]
    
    -- 解析参数
    local symbol, type_name = split_key(key)
    if not symbol then
        return {error = "ERR invalid key format"}
    end
    
    local valid, error_msg = validate_symbol(symbol)
    if not valid then
        return {error = "ERR " .. error_msg}
    end
    
    local timestamp, error_msg = parse_timestamp(timestamp_str)
    if not timestamp then
        return {error = "ERR " .. error_msg}
    end
    
    local data_type_code, error_msg = validate_data_type(data_type or type_name)
    if not data_type_code then
        return {error = "ERR " .. error_msg}
    end
    
    -- 查询数据点
    local point, error_msg = tsdb.read_point(symbol, timestamp, data_type_code)
    if not point then
        return {nil = true}
    end
    
    return {array = {
        format_timestamp(point.timestamp),
        format_value(point.value),
        tostring(point.quality)
    }}
end

local function handle_ts_info(args)
    if #args < 1 then
        return {error = "ERR wrong number of arguments for 'TS.INFO' command"}
    end
    
    local key = args[1]
    local data_type = args[2]
    
    -- 解析参数
    local symbol, type_name = split_key(key)
    if not symbol then
        return {error = "ERR invalid key format"}
    end
    
    local valid, error_msg = validate_symbol(symbol)
    if not valid then
        return {error = "ERR " .. error_msg}
    end
    
    local data_type_code, error_msg = validate_data_type(data_type or type_name)
    if not data_type_code then
        return {error = "ERR " .. error_msg}
    end
    
    -- 获取统计信息
    local stats = tsdb.get_stats()
    
    -- 构建响应
    local info = {
        symbol = symbol,
        data_type = tsdb.get_data_type_name(data_type_code),
        total_points = 0,  -- 需要从存储获取
        start_time = 0,    -- 需要从存储获取
        end_time = 0,      -- 需要从存储获取
        memory_usage = 0,  -- 需要从存储获取
        cache_stats = stats.cache
    }
    
    return {array = info}
end

-- 通用命令处理器
local function handle_ping(args)
    if #args == 0 then
        return {string = "PONG"}
    else
        return {string = args[1]}
    end
end

local function handle_info(args)
    local section = args[1] or "all"
    
    -- 构建服务器信息
    local info = {
        "# Server",
        "stock-tsdb-version:1.0.0",
        "rocksdb-version:6.0.0",
        "lua-version:5.1",
        "",
        "# Clients",
        "connected_clients:0",  -- 需要从服务器获取
        "",
        "# Memory",
        "used_memory:0",  -- 需要从服务器获取
        "",
        "# Persistence",
        "loading:0",
        "rdb_changes_since_last_save:0",
        "",
        "# Stats",
        "total_connections_received:0",
        "total_commands_processed:0",
        "instantaneous_ops_per_sec:0",
        "",
        "# Time Series",
        "ts_total_keys:0",
        "ts_total_points:0",
        "ts_cache_hits:0",
        "ts_cache_misses:0"
    }
    
    return {string = table.concat(info, "\n")}
end

local function handle_config(args)
    if #args < 2 then
        return {error = "ERR wrong number of arguments for 'CONFIG' command"}
    end
    
    local subcommand = string.upper(args[1])
    local parameter = args[2]
    
    if subcommand == "GET" then
        -- 获取配置
        local config = tsdb.get_config()
        local value = config
        
        -- 支持嵌套配置访问
        for key in string.gmatch(parameter, "[^.]+") do
            if value and type(value) == "table" then
                value = value[key]
            else
                value = nil
                break
            end
        end
        
        if value ~= nil then
            return {array = {parameter, tostring(value)}}
        else
            return {array = {}}
        end
        
    elseif subcommand == "SET" then
        if #args < 3 then
            return {error = "ERR wrong number of arguments for 'CONFIG SET' command"}
        end
        
        local value = args[3]
        tsdb.set_config(parameter, value)
        return {ok = "OK"}
        
    else
        return {error = "ERR unknown subcommand"}
    end
end

-- 注册所有命令
register_command("TS.ADD", handle_ts_add, false)
register_command("TS.RANGE", handle_ts_range, true)
register_command("TS.GET", handle_ts_get, true)
register_command("TS.INFO", handle_ts_info, true)
register_command("PING", handle_ping, true)
register_command("INFO", handle_info, true)
register_command("CONFIG", handle_config, false)

-- 命令处理函数
function api.process_command(command, args)
    -- 处理Redis命令
    local cmd = string.upper(command)
    local handler_info = command_handlers[cmd]
    
    if not handler_info then
        return {error = string.format("ERR unknown command '%s'", command)}
    end
    
    -- 调用处理器
    local result = handler_info.handler(args)
    
    -- 格式化响应
    return api.format_response(result)
end

function api.format_response(result)
    -- 格式化Redis协议响应
    if result.error then
        -- 错误响应
        return "-" .. result.error .. "\r\n"
    elseif result.ok then
        -- 简单字符串响应
        return "+" .. result.ok .. "\r\n"
    elseif result.string then
        -- 简单字符串响应
        return "+" .. result.string .. "\r\n"
    elseif result.integer then
        -- 整数响应
        return ":" .. result.integer .. "\r\n"
    elseif result.array then
        -- 数组响应
        local response = "*" .. #result.array .. "\r\n"
        for _, item in ipairs(result.array) do
            if item == nil then
                response = response .. "$-1\r\n"
            else
                local str_item = tostring(item)
                response = response .. "$" .. #str_item .. "\r\n" .. str_item .. "\r\n"
            end
        end
        return response
    elseif result.nil then
        -- 空响应
        return "$-1\r\n"
    else
        -- 默认错误响应
        return "-ERR invalid response format\r\n"
    end
end

function api.get_supported_commands()
    -- 获取支持的命令列表
    local commands = {}
    
    for _, cmd in ipairs(TS_COMMANDS) do
        table.insert(commands, {
            name = cmd,
            type = "time_series",
            help = HELP_MESSAGES[cmd] or "No help available"
        })
    end
    
    for _, cmd in ipairs(COMMON_COMMANDS) do
        table.insert(commands, {
            name = cmd,
            type = "common",
            help = HELP_MESSAGES[cmd] or "No help available"
        })
    end
    
    return commands
end

function api.get_command_help(command)
    -- 获取命令帮助
    local cmd = string.upper(command)
    return HELP_MESSAGES[cmd] or string.format("No help available for '%s'", command)
end

-- 导出API
return api