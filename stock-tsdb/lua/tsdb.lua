--
-- 股票行情数据TSDB系统 - Lua业务逻辑
-- 提供时间序列数据的核心处理逻辑
--

local tsdb = {}
local ffi = require "ffi"

-- 加载工具函数并设置模块路径
local utils = require "commons.utils"
utils.setup_module_paths()
local cjson = utils.safe_require_cjson()

-- 配置表
local config = {
    -- 数据块大小（秒）
    block_size = 30,
    
    -- 最大数据点数量（30秒 * 1000点/秒）
    max_points_per_block = 30000,
    
    -- 压缩配置
    compression = {
        enabled = true,
        level = 6,
        algorithm = "zstd"
    },
    
    -- 缓存配置
    cache = {
        enabled = true,
        max_blocks = 1000,
        ttl = 300  -- 5分钟
    },
    
    -- 数据质量配置
    quality = {
        good = 100,
        uncertain = 50,
        bad = 0
    }
}

-- 数据块缓存
local block_cache = {}
local cache_stats = {
    hits = 0,
    misses = 0,
    evictions = 0
}

-- 数据类型定义
local DATA_TYPES = {
    PRICE = 0,      -- 价格
    VOLUME = 1,     -- 成交量
    BID = 2,        -- 买一
    ASK = 3,        -- 卖一
    OPEN = 4,       -- 开盘价
    HIGH = 5,       -- 最高价
    LOW = 6,        -- 最低价
    CLOSE = 7,      -- 收盘价
    TURNOVER = 8    -- 成交额
}

-- 工具函数
local function get_block_start_time(timestamp)
    -- 将时间戳对齐到30秒边界
    return math.floor(timestamp / (config.block_size * 1000000)) * config.block_size * 1000000
end

local function get_block_end_time(start_time)
    return start_time + config.block_size * 1000000 - 1
end

local function create_row_key(symbol, timestamp, data_type)
    -- RowKey格式: [股票代码(8字节)][时间戳(8字节)][数据类型(1字节)]
    local block_start = get_block_start_time(timestamp)
    local symbol_padded = string.format("%-8s", symbol):sub(1, 8)
    local key = symbol_padded .. string.pack(">I8", block_start) .. string.pack("B", data_type or 0)
    return key
end

local function parse_row_key(key)
    -- 解析RowKey
    local symbol = key:sub(1, 8):gsub("%s+$", "")
    local timestamp = string.unpack(">I8", key:sub(9, 16))
    local data_type = string.unpack("B", key:sub(17, 17))
    return symbol, timestamp, data_type
end

local function validate_data_point(symbol, timestamp, value, data_type)
    -- 验证数据点
    if not symbol or #symbol == 0 or #symbol > 8 then
        return false, "股票代码无效"
    end
    
    if not timestamp or timestamp <= 0 then
        return false, "时间戳无效"
    end
    
    if not value or type(value) ~= "number" then
        return false, "数据值无效"
    end
    
    if data_type and not DATA_TYPES[data_type] then
        return false, "数据类型无效"
    end
    
    return true
end

-- 数据块操作
function tsdb.create_data_block(symbol, start_time, data_type)
    -- 创建新的数据块
    local block = {
        symbol = symbol,
        start_time = start_time,
        end_time = get_block_end_time(start_time),
        data_type = data_type or DATA_TYPES.PRICE,
        point_count = 0,
        compression_type = 0,
        points = {}
    }
    
    return block
end

function tsdb.add_point_to_block(block, timestamp, value, quality)
    -- 向数据块添加数据点
    if block.point_count >= config.max_points_per_block then
        return false, "数据块已满"
    end
    
    if timestamp < block.start_time or timestamp > block.end_time then
        return false, "时间戳超出范围"
    end
    
    -- 计算在块内的偏移
    local offset = math.floor((timestamp - block.start_time) / 1000)  -- 微秒转毫秒
    
    -- 创建数据点
    local point = {
        timestamp = timestamp,
        value = value,
        quality = quality or config.quality.good,
        offset = offset
    }
    
    -- 添加到块中
    table.insert(block.points, point)
    block.point_count = block.point_count + 1
    
    -- 按时间戳排序
    table.sort(block.points, function(a, b) 
        return a.timestamp < b.timestamp 
    end)
    
    return true
end

function tsdb.serialize_block(block)
    -- 序列化数据块
    local data = {
        start_time = block.start_time,
        end_time = block.end_time,
        point_count = block.point_count,
        compression_type = block.compression_type,
        points = block.points
    }
    
    local json_str = cjson.encode(data)
    
    -- 压缩（如果启用）
    if config.compression.enabled then
        -- 这里应该调用压缩库，简化处理
        return json_str, true
    end
    
    return json_str, false
end

function tsdb.deserialize_block(data_str, compressed)
    -- 反序列化数据块
    local data
    
    if compressed then
        -- 解压缩（如果启用）
        -- 这里应该调用解压缩库，简化处理
        data = cjson.decode(data_str)
    else
        data = cjson.decode(data_str)
    end
    
    local block = {
        start_time = data.start_time,
        end_time = data.end_time,
        point_count = data.point_count,
        compression_type = data.compression_type,
        points = data.points
    }
    
    return block
end

-- 缓存操作
function tsdb.get_cached_block(key)
    if not config.cache.enabled then
        return nil
    end
    
    local cached = block_cache[key]
    if cached then
        -- 检查是否过期
        if os.time() - cached.timestamp < config.cache.ttl then
            cache_stats.hits = cache_stats.hits + 1
            return cached.block
        else
            -- 过期，从缓存中移除
            block_cache[key] = nil
            cache_stats.evictions = cache_stats.evictions + 1
        end
    end
    
    cache_stats.misses = cache_stats.misses + 1
    return nil
