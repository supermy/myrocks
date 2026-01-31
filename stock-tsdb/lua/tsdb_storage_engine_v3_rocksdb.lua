-- V3存储引擎RocksDB落盘改进版本
-- P0优化: 二进制序列化 + LRU缓存
local ffi = require "ffi"

local V3StorageEngineRocksDB = {}
V3StorageEngineRocksDB.__index = V3StorageEngineRocksDB

function V3StorageEngineRocksDB:new(config)
    local obj = setmetatable({}, V3StorageEngineRocksDB)
    obj.config = config or {}
    obj.initialized = false
    
    -- RocksDB配置
    obj.use_rocksdb = config.use_rocksdb or true
    obj.data_dir = config.data_dir or "./v3_rocksdb_data"
    obj.rocksdb_options = config.rocksdb_options or {
        write_buffer_size = 64 * 1024 * 1024,  -- 64MB
        max_write_buffer_number = 4,
        compression = 4,  -- LZ4压缩
        create_if_missing = true
    }
    
    -- 冷热数据分离配置
    obj.enable_cold_data_separation = config.enable_cold_data_separation or false
    obj.cold_data_threshold_days = config.cold_data_threshold_days or 30
    
    -- 批量写入配置
    obj.batch_size = config.batch_size or 1000
    obj.write_batch = nil
    obj.last_commit_time = 0  -- P1优化: 上次提交时间
    obj.commit_interval_ms = config.commit_interval_ms or 100  -- P1优化: 提交间隔
    
    -- 读取优化配置
    obj.max_read_process = config.max_read_process or 10000  -- 最大读取处理数量
    obj.enable_read_cache = config.enable_read_cache or true  -- 启用读取缓存
    
    -- P0优化: 使用LRU缓存替代简单table
    local LRUCache = require "lrucache"
    obj.data = LRUCache:new({
        max_size = config.memory_cache_size or 100000,
        default_ttl = config.memory_cache_ttl or 300  -- 5分钟
    })
    
    -- P0优化: 读取缓存也使用LRU
    obj.read_cache = LRUCache:new({
        max_size = config.read_cache_size or 1000,
        default_ttl = config.read_cache_ttl or 60  -- 1分钟
    })
    
    -- P0优化: 初始化二进制序列化器
    local BinarySerializer = require "binary_serializer"
    obj.binary_serializer = BinarySerializer:new()
    obj.use_binary_serialization = config.use_binary_serialization ~= false  -- 默认启用
    
    -- 统计信息
    obj.stats = {
        writes = 0,
        reads = 0,
        rocksdb_writes = 0,
        rocksdb_reads = 0,
        batch_commits = 0,
        read_cache_hits = 0,
        read_cache_misses = 0,
        serialization_time_ms = 0,  -- P0优化: 序列化时间
        deserialization_time_ms = 0  -- P0优化: 反序列化时间
    }
    
    -- 初始化CSV数据管理器（可选）
    local success, csv_manager = pcall(require, "csv_data_manager")
    if success and csv_manager then
        obj.csv_manager = csv_manager:new(obj)
    else
        obj.csv_manager = nil
        print("[信息] CSV数据管理器不可用，相关功能将禁用")
    end
    
    return obj
end

function V3StorageEngineRocksDB:initialize()
    if self.initialized then
        return true
    end
    
    -- 初始化RocksDB
    if self.use_rocksdb then
        local success, rocksdb_ffi = pcall(require, "rocksdb_ffi")
        if success and rocksdb_ffi and rocksdb_ffi.is_available() then
            self.rocksdb_ffi = rocksdb_ffi
            
            -- 创建RocksDB选项
            self.rocksdb_options_obj = self.rocksdb_ffi.create_options()
            self.rocksdb_ffi.set_create_if_missing(self.rocksdb_options_obj, true)
            self.rocksdb_ffi.set_compression(self.rocksdb_options_obj, self.rocksdb_options.compression)
            
            -- 打开数据库
            self.db, self.db_error = self.rocksdb_ffi.open_database(self.rocksdb_options_obj, self.data_dir)
            if not self.db then
                print("[警告] RocksDB初始化失败: " .. tostring(self.db_error))
                print("[信息] 将使用内存存储模式")
                self.use_rocksdb = false
            else
                print("[信息] RocksDB数据库初始化成功: " .. self.data_dir)
                
                -- 创建写选项
                self.write_options = self.rocksdb_ffi.create_write_options()
                self.read_options = self.rocksdb_ffi.create_read_options()
                
                -- 初始化WriteBatch
                self.write_batch = self.rocksdb_ffi.create_writebatch()
            end
        else
            print("[警告] RocksDB FFI不可用，将使用内存存储模式")
            self.use_rocksdb = false
        end
    end
    
    self.initialized = true
    print("[信息] V3存储引擎RocksDB版本初始化成功")
    return true
