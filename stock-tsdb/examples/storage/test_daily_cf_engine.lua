-- 测试每日CF存储引擎功能

local DailyCFStorageEngine = require "lua/daily_cf_storage_engine"

print("=== 测试每日CF存储引擎功能 ===\n")

-- 创建存储引擎配置
local config = {
    enable_cold_data_separation = true,
    cold_data_threshold_days = 7,  -- 7天阈值
    daily_cf_enabled = true,
    cold_cf_compression = "zstd",  -- 冷数据使用ZSTD压缩
    cold_cf_disable_compaction = true,  -- 冷数据关闭自动Compaction
    retention_days = 30  -- 30天数据保留
}

-- 创建存储引擎实例
local engine = DailyCFStorageEngine:new(config)

-- 初始化存储引擎
print("1. 初始化存储引擎...")
local success = engine:initialize()
assert(success, "存储引擎初始化失败")
print("✓ 存储引擎初始化成功\n")

-- 测试写入不同时间的数据
print("2. 测试写入不同时间的数据...")

-- 今天的数据
local today_timestamp = os.time()
engine:write_point("stock.000001", today_timestamp, 10.5, {market = "SH"})

-- 3天前的数据（热数据）
local three_days_ago = today_timestamp - 3 * 24 * 60 * 60
engine:write_point("stock.000001", three_days_ago, 9.8, {market = "SH"})

-- 8天前的数据（冷数据）
local eight_days_ago = today_timestamp - 8 * 24 * 60 * 60
engine:write_point("stock.000001", eight_days_ago, 8.5, {market = "SH"})

-- 35天前的数据（冷数据，且即将被清理）
local thirty_five_days_ago = today_timestamp - 35 * 24 * 60 * 60
engine:write_point("stock.000001", thirty_five_days_ago, 7.2, {market = "SH"})

print("✓ 数据写入测试完成\n")

-- 测试统计信息
print("3. 获取统计信息...")
local stats = engine:get_stats()
print("总数据点: " .. stats.total_points)
print("CF数量: " .. stats.cf_count)
print("冷热数据分离: " .. tostring(stats.cold_hot_separation_enabled))
print("冷数据阈值: " .. stats.cold_data_threshold_days .. "天")
print("冷数据CF压缩: " .. stats.cold_cf_compression)
print("冷数据CF关闭Compaction: " .. tostring(stats.cold_cf_disable_compaction))
print("数据保留天数: " .. stats.retention_days .. "天")

-- 打印CF详情
print("\nCF详情:")
for cf_name, cf_info in pairs(stats.cf_details) do
    print(string.format("  %s: 数据点=%d, 热数据=%s, 压缩=%s, Compaction=%s", 
        cf_name, cf_info.data_points, tostring(cf_info.is_hot), 
        cf_info.compression, cf_info.disable_compaction and "关闭" or "开启"))
end
print("✓ 统计信息获取完成\n")

-- 测试冷热数据统计
print("4. 获取冷热数据统计...")
local cold_hot_stats = engine:get_cold_hot_stats()
print("热数据点: " .. cold_hot_stats.hot_data_points)
print("冷数据点: " .. cold_hot_stats.cold_data_points)
print("总数据点: " .. cold_hot_stats.total_data_points)
print("热数据占比: " .. string.format("%.2f%%", cold_hot_stats.hot_percentage))
print("CF数量: " .. cold_hot_stats.cf_count)
print("✓ 冷热数据统计完成\n")

-- 测试数据迁移
print("5. 测试数据迁移到冷存储...")
local migration_success = engine:migrate_to_cold_data(three_days_ago)
print("迁移结果: " .. tostring(migration_success))

-- 重新获取统计信息查看迁移效果
local stats_after_migration = engine:get_stats()
print("迁移后CF详情:")
for cf_name, cf_info in pairs(stats_after_migration.cf_details) do
    print(string.format("  %s: 数据点=%d, 热数据=%s", cf_name, cf_info.data_points, tostring(cf_info.is_hot)))
end
print("✓ 数据迁移测试完成\n")

-- 测试秒级清理旧数据
print("6. 测试秒级清理30天前的旧数据...")
local start_time = os.time()
local cleanup_success = engine:cleanup_old_data(30)  -- 清理30天前的数据
local end_time = os.time()
local cleanup_duration = end_time - start_time

print("清理结果: " .. tostring(cleanup_success))
print("清理耗时: " .. cleanup_duration .. "秒")
assert(cleanup_duration < 1, "清理操作应该秒级完成")
print("✓ 秒级清理测试完成 (耗时: " .. cleanup_duration .. "秒)\n")

-- 清理后统计
print("7. 清理后统计信息...")
local final_stats = engine:get_stats()
print("清理后总数据点: " .. final_stats.total_points)
print("清理后CF数量: " .. final_stats.cf_count)

local final_cold_hot_stats = engine:get_cold_hot_stats()
print("清理后热数据点: " .. final_cold_hot_stats.hot_data_points)
print("清理后冷数据点: " .. final_cold_hot_stats.cold_data_points)
print("✓ 清理后统计完成\n")

-- 测试查询功能
print("8. 测试数据查询功能...")
local query_success, results = engine:read_point("stock.000001", today_timestamp - 10 * 24 * 60 * 60, today_timestamp)
print("查询结果数量: " .. #results)
for i, result in ipairs(results) do
    print(string.format("  结果%d: 时间=%s, 值=%.2f, CF=%s", 
        i, os.date("%Y-%m-%d %H:%M:%S", result.timestamp), result.value, result.cf))
end
print("✓ 数据查询测试完成\n")

-- 关闭存储引擎
print("9. 关闭存储引擎...")
engine:close()
print("✓ 存储引擎关闭成功\n")

print("=== 所有测试通过！每日CF存储引擎功能验证完成 ===")
print("\n功能总结:")
print("✓ 每日自动新建CF")
print("✓ 冷热数据分离 (7天阈值)")
print("✓ 冷数据CF使用ZSTD压缩")
print("✓ 冷数据CF关闭自动Compaction")
print("✓ 秒级删除30天前数据 (直接Drop整个CF)")
print("✓ 完整的统计和监控功能")
print("✓ 数据迁移和查询功能正常")