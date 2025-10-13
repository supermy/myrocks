-- 统一数据访问层
-- 为上层应用提供透明的多实例访问接口

local UnifiedDataAccess = {}
UnifiedDataAccess.__index = UnifiedDataAccess

-- 导入业务路由管理器
local BusinessRouter = require "business_router"

function UnifiedDataAccess:new()
    local obj = setmetatable({}, UnifiedDataAccess)
    obj.name = "unified_data_access"
    obj.version = "1.0.0"
    obj.description = "统一数据访问层，透明处理多实例数据访问"
    
    -- 初始化业务路由管理器
    obj.router = BusinessRouter:new()
    
    -- 连接池管理
    obj.connection_pools = {}
    obj.max_connections_per_instance = 10
    obj.connection_timeout = 5000  -- 5秒
    
    -- 统计信息
    obj.stats = {
        total_requests = 0,
        successful_requests = 0,
        failed_requests = 0,
        cache_hits = 0,
        cache_misses = 0,
        last_reset_time = os.time()
    }
    
    -- 缓存配置
    obj.enable_cache = true
    obj.cache_ttl = 300  -- 5分钟
    obj.data_cache = {}
    
    return obj
end

-- 设置数据（自动路由到对应的业务实例）
function UnifiedDataAccess:set(key, value, options)
    options = options or {}
    
    -- 更新统计
    self.stats.total_requests = self.stats.total_requests + 1
    
    -- 检测业务类型
    local business_type = self.router:detect_business_type(key)
    if not business_type then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "无法识别的业务类型，键: " .. tostring(key)
    end
    
    -- 路由到对应的业务实例
    local route_result, err = self.router:route_request(business_type, "SET", key, value)
    if not route_result then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "路由失败: " .. tostring(err)
    end
    
    -- 这里应该实现实际的数据库操作
    -- 简化版本：模拟操作成功
    local success = self:execute_on_instance(route_result.target_port, "SET", key, value)
    
    if success then
        self.stats.successful_requests = self.stats.successful_requests + 1
        
        -- 更新缓存
        if self.enable_cache then
            self.data_cache[key] = {
                value = value,
                timestamp = os.time(),
                business_type = business_type
            }
        end
        
        return true
    else
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "数据库操作失败"
    end
end

-- 获取数据（自动路由到对应的业务实例）
function UnifiedDataAccess:get(key, options)
    options = options or {}
    
    -- 更新统计
    self.stats.total_requests = self.stats.total_requests + 1
    
    -- 检查缓存
    if self.enable_cache and not options.force_refresh then
        local cached_data = self.data_cache[key]
        if cached_data and os.time() - cached_data.timestamp < self.cache_ttl then
            self.stats.cache_hits = self.stats.cache_hits + 1
            return cached_data.value
        else
            self.stats.cache_misses = self.stats.cache_misses + 1
        end
    end
    
    -- 检测业务类型
    local business_type = self.router:detect_business_type(key)
    if not business_type then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "无法识别的业务类型，键: " .. tostring(key)
    end
    
    -- 路由到对应的业务实例
    local route_result, err = self.router:route_request(business_type, "GET", key)
    if not route_result then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "路由失败: " .. tostring(err)
    end
    
    -- 这里应该实现实际的数据库操作
    -- 简化版本：模拟操作成功
    local value = self:execute_on_instance(route_result.target_port, "GET", key)
    
    if value ~= nil then
        self.stats.successful_requests = self.stats.successful_requests + 1
        
        -- 更新缓存
        if self.enable_cache then
            self.data_cache[key] = {
                value = value,
                timestamp = os.time(),
                business_type = business_type
            }
        end
        
        return value
    else
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "数据不存在"
    end
end