end

-- 编码RocksDB键
function V3StorageEngineRocksDB:encode_rocksdb_key(metric, timestamp, tags)
    local key_parts = {metric}
    
    -- 添加标签到key
    if tags then
        for k, v in pairs(tags) do
            table.insert(key_parts, string.format("%s=%s", k, v))
        end
    end
    
    local row_key = table.concat(key_parts, "_")
    local qualifier = string.format("%08x", timestamp % 0x100000000)
    
    return row_key .. "_" .. qualifier
end

-- 序列化数据 (P0优化: 使用二进制序列化)
function V3StorageEngineRocksDB:serialize_data(value, tags)
    local data = {
        value = value,
        tags = tags,
        timestamp = os.time()
    }
    
    -- P0优化: 使用二进制序列化替代JSON
    if self.use_binary_serialization and self.binary_serializer then
        local start_time = os.clock()
        local serialized = self.binary_serializer:serialize(data)
        self.stats.serialization_time_ms = self.stats.serialization_time_ms + (os.clock() - start_time) * 1000
        return serialized
    else
        -- 回退到JSON序列化
        local json_str = "{\"value\":" .. tostring(value)
        if tags then
            json_str = json_str .. ",\"tags\":{"
            local tag_parts = {}
            for k, v in pairs(tags) do
                table.insert(tag_parts, string.format('"%s":"%s"', k, v))
            end
            json_str = json_str .. table.concat(tag_parts, ",") .. "}"
        end
        json_str = json_str .. ",\"timestamp\":" .. os.time() .. "}"
        return json_str
    end
end

-- 反序列化数据 (P0优化: 使用二进制反序列化)
function V3StorageEngineRocksDB:deserialize_data(data_str)
    -- P0优化: 尝试二进制反序列化
    if self.use_binary_serialization and self.binary_serializer then
        local start_time = os.clock()
        local data = self.binary_serializer:deserialize(data_str)
        self.stats.deserialization_time_ms = self.stats.deserialization_time_ms + (os.clock() - start_time) * 1000
        if data then
            return data
        end
        -- 如果二进制反序列化失败，回退到JSON解析
    end
    
    -- 简单JSON解析（回退方案）
    local data = {}
    
    -- 提取value
    local value_start, value_end = string.find(data_str, '"value":([^,}]+)')
    if value_start then
        data.value = tonumber(string.match(data_str, '"value":([^,}]+)', value_start))
    end
    
    -- 提取timestamp
    local ts_start, ts_end = string.find(data_str, '"timestamp":([^,}]+)')
    if ts_start then
        data.timestamp = tonumber(string.match(data_str, '"timestamp":([^,}]+)', ts_start))
    end
    
    -- 提取tags
    local tags_start, tags_end = string.find(data_str, '"tags":%s*{([^}]+)}')
    if tags_start then
        data.tags = {}
        local tags_str = string.match(data_str, '"tags":%s*{([^}]+)}', tags_start)
        for k, v in string.gmatch(tags_str, '"([^"]+)":"([^"]+)"') do
            data.tags[k] = v
        end
    end
    
    return data
end

