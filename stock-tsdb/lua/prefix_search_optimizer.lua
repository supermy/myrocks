--[[
    前缀搜索优化器
    P1优化: 使用RocksDB原生前缀搜索
]]

local PrefixSearchOptimizer = {}
PrefixSearchOptimizer.__index = PrefixSearchOptimizer

function PrefixSearchOptimizer:new(rocksdb_ffi)
    local obj = setmetatable({}, self)
    obj.rocksdb_ffi = rocksdb_ffi
    obj.prefix_extractors = {}  -- 缓存前缀提取器
    return obj
end

-- 创建前缀提取器
function PrefixSearchOptimizer:create_prefix_extractor(prefix_length)
    -- 使用RocksDB的FixedPrefixTransform
    local ffi = require "ffi"
    
    -- 创建前缀提取器配置
    local prefix_config = {
        prefix_length = prefix_length,
        name = "fixed_prefix_" .. prefix_length
    }
    
    return prefix_config
end

-- 优化的前缀搜索
function PrefixSearchOptimizer:prefix_search(db, read_options, prefix, callback)
    if not db or not self.rocksdb_ffi then
        return false, "数据库未初始化"
    end
    
    local iterator = self.rocksdb_ffi.create_iterator(db, read_options)
    if not iterator then
        return false, "无法创建迭代器"
    end
    
    -- P1优化: 使用Seek直接定位到前缀
    self.rocksdb_ffi.iterator_seek(iterator, prefix)
    
    local count = 0
    local max_count = 10000  -- 限制最大处理数量
    
    while self.rocksdb_ffi.iterator_valid(iterator) and count < max_count do
        local key = self.rocksdb_ffi.iterator_key(iterator)
        
        -- 检查是否还在前缀范围内
        if not key or not self:_starts_with(key, prefix) then
            break
        end
        
        local value = self.rocksdb_ffi.iterator_value(iterator)
        
        -- 调用回调函数处理数据
        if callback then
            local should_continue = callback(key, value)
            if should_continue == false then
                break
            end
        end
        
        count = count + 1
        self.rocksdb_ffi.iterator_next(iterator)
    end
    
    self.rocksdb_ffi.destroy_iterator(iterator)
    
    return true, count
end

-- 批量前缀搜索（用于多个前缀）
function PrefixSearchOptimizer:batch_prefix_search(db, read_options, prefixes, callback)
    local results = {}
    
    for _, prefix in ipairs(prefixes) do
        local success, count = self:prefix_search(db, read_options, prefix, function(key, value)
            if callback then
                return callback(prefix, key, value)
            end
            return true
        end)
        
        if success then
            results[prefix] = count
        else
            results[prefix] = 0
        end
    end
    
    return results
end

-- 范围搜索优化
function PrefixSearchOptimizer:range_search(db, read_options, start_key, end_key, callback)
    if not db or not self.rocksdb_ffi then
        return false, "数据库未初始化"
    end
    
    local iterator = self.rocksdb_ffi.create_iterator(db, read_options)
    if not iterator then
        return false, "无法创建迭代器"
    end
    
    -- 定位到起始键
    self.rocksdb_ffi.iterator_seek(iterator, start_key)
    
    local count = 0
    local max_count = 10000
    
    while self.rocksdb_ffi.iterator_valid(iterator) and count < max_count do
        local key = self.rocksdb_ffi.iterator_key(iterator)
        
        -- 检查是否超出范围
        if not key or key > end_key then
            break
        end
        
        local value = self.rocksdb_ffi.iterator_value(iterator)
        
        if callback then
            local should_continue = callback(key, value)
            if should_continue == false then
                break
            end
        end
        
        count = count + 1
        self.rocksdb_ffi.iterator_next(iterator)
    end
    
    self.rocksdb_ffi.destroy_iterator(iterator)
    
    return true, count
end

-- 辅助函数：检查字符串是否以指定前缀开头
function PrefixSearchOptimizer:_starts_with(str, prefix)
    return string.sub(str, 1, #prefix) == prefix
end

-- 生成优化的读取选项
function PrefixSearchOptimizer:create_optimized_read_options(options)
    -- 启用前缀搜索优化
    options = options or {}
    options.prefix_same_as_start = true
    options.total_order_seek = false
    options.auto_prefix_mode = true
    
    return options
end

return PrefixSearchOptimizer
