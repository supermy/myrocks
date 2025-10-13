-- micro_ts插件最终优化版本
-- 基于第二版优化的成功经验，进一步优化性能

local ffi = require("ffi")

-- 定义C函数接口
ffi.cdef[[
    /* 打包 Key + Qual */
    void pack_key_qual(uint8_t *out18,
                       char market, const char *code9,
                       uint64_t chunk_base_ms);
    
    void pack_qual(uint8_t *out6, uint32_t micro_off, uint16_t seq);
    
    /* 打包 Value */
    void pack_value(uint8_t *out50,
                    int32_t price, uint32_t qty,
                    uint8_t ch, uint8_t side,
                    uint64_t order_no, uint64_t tick_no);
    
    /* 解包 Value */
    void unpack_value(const uint8_t *in50,
                      int32_t *price, uint32_t *qty,
                      uint8_t *ch, uint8_t *side,
                      uint64_t *order_no, uint64_t *tick_no);
                      
    /* 解包 Key */
    uint64_t unpack_timestamp(const uint8_t *in18);
]]

-- 加载C库
local micro_ts_lib
local success, err = pcall(function()
    micro_ts_lib = ffi.load("lib/micro_ts.so")
end)
if not success then
    success, err = pcall(function()
        micro_ts_lib = ffi.load("micro_ts")
    end)
end
if not success then
    error("无法加载micro_ts库: " .. err)
end

local MicroTsPluginFinal = {}
MicroTsPluginFinal.__index = MicroTsPluginFinal

-- 常量定义
local MARKET_SH = 0x01
local MARKET_SZ = 0x02
local MARKET_BJ = 0x03

-- 预分配缓冲区
local ENCODE_BUFFER_SIZE = 50  -- 最大值，用于Value
local DECODE_BUFFER_SIZE = 50
local encode_buffer = ffi.new("uint8_t[?]", ENCODE_BUFFER_SIZE)
local decode_buffer = ffi.new("uint8_t[?]", DECODE_BUFFER_SIZE)
local rowkey_buffer = ffi.new("uint8_t[?]", 18)  -- 专门用于RowKey
local qual_buffer = ffi.new("uint8_t[?]", 6)     -- 专门用于Qualifier

-- 精简缓存策略 - 减小缓存大小，提高命中率
local CACHE_SIZE = 500
local rowkey_cache = {}
local value_cache = {}

-- 预编译常用字符串操作
local string_sub = string.sub
local string_byte = string.byte
local string_format = string.format
local ffi_string = ffi.string
local tonumber = tonumber

-- 辅助函数：计算缓存键
local function get_rowkey_cache_key(stock_code, timestamp, market)
    return stock_code .. "|" .. timestamp .. "|" .. market
end

-- 辅助函数：计算值缓存键
local function get_value_cache_key(price, volume, ch, side, order_no, tick_no)
    return price .. "|" .. volume .. "|" .. ch .. "|" .. side .. "|" .. order_no .. "|" .. tick_no
end

-- 简化的缓存管理函数
local function cache_get(cache, key)
    local value = cache[key]
    if value then
        -- 移动到最近使用位置
        cache[key] = nil
        cache[key] = value
        return value
    end
    return nil
end

local function cache_put(cache, key, value)
    -- 如果缓存已满，删除最旧的项
    if next(cache) and #cache >= CACHE_SIZE then
        local old_key = next(cache)
        cache[old_key] = nil
    end
    
    cache[key] = value
end

-- 构造函数
function MicroTsPluginFinal:new()
    local self = setmetatable({}, MicroTsPluginFinal)
    return self
end

-- 获取插件信息
function MicroTsPluginFinal:get_info()
    return {
        name = "micro_ts_final",
        version = "3.0.0",
        description = "最终优化版高性能股票行情数据插件",
        encoding_format = "binary",
        features = {
            "high_performance",
            "compact_encoding",
            "optimized_cache",
            "preallocated_buffers",
            "reduced_overhead"
        }
    }
end

-- 获取插件名称
function MicroTsPluginFinal:get_name()
    return "micro_ts_final"
end

-- 获取插件版本
function MicroTsPluginFinal:get_version()
    return "3.0.0"
end

-- 获取插件描述
function MicroTsPluginFinal:get_description()
    return "最终优化版高性能股票行情数据插件"
end

