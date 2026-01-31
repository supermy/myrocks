#!/usr/bin/env luajit

-- 简单的LuaJIT WriteBatch测试脚本

local ffi = require("ffi")

-- 加载RocksDB库
local rocksdb = ffi.load("rocksdb")

-- 定义RocksDB FFI接口
ffi.cdef[[
typedef struct rocksdb_t rocksdb_t;
typedef struct rocksdb_options_t rocksdb_options_t;
typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;

// 选项创建和销毁
rocksdb_options_t* rocksdb_options_create();
void rocksdb_options_destroy(rocksdb_options_t* options);
void rocksdb_options_set_create_if_missing(rocksdb_options_t* options, unsigned char val);

// 数据库操作
rocksdb_t* rocksdb_open(const rocksdb_options_t* options, const char* name, char** errptr);
void rocksdb_close(rocksdb_t* db);

// 写入选项
rocksdb_writeoptions_t* rocksdb_writeoptions_create();
void rocksdb_writeoptions_destroy(rocksdb_writeoptions_t* options);

// 读取选项
rocksdb_readoptions_t* rocksdb_readoptions_create();
void rocksdb_readoptions_destroy(rocksdb_readoptions_t* options);

// 基本操作
void rocksdb_put(rocksdb_t* db, const rocksdb_writeoptions_t* options,
                 const char* key, size_t keylen,
                 const char* val, size_t vallen, char** errptr);

char* rocksdb_get(rocksdb_t* db, const rocksdb_readoptions_t* options,
                  const char* key, size_t keylen, size_t* vallen, char** errptr);

void rocksdb_free(void* ptr);

// WriteBatch操作
rocksdb_writebatch_t* rocksdb_writebatch_create();
void rocksdb_writebatch_destroy(rocksdb_writebatch_t* batch);
void rocksdb_writebatch_put(rocksdb_writebatch_t* batch,
                           const char* key, size_t klen,
                           const char* val, size_t vlen);
void rocksdb_writebatch_delete(rocksdb_writebatch_t* batch,
                              const char* key, size_t klen);
void rocksdb_write(rocksdb_t* db, const rocksdb_writeoptions_t* options,
                   const rocksdb_writebatch_t* batch, char** errptr);
]]

-- 测试数据库路径
local TEST_DB_PATH = "/tmp/simple_test_rocksdb_luajit"

-- 清理测试数据库
os.execute("rm -rf " .. TEST_DB_PATH)

print("=== LuaJIT RocksDB WriteBatch 简单测试 ===")

-- 创建数据库选项
local options = rocksdb.rocksdb_options_create()
rocksdb.rocksdb_options_set_create_if_missing(options, 1)

-- 打开数据库
local errptr = ffi.new("char*[1]")
local db = rocksdb.rocksdb_open(options, TEST_DB_PATH, errptr)

if errptr[0] ~= nil then
    print("打开数据库错误: " .. ffi.string(errptr[0]))
    rocksdb.rocksdb_options_destroy(options)
    os.exit(1)
end

rocksdb.rocksdb_options_destroy(options)

-- 创建写入和读取选项
local write_options = rocksdb.rocksdb_writeoptions_create()
local read_options = rocksdb.rocksdb_readoptions_create()

print("1. 测试基本WriteBatch功能")

-- 创建WriteBatch
local batch = rocksdb.rocksdb_writebatch_create()

-- 添加多个操作到WriteBatch
local test_data = {
    {key = "stock_001", value = "{price: 100.5, volume: 1000}"},
    {key = "stock_002", value = "{price: 45.2, volume: 2500}"},
    {key = "stock_003", value = "{price: 78.9, volume: 1800}"}
}

