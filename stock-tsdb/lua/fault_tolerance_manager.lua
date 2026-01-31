--[[
    容错管理器
    优化方案4: 实现故障检测、自动故障转移和数据一致性保证
]]

local FaultToleranceManager = {}
FaultToleranceManager.__index = FaultToleranceManager

-- 节点状态枚举
local NODE_STATUS = {
    HEALTHY = "healthy",
    SUSPECT = "suspect",      -- 可疑
    UNHEALTHY = "unhealthy",
    OFFLINE = "offline"
}

function FaultToleranceManager:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.heartbeat_interval = obj.config.heartbeat_interval or 30000      -- 30秒
    obj.timeout_threshold = obj.config.timeout_threshold or 3             -- 3次超时
    obj.suspect_threshold = obj.config.suspect_threshold or 2             -- 2次超时标记为可疑
    obj.recovery_timeout = obj.config.recovery_timeout or 300000          -- 5分钟
    
    -- 节点管理
    obj.nodes = {}
    obj.node_status = {}
    obj.failure_counts = {}
    
    -- 故障转移
    obj.primary_nodes = {}      -- 主节点
    obj.backup_nodes = {}       -- 备份节点映射
    obj.failover_history = {}   -- 故障转移历史
    
    -- 数据一致性
    obj.pending_syncs = {}      -- 待同步数据
    obj.sync_queue = {}         -- 同步队列
    
    -- 统计信息
    obj.stats = {
        total_failovers = 0,
        total_recoveries = 0,
        total_heartbeats = 0,
        failed_heartbeats = 0
    }
    
    return obj
end

-- 注册节点
function FaultToleranceManager:register_node(node_id, node_config)
    node_config = node_config or {}
    
    self.nodes[node_id] = {
        id = node_id,
        host = node_config.host or "localhost",
        port = node_config.port or 8080,
        role = node_config.role or "primary",  -- primary, backup
        backup_for = node_config.backup_for,     -- 如果是backup，对应的主节点
        is_active = true,
        registered_at = os.time(),
        last_heartbeat = os.time(),
        status = NODE_STATUS.HEALTHY,
        failure_count = 0,
        recovery_count = 0
    }
    
    self.node_status[node_id] = NODE_STATUS.HEALTHY
    self.failure_counts[node_id] = 0
    
    -- 更新主备映射
    if node_config.role == "primary" then
        self.primary_nodes[node_id] = self.nodes[node_id]
    elseif node_config.role == "backup" and node_config.backup_for then
        if not self.backup_nodes[node_config.backup_for] then
            self.backup_nodes[node_config.backup_for] = {}
        end
        table.insert(self.backup_nodes[node_config.backup_for], node_id)
    end
    
    print(string.format("[容错管理] 注册节点: %s (角色: %s)", node_id, node_config.role or "primary"))
    
    return true
end

-- 注销节点
function FaultToleranceManager:unregister_node(node_id)
    local node = self.nodes[node_id]
    if not node then
        return false, "Node not found"
    end
    
    -- 如果是主节点，触发故障转移
    if node.role == "primary" then
        self:trigger_failover(node_id)
    end
    
    -- 从备份映射中移除
    if node.role == "backup" and node.backup_for then
        local backups = self.backup_nodes[node.backup_for]
        if backups then
            for i, id in ipairs(backups) do
                if id == node_id then
                    table.remove(backups, i)
                    break
                end
            end
        end
    end
    
    self.nodes[node_id] = nil
    self.node_status[node_id] = nil
    self.failure_counts[node_id] = nil
    
    print(string.format("[容错管理] 注销节点: %s", node_id))
    
    return true
end

-- 处理心跳
function FaultToleranceManager:handle_heartbeat(node_id)
    local node = self.nodes[node_id]
    if not node then
        return false, "Node not registered"
    end
    
    self.stats.total_heartbeats = self.stats.total_heartbeats + 1
    
    -- 更新心跳时间
    node.last_heartbeat = os.time()
    
    -- 如果节点之前不健康，现在恢复
    if node.status ~= NODE_STATUS.HEALTHY then
        self:_recover_node(node_id)
    end
    
    -- 重置失败计数
    node.failure_count = 0
    self.failure_counts[node_id] = 0
    
    return true
end

-- 检查节点健康状态
function FaultToleranceManager:check_node_health(node_id)
    local node = self.nodes[node_id]
    if not node then
        return false
    end
    
    local current_time = os.time()
    local time_since_last_heartbeat = current_time - node.last_heartbeat
    
    -- 计算超时次数（基于心跳间隔）
    local missed_heartbeats = math.floor(time_since_last_heartbeat / (self.heartbeat_interval / 1000))
    
    -- 更新失败计数
    if missed_heartbeats > self.failure_counts[node_id] then
        self.failure_counts[node_id] = missed_heartbeats
        node.failure_count = missed_heartbeats
        self.stats.failed_heartbeats = self.stats.failed_heartbeats + 1
    end
    
    -- 根据失败次数更新状态
    if missed_heartbeats >= self.timeout_threshold then
        -- 标记为不健康
        if node.status ~= NODE_STATUS.UNHEALTHY then
            self:_mark_node_unhealthy(node_id)
        end
        return false
    elseif missed_heartbeats >= self.suspect_threshold then
        -- 标记为可疑
        if node.status ~= NODE_STATUS.SUSPECT then
            node.status = NODE_STATUS.SUSPECT
            self.node_status[node_id] = NODE_STATUS.SUSPECT
            print(string.format("[容错管理] 节点 %s 状态变更为: 可疑", node_id))
        end
        return true  -- 仍然认为可用，但需警惕
    end
    
    return true
end

