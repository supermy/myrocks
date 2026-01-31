# V3存储引擎详细架构说明

## 🏗️ 整体架构概述

V3存储引擎采用插件化架构设计，支持基础版本和集成版本两种实现，提供统一的API接口。整个系统采用分层架构，从应用层到存储层都有清晰的职责划分。

### 架构层次

```
应用层 (Application Layer)
    ↓
API层 (API Layer) 
    ↓
引擎层 (Engine Layer)
    ↓
存储层 (Storage Layer)
    ↓
基础设施层 (Infrastructure Layer)
```

## 🔧 核心组件详细说明

### 1. V3StorageEngine 核心类

```lua
-- 核心类结构
V3StorageEngine = {
    config = {},           -- 配置参数
    data = {},             -- 内存数据存储
    initialized = false,   -- 初始化状态
    csv_manager = nil,     -- CSV数据管理器
    
    -- 冷热数据分离配置
    enable_cold_data_separation = false,
    cold_data_threshold_days = 30
}
```

#### 主要方法

**初始化方法**
- `new(config)`: 创建引擎实例
- `initialize()`: 初始化引擎
- `close()`: 关闭引擎

**数据操作方法**
- `write_point(metric, timestamp, value, tags)`: 写入数据点
- `read_point(metric, start_time, end_time, tags)`: 查询数据点
- `encode_metric_key(metric, timestamp, tags)`: RowKey编码
- `encode_stock_key(stock_code, timestamp, market)`: 股票数据编码

**管理方法**
- `get_cf_name_for_timestamp(timestamp)`: ColumnFamily管理
- `get_stats()`: 获取统计信息
- `migrate_to_cold_data(timestamp)`: 冷数据迁移
- `cleanup_old_data(retention_days)`: 数据清理

### 2. 数据存储架构

#### RowKey编码策略

```lua
-- 通用数据编码
function encode_metric_key(metric, timestamp, tags)
    -- 格式: metric_tag1=value1_tag2=value2
    local key_parts = {metric}
    if tags then
        for k, v in pairs(tags) do
            table.insert(key_parts, string.format("%s=%s", k, v))
        end
    end
    return table.concat(key_parts, "_"), string.format("%08x", timestamp % 0x100000000)
end

-- 股票数据编码
function encode_stock_key(stock_code, timestamp, market)
    -- 格式: stock_code_market
    return string.format("stock_%s_%s", stock_code, market), 
           string.format("%08x", timestamp % 0x100000000)
end
```

#### 30秒定长块存储

```lua
-- 块时间计算
function calculate_block_time(timestamp)
    return math.floor(timestamp / 30) * 30  -- 30秒对齐
end

-- 块内偏移
function calculate_block_offset(timestamp)
    return timestamp % 30  -- 0-29秒偏移
end
```

### 3. 冷热数据分离机制

#### 数据分类策略

```lua
function get_cf_name_for_timestamp(timestamp)
    local date = os.date("*t", timestamp)
    local date_str = string.format("%04d%02d%02d", date.year, date.month, date.day)
    
    if self.enable_cold_data_separation then
        local current_time = os.time()
        local days_diff = os.difftime(current_time, timestamp) / (24 * 60 * 60)
        
        if days_diff > self.cold_data_threshold_days then
            return "cold_" .. date_str  -- 冷数据ColumnFamily
        else
            return "cf_" .. date_str    -- 热数据ColumnFamily
        end
    else
        return "cf_" .. date_str       -- 统一ColumnFamily
    end
end
```

#### 冷热数据统计

```lua
function get_cold_hot_stats()
    local current_time = os.time()
    local hot_count, cold_count = 0, 0
    
    for key, data in pairs(self.data) do
        local days_diff = os.difftime(current_time, data.timestamp) / (24 * 60 * 60)
        if days_diff <= self.cold_data_threshold_days then
            hot_count = hot_count + 1
        else
            cold_count = cold_count + 1
        end
    end
    
    return {hot = hot_count, cold = cold_count}
end
```

## 🔄 数据流程详细说明

### 1. 数据写入流程

#### 步骤分解

1. **数据接收与验证**
   ```lua
   -- 验证数据格式
   if not metric or not timestamp or not value then
       return false, "缺少必要参数"
   end
   
   -- 验证时间戳有效性
   if timestamp <= 0 then
       return false, "时间戳无效"
   end
   ```

2. **RowKey编码**
   ```lua
   -- 生成RowKey和Qualifier
   local row_key, qualifier = self:encode_metric_key(metric, timestamp, tags)
   ```

3. **冷热数据判断**
   ```lua
   -- 确定存储的ColumnFamily
   local cf_name = self:get_cf_name_for_timestamp(timestamp)
   ```

