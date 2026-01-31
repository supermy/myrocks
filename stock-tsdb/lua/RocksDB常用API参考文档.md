# RocksDB常用API参考文档

## 概述

RocksDB是一个高性能的嵌入式键值存储引擎，特别适合写密集型工作负载。本文档基于项目中使用的RocksDB FFI实现，整理了常用的API函数和使用方法。

## 基本数据类型

### 核心结构体

```c
typedef struct rocksdb_t rocksdb_t;                    // 数据库实例
typedef struct rocksdb_options_t rocksdb_options_t;     // 数据库选项
typedef struct rocksdb_writeoptions_t rocksdb_writeoptions_t; // 写选项
typedef struct rocksdb_readoptions_t rocksdb_readoptions_t;   // 读选项
typedef struct rocksdb_iterator_t rocksdb_iterator_t;        // 迭代器
typedef struct rocksdb_slicetransform_t rocksdb_slicetransform_t; // 前缀提取器
```

## 数据库生命周期管理

### 1. 创建和销毁选项

```lua
-- 创建数据库选项
local options = RocksDBFFI.create_options()

-- 设置选项：如果数据库不存在则创建
RocksDBFFI.set_create_if_missing(options, true)

-- 设置压缩选项
RocksDBFFI.set_compression(options, 1) -- 1=SNAPPY压缩
```

### 2. 打开和关闭数据库

```lua
-- 打开数据库
local db, err = RocksDBFFI.open_database(options, "/path/to/db")
if not db then
    print("打开数据库失败:", err)
    return
end

-- 关闭数据库
RocksDBFFI.close_database(db)
```

## 数据操作API

### 1. 写入数据

```lua
-- 创建写选项
local write_options = RocksDBFFI.create_write_options()

-- 写入键值对
local success, err = RocksDBFFI.put(db, write_options, "key1", "value1")
if not success then
    print("写入失败:", err)
end
```

### 2. 读取数据

```lua
-- 创建读选项
local read_options = RocksDBFFI.create_read_options()

-- 读取数据
local value, err = RocksDBFFI.get(db, read_options, "key1")
if err then
    print("读取失败:", err)
elseif value == nil then
    print("键不存在")
else
    print("读取到的值:", value)
end
```

### 3. 删除数据

```lua
-- 删除键
local success, err = RocksDBFFI.delete(db, write_options, "key1")
if not success then
    print("删除失败:", err)
end
```

## 批量操作API

### 1. WriteBatch（批量写入）

WriteBatch允许将多个写操作（put/delete）组合成一个原子操作，提高写入性能。

#### 基本使用

```lua
-- 创建WriteBatch
local batch = RocksDBFFI.create_writebatch()

-- 批量添加put操作
RocksDBFFI.writebatch_put(batch, "key1", "value1")
RocksDBFFI.writebatch_put(batch, "key2", "value2")
RocksDBFFI.writebatch_put(batch, "key3", "value3")

-- 批量添加delete操作
RocksDBFFI.writebatch_delete(batch, "old_key")

-- 执行批量写入
local success, err = RocksDBFFI.write_batch(db, write_options, batch)
if not success then
    print("批量写入失败:", err)
else
    print("批量写入成功")
end

-- 清空WriteBatch（可选）
RocksDBFFI.writebatch_clear(batch)
```

#### 性能优势

- **原子性**：所有操作要么全部成功，要么全部失败
- **减少I/O开销**：多个操作合并为一次写入
- **提高吞吐量**：特别适合批量数据导入场景

### 2. MultiGet（批量读取）

MultiGet允许一次性读取多个键，减少网络/磁盘I/O开销。

#### 基本使用

```lua
-- 准备要查询的键列表
local keys = {"key1", "key2", "key3", "key4"}

-- 执行批量读取
local results = RocksDBFFI.multi_get(db, read_options, keys)

-- 处理结果
for i, result in ipairs(results) do
    if type(result) == "table" and result.error then
        print(string.format("键 %s 读取失败: %s", keys[i], result.error))
    elseif result == nil then
        print(string.format("键 %s 不存在", keys[i]))
    else
        print(string.format("键 %s 的值: %s", keys[i], result))
    end
end
```

