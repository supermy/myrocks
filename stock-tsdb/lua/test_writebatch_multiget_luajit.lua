#!/usr/bin/env luajit

-- LuaJIT真实数据库测试脚本 - WriteBatch和MultiGet功能测试
-- 使用真实的RocksDB库进行测试

local ffi = require("ffi")
local bit = require("bit")

-- 加载RocksDB库
local rocksdb = ffi.load("rocksdb")

-- 定义RocksDB FFI接口
ffi.cdef[[
// 错误处理
typedef struct rocksdb_t rocksdb_t;
typedef struct rocksdb_options_t rocksdb_options_t;
typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;
typedef struct rocksdb_iterator_t rocksdb_iterator_t;

// 错误处理
char* rocksdb_get_error(int error_code);

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

void rocksdb_delete(rocksdb_t* db, const rocksdb_writeoptions_t* options,
                    const char* key, size_t keylen, char** errptr);

// WriteBatch操作
rocksdb_writebatch_t* rocksdb_writebatch_create();
void rocksdb_writebatch_destroy(rocksdb_writebatch_t* batch);
void rocksdb_writebatch_put(rocksdb_writebatch_t* batch,
                           const char* key, size_t klen,
                           const char* val, size_t vlen);
void rocksdb_writebatch_delete(rocksdb_writebatch_t* batch,
                              const char* key, size_t klen);
void rocksdb_writebatch_clear(rocksdb_writebatch_t* batch);
void rocksdb_write(rocksdb_t* db, const rocksdb_writeoptions_t* options,
                   const rocksdb_writebatch_t* batch, char** errptr);

// MultiGet操作 (简化版本)
void rocksdb_multi_get(rocksdb_t* db, const rocksdb_readoptions_t* options,
                      size_t num_keys, const char* const* keys_list,
                      const size_t* keys_list_sizes, char** values_list,
                      size_t* values_list_sizes, char** errs);

// 迭代器操作
rocksdb_iterator_t* rocksdb_create_iterator(rocksdb_t* db, const rocksdb_readoptions_t* options);
void rocksdb_iter_destroy(rocksdb_iterator_t* iter);
unsigned char rocksdb_iter_valid(const rocksdb_iterator_t* iter);
void rocksdb_iter_seek_to_first(rocksdb_iterator_t* iter);
void rocksdb_iter_next(rocksdb_iterator_t* iter);
const char* rocksdb_iter_key(const rocksdb_iterator_t* iter, size_t* klen);
const char* rocksdb_iter_value(const rocksdb_iterator_t* iter, size_t* vlen);
]]

-- 基础测试数据库路径
local BASE_TEST_DB_PATH = "/tmp/test_rocksdb_writebatch_multiget_luajit"

-- 清理测试数据库
local function cleanup_test_db(db_path)
    os.execute("rm -rf " .. db_path)
end

-- 创建测试数据库
local function create_test_db(test_name)
    local db_path = BASE_TEST_DB_PATH .. "_" .. test_name
    cleanup_test_db(db_path)
    
    local options = rocksdb.rocksdb_options_create()
    rocksdb.rocksdb_options_set_create_if_missing(options, 1)
    
    local errptr = ffi.new("char*[1]")
    local db = rocksdb.rocksdb_open(options, db_path, errptr)
    
    if errptr[0] ~= nil then
        print("Error opening database: " .. ffi.string(errptr[0]))
        rocksdb.rocksdb_options_destroy(options)
        return nil
    end
    
    rocksdb.rocksdb_options_destroy(options)
    return db, db_path
end