-- 删除数据
function UnifiedDataAccess:delete(key, options)
    options = options or {}
    
    -- 更新统计
    self.stats.total_requests = self.stats.total_requests + 1
    
    -- 检测业务类型
    local business_type = self.router:detect_business_type(key)
    if not business_type then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "无法识别的业务类型，键: " .. tostring(key)
    end
    
    -- 路由到对应的业务实例
    local route_result, err = self.router:route_request(business_type, "DELETE", key)
    if not route_result then
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "路由失败: " .. tostring(err)
    end
    
    -- 这里应该实现实际的数据库操作
    -- 简化版本：模拟操作成功
    local success = self:execute_on_instance(route_result.target_port, "DELETE", key)
    
    if success then
        self.stats.successful_requests = self.stats.successful_requests + 1
        
        -- 清除缓存
        if self.enable_cache then
            self.data_cache[key] = nil
        end
        
        return true
    else
        self.stats.failed_requests = self.stats.failed_requests + 1
        return nil, "删除操作失败"
    end
end

-- 批量设置数据
function UnifiedDataAccess:mset(key_value_pairs, options)
    options = options or {}
    
    if not key_value_pairs or type(key_value_pairs) ~= "table" then
        return nil, "参数必须是键值对表格"
    end
    
    local results = {}
    local grouped_operations = {}
    
    -- 按业务类型分组操作
    for key, value in pairs(key_value_pairs) do
        local business_type = self.router:detect_business_type(key)
        if business_type then
            if not grouped_operations[business_type] then
                grouped_operations[business_type] = {}
            end
            grouped_operations[business_type][key] = value
        else
            results[key] = {success = false, error = "无法识别的业务类型"}
        end
    end
    
    -- 按业务类型执行批量操作
    for business_type, operations in pairs(grouped_operations) do
        local route_result, err = self.router:route_request(business_type, "MSET", operations)
        if route_result then
            -- 这里应该实现实际的批量数据库操作
            local success = self:execute_batch_on_instance(route_result.target_port, "MSET", operations)
            
            if success then
                for key, value in pairs(operations) do
                    results[key] = {success = true}
                    
                    -- 更新缓存
                    if self.enable_cache then
                        self.data_cache[key] = {
                            value = value,
                            timestamp = os.time(),
                            business_type = business_type
                        }
                    end
                end
            else
                for key, value in pairs(operations) do
                    results[key] = {success = false, error = "批量操作失败"}
                end
            end
        else
            for key, value in pairs(operations) do
                results[key] = {success = false, error = "路由失败: " .. tostring(err)}
            end
        end
    end
    
    return results
end

-- 批量获取数据
function UnifiedDataAccess:mget(keys, options)
    options = options or {}
    
    if not keys or type(keys) ~= "table" then
        return nil, "参数必须是键列表"
    end
    
    local results = {}
    local grouped_operations = {}
    local cached_results = {}
    
    -- 检查缓存并分组
    for i, key in ipairs(keys) do
        if self.enable_cache and not options.force_refresh then
            local cached_data = self.data_cache[key]
            if cached_data and os.time() - cached_data.timestamp < self.cache_ttl then
                cached_results[key] = cached_data.value
                self.stats.cache_hits = self.stats.cache_hits + 1
            else
                local business_type = self.router:detect_business_type(key)
                if business_type then
                    if not grouped_operations[business_type] then
                        grouped_operations[business_type] = {}
                    end
                    table.insert(grouped_operations[business_type], key)
                    self.stats.cache_misses = self.stats.cache_misses + 1
                else
                    results[key] = {success = false, error = "无法识别的业务类型"}
                end
            end
        else
            local business_type = self.router:detect_business_type(key)
            if business_type then
                if not grouped_operations[business_type] then
                    grouped_operations[business_type] = {}
                end
                table.insert(grouped_operations[business_type], key)
            else
                results[key] = {success = false, error = "无法识别的业务类型"}
            end
        end
    end
    
    -- 添加缓存结果
    for key, value in pairs(cached_results) do
        results[key] = {success = true, value = value, from_cache = true}
    end
    
    -- 按业务类型执行批量操作
    for business_type, operation_keys in pairs(grouped_operations) do
        local route_result, err = self.router:route_request(business_type, "MGET", operation_keys)
        if route_result then
            -- 这里应该实现实际的批量数据库操作
            local batch_results = self:execute_batch_on_instance(route_result.target_port, "MGET", operation_keys)
            
            if batch_results then
                for i, key in ipairs(operation_keys) do
                    local value = batch_results[key]
                    if value ~= nil then
                        results[key] = {success = true, value = value}
                        
                        -- 更新缓存
                        if self.enable_cache then
                            self.data_cache[key] = {
                                value = value,
                                timestamp = os.time(),
                                business_type = business_type
                            }
                        end
                    else
                        results[key] = {success = false, error = "数据不存在"}
                    end
                end
            else
                for i, key in ipairs(operation_keys) do
                    results[key] = {success = false, error = "批量操作失败"}
                end
            end
        else
            for i, key in ipairs(operation_keys) do
                results[key] = {success = false, error = "路由失败: " .. tostring(err)}
            end
        end
    end
    
    return results
