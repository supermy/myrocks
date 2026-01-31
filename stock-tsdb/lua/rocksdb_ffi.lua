-- RocksDB FFI公共模块
-- 提供统一的RocksDB FFI绑定和基础操作

local ffi = require "ffi"

-- FFI定义
ffi.cdef[[
    // RocksDB基本类型
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
    typedef struct rocksdb_iterator_t rocksdb_iterator_t;
    typedef struct rocksdb_slicetransform_t rocksdb_slicetransform_t;
    typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;
    typedef struct rocksdb_column_family_handle_t rocksdb_column_family_handle_t;

    // 基本函数
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);
    void rocksdb_options_set_create_missing_column_families(rocksdb_options_t*, unsigned char);
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
    char* rocksdb_get_cf(rocksdb_t* db, const rocksdb_readoptions_t* options, rocksdb_column_family_handle_t* column_family, const char* key, size_t keylen, size_t* vallen, char** errptr);
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

    // MultiGet相关函数
    void rocksdb_multi_get(rocksdb_t* db, const rocksdb_readoptions_t* options, size_t num_keys, const char* const* keys_list, const size_t* keys_list_sizes, char** values_list, size_t* values_list_sizes, char** errs);

    // 迭代器函数
    rocksdb_iterator_t* rocksdb_create_iterator(rocksdb_t* db, const rocksdb_readoptions_t* options);
    void rocksdb_iter_destroy(rocksdb_iterator_t*);
    void rocksdb_iter_seek_to_first(rocksdb_iterator_t*);
    unsigned char rocksdb_iter_valid(const rocksdb_iterator_t*);
    void rocksdb_iter_next(rocksdb_iterator_t*);
    const char* rocksdb_iter_key(const rocksdb_iterator_t*, size_t* klen);
    const char* rocksdb_iter_value(const rocksdb_iterator_t*, size_t* vlen);

    void rocksdb_free(void* ptr);
]]

-- 加载RocksDB库
local rocksdb, rocksdb_loaded
local rocksdb_error

-- 尝试加载RocksDB库
local success, result = pcall(function()
    -- 首先尝试使用完整路径加载
    return ffi.load("/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib")
end)

if not success then
    -- 如果完整路径失败，尝试使用系统路径
    success, result = pcall(function()
        return ffi.load("rocksdb")
    end)
end

if success then
    rocksdb = result
    rocksdb_loaded = true
else
    rocksdb_error = result
    rocksdb_loaded = false
    -- 创建一个空的模拟表，避免后续调用出错
    rocksdb = {}
    print("⚠️  RocksDB库加载失败: " .. tostring(rocksdb_error))
    print("⚠️  将使用文件系统存储模拟器")
end

local RocksDBFFI = {}

-- 检查RocksDB是否可用
function RocksDBFFI.is_available()
    return rocksdb_loaded
end

-- 获取加载错误信息
function RocksDBFFI.get_load_error()
    return rocksdb_error
end

-- WriteBatch封装函数
function RocksDBFFI.create_writebatch()
    return ffi.gc(rocksdb.rocksdb_writebatch_create(), rocksdb.rocksdb_writebatch_destroy)
end

