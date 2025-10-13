#!/usr/bin/env luajit

-- 高级股票行情数据存储示例
-- 使用RocksDB FFI绑定，包含迭代器功能

package.path = package.path .. ";./lua/?.lua"

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
    unsigned char rocksdb_iter_valid(const rocksdb_iterator_t*);
    void rocksdb_iter_seek_to_first(rocksdb_iterator_t*);
    void rocksdb_iter_seek_to_last(rocksdb_iterator_t*);
    void rocksdb_iter_seek(rocksdb_iterator_t*, const char* k, size_t klen);
    void rocksdb_iter_next(rocksdb_iterator_t*);
    void rocksdb_iter_prev(rocksdb_iterator_t*);
    const char* rocksdb_iter_key(const rocksdb_iterator_t*, size_t* klen);
    const char* rocksdb_iter_value(const rocksdb_iterator_t*, size_t* vlen);

    void rocksdb_free(void* ptr);
]]

-- 加载RocksDB库
local rocksdb = ffi.load("rocksdb")

-- 存储引擎类
local StorageEngine = {}
StorageEngine.__index = StorageEngine

function StorageEngine:new(config)
    local obj = setmetatable({}, StorageEngine)
    obj.config = config
    obj.db = nil
    obj.options = nil
    obj.write_options = nil
    obj.read_options = nil
    obj.is_opened = false
    return obj
end

function StorageEngine:open()
    -- 创建RocksDB选项
    self.options = ffi.gc(rocksdb.rocksdb_options_create(), rocksdb.rocksdb_options_destroy)
    
    -- 设置基本选项
    rocksdb.rocksdb_options_set_create_if_missing(self.options, 1)
    
    -- 设置压缩选项
    local compression = self.config.compression or 4  -- 默认LZ4压缩
    rocksdb.rocksdb_options_set_compression(self.options, compression)
    
    -- 打开数据库
    local errptr = ffi.new("char*[1]")
    self.db = rocksdb.rocksdb_open(self.options, self.config.data_dir, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    -- 创建读写选项
    self.write_options = ffi.gc(rocksdb.rocksdb_writeoptions_create(), rocksdb.rocksdb_writeoptions_destroy)
    self.read_options = ffi.gc(rocksdb.rocksdb_readoptions_create(), rocksdb.rocksdb_readoptions_destroy)
    
    self.is_opened = true
    return true
end

function StorageEngine:close()
    if self.db then
        rocksdb.rocksdb_close(self.db)
        self.db = nil
        self.is_opened = false
    end
end

function StorageEngine:put(key, value)
    if not self.is_opened then
        return false, "数据库未打开"
    end
    
    local key_ptr = ffi.cast("const char*", key)
    local value_ptr = ffi.cast("const char*", value)
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_put(self.db, self.write_options, key_ptr, #key, value_ptr, #value, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

function StorageEngine:get(key)
    if not self.is_opened then
        return nil, "数据库未打开"
    end
    
    local key_ptr = ffi.cast("const char*", key)
    local vallen = ffi.new("size_t[1]")
    local errptr = ffi.new("char*[1]")
    
    local value_ptr = rocksdb.rocksdb_get(self.db, self.read_options, key_ptr, #key, vallen, errptr)
    
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

function StorageEngine:create_iterator()
    if not self.is_opened then
        return nil, "数据库未打开"
    end
    
    local iter = rocksdb.rocksdb_create_iterator(self.db, self.read_options)
    return iter
end

-- 迭代器工具函数
function StorageEngine:scan_prefix(prefix)
    if not self.is_opened then
        return nil, "数据库未打开"
    end
    
    local iter = self:create_iterator()
    if not iter then
        return nil, "无法创建迭代器"
    end
    
    local results = {}
    local prefix_ptr = ffi.cast("const char*", prefix)
    
    -- 寻找到前缀的开始位置
    rocksdb.rocksdb_iter_seek(iter, prefix_ptr, #prefix)
    
    -- 遍历所有匹配前缀的键值对
    while rocksdb.rocksdb_iter_valid(iter) ~= 0 do
        local key_len = ffi.new("size_t[1]")
        local key_ptr = rocksdb.rocksdb_iter_key(iter, key_len)
        local key = ffi.string(key_ptr, key_len[0])
        
        -- 检查键是否以指定前缀开始
        if string.sub(key, 1, #prefix) == prefix then
            local value_len = ffi.new("size_t[1]")
            local value_ptr = rocksdb.rocksdb_iter_value(iter, value_len)
            local value = ffi.string(value_ptr, value_len[0])
            
            table.insert(results, {key = key, value = value})
            rocksdb.rocksdb_iter_next(iter)
        else
            break
        end
    end
    
    rocksdb.rocksdb_iter_destroy(iter)
    return results
end

-- 配置
local config = {
    data_dir = "./data/stock_data",
    compression = 4,  -- LZ4压缩
}

-- 创建存储引擎
local engine = StorageEngine:new(config)

-- 打开数据库
local success, err = engine:open()
if not success then
    print("✗ 打开数据库失败:", err)
    return
end

print("✓ 成功打开股票行情数据库")

-- 模拟股票行情数据
local stock_data = {
    { code = "SH000001", timestamp = 1625097600, price = 3580.23, volume = 123456789 },
    { code = "SH000001", timestamp = 1625097660, price = 3581.45, volume = 98765432 },
    { code = "SH000001", timestamp = 1625097720, price = 3582.67, volume = 87654321 },
    { code = "SZ000001", timestamp = 1625097600, price = 25.67, volume = 54321098 },
    { code = "SZ000001", timestamp = 1625097660, price = 25.78, volume = 67890123 },
    { code = "SZ000002", timestamp = 1625097600, price = 18.92, volume = 34567890 },
}

-- 写入数据
print("\n写入股票行情数据:")
for _, data in ipairs(stock_data) do
    -- 构造键值
    local key = string.format("%s:%d", data.code, data.timestamp)
    local value = string.format("%.2f:%d", data.price, data.volume)
    
    local success, err = engine:put(key, value)
    if success then
        print(string.format("  ✓ 写入 %s = %s", key, value))
    else
        print(string.format("  ✗ 写入 %s 失败: %s", key, err))
    end
end

-- 读取数据
print("\n读取股票行情数据:")
for _, data in ipairs(stock_data) do
    local key = string.format("%s:%d", data.code, data.timestamp)
    local value, err = engine:get(key)
    
    if value then
        print(string.format("  ✓ 读取 %s = %s", key, value))
    else
        print(string.format("  ✗ 读取 %s 失败: %s", key, err or "键不存在"))
    end
end

-- 查询特定股票的所有数据
print("\n查询SH000001股票数据:")
local sh_results = engine:scan_prefix("SH000001:")
if sh_results then
    for _, item in ipairs(sh_results) do
        print(string.format("  ✓ %s = %s", item.key, item.value))
    end
else
    print("  ✗ 查询失败")
end

print("\n查询SZ000001股票数据:")
local sz_results = engine:scan_prefix("SZ000001:")
if sz_results then
    for _, item in ipairs(sz_results) do
        print(string.format("  ✓ %s = %s", item.key, item.value))
    end
else
    print("  ✗ 查询失败")
end

-- 关闭数据库
engine:close()
print("\n✓ 数据库已关闭")

print("\n高级股票行情数据存储示例完成")