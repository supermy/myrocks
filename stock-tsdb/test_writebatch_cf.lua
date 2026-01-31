-- 测试WriteBatch的列族操作
local ffi = require "ffi"
local rocksdb_ffi = require "lua.rocksdb_ffi"

print("测试WriteBatch列族操作...")

-- 检查RocksDB是否可用
if not rocksdb_ffi.is_available() then
    print("❌ RocksDB不可用: " .. tostring(rocksdb_ffi.get_load_error()))
    return
end

print("✅ RocksDB可用")

-- 创建选项
local options, err = rocksdb_ffi.create_options()
if not options then
    print("❌ 创建选项失败: " .. tostring(err))
    return
end

-- 设置基本选项
rocksdb_ffi.set_create_if_missing(options, true)
rocksdb_ffi.set_create_missing_column_families(options, true)

-- 创建写选项和读选项
local write_options = rocksdb_ffi.create_write_options()
local read_options = rocksdb_ffi.create_read_options()

print("✅ 选项创建成功")

-- 创建WriteBatch
local batch = rocksdb_ffi.create_writebatch()
print("✅ WriteBatch创建成功")

-- 测试基本的put操作（不带列族）
print("测试基本put操作...")
rocksdb_ffi.writebatch_put(batch, "test_key", "test_value")
print("✅ 基本put操作成功")

-- 测试列族相关的操作
print("测试列族操作需要数据库句柄和列族句柄...")

-- 创建临时数据库进行测试
local test_db_path = "/tmp/test_writebatch_cf"
os.execute("rm -rf " .. test_db_path)

-- 获取RocksDB库
local rocksdb_lib = rocksdb_ffi.get_library()

-- 定义列族名称
local cf_names = ffi.new("const char*[2]")
cf_names[0] = "default"
cf_names[1] = "test_cf"

-- 创建列族选项数组（使用相同选项）
local cf_options = ffi.new("const rocksdb_options_t*[2]")
cf_options[0] = options
cf_options[1] = options

-- 创建列族句柄数组
local cf_handles = ffi.new("rocksdb_column_family_handle_t*[2]")

-- 打开多CF数据库
local errptr = ffi.new("char*[1]")
local db = rocksdb_lib.rocksdb_open_column_families(options, test_db_path, 2, cf_names, cf_options, cf_handles, errptr)

if errptr[0] ~= nil then
    local error_msg = ffi.string(errptr[0])
    rocksdb_lib.rocksdb_free(errptr[0])
    print("❌ 打开数据库失败: " .. error_msg)
    return
end

print("✅ 多CF数据库打开成功")
print("列族句柄1: " .. tostring(cf_handles[0]))
print("列族句柄2: " .. tostring(cf_handles[1]))

-- 测试列族put操作
print("测试列族put操作...")
pcall(function()
    rocksdb_ffi.writebatch_put_cf(batch, cf_handles[1], "cf_test_key", "cf_test_value")
    print("✅ 列族put操作成功")
end)

-- 执行批处理
print("执行WriteBatch...")
local success, err = rocksdb_ffi.write_batch(db, write_options, batch)
if success then
    print("✅ WriteBatch执行成功")
else
    print("❌ WriteBatch执行失败: " .. tostring(err))
end

-- 清理
print("清理资源...")
rocksdb_lib.rocksdb_close(db)
rocksdb_lib.rocksdb_column_family_handle_destroy(cf_handles[1])
os.execute("rm -rf " .. test_db_path)

print("测试完成")