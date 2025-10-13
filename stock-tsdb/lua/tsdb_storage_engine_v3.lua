-- V3存储引擎兼容版本
local ffi = require "ffi"

local V3StorageEngine = {}
V3StorageEngine.__index = V3StorageEngine

function V3StorageEngine:new(config)
    local obj = setmetatable({}, V3StorageEngine)
    obj.config = config or {}
    obj.data = {}
    obj.initialized = false
    
    -- 冷热数据分离配置
    obj.enable_cold_data_separation = config.enable_cold_data_separation or false
    obj.cold_data_threshold_days = config.cold_data_threshold_days or 30  -- 默认30天
    
    return obj
end

function V3StorageEngine:initialize()
    print("[信息] V3存储引擎兼容版本初始化成功")
    self.initialized = true
    return true
end

function V3StorageEngine:write_point(metric, timestamp, value, tags)
    if not self.initialized then return false end
    
    local key = string.format("%s_%d", metric, timestamp)
    self.data[key] = {
        metric = metric,
        timestamp = timestamp,
        value = value,
        tags = tags
    }
    
    return true
end

function V3StorageEngine:read_point(metric, start_time, end_time, tags)
    if not self.initialized then return false, {} end
    
    local results = {}
    for key, data in pairs(self.data) do
        if data.metric == metric and 
           data.timestamp >= start_time and 
           data.timestamp <= end_time then
            table.insert(results, data)
        end
    end
    
    return true, results
end

function V3StorageEngine:close()
    self.initialized = false
    return true
end

-- 添加RowKey编码方法（兼容测试）
function V3StorageEngine:encode_metric_key(metric, timestamp, tags)
    local key_parts = {metric}
    
    -- 添加标签到key
    if tags then
        for k, v in pairs(tags) do
            table.insert(key_parts, string.format("%s=%s", k, v))
        end
    end
    
    local row_key = table.concat(key_parts, "_")
    local qualifier = string.format("%08x", timestamp % 0x100000000)  -- 8位十六进制
    
    return row_key, qualifier
end

-- 添加股票数据编码方法（兼容测试）
function V3StorageEngine:encode_stock_key(stock_code, timestamp, market)
    local row_key = string.format("stock_%s_%s", stock_code, market)
    local qualifier = string.format("%08x", timestamp % 0x100000000)
    
    return row_key, qualifier
end

-- 添加ColumnFamily管理方法（兼容测试）
function V3StorageEngine:get_cf_name_for_timestamp(timestamp)
    local date = os.date("*t", timestamp)
    local date_str = string.format("%04d%02d%02d", date.year, date.month, date.day)
    
    -- 冷热数据分离逻辑
    if self.enable_cold_data_separation then
        local current_time = os.time()
        local days_diff = os.difftime(current_time, timestamp) / (24 * 60 * 60)
        
        if days_diff > self.cold_data_threshold_days then
            -- 冷数据：超过阈值天数的数据
            return "cold_" .. date_str
        else
            -- 热数据：阈值天数内的数据
            return "cf_" .. date_str
        end
    else
        -- 未启用冷热数据分离，统一使用热数据CF
        return "cf_" .. date_str
    end
end

-- 添加统计信息方法（兼容测试）
function V3StorageEngine:get_stats()
    return {
        is_initialized = self.initialized,
        data_points = table.maxn(self.data) or 0,
        memory_usage = collectgarbage("count") * 1024,  -- KB to bytes
        cold_hot_separation_enabled = self.enable_cold_data_separation,
        cold_data_threshold_days = self.cold_data_threshold_days
    }
end

-- 冷热数据管理方法
function V3StorageEngine:migrate_to_cold_data(timestamp)
    if not self.initialized then return false end
    
    -- 模拟数据迁移到冷存储
    print(string.format("[信息] 迁移时间戳 %d 的数据到冷存储", timestamp))
    return true
end

function V3StorageEngine:cleanup_old_data(retention_days)
    if not self.initialized then return false end
    
    local current_time = os.time()
    local cutoff_time = current_time - (retention_days * 24 * 60 * 60)
    local cleaned_count = 0
    
    -- 模拟清理过期数据
    for key, data in pairs(self.data) do
        if data.timestamp < cutoff_time then
            self.data[key] = nil
            cleaned_count = cleaned_count + 1
        end
    end
    
    print(string.format("[信息] 清理了 %d 条超过 %d 天的旧数据", cleaned_count, retention_days))
    return true
end

-- 获取冷热数据统计
function V3StorageEngine:get_cold_hot_stats()
    if not self.initialized then return {} end
    
    local current_time = os.time()
    local hot_count = 0
    local cold_count = 0
    
    for key, data in pairs(self.data) do
        local days_diff = os.difftime(current_time, data.timestamp) / (24 * 60 * 60)
        if days_diff <= self.cold_data_threshold_days then
            hot_count = hot_count + 1
        else
            cold_count = cold_count + 1
        end
    end
    
    return {
        hot_data_points = hot_count,
        cold_data_points = cold_count,
        total_data_points = hot_count + cold_count,
        hot_percentage = (hot_count / (hot_count + cold_count)) * 100
    }
end

return V3StorageEngine
