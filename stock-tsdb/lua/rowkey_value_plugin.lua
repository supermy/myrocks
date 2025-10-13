-- RowKey与Value编码插件框架
-- 支持多种业务场景的编码方案



-- 插件框架基类
local RowKeyValuePlugin = {}
RowKeyValuePlugin.__index = RowKeyValuePlugin

function RowKeyValuePlugin:new(name, version)
    local obj = setmetatable({}, RowKeyValuePlugin)
    obj.name = name or "unknown"
    obj.version = version or "1.0.0"
    obj.description = ""
    return obj
end

function RowKeyValuePlugin:get_name()
    return self.name
end

function RowKeyValuePlugin:get_version()
    return self.version
end

function RowKeyValuePlugin:get_description()
    return self.description
end

-- 抽象方法：编码RowKey
function RowKeyValuePlugin:encode_rowkey(...)
    error("子类必须实现encode_rowkey方法")
end

-- 抽象方法：解码RowKey
function RowKeyValuePlugin:decode_rowkey(rowkey)
    error("子类必须实现decode_rowkey方法")
end

-- 抽象方法：编码Value
function RowKeyValuePlugin:encode_value(...)
    error("子类必须实现encode_value方法")
end

-- 抽象方法：解码Value
function RowKeyValuePlugin:decode_value(value)
    error("子类必须实现decode_value方法")
end

-- 抽象方法：获取插件信息
function RowKeyValuePlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {}
    }
end

-- 股票行情数据插件（保持现有编码方案）
local StockQuotePlugin = {}
StockQuotePlugin.__index = StockQuotePlugin

function StockQuotePlugin:new()
    local obj = setmetatable({}, StockQuotePlugin)
    obj.name = "stock_quote"
    obj.version = "1.0.0"
    obj.description = "股票行情数据RowKey/Value编码插件，保持现有编码方案"
    obj.BLOCK_SIZE_SECONDS = 30
    obj.MICROSECONDS_PER_SECOND = 1000000
    
    -- 添加缓存机制优化重复计算
    obj.rowkey_cache = {}
    obj.value_cache = {}
    obj.cache_size = 1000  -- 限制缓存大小
    
    -- 预分配常用字符串和模板，减少内存分配
    obj.empty_stock_code = string.rep(" ", 6)
    obj.zero_qualifier = "00000000"
    obj.json_template = {
        '{"open":', ',"high":', ',"low":', ',"close":', ',"volume":', ',"amount":', '}'
    }
    obj.field_order = {"open", "high", "low", "close", "volume", "amount"}
    
    return obj
end

-- 确保插件继承基类的方法
function StockQuotePlugin:get_name()
    return self.name
end

function StockQuotePlugin:get_version()
    return self.version
end

function StockQuotePlugin:get_description()
    return self.description
end

function StockQuotePlugin:encode_rowkey(stock_code, timestamp, market)
    -- 编码股票数据RowKey（优化版本）
    -- 格式: stock|market|code|timestamp
    
    -- 缓存键生成
    local cache_key = stock_code .. "|" .. tostring(timestamp) .. "|" .. (market or "SH")
    
    -- 检查缓存
    if self.rowkey_cache[cache_key] then
        return self.rowkey_cache[cache_key].rowkey, self.rowkey_cache[cache_key].qualifier
    end
    
    local timestamp_seconds = math.floor(timestamp)
    local block_start = math.floor(timestamp_seconds / self.BLOCK_SIZE_SECONDS) * self.BLOCK_SIZE_SECONDS
    local micro_offset = math.floor((timestamp - timestamp_seconds) * self.MICROSECONDS_PER_SECOND)
    
    -- 使用预分配字符串和table.concat优化
    local key_parts = {"stock", market or "SH", stock_code, tostring(block_start)}
    local rowkey = table.concat(key_parts, "|")
    
    -- 优化qualifier生成
    local qualifier
    if micro_offset == 0 then
        qualifier = self.zero_qualifier
    else
        qualifier = string.format("%08x", micro_offset)
    end
    
    -- 更新缓存
    if #self.rowkey_cache >= self.cache_size then
        -- 简单的LRU策略：移除第一个元素
        local first_key = next(self.rowkey_cache)
        if first_key then
            self.rowkey_cache[first_key] = nil
        end
    end
    
    self.rowkey_cache[cache_key] = {rowkey = rowkey, qualifier = qualifier}
    
    return rowkey, qualifier
