#!/usr/bin/env luajit

-- 测试RocksDB FFI模块

local ffi = require "ffi"

-- 声明RocksDB函数（正确版本，不带下划线）
ffi.cdef[[
    // 基本类型
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
    typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;
    typedef struct rocksdb_column_family_handle_t rocksdb_column_family_handle_t;
    typedef struct rocksdb_slicetransform_t rocksdb_slicetransform_t;
    
    // 基本函数
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);
    void rocksdb_options_set_compression(rocksdb_options_t*, int);
    
    // 前缀压缩相关函数
    rocksdb_slicetransform_t* rocksdb_slicetransform_create_fixed_prefix(size_t);
    rocksdb_slicetransform_t* rocksdb_slicetransform_create_noop();
    void rocksdb_slicetransform_destroy(rocksdb_slicetransform_t*);
    void rocksdb_options_set_prefix_extractor(rocksdb_options_t*, rocksdb_slicetransform_t*);
    void rocksdb_options_set_memtable_prefix_bloom_size_ratio(rocksdb_options_t*, double);
    void rocksdb_options_enable_memtable_prefix_bloom_filter(rocksdb_options_t*, unsigned char);

    rocksdb_t* rocksdb_open(const rocksdb_options_t* options, const char* name, char** errptr);
    void rocksdb_close(rocksdb_t*);

    rocksdb_writeoptions_t* rocksdb_writeoptions_create();
    void rocksdb_writeoptions_destroy(rocksdb_writeoptions_t*);
    void rocksdb_writeoptions_set_sync(rocksdb_writeoptions_t*, unsigned char);

    rocksdb_readoptions_t* rocksdb_readoptions_create();
    void rocksdb_readoptions_destroy(rocksdb_readoptions_t*);

    char* rocksdb_get(rocksdb_t* db, const rocksdb_readoptions_t* options, const char* key, size_t keylen, size_t* vallen, char** errptr);
    void rocksdb_put(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, const char* val, size_t vallen, char** errptr);
    void rocksdb_delete(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, char** errptr);

    // WriteBatch相关函数
    rocksdb_writebatch_t* rocksdb_writebatch_create();
    void rocksdb_writebatch_destroy(rocksdb_writebatch_t*);
    void rocksdb_writebatch_put(rocksdb_writebatch_t*, const char* key, size_t klen, const char* val, size_t vlen);
    void rocksdb_writebatch_delete(rocksdb_writebatch_t*, const char* key, size_t klen);
    void rocksdb_writebatch_clear(rocksdb_writebatch_t*);
    void rocksdb_write(rocksdb_t* db, const rocksdb_writeoptions_t* options, rocksdb_writebatch_t* batch, char** errptr);

    // 列族相关函数
    void rocksdb_writebatch_put_cf(rocksdb_writebatch_t*, rocksdb_column_family_handle_t*, const char* key, size_t klen, const char* val, size_t vlen);
    void rocksdb_writebatch_delete_cf(rocksdb_writebatch_t*, rocksdb_column_family_handle_t*, const char* key, size_t klen);
    
    // 多CF数据库操作
    rocksdb_t* rocksdb_open_column_families(const rocksdb_options_t* options, const char* name, int num_column_families, const char* const* column_family_names, const rocksdb_options_t* const* column_family_options, rocksdb_column_family_handle_t** column_family_handles, char** errptr);
    rocksdb_column_family_handle_t* rocksdb_create_column_family(rocksdb_t* db, const rocksdb_options_t* column_family_options, const char* column_family_name, char** errptr);
    void rocksdb_drop_column_family(rocksdb_t* db, rocksdb_column_family_handle_t* handle, char** errptr);
    void rocksdb_column_family_handle_destroy(rocksdb_column_family_handle_t* handle);

    void rocksdb_free(void* ptr);
]]

-- 测试直接加载RocksDB库
print("=== 测试直接加载RocksDB库 ===")

local rocksdb
local success, result = pcall(function()
    return ffi.load("/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib")
end)

if success then
    rocksdb = result
    print("✅ RocksDB库加载成功")
    
    -- 测试基本函数是否存在
    print("\n=== 测试基本函数 ===")
    
    -- 测试函数名称
    local function test_function(func_name)
        local func_ptr = rocksdb[func_name]
        if func_ptr ~= nil then
            print("✅ " .. func_name .. " 函数可用")
            return true
        else
            print("❌ " .. func_name .. " 函数不可用")
            return false
        end
    end
    
    -- 测试函数
    test_function("rocksdb_options_create")
    test_function("rocksdb_options_destroy")
    test_function("rocksdb_open")
    test_function("rocksdb_close")
    test_function("rocksdb_put")
    test_function("rocksdb_get")
    
    -- 测试多CF函数
    print("\n=== 测试多CF函数 ===")
    test_function("rocksdb_open_column_families")
    test_function("rocksdb_create_column_family")
    test_function("rocksdb_drop_column_family")
    test_function("rocksdb_column_family_handle_destroy")
    test_function("rocksdb_writebatch_put_cf")
    test_function("rocksdb_writebatch_delete_cf")
    
else
    print("❌ RocksDB库加载失败: " .. tostring(result))
end

print("\n=== 测试RocksDB FFI模块 ===")

-- 测试RocksDB FFI模块
local rocksdb_ffi = require "rocksdb_ffi"

if rocksdb_ffi.is_available() then
    print("✅ RocksDB FFI模块可用")
    
    -- 测试创建选项
    local options, err = rocksdb_ffi.create_options()
    if options then
        print("✅ 选项创建成功")
        
        -- 测试设置选项
        local success = rocksdb_ffi.set_create_if_missing(options, true)
        if success then
            print("✅ 设置选项成功")
        else
            print("❌ 设置选项失败")
        end
    else
        print("❌ 选项创建失败: " .. tostring(err))
    end
    
    -- 测试WriteBatch
    local batch = rocksdb_ffi.create_writebatch()
    if batch then
        print("✅ WriteBatch创建成功")
    else
        print("❌ WriteBatch创建失败")
    end
    
else
    print("❌ RocksDB FFI模块不可用: " .. tostring(rocksdb_ffi.get_load_error()))
end