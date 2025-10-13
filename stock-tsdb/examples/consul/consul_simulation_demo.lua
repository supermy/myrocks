#!/usr/bin/env luajit

-- Consul FFI 模拟模式演示
-- Simulation mode demonstration for Consul FFI integration

package.path = package.path .. ";./?.lua;/opt/stock-tsdb/lua/?.lua"

-- 使用模拟模式进行测试
local consul_ffi = require("consul_ffi")
local consul_ha_cluster = require("consul_ha_cluster")

print("=== Consul FFI 模拟模式演示 ===")

-- 创建模拟模式的Consul客户端
local consul_client = consul_ffi.ConsulClient:new({
    consul_url = "http://localhost:8500",
    timeout = 5000,
    simulate = true  -- 启用模拟模式
})

if not consul_client or not consul_client.initialized then
    print("[错误] 无法创建Consul客户端")
    os.exit(1)
end

print("[成功] 创建模拟模式Consul客户端")

-- 测试KV操作
print("\n=== KV操作测试 ===")

-- 1. 存储数据
local test_data = {
    symbol = "AAPL",
    price = 150.25,
    volume = 1000000,
    timestamp = os.time()
}

local success, result = consul_client:kv_put("stocks/AAPL/20241012", test_data)
if success then
    print("[成功] 存储数据: stocks/AAPL/20241012")
else
    print("[错误] 存储数据失败: " .. tostring(result))
end

-- 2. 读取数据
success, result = consul_client:kv_get("stocks/AAPL/20241012")
if success then
    print("[成功] 读取数据: " .. tostring(result))
else
    print("[错误] 读取数据失败: " .. tostring(result))
end

-- 3. 删除数据
success, result = consul_client:kv_delete("stocks/AAPL/20241012")
if success then
    print("[成功] 删除数据")
else
    print("[错误] 删除数据失败: " .. tostring(result))
end

-- 测试服务注册发现
print("\n=== 服务注册发现测试 ===")

-- 1. 注册服务
local service_name = "stock-tsdb"
local service_address = "127.0.0.1"
local service_port = 8080
local service_tags = {"database", "timeseries", "stock"}

success, result = consul_client:register_service("stock-tsdb-node1", service_name, service_address, service_port, service_tags)
if success then
    print("[成功] 注册服务: stock-tsdb-node1")
else
    print("[错误] 注册服务失败: " .. tostring(result))
end

-- 2. 发现服务
success, result = consul_client:discover_services("stock-tsdb")
if success then
    print("[成功] 发现服务: " .. tostring(result))
else
    print("[错误] 发现服务失败: " .. tostring(result))
end

-- 3. 注销服务
success, result = consul_client:deregister_service("stock-tsdb-node1")
if success then
    print("[成功] 注销服务: stock-tsdb-node1")
else
    print("[错误] 注销服务失败: " .. tostring(result))
end

-- 测试会话管理
print("\n=== 会话管理测试 ===")

-- 1. 创建会话
success, result = consul_client:create_session("test-session", "30s")
if success then
    print("[成功] 创建会话: " .. tostring(result))
else
    print("[错误] 创建会话失败: " .. tostring(result))
end

-- 2. 销毁会话
if result then
    local session_id = result:match('"ID":"([^"]+)"')
    if session_id then
        success, result = consul_client:destroy_session(session_id)
        if success then
            print("[成功] 销毁会话: " .. session_id)
        else
            print("[错误] 销毁会话失败: " .. tostring(result))
        end
    end
end

-- 测试HA集群
print("\n=== HA集群测试 ===")

-- 创建模拟模式的HA集群
local cluster = consul_ha_cluster.ConsulHACluster:new({
    consul_url = "http://localhost:8500",
    node_id = "test-node-1",
    node_address = "127.0.0.1:8081",
    heartbeat_interval = 5,
    simulate = true  -- 启用模拟模式
})

if cluster then
    print("[成功] 创建HA集群实例")
    
    -- 启动集群
    cluster:start()
    print("[成功] 启动HA集群")
    
    -- 获取节点数量
    local node_count = cluster:get_node_count()
    print("[信息] 集群节点数量: " .. node_count)
    
    -- 检查是否为Leader
    local is_leader = cluster:is_leader_node()
    print("[信息] 当前节点是否为Leader: " .. tostring(is_leader))
    
    -- 获取Leader信息
    local leader_info = cluster:get_leader_info()
    print("[信息] Leader信息: " .. tostring(leader_info or "无"))
    
    -- 测试一致性哈希
    print("\n--- 一致性哈希测试 ---")
    local test_keys = {"AAPL", "GOOGL", "MSFT", "TSLA", "AMZN"}
    
    for _, key in ipairs(test_keys) do
        local node = cluster:get_node_for_key(key)
        if node then
            print("[信息] 键 '" .. key .. "' -> 节点: " .. node)
        else
            print("[警告] 无法为键 '" .. key .. "' 找到节点")
        end
    end
    
    -- 测试副本节点
    print("\n--- 副本节点测试 ---")
    for _, key in ipairs(test_keys) do
        local replicas = cluster:get_replica_nodes(key, 2)
        print("[信息] 键 '" .. key .. "' 的副本节点数量: " .. #replicas)
        for i, replica in ipairs(replicas) do
            print("  副本 " .. i .. ": " .. replica)
        end
    end
    
    -- 停止集群
    cluster:stop()
    print("[成功] 停止HA集群")
else
    print("[错误] 无法创建HA集群实例")
end

-- 清理资源
consul_client:destroy()
print("\n[成功] 清理Consul客户端资源")

print("\n=== Consul FFI 模拟模式演示完成 ===")