end

function StockQuotePlugin:decode_rowkey(rowkey)
    -- 解码股票数据RowKey
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 4 and parts[1] == "stock" then
        return {
            type = "stock",
            market = parts[2],
            code = parts[3],
            timestamp = tonumber(parts[4])
        }
    end
    
    return {type = "unknown"}
end

function StockQuotePlugin:encode_value(data)
    -- 编码股票数据Value（JSON格式，优化版本）
    -- 使用预分配模板和缓存机制，避免频繁字符串拼接
    
    -- 缓存键生成
    local cache_key = string.format("%.6f|%.6f|%.6f|%.6f|%.0f|%.6f", 
        data.open or 0, data.high or 0, data.low or 0, 
        data.close or 0, data.volume or 0, data.amount or 0)
    
    -- 检查缓存
    if self.value_cache[cache_key] then
        return self.value_cache[cache_key]
    end
    
    -- 使用预分配模板构建JSON
    local json_parts = {}
    local has_data = false
    
    for i, field in ipairs(self.field_order) do
        local value = data[field]
        if value ~= nil then
            if has_data then
                table.insert(json_parts, self.json_template[i])
            else
                table.insert(json_parts, string.sub(self.json_template[i], 2)) -- 移除开头的逗号
                has_data = true
            end
            table.insert(json_parts, tostring(value))
        end
    end
    
    -- 如果没有数据，返回空对象
    if not has_data then
        return "{}"
    end
    
    -- 添加结束花括号
    table.insert(json_parts, self.json_template[#self.json_template])
    
    local result = table.concat(json_parts)
    
    -- 更新缓存
    if #self.value_cache >= self.cache_size then
        -- 简单的LRU策略：移除第一个元素
        local first_key = next(self.value_cache)
        if first_key then
            self.value_cache[first_key] = nil
        end
    end
    
    self.value_cache[cache_key] = result
    
    return result
end

function StockQuotePlugin:decode_value(value_str)
    -- 解码股票数据Value（JSON格式，优化版本）
    -- 使用更可靠的JSON解析方法
    
    if not value_str or value_str == "" or value_str == "{}" then
        return {}
    end
    
    -- 缓存键检查
    if self.value_cache[value_str] then
        return self.value_cache[value_str]
    end
    
    local result = {}
    
    -- 使用字符串模式匹配解析JSON
    for field, value in string.gmatch(value_str, '"([^"]+)":([^,}]+)') do
        -- 检查字段是否在预定义列表中
        local is_valid_field = false
        for _, valid_field in ipairs(self.field_order) do
            if field == valid_field then
                is_valid_field = true
                break
            end
        end
        
        if is_valid_field then
            local num_val = tonumber(value)
            if num_val then
                result[field] = num_val
            else
                -- 处理可能的字符串值
                result[field] = string.gsub(value, '^"(.*)"$', '%1')
            end
        end
    end
    
    -- 更新缓存
    if #self.value_cache >= self.cache_size then
        local first_key = next(self.value_cache)
        if first_key then
            self.value_cache[first_key] = nil
        end
    end
    
    self.value_cache[value_str] = result
    
    return result
end

function StockQuotePlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"stock_quote", "stock_price", "stock_volume"},
        encoding_format = "JSON",
        key_format = "stock|market|code|timestamp",
        features = {
            "variable_length_key",
            "json_value_encoding",
            "microsecond_precision",
            "30_second_blocks"
        }
    }
end

-- IOT业务数据插件（新增编码方案）
local IOTDataPlugin = {}
IOTDataPlugin.__index = IOTDataPlugin

function IOTDataPlugin:new()
    local obj = setmetatable({}, IOTDataPlugin)
    obj.name = "iot_data"
    obj.version = "1.0.0"
    obj.description = "IOT业务数据RowKey/Value编码插件，采用二进制紧凑格式"
    
    -- 添加预编译映射表优化
    obj.metric_type_map = {
        temperature = 0x01, humidity = 0x02, pressure = 0x03,
        light = 0x04, sound = 0x05, motion = 0x06
    }
    obj.reverse_metric_map = {
        [0x01] = "temperature", [0x02] = "humidity", [0x03] = "pressure",
        [0x04] = "light", [0x05] = "sound", [0x06] = "motion"
    }
    
    return obj
end