4. **数据存储**
   ```lua
   -- 存储到内存数据结构
   local key = string.format("%s_%d", metric, timestamp)
   self.data[key] = {
       metric = metric,
       timestamp = timestamp,
       value = value,
       tags = tags
   }
   ```

### 2. 数据查询流程

#### 步骤分解

1. **查询解析**
   ```lua
   -- 解析查询参数
   local start_ts = start_time or 0
   local end_ts = end_time or os.time()
   ```

2. **时间范围优化**
   ```lua
   -- 确定需要查询的ColumnFamily范围
   local start_cf = self:get_cf_name_for_timestamp(start_ts)
   local end_cf = self:get_cf_name_for_timestamp(end_ts)
   ```

3. **数据检索**
   ```lua
   -- 遍历内存数据结构
   local results = {}
   for key, data in pairs(self.data) do
       if data.metric == metric and 
          data.timestamp >= start_ts and 
          data.timestamp <= end_ts then
           table.insert(results, data)
       end
   end
   ```

4. **结果处理**
   ```lua
   -- 排序和格式化结果
   table.sort(results, function(a, b) return a.timestamp < b.timestamp end)
   return true, results
   ```

## 🏢 V3集成版本架构

### 1. 集群架构设计

#### 一致性哈希分片

```lua
-- 虚拟节点管理
function create_virtual_nodes(physical_nodes, virtual_nodes_per_physical)
    local virtual_nodes = {}
    for _, node in ipairs(physical_nodes) do
        for i = 1, virtual_nodes_per_physical do
            local virtual_node = string.format("%s_virtual_%d", node, i)
            table.insert(virtual_nodes, {
                physical_node = node,
                virtual_node = virtual_node,
                hash = hash_function(virtual_node)
            })
        end
    end
    return virtual_nodes
end

-- 数据路由
function route_data(key, virtual_nodes)
    local key_hash = hash_function(key)
    -- 在哈希环上找到合适的节点
    -- ...
end
```

#### ZeroMQ集群通信

```lua
-- 消息格式定义
local message_types = {
    DATA_WRITE = 1,
    DATA_READ = 2,
    HEARTBEAT = 3,
    SYNC_REQUEST = 4,
    SYNC_RESPONSE = 5
}

-- 消息处理
function handle_zmq_message(message)
    local msg_type = message.type
    
    if msg_type == message_types.DATA_WRITE then
        return handle_data_write(message)
    elseif msg_type == message_types.DATA_READ then
        return handle_data_read(message)
    -- ... 其他消息类型
    end
end
```

### 2. 高可用机制

#### Consul服务发现

```lua
-- 服务注册
function register_with_consul(service_config)
    local consul = require("consul")
    local client = consul:new(service_config.consul_endpoints)
    
    return client:register_service({
        ID = service_config.node_id,
        Name = service_config.cluster_name,
        Address = service_config.node_address,
        Port = service_config.service_port,
        Check = {
            HTTP = service_config.health_check_url,
            Interval = "10s",
            Timeout = "5s"
        }
    })
end
```

#### 故障检测与恢复

```lua
-- 健康检查
function health_check()
    return {
        status = "healthy",
        timestamp = os.time(),
        memory_usage = collectgarbage("count"),
        data_points = #self.data,
        last_heartbeat = self.last_heartbeat_time
    }
end

-- 故障转移
function handle_node_failure(failed_node)
    -- 重新分配数据
    -- 更新路由表
    -- 通知客户端
end
```

## 📊 性能优化技术

### 1. 存储优化

#### 压缩算法选择

```lua
-- 压缩配置
local compression_algorithms = {
    lz4 = {
        name = "lz4",
        level = 1,
        enabled = true
    },
    snappy = {
        name = "snappy", 
        level = 1,
        enabled = false
    }
}

function configure_compression(algorithm_config)
    if algorithm_config.enabled then
        rocksdb_options_set_compression(self.options, algorithm_config.name)
        rocksdb_options_set_compression_level(self.options, algorithm_config.level)
    end
end
```

#### 缓存策略

```lua
-- 块缓存配置
function configure_block_cache(cache_size_mb)
    local cache = rocksdb_cache_create_lru(cache_size_mb * 1024 * 1024)
    rocksdb_options_set_block_cache(self.options, cache)
end

-- 写入缓冲区
function configure_write_buffer(write_buffer_size_mb, max_write_buffers)
    rocksdb_options_set_write_buffer_size(self.options, write_buffer_size_mb * 1024 * 1024)
    rocksdb_options_set_max_write_buffer_number(self.options, max_write_buffers)
end
```