end

-- 在指定实例上执行操作（简化版本）
function UnifiedDataAccess:execute_on_instance(port, operation, ...)
    -- 这里应该实现实际的数据库连接和操作
    -- 简化版本：返回模拟数据
    
    if operation == "GET" then
        local key = select(1, ...)
        -- 模拟返回数据
        return "value_for_" .. key .. "_on_port_" .. port
    elseif operation == "SET" then
        -- 模拟设置成功
        return true
    elseif operation == "DELETE" then
        -- 模拟删除成功
        return true
    end
    
    return nil
end

-- 在指定实例上执行批量操作（简化版本）
function UnifiedDataAccess:execute_batch_on_instance(port, operation, data)
    -- 这里应该实现实际的批量数据库操作
    -- 简化版本：返回模拟数据
    
    if operation == "MGET" then
        local results = {}
        for i, key in ipairs(data) do
            results[key] = "batch_value_for_" .. key .. "_on_port_" .. port
        end
        return results
    elseif operation == "MSET" then
        -- 模拟批量设置成功
        return true
    end
    
    return nil
end

-- 获取统计信息
function UnifiedDataAccess:get_stats()
    local stats_copy = {}
    for k, v in pairs(self.stats) do
        stats_copy[k] = v
    end
    
    -- 计算成功率
    if stats_copy.total_requests > 0 then
        stats_copy.success_rate = (stats_copy.successful_requests / stats_copy.total_requests) * 100
    else
        stats_copy.success_rate = 0
    end
    
    -- 计算缓存命中率
    local total_cache_requests = stats_copy.cache_hits + stats_copy.cache_misses
    if total_cache_requests > 0 then
        stats_copy.cache_hit_rate = (stats_copy.cache_hits / total_cache_requests) * 100
    else
        stats_copy.cache_hit_rate = 0
    end
    
    return stats_copy
end

-- 重置统计信息
function UnifiedDataAccess:reset_stats()
    self.stats = {
        total_requests = 0,
        successful_requests = 0,
        failed_requests = 0,
        cache_hits = 0,
        cache_misses = 0,
        last_reset_time = os.time()
    }
end

-- 清空缓存
function UnifiedDataAccess:clear_cache()
    self.data_cache = {}
end

-- 启用/禁用缓存
function UnifiedDataAccess:set_cache_enabled(enabled)
    self.enable_cache = enabled
end

-- 设置缓存TTL
function UnifiedDataAccess:set_cache_ttl(ttl)
    self.cache_ttl = ttl
end

-- 健康检查
function UnifiedDataAccess:health_check()
    local router_health = self.router:health_check()
    
    local health_status = {
        service = "unified_data_access",
        healthy = router_health.healthy,
        router_health = router_health,
        cache_enabled = self.enable_cache,
        cache_size = 0,
        timestamp = os.time()
    }
    
    -- 计算缓存大小
    for _ in pairs(self.data_cache) do
        health_status.cache_size = health_status.cache_size + 1
    end
    
    return health_status
end

return UnifiedDataAccess