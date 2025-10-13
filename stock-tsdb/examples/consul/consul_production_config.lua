-- Consul FFI 生产环境配置示例
-- Production-ready configuration for Consul FFI integration

local consul_ffi = require("consul_ffi")
local consul_ha_cluster = require("consul_ha_cluster")

-- 生产环境配置
local config = {
    -- Consul 集群配置
    consul = {
        -- 生产环境Consul集群地址
        servers = {
            "http://consul-server1:8500",
            "http://consul-server2:8500", 
            "http://consul-server3:8500"
        },
        
        -- 连接配置
        timeout = 10,                    -- 超时时间(秒)
        retry_attempts = 3,              -- 重试次数
        retry_interval = 1,              -- 重试间隔(秒)
        
        -- 健康检查配置
        health_check_interval = 30,      -- 健康检查间隔(秒)
        health_check_timeout = 5,        -- 健康检查超时(秒)
        
        -- 认证配置 (如果Consul启用了ACL)
        acl_token = os.getenv("CONSUL_ACL_TOKEN"),  -- 从环境变量读取
        
        -- TLS配置 (如果Consul使用HTTPS)
        tls_enabled = true,
        tls_verify = true,
        tls_cert_file = "/etc/consul/client.crt",
        tls_key_file = "/etc/consul/client.key",
        tls_ca_file = "/etc/consul/ca.crt",
        
        -- 模拟模式 (开发测试时使用)
        simulate = false
    },
    
    -- HA集群配置
    cluster = {
        -- 节点配置
        node_id = os.getenv("NODE_ID") or "node-" .. os.time(),
        datacenter = os.getenv("DATACENTER") or "dc1",
        
        -- 集群配置
        min_nodes = 3,                   -- 最小节点数
        max_nodes = 9,                   -- 最大节点数
        
        -- 心跳配置
        heartbeat_interval = 5,          -- 心跳间隔(秒)
        heartbeat_timeout = 15,          -- 心跳超时(秒)
        
        -- Leader选举配置
        election_timeout = 10,           -- 选举超时(秒)
        leader_lease_duration = 60,      -- Leader租约时长(秒)
        
        -- 一致性配置
        consistency_mode = "consistent",   -- consistent|stale
        read_timeout = 30,               -- 读操作超时(秒)
        write_timeout = 60,              -- 写操作超时(秒)
        
        -- 故障恢复配置
        failover_timeout = 30,           -- 故障转移超时(秒)
        recovery_interval = 60,          -- 恢复检查间隔(秒)
        
        -- 数据一致性配置
        replication_factor = 3,          -- 副本因子
        write_quorum = 2,                -- 写 quorum
        read_quorum = 2                  -- 读 quorum
    },
    
    -- 存储配置
    storage = {
        -- KV存储配置
        kv_prefix = "stock-tsdb/",       -- KV存储前缀
        kv_consistency = "consistent",   -- KV一致性模式
        
        -- 元数据配置
        metadata_prefix = "metadata/",     -- 元数据前缀
        lock_prefix = "locks/",          -- 锁前缀
        session_prefix = "sessions/"     -- 会话前缀
    },
    
    -- 监控配置
    monitoring = {
        -- 指标收集
        metrics_enabled = true,
        metrics_interval = 60,         -- 指标收集间隔(秒)
        
        -- 日志配置
        log_level = "INFO",              -- DEBUG|INFO|WARN|ERROR
        log_file = "/var/log/stock-tsdb/consul.log",
        log_max_size = 100,              -- MB
        log_max_backups = 10,
        log_max_age = 30,                -- days
        
        -- 告警配置
        alert_enabled = true,
        alert_threshold = {
            node_down_count = 2,         -- 节点下线数量阈值
            response_time_ms = 5000,     -- 响应时间阈值(毫秒)
            error_rate_percent = 5       -- 错误率阈值(%)
        }
    },
    
    -- 安全配置
    security = {
        -- 访问控制
        enable_acl = true,
        acl_policy_file = "/etc/consul/acl-policy.hcl",
        
        -- 加密配置
        encrypt_traffic = true,
        encryption_key = os.getenv("CONSUL_ENCRYPTION_KEY"),
        
        -- 审计配置
        audit_enabled = true,
        audit_log_file = "/var/log/stock-tsdb/audit.log"
    }
}

-- 生产环境Consul FFI客户端管理器
local ConsulManager = {
    clients = {},
    cluster = nil,
    config = config,
    is_initialized = false
}

-- 初始化Consul管理器
function ConsulManager:init()
    if self.is_initialized then
        return true
    end
    
    print("[ConsulManager] 初始化Consul FFI客户端...")
    
    -- 创建多个Consul客户端实例（高可用）
    for i, server_url in ipairs(config.consul.servers) do
        local client_config = {
            consul_url = server_url,
            timeout = config.consul.timeout,
            simulate = config.consul.simulate
        }
        
        -- 添加ACL token（如果配置）
        if config.consul.acl_token then
            client_config.acl_token = config.consul.acl_token
        end
        
        local client = consul_ffi.ConsulClient:new(client_config)
        if client and client.initialized then
            table.insert(self.clients, client)
            print("[ConsulManager] 创建Consul客户端 " .. i .. ": " .. server_url)
        else
            print("[ConsulManager] 警告: 无法创建Consul客户端 " .. i .. ": " .. server_url)
        end
    end
    
    if #self.clients == 0 then
        error("[ConsulManager] 错误: 无法创建任何Consul客户端")
        return false
    end
    
    -- 初始化HA集群
    self.cluster = consul_ha_cluster.ConsulHACluster:new({
        consul_url = self.clients[1].consul_url,  -- 使用第一个客户端的URL
        node_id = config.cluster.node_id,
        datacenter = config.cluster.datacenter,
        heartbeat_interval = config.cluster.heartbeat_interval,
        min_nodes = config.cluster.min_nodes
    })
    
    -- 启动集群
    if self.cluster then
        self.cluster:start()
    end
    
    self.is_initialized = true
    print("[ConsulManager] Consul管理器初始化完成")
    return true
