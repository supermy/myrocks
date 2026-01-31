# TSDB 性能优化分析报告

## 概述

本文档基于对 stock-tsdb 项目核心代码的深度阅读，分析性能瓶颈并提出优化建议。

---

## 已实现的优化

### ✅ 方案1: 前缀搜索与读取缓存
- **状态**: 已实现
- **文件**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 260-320)
- **效果**: 读取性能提升 27-120 倍

### ✅ 方案2: 批量写入与冷热分离
- **状态**: 已实现
- **文件**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 180-230)
- **效果**: 写入性能 35,000-55,000 点/秒

### ✅ 方案3-6: 集群与运维优化
- **状态**: 已实现
- **文件**: `lua/smart_load_balancer.lua`, `lua/performance_monitor.lua` 等
- **效果**: 详见优化方案文档

---

## 发现的性能瓶颈

### 1. 🔴 高优先级: 序列化/反序列化性能

**位置**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 115-165)

**问题**:
```lua
-- 当前使用简单的字符串拼接JSON
function V3StorageEngineRocksDB:serialize_data(value, tags)
    local json_str = "{\"value\":" .. tostring(value)
    -- 字符串拼接效率低
    json_str = json_str .. ",\"tags\":{"
    -- ...
end
```

**影响**: 
- 每次写入都进行字符串拼接
- 每次读取都进行字符串解析
- 成为CPU密集型操作的瓶颈

**建议优化**:
```lua
-- 使用二进制序列化替代JSON
function V3StorageEngineRocksDB:serialize_data_binary(value, tags)
    -- 使用MessagePack或自定义二进制格式
    -- 减少50-70%的序列化开销
end
```

---

### 2. 🔴 高优先级: 内存缓存无过期机制

**位置**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 40-45)

**问题**:
```lua
obj.data = {}  -- 内存缓存
-- 缓存无限增长，无过期机制
```

**影响**:
- 长时间运行后内存持续增长
- 可能导致OOM

**建议优化**:
```lua
-- 添加LRU缓存和过期机制
obj.data = lrucache.new({
    max_items = 100000,      -- 最大条目
    ttl = 300,               -- 5分钟过期
    eviction_callback = function(key, value)
        -- 持久化到RocksDB
    end
})
```

---

### 3. 🟡 中优先级: 迭代器未使用前缀搜索

**位置**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 275-285)

**问题**:
```lua
-- 当前实现
self.rocksdb_ffi.iterator_seek_to_first(iterator)
-- 遍历所有数据
```

**影响**:
- 虽然使用了前缀检查，但仍需遍历大量数据
- 可以进一步优化为真正的前缀搜索

**建议优化**:
```lua
-- 使用RocksDB原生前缀搜索
local prefix_transform = rocksdb_ffi.create_prefix_transform(prefix_length)
rocksdb_ffi.options_set_prefix_extractor(options, prefix_transform)

-- 然后使用前缀迭代
rocksdb_ffi.iterator_seek(iterator, prefix)
```

---

### 4. 🟡 中优先级: WriteBatch大小无限制

**位置**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 190-200)

**问题**:
```lua
-- 只在达到batch_size时提交
if self.stats.rocksdb_writes % self.batch_size == 0 then
    self:commit_batch()
end
```

**影响**:
- 异常退出时可能丢失数据
- 大batch导致内存峰值

**建议优化**:
```lua
-- 添加时间触发提交
function V3StorageEngineRocksDB:write_point(...)
    -- ...
    
    -- 检查是否需要提交（数量或时间）
    local should_commit = false
    
    -- 数量触发
    if self.stats.rocksdb_writes % self.batch_size == 0 then
        should_commit = true
    end
    
    -- 时间触发（每100ms）
    if os.clock() - self.last_commit_time > 0.1 then
        should_commit = true
    end
    
    if should_commit then
        self:commit_batch()
        self.last_commit_time = os.clock()
    end
end
```

---

### 5. 🟡 中优先级: 读取缓存无大小限制

**位置**: `lua/tsdb_storage_engine_v3_rocksdb.lua` (行 400-420)

**问题**:
```lua
-- 缓存清理逻辑效率低
if #self.read_cache >= self.read_cache_size then
    -- 遍历查找最旧缓存，O(n)复杂度
    for k, v in pairs(self.read_cache) do
        -- ...
    end
end
```

**影响**:
- 缓存清理时遍历所有条目
- 高并发时可能成为瓶颈

**建议优化**:
```lua
-- 使用LRU链表实现O(1)淘汰
self.read_cache = {
    data = {},           -- 缓存数据
    lru_list = {},       -- LRU链表
    head = nil,          -- 最新
    tail = nil           -- 最旧
}
```

---

### 6. 🟢 低优先级: 集群数据聚合效率

**位置**: `lua/tsdb_storage_engine_integrated.lua` (行 260-290)

**问题**:
```lua
-- 从多个节点获取数据后简单合并
for _, node_id in ipairs(target_nodes) do
    local success, remote_data = self.cluster_manager:fetch_data(...)
    if success then
        for _, data_point in ipairs(remote_data) do
            table.insert(local_data, data_point)  -- O(n)插入
        end
    end
end

-- 最后统一排序
table.sort(local_data, ...)  -- O(n log n)
```

**影响**:
- 大量数据时排序开销大
- 可以优化为流式合并

