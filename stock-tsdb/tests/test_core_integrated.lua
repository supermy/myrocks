#!/usr/bin/env luajit
-- 集成版本存储引擎测试 - 验证集成版本的基本功能

package.path = package.path .. ";./?.lua;./lua/?.lua"

local TSDBStorageEngineIntegrated = require("lua.tsdb_storage_engine_integrated")

print("=== 集成版本存储引擎测试 ===")
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

-- 测试1: 创建集成引擎
print("--- 测试1: 创建集成引擎 ---")
local engine = TSDBStorageEngineIntegrated:new({
    data_dir = "./test_core_integrated_data",
    node_id = "test_node_1",
    cluster_name = "test-cluster",
    enable_cold_data_separation = true,
    cold_data_threshold_days = 30
})
assert_true(engine ~= nil, "集成引擎创建成功")

-- 测试2: 初始化
print("\n--- 测试2: 初始化 ---")
local init_success = engine:init()
assert_true(init_success, "集成引擎初始化成功")

-- 测试3: 写入股票数据
print("\n--- 测试3: 写入股票数据 ---")
local stock_data = {
    open = 100.5,
    high = 105.2,
    low = 99.8,
    close = 102.3,
    volume = 1000000,
    amount = 102300000
}
local write_success = engine:put_stock_data("000001", os.time(), stock_data, "SH")
assert_true(write_success, "写入股票数据成功")

-- 测试4: 写入指标数据
print("\n--- 测试4: 写入指标数据 ---")
local metric_success = engine:put_metric_data("cpu.usage", os.time(), 75.5, {host = "server1", region = "east"})
assert_true(metric_success, "写入指标数据成功")

-- 测试5: 获取统计信息
print("\n--- 测试5: 获取统计信息 ---")
local stats = engine:get_stats()
assert_true(stats ~= nil, "获取统计信息成功")
assert_true(stats.is_initialized == true, "引擎已初始化")
print("  节点ID: " .. tostring(stats.node_id or "N/A"))
print("  集群启用: " .. tostring(stats.cluster_enabled or false))

-- 测试6: 关闭引擎
print("\n--- 测试6: 关闭引擎 ---")
local close_success = engine:close()
assert_true(close_success, "集成引擎关闭成功")

-- 测试结果汇总
print("\n=== 测试结果汇总 ===")
print(string.format("通过: %d", test_results.passed))
print(string.format("失败: %d", test_results.failed))
print(string.format("成功率: %.1f%%", (test_results.passed / (test_results.passed + test_results.failed)) * 100))

if test_results.failed == 0 then
    print("\n🎉 所有集成版本测试通过！")
    os.exit(0)
else
    print("\n⚠ 部分测试失败")
    os.exit(1)
end
