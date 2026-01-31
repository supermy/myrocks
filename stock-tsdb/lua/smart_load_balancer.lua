--[[
    智能负载均衡器
    优化方案3: 实现多种负载均衡算法和实时监控
]]

local SmartLoadBalancer = {}
SmartLoadBalancer.__index = SmartLoadBalancer

-- 负载均衡算法枚举
local LB_ALGORITHMS = {
    ROUND_ROBIN = "round_robin",           -- 轮询
    WEIGHTED_ROUND_ROBIN = "weighted_rr",  -- 加权轮询
    LEAST_CONNECTIONS = "least_conn",      -- 最少连接
    LEAST_RESPONSE_TIME = "least_time",    -- 最少响应时间
    ADAPTIVE = "adaptive"                  -- 自适应算法
}

function SmartLoadBalancer:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.algorithm = obj.config.algorithm or LB_ALGORITHMS.ADAPTIVE
    obj.health_check_interval = obj.config.health_check_interval or 10000  -- 10秒
    obj.metrics_window_size = obj.config.metrics_window_size or 100        -- 指标窗口大小
    
    -- 节点状态
    obj.nodes = {}
    obj.node_list = {}      -- 用于轮询的节点列表
    obj.current_index = 0   -- 轮询索引
    
    -- 性能指标
    obj.metrics = {}
    obj.node_weights = {}
    
    -- 健康检查
    obj.health_checkers = {}
    obj.last_health_check = 0
    
    -- 统计信息
    obj.stats = {
        total_requests = 0,
        successful_requests = 0,
        failed_requests = 0,
        algorithm_switches = 0
    }
    
    return obj
end

-- 添加节点
function SmartLoadBalancer:add_node(node_id, node_config)
    node_config = node_config or {}
    
    self.nodes[node_id] = {
        id = node_id,
        host = node_config.host or "localhost",
        port = node_config.port or 8080,
        weight = node_config.weight or 1,
        max_connections = node_config.max_connections or 100,
        current_connections = 0,
        is_healthy = true,
        last_check_time = 0,
        failure_count = 0,
        success_count = 0,
        response_times = {},
        avg_response_time = 0
    }
    
    table.insert(self.node_list, node_id)
    self.node_weights[node_id] = node_config.weight or 1
    self.metrics[node_id] = {
        requests = 0,
        errors = 0,
        total_response_time = 0
    }
    
    return true
end

-- 移除节点
function SmartLoadBalancer:remove_node(node_id)
    if not self.nodes[node_id] then
        return false, "Node not found"
    end
    
    self.nodes[node_id] = nil
    self.metrics[node_id] = nil
    self.node_weights[node_id] = nil
    
    -- 从节点列表中移除
    for i, id in ipairs(self.node_list) do
        if id == node_id then
            table.remove(self.node_list, i)
            break
        end
    end
    
    return true
end

-- 选择节点
function SmartLoadBalancer:select_node()
    local healthy_nodes = self:get_healthy_nodes()
    
    if #healthy_nodes == 0 then
        return nil, "No healthy nodes available"
    end
    
    self.stats.total_requests = self.stats.total_requests + 1
    
    local selected_node = nil
    
    if self.algorithm == LB_ALGORITHMS.ROUND_ROBIN then
        selected_node = self:_round_robin_select(healthy_nodes)
    elseif self.algorithm == LB_ALGORITHMS.WEIGHTED_ROUND_ROBIN then
        selected_node = self:_weighted_round_robin_select(healthy_nodes)
    elseif self.algorithm == LB_ALGORITHMS.LEAST_CONNECTIONS then
        selected_node = self:_least_connections_select(healthy_nodes)
    elseif self.algorithm == LB_ALGORITHMS.LEAST_RESPONSE_TIME then
        selected_node = self:_least_response_time_select(healthy_nodes)
    else
        selected_node = self:_adaptive_select(healthy_nodes)
    end
    
    if selected_node then
        selected_node.current_connections = selected_node.current_connections + 1
    end
    
    return selected_node
end

