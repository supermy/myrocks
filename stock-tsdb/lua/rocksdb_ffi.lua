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

    // 基本函数
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);
    void rocksdb_options_set_compression(rocksdb_options_t*, int);

    rocksdb_t* rocksdb_open(const rocksdb_options_t* options, const char* name, char** errptr);
    void rocksdb_close(rocksdb_t*);

    rocksdb_writeoptions_t* rocksdb_writeoptions_create();
    void rocksdb_writeoptions_destroy(rocksdb_writeoptions_t*);

    rocksdb_readoptions_t* rocksdb_readoptions_create();
    void rocksdb_readoptions_destroy(rocksdb_readoptions_t*);

    char* rocksdb_get(rocksdb_t* db, const rocksdb_readoptions_t* options, const char* key, size_t keylen, size_t* vallen, char** errptr);
    void rocksdb_put(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, const char* val, size_t vallen, char** errptr);
    void rocksdb_delete(rocksdb_t* db, const rocksdb_writeoptions_t* options, const char* key, size_t keylen, char** errptr);

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
local rocksdb = ffi.load("rocksdb")

local RocksDBFFI = {}

-- 获取RocksDB库对象
function RocksDBFFI.get_library()
    return rocksdb
end

-- 创建RocksDB选项
function RocksDBFFI.create_options()
    return ffi.gc(rocksdb.rocksdb_options_create(), rocksdb.rocksdb_options_destroy)
end

-- 创建写选项
function RocksDBFFI.create_write_options()
    return ffi.gc(rocksdb.rocksdb_writeoptions_create(), rocksdb.rocksdb_writeoptions_destroy)
end

-- 创建读选项
function RocksDBFFI.create_read_options()
    return ffi.gc(rocksdb.rocksdb_readoptions_create(), rocksdb.rocksdb_readoptions_destroy)
end

-- 设置选项：创建缺失数据库
function RocksDBFFI.set_create_if_missing(options, value)
    rocksdb.rocksdb_options_set_create_if_missing(options, value and 1 or 0)
end

-- 设置选项：压缩
function RocksDBFFI.set_compression(options, compression_level)
    rocksdb.rocksdb_options_set_compression(options, compression_level)
end

-- 打开数据库
function RocksDBFFI.open_database(options, db_path)
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
    if db then
        rocksdb.rocksdb_close(db)
    end
end

-- 写入数据
function RocksDBFFI.put(db, write_options, key, value)
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

-- 删除数据
function RocksDBFFI.delete(db, write_options, key)
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
    return ffi.gc(rocksdb.rocksdb_create_iterator(db, read_options), rocksdb.rocksdb_iter_destroy)
end

-- 迭代器操作
function RocksDBFFI.iterator_seek_to_first(iterator)
    rocksdb.rocksdb_iter_seek_to_first(iterator)
end

function RocksDBFFI.iterator_valid(iterator)
    return rocksdb.rocksdb_iter_valid(iterator) ~= 0
end

function RocksDBFFI.iterator_next(iterator)
    rocksdb.rocksdb_iter_next(iterator)
end

function RocksDBFFI.iterator_key(iterator)
    local klen = ffi.new("size_t[1]")
    local key_ptr = rocksdb.rocksdb_iter_key(iterator, klen)
    if key_ptr ~= nil then
        return ffi.string(key_ptr, klen[0])
    end
    return nil
end

function RocksDBFFI.iterator_value(iterator)
    local vlen = ffi.new("size_t[1]")
    local value_ptr = rocksdb.rocksdb_iter_value(iterator, vlen)
    if value_ptr ~= nil then
        return ffi.string(value_ptr, vlen[0])
    end
    return nil
end

return RocksDBFFI