-- 标记节点为不健康
function FaultToleranceManager:_mark_node_unhealthy(node_id)
    local node = self.nodes[node_id]
    if not node then
        return false
    end
    
    node.status = NODE_STATUS.UNHEALTHY
    node.is_active = false
    self.node_status[node_id] = NODE_STATUS.UNHEALTHY
    
    print(string.format("[容错管理] 节点 %s 标记为不健康", node_id))
    
    -- 如果是主节点，触发故障转移
    if node.role == "primary" then
        self:trigger_failover(node_id)
    end
    
    return true
end

-- 恢复节点
function FaultToleranceManager:_recover_node(node_id)
    local node = self.nodes[node_id]
    if not node then
        return false
    end
    
    node.status = NODE_STATUS.HEALTHY
    node.is_active = true
    node.failure_count = 0
    node.recovery_count = node.recovery_count + 1
    self.node_status[node_id] = NODE_STATUS.HEALTHY
    self.failure_counts[node_id] = 0
    
    self.stats.total_recoveries = self.stats.total_recoveries + 1
    
    print(string.format("[容错管理] 节点 %s 已恢复", node_id))
    
    -- 如果节点是备份节点，检查是否需要重新同步数据
    if node.role == "backup" then
        self:_schedule_data_sync(node_id)
    end
    
    return true
end

-- 触发故障转移
function FaultToleranceManager:trigger_failover(failed_node_id)
    local failed_node = self.nodes[failed_node_id]
    if not failed_node then
        return false, "Node not found"
    end
    
    print(string.format("[容错管理] 触发节点 %s 的故障转移", failed_node_id))
    
    -- 查找可用的备份节点
    local backups = self.backup_nodes[failed_node_id]
    if not backups or #backups == 0 then
        print(string.format("[容错管理-警告] 节点 %s 没有可用的备份节点", failed_node_id))
        return false, "No backup nodes available"
    end
    
    -- 选择第一个可用的备份节点提升为主节点
    local promoted_node = nil
    for _, backup_id in ipairs(backups) do
        local backup = self.nodes[backup_id]
        if backup and backup.status == NODE_STATUS.HEALTHY then
            promoted_node = backup
            break
        end
    end
    
    if not promoted_node then
        print(string.format("[容错管理-警告] 节点 %s 的所有备份节点都不可用", failed_node_id))
        return false, "No healthy backup nodes"
    end
    
    -- 提升备份节点为主节点
    promoted_node.role = "primary"
    promoted_node.backup_for = nil
    self.primary_nodes[promoted_node.id] = promoted_node
    
    -- 更新备份映射
    self.backup_nodes[failed_node_id] = nil
    self.backup_nodes[promoted_node.id] = {}
    
    -- 记录故障转移
    local failover_record = {
        id = tostring(os.time()) .. "_" .. failed_node_id,
        failed_node = failed_node_id,
        promoted_node = promoted_node.id,
        timestamp = os.time(),
        status = "completed"
    }
    
    table.insert(self.failover_history, failover_record)
    self.stats.total_failovers = self.stats.total_failovers + 1
    
    print(string.format("[容错管理] 故障转移完成: %s -> %s", failed_node_id, promoted_node.id))
    
    return true, promoted_node.id
end

-- 安排数据同步
function FaultToleranceManager:_schedule_data_sync(node_id)
    print(string.format("[容错管理] 安排节点 %s 的数据同步", node_id))
    
    table.insert(self.sync_queue, {
        node_id = node_id,
        scheduled_at = os.time(),
        priority = "normal"
    })
    
    return true
end

-- 执行数据同步
function FaultToleranceManager:execute_data_sync()
    local sync_count = 0
    
    for i = #self.sync_queue, 1, -1 do
        local sync_task = self.sync_queue[i]
        local node = self.nodes[sync_task.node_id]
        
        if node and node.status == NODE_STATUS.HEALTHY then
            -- 执行同步（简化实现）
            print(string.format("[容错管理] 执行节点 %s 的数据同步", sync_task.node_id))
            sync_count = sync_count + 1
            table.remove(self.sync_queue, i)
        end
    end
    
    return sync_count
end

-- 获取节点状态
function FaultToleranceManager:get_node_status(node_id)
    if node_id then
        return self.node_status[node_id]
    end
    
    return self.node_status
end

-- 获取健康节点列表
function FaultToleranceManager:get_healthy_nodes()
    local healthy = {}
    
    for node_id, status in pairs(self.node_status) do
        if status == NODE_STATUS.HEALTHY then
            table.insert(healthy, node_id)
        end
    end
    
    return healthy
end

-- 获取容错统计
function FaultToleranceManager:get_stats()
    local node_stats = {}
    
    for node_id, node in pairs(self.nodes) do
        node_stats[node_id] = {
            status = node.status,
            role = node.role,
            is_active = node.is_active,
            failure_count = node.failure_count,
            recovery_count = node.recovery_count,
            last_heartbeat = node.last_heartbeat
        }
    end
    
    return {
        stats = self.stats,
        nodes = node_stats,
        failover_history = self.failover_history,
        pending_syncs = #self.sync_queue
    }
end

-- 检查所有节点健康状态
function FaultToleranceManager:check_all_nodes_health()
    local results = {
        healthy = 0,
        suspect = 0,
        unhealthy = 0,
        offline = 0
    }
    
    for node_id, _ in pairs(self.nodes) do
        local is_healthy = self:check_node_health(node_id)
        local status = self.node_status[node_id]
        
        if status == NODE_STATUS.HEALTHY then
            results.healthy = results.healthy + 1
        elseif status == NODE_STATUS.SUSPECT then
            results.suspect = results.suspect + 1
        elseif status == NODE_STATUS.UNHEALTHY then
            results.unhealthy = results.unhealthy + 1
        else
            results.offline = results.offline + 1
        end
    end
    
    return results
end

return FaultToleranceManager
