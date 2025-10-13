--
-- TSDB集群优化模块
-- 提供网络通信、负载均衡、数据同步等优化功能
--

local cluster_optimizer = {}

-- 简单的位操作替代函数（避免依赖bit模块）
local function bit_xor(a, b)
    -- 简单的异或实现
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit ~= b_bit then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

local function bit_and(a, b)
    -- 简单的与操作实现
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        local a_bit = a % 2
        local b_bit = b % 2
        if a_bit == 1 and b_bit == 1 then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

-- 优化配置
local OPTIMIZATION_CONFIG = {
    -- 网络通信优化
    network = {
        connection_pool_size = 10,
        connection_timeout = 5000,  -- 5秒
        heartbeat_interval = 30000, -- 30秒
        max_retry_attempts = 3,
        retry_delay = 1000,         -- 1秒
    },
    
    -- 负载均衡优化
    load_balancing = {
        algorithm = "weighted_round_robin", -- weighted_round_robin, least_connections, hash
        health_check_interval = 10000,       -- 10秒
        max_failures = 3,
        recovery_time = 60000,              -- 60秒
    },
    
    -- 数据同步优化
    data_sync = {
        batch_size = 1000,
        sync_interval = 5000,               -- 5秒
        compression_enabled = true,
        checksum_verification = true,
    },
    
    -- 容错优化
    fault_tolerance = {
        auto_failover = true,
        quorum_size = 2,
        data_consistency_check = true,
        graceful_shutdown = true,
    }
}

-- 连接池管理器
local ConnectionPool = {}
ConnectionPool.__index = ConnectionPool

function ConnectionPool:new(config)
    local obj = setmetatable({}, ConnectionPool)
    obj.config = config or {}
    obj.pool = {}
    obj.connections = {}
    obj.stats = {
        created = 0,
        reused = 0,
        closed = 0,
        errors = 0
    }
    return obj
end

function ConnectionPool:get_connection(node_id, host, port)
    local key = string.format("%s:%d", host, port)
    
    -- 检查连接池中是否有可用连接
    if self.pool[key] and #self.pool[key] > 0 then
        local conn = table.remove(self.pool[key])
        self.stats.reused = self.stats.reused + 1
        return conn
    end
    
    -- 创建新连接
    local conn = self:create_connection(node_id, host, port)
    if conn then
        self.stats.created = self.stats.created + 1
        self.connections[conn.id] = conn
    end
    
    return conn
end

function ConnectionPool:create_connection(node_id, host, port)
    -- 简化版本：实际实现需要根据具体协议创建连接
    return {
        id = string.format("%s_%d_%d", node_id, os.time(), math.random(1000)),
        node_id = node_id,
        host = host,
        port = port,
        created_at = os.time(),
        last_used = os.time(),
        status = "connected"
    }
end

function ConnectionPool:release_connection(conn)
    if not conn then return end
    
    local key = string.format("%s:%d", conn.host, conn.port)
    
    -- 检查连接池是否已满
    if not self.pool[key] then
        self.pool[key] = {}
    end
    
    if #self.pool[key] < self.config.max_pool_size then
        conn.last_used = os.time()
        table.insert(self.pool[key], conn)
    else
        -- 关闭连接
        self:close_connection(conn)
        self.stats.closed = self.stats.closed + 1
    end
end

function ConnectionPool:close_connection(conn)
    -- 实际实现需要根据具体协议关闭连接
    if self.connections[conn.id] then
        self.connections[conn.id] = nil
    end
end

-- 智能负载均衡器
local SmartLoadBalancer = {}
SmartLoadBalancer.__index = SmartLoadBalancer

function SmartLoadBalancer:new(config)
    local obj = setmetatable({}, SmartLoadBalancer)
    obj.config = config or {}
    obj.nodes = {}
    obj.node_stats = {}
    obj.algorithm = config.algorithm or "weighted_round_robin"
    obj.current_index = 1
    return obj
end

function SmartLoadBalancer:add_node(node_id, weight, capacity)
    self.nodes[node_id] = {
        id = node_id,
        weight = weight or 1,
        capacity = capacity or 1000,
        current_load = 0,
        failure_count = 0,
        last_health_check = os.time(),
        status = "healthy"
    }
    
    self.node_stats[node_id] = {
        requests_handled = 0,
        errors = 0,
        response_time_sum = 0,
        response_time_count = 0
    }
end

function SmartLoadBalancer:select_node(key)
    local node_count = 0
    for _ in pairs(self.nodes) do
        node_count = node_count + 1
    end
    
    if node_count == 0 then
        return nil
    end
    
    if self.algorithm == "hash" then
        return self:hash_based_selection(key)
    elseif self.algorithm == "least_connections" then
        return self:least_connections_selection()
    else
        return self:weighted_round_robin_selection()
    end
end

