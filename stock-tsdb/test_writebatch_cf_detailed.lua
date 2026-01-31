#!/usr/bin/env luajit

-- 详细的WriteBatch列族操作测试
local ffi = require "ffi"
local rocksdb_ffi = require "lua.rocksdb_ffi"

-- 检查FFI是否可用
if not rocksdb_ffi.is_available() then
    print("RocksDB FFI不可用: " .. rocksdb_ffi.get_load_error())
    os.exit(1)
end

print("=== 详细WriteBatch列族测试 ===")

-- 创建选项
local options = rocksdb_ffi.create_options()
local write_options = rocksdb_ffi.create_write_options()
local read_options = rocksdb_ffi.create_read_options()

-- 设置选项
rocksdb_ffi.set_create_if_missing(options, true)
rocksdb_ffi.set_create_missing_column_families(options, true)

-- 数据库路径
local db_path = "/tmp/test_rocksdb_cf_detailed"

-- 列族配置
local cf_names = ffi.new("const char*[2]")
cf_names[0] = "default"
cf_names[1] = "time_dimension"

local cf_options = ffi.new("const rocksdb_options_t*[2]")
cf_options[0] = options  -- 默认列族使用相同选项
cf_options[1] = options  -- time_dimension列族使用相同选项

local cf_handles = ffi.new("rocksdb_column_family_handle_t*[2]")

-- 错误处理
local errptr = ffi.new("char*[1]")

print("1. 打开数据库并创建列族...")

-- 尝试打开已存在的数据库，如果不存在则创建
local db, cfs = rocksdb_ffi.open_with_column_families(
    options, 
    db_path, 
    {"default", "time_dimension"}, 
    {}
)

if not db then
    print("打开数据库失败")
    os.exit(1)
end

print("数据库打开成功")

print("列族句柄:")
print("  default: " .. tostring(cfs.default or "nil"))
print("  time_dimension: " .. tostring(cfs.time_dimension or "nil"))

-- 创建WriteBatch
print("\n2. 创建WriteBatch...")
local batch = rocksdb_ffi.create_writebatch()
print("WriteBatch创建成功: " .. tostring(batch))

-- 测试1: 普通put操作
print("\n3. 测试普通put操作...")
rocksdb_ffi.writebatch_put(batch, "test_key", "test_value")
print("普通put成功")

-- 测试2: 列族put操作 - 使用正确的参数顺序
print("\n4. 测试列族put操作...")
print("调用 writebatch_put_cf(batch, cf_handle, key, value)...")

-- 正确的参数顺序: batch, cf_handle, key, value
local success, err = pcall(function()
    rocksdb_ffi.writebatch_put_cf(batch, cfs.time_dimension, "time_key_1", "time_value_1")
end)

if success then
    print("列族put操作成功")
else
    print("列族put操作失败: " .. err)
end

-- 测试3: 执行批处理
print("\n5. 执行批处理...")
success, err = pcall(function()
    rocksdb_ffi.write_batch(db, write_options, batch)
end)

if success then
    print("批处理执行成功")
else
    print("批处理执行失败: " .. err)
end

-- 测试4: 验证数据写入
print("\n6. 验证数据写入...")
success, err = pcall(function()
    local value1 = rocksdb_ffi.get(db, read_options, "test_key")
    print("普通键值: " .. (value1 or "nil"))
    
    -- 使用列族get - 使用原始的C函数调用
    local key_ptr = ffi.cast("const char*", "time_key_1")
    local vallen = ffi.new("size_t[1]")
    local errptr = ffi.new("char*[1]")
    local value_ptr = rocksdb_ffi.get_library().rocksdb_get_cf(db, read_options, cfs.time_dimension, key_ptr, #"time_key_1", vallen, errptr)
    
    if value_ptr ~= nil then
        local value2 = ffi.string(value_ptr, vallen[0])
        print("列族键值: " .. value2)
        rocksdb_ffi.get_library().rocksdb_free(value_ptr)
    else
        print("列族键值: nil")
    end
end)

if success then
    print("数据验证成功")
else
    print("数据验证失败: " .. err)
end

-- 清理资源
print("\n7. 清理资源...")

-- WriteBatch会自动销毁，不需要手动处理
print("WriteBatch将通过垃圾回收自动销毁")

-- 关闭列族句柄（FFI会自动处理）
print("列族句柄将由FFI自动清理")

-- 关闭数据库
print("关闭数据库...")
rocksdb_ffi.close_database(db)

-- 销毁选项
print("销毁选项...")
rocksdb_ffi.destroy_options(options)
rocksdb_ffi.destroy_write_options(write_options)
rocksdb_ffi.destroy_read_options(read_options)

print("\n=== 测试完成 ===")