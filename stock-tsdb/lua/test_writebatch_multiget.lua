#!/usr/bin/env luajit

-- 测试WriteBatch和MultiGet功能
print("=== RocksDB WriteBatch和MultiGet功能测试 ===")

-- 检查RocksDB是否可用
local rocksdb_available = pcall(require, "rocksdb_ffi")
if not rocksdb_available then
    print("RocksDB不可用，跳过测试")
    return
end

local RocksDBFFI = require("rocksdb_ffi")

-- 创建测试数据库路径
local test_db_path = "./test_batch_db"

-- 清理之前的测试数据
os.execute("rm -rf " .. test_db_path)

-- 创建数据库选项
local options = RocksDBFFI.create_options()
RocksDBFFI.set_create_if_missing(options, true)

-- 打开数据库
local db, err = RocksDBFFI.open_database(options, test_db_path)
if not db then
    print("打开数据库失败:", err)
    return
end

print("数据库打开成功")

-- 创建写选项和读选项
local write_options = RocksDBFFI.create_write_options()
local read_options = RocksDBFFI.create_read_options()

-- 测试1: 基本WriteBatch功能
print("\n--- 测试1: WriteBatch基本功能 ---")

-- 创建WriteBatch
local batch = RocksDBFFI.create_writebatch()

-- 添加多个put操作
RocksDBFFI.writebatch_put(batch, "batch_key1", "batch_value1")
RocksDBFFI.writebatch_put(batch, "batch_key2", "batch_value2")
RocksDBFFI.writebatch_put(batch, "batch_key3", "batch_value3")

-- 添加delete操作
RocksDBFFI.writebatch_delete(batch, "batch_key2")  -- 删除key2

-- 执行批量写入
local success, err = RocksDBFFI.write_batch(db, write_options, batch)
if not success then
    print("WriteBatch执行失败:", err)
else
    print("WriteBatch执行成功")
end

-- 验证写入结果
local value1 = RocksDBFFI.get(db, read_options, "batch_key1")
local value2 = RocksDBFFI.get(db, read_options, "batch_key2")
local value3 = RocksDBFFI.get(db, read_options, "batch_key3")

print("batch_key1:", value1 or "不存在")
print("batch_key2:", value2 or "不存在")  -- 应该不存在（被删除）
print("batch_key3:", value3 or "不存在")

-- 测试2: MultiGet功能
print("\n--- 测试2: MultiGet批量读取 ---")

-- 先写入一些测试数据
RocksDBFFI.put(db, write_options, "multi_key1", "multi_value1")
RocksDBFFI.put(db, write_options, "multi_key2", "multi_value2")
RocksDBFFI.put(db, write_options, "multi_key3", "multi_value3")

-- 准备要查询的键列表
local keys_to_query = {
    "multi_key1",      -- 存在
    "multi_key2",      -- 存在
    "multi_key3",      -- 存在
    "non_existent_key", -- 不存在
    "batch_key1"       -- 存在（来自WriteBatch测试）
}

-- 执行MultiGet
local results = RocksDBFFI.multi_get(db, read_options, keys_to_query)

print("MultiGet结果:")
for i, key in ipairs(keys_to_query) do
    local result = results[i]
    if type(result) == "table" and result.error then
        print(string.format("  %s: 错误 - %s", key, result.error))
    elseif result == nil then
        print(string.format("  %s: 不存在", key))
    else
        print(string.format("  %s: %s", key, result))
    end
end

-- 测试3: WriteBatch性能对比
print("\n--- 测试3: WriteBatch性能对比 ---")

local num_operations = 1000

-- 方法1: 逐个写入（基准测试）
local start_time = os.clock()
for i = 1, num_operations do
    local key = "single_key_" .. i
    local value = "single_value_" .. i
    RocksDBFFI.put(db, write_options, key, value)
end
local single_time = os.clock() - start_time

-- 方法2: 使用WriteBatch批量写入
start_time = os.clock()
local performance_batch = RocksDBFFI.create_writebatch()
for i = 1, num_operations do
    local key = "batch_key_" .. i
    local value = "batch_value_" .. i
    RocksDBFFI.writebatch_put(performance_batch, key, value)
end
RocksDBFFI.write_batch(db, write_options, performance_batch)
local batch_time = os.clock() - start_time

print(string.format("逐个写入 %d 次耗时: %.3f 秒", num_operations, single_time))
print(string.format("WriteBatch批量写入 %d 次耗时: %.3f 秒", num_operations, batch_time))
print(string.format("性能提升: %.2f 倍", single_time / batch_time))

-- 测试4: WriteBatch清空和重用
print("\n--- 测试4: WriteBatch清空和重用 ---")

local reusable_batch = RocksDBFFI.create_writebatch()

-- 第一次使用
RocksDBFFI.writebatch_put(reusable_batch, "reuse_key1", "reuse_value1")
RocksDBFFI.write_batch(db, write_options, reusable_batch)

-- 清空后重用
RocksDBFFI.writebatch_clear(reusable_batch)
RocksDBFFI.writebatch_put(reusable_batch, "reuse_key2", "reuse_value2")
RocksDBFFI.write_batch(db, write_options, reusable_batch)

-- 验证重用结果
local reuse_val1 = RocksDBFFI.get(db, read_options, "reuse_key1")
local reuse_val2 = RocksDBFFI.get(db, read_options, "reuse_key2")

print("reuse_key1:", reuse_val1 or "不存在")
print("reuse_key2:", reuse_val2 or "不存在")

-- 清理资源
RocksDBFFI.close_database(db)
RocksDBFFI.destroy_options(options)
RocksDBFFI.destroy_write_options(write_options)
RocksDBFFI.destroy_read_options(read_options)

print("\n=== 测试完成 ===")
print("测试数据库路径:", test_db_path)
print("可以手动检查数据库文件: ls -la", test_db_path)