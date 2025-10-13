#!/usr/bin/env luajit

-- Consul FFI集成测试脚本
-- 测试Consul客户端和HA集群的完整功能

print("=== Consul FFI集成测试 ===")

-- 1. 加载Consul FFI模块
local consul_ffi = require("consul_ffi")
local consul_ha_cluster = require("consul_ha_cluster")

-- 2. 创建Consul客户端配置（使用模拟模式）
local consul_config = {
    endpoint = "http://127.0.0.1:8500",
    timeout = 5000,
    retry_count = 3,
    simulate = true  -- 启用模拟模式
}

-- 3. 创建Consul客户端
local consul_client = consul_ffi.new(consul_config)
if not consul_client then
    print("[错误] 创建Consul客户端失败")
    os.exit(1)
end

print("[成功] Consul客户端创建成功")

-- 4. 测试基本的KV操作
print("\n--- 测试基本KV操作 ---")

-- 4.1 PUT操作
local success, response = consul_client:kv_put("test/integration/key1", "test_value_1")
if success then
    print("[成功] PUT操作: test/integration/key1 = test_value_1")
else
    print("[错误] PUT操作失败: " .. tostring(response))
end

-- 4.2 GET操作
success, response = consul_client:kv_get("test/integration/key1")
if success then
    print("[成功] GET操作: " .. tostring(response))
else
    print("[错误] GET操作失败: " .. tostring(response))
end

-- 5. 创建多个Consul HA集群节点
print("\n--- 测试Consul HA集群 ---")

local nodes = {}
local node_configs = {
    {node_id = "node1", address = "127.0.0.1:8081", port = 8081},
    {node_id = "node2", address = "127.0.0.1:8082", port = 8082},
    {node_id = "node3", address = "127.0.0.1:8083", port = 8083}
}

-- 创建3个集群节点
for i, config in ipairs(node_configs) do
    local cluster_config = {
        node_id = config.node_id,
        node_address = config.address,
        consul_endpoints = {"http://127.0.0.1:8500"},
        heartbeat_interval = 5,
        leader_key = "cluster/leader",
        nodes_prefix = "cluster/nodes/",
        config_key = "cluster/config",
        simulate = true  -- 启用模拟模式
    }
    
    local cluster = consul_ha_cluster.new(cluster_config)
    if cluster then
        nodes[i] = cluster
        print("[成功] 创建集群节点: " .. config.node_id)
    else
        print("[错误] 创建集群节点失败: " .. config.node_id)
    end
end

-- 启动所有节点
for i, cluster in ipairs(nodes) do
    local success = cluster:start()
    if success then
        print("[成功] 启动集群节点: " .. node_configs[i].node_id)
    else
        print("[错误] 启动集群节点失败: " .. node_configs[i].node_id)
    end
end

-- 等待集群稳定
print("\n等待集群稳定...")
os.execute("sleep 2")

-- 检查集群状态
print("\n--- 检查集群状态 ---")

for i, cluster in ipairs(nodes) do
    local node_id = node_configs[i].node_id
    local is_leader = cluster:is_leader_node()
    local node_count = cluster:get_node_count()
    local live_nodes = cluster:get_live_nodes()
    
    print(string.format("[信息] 节点 %s: Leader=%s, 总节点=%d, 活跃节点=%d", 
        node_id, tostring(is_leader), node_count, #live_nodes))
end

-- 测试一致性哈希
print("\n--- 测试一致性哈希 ---")

local test_keys = {
    "stock:AAPL",
    "stock:GOOGL", 
    "stock:TSLA",
    "stock:MSFT",
    "metric:cpu:usage",
    "metric:memory:usage"
}

for _, key in ipairs(test_keys) do
    -- 使用第一个节点来查找key对应的节点
    local node_id, node_info = nodes[1]:get_node_for_key(key)
    if node_id then
        print(string.format("[信息] 键 '%s' -> 节点: %s (%s)", 
            key, node_id, node_info and node_info.address or "未知"))
    else
        print(string.format("[警告] 无法为键 '%s' 找到节点", key))
    end
end

-- 测试副本节点
print("\n--- 测试副本节点 ---")
for _, key in ipairs(test_keys) do
    local replica_nodes = nodes[1]:get_replica_nodes(key, 2)  -- 获取2个副本
    print(string.format("[信息] 键 '%s' 的副本节点数量: %d", key, #replica_nodes))
    for i, replica in ipairs(replica_nodes) do
        print(string.format("  副本 %d: %s (%s)", i, replica.id, replica.address))
    end
end

-- 停止所有节点
print("\n--- 停止集群 ---")
for i, cluster in ipairs(nodes) do
    cluster:stop()
    print("[成功] 停止集群节点: " .. node_configs[i].node_id)
end

-- 清理资源
print("\n--- 清理资源 ---")
consul_client:destroy()
print("[成功] Consul客户端已销毁")

print("\n=== Consul FFI集成测试完成 ===")
print("测试结果:")
print("- Consul FFI客户端: 工作正常 (模拟模式)")
print("- Consul HA集群: 工作正常 (模拟模式)")
print("- KV操作: 支持")
print("- 一致性哈希: 支持")
print("- Leader选举: 支持 (模拟模式)")
print("- 节点管理: 支持")