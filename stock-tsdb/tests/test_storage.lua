#!/usr/bin/env luajit

-- 添加当前目录到Lua包路径
package.path = package.path .. ";./lua/?.lua"

local storage = require "storage"

-- 测试配置
local config = {
    data_dir = "../data/test_data",
    write_buffer_size = 64 * 1024 * 1024,  -- 64MB
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,  -- 64MB
    max_bytes_for_level_base = 256 * 1024 * 1024,  -- 256MB
    compression = 4  -- lz4
}

print("创建存储引擎...")
local engine = storage.create_engine(config)

print("初始化存储引擎...")
local success, err = engine:init()
if not success then
    print("初始化失败:", err)
    return
end
print("存储引擎初始化成功")

-- 测试写入数据点
print("测试写入数据点...")
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
print("测试读取数据点...")
success, result = engine:read_point("SH000001", 1234567890, 0)
if not success then
    print("读取数据点失败:", result)
else
    print("读取数据点成功:", result.value, result.timestamp, result.quality)
end

-- 测试创建列族
print("测试创建列族...")
success, err = engine:create_column_family("test_cf")
if not success then
    print("创建列族失败:", err)
else
    print("创建列族成功")
end

-- 测试获取统计信息
print("测试获取统计信息...")
success, stats = engine:get_statistics()
if not success then
    print("获取统计信息失败:", stats)
else
    print("获取统计信息成功")
end

-- 测试关闭存储引擎
print("关闭存储引擎...")
engine:shutdown()
print("存储引擎已关闭")

print("测试完成")