-- 轮询选择
function SmartLoadBalancer:_round_robin_select(healthy_nodes)
    self.current_index = (self.current_index % #healthy_nodes) + 1
    return healthy_nodes[self.current_index]
end

-- 加权轮询选择
function SmartLoadBalancer:_weighted_round_robin_select(healthy_nodes)
    local total_weight = 0
    for _, node in ipairs(healthy_nodes) do
        total_weight = total_weight + node.weight
    end
    
    local random_weight = math.random(1, total_weight)
    local current_weight = 0
    
    for _, node in ipairs(healthy_nodes) do
        current_weight = current_weight + node.weight
        if random_weight <= current_weight then
            return node
        end
    end
    
    return healthy_nodes[1]
end

-- 最少连接选择
function SmartLoadBalancer:_least_connections_select(healthy_nodes)
    local selected = healthy_nodes[1]
    
    for i = 2, #healthy_nodes do
        local node = healthy_nodes[i]
        if node.current_connections < selected.current_connections then
            selected = node
        end
    end
    
    return selected
end

-- 最少响应时间选择
function SmartLoadBalancer:_least_response_time_select(healthy_nodes)
    local selected = healthy_nodes[1]
    
    for i = 2, #healthy_nodes do
        local node = healthy_nodes[i]
        if node.avg_response_time < selected.avg_response_time then
            selected = node
        end
    end
    
    return selected
end

-- 自适应选择（综合考虑多个指标）
function SmartLoadBalancer:_adaptive_select(healthy_nodes)
    local best_score = -1
    local selected = nil
    
    for _, node in ipairs(healthy_nodes) do
        -- 计算节点得分（越高越好）
        local score = self:_calculate_node_score(node)
        
        if score > best_score then
            best_score = score
            selected = node
        end
    end
    
    return selected
end

-- 计算节点得分
function SmartLoadBalancer:_calculate_node_score(node)
    -- 连接利用率 (0-1, 越低越好)
    local conn_utilization = node.current_connections / node.max_connections
    
    -- 响应时间得分 (归一化到0-1，越低越好)
    local response_score = math.min(node.avg_response_time / 1000, 1)
    
    -- 成功率得分
    local total_requests = node.success_count + node.failure_count
    local success_rate = total_requests > 0 and (node.success_count / total_requests) or 1
    
    -- 权重因子
    local weight_factor = node.weight / 10  -- 归一化权重
    
    -- 综合得分计算
    local score = (1 - conn_utilization) * 0.3 +      -- 30% 连接利用率
                  (1 - response_score) * 0.3 +         -- 30% 响应时间
                  success_rate * 0.3 +                 -- 30% 成功率
                  weight_factor * 0.1                  -- 10% 权重
    
    return score
end

-- 获取健康节点
function SmartLoadBalancer:get_healthy_nodes()
    local healthy = {}
    
    for _, node_id in ipairs(self.node_list) do
        local node = self.nodes[node_id]
        if node and node.is_healthy then
            table.insert(healthy, node)
        end
    end
    
    return healthy
end

-- 更新节点指标
function SmartLoadBalancer:update_node_metrics(node_id, response_time, success)
    local node = self.nodes[node_id]
    if not node then
        return false
    end
    
    -- 更新响应时间历史
    table.insert(node.response_times, response_time)
    if #node.response_times > self.metrics_window_size then
        table.remove(node.response_times, 1)
    end
    
    -- 计算平均响应时间
    local total_time = 0
    for _, time in ipairs(node.response_times) do
        total_time = total_time + time
    end
    node.avg_response_time = #node.response_times > 0 and (total_time / #node.response_times) or 0
    
    -- 更新成功/失败计数
    if success then
        node.success_count = node.success_count + 1
        self.stats.successful_requests = self.stats.successful_requests + 1
    else
        node.failure_count = node.failure_count + 1
        self.stats.failed_requests = self.stats.failed_requests + 1
    end
    
    -- 更新当前连接数
    node.current_connections = math.max(0, node.current_connections - 1)
    
    return true
end

-- 健康检查
function SmartLoadBalancer:health_check()
    local current_time = os.time() * 1000  -- 毫秒
    
    if current_time - self.last_health_check < self.health_check_interval then
        return  -- 检查间隔未到
    end
    
    self.last_health_check = current_time
    
    for node_id, node in pairs(self.nodes) do
        -- 模拟健康检查
        local is_healthy = self:_perform_health_check(node)
        
        if is_healthy ~= node.is_healthy then
            node.is_healthy = is_healthy
            print(string.format("[负载均衡] 节点 %s 健康状态变更: %s", 
                node_id, is_healthy and "健康" or "不健康"))
        end
        
        node.last_check_time = current_time
    end
end

-- 执行健康检查
function SmartLoadBalancer:_perform_health_check(node)
    -- 简化的健康检查逻辑
    -- 实际实现中应该发送真实的健康检查请求
    
    -- 如果失败次数过多，标记为不健康
    if node.failure_count > 10 and node.success_count == 0 then
        return false
    end
    
    -- 如果平均响应时间过长，标记为不健康
    if node.avg_response_time > 5000 then  -- 5秒
        return false
    end
    
    return true
end

-- 切换负载均衡算法
function SmartLoadBalancer:switch_algorithm(algorithm)
    if LB_ALGORITHMS[algorithm:upper()] then
        self.algorithm = LB_ALGORITHMS[algorithm:upper()]
        self.stats.algorithm_switches = self.stats.algorithm_switches + 1
        print(string.format("[负载均衡] 切换算法为: %s", algorithm))
        return true
    end
    return false
end

-- 获取统计信息
function SmartLoadBalancer:get_stats()
    return {
        algorithm = self.algorithm,
        total_nodes = #self.node_list,
        healthy_nodes = #self:get_healthy_nodes(),
        stats = self.stats,
        node_details = self.nodes
    }
end

-- 获取支持的算法列表
function SmartLoadBalancer.get_supported_algorithms()
    local algorithms = {}
    for name, value in pairs(LB_ALGORITHMS) do
        table.insert(algorithms, value)
    end
    return algorithms
end

return SmartLoadBalancer
