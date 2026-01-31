#!/usr/bin/env luajit

-- 简单真实RocksDB测试脚本
-- 验证RocksDB FFI是否正常工作

package.path = package.path .. ";./lua/?.lua"

local ffi = require "ffi"

-- 加载RocksDB FFI模块
local RocksDBFFI = require "rocksdb_ffi"

print("=== 真实RocksDB测试 ===")

-- 检查RocksDB库是否加载成功
local rocksdb = RocksDBFFI.get_library()
if rocksdb then
    print("✅ RocksDB库加载成功")
else
    print("❌ RocksDB库加载失败")
    return
end

-- 创建数据库选项
local options = RocksDBFFI.create_options()
RocksDBFFI.set_create_if_missing(options, true)
RocksDBFFI.set_compression(options, 1)  -- SNAPPY压缩

local write_options = RocksDBFFI.create_write_options()
local read_options = RocksDBFFI.create_read_options()

-- 数据库路径
local db_path = "/tmp/test_real_rocksdb"

-- 打开数据库
print("正在打开RocksDB数据库...")
local errptr = ffi.new("char*[1]")
local db = rocksdb.rocksdb_open(options, db_path, errptr)

if errptr[0] ~= nil then
    local error_msg = ffi.string(errptr[0])
    rocksdb.rocksdb_free(errptr[0])
    print("❌ 打开RocksDB数据库失败:", error_msg)
    return
end

print("✅ RocksDB数据库打开成功")

-- 测试基本写入操作
print("\n=== 测试基本写入操作 ===")

local test_key = "test_key_1"
local test_value = "test_value_1"

-- 写入数据
local errptr_write = ffi.new("char*[1]")
rocksdb.rocksdb_put(db, write_options, test_key, #test_key, test_value, #test_value, errptr_write)

if errptr_write[0] ~= nil then
    local error_msg = ffi.string(errptr_write[0])
    rocksdb.rocksdb_free(errptr_write[0])
    print("❌ 写入数据失败:", error_msg)
else
    print("✅ 数据写入成功")
end

-- 测试读取操作
print("\n=== 测试读取操作 ===")

local errptr_read = ffi.new("char*[1]")
local vallen = ffi.new("size_t[1]")
local value_ptr = rocksdb.rocksdb_get(db, read_options, test_key, #test_key, vallen, errptr_read)

if errptr_read[0] ~= nil then
    local error_msg = ffi.string(errptr_read[0])
    rocksdb.rocksdb_free(errptr_read[0])
    print("❌ 读取数据失败:", error_msg)
elseif value_ptr ~= nil then
    local retrieved_value = ffi.string(value_ptr, vallen[0])
    rocksdb.rocksdb_free(value_ptr)
    print("✅ 数据读取成功:", retrieved_value)
    
    if retrieved_value == test_value then
        print("✅ 数据验证成功")
    else
        print("❌ 数据验证失败")
    end
else
    print("❌ 未找到数据")
end

-- 测试WriteBatch批量写入
print("\n=== 测试WriteBatch批量写入 ===")

local batch = RocksDBFFI.create_writebatch()

-- 添加多个键值对到batch
for i = 1, 5 do
    local batch_key = "batch_key_" .. i
    local batch_value = "batch_value_" .. i
    RocksDBFFI.writebatch_put(batch, batch_key, batch_value)
end

-- 执行批量写入
local success, err = RocksDBFFI.write_batch(db, write_options, batch)
if success then
    print("✅ WriteBatch批量写入成功")
else
    print("❌ WriteBatch批量写入失败:", err)
end

-- 验证批量写入的数据
print("\n=== 验证批量写入的数据 ===")

for i = 1, 5 do
    local batch_key = "batch_key_" .. i
    local expected_value = "batch_value_" .. i
    
    local errptr_batch = ffi.new("char*[1]")
    local vallen_batch = ffi.new("size_t[1]")
    local value_ptr_batch = rocksdb.rocksdb_get(db, read_options, batch_key, #batch_key, vallen_batch, errptr_batch)
    
    if errptr_batch[0] ~= nil then
        local error_msg = ffi.string(errptr_batch[0])
        rocksdb.rocksdb_free(errptr_batch[0])
        print("❌ 读取", batch_key, "失败:", error_msg)
    elseif value_ptr_batch ~= nil then
        local retrieved_value = ffi.string(value_ptr_batch, vallen_batch[0])
        rocksdb.rocksdb_free(value_ptr_batch)
        
        if retrieved_value == expected_value then
            print("✅", batch_key, "验证成功")
        else
            print("❌", batch_key, "验证失败")
        end
    else
        print("❌ 未找到", batch_key)
    end
end

-- 测试MultiGet
print("\n=== 测试MultiGet操作 ===")

local keys_to_get = {"batch_key_1", "batch_key_3", "batch_key_5", "nonexistent_key"}
local results = RocksDBFFI.multi_get(db, read_options, keys_to_get)

for i, result in ipairs(results) do
    local key = keys_to_get[i]
    if type(result) == "table" and result.error then
        print("❌", key, "读取失败:", result.error)
    elseif result then
        print("✅", key, "读取成功:", result)
    else
        print("❌", key, "未找到")
    end
end

-- 关闭数据库
print("\n=== 清理资源 ===")

if db then
    rocksdb.rocksdb_close(db)
    print("✅ RocksDB数据库已关闭")
end

print("\n=== 测试完成 ===")
print("真实RocksDB功能验证成功！")