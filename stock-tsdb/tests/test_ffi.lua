#!/usr/bin/env luajit

-- 测试RocksDB FFI绑定

local ffi = require "ffi"

-- FFI定义
ffi.cdef[[
    // RocksDB基本类型
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;

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

    void rocksdb_free(void* ptr);
]]

print("RocksDB FFI绑定测试")
print("==================")

-- 尝试加载RocksDB库
local success, rocksdb = pcall(function()
    return ffi.load("rocksdb")
end)

if not success then
    print("✗ 无法加载RocksDB库:", rocksdb)
    print("请确保已安装RocksDB共享库")
    return
end

print("✓ 成功加载RocksDB库")

-- 创建选项
local options = rocksdb.rocksdb_options_create()
rocksdb.rocksdb_options_set_create_if_missing(options, 1)

-- 打开数据库
local errptr = ffi.new("char*[1]")
local db = rocksdb.rocksdb_open(options, "./data/testdb", errptr)

if errptr[0] ~= nil then
    local error_msg = ffi.string(errptr[0])
    rocksdb.rocksdb_free(errptr[0])
    print("✗ 打开数据库失败:", error_msg)
else
    print("✓ 成功打开数据库")

    -- 创建读写选项
    local write_options = rocksdb.rocksdb_writeoptions_create()
    local read_options = rocksdb.rocksdb_readoptions_create()

    -- 写入测试数据
    local key = "test_key"
    local value = "test_value"
    local key_ptr = ffi.cast("const char*", key)
    local value_ptr = ffi.cast("const char*", value)
    
    rocksdb.rocksdb_put(db, write_options, key_ptr, #key, value_ptr, #value, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("✗ 写入数据失败:", error_msg)
    else
        print("✓ 成功写入测试数据")
        
        -- 读取测试数据
        local vallen = ffi.new("size_t[1]")
        local value_ptr = rocksdb.rocksdb_get(db, read_options, key_ptr, #key, vallen, errptr)
        
        if errptr[0] ~= nil then
            local error_msg = ffi.string(errptr[0])
            rocksdb.rocksdb_free(errptr[0])
            print("✗ 读取数据失败:", error_msg)
        else
            if value_ptr ~= nil then
                local retrieved_value = ffi.string(value_ptr, vallen[0])
                rocksdb.rocksdb_free(value_ptr)
                print("✓ 成功读取数据:", retrieved_value)
            else
                print("✗ 未找到键值")
            end
        end
    end

    -- 清理资源
    rocksdb.rocksdb_writeoptions_destroy(write_options)
    rocksdb.rocksdb_readoptions_destroy(read_options)
    rocksdb.rocksdb_close(db)
    print("✓ 数据库已关闭")
end

-- 清理选项
rocksdb.rocksdb_options_destroy(options)

print("测试完成")