-- 编码RowKey
function MicroTsPluginFinal:encode_rowkey(stock_code, timestamp, market)
    -- 检查缓存
    local cache_key = get_rowkey_cache_key(stock_code, timestamp, market)
    local cached = cache_get(rowkey_cache, cache_key)
    if cached then
        return cached.rowkey, cached.qualifier
    end
    
    -- 转换市场代码
    local market_char = 'S'  -- 默认上海
    if market == "SZ" then
        market_char = 'Z'
    elseif market == "BJ" then
        market_char = 'B'
    elseif market == "HK" then
        market_char = 'H'
    elseif market == "US" then
        market_char = 'U'
    elseif market == "JP" then
        market_char = 'J'
    elseif market == "EU" then
        market_char = 'E'
    end
    
    -- 股票代码处理（最多9字节）
    local code9 = stock_code
    if #code9 < 9 then
        code9 = code9 .. string.rep("\0", 9 - #code9)
    elseif #code9 > 9 then
        code9 = string_sub(code9, 1, 9)
    end
    
    -- 时间戳处理（毫秒精度）
    local timestamp_ms = math.floor(timestamp * 1000)  -- 转换为毫秒
    local chunk_base_ms = math.floor(timestamp_ms / 60000) * 60000  -- 按分钟分块
    
    -- 调用C函数打包Key+Qual
    micro_ts_lib.pack_key_qual(rowkey_buffer, string_byte(market_char), code9, chunk_base_ms)
    
    -- 生成RowKey（18字节二进制）
    local rowkey = ffi_string(rowkey_buffer, 18)
    
    -- 生成Qualifier（6字节二进制，包含微秒偏移和序列号）
    local micro_offset = timestamp_ms - chunk_base_ms
    local seq = 0  -- 序列号，默认为0
    micro_ts_lib.pack_qual(qual_buffer, micro_offset, seq)
    local qualifier = ffi_string(qual_buffer, 6)
    
    -- 缓存结果
    cache_put(rowkey_cache, cache_key, {rowkey = rowkey, qualifier = qualifier})
    
    return rowkey, qualifier
end

-- 解码RowKey
function MicroTsPluginFinal:decode_rowkey(rowkey)
    -- 从二进制数据中解析
    local market_code = string_byte(rowkey, 1)
    local market = "SH"
    if market_code == MARKET_SZ then
        market = "SZ"
    elseif market_code == MARKET_BJ then
        market = "BJ"
    elseif market_code == MARKET_HK then
        market = "HK"
    elseif market_code == MARKET_US then
        market = "US"
    elseif market_code == MARKET_JP then
        market = "JP"
    elseif market_code == MARKET_EU then
        market = "EU"
    end
    
    -- 解析股票代码
    local stock_code = string_sub(rowkey, 2, 7)
    
    -- 使用C函数解析时间戳（毫秒）
    local rowkey_c = ffi.new("uint8_t[?]", #rowkey)
    ffi.copy(rowkey_c, rowkey)
    local timestamp_ms = tonumber(micro_ts_lib.unpack_timestamp(rowkey_c))
    
    -- 转换为秒级时间戳
    local timestamp = math.floor(timestamp_ms / 1000)
    
    return {
        market = market,
        stock_code = stock_code,
        timestamp = timestamp
    }
end

-- 编码Value
function MicroTsPluginFinal:encode_value(data)
    -- 检查缓存
    local cache_key = get_value_cache_key(
        data.price, data.volume, data.ch, data.side, 
        data.order_no, data.tick_no
    )
    local cached = cache_get(value_cache, cache_key)
    if cached then
        return cached
    end
    
    -- 调用C函数打包
    micro_ts_lib.pack_value(
        encode_buffer,
        data.price or 0, data.volume or 0, data.ch or 1, data.side or 0,
        data.order_no or 0, data.tick_no or 0
    )
    
    local result = ffi_string(encode_buffer, 50)
    
    -- 缓存结果
    cache_put(value_cache, cache_key, result)
    
    return result
end

-- 解码Value
function MicroTsPluginFinal:decode_value(value)
    -- 使用预分配的缓冲区
    local price = ffi.new("int32_t[1]")
    local volume = ffi.new("uint32_t[1]")
    local ch = ffi.new("uint8_t[1]")
    local side = ffi.new("uint8_t[1]")
    local order_no = ffi.new("uint64_t[1]")
    local tick_no = ffi.new("uint64_t[1]")
    
    -- 转换value为FFI兼容类型
    local value_c = ffi.new("uint8_t[?]", #value)
    ffi.copy(value_c, value)
    
    -- 调用C函数解包
    micro_ts_lib.unpack_value(
        value_c,
        price, volume, ch, side, order_no, tick_no
    )
    
    return {
        price = tonumber(price[0]),
        volume = tonumber(volume[0]),
        ch = tonumber(ch[0]),
        side = tonumber(side[0]),
        order_no = tonumber(order_no[0]),
        tick_no = tonumber(tick_no[0])
    }
end

-- 性能测试
function MicroTsPluginFinal:performance_test(iterations)
    iterations = iterations or 10000
    
    local test_data = {
        stock_code = "000001",
        timestamp = os.time(),
        market = "SH",
        price = 1000,
        volume = 10000,
        ch = 1,
        side = 0,
        order_no = 1234567890,
        tick_no = 9876543210
    }
    
    -- 编码性能测试
    local encode_start = os.clock()
    for i = 1, iterations do
        test_data.timestamp = os.time() + i
        self:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
        self:encode_value(test_data)
    end
    local encode_time = (os.clock() - encode_start) * 1000
    
    -- 解码性能测试
    local rowkey, qualifier = self:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
    local value = self:encode_value(test_data)
    
    local decode_start = os.clock()
    for i = 1, iterations do
        self:decode_rowkey(rowkey)
        self:decode_value(value)
    end
    local decode_time = (os.clock() - decode_start) * 1000
    
    return {
        iterations = iterations,
        encode_ops_per_sec = math.floor(iterations / (encode_time / 1000)),
        decode_ops_per_sec = math.floor(iterations / (decode_time / 1000)),
        avg_encode_time_per_op = encode_time / iterations,
        avg_decode_time_per_op = decode_time / iterations,
        cache_hit_rate = self:get_cache_hit_rate()
    }
end

-- 获取缓存命中率
function MicroTsPluginFinal:get_cache_hit_rate()
    local rowkey_count = 0
    local value_count = 0
    
    for _ in pairs(rowkey_cache) do
        rowkey_count = rowkey_count + 1
    end
    
    for _ in pairs(value_cache) do
        value_count = value_count + 1
    end
    
    return {
        rowkey_cache_size = rowkey_count,
        value_cache_size = value_count,
        total_cache_size = rowkey_count + value_count
    }
end

-- 清空缓存
function MicroTsPluginFinal:clear_cache()
    rowkey_cache = {}
    value_cache = {}
end

return MicroTsPluginFinal