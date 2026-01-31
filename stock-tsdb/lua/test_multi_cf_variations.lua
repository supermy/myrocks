-- 多CF数据库打开方式变体测试
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
    void rocksdb_options_set_create_missing_column_families(rocksdb_options_t*, unsigned char);
    
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

-- 测试函数
local function test_multi_cf(test_name, cf_names, set_create_missing_cf)
    print("\n=== " .. test_name .. " ===")
    
    -- 创建默认选项
    local default_options = rocksdb.rocksdb_options_create()
    rocksdb.rocksdb_options_set_create_if_missing(default_options, 1)
    
    if set_create_missing_cf then
        rocksdb.rocksdb_options_set_create_missing_column_families(default_options, 1)
    end
    
    -- 准备CF名称和选项
    local num_cfs = #cf_names
    
    -- 准备CF名称数组
    local cf_names_ptr = ffi.new("const char*[?]", num_cfs)
    for i, cf_name in ipairs(cf_names) do
        cf_names_ptr[i-1] = ffi.cast("const char*", cf_name)
        print("CF名称[" .. (i-1) .. "]: '" .. cf_name .. "'")
    end
    
    -- 准备CF选项数组（全部使用默认选项）
    local cf_options_ptr = ffi.new("const rocksdb_options_t*[?]", num_cfs)
    for i = 1, num_cfs do
        cf_options_ptr[i-1] = default_options
    end
    
    -- 准备CF句柄数组
    local cf_handles_ptr = ffi.new("rocksdb_column_family_handle_t*[?]", num_cfs)
    
    -- 数据库路径
    local db_path = "/tmp/test_multi_cf_variations"
    
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
        for i, cf_name in ipairs(cf_names) do
            local cf_handle = cf_handles_ptr[i-1]
            if cf_handle ~= nil then
                print("✅ CF句柄['" .. cf_name .. "']: " .. tostring(cf_handle))
            else
                print("❌ CF句柄['" .. cf_name .. "']: 为空")
            end
        end
        
        -- 关闭数据库
        if db then
            rocksdb.rocksdb_close(db)
            print("✅ 数据库关闭成功")
        end
        
        -- 销毁CF句柄
        for i = 1, num_cfs do
            local cf_handle = cf_handles_ptr[i-1]
            if cf_handle ~= nil then
                rocksdb.rocksdb_column_family_handle_destroy(cf_handle)
            end
        end
    end
    
    -- 销毁选项
    rocksdb.rocksdb_options_destroy(default_options)
end

-- 运行不同变体的测试
print("=== 多CF数据库打开方式变体测试 ===")

-- 测试1: 默认CF为空字符串，启用create_missing_column_families
test_multi_cf("测试1: 默认CF为空字符串，启用create_missing_column_families", {"", "time_cf", "stock_cf"}, true)

-- 测试2: 默认CF为"default"，启用create_missing_column_families
test_multi_cf("测试2: 默认CF为'default'，启用create_missing_column_families", {"default", "time_cf", "stock_cf"}, true)

-- 测试3: 默认CF为空字符串，不启用create_missing_column_families
test_multi_cf("测试3: 默认CF为空字符串，不启用create_missing_column_families", {"", "time_cf", "stock_cf"}, false)

-- 测试4: 只有默认CF
test_multi_cf("测试4: 只有默认CF", {""}, true)

-- 测试5: 使用"default_cf"作为默认CF
test_multi_cf("测试5: 使用'default_cf'作为默认CF", {"default_cf", "time_cf", "stock_cf"}, true)

print("\n=== 所有测试完成 ===")