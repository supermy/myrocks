local ffi = require "ffi"

-- 简化版存储引擎
local SimpleStorageEngine = {}
SimpleStorageEngine.__index = SimpleStorageEngine

function SimpleStorageEngine:new(config)
    local obj = setmetatable({}, SimpleStorageEngine)
    obj.config = config or {}
    obj.data = {}  -- 文件系统存储模拟器
    obj.initialized = false
    return obj
end

function SimpleStorageEngine:initialize()
    print("[信息] 简化存储引擎初始化成功")
    self.initialized = true
    return true
end

function SimpleStorageEngine:write_point(metric, timestamp, value, tags)
    if not self.initialized then
        print("[错误] 存储引擎未初始化")
        return false
    end
    
    local key = string.format("%s_%d", metric, timestamp)
    self.data[key] = {
        metric = metric,
        timestamp = timestamp,
        value = value,
        tags = tags or {}
    }
    
    print(string.format("[信息] 写入数据点: %s @ %d = %s", metric, timestamp, tostring(value)))
    return true
end

function SimpleStorageEngine:read_point(metric, start_time, end_time, tags)
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
    
    print(string.format("[信息] 查询到 %d 条数据点", #results))
    return true, results
end

function SimpleStorageEngine:close()
    print("[信息] 简化存储引擎关闭")
    self.initialized = false
    return true
end

function SimpleStorageEngine:get_stats()
    local stats = {
        total_points = 0,
        memory_usage = 0
    }
    
    for _ in pairs(self.data) do
        stats.total_points = stats.total_points + 1
    end
    
    -- 估算内存使用
    stats.memory_usage = stats.total_points * 100  -- 粗略估算
    
    return stats
end

return SimpleStorageEngine