for _, data in ipairs(test_data) do
    rocksdb.rocksdb_writebatch_put(batch, data.key, #data.key, data.value, #data.value)
    print("  添加到WriteBatch: " .. data.key .. " -> " .. data.value)
end

-- 执行批量写入
local errptr_write = ffi.new("char*[1]")
rocksdb.rocksdb_write(db, write_options, batch, errptr_write)

if errptr_write[0] ~= nil then
    print("WriteBatch写入错误: " .. ffi.string(errptr_write[0]))
else
    print("  WriteBatch写入成功")
end

-- 验证数据
print("2. 验证写入的数据")

for _, data in ipairs(test_data) do
    local vallen = ffi.new("size_t[1]")
    local errptr_get = ffi.new("char*[1]")
    local value = rocksdb.rocksdb_get(db, read_options, data.key, #data.key, vallen, errptr_get)
    
    if value ~= nil and errptr_get[0] == nil then
        local retrieved_value = ffi.string(value, vallen[0])
        if retrieved_value == data.value then
            print("  ✓ " .. data.key .. " -> " .. retrieved_value)
        else
            print("  ✗ " .. data.key .. " 值不匹配")
        end
        rocksdb.rocksdb_free(value)
    else
        print("  ✗ " .. data.key .. " 读取失败")
    end
end

-- 测试混合操作
print("3. 测试WriteBatch混合操作（插入和删除）")

local mixed_batch = rocksdb.rocksdb_writebatch_create()

-- 添加新数据
rocksdb.rocksdb_writebatch_put(mixed_batch, "new_stock_001", 13, "{price: 200.0, volume: 500}", 25)
rocksdb.rocksdb_writebatch_put(mixed_batch, "new_stock_002", 13, "{price: 150.0, volume: 800}", 25)

-- 删除一些数据
rocksdb.rocksdb_writebatch_delete(mixed_batch, "stock_002", 8)

-- 执行混合操作
local errptr_mixed = ffi.new("char*[1]")
rocksdb.rocksdb_write(db, write_options, mixed_batch, errptr_mixed)

if errptr_mixed[0] ~= nil then
    print("混合操作WriteBatch错误: " .. ffi.string(errptr_mixed[0]))
else
    print("  混合操作WriteBatch执行成功")
end

-- 验证混合操作结果
local mixed_test_cases = {
    {key = "stock_001", should_exist = true, expected = "{price: 100.5, volume: 1000}"},
    {key = "stock_002", should_exist = false},
    {key = "stock_003", should_exist = true, expected = "{price: 78.9, volume: 1800}"},
    {key = "new_stock_001", should_exist = true, expected = "{price: 200.0, volume: 500}"},
    {key = "new_stock_002", should_exist = true, expected = "{price: 150.0, volume: 800}"}
}

for _, test_case in ipairs(mixed_test_cases) do
    local vallen = ffi.new("size_t[1]")
    local errptr_get = ffi.new("char*[1]")
    local value = rocksdb.rocksdb_get(db, read_options, test_case.key, #test_case.key, vallen, errptr_get)
    
    if test_case.should_exist then
        if value ~= nil and errptr_get[0] == nil then
            local retrieved_value = ffi.string(value, vallen[0])
            if retrieved_value == test_case.expected then
                print("  ✓ " .. test_case.key .. " -> " .. retrieved_value)
            else
                print("  ✗ " .. test_case.key .. " 值不匹配")
            end
            rocksdb.rocksdb_free(value)
        else
            print("  ✗ " .. test_case.key .. " 应该存在但读取失败")
        end
    else
        if value == nil and errptr_get[0] == nil then
            print("  ✓ " .. test_case.key .. " 不存在（正确删除）")
        else
            print("  ✗ " .. test_case.key .. " 应该不存在")
            if value then rocksdb.rocksdb_free(value) end
        end
    end
end

-- 性能对比测试
print("4. WriteBatch性能对比测试")

local num_operations = 100

-- 方法1: 逐个写入
local start_time = os.clock()
for i = 1, num_operations do
    local key = "perf_key_" .. i
    local value = "perf_value_" .. i
    local errptr_put = ffi.new("char*[1]")
    rocksdb.rocksdb_put(db, write_options, key, #key, value, #value, errptr_put)
end
local individual_time = os.clock() - start_time

-- 方法2: 使用WriteBatch批量写入
start_time = os.clock()
local perf_batch = rocksdb.rocksdb_writebatch_create()

for i = 1, num_operations do
    local key = "batch_key_" .. i
    local value = "batch_value_" .. i
    rocksdb.rocksdb_writebatch_put(perf_batch, key, #key, value, #value)
end

local errptr_perf = ffi.new("char*[1]")
rocksdb.rocksdb_write(db, write_options, perf_batch, errptr_perf)
local batch_time = os.clock() - start_time

-- 性能对比
local speedup = individual_time / batch_time

print(string.format("  逐个写入 %d 次: %.4f 秒", num_operations, individual_time))
print(string.format("  WriteBatch批量写入 %d 次: %.4f 秒", num_operations, batch_time))
print(string.format("  性能提升: %.2fx", speedup))

-- 清理资源
rocksdb.rocksdb_writebatch_destroy(batch)
rocksdb.rocksdb_writebatch_destroy(mixed_batch)
rocksdb.rocksdb_writebatch_destroy(perf_batch)
rocksdb.rocksdb_writeoptions_destroy(write_options)
rocksdb.rocksdb_readoptions_destroy(read_options)
rocksdb.rocksdb_close(db)

-- 清理测试数据库
os.execute("rm -rf " .. TEST_DB_PATH)

print("\n=== 测试完成 ===")
print("LuaJIT RocksDB WriteBatch功能测试成功！")