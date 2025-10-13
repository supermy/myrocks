-- 业务路由管理器
-- 负责将不同的业务请求路由到对应的数据库实例

local ConfigManager = require "lua.config_manager"

local BusinessRouter = {}
BusinessRouter.__index = BusinessRouter

function BusinessRouter:new(config_db_path_or_config_manager)
    local obj = setmetatable({}, BusinessRouter)
    obj.name = "business_router"
    obj.version = "1.0.0"
    obj.description = "业务路由管理器，负责将业务请求路由到对应的数据库实例"
    
    -- 判断参数是配置管理器实例还是数据库路径
    if type(config_db_path_or_config_manager) == "table" and config_db_path_or_config_manager.initialize then
        -- 参数是配置管理器实例
        obj.config_manager = config_db_path_or_config_manager
    else
        -- 参数是数据库路径，创建新的配置管理器
        obj.config_manager = ConfigManager:new(config_db_path_or_config_manager)
        local success, err = obj.config_manager:initialize()
        if not success then
            error("业务路由器初始化失败: " .. tostring(err))
        end
    end
    
    -- 连接池（简化版本）
    obj.connections = {}
    
    -- 路由缓存
    obj.route_cache = {}
    obj.cache_ttl = 300  -- 5分钟
    
    return obj
end

-- 根据业务类型获取目标实例端口
function BusinessRouter:get_target_port(business_type)
    local port_mapping = self.config_manager:get_port_mapping()
    return port_mapping and port_mapping[business_type]
end

-- 根据业务类型获取目标实例ID
function BusinessRouter:get_target_instance_id(business_type)
    return business_type .. "_instance"
end

