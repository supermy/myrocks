#!/usr/bin/env luajit

-- 基本RocksDB功能测试

local ffi = require "ffi"

-- FFI定义
ffi.cdef[[
    // RocksDB基本类型
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
    typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;

    // 基本函数
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);

    rocksdb_t* rocksdb_open(const rocksdb_options_t* options, const char* name, char** errptr);
    void rocksdb_close(rocksdb_t*);

    rocksdb_writeoptions_t* rocksdb_writeoptions_create();
    void rocksdb_writeoptions_destroy(rocksdb_writeoptions_t*);

    rocksdb_readoptions_t* rocksdb_readoptions_create();
    void rocksdb_readoptions_destroy(rocksdb_readoptions_t*);

    char* rocksdb_get(rocksdb_t* db, const rocksdb_readoptions_t* options, const char* key, size_t keylen, size_t* vallen, char** errptr);
    void rocksdb_put(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, const char* val, size_t vallen, char** errptr);
    void rocksdb_delete(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, char** errptr);

    // WriteBatch相关函数
    rocksdb_writebatch_t* rocksdb_writebatch_create();
    void rocksdb_writebatch_destroy(rocksdb_writebatch_t*);
    void rocksdb_writebatch_put(rocksdb_writebatch_t*, const char* key, size_t klen, const char* val, size_t vlen);
    void rocksdb_write(rocksdb_t* db, const rocksdb_writeoptions_t* options, rocksdb_writebatch_t* batch, char** errptr);

    void rocksdb_free(void* ptr);
]]

print("=== 基本RocksDB功能测试 ===")

-- 尝试加载RocksDB库
local rocksdb, rocksdb_loaded
local success, result = pcall(function()
    return ffi.load("rocksdb")
end)

if success then
    rocksdb = result
    rocksdb_loaded = true
    print("✅ RocksDB库加载成功")
else
    rocksdb_loaded = false
    print("❌ RocksDB库加载失败: " .. tostring(result))
    os.exit(1)
end

-- 测试基本操作
local function test_basic_operations()
    print("\n--- 测试基本操作 ---")
    
    -- 创建选项
    local options = rocksdb.rocksdb_options_create()
    rocksdb.rocksdb_options_set_create_if_missing(options, 1)
    
    -- 创建写选项
    local write_options = rocksdb.rocksdb_writeoptions_create()
    
    -- 创建读选项
    local read_options = rocksdb.rocksdb_readoptions_create()
    
    -- 打开数据库
    local errptr = ffi.new("char*[1]")
    local db = rocksdb.rocksdb_open(options, "/tmp/test_basic_db", errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("❌ 数据库打开失败: " .. error_msg)
        return false
    end
    
    print("✅ 数据库打开成功")
    
    -- 测试基本写入
    local key = "test_key"
    local value = "test_value"
    
    rocksdb.rocksdb_put(db, write_options, key, #key, value, #value, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("❌ 写入失败: " .. error_msg)
        return false
    end
    
    print("✅ 写入成功")
    
    -- 测试基本读取
    local vallen = ffi.new("size_t[1]")
    local value_ptr = rocksdb.rocksdb_get(db, read_options, key, #key, vallen, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("❌ 读取失败: " .. error_msg)
        return false
    end
    
    if value_ptr == nil then
        print("❌ 键不存在")
        return false
    end
    
    local retrieved_value = ffi.string(value_ptr, vallen[0])
    rocksdb.rocksdb_free(value_ptr)
    
    if retrieved_value == value then
        print("✅ 读取成功: " .. retrieved_value)
    else
        print("❌ 读取值不匹配: " .. retrieved_value)
        return false
    end
    
    -- 测试WriteBatch
    print("\n--- 测试WriteBatch ---")
    
    local batch = rocksdb.rocksdb_writebatch_create()
    
    -- 向batch中添加操作
    local key1 = "batch_key1"
    local value1 = "batch_value1"
    local key2 = "batch_key2"
    local value2 = "batch_value2"
    
    rocksdb.rocksdb_writebatch_put(batch, key1, #key1, value1, #value1)
    rocksdb.rocksdb_writebatch_put(batch, key2, #key2, value2, #value2)
    
    -- 执行batch写入
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("❌ WriteBatch写入失败: " .. error_msg)
        return false
    end
    
    print("✅ WriteBatch写入成功")
    
    -- 验证batch写入结果
    local value1_ptr = rocksdb.rocksdb_get(db, read_options, key1, #key1, vallen, errptr)
    if value1_ptr ~= nil then
        local retrieved_value1 = ffi.string(value1_ptr, vallen[0])
        rocksdb.rocksdb_free(value1_ptr)
        print("✅ Batch键1验证成功: " .. retrieved_value1)
    else
        print("❌ Batch键1验证失败")
        return false
    end
    
    local value2_ptr = rocksdb.rocksdb_get(db, read_options, key2, #key2, vallen, errptr)
    if value2_ptr ~= nil then
        local retrieved_value2 = ffi.string(value2_ptr, vallen[0])
        rocksdb.rocksdb_free(value2_ptr)
        print("✅ Batch键2验证成功: " .. retrieved_value2)
    else
        print("❌ Batch键2验证失败")
        return false
    end
    
    -- 清理资源
    rocksdb.rocksdb_writebatch_destroy(batch)
    rocksdb.rocksdb_close(db)
    rocksdb.rocksdb_options_destroy(options)
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_readoptions_destroy(read_options)
    
    print("✅ 所有测试通过")
    return true
end

-- 运行测试
local success, result = pcall(test_basic_operations)
if not success then
    print("❌ 测试过程中出现错误: " .. tostring(result))
    os.exit(1)
end

if result then
    print("\n🎉 所有基本功能测试通过！")
else
    print("\n💥 基本功能测试失败")
    os.exit(1)
end