#### 错误处理

MultiGet为每个键返回独立的结果，包含：
- 成功读取的值
- `nil`（键不存在）
- 错误信息（读取失败）

## 迭代器操作

### 1. 创建和遍历迭代器

```lua
-- 创建迭代器
local iterator = RocksDBFFI.create_iterator(db, read_options)

-- 定位到第一个键
RocksDBFFI.iterator_seek_to_first(iterator)

-- 遍历所有键值对
while RocksDBFFI.iterator_valid(iterator) do
    local key = RocksDBFFI.iterator_key(iterator)
    local value = RocksDBFFI.iterator_value(iterator)
    
    print(string.format("Key: %s, Value: %s", key, value))
    
    -- 移动到下一个
    RocksDBFFI.iterator_next(iterator)
end
```

### 2. 范围查询

```lua
-- 定位到特定键开始遍历
-- 注意：需要先seek到起始位置
RocksDBFFI.iterator_seek_to_first(iterator)

-- 或者使用前缀搜索（需要配置前缀提取器）
```

## 前缀压缩和优化

### 1. 前缀提取器配置

```lua
-- 设置固定长度前缀提取器（前缀压缩）
RocksDBFFI.set_prefix_extractor(options, 3) -- 使用前3个字符作为前缀

-- 启用memtable前缀布隆过滤器
RocksDBFFI.enable_memtable_prefix_bloom_filter(options, true, 0.1)
```

### 2. 手动前缀提取器管理

```lua
-- 创建固定长度前缀提取器
local prefix_extractor = RocksDBFFI.create_fixed_prefix_extractor(2)

-- 创建无操作前缀提取器（禁用前缀压缩）
local noop_extractor = RocksDBFFI.create_noop_prefix_extractor()

-- 销毁前缀提取器
RocksDBFFI.destroy_prefix_extractor(prefix_extractor)
```

## 高级配置选项

### 1. 性能优化配置

```lua
-- 设置写缓冲区大小（示例值）
-- RocksDBFFI.set_write_buffer_size(options, 64 * 1024 * 1024) -- 64MB

-- 设置块缓存大小
-- RocksDBFFI.set_block_cache_size(options, 128 * 1024 * 1024) -- 128MB

-- 设置最大写缓冲区数量
-- RocksDBFFI.set_max_write_buffer_number(options, 4)
```

### 2. 压缩配置

```lua
-- 压缩类型常量
local COMPRESSION_TYPES = {
    NO = 0,      -- 无压缩
    SNAPPY = 1,  -- Snappy压缩
    ZLIB = 2,    -- Zlib压缩
    BZLIB2 = 3,  -- Bzip2压缩
    LZ4 = 4,     -- LZ4压缩
    LZ4HC = 5,   -- LZ4高压缩比
    ZSTD = 6     -- Zstandard压缩
}

-- 设置压缩算法
RocksDBFFI.set_compression(options, COMPRESSION_TYPES.SNAPPY)
```

## 错误处理模式

### 1. 统一错误处理

```lua
local function safe_rocksdb_operation(operation_func, ...)
    local result, err = operation_func(...)
    if err then
        print("RocksDB操作失败:", err)
        return nil, err
    end
    return result
end

-- 使用示例
local db = safe_rocksdb_operation(RocksDBFFI.open_database, options, "/path/to/db")
if not db then return end

local success = safe_rocksdb_operation(RocksDBFFI.put, db, write_options, "key", "value")
```

### 2. 资源自动管理

```lua
-- 使用ffi.gc自动管理资源生命周期
local options = ffi.gc(rocksdb.rocksdb_options_create(), rocksdb.rocksdb_options_destroy)
local write_options = ffi.gc(rocksdb.rocksdb_writeoptions_create(), rocksdb.rocksdb_writeoptions_destroy)
local read_options = ffi.gc(rocksdb.rocksdb_readoptions_create(), rocksdb.rocksdb_readoptions_destroy)
```

## 完整使用示例

### 1. 基础使用示例

