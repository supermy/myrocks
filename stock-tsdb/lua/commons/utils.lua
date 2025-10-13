--
-- 通用工具函数库
-- 提供字符串处理、时间处理、数据验证等通用功能
--

local utils = {}

-- 字符串处理工具函数

-- 字符串分割函数
function utils.split(str, delimiter)
    if not str or not delimiter then
        return {}
    end
    
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    
    for match in string.gmatch(str, pattern) do
        table.insert(result, match)
    end
    
    return result
end

-- 字符串trim函数
function utils.trim(str)
    if not str then
        return ""
    end
    
    return string.match(str, "^%s*(.-)%s*$") or ""
end

-- 检查字符串是否以指定前缀开头
function utils.starts_with(str, prefix)
    if not str or not prefix then
        return false
    end
    
    return string.sub(str, 1, #prefix) == prefix
end

-- 检查字符串是否以指定后缀结尾
function utils.ends_with(str, suffix)
    if not str or not suffix then
        return false
    end
    
    return string.sub(str, -#suffix) == suffix
end

-- 字符串格式化（支持可变参数）
function utils.format_string(format_str, ...)
    if not format_str then
        return ""
    end
    
    if select('#', ...) > 0 then
        return string.format(format_str, ...)
    else
        return format_str
    end
end

-- 时间处理工具函数

-- 获取当前时间戳（毫秒）
function utils.current_time_ms()
    return os.time() * 1000
end

-- 获取当前时间戳（微秒）
function utils.current_time_us()
    return os.time() * 1000000
end

-- 格式化时间戳为可读字符串
function utils.format_timestamp(timestamp, format)
    if not timestamp then
        return ""
    end
    
    -- 支持毫秒和微秒时间戳
    local time_seconds
    if timestamp > 1000000000000 then  -- 毫秒时间戳
        time_seconds = timestamp / 1000
    elseif timestamp > 1000000000000000 then  -- 微秒时间戳
        time_seconds = timestamp / 1000000
    else
        time_seconds = timestamp
    end
    
    format = format or "%Y-%m-%d %H:%M:%S"
    return os.date(format, time_seconds)
end

-- 解析时间戳字符串
function utils.parse_timestamp(timestamp_str)
    if not timestamp_str then
        return nil, "时间戳字符串不能为空"
    end
    
    local timestamp = tonumber(timestamp_str)
    if not timestamp then
        return nil, "无效的时间戳格式"
    end
    
    -- 如果是毫秒时间戳，转换为微秒
    if timestamp < 1000000000000 then  -- 小于2001年的秒时间戳
        return nil, "时间戳格式不支持"
    elseif timestamp < 1000000000000000 then  -- 毫秒时间戳
        timestamp = timestamp * 1000  -- 转换为微秒
    end
    
    return timestamp
end

-- 数据验证工具函数

-- 验证股票代码
function utils.validate_symbol(symbol)
    if not symbol or #symbol == 0 or #symbol > 8 then
        return false, "股票代码无效（长度1-8）"
    end
    
    -- 检查是否为有效的股票代码格式
    if not string.match(symbol, "^%d+$") and not string.match(symbol, "^%u+$") then
        return false, "股票代码格式无效（应为数字或大写字母）"
    end
    
    return true
end

-- 验证数据类型
function utils.validate_data_type(data_type)
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

-- 验证数值范围
function utils.validate_number_range(value, min, max)
    local num = tonumber(value)
    if not num then
        return false, "无效的数值"
    end
    
    if min and num < min then
        return false, string.format("数值不能小于 %s", min)
    end
    
    if max and num > max then
        return false, string.format("数值不能大于 %s", max)
    end
    
    return true, num
end

-- 模块路径设置工具函数

-- 设置Lua模块路径以使用lib目录下的cjson.so和其他共享库
function utils.setup_module_paths()
    -- 设置Lua C模块路径
    package.cpath = package.cpath .. ";../lib/?.so;./lib/?.so;./?.so"
    
    -- 设置Lua模块路径
    package.path = package.path .. ";../lua/?.lua;./lua/?.lua;./?.lua"
    
    return true
end

-- 安全加载cjson模块（如果可用）
function utils.safe_require_cjson()
    local ok, cjson = pcall(require, "cjson")
    if ok then
        return cjson
    else
        -- 如果cjson不可用，提供一个简化的JSON实现
        local simple_json = {}
        
        function simple_json.encode(obj)
            if type(obj) == "table" then
                local parts = {}
                for k, v in pairs(obj) do
                    table.insert(parts, string.format('"%s":"%s"', tostring(k), tostring(v)))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            else
                return tostring(obj)
            end
        end
        
        function simple_json.decode(str)
            local result = {}
            -- 简单的JSON解析（仅支持基本格式）
            str = str:gsub("^%s*{%s*", ""):gsub("%s*}%s*$", "")
            for k, v in str:gmatch('"([^"]+)":"([^"]+)"') do
                result[k] = v
            end
            return result
        end
        
        print("[警告] 使用简化的JSON实现，建议安装cjson库以获得更好的性能")
        return simple_json
    end
end

-- 数据格式化工具函数

-- 格式化数值
function utils.format_number(value, precision)
    precision = precision or 6
    
    if type(value) == "number" then
        return string.format("%." .. precision .. "f", value)
    else
        return tostring(value)
    end
end

-- 格式化字节大小
function utils.format_bytes(bytes)
    if not bytes then
        return "0 B"
    end
    
    local units = {"B", "KB", "MB", "GB", "TB"}
    local unit_index = 1
    
    while bytes >= 1024 and unit_index < #units do
        bytes = bytes / 1024
        unit_index = unit_index + 1
    end
    
    return string.format("%.2f %s", bytes, units[unit_index])
end

-- 格式化时间间隔
function utils.format_duration(seconds)
    if not seconds then
        return "0s"
    end
    
    local units = {
        {value = 86400, suffix = "d"},
        {value = 3600, suffix = "h"},
        {value = 60, suffix = "m"},
        {value = 1, suffix = "s"}
    }
    
    local result = ""
    local remaining = seconds
    
    for _, unit in ipairs(units) do
        if remaining >= unit.value then
            local count = math.floor(remaining / unit.value)
            result = result .. count .. unit.suffix .. " "
            remaining = remaining % unit.value
        end
    end
    
    return result:trim()
end

-- 表操作工具函数

-- 深度复制表
function utils.deep_copy(original)
    if type(original) ~= "table" then
        return original
    end
    
    local copy = {}
    for k, v in pairs(original) do
        copy[utils.deep_copy(k)] = utils.deep_copy(v)
    end
    
    return copy
end

-- 合并多个表
function utils.merge_tables(...)
    local result = {}
    
    for i = 1, select('#', ...) do
        local table_arg = select(i, ...)
        if type(table_arg) == "table" then
            for k, v in pairs(table_arg) do
                result[k] = v
            end
        end
    end
    
    return result
end

-- 获取表的大小
function utils.table_size(t)
    if type(t) ~= "table" then
        return 0
    end
    
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    
    return count
end

-- 检查表是否为空
function utils.table_is_empty(t)
    if type(t) ~= "table" then
        return true
    end
    
    return next(t) == nil
end

-- 错误处理工具函数

-- 安全执行函数（捕获异常）
function utils.safe_execute(func, ...)
    local success, result = pcall(func, ...)
    if success then
        return true, result
    else
        return false, result
    end
end

-- 重试执行函数
function utils.retry_execute(func, max_retries, delay_ms, ...)
    max_retries = max_retries or 3
    delay_ms = delay_ms or 1000
    
    for attempt = 1, max_retries do
        local success, result = utils.safe_execute(func, ...)
        if success then
            return true, result
        end
        
        if attempt < max_retries then
            -- 等待一段时间后重试
            local timer = require("lzmq.timer")
            timer.sleep(delay_ms)
        end
    end
    
    return false, "达到最大重试次数"
end

-- 性能监控工具函数

-- 创建性能计时器
function utils.create_timer()
    local start_time = os.clock()
    
    return {
        elapsed = function()
            return os.clock() - start_time
        end,
        reset = function()
            start_time = os.clock()
        end
    }
end

-- 批量操作工具函数

-- 批量处理数组
function utils.batch_process(array, batch_size, processor)
    if not array or type(array) ~= "table" or not processor then
        return false, "参数错误"
    end
    
    batch_size = batch_size or 1000
    local results = {}
    
    for i = 1, #array, batch_size do
        local batch = {}
        for j = i, math.min(i + batch_size - 1, #array) do
            table.insert(batch, array[j])
        end
        
        local success, result = processor(batch)
        if not success then
            return false, result
        end
        
        table.insert(results, result)
    end
    
    return true, results
end

-- 数学工具函数

-- 生成随机数
function utils.random_range(min, max)
    math.randomseed(os.time())
    return math.random(min, max)
end

-- 限制数值在指定范围内
function utils.clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    else
        return value
    end
end

-- 文件操作工具函数

-- 检查文件是否存在
function utils.file_exists(filename)
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- 读取文件内容
function utils.read_file(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil, "文件不存在: " .. filename
    end
    
    local content = file:read("*a")
    file:close()
    
    return content
end

-- 写入文件内容
function utils.write_file(filename, content)
    local file = io.open(filename, "w")
    if not file then
        return false, "无法打开文件: " .. filename
    end
    
    file:write(content)
    file:close()
    
    return true
end

return utils