-- 根据键前缀自动识别业务类型
function BusinessRouter:detect_business_type(key)
    if not key or type(key) ~= "string" then
        return nil
    end
    
    -- 从配置管理器获取路由配置
    local routing_config = self.config_manager:get_routing_config()
    if not routing_config then
        return nil
    end
    
    -- 检查键前缀
    for prefix, business_type in pairs(routing_config) do
        if string.sub(key, 1, #prefix) == prefix then
            return business_type
        end
    end
    
    -- 如果无法通过前缀识别，尝试其他方式
    if string.find(key, "stock") or string.find(key, "quote") then
        return "stock_quotes"
    elseif string.find(key, "iot") or string.find(key, "sensor") then
        return "iot_data"
    elseif string.find(key, "financial") or string.find(key, "forex") then
        return "financial_quotes"
    elseif string.find(key, "order") then
        return "orders"
    elseif string.find(key, "payment") then
        return "payments"
    elseif string.find(key, "inventory") or string.find(key, "sku") then
        return "inventory"
    elseif string.find(key, "sms") or string.find(key, "message") then
        return "sms"
    end
    
    return nil
end

-- 路由请求到对应的业务实例
function BusinessRouter:route_request(business_type, operation, ...)
    if not business_type then
        return nil, "业务类型不能为空"
    end
    
    local target_port = self:get_target_port(business_type)
    if not target_port then
        return nil, "找不到业务类型对应的实例: " .. tostring(business_type)
    end
    
    -- 这里应该实现实际的网络请求路由
    -- 简化版本：返回目标端口信息
    return {
        business_type = business_type,
        target_port = target_port,
        instance_id = self:get_target_instance_id(business_type),
        operation = operation,
        timestamp = os.time()
    }
end

-- 批量路由请求
function BusinessRouter:route_batch_requests(requests)
    local results = {}
    local grouped_requests = {}
    
    -- 按业务类型分组请求
    for i, request in ipairs(requests) do
        local business_type = request.business_type or self:detect_business_type(request.key)
        if business_type then
            if not grouped_requests[business_type] then
                grouped_requests[business_type] = {}
            end
            table.insert(grouped_requests[business_type], request)
        else
            -- 无法识别的业务类型
            table.insert(results, {
                index = i,
                success = false,
                error = "无法识别的业务类型"
            })
        end
    end
    
    -- 按业务类型处理请求
    for business_type, business_requests in pairs(grouped_requests) do
        local target_port = self:get_target_port(business_type)
        if target_port then
            -- 这里应该实现实际的批量路由
            for _, request in ipairs(business_requests) do
                table.insert(results, {
                    business_type = business_type,
                    target_port = target_port,
                    success = true,
                    operation = request.operation
                })
            end
        else
            for _, request in ipairs(business_requests) do
                table.insert(results, {
                    business_type = business_type,
                    success = false,
                    error = "找不到业务类型对应的实例"
                })
            end
        end
    end
    
    return results
end

-- 获取所有业务路由信息
function BusinessRouter:get_all_routes()
    local routes = {}
    
    local port_mapping = self.config_manager:get_port_mapping()
    local business_configs = self.config_manager:get_all_business_configs()
    
    if port_mapping and business_configs then
        for business_type, port in pairs(port_mapping) do
            local business_config = business_configs[business_type]
            table.insert(routes, {
                business_type = business_type,
                target_port = port,
                instance_id = business_type .. "_instance",
                description = business_config and business_config.name or "未知业务类型",
                config = business_config
            })
        end
    end
    
    return routes
end

-- 获取业务描述
function BusinessRouter:get_business_description(business_type)
    local business_configs = self.config_manager:get_all_business_configs()
    if business_configs and business_configs[business_type] then
        return business_configs[business_type].name or "未知业务类型"
    end
    
    return "未知业务类型"
end

-- 获取业务配置
function BusinessRouter:get_business_config(business_type)
    return self.config_manager:get_config("business", business_type)
end

-- 获取实例配置
function BusinessRouter:get_instance_config(business_type)
    return self.config_manager:get_config("instance", business_type)
end

-- 重新加载配置（热更新）
function BusinessRouter:reload_configs()
    return self.config_manager:load_all_configs()
end

-- 关闭路由器
function BusinessRouter:close()
    if self.config_manager then
        self.config_manager:close()
    end
end

-- 健康检查
function BusinessRouter:health_check()
    local health_status = {
        healthy = true,
        details = {},
        timestamp = os.time()
    }
    
    -- 检查每个业务实例的路由配置
    for business_type, port in pairs(BUSINESS_PORT_MAPPING) do
        local status = {
            business_type = business_type,
            port = port,
            instance_id = BUSINESS_INSTANCE_MAPPING[business_type],
            configured = true,
            reachable = self:check_port_reachable(port)
        }
        
        health_status.details[business_type] = status
        
        if not status.reachable then
            health_status.healthy = false
        end
    end
    
    return health_status
end

-- 检查端口是否可达（简化版本）
function BusinessRouter:check_port_reachable(port)
    -- 这里应该实现实际的端口可达性检查
    -- 简化版本：假设端口都可达
    return true
end

-- 重新加载路由配置
function BusinessRouter:reload_config(config_path)
    config_path = config_path or "business_instance_config.json"
    
    local file = io.open(config_path, "r")
    if not file then
        return false, "无法打开配置文件: " .. config_path
    end
    
    local content = file:read("*a")
    file:close()
    
    -- 解析JSON配置
    local json = require "cjson"
    local config_data = json.decode(content)
    
    -- 更新路由映射
    if config_data.business_instances then
        BUSINESS_PORT_MAPPING = {}
        BUSINESS_INSTANCE_MAPPING = {}
        
        for business_type, instance_config in pairs(config_data.business_instances) do
            BUSINESS_PORT_MAPPING[business_type] = instance_config.port
            BUSINESS_INSTANCE_MAPPING[business_type] = instance_config.instance_id
        end
    end
    
    -- 清空缓存
    self.route_cache = {}
    
    return true
end

-- 获取路由统计信息
function BusinessRouter:get_routing_stats()
    local stats = {
        total_business_types = 0,
        configured_ports = 0,
        cache_size = 0,
        last_reload_time = os.time()
    }
    
    for _ in pairs(BUSINESS_PORT_MAPPING) do
        stats.total_business_types = stats.total_business_types + 1
    end
    
    for _ in pairs(BUSINESS_PORT_MAPPING) do
        stats.configured_ports = stats.configured_ports + 1
    end
    
    for _ in pairs(self.route_cache) do
        stats.cache_size = stats.cache_size + 1
    end
    
    return stats
end

return BusinessRouter