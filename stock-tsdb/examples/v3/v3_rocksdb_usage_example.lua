-- V3存储引擎RocksDB落盘功能使用示例
print("=== V3存储引擎RocksDB落盘功能使用示例 ===")

-- 加载V3存储引擎RocksDB版本
local V3StorageEngineRocksDB = require("lua.tsdb_storage_engine_v3_rocksdb")

-- 示例1: 基础配置和使用
print("\n--- 示例1: 基础配置和使用 ---")

local config_basic = {
    use_rocksdb = true,
    data_dir = "./v3_data_basic",
    batch_size = 500,
    enable_cold_data_separation = false,
    rocksdb_options = {
        write_buffer_size = 32 * 1024 * 1024,  -- 32MB
        max_write_buffer_number = 3,
        compression = 4,  -- LZ4压缩
        create_if_missing = true
    }
}

local engine_basic = V3StorageEngineRocksDB:new(config_basic)
engine_basic:initialize()

-- 写入一些基础数据
for i = 1, 100 do
    engine_basic:write_point("basic.metric", os.time() + i, math.random() * 100, {
        host = "server-" .. math.random(1, 10),
        region = "us-east"
    })
end

print("基础配置示例完成，写入100个数据点")

-- 示例2: 高级配置（冷热数据分离）
print("\n--- 示例2: 高级配置（冷热数据分离） ---")

local config_advanced = {
    use_rocksdb = true,
    data_dir = "./v3_data_advanced",
    batch_size = 1000,
    enable_cold_data_separation = true,
    cold_data_threshold_days = 7,  -- 7天前的数据视为冷数据
    rocksdb_options = {
        write_buffer_size = 64 * 1024 * 1024,  -- 64MB
        max_write_buffer_number = 4,
        compression = 2,  -- Snappy压缩
        create_if_missing = true
    }
}

local engine_advanced = V3StorageEngineRocksDB:new(config_advanced)
engine_advanced:initialize()

-- 写入不同时间范围的数据
local current_time = os.time()

-- 写入热数据（最近7天）
for i = 1, 50 do
    engine_advanced:write_point("hot.metric", current_time - i * 3600, math.random() * 80 + 20, {
        host = "hot-server",
        data_type = "hot"
    })
end

-- 写入冷数据（7天前）
for i = 1, 30 do
    engine_advanced:write_point("cold.metric", current_time - (7 + i) * 86400, math.random() * 50, {
        host = "cold-server", 
        data_type = "cold"
    })
end

print("高级配置示例完成，写入热数据50个，冷数据30个")

-- 示例3: 批量写入性能优化
print("\n--- 示例3: 批量写入性能优化 ---")

local config_performance = {
    use_rocksdb = true,
    data_dir = "./v3_data_performance",
    batch_size = 5000,  -- 更大的批量大小
    enable_cold_data_separation = true,
    cold_data_threshold_days = 30,
    rocksdb_options = {
        write_buffer_size = 128 * 1024 * 1024,  -- 128MB
        max_write_buffer_number = 6,
        compression = 4,  -- LZ4压缩
        create_if_missing = true
    }
}

local engine_performance = V3StorageEngineRocksDB:new(config_performance)
engine_performance:initialize()

-- 生成批量数据
local batch_data = {}
for i = 1, 10000 do
    table.insert(batch_data, {
        metric = "performance.metric",
        timestamp = current_time + i,
        value = math.random() * 100,
        tags = {
            host = "perf-server-" .. math.random(1, 100),
            metric_type = "gauge",
            environment = "production"
        }
    })
end

-- 批量写入
local start_time = os.clock()
local success_count = engine_performance:write_batch(batch_data)
local end_time = os.clock()

local elapsed_time = end_time - start_time
local points_per_second = success_count / elapsed_time

print("批量写入性能测试:")
print("  - 写入点数: " .. success_count)
print("  - 耗时: " .. string.format("%.3f 秒", elapsed_time))
print("  - 写入速率: " .. string.format("%.0f 点/秒", points_per_second))

-- 示例4: 数据查询和统计
print("\n--- 示例4: 数据查询和统计 ---")