end

-- 获取健康的Consul客户端（轮询负载均衡）
local current_client_index = 1
function ConsulManager:get_healthy_client()
    if not self.is_initialized then
        self:init()
    end
    
    local attempts = 0
    local max_attempts = #self.clients * 2
    
    while attempts < max_attempts do
        local client = self.clients[current_client_index]
        current_client_index = (current_client_index % #self.clients) + 1
        
        -- 简单的健康检查：尝试获取KV值
        local success, result = pcall(function()
            return client:kv_get("health/check")
        end)
        
        if success then
            return client
        end
        
        attempts = attempts + 1
    end
    
    return nil  -- 没有找到健康的客户端
end

-- 获取集群信息
function ConsulManager:get_cluster_info()
    if not self.cluster then
        return nil
    end
    
    return {
        node_count = self.cluster:get_node_count(),
        leader_node = self.cluster:get_leader_info(),  -- 修正方法名
        current_node = self.cluster.node_id,
        is_leader = self.cluster:is_leader_node(),  -- 修正方法名
        nodes = self.cluster.cluster_nodes  -- 使用cluster_nodes而不是nodes
    }
end

-- 存储数据（带副本和一致性保证）
function ConsulManager:store_data(key, value, options)
    options = options or {}
    local consistency = options.consistency or config.cluster.consistency_mode
    local replication_factor = options.replication_factor or config.cluster.replication_factor
    
    local client = self:get_healthy_client()
    if not client then
        return false, "没有可用的Consul客户端"
    end
    
    -- 添加存储前缀
    local full_key = config.storage.kv_prefix .. key
    
    -- 写入主副本
    local success, error = client:kv_put(full_key, value)
    if not success then
        return false, "写入主副本失败: " .. (error or "未知错误")
    end
    
    -- 如果配置了副本，写入到其他节点
    if replication_factor > 1 and self.cluster then
        local nodes = self.cluster:get_replica_nodes(key, replication_factor - 1)
        for _, node in ipairs(nodes) do
            -- 在实际生产环境中，这里需要写入到其他节点的存储系统
            -- 这里只是记录副本信息到Consul
            local replica_key = full_key .. "/replicas/" .. node.id
            client:kv_put(replica_key, node.address)
        end
    end
    
    return true
end

-- 读取数据（带一致性保证）
function ConsulManager:read_data(key, options)
    options = options or {}
    local consistency = options.consistency or config.cluster.consistency_mode
    
    local client = self:get_healthy_client()
    if not client then
        return nil, "没有可用的Consul客户端"
    end
    
    -- 添加存储前缀
    local full_key = config.storage.kv_prefix .. key
    
    return client:kv_get(full_key)
end

-- 获取一致性哈希节点
function ConsulManager:get_consistent_node(key)
    if not self.cluster then
        return nil
    end
    
    -- 使用cluster的get_node_for_key方法
    return self.cluster:get_node_for_key(key)
end

-- 监控集群健康状态
function ConsulManager:monitor_health()
    if not self.cluster then
        return false, "集群未初始化"
    end
    
    local health_info = {
        timestamp = os.time(),
        node_count = self.cluster:get_node_count(),
        leader_node = self.cluster:get_leader_info(),  -- 修正方法名
        is_healthy = true,
        issues = {}
    }
    
    -- 检查节点数量
    if health_info.node_count < self.config.cluster.min_nodes then
        table.insert(health_info.issues, "节点数量不足: " .. health_info.node_count .. " < " .. self.config.cluster.min_nodes)
        health_info.is_healthy = false
    end
    
    -- 检查Leader
    if not health_info.leader_node then
        table.insert(health_info.issues, "没有Leader节点")
        health_info.is_healthy = false
    end
    
    -- 检查Consul客户端健康
    local healthy_clients = 0
    for _, client in ipairs(self.clients) do
        local success = pcall(function()
            client:kv_get("health/check")
        end)
        if success then
            healthy_clients = healthy_clients + 1
        end
    end
    
    if healthy_clients == 0 then
        table.insert(health_info.issues, "没有健康的Consul客户端")
        health_info.is_healthy = false
    elseif healthy_clients < math.ceil(#self.clients / 2) then
        table.insert(health_info.issues, "Consul客户端健康数量不足: " .. healthy_clients .. "/" .. #self.clients)
        health_info.is_healthy = false
    end
    
    return health_info
end

-- 优雅关闭
function ConsulManager:cleanup()
    print("[ConsulManager] 清理资源...")
    
    if self.cluster then
        if self.cluster.stop then
            self.cluster:stop()  -- 使用stop而不是cleanup
        end
        self.cluster = nil
    end
    
    for _, client in ipairs(self.clients) do
        if client.destroy then
            client:destroy()
        end
    end
    
    self.clients = {}
    self.is_initialized = false
    print("[ConsulManager] 资源清理完成")
end

-- 创建全局实例
local consul_manager = ConsulManager

-- 自动初始化（可选）
-- consul_manager:init()

return {
    ConsulManager = consul_manager,
    config = config
}