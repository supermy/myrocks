-- 每日自动新建CF的存储引擎实现
-- 支持冷热数据分离、ZSTD压缩、关闭自动Compaction、秒级删除旧数据

local ffi = require "ffi"

local DailyCFStorageEngine = {}
DailyCFStorageEngine.__index = DailyCFStorageEngine

function DailyCFStorageEngine:new(config)
    local obj = setmetatable({}, DailyCFStorageEngine)
    obj.config = config or {}
    obj.data = {}  -- 内存存储，模拟RocksDB
    obj.initialized = false
    
    -- 冷热数据分离配置
    obj.enable_cold_data_separation = config.enable_cold_data_separation or false
    obj.cold_data_threshold_days = config.cold_data_threshold_days or 30
    
    -- CF管理配置
    obj.daily_cf_enabled = config.daily_cf_enabled or true
    obj.cold_cf_compression = config.cold_cf_compression or "zstd"  -- 冷数据CF压缩
    obj.cold_cf_disable_compaction = config.cold_cf_disable_compaction or true  -- 冷数据CF关闭自动Compaction
    obj.retention_days = config.retention_days or 30  -- 数据保留天数
    
    -- CF状态管理
    obj.column_families = {}  -- 存储所有CF的状态
    obj.current_cf = nil      -- 当前活跃CF
    obj.last_cf_check = 0     -- 上次CF检查时间
    
    return obj
end

function DailyCFStorageEngine:initialize()
    print("[信息] 每日CF存储引擎初始化成功")
    print("[配置] 冷热数据分离: " .. tostring(self.enable_cold_data_separation))
    print("[配置] 冷数据阈值: " .. self.cold_data_threshold_days .. "天")
    print("[配置] 每日CF: " .. tostring(self.daily_cf_enabled))
    print("[配置] 冷数据CF压缩: " .. self.cold_cf_compression)
    print("[配置] 冷数据CF关闭Compaction: " .. tostring(self.cold_cf_disable_compaction))
    print("[配置] 数据保留天数: " .. self.retention_days .. "天")
    
    -- 初始化当前CF
    self:ensure_current_cf()
    
    self.initialized = true
    return true
end

-- 确保当前CF存在并正确配置
function DailyCFStorageEngine:ensure_current_cf()
    local current_date = os.date("%Y%m%d")
    local cf_name = "cf_" .. current_date
    
    if not self.column_families[cf_name] then
        -- 创建新的CF
        self.column_families[cf_name] = {
            name = cf_name,
            created_date = current_date,
            is_hot = true,  -- 新创建的CF都是热数据
            compression = "lz4",  -- 热数据使用LZ4快速压缩
            disable_compaction = false,  -- 热数据启用Compaction
            data_points = 0
        }
        print("[CF管理] 创建新CF: " .. cf_name)
    end
    
    self.current_cf = cf_name
    self.last_cf_check = os.time()
    
    return cf_name
end

-- 获取指定时间戳对应的CF名称
function DailyCFStorageEngine:get_cf_name_for_timestamp(timestamp)
    if not self.daily_cf_enabled then
        return "default"  -- 未启用每日CF功能
    end
    
    -- 确保当前CF存在
    self:ensure_current_cf()
    
    local date = os.date("*t", timestamp)
    local date_str = string.format("%04d%02d%02d", date.year, date.month, date.day)
    local cf_name = "cf_" .. date_str
    
    -- 冷热数据分离逻辑
    if self.enable_cold_data_separation then
        local current_time = os.time()
        local days_diff = os.difftime(current_time, timestamp) / (24 * 60 * 60)
        
        if days_diff > self.cold_data_threshold_days then
            -- 冷数据：超过阈值天数的数据
            cf_name = "cold_" .. date_str
            
            -- 确保冷数据CF存在并正确配置
            if not self.column_families[cf_name] then
                self.column_families[cf_name] = {
                    name = cf_name,
                    created_date = date_str,
                    is_hot = false,  -- 冷数据
                    compression = self.cold_cf_compression,  -- 使用配置的压缩算法
                    disable_compaction = self.cold_cf_disable_compaction,  -- 关闭自动Compaction
                    data_points = 0
                }
                print("[CF管理] 创建冷数据CF: " .. cf_name .. " (压缩: " .. self.cold_cf_compression .. ", Compaction: " .. (self.cold_cf_disable_compaction and "关闭" or "开启") .. ")")
            end
        end
    end
    
    -- 确保CF存在
    if not self.column_families[cf_name] then
        self.column_families[cf_name] = {
            name = cf_name,
            created_date = date_str,
            is_hot = true,
            compression = "lz4",
            disable_compaction = false,
            data_points = 0
        }
    end
    
    return cf_name
end

function DailyCFStorageEngine:write_point(metric, timestamp, value, tags)
    if not self.initialized then
        print("[错误] 存储引擎未初始化")
        return false
    end
    
    -- 获取对应的CF
    local cf_name = self:get_cf_name_for_timestamp(timestamp)
    
    -- 存储数据
    local key = string.format("%s_%d", metric, timestamp)
    self.data[key] = {
        metric = metric,
        timestamp = timestamp,
        value = value,
        tags = tags or {},
        cf = cf_name
    }
    
    -- 更新CF统计
    if self.column_families[cf_name] then
        self.column_families[cf_name].data_points = self.column_families[cf_name].data_points + 1
    end
    
    print(string.format("[写入] CF=%s, 数据点: %s @ %d = %s", cf_name, metric, timestamp, tostring(value)))
    return true
end