end

function tsdb.set_cached_block(key, block)
    if not config.cache.enabled then
        return
    end
    
    -- 检查缓存大小
    local cache_size = 0
    for k, v in pairs(block_cache) do
        cache_size = cache_size + 1
    end
    
    -- 如果缓存满了，移除最老的条目
    if cache_size >= config.cache.max_blocks then
        local oldest_key = nil
        oldest_timestamp = math.huge
        
        for k, v in pairs(block_cache) do
            if v.timestamp < oldest_timestamp then
                oldest_timestamp = v.timestamp
                oldest_key = k
            end
        end
        
        if oldest_key then
            block_cache[oldest_key] = nil
            cache_stats.evictions = cache_stats.evictions + 1
        end
    end
    
    -- 添加到缓存
    block_cache[key] = {
        block = block,
        timestamp = os.time()
    }
end

function tsdb.clear_cache()
    block_cache = {}
    cache_stats = { hits = 0, misses = 0, evictions = 0 }
end

function tsdb.get_cache_stats()
    return cache_stats
end

-- 数据写入操作
function tsdb.write_point(symbol, timestamp, value, data_type, quality)
    -- 验证数据
    local valid, error_msg = validate_data_point(symbol, timestamp, value, data_type)
    if not valid then
        return false, error_msg
    end
    
    -- 获取数据块键
    local block_start = get_block_start_time(timestamp)
    local row_key = create_row_key(symbol, block_start, data_type)
    
    -- 检查缓存
    local block = tsdb.get_cached_block(row_key)
    
    if not block then
        -- 从存储中读取数据块
        -- 这里应该调用C接口从RocksDB读取
        -- 简化处理，创建新块
        block = tsdb.create_data_block(symbol, block_start, data_type)
    end
    
    -- 添加数据点
    local success, msg = tsdb.add_point_to_block(block, timestamp, value, quality)
    if not success then
        return false, msg
    end
    
    -- 更新缓存
    tsdb.set_cached_block(row_key, block)
    
    -- 如果块满了，写入存储
    if block.point_count >= config.max_points_per_block then
        -- 这里应该调用C接口写入RocksDB
        -- tsdb.flush_block_to_storage(row_key, block)
    end
    
    return true
end

function tsdb.write_points(symbol, points, data_type)
    -- 批量写入数据点
    local success_count = 0
    local error_count = 0
    local errors = {}
    
    for i, point in ipairs(points) do
        local success, error_msg = tsdb.write_point(
            symbol, 
            point.timestamp, 
            point.value, 
            data_type,
            point.quality
        )
        
        if success then
            success_count = success_count + 1
        else
            error_count = error_count + 1
            table.insert(errors, string.format("点%d: %s", i, error_msg))
        end
    end
    
    return {
        success = success_count,
        errors = error_count,
        error_messages = errors
    }
end

-- 数据读取操作
function tsdb.read_point(symbol, timestamp, data_type)
    -- 读取单个数据点
    local block_start = get_block_start_time(timestamp)
    local row_key = create_row_key(symbol, block_start, data_type)
    
    -- 检查缓存
    local block = tsdb.get_cached_block(row_key)
    
    if not block then
        -- 从存储中读取
        -- 这里应该调用C接口从RocksDB读取
        return nil, "数据块不存在"
    end
    
    -- 在块中查找数据点
    for _, point in ipairs(block.points) do
        if point.timestamp == timestamp then
            return point
        end
    end
    
    return nil, "数据点不存在"
end

function tsdb.read_range(symbol, start_time, end_time, data_type)
    -- 读取时间范围数据
    local result = {}
    
    -- 计算需要读取的数据块
    local block_start = get_block_start_time(start_time)
    local block_end = get_block_start_time(end_time)
    
    for block_time = block_start, block_end, config.block_size * 1000000 do
        local row_key = create_row_key(symbol, block_time, data_type)
        local block = tsdb.get_cached_block(row_key)
        
        if not block then
            -- 从存储中读取
            -- 这里应该调用C接口从RocksDB读取
            -- block = tsdb.read_block_from_storage(row_key)
        end
        
        if block then
            -- 添加在指定时间范围内的数据点
            for _, point in ipairs(block.points) do
                if point.timestamp >= start_time and point.timestamp <= end_time then
                    table.insert(result, point)
                end
            end
        end
    end
    
    -- 按时间戳排序
    table.sort(result, function(a, b)
        return a.timestamp < b.timestamp
    end)
    
    return result
end

-- 配置管理
function tsdb.get_config()
    return config
end

function tsdb.set_config(key, value)
    -- 设置配置项
    local keys = {}
    for k in string.gmatch(key, "[^.]+") do
        table.insert(keys, k)
    end
    
    local current = config
    for i = 1, #keys - 1 do
        if not current[keys[i]] then
            current[keys[i]] = {}
        end
        current = current[keys[i]]
    end
    
    current[keys[#keys]] = value
end

-- 统计信息
function tsdb.get_stats()
    return {
        cache = cache_stats,
        config = config
    }
end

-- 数据类型操作
function tsdb.get_data_types()
    return DATA_TYPES
end

function tsdb.get_data_type_name(data_type)
    for name, value in pairs(DATA_TYPES) do
        if value == data_type then
            return name
        end
    end
    return nil
end

-- 导出函数
return tsdb