function RocksDBFFI.writebatch_put(batch, key, value)
    local key_ptr = ffi.cast("const char*", key)
    local value_ptr = ffi.cast("const char*", value)
    rocksdb.rocksdb_writebatch_put(batch, key_ptr, #key, value_ptr, #value)
end

function RocksDBFFI.writebatch_delete(batch, key)
    local key_ptr = ffi.cast("const char*", key)
    rocksdb.rocksdb_writebatch_delete(batch, key_ptr, #key)
end

function RocksDBFFI.writebatch_clear(batch)
    rocksdb.rocksdb_writebatch_clear(batch)
end

function RocksDBFFI.writebatch_put_cf(batch, cf_handle, key, value)
    local key_ptr = ffi.cast("const char*", key)
    local value_ptr = ffi.cast("const char*", value)
    rocksdb.rocksdb_writebatch_put_cf(batch, cf_handle, key_ptr, #key, value_ptr, #value)
end

function RocksDBFFI.writebatch_delete_cf(batch, cf_handle, key)
    local key_ptr = ffi.cast("const char*", key)
    rocksdb.rocksdb_writebatch_delete_cf(batch, cf_handle, key_ptr, #key)
end

function RocksDBFFI.commit_write_batch(db, write_options, batch)
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

-- MultiGet封装函数
function RocksDBFFI.multi_get(db, read_options, keys)
    if #keys == 0 then
        return {}
    end
    
    local num_keys = #keys
    local keys_list = ffi.new("const char*[?]", num_keys)
    local keys_list_sizes = ffi.new("size_t[?]", num_keys)
    local values_list = ffi.new("char*[?]", num_keys)
    local values_list_sizes = ffi.new("size_t[?]", num_keys)
    local errs = ffi.new("char*[?]", num_keys)
    
    -- 准备键列表
    for i, key in ipairs(keys) do
        keys_list[i-1] = ffi.cast("const char*", key)
        keys_list_sizes[i-1] = #key
    end
    
    -- 执行MultiGet
    rocksdb.rocksdb_multi_get(db, read_options, num_keys, keys_list, keys_list_sizes, values_list, values_list_sizes, errs)
    
    -- 处理结果
    local results = {}
    for i = 1, num_keys do
        local err = errs[i-1]
        if err ~= nil then
            results[i] = {error = ffi.string(err)}
            rocksdb.rocksdb_free(err)
        else
            local value = values_list[i-1]
            if value ~= nil then
                results[i] = ffi.string(value, values_list_sizes[i-1])
                rocksdb.rocksdb_free(value)
            else
                results[i] = nil
            end
        end
    end
    
    return results
end

-- 获取RocksDB库对象
function RocksDBFFI.get_library()
    return rocksdb
end

-- 创建RocksDB选项
function RocksDBFFI.create_options()
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return ffi.gc(rocksdb.rocksdb_options_create(), rocksdb.rocksdb_options_destroy)
end

-- 销毁RocksDB选项（注意：使用ffi.gc创建的对象会自动销毁，通常不需要手动调用）
function RocksDBFFI.destroy_options(options)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    if options then
        -- 注意：如果对象是通过ffi.gc创建的，不要手动调用销毁函数
        -- 垃圾回收器会自动处理
        print("警告：通常不需要手动销毁通过ffi.gc创建的对象")
    end
    return true
end

-- 创建写选项
function RocksDBFFI.create_write_options()
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return ffi.gc(rocksdb.rocksdb_writeoptions_create(), rocksdb.rocksdb_writeoptions_destroy)
end

-- 设置写选项：同步写入
function RocksDBFFI.set_writeoptions_sync(write_options, sync)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_writeoptions_set_sync(write_options, sync and 1 or 0)
    return true
end

-- 创建读选项
function RocksDBFFI.create_read_options()
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return ffi.gc(rocksdb.rocksdb_readoptions_create(), rocksdb.rocksdb_readoptions_destroy)
end

-- 销毁写选项
function RocksDBFFI.destroy_write_options(write_options)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    if write_options then
        rocksdb.rocksdb_writeoptions_destroy(write_options)
    end
    return true
end

-- 销毁读选项
function RocksDBFFI.destroy_read_options(read_options)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    if read_options then
        rocksdb.rocksdb_readoptions_destroy(read_options)
    end
    return true
end

-- 设置选项：创建缺失数据库
function RocksDBFFI.set_create_if_missing(options, value)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_options_set_create_if_missing(options, value and 1 or 0)
    return true
end

-- 设置选项：创建缺失的列族
function RocksDBFFI.set_create_missing_column_families(options, value)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_options_set_create_missing_column_families(options, value and 1 or 0)
    return true
end

-- 设置选项：压缩
function RocksDBFFI.set_compression(options, compression_level)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_options_set_compression(options, compression_level)
    return true
end

-- 设置选项：前缀提取器（前缀压缩）
function RocksDBFFI.set_prefix_extractor(options, prefix_length)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    
    -- 检查prefix_length的类型，确保是数字
    if prefix_length and type(prefix_length) == "number" and prefix_length > 0 then
        local prefix_extractor = rocksdb.rocksdb_slicetransform_create_fixed_prefix(prefix_length)
        rocksdb.rocksdb_options_set_prefix_extractor(options, prefix_extractor)
        -- 启用memtable前缀布隆过滤器
        rocksdb.rocksdb_options_enable_memtable_prefix_bloom_filter(options, 1)
        rocksdb.rocksdb_options_set_memtable_prefix_bloom_size_ratio(options, 0.1)  -- 10%的内存用于布隆过滤器
    else
        -- 禁用前缀压缩
        local noop_extractor = rocksdb.rocksdb_slicetransform_create_noop()
        rocksdb.rocksdb_options_set_prefix_extractor(options, noop_extractor)
    end
    return true
end

-- 创建固定长度前缀提取器
function RocksDBFFI.create_fixed_prefix_extractor(prefix_length)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return rocksdb.rocksdb_slicetransform_create_fixed_prefix(prefix_length)
end

-- 创建无操作前缀提取器
function RocksDBFFI.create_noop_prefix_extractor()
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return rocksdb.rocksdb_slicetransform_create_noop()
end

-- 销毁前缀提取器
function RocksDBFFI.destroy_prefix_extractor(extractor)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    if extractor then
        rocksdb.rocksdb_slicetransform_destroy(extractor)
    end
    return true
end

-- 设置memtable前缀布隆过滤器
function RocksDBFFI.enable_memtable_prefix_bloom_filter(options, enabled, ratio)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_options_enable_memtable_prefix_bloom_filter(options, enabled and 1 or 0)
    if ratio then
        rocksdb.rocksdb_options_set_memtable_prefix_bloom_size_ratio(options, ratio)
    end
    return true
end

-- 打开数据库
function RocksDBFFI.open_database(options, db_path)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    local errptr = ffi.new("char*[1]")
    local db = rocksdb.rocksdb_open(options, db_path, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return nil, error_msg
    end
    
    return db
end

-- 关闭数据库
function RocksDBFFI.close_database(db)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    if db then
        rocksdb.rocksdb_close(db)
    end
    return true
end

-- 打开多CF数据库
function RocksDBFFI.open_with_column_families(default_options, db_path, cf_names, cf_options_map)
    if not rocksdb_loaded then
        return nil, nil, "RocksDB库不可用"
    end
    
    -- 处理Lua表包装的选项对象
    local default_options_cdata = default_options
    if type(default_options) == "table" and default_options._cdata then
        default_options_cdata = default_options._cdata
    end
    
    local num_cfs = #cf_names
    
    -- 准备CF名称数组
    local cf_names_ptr = ffi.new("const char*[?]", num_cfs)
    for i, cf_name in ipairs(cf_names) do
        cf_names_ptr[i-1] = ffi.cast("const char*", cf_name)
    end
    
    -- 准备CF选项数组
    local cf_options_ptr = ffi.new("const rocksdb_options_t*[?]", num_cfs)
    for i, cf_name in ipairs(cf_names) do
        local cf_options = cf_options_map[cf_name]
        if cf_options then
            -- 处理Lua表包装的CF选项对象
            local cf_options_cdata = cf_options
            if type(cf_options) == "table" and cf_options._cdata then
                cf_options_cdata = cf_options._cdata
            end
            cf_options_ptr[i-1] = cf_options_cdata
        else
            -- 如果没有指定CF选项，使用默认选项
            cf_options_ptr[i-1] = default_options_cdata
        end
    end
    
    -- 准备CF句柄数组
    local cf_handles_ptr = ffi.new("rocksdb_column_family_handle_t*[?]", num_cfs)
    
    local errptr = ffi.new("char*[1]")
    local db = rocksdb.rocksdb_open_column_families(
        default_options_cdata, 
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
        return nil, nil, "多CF数据库打开失败: " .. error_msg
    end
    
    if not db then
        return nil, nil, "多CF数据库打开失败"
    end
    
    -- 构建CF映射表
    local cfs = {}
    for i, cf_name in ipairs(cf_names) do
        local cf_handle = cf_handles_ptr[i-1]
        if cf_handle ~= nil then
            -- 使用垃圾回收包装CF句柄
            cfs[cf_name] = ffi.gc(cf_handle, rocksdb.rocksdb_column_family_handle_destroy)
        else
            cfs[cf_name] = nil
        end
    end
    
    return db, cfs
end

-- 写入数据
function RocksDBFFI.put(db, write_options, key, value)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    local key_ptr = ffi.cast("const char*", key)
    local value_ptr = ffi.cast("const char*", value)
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_put(db, write_options, key_ptr, #key, value_ptr, #value, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

-- 读取数据
function RocksDBFFI.get(db, read_options, key)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    local key_ptr = ffi.cast("const char*", key)
    local vallen = ffi.new("size_t[1]")
    local errptr = ffi.new("char*[1]")
    
    local value_ptr = rocksdb.rocksdb_get(db, read_options, key_ptr, #key, vallen, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return nil, error_msg
    end
    
    if value_ptr == nil then
        return nil, nil  -- 键不存在
    end
    
    local value = ffi.string(value_ptr, vallen[0])
    rocksdb.rocksdb_free(value_ptr)
    
    return value
end

-- 从列族读取数据
function RocksDBFFI.get_cf(db, read_options, column_family, key)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    local key_ptr = ffi.cast("const char*", key)
    local vallen = ffi.new("size_t[1]")
    local errptr = ffi.new("char*[1]")
    
    local value_ptr = rocksdb.rocksdb_get_cf(db, read_options, column_family, key_ptr, #key, vallen, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return nil, error_msg
    end
    
    if value_ptr == nil then
        return nil, nil  -- 键不存在
    end
    
    local value = ffi.string(value_ptr, vallen[0])
    rocksdb.rocksdb_free(value_ptr)
    
    return value
end

-- 删除数据
function RocksDBFFI.delete(db, write_options, key)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    local key_ptr = ffi.cast("const char*", key)
    local errptr = ffi.new("char*[1]")
    
    rocksdb.rocksdb_delete(db, write_options, key_ptr, #key, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

-- 创建迭代器
function RocksDBFFI.create_iterator(db, read_options)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    return ffi.gc(rocksdb.rocksdb_create_iterator(db, read_options), rocksdb.rocksdb_iter_destroy)
end

-- 创建列族
function RocksDBFFI.create_column_family(db, column_family_options, column_family_name)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    
    local errptr = ffi.new("char*[1]")
    local cf_handle = rocksdb.rocksdb_create_column_family(db, column_family_options, column_family_name, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return nil, "创建列族失败: " .. error_msg
    end
    
    if not cf_handle then
        return nil, "创建列族失败"
    end
    
    -- 使用垃圾回收包装CF句柄
    return ffi.gc(cf_handle, rocksdb.rocksdb_column_family_handle_destroy)
end

-- 迭代器操作
function RocksDBFFI.iterator_seek_to_first(iterator)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_iter_seek_to_first(iterator)
    return true
end

function RocksDBFFI.iterator_valid(iterator)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    return rocksdb.rocksdb_iter_valid(iterator) ~= 0
end

function RocksDBFFI.iterator_next(iterator)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_iter_next(iterator)
    return true
end

function RocksDBFFI.iterator_key(iterator)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    local klen = ffi.new("size_t[1]")
    local key_ptr = rocksdb.rocksdb_iter_key(iterator, klen)
    if key_ptr ~= nil then
        return ffi.string(key_ptr, klen[0])
    end
    return nil
end

function RocksDBFFI.iterator_value(iterator)
    if not rocksdb_loaded then
        return nil, "RocksDB库不可用"
    end
    local vlen = ffi.new("size_t[1]")
    local value_ptr = rocksdb.rocksdb_iter_value(iterator, vlen)
    if value_ptr ~= nil then
        return ffi.string(value_ptr, vlen[0])
    end
    return nil
end

function RocksDBFFI.destroy_iterator(iterator)
    if not rocksdb_loaded then
        return false, "RocksDB库不可用"
    end
    rocksdb.rocksdb_iter_destroy(iterator)
    return true
end

return RocksDBFFI