-- 确保IOT插件继承基类的方法
function IOTDataPlugin:get_name()
    return self.name
end

function IOTDataPlugin:get_version()
    return self.version
end

function IOTDataPlugin:get_description()
    return self.description
end

function IOTDataPlugin:encode_rowkey(device_id, timestamp, metric_type, location)
    -- IOT数据RowKey编码（优化版本）
    -- 格式: device_id(8字节) + timestamp(8字节) + metric_type(1字节) + location(3字节)
    
    -- 使用预编译映射表，避免每次创建新表
    local metric_byte = string.char(self.metric_type_map[metric_type] or 0x00)
    
    -- 使用单次格式化，避免多次字符串操作
    return string.sub(string.format("%-8s%-3s", device_id, location or ""), 1, 11) .. 
           self:uint64_to_bytes(timestamp) .. metric_byte, ""
end

function IOTDataPlugin:decode_rowkey(rowkey)
    -- IOT数据RowKey解码（优化版本）
    if #rowkey ~= 20 then
        return {type = "invalid", error = "invalid rowkey length"}
    end
    
    -- 使用预编译反向映射表
    local metric_byte = string.byte(rowkey, 17)
    local metric_type = self.reverse_metric_map[metric_byte] or "unknown"
    
    -- 使用单次字符串操作
    return {
        type = "iot",
        device_id = string.gsub(string.sub(rowkey, 1, 8), "%s+$", ""),
        timestamp = self:bytes_to_uint64(string.sub(rowkey, 9, 16)),
        metric_type = metric_type,
        location = string.gsub(string.sub(rowkey, 18, 20), "%s+$", "")
    }
end

function IOTDataPlugin:encode_value(data)
    -- IOT数据Value编码（二进制紧凑格式）
    -- 格式: value(4字节float) + quality(1字节) + reserved(11字节) = 16字节固定长度
    
    local value = data.value or 0.0
    local quality = data.quality or 0
    
    -- 将浮点数转换为4字节（简化实现）
    local value_bytes = self:float_to_bytes(value)
    local quality_byte = string.char(quality)
    local reserved = string.rep("\0", 11)  -- 预留空间
    
    return value_bytes .. quality_byte .. reserved
end

function IOTDataPlugin:decode_value(value)
    -- IOT数据Value解码
    if #value ~= 16 then
        return {error = "invalid value length"}
    end
    
    local value_bytes = string.sub(value, 1, 4)
    local quality_byte = string.sub(value, 5, 5)
    
    local float_value = self:bytes_to_float(value_bytes)
    local quality = string.byte(quality_byte)
    
    return {
        value = float_value,
        quality = quality
    }
end

-- 辅助方法：整数转字节
function IOTDataPlugin:uint64_to_bytes(num)
    local bytes = {}
    local n = tonumber(num) or 0  -- 确保是数字类型
    for i = 7, 0, -1 do
        bytes[i+1] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(bytes)
end

function IOTDataPlugin:bytes_to_uint64(bytes)
    local num = 0
    for i = 1, 8 do
        num = num * 256 + string.byte(bytes, i)
    end
    return num
end

-- 辅助方法：浮点数转字节（优化实现）
function IOTDataPlugin:float_to_bytes(num)
    -- 优化的浮点数转换，使用位操作和预分配
    local sign = num < 0 and 1 or 0
    num = math.abs(num)
    
    -- 使用更高效的整数和小数分离
    local integer = math.floor(num)
    local fraction = math.floor((num - integer) * 256)
    
    -- 预分配字节数组，避免多次concat
    return string.char(
        sign * 128 + math.floor(integer / 65536),
        math.floor(integer / 256) % 256,
        integer % 256,
        fraction
    )
end

function IOTDataPlugin:bytes_to_float(bytes)
    -- 优化的字节转浮点数
    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    return (b1 >= 128 and -1 or 1) * (((b1 % 128) * 65536 + b2 * 256 + b3) + b4 / 256.0)
end

function IOTDataPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"iot_temperature", "iot_humidity", "iot_pressure", "iot_light", "iot_sound", "iot_motion"},
        encoding_format = "Binary",
        key_format = "device_id(8B) + timestamp(8B) + metric_type(1B) + location(3B) = 20B",
        value_format = "value(4B) + quality(1B) + reserved(11B) = 16B",
        features = {
            "fixed_length_key",
            "binary_value_encoding",
            "compact_format",
            "16_byte_fixed_value"
        }
    }
