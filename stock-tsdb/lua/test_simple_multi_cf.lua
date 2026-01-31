-- 简单多CF数据库测试脚本
local ffi = require "ffi"

-- 加载RocksDB库
local rocksdb = ffi.load("/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib")

-- FFI定义
ffi.cdef[[
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_column_family_handle_t rocksdb_column_family_handle_t;
    
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);
    
    rocksdb_t* rocksdb_open_column_families(const rocksdb_options_t* options, 
                                           const char* name, 
                                           int num_column_families, 
                                           const char* const* column_family_names, 
                                           const rocksdb_options_t* const* column_family_options, 
                                           rocksdb_column_family_handle_t** column_family_handles, 
                                           char** errptr);
    
    void rocksdb_close(rocksdb_t*);
    void rocksdb_column_family_handle_destroy(rocksdb_column_family_handle_t*);
    void rocksdb_free(void* ptr);
]]

-- 测试多CF数据库打开
print("=== 测试简单多CF数据库打开 ===")

-- 创建默认选项
local default_options = rocksdb.rocksdb_options_create()
rocksdb.rocksdb_options_set_create_if_missing(default_options, 1)

-- 准备CF名称和选项
local cf_names = {"", "time_cf", "stock_cf"}  -- 默认CF必须是第一个
local num_cfs = #cf_names

-- 准备CF名称数组
local cf_names_ptr = ffi.new("const char*[?]", num_cfs)
for i, cf_name in ipairs(cf_names) do
    cf_names_ptr[i-1] = ffi.cast("const char*", cf_name)
    print("CF名称[" .. (i-1) .. "]: " .. cf_name)
end

-- 准备CF选项数组（全部使用默认选项）
local cf_options_ptr = ffi.new("const rocksdb_options_t*[?]", num_cfs)
for i = 1, num_cfs do
    cf_options_ptr[i-1] = default_options
end

-- 准备CF句柄数组
local cf_handles_ptr = ffi.new("rocksdb_column_family_handle_t*[?]", num_cfs)

-- 数据库路径
local db_path = "/tmp/test_simple_multi_cf"

-- 打开多CF数据库
local errptr = ffi.new("char*[1]")
local db = rocksdb.rocksdb_open_column_families(
    default_options, 
    db_path, 
    num_cfs, 
    cf_names_ptr, 
    cf_options_ptr, 
    cf_handles_ptr, 
    errptr
)

if errptr[0] ~= nil then
    local error_msg = ffi.string(errptr[0])
    rocksdb.rocksdb_free(errptr[0])
    print("❌ 多CF数据库打开失败: " .. error_msg)
else
    print("✅ 多CF数据库打开成功")
    
    -- 构建CF映射表
    local cfs = {}
    for i, cf_name in ipairs(cf_names) do
        local cf_handle = cf_handles_ptr[i-1]
        if cf_handle ~= nil then
            cfs[cf_name] = cf_handle
            print("✅ CF句柄[" .. cf_name .. "]: " .. tostring(cf_handle))
        else
            cfs[cf_name] = nil
            print("❌ CF句柄[" .. cf_name .. "]: 为空")
        end
    end
    
    -- 关闭数据库
    if db then
        rocksdb.rocksdb_close(db)
        print("✅ 数据库关闭成功")
    end
    
    -- 销毁CF句柄
    for i, cf_handle in ipairs(cf_handles_ptr) do
        if cf_handle ~= nil then
            rocksdb.rocksdb_column_family_handle_destroy(cf_handle)
        end
    end
end

-- 销毁选项
rocksdb.rocksdb_options_destroy(default_options)

print("=== 测试完成 ===")