function DailyCFStorageEngine:read_point(metric, start_time, end_time, tags)
    if not self.initialized then
        print("[错误] 存储引擎未初始化")
        return false, {}
    end
    
    local results = {}
    for key, data in pairs(self.data) do
        if data.metric == metric and 
           data.timestamp >= start_time and 
           data.timestamp <= end_time then
            table.insert(results, data)
        end
    end
    
    print(string.format("[查询] 在时间范围[%d-%d]内查询到 %d 条数据点", start_time, end_time, #results))
    return true, results
end

function DailyCFStorageEngine:close()
    print("[信息] 每日CF存储引擎关闭")
    self.initialized = false
    return true
end

-- 获取统计信息
function DailyCFStorageEngine:get_stats()
    local stats = {
        total_points = 0,
        memory_usage = 0,
        cf_count = 0,
        cf_details = {},
        cold_hot_separation_enabled = self.enable_cold_data_separation,
        cold_data_threshold_days = self.cold_data_threshold_days,
        daily_cf_enabled = self.daily_cf_enabled,
        cold_cf_compression = self.cold_cf_compression,
        cold_cf_disable_compaction = self.cold_cf_disable_compaction,
        retention_days = self.retention_days
    }
    
    for _ in pairs(self.data) do
        stats.total_points = stats.total_points + 1
    end
    
    stats.cf_count = 0
    for cf_name, cf_info in pairs(self.column_families) do
        stats.cf_count = stats.cf_count + 1
        stats.cf_details[cf_name] = {
            data_points = cf_info.data_points,
            is_hot = cf_info.is_hot,
            compression = cf_info.compression,
            disable_compaction = cf_info.disable_compaction,
            created_date = cf_info.created_date
        }
    end
    
    -- 估算内存使用
    stats.memory_usage = stats.total_points * 100  -- 粗略估算
    
    return stats
end

-- 冷热数据管理方法
function DailyCFStorageEngine:migrate_to_cold_data(timestamp)
    if not self.initialized then return false end
    
    local cf_name = self:get_cf_name_for_timestamp(timestamp)
    if string.find(cf_name, "^cf_") then
        -- 如果是热数据CF，迁移到冷数据CF
        local date_str = string.sub(cf_name, 4)  -- 去掉"cf_"前缀
        local cold_cf_name = "cold_" .. date_str
        
        -- 创建冷数据CF（如果不存在）
        if not self.column_families[cold_cf_name] then
            self.column_families[cold_cf_name] = {
                name = cold_cf_name,
                created_date = date_str,
                is_hot = false,
                compression = self.cold_cf_compression,
                disable_compaction = self.cold_cf_disable_compaction,
                data_points = 0
            }
        end
        
        -- 迁移数据（模拟）
        local migrated_count = 0
        for key, data in pairs(self.data) do
            if data.cf == cf_name and data.timestamp == timestamp then
                data.cf = cold_cf_name
                migrated_count = migrated_count + 1
                
                -- 更新CF统计
                if self.column_families[cf_name] then
                    self.column_families[cf_name].data_points = math.max(0, self.column_families[cf_name].data_points - 1)
                end
                if self.column_families[cold_cf_name] then
                    self.column_families[cold_cf_name].data_points = self.column_families[cold_cf_name].data_points + 1
                end
            end
        end
        
        print(string.format("[迁移] 将时间戳 %d 的 %d 条数据从 %s 迁移到 %s", timestamp, migrated_count, cf_name, cold_cf_name))
        return true
    end
    
    return false
end

-- 清理过期数据（秒级完成，直接Drop整个CF）
function DailyCFStorageEngine:cleanup_old_data(retention_days)
    if not self.initialized then return false end
    
    local current_time = os.time()
    local cutoff_date = os.date("%Y%m%d", current_time - (retention_days * 24 * 60 * 60))
    local cleaned_cf_count = 0
    local cleaned_data_count = 0
    
    -- 收集需要删除的CF
    local cf_to_delete = {}
    for cf_name, cf_info in pairs(self.column_families) do
        if tonumber(cf_info.created_date) < tonumber(cutoff_date) then
            table.insert(cf_to_delete, cf_name)
        end
    end
    
    -- 秒级删除：直接Drop整个CF
    for _, cf_name in ipairs(cf_to_delete) do
        -- 删除该CF下的所有数据
        local cf_data_count = 0
        local keys_to_remove = {}
        
        for key, data in pairs(self.data) do
            if data.cf == cf_name then
                table.insert(keys_to_remove, key)
                cf_data_count = cf_data_count + 1
            end
        end
        
        -- 批量删除数据
        for _, key in ipairs(keys_to_remove) do
            self.data[key] = nil
        end
        
        -- 删除CF
        local cf_created_date = self.column_families[cf_name].created_date
        self.column_families[cf_name] = nil
        
        cleaned_cf_count = cleaned_cf_count + 1
        cleaned_data_count = cleaned_data_count + cf_data_count
        
        print(string.format("[清理] 删除CF %s (创建日期: %s), 清理数据: %d 条", cf_name, cf_created_date, cf_data_count))
    end
    
    print(string.format("[清理完成] 共删除 %d 个CF, 清理 %d 条数据 (耗时: <1秒)", cleaned_cf_count, cleaned_data_count))
    return true
end

-- 获取冷热数据统计
function DailyCFStorageEngine:get_cold_hot_stats()
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
        hot_percentage = (hot_count / (hot_count + cold_count)) * 100,
        cf_count = self:get_stats().cf_count
    }
end

-- 手动触发CF检查（用于测试）
function DailyCFStorageEngine:check_and_create_cf()
    return self:ensure_current_cf()
end

return DailyCFStorageEngine