```lua
local RocksDBFFI = require "rocksdb_ffi"

-- 1. 创建选项
local options = RocksDBFFI.create_options()
RocksDBFFI.set_create_if_missing(options, true)
RocksDBFFI.set_compression(options, 1) -- SNAPPY压缩

-- 2. 打开数据库
local db, err = RocksDBFFI.open_database(options, "./test_db")
if not db then
    print("打开数据库失败:", err)
    return
end

-- 3. 创建写选项
local write_options = RocksDBFFI.create_write_options()

-- 4. 写入数据
RocksDBFFI.put(db, write_options, "user:1001", "{name: \"张三\", age: 25}")
RocksDBFFI.put(db, write_options, "user:1002", "{name: \"李四\", age: 30}")

-- 5. 创建读选项
local read_options = RocksDBFFI.create_read_options()

-- 6. 读取数据
local value = RocksDBFFI.get(db, read_options, "user:1001")
print("用户1001:", value)

-- 7. 遍历所有数据
local iterator = RocksDBFFI.create_iterator(db, read_options)
RocksDBFFI.iterator_seek_to_first(iterator)

print("=== 所有数据 ===")
while RocksDBFFI.iterator_valid(iterator) do
    local key = RocksDBFFI.iterator_key(iterator)
    local value = RocksDBFFI.iterator_value(iterator)
    print(string.format("%s => %s", key, value))
    RocksDBFFI.iterator_next(iterator)
end

-- 8. 关闭数据库
RocksDBFFI.close_database(db)
```

### 2. 前缀压缩优化示例

```lua
local RocksDBFFI = require "rocksdb_ffi"

-- 配置前缀压缩
local options = RocksDBFFI.create_options()
RocksDBFFI.set_create_if_missing(options, true)

-- 使用前缀压缩（前2个字符作为前缀）
RocksDBFFI.set_prefix_extractor(options, 2)
RocksDBFFI.enable_memtable_prefix_bloom_filter(options, true, 0.1)

-- 打开数据库
local db = RocksDBFFI.open_database(options, "./prefix_db")

-- 写入具有相似前缀的键
local write_options = RocksDBFFI.create_write_options()
RocksDBFFI.put(db, write_options, "us:1001", "user data 1")
RocksDBFFI.put(db, write_options, "us:1002", "user data 2") 
RocksDBFFI.put(db, write_options, "pr:2001", "product data 1")
RocksDBFFI.put(db, write_options, "pr:2002", "product data 2")

-- 前缀压缩可以优化具有相似前缀的键的存储和查询效率
```

## 性能优化建议

### 1. 写优化
- 使用批量写入（如果支持）
- 合理设置写缓冲区大小
- 启用合适的压缩算法

### 2. 读优化  
- 配置前缀布隆过滤器
- 使用合适的块缓存大小
- 考虑使用迭代器进行范围查询

### 3. 存储优化
- 启用前缀压缩减少存储空间
- 定期进行压缩操作
- 监控存储使用情况

## 常见问题解决

### 1. 数据库打开失败
- 检查路径权限
- 确认RocksDB库是否正确安装
- 检查选项配置是否正确

### 2. 性能问题
- 检查是否启用了合适的压缩
- 确认内存配置是否合理
- 考虑使用前缀压缩优化

### 3. 内存泄漏
- 确保正确关闭数据库和释放资源
- 使用ffi.gc自动管理资源生命周期

## 相关文件

- <mcfile name="rocksdb_ffi.lua" path="/Users/moyong/project/ai/myrocks/stock-tsdb/lua/rocksdb_ffi.lua"></mcfile> - RocksDB FFI绑定实现
- <mcfile name="light_aggregation_storage.lua" path="/Users/moyong/project/ai/myrocks/stock-tsdb/lua/light_aggregation_storage.lua"></mcfile> - 使用RocksDB的存储引擎
- <mcfile name="business_instance_manager.lua" path="/Users/moyong/project/ai/myrocks/stock-tsdb/lua/business_instance_manager.lua"></mcfile> - 业务实例管理，包含RocksDB使用示例

这个文档涵盖了RocksDB在Lua环境中的常用API和使用方法，基于项目中实际的FFI实现。