function SmartLoadBalancer:weighted_round_robin_selection()
    local total_weight = 0
    local healthy_nodes = {}
    
    -- 收集健康节点
    for _, node in pairs(self.nodes) do
        if node.status == "healthy" then
            table.insert(healthy_nodes, node)
            total_weight = total_weight + node.weight
        end
    end
    
    if #healthy_nodes == 0 then
        return nil
    end
    
    -- 加权轮询算法
    local current_weight = 0
    local selected_node = nil
    
    for i = 1, #healthy_nodes do
        self.current_index = (self.current_index % #healthy_nodes) + 1
        local node = healthy_nodes[self.current_index]
        
        if node.weight > current_weight then
            current_weight = node.weight
            selected_node = node
        end
    end
    
    return selected_node
end

function SmartLoadBalancer:least_connections_selection()
    local min_load = math.huge
    local selected_node = nil
    
    for _, node in pairs(self.nodes) do
        if node.status == "healthy" and node.current_load < min_load then
            min_load = node.current_load
            selected_node = node
        end
    end
    
    return selected_node
end

function SmartLoadBalancer:hash_based_selection(key)
    local hash = self:fnv1a_hash(key)
    local node_ids = {}
    
    for node_id, _ in pairs(self.nodes) do
        table.insert(node_ids, node_id)
    end
    
    local node_count = #node_ids
    
    if node_count == 0 then
        return nil
    end
    
    local node_index = (hash % node_count) + 1
    table.sort(node_ids)
    local selected_node_id = node_ids[node_index]
    
    return self.nodes[selected_node_id]
end

function SmartLoadBalancer:fnv1a_hash(str)
    local hash = 2166136261
    
    for i = 1, #str do
        hash = bit_xor(hash, string.byte(str, i))
        hash = hash * 16777619
        hash = bit_and(hash, 0xFFFFFFFF)
    end
    
    return hash
end

-- 增量数据同步器
local IncrementalSync = {}
IncrementalSync.__index = IncrementalSync

function IncrementalSync:new(config)
    local obj = setmetatable({}, IncrementalSync)
    obj.config = config or {}
    obj.sync_queue = {}
    obj.last_sync_timestamp = os.time()
    obj.compression_enabled = (config and config.compression_enabled) or true
    return obj
end

function IncrementalSync:queue_data_operation(operation, data)
    local sync_item = {
        timestamp = os.time(),
        operation = operation,  -- insert, update, delete
        data = data,
        checksum = self:calculate_checksum(data)
    }
    
    table.insert(self.sync_queue, sync_item)
    
    -- 检查是否需要立即同步
    if #self.sync_queue >= self.config.batch_size then
        self:sync_batch()
    end
end

function IncrementalSync:sync_batch()
    if #self.sync_queue == 0 then
        return
    end
    
    local batch = {}
    for i = 1, math.min(#self.sync_queue, self.config.batch_size) do
        table.insert(batch, table.remove(self.sync_queue, 1))
    end
    
    -- 压缩数据
    if self.compression_enabled then
        batch = self:compress_batch(batch)
    end
    
    -- 发送同步请求
    self:send_sync_request(batch)
    
    self.last_sync_timestamp = os.time()
end

function IncrementalSync:compress_batch(batch)
    -- 简化版本：实际实现需要使用压缩算法
    return {
        compressed = true,
        original_size = #batch,
        data = batch
    }
end

function IncrementalSync:send_sync_request(batch)
    -- 简化版本：实际实现需要发送到目标节点
    print(string.format("[增量同步] 发送 %d 条数据到副本节点", #batch.data or 0))
end

function IncrementalSync:calculate_checksum(data)
    -- 简化版本：实际实现需要更复杂的校验算法
    local str = tostring(data)
    local checksum = 0
    
    for i = 1, #str do
        checksum = checksum + string.byte(str, i)
    end
    
    return checksum
end

-- 故障检测和恢复管理器
local FaultDetectionManager = {}
FaultDetectionManager.__index = FaultDetectionManager

function FaultDetectionManager:new(config)
    local obj = setmetatable({}, FaultDetectionManager)
    obj.config = config or {}
    obj.node_status = {}
    obj.failure_threshold = (config and config.max_failures) or 3
    obj.recovery_timeout = (config and config.recovery_time) or 60000
    return obj
end

function FaultDetectionManager:register_node(node_id, health_check_func)
    self.node_status[node_id] = {
        status = "healthy",
        failure_count = 0,
        last_health_check = os.time(),
        health_check_func = health_check_func,
        recovery_start_time = nil
    }
end

function FaultDetectionManager:check_node_health(node_id)
    local node = self.node_status[node_id]
    if not node then
        return false
    end
    
    -- 执行健康检查
    local is_healthy = node.health_check_func()
    
    if is_healthy then
        if node.status == "unhealthy" then
            -- 节点恢复
            node.status = "healthy"
            node.failure_count = 0
            node.recovery_start_time = nil
            print(string.format("[故障检测] 节点 %s 已恢复", node_id))
        end
    else
        node.failure_count = node.failure_count + 1
        
        if node.failure_count >= self.failure_threshold then
            node.status = "unhealthy"
            node.recovery_start_time = os.time()
            print(string.format("[故障检测] 节点 %s 标记为不健康", node_id))
        end
    end
    
    node.last_health_check = os.time()
    return is_healthy
end

function FaultDetectionManager:get_node_status(node_id)
    local node = self.node_status[node_id]
    if not node then
        return "unknown"
    end
    
    -- 检查是否需要自动恢复
    if node.status == "unhealthy" and node.recovery_start_time then
        local time_since_failure = (os.time() - node.recovery_start_time) * 1000
        if time_since_failure >= self.recovery_timeout then
            node.status = "recovering"
            print(string.format("[故障检测] 节点 %s 开始自动恢复", node_id))
        end
    end
    
    return node.status
end

-- 导出优化模块
cluster_optimizer.ConnectionPool = ConnectionPool
cluster_optimizer.SmartLoadBalancer = SmartLoadBalancer
cluster_optimizer.IncrementalSync = IncrementalSync
cluster_optimizer.FaultDetectionManager = FaultDetectionManager

return cluster_optimizer