### 2. 查询优化

#### 并行查询

```lua
-- 多线程查询
function parallel_query(queries, num_threads)
    local threads = {}
    local results = {}
    
    -- 分割查询任务
    local query_chunks = split_queries(queries, num_threads)
    
    for i, chunk in ipairs(query_chunks) do
        threads[i] = coroutine.create(function()
            return execute_queries(chunk)
        end)
    end
    
    -- 等待所有线程完成
    for i, thread in ipairs(threads) do
        local success, result = coroutine.resume(thread)
        if success then
            table.insert(results, result)
        end
    end
    
    return merge_results(results)
end
```

#### 索引优化

```lua
-- 前缀压缩
function configure_prefix_extractor()
    local prefix_extractor = rocksdb_slice_transform_create_fixed_prefix(8)  -- 8字节前缀
    rocksdb_options_set_prefix_extractor(self.options, prefix_extractor)
end

-- 布隆过滤器
function configure_bloom_filter(bits_per_key)
    local filter = rocksdb_filterpolicy_create_bloom(bits_per_key)
    rocksdb_options_set_filter_policy(self.options, filter)
end
```

## 🔧 监控与运维

### 1. 统计信息收集

```lua
function collect_detailed_stats()
    return {
        -- 基础信息
        is_initialized = self.initialized,
        uptime = os.time() - self.start_time,
        
        -- 数据统计
        total_data_points = #self.data,
        hot_data_points = self:get_cold_hot_stats().hot,
        cold_data_points = self:get_cold_hot_stats().cold,
        
        -- 性能统计
        write_operations = self.stats.write_count or 0,
        read_operations = self.stats.read_count or 0,
        average_write_latency = self.stats.avg_write_latency or 0,
        average_read_latency = self.stats.avg_read_latency or 0,
        
        -- 资源使用
        memory_usage = collectgarbage("count") * 1024,  -- bytes
        file_descriptors = get_open_file_descriptors(),
        
        -- 集群信息（集成版本）
        cluster_enabled = self.cluster_enabled or false,
        cluster_nodes = self.cluster_nodes or {},
        replication_factor = self.replication_factor or 1
    }
end
```

### 2. 健康检查

```lua
function perform_health_check()
    local checks = {
        {name = "引擎状态", check = function() return self.initialized end},
        {name = "内存使用", check = function() return collectgarbage("count") < 1000 end},  -- < 1GB
        {name = "数据完整性", check = function() return self:verify_data_integrity() end},
        {name = "存储可用性", check = function() return self:check_storage_availability() end}
    }
    
    local results = {}
    for _, check in ipairs(checks) do
        local success, err = pcall(check.check)
        results[check.name] = {
            status = success and "healthy" or "unhealthy",
            error = err
        }
    end
    
    return results
end
```

## 📈 部署架构

### 1. 单机部署配置

```lua
-- 基础版本配置
local basic_config = {
    data_dir = "./data/basic",
    block_size = 30,
    enable_compression = true,
    compression_type = "lz4",
    write_buffer_size = 64 * 1024 * 1024,  -- 64MB
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,
    max_bytes_for_level_base = 256 * 1024 * 1024
}
```

### 2. 集群部署配置

```lua
-- 集成版本配置
local integrated_config = {
    data_dir = "./data/integrated",
    node_id = "node_1",
    cluster_name = "tsdb-cluster",
    
    -- 存储配置
    block_size = 30,
    enable_compression = true,
    compression_type = "lz4",
    
    -- 集群配置
    seed_nodes = {"node1:9090", "node2:9090", "node3:9090"},
    gossip_port = 9090,
    data_port = 9091,
    consul_endpoints = {"http://127.0.0.1:8500"},
    replication_factor = 3,
    virtual_nodes_per_physical = 100,
    
    -- 高可用配置
    enable_ha = true,
    heartbeat_interval = 5,  -- 5秒
    failure_detection_timeout = 30  -- 30秒
}
```

## 🎯 总结

V3存储引擎通过插件化架构设计，提供了灵活且高性能的时间序列数据存储解决方案。基础版本适合单机部署场景，集成版本则提供了完整的分布式集群功能。整个系统在设计上考虑了性能、可靠性和可扩展性，为不同规模的业务需求提供了合适的解决方案。

关键特性总结：
- ✅ 插件化架构，支持多种存储引擎实现
- ✅ 30秒定长块存储，优化查询性能
- ✅ 冷热数据分离，降低存储成本
- ✅ 一致性哈希分片，支持水平扩展
- ✅ 完善的监控和运维支持
- ✅ 丰富的性能优化选项