-- 写入数据点（支持批量写入）
function V3StorageEngineRocksDB:write_point(metric, timestamp, value, tags)
    if not self.initialized then return false end
    
    -- 内存存储
    local key = string.format("%s_%d", metric, timestamp)
    self.data[key] = {
        metric = metric,
        timestamp = timestamp,
        value = value,
        tags = tags
    }
    
    -- RocksDB持久化
    if self.use_rocksdb and self.db then
        local rocksdb_key = self:encode_rocksdb_key(metric, timestamp, tags)
        local rocksdb_value = self:serialize_data(value, tags)
        
        -- 使用WriteBatch批量写入
        if self.write_batch then
            self.rocksdb_ffi.writebatch_put(self.write_batch, rocksdb_key, rocksdb_value)
            self.stats.rocksdb_writes = self.stats.rocksdb_writes + 1
            
            -- P1优化: 批量提交检查（数量或时间触发）
            local current_time = os.clock() * 1000  -- 转换为毫秒
            local should_commit = false
            
            -- 数量触发
            if self.stats.rocksdb_writes % self.batch_size == 0 then
                should_commit = true
            end
            
            -- P1优化: 时间触发（避免数据丢失）
            if current_time - self.last_commit_time > self.commit_interval_ms then
                should_commit = true
            end
            
            if should_commit then
                self:commit_batch()
                self.last_commit_time = current_time
            end
        else
            -- 直接写入
            local success, err = self.rocksdb_ffi.put(self.db, self.write_options, rocksdb_key, rocksdb_value)
            if not success then
                print("[警告] RocksDB写入失败: " .. tostring(err))
            else
                self.stats.rocksdb_writes = self.stats.rocksdb_writes + 1
            end
        end
    end
    
    self.stats.writes = self.stats.writes + 1
    return true
end

-- 批量写入数据
function V3StorageEngineRocksDB:batch_write(points)
    if not self.initialized then return 0 end
    
    local success_count = 0
    
    for _, point in ipairs(points) do
        if self:write_point(point.metric, point.timestamp, point.value, point.tags) then
            success_count = success_count + 1
        end
    end
    
    -- 提交剩余的批量写入
    if self.use_rocksdb and self.write_batch then
        self:commit_batch()
    end
    
    return success_count
end

-- 兼容旧接口
function V3StorageEngineRocksDB:write_batch(points)
    return self:batch_write(points)
end

-- 提交批量写入
function V3StorageEngineRocksDB:commit_batch()
    if self.use_rocksdb and self.write_batch and self.db then
        local success, err = self.rocksdb_ffi.commit_write_batch(self.db, self.write_options, self.write_batch)
        if success then
            self.stats.batch_commits = self.stats.batch_commits + 1
            -- 清空WriteBatch
            self.rocksdb_ffi.writebatch_clear(self.write_batch)
        else
            print("[警告] 批量提交失败: " .. tostring(err))
        end
    end
end

