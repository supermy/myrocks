--
-- Storage模块包装器
-- 包装新的纯Lua实现的存储引擎
--

local storage = {}
local StorageEngine = require "tsdb_storage_engine_v3"

-- 验证键的有效性
function storage.validate_key(key)
    if not key or type(key) ~= "string" or #key == 0 then
        return false, "键不能为空"
    end
    if #key > 1024 then
        return false, "键长度不能超过1024字节"
    end
    return true
end

-- 验证值的有效性
function storage.validate_value(value)
    if not value or type(value) ~= "string" then
        return false, "值必须是字符串"
    end
    if #value > 1024 * 1024 then  -- 1MB
        return false, "值长度不能超过1MB"
    end
    return true
end

-- 存储统计信息类
local StorageStats = {}
StorageStats.__index = StorageStats

function StorageStats:new()
    local obj = setmetatable({}, StorageStats)
    obj.put_count = 0
    obj.get_count = 0
    obj.delete_count = 0
    obj.scan_count = 0
    obj.last_error = nil
    obj.error_count = 0
    return obj
end

function StorageStats:increment_put()
    self.put_count = self.put_count + 1
end

function StorageStats:increment_get()
    self.get_count = self.get_count + 1
end

function StorageStats:increment_delete()
    self.delete_count = self.delete_count + 1
end

function StorageStats:increment_scan()
    self.scan_count = self.scan_count + 1
end

function StorageStats:record_error(error_msg)
    self.last_error = error_msg
    self.error_count = self.error_count + 1
end

function StorageStats:get_report()
    return {
        put_count = self.put_count,
        get_count = self.get_count,
        delete_count = self.delete_count,
        scan_count = self.scan_count,
        error_count = self.error_count,
        last_error = self.last_error
    }
end

-- 列族管理器
local ColumnFamilyManager = {}
ColumnFamilyManager.__index = ColumnFamilyManager

function ColumnFamilyManager:new(storage_engine)
    local obj = setmetatable({}, ColumnFamilyManager)
    obj.storage = storage_engine
    obj.column_families = {}
    return obj
end

function ColumnFamilyManager:create_cf(name, options)
    -- 创建列族
    local success, error = self.storage:create_column_family(name)
    if success then
        self.column_families[name] = {
            name = name,
            options = options or {}
        }
        return true
    else
        return false, error
    end
end

function ColumnFamilyManager:drop_cf(name)
    -- 删除列族
    local success, error = self.storage:drop_column_family(name)
    if success then
        self.column_families[name] = nil
        return true
    else
        return false, error
    end
end

function ColumnFamilyManager:list_cfs()
    -- 列出所有列族
    return self.storage:get_column_families()
end

-- 批量写入器
local BatchWriter = {}
BatchWriter.__index = BatchWriter

function BatchWriter:new(storage_engine)
    local obj = setmetatable({}, BatchWriter)
    obj.storage = storage_engine
    obj.batch = {}  -- 简化实现，使用Lua表而不是RocksDB的批处理
    return obj
end

function BatchWriter:put(key, value, cf)
    local valid, error = storage.validate_key(key)
    if not valid then
        return false, error
    end
    
    valid, error = storage.validate_value(value)
    if not valid then
        return false, error
    end
    
    table.insert(self.batch, {
        type = "put",
        key = key,
        value = value,
        cf = cf
    })
    
    return true
end

function BatchWriter:delete(key, cf)
    local valid, error = storage.validate_key(key)
    if not valid then
        return false, error
    end
    
    table.insert(self.batch, {
        type = "delete",
        key = key,
        cf = cf
    })
    
    return true
end

function BatchWriter:write()
    -- 执行批量写入
    -- 这里简化实现，实际应该使用RocksDB的批量写入功能
    for _, operation in ipairs(self.batch) do
        if operation.type == "put" then
            -- 简化实现，实际应该调用storage_engine的put方法
        elseif operation.type == "delete" then
            -- 简化实现，实际应该调用storage_engine的delete方法
        end
    end
    
    -- 清空批次
    self.batch = {}
    
    return true
end

function BatchWriter:clear()
    self.batch = {}
    return true
end

-- 创建存储引擎的工厂函数
function storage.create_engine(config)
    -- 使用新的纯Lua实现
    local engine = StorageEngine:new(config)
    return engine
end

-- 导出类和函数
storage.StorageStats = StorageStats
storage.ColumnFamilyManager = ColumnFamilyManager
storage.BatchWriter = BatchWriter

return storage