end

-- 插件管理器
local PluginManager = {}
PluginManager.__index = PluginManager

function PluginManager:new()
    local obj = setmetatable({}, PluginManager)
    obj.plugins = {}
    obj.default_plugin = nil
    return obj
end

function PluginManager:register_plugin(plugin)
    if not plugin or not plugin.get_name then
        return false, "无效的插件"
    end
    
    local name = plugin:get_name()
    self.plugins[name] = plugin
    
    -- 设置第一个插件为默认插件
    if not self.default_plugin then
        self.default_plugin = name
    end
    
    return true
end

function PluginManager:get_plugin(name)
    name = name or self.default_plugin
    return self.plugins[name]
end

function PluginManager:list_plugins()
    local list = {}
    for name, plugin in pairs(self.plugins) do
        table.insert(list, {
            name = name,
            version = plugin:get_version(),
            description = plugin:get_description()
        })
    end
    return list
end

function PluginManager:get_default_plugin()
    return self:get_plugin(self.default_plugin)
end

function PluginManager:set_default_plugin(name)
    if self.plugins[name] then
        self.default_plugin = name
        return true
    end
    return false, "插件不存在"
end

-- 创建默认插件管理器实例
local plugin_manager = PluginManager:new()

-- 注册内置插件
plugin_manager:register_plugin(StockQuotePlugin:new())
plugin_manager:register_plugin(IOTDataPlugin:new())

-- 注册业务插件
local FinancialQuotePlugin = require "lua.financial_quote_plugin"
local OrderManagementPlugin = require "lua.order_management_plugin"
local PaymentSystemPlugin = require "lua.payment_system_plugin"
local InventoryManagementPlugin = require "lua.inventory_management_plugin"
local SMSDeliveryPlugin = require "lua.sms_delivery_plugin"

plugin_manager:register_plugin(FinancialQuotePlugin:new())
plugin_manager:register_plugin(OrderManagementPlugin:new())
plugin_manager:register_plugin(PaymentSystemPlugin:new())
plugin_manager:register_plugin(InventoryManagementPlugin:new())
plugin_manager:register_plugin(SMSDeliveryPlugin:new())

-- 注册高性能micro_ts插件（FFI调用micro_ts.so）
local MicroTsPlugin = require "lua.micro_ts_plugin"
plugin_manager:register_plugin(MicroTsPlugin:new())

-- 股票行情数据二进制编码插件
local StockQuoteBinaryPlugin = {}
StockQuoteBinaryPlugin.__index = StockQuoteBinaryPlugin

function StockQuoteBinaryPlugin:new()
    local obj = setmetatable({}, StockQuoteBinaryPlugin)
    obj.name = "stock_quote_binary"
    obj.version = "1.0.0"
    obj.description = "股票行情数据RowKey/Value二进制编码插件，采用紧凑二进制格式"
    obj.BLOCK_SIZE_SECONDS = 30
    obj.MICROSECONDS_PER_SECOND = 1000000
    
    -- 市场代码映射表
    obj.market_map = {
        SH = 0x01, SZ = 0x02, BJ = 0x03, HK = 0x04,
        US = 0x05, JP = 0x06, EU = 0x07, UK = 0x08
    }
    obj.reverse_market_map = {
        [0x01] = "SH", [0x02] = "SZ", [0x03] = "BJ", [0x04] = "HK",
        [0x05] = "US", [0x06] = "JP", [0x07] = "EU", [0x08] = "UK"
    }
    
    -- 缓存机制
    obj.rowkey_cache = {}
    obj.value_cache = {}
    obj.cache_size = 1000
    
    -- 预分配常用字符串，减少内存分配
    obj.empty_stock_code = string.rep(" ", 6)
    obj.zero_qualifier = "00000000"
    
    return obj
end

-- 确保插件继承基类的方法
function StockQuoteBinaryPlugin:get_name()
    return self.name
end

function StockQuoteBinaryPlugin:get_version()
    return self.version
end

function StockQuoteBinaryPlugin:get_description()
    return self.description
end

