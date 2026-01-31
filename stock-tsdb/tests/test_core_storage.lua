#!/usr/bin/env luajit
-- 核心存储引擎测试 - 验证 RocksDB 版本和集成版本的基本功能

package.path = package.path .. ";./?.lua;./lua/?.lua"

local V3StorageEngineRocksDB = require("lua.tsdb_storage_engine_v3_rocksdb")

print("=== 核心存储引擎测试 ===")
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

-- 测试1: 创建存储引擎
print("--- 测试1: 创建存储引擎 ---")
local engine = V3StorageEngineRocksDB:new({
    data_dir = "./test_core_storage_data",
    batch_size = 100,
    enable_cold_data_separation = true,
    cold_data_threshold_days = 30
})
assert_true(engine ~= nil, "存储引擎创建成功")

-- 测试2: 初始化
print("\n--- 测试2: 初始化 ---")
local init_success = engine:initialize()
assert_true(init_success, "存储引擎初始化成功")

-- 测试3: 写入数据点
print("\n--- 测试3: 写入数据点 ---")
local write_success = true
for i = 1, 10 do
    local success = engine:write_point("TEST_METRIC", os.time() + i, 100 + i, {tag1 = "value" .. i})
    if not success then
        write_success = false
        break
    end
end
assert_true(write_success, "写入10个数据点成功")

-- 测试4: 批量写入
print("\n--- 测试4: 批量写入 ---")
local batch_points = {}
for i = 1, 5 do
    table.insert(batch_points, {
        metric = "BATCH_METRIC",
        timestamp = os.time() + i,
        value = 200 + i,
        tags = {batch = "true"}
    })
end
local batch_success = engine:batch_write(batch_points)
assert_true(batch_success == 5, "批量写入5个数据点成功")

-- 测试5: 获取统计信息
print("\n--- 测试5: 获取统计信息 ---")
local stats = engine:get_stats()
assert_true(stats ~= nil, "获取统计信息成功")
assert_true(stats.is_initialized == true, "引擎已初始化")
print("  数据点数: " .. tostring(stats.data_points or 0))
print("  写入次数: " .. tostring(stats.stats and stats.stats.writes or 0))

-- 测试6: 编码方法
print("\n--- 测试6: 编码方法 ---")
local row_key, qualifier = engine:encode_metric_key("cpu.usage", os.time(), {host = "server1"})
assert_true(row_key ~= nil and qualifier ~= nil, "RowKey编码成功")
print("  RowKey: " .. tostring(row_key))
print("  Qualifier: " .. tostring(qualifier))

-- 测试7: 冷热数据分离
print("\n--- 测试7: 冷热数据分离 ---")
local today_cf = engine:get_cf_name_for_timestamp(os.time())
local old_cf = engine:get_cf_name_for_timestamp(os.time() - 40 * 24 * 60 * 60)
assert_true(string.find(today_cf, "cf_") ~= nil, "热数据CF命名正确: " .. today_cf)
assert_true(string.find(old_cf, "cold_") ~= nil, "冷数据CF命名正确: " .. old_cf)

-- 测试8: 关闭引擎
print("\n--- 测试8: 关闭引擎 ---")
local close_success = engine:close()
assert_true(close_success, "存储引擎关闭成功")

-- 测试结果汇总
print("\n=== 测试结果汇总 ===")
print(string.format("通过: %d", test_results.passed))
print(string.format("失败: %d", test_results.failed))
print(string.format("成功率: %.1f%%", (test_results.passed / (test_results.passed + test_results.failed)) * 100))

if test_results.failed == 0 then
    print("\n🎉 所有核心测试通过！")
    os.exit(0)
else
    print("\n⚠ 部分测试失败")
    os.exit(1)
end
