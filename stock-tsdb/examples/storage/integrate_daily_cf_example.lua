-- 每日CF功能集成示例
-- 展示如何将每日CF功能集成到现有的TSDB系统中

local DailyCFStorageEngine = require "lua/daily_cf_storage_engine"

print("=== 每日CF功能集成示例 ===\n")

-- 配置示例：生产环境推荐配置
local production_config = {
    enable_cold_data_separation = true,
    cold_data_threshold_days = 7,           -- 7天冷热数据分离阈值
    daily_cf_enabled = true,                -- 启用每日CF
    cold_cf_compression = "zstd",          -- 冷数据使用ZSTD高压缩比
    cold_cf_disable_compaction = true,     -- 冷数据关闭自动Compaction
    retention_days = 90                    -- 90天数据保留
}

-- 创建生产环境存储引擎
local production_engine = DailyCFStorageEngine:new(production_config)
production_engine:initialize()

print("生产环境配置:")
print("- 冷热数据分离: 启用 (7天阈值)")
print("- 每日CF: 启用")
print("- 冷数据压缩: ZSTD (高压缩比)")
print("- 冷数据Compaction: 关闭 (避免性能抖动)")
print("- 数据保留: 90天")
print("\n")

-- 模拟生产环境数据写入
print("模拟生产环境数据写入...")

-- 模拟连续30天的数据写入
local base_time = os.time() - 30 * 24 * 60 * 60  -- 30天前
for i = 0, 30 do
    local timestamp = base_time + i * 24 * 60 * 60
    local stock_code = string.format("stock.%06d", (i % 100) + 1)  -- 模拟100只股票
    local price = 10.0 + (i % 10) * 0.1  -- 模拟价格波动
    
    production_engine:write_point(stock_code, timestamp, price, {market = "SH"})
end

print("数据写入完成\n")

-- 查看CF分布情况
local stats = production_engine:get_stats()
print("CF分布统计:")
print("总数据点: " .. stats.total_points)
print("CF数量: " .. stats.cf_count)

-- 按日期排序显示CF
local cf_list = {}
for cf_name, cf_info in pairs(stats.cf_details) do
    table.insert(cf_list, {name = cf_name, info = cf_info})
end

table.sort(cf_list, function(a, b) 
    return a.info.created_date < b.info.created_date 
end)

print("\nCF详情 (按日期排序):")
for i, cf in ipairs(cf_list) do
    local status = cf.info.is_hot and "热数据" or "冷数据"
    local compression = cf.info.compression
    local compaction = cf.info.disable_compaction and "关闭" or "开启"
    print(string.format("  %s: %s, 数据点=%d, 压缩=%s, Compaction=%s", 
        cf.name, status, cf.info.data_points, compression, compaction))
end

-- 冷热数据统计
local cold_hot_stats = production_engine:get_cold_hot_stats()
print("\n冷热数据分布:")
print("热数据点: " .. cold_hot_stats.hot_data_points .. " (最近7天)")
print("冷数据点: " .. cold_hot_stats.cold_data_points .. " (7天前)")
print("热数据占比: " .. string.format("%.1f%%", cold_hot_stats.hot_percentage))

-- 演示秒级数据清理
print("\n=== 演示秒级数据清理 ===")
print("清理30天前的旧数据...")

local start_time = os.time()
production_engine:cleanup_old_data(30)  -- 清理30天前的数据
local end_time = os.time()

print("清理完成，耗时: " .. (end_time - start_time) .. "秒")

-- 清理后统计
local stats_after_cleanup = production_engine:get_stats()
print("清理后数据点: " .. stats_after_cleanup.total_points)
print("清理后CF数量: " .. stats_after_cleanup.cf_count)

-- 查询示例
print("\n=== 数据查询示例 ===")

-- 查询最近3天的数据
local end_time_query = os.time()
local start_time_query = end_time_query - 3 * 24 * 60 * 60

local success, results = production_engine:read_point("stock.000001", start_time_query, end_time_query)
print("查询股票000001最近3天的数据: " .. #results .. " 条记录")

-- 关闭引擎
production_engine:close()

print("\n=== 集成示例完成 ===")
print("\n使用建议:")
print("1. 生产环境推荐配置:")
print("   - 冷热数据分离阈值: 7-30天")
print("   - 冷数据压缩: ZSTD (节省存储空间)")
print("   - 冷数据Compaction: 关闭 (避免性能影响)")
print("   - 数据保留: 根据业务需求设置")
print("\n2. 运维操作:")
print("   - 定期执行cleanup_old_data()清理过期数据")
print("   - 监控CF数量和大小分布")
print("   - 根据访问模式调整冷热数据阈值")
print("\n3. 性能优势:")
print("   - 秒级删除旧数据，无Compaction抖动")
print("   - 冷热数据分离，优化访问性能")
print("   - 按日分CF，便于数据管理和备份")