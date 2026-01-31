--[[
    RocksDB FFI 批量操作优化
    P2优化: 减少Lua-C边界crossing开销
]]

local ffi = require "ffi"

local RocksDBBatchFFI = {}
RocksDBBatchFFI.__index = RocksDBBatchFFI

-- 加载RocksDB库
local rocksdb = ffi.load("rocksdb")

-- 定义C结构
ffi.cdef[[
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t;
    typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;
    typedef struct rocksdb_writebatch_t rocksdb_writebatch_t;
    typedef struct rocksdb_iterator_t rocksdb_iterator_t;
    
    rocksdb_writebatch_t* rocksdb_writebatch_create(void);
    void rocksdb_writebatch_destroy(rocksdb_writebatch_t* batch);
    void rocksdb_writebatch_clear(rocksdb_writebatch_t* batch);
    void rocksdb_writebatch_put(rocksdb_writebatch_t* batch, 
                                const char* key, size_t klen,
                                const char* val, size_t vlen);
    void rocksdb_write(rocksdb_t* db,
                       const rocksdb_writeoptions_t* options,
                       rocksdb_writebatch_t* batch,
                       char** errptr);
    
    void rocksdb_free(void* ptr);
]]

function RocksDBBatchFFI:new(rocksdb_ffi)
    local obj = setmetatable({}, self)
    obj.rocksdb_ffi = rocksdb_ffi
    obj.batch_buffer = {}  -- 批量操作缓冲区
    obj.batch_size = 100   -- 默认批量大小
    obj.pending_ops = 0    -- 待处理操作数
    return obj
end

-- 设置批量大小
function RocksDBBatchFFI:set_batch_size(size)
    self.batch_size = size or 100
end

-- 批量Put操作
function RocksDBBatchFFI:batch_put(db, write_options, kv_pairs)
    if not db or not kv_pairs or #kv_pairs == 0 then
        return false, "无效参数"
    end
    
    local batch = rocksdb.rocksdb_writebatch_create()
    
    -- 在C层面批量处理所有操作
    for _, pair in ipairs(kv_pairs) do
        local key_ptr = ffi.cast("const char*", pair.key)
        local value_ptr = ffi.cast("const char*", pair.value)
        rocksdb.rocksdb_writebatch_put(batch, key_ptr, #pair.key, value_ptr, #pair.value)
    end
    
    -- 一次性提交
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    rocksdb.rocksdb_writebatch_destroy(batch)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

-- 缓冲Put操作
function RocksDBBatchFFI:buffered_put(key, value)
    table.insert(self.batch_buffer, {key = key, value = value})
    self.pending_ops = self.pending_ops + 1
    
    -- 达到批量大小则自动提交
    if self.pending_ops >= self.batch_size then
        return self:flush_buffer()
    end
    
    return true
end

-- 刷新缓冲区
function RocksDBBatchFFI:flush_buffer(db, write_options)
    if self.pending_ops == 0 then
        return true
    end
    
    if not db or not write_options then
        return false, "数据库未初始化"
    end
    
    local success, err = self:batch_put(db, write_options, self.batch_buffer)
    
    if success then
        self.batch_buffer = {}
        self.pending_ops = 0
    end
    
    return success, err
end

-- 批量Get操作优化
function RocksDBBatchFFI:batch_get(db, read_options, keys)
    if not db or not keys or #keys == 0 then
        return false, "无效参数"
    end
    
    local results = {}
    
    -- 使用迭代器批量读取
    for _, key in ipairs(keys) do
        local value = self.rocksdb_ffi.get(db, read_options, key)
        results[key] = value
    end
    
    return true, results
end

-- 批量Delete操作
function RocksDBBatchFFI:batch_delete(db, write_options, keys)
    if not db or not keys or #keys == 0 then
        return false, "无效参数"
    end
    
    local batch = rocksdb.rocksdb_writebatch_create()
    
    for _, key in ipairs(keys) do
        local key_ptr = ffi.cast("const char*", key)
        rocksdb.rocksdb_writebatch_delete(batch, key_ptr, #key)
    end
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    rocksdb.rocksdb_writebatch_destroy(batch)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        return false, error_msg
    end
    
    return true
end

-- 性能测试
function RocksDBBatchFFI:benchmark(db, write_options, iterations)
    iterations = iterations or 1000
    
    -- 准备测试数据
    local kv_pairs = {}
    for i = 1, 100 do
        table.insert(kv_pairs, {
            key = "benchmark_key_" .. i,
            value = "benchmark_value_" .. i
        })
    end
    
    -- 测试批量写入
    local start_time = os.clock()
    for i = 1, iterations do
        self:batch_put(db, write_options, kv_pairs)
    end
    local batch_time = os.clock() - start_time
    
    -- 测试单个写入
    start_time = os.clock()
    for i = 1, iterations do
        for _, pair in ipairs(kv_pairs) do
            self.rocksdb_ffi.put(db, write_options, pair.key, pair.value)
        end
    end
    local single_time = os.clock() - start_time
    
    return {
        batch_time_ms = batch_time * 1000,
        single_time_ms = single_time * 1000,
        speedup = single_time / batch_time,
        ops_per_second = (iterations * #kv_pairs) / batch_time
    }
end

return RocksDBBatchFFI