-- 查询热数据
local success, hot_results = engine_advanced:read_point("hot.metric", current_time - 7 * 86400, current_time, {data_type = "hot"})
if success then
    print("热数据查询结果: " .. #hot_results .. " 个数据点")
    
    -- 计算统计信息
    local sum = 0
    local min_val = math.huge
    local max_val = -math.huge
    
    for _, data in ipairs(hot_results) do
        sum = sum + data.value
        min_val = math.min(min_val, data.value)
        max_val = math.max(max_val, data.value)
    end
    
    local avg = sum / #hot_results
    print("  平均值: " .. string.format("%.2f", avg))
    print("  最小值: " .. string.format("%.2f", min_val))
    print("  最大值: " .. string.format("%.2f", max_val))
end

-- 查询冷数据
local success, cold_results = engine_advanced:read_point("cold.metric", current_time - 30 * 86400, current_time - 7 * 86400, {data_type = "cold"})
if success then
    print("冷数据查询结果: " .. #cold_results .. " 个数据点")
end

-- 示例5: 数据备份和恢复
print("\n--- 示例5: 数据备份和恢复 ---")

-- 备份数据
local backup_dir = "./v3_backup_example_" .. os.date("%Y%m%d_%H%M%S")
local backup_success = engine_advanced:backup_data(backup_dir)

if backup_success then
    print("数据备份成功: " .. backup_dir)
    
    -- 检查备份文件
    local files = io.popen("ls -la " .. backup_dir):read("*a")
    print("备份目录内容:")
    print(files)
end

-- 示例6: 统计信息监控
print("\n--- 示例6: 统计信息监控 ---")

-- 获取所有引擎的统计信息
local engines = {engine_basic, engine_advanced, engine_performance}
local engine_names = {"基础引擎", "高级引擎", "性能引擎"}

for i, engine in ipairs(engines) do
    local stats = engine:get_stats()
    print(engine_names[i] .. "统计信息:")
    print("  - 数据点数: " .. stats.data_points)
    print("  - 内存使用: " .. string.format("%.2f MB", stats.memory_usage / 1024 / 1024))
    print("  - 总写入次数: " .. stats.stats.writes)
    print("  - RocksDB写入次数: " .. stats.stats.rocksdb_writes)
    print("  - 批量提交次数: " .. stats.stats.batch_commits)
    print("  - 冷热数据分离: " .. tostring(stats.cold_hot_separation_enabled))
end

-- 示例7: 优雅关闭
print("\n--- 示例7: 优雅关闭 ---")

-- 关闭所有引擎
for i, engine in ipairs(engines) do
    local close_success = engine:close()
    if close_success then
        print(engine_names[i] .. "关闭成功")
    else
        print(engine_names[i] .. "关闭失败")
    end
end

-- 示例8: 配置建议
print("\n--- 示例8: 配置建议 ---")

print("针对不同场景的配置建议:")
print("1. 开发测试环境:")
print("   - batch_size: 100-500")
print("   - write_buffer_size: 16-32MB")
print("   - 禁用冷热数据分离")

print("2. 生产环境（中等负载）:")
print("   - batch_size: 1000-5000")
print("   - write_buffer_size: 64-128MB")
print("   - 启用冷热数据分离（阈值7-30天）")

print("3. 生产环境（高负载）:")
print("   - batch_size: 5000-10000")
print("   - write_buffer_size: 128-256MB")
print("   - 启用冷热数据分离（阈值1-7天）")
print("   - 使用LZ4压缩算法")

-- 清理示例数据
print("\n--- 清理示例数据 ---")

os.execute("rm -rf ./v3_data_basic")
os.execute("rm -rf ./v3_data_advanced") 
os.execute("rm -rf ./v3_data_performance")
os.execute("rm -rf ./v3_backup_example_*")

print("示例数据清理完成")

print("\n=== V3存储引擎RocksDB落盘功能使用示例完成 ===")
print("✓ 展示了多种配置和使用场景")
print("✓ 实现了数据持久化和批量写入优化")
print("✓ 支持冷热数据分离和统计监控")
print("✓ 提供了生产环境配置建议")