function StockQuoteBinaryPlugin:encode_rowkey(stock_code, timestamp, market)
    -- 编码股票数据RowKey（二进制紧凑格式）
    -- 格式: market(1字节) + stock_code(6字节) + timestamp(8字节) = 15字节固定长度
    
    -- 缓存键生成
    local cache_key = stock_code .. "|" .. tostring(timestamp) .. "|" .. (market or "SH")
    
    -- 检查缓存
    if self.rowkey_cache[cache_key] then
        return self.rowkey_cache[cache_key].rowkey, self.rowkey_cache[cache_key].qualifier
    end
    
    local market_code = self.market_map[market or "SH"] or 0x00
    
    -- 股票代码处理（最多6字节）- 优化字符串操作
    local code_bytes = stock_code
    if #code_bytes < 6 then
        code_bytes = code_bytes .. string.sub(self.empty_stock_code, #code_bytes + 1)
    elseif #code_bytes > 6 then
        code_bytes = string.sub(code_bytes, 1, 6)
    end
    
    -- 时间戳处理（8字节）- 优化计算
    local timestamp_seconds = math.floor(timestamp)
    local block_start = math.floor(timestamp_seconds / self.BLOCK_SIZE_SECONDS) * self.BLOCK_SIZE_SECONDS
    local micro_offset = math.floor((timestamp - timestamp_seconds) * self.MICROSECONDS_PER_SECOND)
    
    -- 组合RowKey - 使用table.concat减少字符串连接操作
    local timestamp_bytes = self:uint64_to_bytes(block_start)
    local rowkey = string.char(market_code) .. code_bytes .. timestamp_bytes
    
    -- 优化qualifier生成
    local qualifier
    if micro_offset == 0 then
        qualifier = self.zero_qualifier
    else
        qualifier = string.format("%08x", micro_offset)
    end
    
    -- 更新缓存
    if #self.rowkey_cache >= self.cache_size then
        -- 简单的LRU策略：移除第一个元素
        local first_key = next(self.rowkey_cache)
        if first_key then
            self.rowkey_cache[first_key] = nil
        end
    end
    
    self.rowkey_cache[cache_key] = {rowkey = rowkey, qualifier = qualifier}
    
    return rowkey, qualifier
end

function StockQuoteBinaryPlugin:decode_rowkey(rowkey)
    -- 解码股票数据RowKey（二进制格式）
    if #rowkey ~= 15 then
        return {type = "invalid", error = "invalid rowkey length"}
    end
    
    local market_code = string.byte(rowkey, 1)
    local market = self.reverse_market_map[market_code] or "UNKNOWN"
    local stock_code = string.gsub(string.sub(rowkey, 2, 7), "%s+$", "")
    local timestamp = self:bytes_to_uint64(string.sub(rowkey, 8, 15))
    
    return {
        type = "stock",
        market = market,
        code = stock_code,
        timestamp = timestamp
    }
end

function StockQuoteBinaryPlugin:encode_value(data)
    -- 编码股票数据Value（二进制紧凑格式）
    -- 格式: open(4字节) + high(4字节) + low(4字节) + close(4字节) + volume(8字节) + amount(4字节) = 28字节固定长度
    
    -- 缓存键生成（基于数据内容）
    local cache_key = string.format("%.2f|%.2f|%.2f|%.2f|%d|%.2f", 
        data.open or 0.0, data.high or 0.0, data.low or 0.0, data.close or 0.0,
        data.volume or 0, data.amount or 0.0)
    
    -- 检查缓存
    if self.value_cache[cache_key] then
        return self.value_cache[cache_key]
    end
    
    -- 直接使用数据，避免多次函数调用
    local open = data.open or 0.0
    local high = data.high or 0.0
    local low = data.low or 0.0
    local close = data.close or 0.0
    local volume = data.volume or 0
    local amount = data.amount or 0.0
    
    -- 一次性构建所有字节，减少字符串连接操作
    local value_bytes = {}
    
    -- 价格数据（4个浮点数，每个4字节）
    table.insert(value_bytes, self:float_to_bytes(open))
    table.insert(value_bytes, self:float_to_bytes(high))
    table.insert(value_bytes, self:float_to_bytes(low))
    table.insert(value_bytes, self:float_to_bytes(close))
    
    -- 成交量（8字节整数）
    table.insert(value_bytes, self:uint64_to_bytes(volume))
    
    -- 成交额（4字节浮点数）
    table.insert(value_bytes, self:float_to_bytes(amount))
    
    local result = table.concat(value_bytes)
    
    -- 更新缓存
    if #self.value_cache >= self.cache_size then
        -- 简单的LRU策略：移除第一个元素
        local first_key = next(self.value_cache)
        if first_key then
            self.value_cache[first_key] = nil
        end
    end
    
    self.value_cache[cache_key] = result
    
    return result
end

function StockQuoteBinaryPlugin:decode_value(value)
    -- 解码股票数据Value（二进制格式）
    if #value ~= 28 then
        return {error = "invalid value length"}
    end
    
    local open_bytes = string.sub(value, 1, 4)
    local high_bytes = string.sub(value, 5, 8)
    local low_bytes = string.sub(value, 9, 12)
    local close_bytes = string.sub(value, 13, 16)
    local volume_bytes = string.sub(value, 17, 24)
    local amount_bytes = string.sub(value, 25, 28)
    
    return {
        open = self:bytes_to_float(open_bytes),
        high = self:bytes_to_float(high_bytes),
        low = self:bytes_to_float(low_bytes),
        close = self:bytes_to_float(close_bytes),
        volume = self:bytes_to_uint64(volume_bytes),
        amount = self:bytes_to_float(amount_bytes)
    }
end

-- 辅助方法：整数转字节（优化版本）
function StockQuoteBinaryPlugin:uint64_to_bytes(num)
    local n = tonumber(num) or 0
    -- 使用数学运算替代循环，提高性能
    return string.char(
        math.floor(n / 72057594037927936) % 256,  -- 2^56
        math.floor(n / 281474976710656) % 256,    -- 2^48
        math.floor(n / 1099511627776) % 256,      -- 2^40
        math.floor(n / 4294967296) % 256,         -- 2^32
        math.floor(n / 16777216) % 256,           -- 2^24
        math.floor(n / 65536) % 256,              -- 2^16
        math.floor(n / 256) % 256,
        n % 256
    )
end

function StockQuoteBinaryPlugin:bytes_to_uint64(bytes)
    local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(bytes, 1, 8)
    -- 使用数学运算替代循环，提高性能
    return b1 * 72057594037927936 +  -- 2^56
           b2 * 281474976710656 +    -- 2^48
           b3 * 1099511627776 +      -- 2^40
           b4 * 4294967296 +         -- 2^32
           b5 * 16777216 +           -- 2^24
           b6 * 65536 +              -- 2^16
           b7 * 256 + b8
end

-- 辅助方法：浮点数转字节（改进版本）
function StockQuoteBinaryPlugin:float_to_bytes(num)
    -- 使用更精确的浮点数编码方法
    local sign = num < 0 and 1 or 0
    num = math.abs(num)
    
    local integer = math.floor(num)
    local fraction = num - integer
    
    -- 将小数部分转换为24位精度
    local fraction_int = math.floor(fraction * 16777216)  -- 2^24
    
    return string.char(
        sign * 128 + math.floor(integer / 65536) % 128,
        math.floor(integer / 256) % 256,
        integer % 256,
        math.floor(fraction_int / 65536) % 256
    )
end

function StockQuoteBinaryPlugin:bytes_to_float(bytes)
    local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
    local sign = b1 >= 128 and -1 or 1
    local integer = (b1 % 128) * 65536 + b2 * 256 + b3
    local fraction = b4 / 256.0
    
    return sign * (integer + fraction)
end

function StockQuoteBinaryPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"stock_quote", "stock_price", "stock_volume", "stock_binary"},
        encoding_format = "Binary",
        key_format = "market(1B) + stock_code(6B) + timestamp(8B) = 15B",
        value_format = "open(4B) + high(4B) + low(4B) + close(4B) + volume(8B) + amount(8B) = 32B",
        features = {
            "fixed_length_key",
            "binary_value_encoding",
            "compact_format",
            "15_byte_fixed_key",
            "32_byte_fixed_value",
            "microsecond_precision",
            "30_second_blocks"
        }
    }
end

-- 注册股票行情二进制编码插件
plugin_manager:register_plugin(StockQuoteBinaryPlugin:new())

-- 模块导出
return {
    RowKeyValuePlugin = RowKeyValuePlugin,
    StockQuotePlugin = StockQuotePlugin,
    StockQuoteBinaryPlugin = StockQuoteBinaryPlugin,
    IOTDataPlugin = IOTDataPlugin,
    PluginManager = PluginManager,
    default_manager = plugin_manager
}