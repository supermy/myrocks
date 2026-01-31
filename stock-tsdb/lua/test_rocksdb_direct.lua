#!/usr/bin/env luajit

-- 直接测试RocksDB函数调用

local ffi = require "ffi"

-- 声明RocksDB函数（带下划线版本）
ffi.cdef[[
    // 基本类型
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
    typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;
    typedef struct rocksdb_column_family_handle_t rocksdb_column_family_handle_t;
    
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

print("=== 测试直接RocksDB函数调用 ===")

-- 尝试加载RocksDB库
local rocksdb
local success, result = pcall(function()
    return ffi.load("/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib")
end)

if success then
    rocksdb = result
    print("✅ RocksDB库加载成功")
    
    -- 测试创建选项
    print("\n=== 测试创建选项 ===")
    
    local options = rocksdb.rocksdb_options_create()
    if options ~= nil then
        print("✅ rocksdb_options_create 成功")
        
        -- 测试设置选项
        rocksdb.rocksdb_options_set_create_if_missing(options, 1)
        print("✅ rocksdb_options_set_create_if_missing 成功")
        
        -- 测试销毁选项
        rocksdb.rocksdb_options_destroy(options)
        print("✅ rocksdb_options_destroy 成功")
    else
        print("❌ rocksdb_options_create 失败")
    end
    
    -- 测试创建写选项
    print("\n=== 测试写选项 ===")
    
    local write_options = rocksdb.rocksdb_writeoptions_create()
    if write_options ~= nil then
        print("✅ rocksdb_writeoptions_create 成功")
        rocksdb.rocksdb_writeoptions_destroy(write_options)
        print("✅ rocksdb_writeoptions_destroy 成功")
    else
        print("❌ rocksdb_writeoptions_create 失败")
    end
    
    -- 测试创建读选项
    print("\n=== 测试读选项 ===")
    
    local read_options = rocksdb.rocksdb_readoptions_create()
    if read_options ~= nil then
        print("✅ rocksdb_readoptions_create 成功")
        rocksdb.rocksdb_readoptions_destroy(read_options)
        print("✅ rocksdb_readoptions_destroy 成功")
    else
        print("❌ rocksdb_readoptions_create 失败")
    end
    
else
    print("❌ RocksDB库加载失败: " .. tostring(result))
end