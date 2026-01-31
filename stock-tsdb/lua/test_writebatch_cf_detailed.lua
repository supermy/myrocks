#!/usr/bin/env luajit

-- 详细的多列族WriteBatch测试脚本
-- 用于验证WriteBatch在多列族环境下的正确性

local ffi = require("ffi")
local rocksdb_ffi = require("rocksdb_ffi")

print("=== 详细的多列族WriteBatch测试 ===")

-- 定义测试数据库路径
local test_db_path = "/tmp/test_rocksdb_writebatch_cf_detailed"

-- 清理之前的测试数据
os.execute("rm -rf " .. test_db_path)

-- 创建数据库选项
local db_options = rocksdb_ffi.create_options()
rocksdb_ffi.set_create_if_missing(db_options, true)
rocksdb_ffi.set_create_missing_column_families(db_options, true)  -- 启用自动创建缺失的列族

-- 创建读写选项
local read_options = rocksdb_ffi.create_read_options()
local write_options = rocksdb_ffi.create_write_options()

-- 列族名称列表
local cf_names = {"default", "time_dimension"}  -- 默认列族必须是第一个，名称为'default'

-- 定义列族选项映射（所有列族使用相同选项）
local cf_options_map = {
    default = db_options,  -- 默认列族
    time_dimension = db_options
}

-- 打开数据库并创建列族
print("打开数据库并创建列族...")
local db, cfs, err = rocksdb_ffi.open_with_column_families(db_options, test_db_path, cf_names, cf_options_map)

if not db then
    print("打开数据库失败: " .. (err or "未知错误"))
    os.exit(1)
end

print("数据库打开成功")
print("列族句柄:")
print("  default: " .. tostring(cfs.default))  -- 默认列族
print("  time_dimension: " .. tostring(cfs.time_dimension))

-- 创建WriteBatch
print("\n创建WriteBatch...")
local batch = rocksdb_ffi.create_writebatch()

-- 准备测试数据
local key1 = "key1"
local value1 = "value1_in_default"
local key2 = "key2"
local value2 = "value2_in_time_dimension"

print("准备测试数据:")
print("  " .. key1 .. " -> " .. value1 .. " (默认列族)")
print("  " .. key2 .. " -> " .. value2 .. " (time_dimension列族)")

-- 将数据添加到WriteBatch
print("\n将数据添加到WriteBatch...")
rocksdb_ffi.writebatch_put(batch, key1, value1)
print("  已添加: " .. key1 .. " -> " .. value1 .. " (默认列族)")

rocksdb_ffi.writebatch_put_cf(batch, cfs.time_dimension, key2, value2)
print("  已添加: " .. key2 .. " -> " .. value2 .. " (time_dimension列族)")

-- 提交WriteBatch
print("\n提交WriteBatch...")
local success, error = rocksdb_ffi.write_batch(db, write_options, batch)
if success then
    print("WriteBatch提交成功")
else
    print("WriteBatch提交失败: " .. (error or "未知错误"))
end

-- 验证数据写入
print("\n验证数据写入...")

-- 从默认列族读取
local value1_read, err = rocksdb_ffi.get_cf(db, read_options, cfs.default, key1)  -- 默认列族
if err then
    print("从默认列族读取失败: " .. err)
else
    if value1_read then
        print("从默认列族读取: " .. key1 .. " = " .. value1_read)
    else
        print("从默认列族读取: " .. key1 .. " = nil")
    end
end

-- 从time_dimension列族读取
local value2_read, err = rocksdb_ffi.get_cf(db, read_options, cfs.time_dimension, key2)
if err then
    print("从time_dimension列族读取失败: " .. err)
else
    if value2_read then
        print("从time_dimension列族读取: " .. key2 .. " = " .. value2_read)
    else
        print("从time_dimension列族读取: " .. key2 .. " = nil")
    end
end

-- 清理资源
print("\n清理资源...")

-- WriteBatch会自动销毁，不需要手动处理
print("WriteBatch会自动销毁，不需要手动处理")

-- 关闭数据库
rocksdb_ffi.close_database(db)
print("数据库已关闭")

-- 清理选项
rocksdb_ffi.destroy_read_options(read_options)
rocksdb_ffi.destroy_write_options(write_options)
rocksdb_ffi.destroy_options(db_options)

print("\n=== 测试完成 ===")