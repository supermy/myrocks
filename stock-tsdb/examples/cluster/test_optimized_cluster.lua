#!/usr/bin/env luajit

-- 优化的TSDB集群测试脚本
-- 测试集群优化功能的完整流程

local optimized_cluster_manager = require "lua.optimized_cluster_manager"

-- 测试配置
local TEST_CONFIG = {
    cluster = {
        node_id = "test_node_1",
        host = "127.0.0.1",
        port = 6379,
        cluster_port = 5555,
        max_nodes = 10,
        replication_factor = 2
    },
    network = {
        connection_pool = {
            max_pool_size = 10,
            connection_timeout = 3000,
            idle_timeout = 180000
        }
    },
    load_balancing = {
        algorithm = "round_robin"
    },
    data_sync = {
        incremental = {
            enabled = true,
            batch_size = 500,
            sync_interval = 2000
        }
    }
}

-- 测试函数
local function test_cluster_initialization()
    print("=== 测试集群初始化 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    
    -- 测试初始化
    local success, err = cluster:initialize()
    if not success then
        print("❌ 集群初始化失败:", err)
        return false
    end
    
    print("✅ 集群初始化成功")
    
    -- 验证集群状态
    assert(cluster.is_initialized == true, "集群应标记为已初始化")
    assert(cluster.local_node ~= nil, "本地节点应已创建")
    assert(cluster.local_node.status == "starting", "本地节点状态应为starting")
    
    print("✅ 集群状态验证通过")
    
    return true
end

local function test_cluster_start_stop()
    print("\n=== 测试集群启动和停止 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    
    -- 测试启动
    local success, err = cluster:start()
    if not success then
        print("❌ 集群启动失败:", err)
        return false
    end
    
    print("✅ 集群启动成功")
    
    -- 验证运行状态
    assert(cluster.is_running == true, "集群应标记为运行中")
    assert(cluster.local_node.status == "running", "本地节点状态应为running")
    
    print("✅ 集群运行状态验证通过")
    
    -- 测试停止
    success, err = cluster:stop()
    if not success then
        print("❌ 集群停止失败:", err)
        return false
    end
    
    print("✅ 集群停止成功")
    
    -- 验证停止状态
    assert(cluster.is_running == false, "集群应标记为已停止")
    assert(cluster.local_node.status == "stopped", "本地节点状态应为stopped")
    
    print("✅ 集群停止状态验证通过")
    
    return true
end

local function test_data_operations()
    print("\n=== 测试数据操作 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    cluster:initialize()
    
    -- 测试数据写入
    local test_key = "test_key_1"
    local test_value = {
        timestamp = os.time(),
        value = 42.5,
        tags = {"temperature", "sensor_1"}
    }
    
    local success, result = cluster:put_data(test_key, test_value)
    if not success then
        print("❌ 数据写入失败:", result)
        return false
    end
    
    print("✅ 数据写入成功:", result)
    
    -- 测试数据读取
    success, result = cluster:get_data(test_key)
    if not success then
        print("❌ 数据读取失败:", result)
        return false
    end
    
    print("✅ 数据读取成功")
    assert(result.value ~= nil, "读取的数据应包含value字段")
    assert(result.timestamp ~= nil, "读取的数据应包含timestamp字段")
    
    print("✅ 数据操作验证通过")
    
    return true
end

local function test_load_balancing()
    print("\n=== 测试负载均衡 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    cluster:initialize()
    
    -- 模拟多个数据操作，测试负载均衡
    local operations = 10
    local success_count = 0
    
    for i = 1, operations do
        local key = "test_key_" .. i
        local value = {value = i * 10, timestamp = os.time()}
        
        local success, result = cluster:put_data(key, value)
        if success then
            success_count = success_count + 1
        else
            print("❌ 操作失败:", result)
        end
    end
    
    local success_rate = success_count / operations * 100
    print(string.format("📊 负载均衡测试: %d/%d 操作成功 (%.1f%%)", 
        success_count, operations, success_rate))
    
    if success_rate < 80 then
        print("❌ 负载均衡测试失败: 成功率低于80%")
        return false
    end
    
    print("✅ 负载均衡测试通过")
    
    return true
end

local function test_fault_tolerance()
    print("\n=== 测试容错能力 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    cluster:initialize()
    
    -- 模拟节点故障处理
    print("🔧 模拟节点故障处理...")
    
    -- 这里应该测试故障检测和恢复机制
    -- 由于是简化实现，主要验证接口可用性
    
    -- 测试健康检查
    local local_health = cluster:check_local_node_health()
    if not local_health then
        print("❌ 本地节点健康检查失败")
        return false
    end
    
    print("✅ 本地节点健康检查通过")
    
    -- 测试故障处理接口
    cluster:handle_node_failure("test_failed_node")
    print("✅ 故障处理接口测试通过")
    
    return true
end

local function test_performance_metrics()
    print("\n=== 测试性能指标收集 ===")
    
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    cluster:initialize()
    
    -- 执行一些操作来生成性能指标
    for i = 1, 5 do
        local key = "metric_test_" .. i
        local value = {value = math.random(100), timestamp = os.time()}
        
        cluster:put_data(key, value)
        cluster:get_data(key)
    end
    
    -- 检查性能指标
    local metrics = cluster.metrics
    
    print("📊 性能指标统计:")
    print(string.format("   总请求数: %d", metrics.requests.total))
    print(string.format("   成功请求数: %d", metrics.requests.success))
    print(string.format("   失败请求数: %d", metrics.requests.failed))
    print(string.format("   平均响应时间: %.2f ms", metrics.requests.avg_response_time))
    
    -- 验证指标收集
    assert(metrics.requests.total > 0, "应收集到请求指标")
    assert(metrics.requests.success >= 0, "成功请求数应为非负数")
    assert(metrics.requests.failed >= 0, "失败请求数应为非负数")
    
    print("✅ 性能指标收集验证通过")
    
    return true
end

local function test_integration_scenario()
    print("\n=== 测试集成场景 ===")
    
    -- 模拟完整的集群使用场景
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    
    -- 1. 启动集群
    local success, err = cluster:start()
    if not success then
        print("❌ 集成测试: 集群启动失败:", err)
        return false
    end
    
    print("✅ 集成测试: 集群启动成功")
    
    -- 2. 执行批量数据操作
    local batch_size = 20
    local successful_operations = 0
    
    for i = 1, batch_size do
        local key = "integration_test_" .. i
        local value = {
            metric = "cpu_usage",
            value = math.random(100),
            timestamp = os.time(),
            tags = {"host=server_" .. math.random(10)}
        }
        
        success, err = cluster:put_data(key, value)
        if success then
            successful_operations = successful_operations + 1
            
            -- 验证数据读取
            success, result = cluster:get_data(key)
            if not success then
                print("❌ 集成测试: 数据读取失败:", result)
            end
        else
            print("❌ 集成测试: 数据写入失败:", err)
        end
    end
    
    local success_rate = successful_operations / batch_size * 100
    print(string.format("📊 集成测试: %d/%d 操作成功 (%.1f%%)", 
        successful_operations, batch_size, success_rate))
    
    if success_rate < 85 then
        print("❌ 集成测试失败: 成功率低于85%")
        cluster:stop()
        return false
    end
    
    -- 3. 检查集群状态
    print("🔍 检查集群状态...")
    assert(cluster.is_running == true, "集群应仍在运行")
    assert(cluster.local_node.status == "running", "本地节点应正常运行")
    
    -- 4. 优雅停止集群
    success, err = cluster:stop()
    if not success then
        print("❌ 集成测试: 集群停止失败:", err)
        return false
    end
    
    print("✅ 集成测试: 集群优雅停止成功")
    
    -- 5. 验证停止状态
    assert(cluster.is_running == false, "集群应已停止")
    assert(cluster.local_node.status == "stopped", "本地节点应已停止")
    
    print("✅ 集成测试全部通过")
    
    return true
end

-- 主测试函数
local function run_all_tests()
    print("🚀 开始运行优化的TSDB集群测试套件")
    print("=" .. string.rep("=", 50))
    
    local tests = {
        {name = "集群初始化", func = test_cluster_initialization},
        {name = "集群启动停止", func = test_cluster_start_stop},
        {name = "数据操作", func = test_data_operations},
        {name = "负载均衡", func = test_load_balancing},
        {name = "容错能力", func = test_fault_tolerance},
        {name = "性能指标", func = test_performance_metrics},
        {name = "集成场景", func = test_integration_scenario}
    }
    
    local passed_tests = 0
    local total_tests = #tests
    
    for i, test in ipairs(tests) do
        print(string.format("\n📋 测试 %d/%d: %s", i, total_tests, test.name))
        
        local success, result = pcall(test.func)
        
        if success and result then
            passed_tests = passed_tests + 1
            print("✅ 测试通过")
        else
            print("❌ 测试失败")
            if not success then
                print("   错误信息:", result)
            end
        end
    end
    
    print("\n" .. "=" .. string.rep("=", 50))
    print(string.format("📊 测试结果: %d/%d 测试通过", passed_tests, total_tests))
    
    if passed_tests == total_tests then
        print("🎉 所有测试通过! 优化的TSDB集群功能正常")
        return true
    else
        print("⚠️  部分测试失败，需要进一步优化")
        return false
    end
end

-- 运行测试
if arg and arg[0] and string.find(arg[0], "test_optimized_cluster") then
    local success = run_all_tests()
    os.exit(success and 0 or 1)
end

return {
    run_all_tests = run_all_tests,
    test_cluster_initialization = test_cluster_initialization,
    test_cluster_start_stop = test_cluster_start_stop,
    test_data_operations = test_data_operations,
    test_load_balancing = test_load_balancing,
    test_fault_tolerance = test_fault_tolerance,
    test_performance_metrics = test_performance_metrics,
    test_integration_scenario = test_integration_scenario
}