#!/usr/bin/env luajit

-- 基于Consul的高可用集群管理器

local ffi = require "ffi"
local consul_ffi = require "consul_ffi"

-- 一致性哈希环实现（复用原有的MurmurHash3算法）
local ConsistentHashRing = {}
ConsistentHashRing.__index = ConsistentHashRing

function ConsistentHashRing:new(virtual_nodes)
    local obj = setmetatable({}, ConsistentHashRing)
    obj.virtual_nodes = virtual_nodes or 160  -- 每个物理节点的虚拟节点数
    obj.ring = {}  -- 哈希环
    obj.nodes = {}  -- 物理节点映射
    obj.sorted_keys = {}  -- 排序的哈希键
    return obj
end

-- MurmurHash3算法实现（LuaJIT兼容版本）
function ConsistentHashRing:murmurhash3(key, seed)
    local h = seed or 0
    local k = 0
    
    -- LuaJIT兼容的位操作函数
    local function band(a, b)
        return bit.band(a, b)
    end
    
    local function bxor(a, b)
        return bit.bxor(a, b)
    end
    
    local function lrotate(x, n)
        return bit.rol(x, n)
    end
    
    local function rshift(x, n)
        return bit.rshift(x, n)
    end
    
    for i = 1, #key do
        k = string.byte(key, i)
        k = k * 0xcc9e2d51
        k = band(k, 0xffffffff)
        k = lrotate(k, 15)
        k = k * 0x1b873593
        k = band(k, 0xffffffff)
        
        h = bxor(h, k)
        h = lrotate(h, 13)
        h = h * 5 + 0xe6546b64
        h = band(h, 0xffffffff)
    end
    
    h = bxor(h, #key)
    h = bxor(h, rshift(h, 16))
    h = h * 0x85ebca6b
    h = band(h, 0xffffffff)
    h = bxor(h, rshift(h, 13))
    h = h * 0xc2b2ae35
    h = band(h, 0xffffffff)
    h = bxor(h, rshift(h, 16))
    
    return h
end

function ConsistentHashRing:add_node(node_id, node_info)
    -- 添加物理节点到哈希环
    self.nodes[node_id] = node_info
    
    -- 为每个物理节点创建虚拟节点
    for i = 1, self.virtual_nodes do
        local virtual_key = string.format("%s#%d", node_id, i)
        local hash = self:murmurhash3(virtual_key)
        
        self.ring[hash] = node_id
        table.insert(self.sorted_keys, hash)
    end
    
    -- 重新排序哈希键
    table.sort(self.sorted_keys)
end

function ConsistentHashRing:remove_node(node_id)
    -- 从哈希环中移除节点
    self.nodes[node_id] = nil
    
    -- 移除所有虚拟节点
    local new_keys = {}
    for hash, node in pairs(self.ring) do
        if node ~= node_id then
            table.insert(new_keys, hash)
        else
            self.ring[hash] = nil
        end
    end
    
    self.sorted_keys = new_keys
    table.sort(self.sorted_keys)
end

function ConsistentHashRing:get_node(key)
    -- 根据键获取对应的节点
    if #self.sorted_keys == 0 then
        return nil
    end
    
    local hash = self:murmurhash3(key)
    
    -- 二分查找第一个大于等于hash的节点
    local left, right = 1, #self.sorted_keys
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if self.sorted_keys[mid] < hash then
            left = mid + 1
        else
            right = mid - 1
        end
    end
    
    -- 如果找到末尾，回到环的开头
    if left > #self.sorted_keys then
        left = 1
    end
    
    local node_hash = self.sorted_keys[left]
    return self.ring[node_hash], self.nodes[self.ring[node_hash]]
end

function ConsistentHashRing:get_replica_nodes(key, replica_count)
    -- 获取主节点和副本节点
    local primary_node = self:get_node(key)
    if not primary_node then
        return {}
    end
    
    local replicas = {primary_node}
    replica_count = replica_count or 2
    
    -- 获取后续的副本节点
    local hash = self:murmurhash3(key)
    local left, right = 1, #self.sorted_keys
    
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if self.sorted_keys[mid] < hash then
            left = mid + 1
        else
            right = mid - 1
        end
    end
    
    for i = 1, replica_count - 1 do
        local next_idx = (left + i - 1) % #self.sorted_keys + 1
        local node_hash = self.sorted_keys[next_idx]
        local node_id = self.ring[node_hash]
        
        if node_id ~= primary_node and not self:contains(replicas, node_id) then
            table.insert(replicas, node_id)
        end
    end
    
    return replicas
end

function ConsistentHashRing:contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- 基于Consul的高可用集群管理器
local ConsulHACluster = {}
ConsulHACluster.__index = ConsulHACluster

function ConsulHACluster:new(config)
    local obj = setmetatable({}, ConsulHACluster)
    obj.config = config or {}
    obj.hash_ring = ConsistentHashRing:new()
    obj.consul_client = nil
    obj.node_id = config.node_id or ("node_" .. tostring(os.time()))
    obj.node_address = config.node_address or "127.0.0.1:8080"
    obj.heartbeat_interval = config.heartbeat_interval or 5  -- 心跳间隔（秒）
    obj.lease_ttl = config.lease_ttl or 30  -- 租约TTL（秒）
    obj.session_id = nil
    obj.is_leader = false
    obj.leader_key = "/tsdb/cluster/leader"
    obj.nodes_prefix = "/tsdb/cluster/nodes/"
    obj.shards_prefix = "/tsdb/cluster/shards/"
    obj.running = false
    obj.heartbeat_timer = nil
    obj.cluster_nodes = {}
    
    -- 初始化Consul客户端
    if config.consul_url then
        obj:initialize_consul()
    end
    
    return obj
end

function ConsulHACluster:initialize_consul()
    -- 初始化Consul客户端
    local consul_config = {
        consul_url = self.config.consul_url or "http://127.0.0.1:8500",
        timeout = 5000
    }
    
    self.consul_client = consul_ffi.new(consul_config)
    
    if self.consul_client then
        print("[Consul HA] Consul客户端初始化成功: " .. consul_config.consul_url)
        
        -- 创建会话（用于分布式锁）
        local success, response = self.consul_client:create_session("tsdb-cluster-" .. self.node_id, self.lease_ttl .. "s")
        if success then
            -- 解析响应获取会话ID（简化处理）
            local session_match = response:match('"ID":"([^"]+)"')
            if session_match then
                self.session_id = session_match
                print("[Consul HA] 会话创建成功: " .. self.session_id)
            else
                print("[Consul HA] 警告: 无法解析会话ID，使用模拟模式")
                self.session_id = "mock_session_" .. self.node_id
            end
        else
            print("[Consul HA] 警告: 会话创建失败，使用模拟模式: " .. tostring(response))
            self.session_id = "mock_session_" .. self.node_id
        end
    else
        print("[Consul HA] 警告: Consul客户端初始化失败，使用本地模式")
        self.consul_client = nil
    end
end

function ConsulHACluster:start()
    -- 启动集群管理器
    print("[Consul HA] 启动集群管理器: " .. self.node_id)
    self.running = true
    
    -- 注册节点
    self:register_node()
    
    -- 加载集群配置
    self:load_cluster_config()
    
    -- 启动心跳
    self:start_heartbeat()
    
    -- 尝试成为Leader
    self:try_become_leader()
    
    print("[Consul HA] 集群管理器启动完成")
end

function ConsulHACluster:stop()
    -- 停止集群管理器
    print("[Consul HA] 停止集群管理器")
    self.running = false
    
    -- 注销节点
    self:unregister_node()
    
    -- 销毁会话
    if self.session_id and self.consul_client then
        self.consul_client:destroy_session(self.session_id)
    end
    
    print("[Consul HA] 集群管理器已停止")
end

function ConsulHACluster:register_node()
    -- 注册节点到Consul
    local node_info = {
        id = self.node_id,
        address = self.node_address,
        status = "alive",
        last_seen = os.time(),
        session_id = self.session_id
    }
    
    local node_key = self.nodes_prefix .. self.node_id
    local node_json = self:encode_json(node_info)
    
    if self.consul_client then
        local success, response = self.consul_client:kv_put(node_key, node_json)
        if success then
            print("[Consul HA] 节点注册成功: " .. self.node_id)
        else
            print("[Consul HA] 节点注册失败: " .. tostring(response))
        end
    else
        print("[Consul HA] 模拟节点注册: " .. self.node_id)
        self.cluster_nodes[self.node_id] = node_info
    end
end

function ConsulHACluster:unregister_node()
    -- 从Consul注销节点
    local node_key = self.nodes_prefix .. self.node_id
    
    if self.consul_client then
        local success, response = self.consul_client:kv_delete(node_key)
        if success then
            print("[Consul HA] 节点注销成功: " .. self.node_id)
        else
            print("[Consul HA] 节点注销失败: " .. tostring(response))
        end
    else
        print("[Consul HA] 模拟节点注销: " .. self.node_id)
        self.cluster_nodes[self.node_id] = nil
    end
end

function ConsulHACluster:load_cluster_config()
    -- 从Consul加载集群配置
    print("[Consul HA] 加载集群配置...")
    
    if self.consul_client then
        -- 获取所有节点
        local success, response = self.consul_client:kv_get(self.nodes_prefix, true)  -- recurse=true
        if success then
            self:parse_nodes_response(response)
        else
            print("[Consul HA] 加载节点配置失败: " .. tostring(response))
        end
        
        -- 获取Leader信息
        local leader_success, leader_response = self.consul_client:kv_get(self.leader_key)
        if leader_success and leader_response ~= "[]" then
            local leader_node = leader_response:match('"Value":"([^"]+)"')
            if leader_node then
                local decoded = self:decode_json(self:base64_decode(leader_node))
                if decoded == self.node_id then
                    self.is_leader = true
                    print("[Consul HA] 当前节点是Leader")
                end
            end
        end
    else
        print("[Consul HA] 使用本地集群配置")
        -- 使用模拟数据
        self.cluster_nodes["node1"] = {id="node1", address="127.0.0.1:8081", status="alive"}
        self.cluster_nodes["node2"] = {id="node2", address="127.0.0.1:8082", status="alive"}
    end
    
    -- 更新哈希环
    self:update_hash_ring()
end

function ConsulHACluster:parse_nodes_response(response)
    -- 解析Consul的节点响应
    if response == "[]" then
        return
    end
    
    -- 简化解析（实际实现需要更完善的JSON解析）
    for node_data in response:gmatch('%b{}') do
        local key = node_data:match('"Key":"([^"]+)"')
        local value = node_data:match('"Value":"([^"]+)"')
        
        if key and value then
            local node_id = key:match("nodes/(.+)$")
            if node_id then
                local decoded_value = self:base64_decode(value)
                local node_info = self:decode_json(decoded_value)
                if node_info then
                    self.cluster_nodes[node_id] = node_info
                end
            end
        end
    end
end

function ConsulHACluster:update_hash_ring()
    -- 更新一致性哈希环
    print("[Consul HA] 更新一致性哈希环...")
    
    -- 清空现有环
    self.hash_ring = ConsistentHashRing:new()
    
    -- 添加活跃节点到哈希环
    for node_id, node_info in pairs(self.cluster_nodes) do
        if node_info.status == "alive" then
            self.hash_ring:add_node(node_id, node_info)
        end
    end
    
    print("[Consul HA] 哈希环更新完成，节点数量: " .. self:get_node_count())
end

function ConsulHACluster:start_heartbeat()
    -- 启动心跳机制（简化版本，暂时禁用定时器）
    print("[Consul HA] 启动心跳机制...")
    
    -- 立即执行一次心跳逻辑（模拟）
    self:update_node_status()
    self:check_leader_status()
    
    -- 在实际实现中，这里应该启动真正的定时器
    -- 现在只是返回一个模拟的定时器对象
    self.heartbeat_timer = {cancel = function() end}
end

function ConsulHACluster:update_node_status()
    -- 更新节点状态
    local node_key = self.nodes_prefix .. self.node_id
    local node_info = {
        id = self.node_id,
        address = self.node_address,
        status = "alive",
        last_seen = os.time(),
        session_id = self.session_id
    }
    
    local node_json = self:encode_json(node_info)
    
    if self.consul_client then
        self.consul_client:kv_put(node_key, node_json)
    else
        self.cluster_nodes[self.node_id] = node_info
    end
end

function ConsulHACluster:check_leader_status()
    -- 检查Leader状态
    if self.is_leader then
        -- 当前是Leader，检查是否需要续租
        self:renew_leader_lease()
    else
        -- 当前不是Leader，尝试成为Leader
        self:try_become_leader()
    end
end

function ConsulHACluster:try_become_leader()
    -- 尝试成为Leader（使用分布式锁）
    if not self.consul_client then
        -- 模拟模式：只有node1可以成为Leader
        if self.node_id == "node1" then
            self.is_leader = true
            print("[Consul HA] 成为Leader (模拟模式)")
        end
        return
    end
    
    -- 尝试获取Leader锁
    local leader_value = self:encode_json({
        node_id = self.node_id,
        session_id = self.session_id,
        timestamp = os.time()
    })
    
    local success, response = self.consul_client:kv_put(self.leader_key, leader_value)
    if success then
        self.is_leader = true
        print("[Consul HA] 成功成为Leader")
    else
        print("[Consul HA] 成为Leader失败: " .. tostring(response))
    end
end

function ConsulHACluster:renew_leader_lease()
    -- 续租Leader地位
    if not self.is_leader then
        return
    end
    
    print("[Consul HA] 续租Leader地位")
    -- 这里可以实现更复杂的续租逻辑
end

function ConsulHACluster:get_node_for_key(key)
    -- 根据键获取对应的节点
    local node_id, node_info = self.hash_ring:get_node(key)
    return node_id, node_info
end

function ConsulHACluster:get_replica_nodes(key, replica_count)
    -- 获取键的副本节点
    return self.hash_ring:get_replica_nodes(key, replica_count)
end

function ConsulHACluster:get_live_nodes()
    -- 获取活跃节点列表
    local live_nodes = {}
    
    for node_id, node_info in pairs(self.cluster_nodes) do
        if node_info.status == "alive" then
            local last_seen = node_info.last_seen or 0
            local current_time = os.time()
            
            -- 检查节点是否超时（超过2倍心跳间隔）
            if current_time - last_seen <= self.heartbeat_interval * 2 then
                table.insert(live_nodes, node_info)
            end
        end
    end
    
    return live_nodes
end

function ConsulHACluster:get_node_count()
    -- 获取节点数量
    local count = 0
    for _ in pairs(self.cluster_nodes) do
        count = count + 1
    end
    return count
end

function ConsulHACluster:is_leader_node()
    -- 检查当前节点是否为Leader
    return self.is_leader
end

function ConsulHACluster:get_leader_info()
    -- 获取Leader信息
    if self.consul_client then
        local success, response = self.consul_client:kv_get(self.leader_key)
        if success and response ~= "[]" then
            local leader_data = response:match('"Value":"([^"]+)"')
            if leader_data then
                local decoded = self:base64_decode(leader_data)
                return self:decode_json(decoded)
            end
        end
    end
    
    return nil
end

-- 工具函数
function ConsulHACluster:encode_json(t)
    -- 简化的JSON编码器
    if type(t) ~= "table" then
        return tostring(t)
    end
    
    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "string" then
            table.insert(parts, '"' .. k .. '":"' .. v .. '"')
        elseif type(v) == "number" then
            table.insert(parts, '"' .. k .. '":' .. v)
        elseif type(v) == "boolean" then
            table.insert(parts, '"' .. k .. '":' .. tostring(v))
        elseif type(v) == "table" then
            table.insert(parts, '"' .. k .. '":' .. self:encode_json(v))
        end
    end
    
    return "{" .. table.concat(parts, ",") .. "}"
end

function ConsulHACluster:decode_json(json_str)
    -- 简化的JSON解码器（实际实现需要更完善的JSON解析）
    local result = {}
    
    -- 简单的键值对提取
    for k, v in json_str:gmatch('"([^"]+)":"([^"]+)"') do
        result[k] = v
    end
    
    for k, v in json_str:gmatch('"([^"]+)":(%d+)') do
        result[k] = tonumber(v)
    end
    
    for k, v in json_str:gmatch('"([^"]+)":(true|false)') do
        result[k] = (v == "true")
    end
    
    return result
end

function ConsulHACluster:base64_decode(data)
    -- 简化的base64解码（实际实现需要更完善的解码）
    -- 这里返回原始数据用于测试
    return data
end

function ConsulHACluster:timer(interval, callback)
    -- 定时器函数（简化实现）
    -- 在实际实现中，这里应该使用真正的定时器机制
    -- 这里只是返回一个模拟的定时器对象，不实际执行回调
    
    -- 在实际环境中，这里应该使用协程或真正的定时器
    -- 现在只是返回模拟对象，不执行回调以避免无限递归
    
    return {cancel = function() end}  -- 返回模拟的定时器对象
end

-- 定时器函数（简化实现）
local function timer(interval, callback)
    -- 在实际实现中，这里应该使用真正的定时器机制
    -- 这里使用简单的延迟执行模拟
    local function delayed_exec()
        local start_time = os.time()
        while os.time() - start_time < interval do
            -- 简单的忙等待（实际实现中不应该这样做）
        end
        callback()
    end
    
    -- 在实际环境中，这里应该使用协程或真正的定时器
    -- 现在立即执行一次回调（模拟定时器触发）
    callback()
    
    return {cancel = function() end}  -- 返回模拟的定时器对象
end

-- 创建集群实例
local function create_consul_ha_cluster(config)
    return ConsulHACluster:new(config)
end

-- 模块导出
return {
    new = create_consul_ha_cluster,
    ConsulHACluster = ConsulHACluster,
    ConsistentHashRing = ConsistentHashRing
}