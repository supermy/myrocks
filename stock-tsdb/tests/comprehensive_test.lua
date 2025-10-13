#!/usr/bin/env luajit

-- 添加当前目录到Lua包路径
package.path = package.path .. ";./lua/?.lua"

local storage = require "storage"

-- 测试配置
local config = {
    data_dir = "../data/comprehensive_test_data",
    write_buffer_size = 64 * 1024 * 1024,  -- 64MB
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,  -- 64MB
    max_bytes_for_level_base = 256 * 1024 * 1024,  -- 256MB
    compression = 4  -- lz4
}

print("=== 存储引擎综合测试 ===")

print("\n1. 创建存储引擎...")
local engine = storage.create_engine(config)

print("2. 初始化存储引擎...")
local success, err = engine:init()
if not success then
    print("初始化失败:", err)
    return
end
print("存储引擎初始化成功")

-- 测试写入单个数据点
print("\n3. 测试写入单个数据点...")
local point = {
    timestamp = 1234567890,
    value = 100.5,
    quality = 100
}

success, err = engine:write_point("SH000001", point, 0)
if not success then
    print("写入数据点失败:", err)
else
    print("写入数据点成功")
end

-- 测试读取数据点
print("\n4. 测试读取数据点...")
success, result = engine:read_point("SH000001", 1234567890, 0)
if not success then
    print("读取数据点失败:", result)
else
    print("读取数据点成功:", result.value, result.timestamp, result.quality)
end

-- 测试批量写入数据点
print("\n5. 测试批量写入数据点...")
local points = {
    {timestamp = 1234567891, value = 101.0, quality = 95},
    {timestamp = 1234567892, value = 102.5, quality = 90},
    {timestamp = 1234567893, value = 103.0, quality = 85}
}

success, err = engine:write_points("SH000001", points, 0)
if not success then
    print("批量写入数据点失败:", err)
else
    print("批量写入数据点成功")
end

-- 测试范围读取
print("\n6. 测试范围读取...")
success, results = engine:read_range("SH000001", 1234567890, 1234567893, 0)
if not success then
    print("范围读取失败:", results)
else
    print("范围读取成功，读取到", #results, "个数据点:")
    for i, point in ipairs(results) do
        print("  ", i, point.timestamp, point.value, point.quality)
    end
end

-- 测试获取最新数据点
print("\n7. 测试获取最新数据点...")
success, result = engine:get_latest_point("SH000001", 0)
if not success then
    print("获取最新数据点失败:", result)
else
    print("获取最新数据点成功:", result.timestamp, result.value, result.quality)
end

-- 测试创建列族
print("\n8. 测试创建列族...")
-- 先检查列族是否已存在
local cf_exists = false
success, result = engine:get_column_families()
if success then
    for _, cf_name in ipairs(result) do
        if cf_name == "test_cf" then
            cf_exists = true
            break
        end
    end
end

if not cf_exists then
    success, err = engine:create_column_family("test_cf")
    if not success then
        print("创建列族失败:", err)
        -- 继续执行其他测试
    else
        print("创建列族成功")
    end
else
    print("列族test_cf已存在")
end

-- 测试获取统计信息
print("\n9. 测试获取统计信息...")
success, stats = engine:get_statistics()
if not success then
    print("获取统计信息失败:", stats)
else
    print("获取统计信息成功")
end

-- 测试数据压缩
print("\n10. 测试数据压缩...")
success, err = engine:compact_data("SH000001")
if not success then
    print("数据压缩失败:", err)
else
    print("数据压缩成功")
end

-- 测试删除数据
print("\n11. 测试删除数据...")
success, count = engine:delete_data("SH000001", 1234567890, 1234567891, 0)
if not success then
    print("删除数据失败:", count)
else
    print("删除数据成功，删除了", count, "个数据点")
end

-- 测试关闭存储引擎
print("\n12. 关闭存储引擎...")
engine:shutdown()
print("存储引擎已关闭")

print("\n=== 测试完成 ===")