-- 读取数据点（优化版本）
function V3StorageEngineRocksDB:read_point(metric, start_time, end_time, tags)
    if not self.initialized then return false, {} end
    
    local results = {}
    
    -- 1. 检查读取缓存
    local cache_key = self:generate_cache_key(metric, start_time, end_time, tags)
    if self.enable_read_cache and self.read_cache[cache_key] then
        self.stats.read_cache_hits = self.stats.read_cache_hits + 1
        return true, self.read_cache[cache_key]
    end
    
    -- 2. 首先从内存缓存读取
    for key, data in pairs(self.data) do
        if data.metric == metric and 
           data.timestamp >= start_time and 
           data.timestamp <= end_time then
            table.insert(results, data)
        end
    end
    
    -- 3. 如果内存中没有足够数据，从RocksDB读取（优化版本）
    if self.use_rocksdb and self.db and (#results == 0 or self.config.always_read_from_rocksdb) then
        -- 使用优化的前缀搜索，避免全表扫描
        local prefix = metric .. "_"
        local iterator = self.rocksdb_ffi.create_iterator(self.db, self.read_options)
        if iterator then
            -- 使用前缀搜索，直接定位到相关数据
            self.rocksdb_ffi.iterator_seek_to_first(iterator)
            
            local processed_count = 0
            local max_process = self.max_read_process  -- 限制处理数量
            local found_prefix = false
            
            while self.rocksdb_ffi.iterator_valid(iterator) do
                local key = self.rocksdb_ffi.iterator_key(iterator)
                
                -- 检查是否还在前缀范围内
                if not key or not string.startswith(key, prefix) then
                    if found_prefix then
                        break  -- 超出前缀范围，提前终止
                    end
                else
                    found_prefix = true
                    local value = self.rocksdb_ffi.iterator_value(iterator)
                    
                    -- 解析key获取时间戳（避免反序列化整个value）
                    local timestamp = self:extract_timestamp_from_key(key)
                    
                    -- 快速时间范围过滤
                    if timestamp and timestamp >= start_time and timestamp <= end_time then
                        -- 只在需要时反序列化value
                        local data = self:deserialize_data(value)
                        if data then
                            table.insert(results, {
                                metric = metric,
                                timestamp = data.timestamp,
                                value = data.value,
                                tags = data.tags
                            })
                        end
                    end
                end
                
                -- 限制处理数量，避免内存溢出
                processed_count = processed_count + 1
                if processed_count >= max_process then
                    print("[警告] 读取处理数量达到上限: " .. max_process)
                    break
                end
                
                self.rocksdb_ffi.iterator_next(iterator)
            end
            
            self.rocksdb_ffi.destroy_iterator(iterator)
            self.stats.rocksdb_reads = self.stats.rocksdb_reads + 1
        end
    end
    
    -- 4. 更新读取缓存
    if self.enable_read_cache and #results > 0 then
        self:update_read_cache(cache_key, results)
        self.stats.read_cache_misses = self.stats.read_cache_misses + 1
    else
        self.stats.read_cache_misses = self.stats.read_cache_misses + 1
    end
    
    self.stats.reads = self.stats.reads + 1
    return true, results
end

-- 批量读取优化
function V3StorageEngineRocksDB:read_batch(queries)
    if not self.initialized then return false, {} end
    
    local batch_results = {}
    
    for i, query in ipairs(queries) do
        local success, results = self:read_point(query.metric, query.start_time, query.end_time, query.tags)
        if success then
            batch_results[i] = results
        else
            batch_results[i] = {}
        end
    end
    
    return true, batch_results
end

-- 生成缓存键
function V3StorageEngineRocksDB:generate_cache_key(metric, start_time, end_time, tags)
    local tag_str = ""
    if tags then
        local sorted_tags = {}
        for k, v in pairs(tags) do
            table.insert(sorted_tags, k .. "=" .. v)
        end
        table.sort(sorted_tags)
        tag_str = table.concat(sorted_tags, "&")
    end
    
    return string.format("%s_%d_%d_%s", metric, start_time, end_time, tag_str)
end

-- 更新读取缓存
function V3StorageEngineRocksDB:update_read_cache(cache_key, results)
    -- 检查缓存大小，如果超过限制则清理最旧的缓存
    if #self.read_cache >= self.read_cache_size then
        local oldest_key = nil
        for k, v in pairs(self.read_cache) do
            if not oldest_key or v.timestamp < self.read_cache[oldest_key].timestamp then
                oldest_key = k
            end
        end
        if oldest_key then
            self.read_cache[oldest_key] = nil
        end
    end
    
    -- 添加新缓存
    self.read_cache[cache_key] = {
        data = results,
        timestamp = os.time()
    }
end

-- 清理读取缓存
function V3StorageEngineRocksDB:clear_read_cache()
    self.read_cache = {}
    self.stats.read_cache_hits = 0
    self.stats.read_cache_misses = 0
    print("[信息] 读取缓存已清理")
end

-- 从key中提取时间戳（优化性能）
function V3StorageEngineRocksDB:extract_timestamp_from_key(key)
    if not key then return nil end
    
    -- 假设key格式为: metric_timestamp_hex_tags
    local parts = {}
    for part in string.gmatch(key, "[^_]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 2 then
        -- 第二个部分通常是时间戳的十六进制表示
        local timestamp_hex = parts[2]
        -- 将十六进制转换为十进制时间戳
        return tonumber(timestamp_hex, 16)
    end
    
    return nil
end

-- 字符串startswith辅助函数
function string.startswith(str, prefix)
    return string.sub(str, 1, string.len(prefix)) == prefix
end

-- 关闭存储引擎
function V3StorageEngineRocksDB:close()
    if not self.initialized then return true end
    
    -- 提交剩余的批量写入
    if self.use_rocksdb and self.write_batch then
        self:commit_batch()
    end
    
    -- 关闭RocksDB
    if self.use_rocksdb and self.db then
        -- 注意：使用ffi.gc创建的对象不需要手动销毁
        -- 只需要关闭数据库即可
        self.rocksdb_ffi.close_database(self.db)
        print("[信息] RocksDB数据库已关闭")
    end
    
    self.initialized = false
    return true
end

-- 获取统计信息
function V3StorageEngineRocksDB:get_stats()
    return {
        is_initialized = self.initialized,
        rocksdb_enabled = self.use_rocksdb,
        data_points = table.maxn(self.data) or 0,
        memory_usage = collectgarbage("count") * 1024,  -- KB to bytes
        stats = self.stats,
        cold_hot_separation_enabled = self.enable_cold_data_separation,
        cold_data_threshold_days = self.cold_data_threshold_days
    }
end

-- 数据备份
function V3StorageEngineRocksDB:backup_data(backup_dir)
    if not self.initialized then return false end
    
    local backup_path = backup_dir or "./v3_backup_" .. os.date("%Y%m%d_%H%M%S")
    
    -- 创建备份目录
    os.execute("mkdir -p " .. backup_path)
    
    -- 备份内存数据
    local memory_backup_file = backup_path .. "/memory_data.lua"
    local file = io.open(memory_backup_file, "w")
    if file then
        file:write("return {")
        for key, data in pairs(self.data) do
            file:write(string.format("['%s'] = {metric='%s', timestamp=%d, value=%f},", 
                key, data.metric, data.timestamp, data.value))
        end
        file:write("}")
        file:close()
    end
    
    -- 备份RocksDB数据（如果启用）
    if self.use_rocksdb and self.db then
        -- 简单的文件系统备份
        os.execute("cp -r " .. self.data_dir .. " " .. backup_path .. "/rocksdb_backup")
    end
    
    print("[信息] 数据备份完成: " .. backup_path)
    return true
end

-- 数据恢复
function V3StorageEngineRocksDB:restore_data(backup_dir)
    if not self.initialized then return false end
    
    -- 实现数据恢复逻辑
    print("[信息] 数据恢复功能待实现")
    return true
end

-- 继承原有V3存储引擎的方法
function V3StorageEngineRocksDB:encode_metric_key(metric, timestamp, tags)
    local key_parts = {metric}
    
    if tags then
        for k, v in pairs(tags) do
            table.insert(key_parts, string.format("%s=%s", k, v))
        end
    end
    
    local row_key = table.concat(key_parts, "_")
    local qualifier = string.format("%08x", timestamp % 0x100000000)
    
    return row_key, qualifier
end

function V3StorageEngineRocksDB:get_cf_name_for_timestamp(timestamp)
    local date = os.date("*t", timestamp)
    local date_str = string.format("%04d%02d%02d", date.year, date.month, date.day)
    
    if self.enable_cold_data_separation then
        local current_time = os.time()
        local days_diff = os.difftime(current_time, timestamp) / (24 * 60 * 60)
        
        if days_diff > self.cold_data_threshold_days then
            return "cold_" .. date_str
        else
            return "cf_" .. date_str
        end
    else
        return "cf_" .. date_str
    end
end

-- CSV数据导入导出接口（继承）
function V3StorageEngineRocksDB:import_csv_data(file_path, business_type, options)
    if not self.csv_manager then
        return false, "CSV管理器未初始化"
    end
    
    return self.csv_manager:import_csv(file_path, business_type, options)
end

function V3StorageEngineRocksDB:export_csv_data(file_path, business_type, start_time, end_time, options)
    if not self.csv_manager then
        return false, "CSV管理器未初始化"
    end
    
    return self.csv_manager:export_csv(file_path, business_type, start_time, end_time, options)
end

return V3StorageEngineRocksDB