**建议优化**:
```lua
-- 使用归并排序思想，流式合并
function merge_sorted_streams(streams)
    local heap = minheap.new()
    
    -- 初始化堆
    for i, stream in ipairs(streams) do
        if #stream > 0 then
            heap:push({value = stream[1], stream_idx = i, item_idx = 1})
        end
    end
    
    -- 流式输出
    local result = {}
    while not heap:empty() do
        local min = heap:pop()
        table.insert(result, min.value)
        
        -- 从对应流取下一个
        local stream = streams[min.stream_idx]
        local next_idx = min.item_idx + 1
        if next_idx <= #stream then
            heap:push({
                value = stream[next_idx],
                stream_idx = min.stream_idx,
                item_idx = next_idx
            })
        end
    end
    
    return result
end
```

---

### 7. 🟢 低优先级: FFI调用开销

**位置**: `lua/rocksdb_ffi.lua` (多处)

**问题**:
- 每次操作都进行FFI调用
- Lua-C边界 crossing 有开销

**建议优化**:
```lua
-- 批量FFI操作，减少边界crossing
function RocksDBFFI.batch_put(db, write_options, kv_pairs)
    local batch = rocksdb.rocksdb_writebatch_create()
    
    -- 在C层面批量处理
    for _, pair in ipairs(kv_pairs) do
        local key_ptr = ffi.cast("const char*", pair.key)
        local value_ptr = ffi.cast("const char*", pair.value)
        rocksdb.rocksdb_writebatch_put(batch, key_ptr, #pair.key, value_ptr, #pair.value)
    end
    
    local errptr = ffi.new("char*[1]")
    rocksdb.rocksdb_write(db, write_options, batch, errptr)
    rocksdb.rocksdb_writebatch_destroy(batch)
    
    return errptr[0] == nil
end
```

---

## 优化优先级矩阵

| 优化项 | 影响程度 | 实现难度 | 优先级 | 预期收益 |
|--------|----------|----------|--------|----------|
| 二进制序列化 | 高 | 中 | 🔴 P0 | 50-70%性能提升 |
| 缓存过期机制 | 高 | 低 | 🔴 P0 | 避免OOM |
| 前缀搜索优化 | 中 | 中 | 🟡 P1 | 20-30%查询提升 |
| WriteBatch时间触发 | 中 | 低 | 🟡 P1 | 数据安全 |
| LRU缓存优化 | 中 | 中 | 🟡 P1 | 降低CPU使用 |
| 流式数据合并 | 低 | 高 | 🟢 P2 | 大查询优化 |
| FFI批量操作 | 低 | 中 | 🟢 P2 | 微优化 |

---

## 推荐实施计划

### 第一阶段 (1-2周): 稳定性优化
1. **实现缓存过期机制**
   - 添加LRU缓存
   - 设置TTL过期
   - 内存上限保护

2. **WriteBatch时间触发**
   - 添加定时提交
   - 异常退出保护
   - 数据完整性保证

### 第二阶段 (2-3周): 性能优化
3. **二进制序列化**
   - 调研MessagePack/lua-cjson
   - 实现序列化接口
   - 性能对比测试

4. **前缀搜索优化**
   - 使用RocksDB原生前缀
   - 配置prefix_extractor
   - 迭代器优化

### 第三阶段 (1-2周): 高级优化
5. **LRU缓存优化**
   - 实现O(1)淘汰
   - 并发安全
   - 统计监控

6. **流式合并** (可选)
   - 实现最小堆
   - 流式聚合
   - 大查询优化

---

## 代码示例

### 优化后的序列化实现

```lua
-- 使用MessagePack
local msgpack = require "msgpack"

function V3StorageEngineRocksDB:serialize_data_optimized(value, tags)
    local data = {
        v = value,           -- 短键名减少大小
        t = tags,
        ts = os.time()
    }
    return msgpack.pack(data)
end

function V3StorageEngineRocksDB:deserialize_data_optimized(data_str)
    local data = msgpack.unpack(data_str)
    return {
        value = data.v,
        tags = data.t,
        timestamp = data.ts
    }
end
```

### 优化后的缓存实现

```lua
local lrucache = require "resty.lrucache"

function V3StorageEngineRocksDB:new(config)
    -- ...
    
    -- 使用LRU缓存替代简单table
    self.data, self.data_err = lrucache.new({
        max_items = config.max_cache_items or 100000,
        ttl = config.cache_ttl or 300
    })
    
    if not self.data then
        error("缓存初始化失败: " .. tostring(self.data_err))
    end
    
    -- ...
end
```

---

## 监控指标建议

添加以下性能监控指标：

```lua
-- 序列化性能
stats.serialization_time_ms = 0
stats.deserialization_time_ms = 0

-- 缓存性能
stats.cache_memory_bytes = 0
stats.cache_evictions = 0

-- WriteBatch性能
stats.batch_commit_latency_ms = 0
stats.batch_size_avg = 0
```

---

## 总结

通过实施上述优化，预期可以达到：

1. **写入性能**: 提升 50-70% (二进制序列化)
2. **读取性能**: 提升 20-30% (前缀搜索优化)
3. **内存稳定性**: 消除OOM风险 (缓存过期)
4. **数据安全**: 减少数据丢失 (定时提交)

建议优先实施 🔴 P0 级别的优化，然后逐步推进其他优化项。