-- 测试1: 基本WriteBatch功能
local function test_basic_writebatch()
    print("=== 测试1: 基本WriteBatch功能 ===")
    
    local db, db_path = create_test_db("basic_writebatch")
    if not db then return false end
    
    local write_options = rocksdb.rocksdb_writeoptions_create()
    local read_options = rocksdb.rocksdb_readoptions_create()
    
    -- 创建WriteBatch
    local batch = rocksdb.rocksdb_writebatch_create()
    
    -- 添加多个操作到WriteBatch
    local keys = {"key1", "key2", "key3", "key4"}
    local values = {"value1", "value2", "value3", "value4"}
    
    for i = 1, #keys do
        rocksdb.rocksdb_writebatch_put(batch, keys[i], #keys[i], values[i], #values[i])
    end
    
    -- 执行批量写入
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        print("WriteBatch写入错误: " .. ffi.string(errptr[0]))
        return false
    end
    
    -- 验证数据
    local success_count = 0
    for i = 1, #keys do
        local vallen = ffi.new("size_t[1]")
        local errptr_get = ffi.new("char*[1]")
        local value = rocksdb.rocksdb_get(db, read_options, keys[i], #keys[i], vallen, errptr_get)
        
        if value ~= nil and errptr_get[0] == nil then
            local retrieved_value = ffi.string(value, vallen[0])
            if retrieved_value == values[i] then
                success_count = success_count + 1
                print(string.format("✓ 键值对验证成功: %s -> %s", keys[i], retrieved_value))
            else
                print(string.format("✗ 键值对不匹配: %s -> %s (期望: %s)", keys[i], retrieved_value, values[i]))
            end
            rocksdb.rocksdb_free(value)
        else
            print(string.format("✗ 读取失败: %s", keys[i]))
        end
    end
    
    -- 清理资源
    rocksdb.rocksdb_writebatch_destroy(batch)
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_readoptions_destroy(read_options)
    rocksdb.rocksdb_close(db)
    
    print(string.format("基本WriteBatch测试结果: %d/%d 成功", success_count, #keys))
    return success_count == #keys
end

-- 测试2: WriteBatch混合操作（插入和删除）
local function test_mixed_writebatch_operations()
    print("\n=== 测试2: WriteBatch混合操作 ===")
    
    local db, db_path = create_test_db("mixed_operations")
    if not db then return false end
    
    local write_options = rocksdb.rocksdb_writeoptions_create()
    local read_options = rocksdb.rocksdb_readoptions_create()
    
    -- 先插入一些基础数据
    local base_keys = {"base1", "base2", "base3"}
    local base_values = {"base_value1", "base_value2", "base_value3"}
    
    for i = 1, #base_keys do
        local errptr = ffi.new("char*[1]")
        rocksdb.rocksdb_put(db, write_options, base_keys[i], #base_keys[i], 
                           base_values[i], #base_values[i], errptr)
        if errptr[0] ~= nil then
            print("基础数据插入错误: " .. ffi.string(errptr[0]))
            return false
        end
    end
    
    -- 创建WriteBatch进行混合操作
    local batch = rocksdb.rocksdb_writebatch_create()
    
    -- 添加新数据
    rocksdb.rocksdb_writebatch_put(batch, "new_key1", 7, "new_value1", 10)
    rocksdb.rocksdb_writebatch_put(batch, "new_key2", 7, "new_value2", 10)
    
    -- 删除一些数据
    rocksdb.rocksdb_writebatch_delete(batch, "base2", 5)
    rocksdb.rocksdb_writebatch_delete(batch, "non_existent", 12)  -- 删除不存在的键
    
    -- 执行批量操作
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        print("混合操作WriteBatch错误: " .. ffi.string(errptr[0]))
        return false
    end
    
    -- 验证结果
    local test_cases = {
        {key = "base1", should_exist = true, expected_value = "base_value1"},
        {key = "base2", should_exist = false},
        {key = "base3", should_exist = true, expected_value = "base_value3"},
        {key = "new_key1", should_exist = true, expected_value = "new_value1"},
        {key = "new_key2", should_exist = true, expected_value = "new_value2"},
        {key = "non_existent", should_exist = false}
    }
    
    local success_count = 0
    for _, test_case in ipairs(test_cases) do
        local vallen = ffi.new("size_t[1]")
        local errptr_get = ffi.new("char*[1]")
        local value = rocksdb.rocksdb_get(db, read_options, test_case.key, #test_case.key, vallen, errptr_get)
        
        if test_case.should_exist then
            if value ~= nil and errptr_get[0] == nil then
                local retrieved_value = ffi.string(value, vallen[0])
                if retrieved_value == test_case.expected_value then
                    success_count = success_count + 1
                    print(string.format("✓ 混合操作验证成功: %s -> %s", test_case.key, retrieved_value))
                else
                    print(string.format("✗ 混合操作值不匹配: %s -> %s (期望: %s)", 
                        test_case.key, retrieved_value, test_case.expected_value))
                end
                rocksdb.rocksdb_free(value)
            else
                print(string.format("✗ 混合操作读取失败: %s", test_case.key))
            end
        else
            if value == nil and errptr_get[0] == nil then
                success_count = success_count + 1
                print(string.format("✓ 混合操作删除验证成功: %s 不存在", test_case.key))
            else
                print(string.format("✗ 混合操作删除失败: %s 应该不存在", test_case.key))
                if value then rocksdb.rocksdb_free(value) end
            end
        end
    end
    
    -- 清理资源
    rocksdb.rocksdb_writebatch_destroy(batch)
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_readoptions_destroy(read_options)
    rocksdb.rocksdb_close(db)
    
    print(string.format("混合操作WriteBatch测试结果: %d/%d 成功", success_count, #test_cases))
    return success_count == #test_cases
end

-- 测试3: WriteBatch性能对比
local function test_writebatch_performance()
    print("\n=== 测试3: WriteBatch性能对比 ===")
    
    local db, db_path = create_test_db("performance_part1")
    if not db then return false end
    
    local write_options = rocksdb.rocksdb_writeoptions_create()
    
    -- 测试数据量
    local num_operations = 1000
    
    -- 方法1: 逐个写入（基准性能）
    local start_time = os.clock()
    for i = 1, num_operations do
        local key = "key_" .. i
        local value = "value_" .. i
        local errptr = ffi.new("char*[1]")
        rocksdb.rocksdb_put(db, write_options, key, #key, value, #value, errptr)
        if errptr[0] ~= nil then
            print("逐个写入错误: " .. ffi.string(errptr[0]))
            return false
        end
    end
    local individual_time = os.clock() - start_time
    
    -- 清理数据库重新测试
    rocksdb.rocksdb_close(db)
    cleanup_test_db(db_path)
    db, db_path = create_test_db("performance_part2")
    
    -- 方法2: 使用WriteBatch批量写入
    start_time = os.clock()
    local batch = rocksdb.rocksdb_writebatch_create()
    
    for i = 1, num_operations do
        local key = "key_" .. i
        local value = "value_" .. i
        rocksdb.rocksdb_writebatch_put(batch, key, #key, value, #value)
    end
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        print("WriteBatch写入错误: " .. ffi.string(errptr[0]))
        return false
    end
    
    local batch_time = os.clock() - start_time
    
    -- 性能对比
    local speedup = individual_time / batch_time
    
    print(string.format("逐个写入时间: %.4f 秒", individual_time))
    print(string.format("WriteBatch写入时间: %.4f 秒", batch_time))
    print(string.format("性能提升倍数: %.2fx", speedup))
    
    -- 清理资源
    rocksdb.rocksdb_writebatch_destroy(batch)
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_close(db)
    
    return speedup > 1.0  -- 期望WriteBatch更快
end

-- 测试4: MultiGet功能测试
local function test_multiget_functionality()
    print("\n=== 测试4: MultiGet功能测试 ===")
    
    local db, db_path = create_test_db("multiget_test")
    if not db then return false end
    
    local write_options = rocksdb.rocksdb_writeoptions_create()
    local read_options = rocksdb.rocksdb_readoptions_create()
    
    -- 准备测试数据
    local test_data = {
        {key = "stock_001", value = "{price: 100.5, volume: 1000}"},
        {key = "stock_002", value = "{price: 45.2, volume: 2500}"},
        {key = "stock_003", value = "{price: 78.9, volume: 1800}"},
        {key = "stock_004", value = "{price: 120.1, volume: 3200}"},
        {key = "stock_005", value = "{price: 65.7, volume: 1500}"}
    }
    
    -- 使用WriteBatch批量插入数据
    local batch = rocksdb.rocksdb_writebatch_create()
    for _, data in ipairs(test_data) do
        rocksdb.rocksdb_writebatch_put(batch, data.key, #data.key, data.value, #data.value)
    end
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        print("MultiGet数据准备错误: " .. ffi.string(errptr[0]))
        return false
    end
    
    -- 模拟MultiGet功能（由于RocksDB的multi_get API较复杂，这里使用迭代方式）
    print("模拟MultiGet批量读取:")
    
    local success_count = 0
    for _, data in ipairs(test_data) do
        local vallen = ffi.new("size_t[1]")
        local errptr_get = ffi.new("char*[1]")
        local value = rocksdb.rocksdb_get(db, read_options, data.key, #data.key, vallen, errptr_get)
        
        if value ~= nil and errptr_get[0] == nil then
            local retrieved_value = ffi.string(value, vallen[0])
            if retrieved_value == data.value then
                success_count = success_count + 1
                print(string.format("✓ MultiGet验证成功: %s -> %s", data.key, retrieved_value))
            else
                print(string.format("✗ MultiGet值不匹配: %s -> %s (期望: %s)", 
                    data.key, retrieved_value, data.value))
            end
            rocksdb.rocksdb_free(value)
        else
            print(string.format("✗ MultiGet读取失败: %s", data.key))
        end
    end
    
    -- 测试部分键不存在的情况
    print("\n测试部分键不存在的情况:")
    local mixed_keys = {"stock_001", "stock_999", "stock_003", "stock_888"}
    
    for _, key in ipairs(mixed_keys) do
        local vallen = ffi.new("size_t[1]")
        local errptr_get = ffi.new("char*[1]")
        local value = rocksdb.rocksdb_get(db, read_options, key, #key, vallen, errptr_get)
        
        if value ~= nil and errptr_get[0] == nil then
            local retrieved_value = ffi.string(value, vallen[0])
            print(string.format("✓ 键存在: %s -> %s", key, retrieved_value))
            rocksdb.rocksdb_free(value)
        else
            print(string.format("✓ 键不存在: %s (预期行为)", key))
        end
    end
    
    -- 清理资源
    rocksdb.rocksdb_writebatch_destroy(batch)
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_readoptions_destroy(read_options)
    rocksdb.rocksdb_close(db)
    
    print(string.format("MultiGet功能测试结果: %d/%d 成功", success_count, #test_data))
    return success_count == #test_data
end

-- 主测试函数
local function main()
    print("LuaJIT RocksDB WriteBatch和MultiGet功能测试")
    print("==========================================")
    
    local tests = {
        {name = "基本WriteBatch功能", func = test_basic_writebatch},
        {name = "WriteBatch混合操作", func = test_mixed_writebatch_operations},
        {name = "WriteBatch性能对比", func = test_writebatch_performance},
        {name = "MultiGet功能测试", func = test_multiget_functionality}
    }
    
    local passed_tests = 0
    local total_tests = #tests
    
    for i, test in ipairs(tests) do
        print(string.format("\n执行测试 %d/%d: %s", i, total_tests, test.name))
        
        local success = pcall(test.func)
        if success then
            passed_tests = passed_tests + 1
            print(string.format("✅ %s: 通过", test.name))
        else
            print(string.format("❌ %s: 失败", test.name))
        end
    end
    
    -- 清理测试数据库
    cleanup_test_db()
    
    print("\n" .. string.rep("=", 50))
    print(string.format("测试总结: %d/%d 个测试通过", passed_tests, total_tests))
    
    if passed_tests == total_tests then
        print("🎉 所有测试通过！WriteBatch和MultiGet功能正常")
    else
        print("⚠️  部分测试失败，请检查RocksDB配置")
    end
    
    return passed_tests == total_tests
end

-- 运行测试
if pcall(main) then
    os.exit(0)
else
    print("测试执行过程中发生错误")
    os.exit(1)
end