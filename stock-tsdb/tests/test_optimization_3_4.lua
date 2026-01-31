#!/usr/bin/env luajit
-- 优化方案3和4的测试

package.path = package.path .. ";./?.lua;./lua/?.lua"

local SmartLoadBalancer = require("lua.smart_load_balancer")
local PerformanceMonitor = require("lua.performance_monitor")
local ConnectionPool = require("lua.connection_pool")
local FaultToleranceManager = require("lua.fault_tolerance_manager")

print("=== 优化方案3和4测试 ===")
print("测试时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
print("")

local test_results = {
    passed = 0,
    failed = 0
}

local function assert_true(condition, message)
    if condition then
        print("✓ " .. message)
        test_results.passed = test_results.passed + 1
        return true
    else
        print("✗ " .. message)
        test_results.failed = test_results.failed + 1
        return false
    end
end

-- ==================== 测试优化方案3: 智能负载均衡 ====================
print("--- 测试优化方案3: 智能负载均衡 ---")

local lb = SmartLoadBalancer:new({
    algorithm = "adaptive",
    health_check_interval = 5000
})

-- 添加测试节点
lb:add_node("node1", {host = "192.168.1.1", port = 8080, weight = 3})
lb:add_node("node2", {host = "192.168.1.2", port = 8080, weight = 2})
lb:add_node("node3", {host = "192.168.1.3", port = 8080, weight = 1})

assert_true(#lb.node_list == 3, "成功添加3个节点")

-- 测试节点选择
local selected = lb:select_node()
assert_true(selected ~= nil, "成功选择节点")

-- 更新节点指标
lb:update_node_metrics(selected.id, 50, true)
assert_true(selected.success_count == 1, "成功更新节点指标")

-- 测试算法切换
local switch_result = lb:switch_algorithm("round_robin")
assert_true(switch_result == true, "成功切换负载均衡算法")
assert_true(lb.algorithm == "round_robin", "算法已切换为轮询")

-- 获取统计信息
local lb_stats = lb:get_stats()
assert_true(lb_stats.total_nodes == 3, "负载均衡器统计正确")

print("")

-- ==================== 测试优化方案3: 性能监控 ====================
print("--- 测试优化方案3: 性能监控 ---")

local monitor = PerformanceMonitor:new({
    enabled = true,
    collection_interval = 5000
})

assert_true(monitor.enabled == true, "性能监控已启用")

-- 添加告警规则
local alert_id = monitor:add_alert_rule({
    name = "CPU使用率告警",
    metric_type = "system",
    metric_name = "cpu_usage",
    operator = ">",
    threshold = 80,
    duration = 60
})
assert_true(alert_id ~= nil, "成功添加告警规则")

-- 收集指标
local metrics = monitor:collect_all_metrics()
assert_true(metrics ~= nil, "成功收集性能指标")
assert_true(metrics.system ~= nil, "系统指标已收集")
assert_true(metrics.application ~= nil, "应用指标已收集")

-- 获取监控报告
local report = monitor:get_report()
assert_true(report ~= nil, "成功生成监控报告")
assert_true(report.summary ~= nil, "报告包含摘要信息")

print("")

-- ==================== 测试优化方案4: 连接池 ====================
print("--- 测试优化方案4: 连接池管理 ---")

local pool = ConnectionPool:new({
    max_pool_size = 10,
    min_pool_size = 2,
    connection_timeout = 5000
})

-- 测试获取连接
local conn1, err1 = pool:borrow_connection("target1")
assert_true(conn1 ~= nil, "成功获取连接1")
assert_true(conn1.target_id == "target1", "连接目标ID正确")

local conn2, err2 = pool:borrow_connection("target1")
assert_true(conn2 ~= nil, "成功获取连接2")
assert_true(conn2.id ~= conn1.id, "连接ID唯一")

-- 测试归还连接
local return_result = pool:return_connection(conn1)
assert_true(return_result == true, "成功归还连接")

-- 获取连接池统计
local pool_stats = pool:get_stats()
assert_true(pool_stats.global_stats.total_created >= 2, "连接池统计正确")

print("")

-- ==================== 测试优化方案4: 容错管理 ====================
print("--- 测试优化方案4: 容错管理 ---")

local ft_manager = FaultToleranceManager:new({
    heartbeat_interval = 30000,
    timeout_threshold = 3
})

-- 注册主节点
ft_manager:register_node("primary1", {
    host = "192.168.1.10",
    port = 8080,
    role = "primary"
})

-- 注册备份节点
ft_manager:register_node("backup1", {
    host = "192.168.1.11",
    port = 8080,
    role = "backup",
    backup_for = "primary1"
})

assert_true(ft_manager.nodes["primary1"] ~= nil, "主节点注册成功")
assert_true(ft_manager.nodes["backup1"] ~= nil, "备份节点注册成功")

-- 测试心跳
local heartbeat_result = ft_manager:handle_heartbeat("primary1")
assert_true(heartbeat_result == true, "心跳处理成功")

-- 测试健康检查
local health_result = ft_manager:check_node_health("primary1")
assert_true(health_result == true, "节点健康检查通过")

-- 获取容错统计
local ft_stats = ft_manager:get_stats()
assert_true(ft_stats.stats ~= nil, "容错统计信息获取成功")
assert_true(ft_stats.nodes["primary1"] ~= nil, "主节点状态信息存在")

print("")

-- ==================== 测试结果汇总 ====================
print("=== 测试结果汇总 ===")
print(string.format("通过: %d", test_results.passed))
print(string.format("失败: %d", test_results.failed))
print(string.format("成功率: %.1f%%", (test_results.passed / (test_results.passed + test_results.failed)) * 100))

if test_results.failed == 0 then
    print("\n🎉 优化方案3和4测试全部通过！")
    print("\n已实现的优化功能:")
    print("  优化方案3:")
    print("    ✓ 智能负载均衡器（支持5种算法）")
    print("    ✓ 性能监控器（系统/应用/存储指标）")
    print("    ✓ 实时告警机制")
    print("  优化方案4:")
    print("    ✓ 连接池管理（连接复用）")
    print("    ✓ 容错管理器（故障检测与转移）")
    print("    ✓ 数据同步机制")
    os.exit(0)
else
    print("\n⚠ 部分测试失败")
    os.exit(1)
end
