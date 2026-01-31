# TSDB 组件使用指南

## 概述

本文档提供 stock-tsdb 项目中各组件的详细使用说明，包括代码示例和最佳实践。

---

## 目录

1. [存储引擎组件](#存储引擎组件)
2. [负载均衡组件](#负载均衡组件)
3. [监控组件](#监控组件)
4. [连接池组件](#连接池组件)
5. [容错组件](#容错组件)
6. [配置管理组件](#配置管理组件)
7. [安全管理组件](#安全管理组件)
8. [部署管理组件](#部署管理组件)
9. [性能测试组件](#性能测试组件)

---

## 存储引擎组件

### V3 RocksDB 存储引擎

**文件**: `lua/tsdb_storage_engine_v3_rocksdb.lua`

#### 基本使用

```lua
local V3StorageEngineRocksDB = require("lua.tsdb_storage_engine_v3_rocksdb")

-- 创建存储引擎实例
local engine = V3StorageEngineRocksDB:new({
    data_dir = "./data",
    use_rocksdb = true,
    enable_read_cache = true,
    read_cache_size = 500
})

-- 初始化
local success = engine:initialize()
if not success then
    error("存储引擎初始化失败")
end
```

#### 数据写入

```lua
-- 单点写入
local success = engine:write_point(
    "stock_price",           -- 指标名
    os.time(),               -- 时间戳
    100.5,                   -- 值
    {symbol = "AAPL", market = "NASDAQ"}  -- 标签
)

-- 批量写入
local batch_points = {
    {metric = "stock_price", timestamp = os.time(), value = 100.5, tags = {symbol = "AAPL"}},
    {metric = "stock_price", timestamp = os.time() + 1, value = 101.0, tags = {symbol = "AAPL"}},
    {metric = "stock_price", timestamp = os.time() + 2, value = 101.5, tags = {symbol = "AAPL"}}
}
local success_count = engine:batch_write(batch_points)
```

#### 数据查询

```lua
-- 单点查询
local success, results = engine:read_point(
    "stock_price",
    os.time() - 3600,  -- 1小时前
    os.time(),          -- 现在
    {symbol = "AAPL"}
)

if success then
    for _, point in ipairs(results) do
        print(string.format("时间: %s, 值: %f", 
            os.date("%Y-%m-%d %H:%M:%S", point.timestamp), 
            point.value))
    end
end
```

#### 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| data_dir | string | "./data" | 数据目录 |
| use_rocksdb | boolean | true | 是否使用RocksDB |
| enable_read_cache | boolean | true | 启用读取缓存 |
| read_cache_size | number | 500 | 缓存大小 |
| max_read_process | number | 5000 | 最大读取处理数 |

---

## 核心优化组件

### 二进制序列化器

**文件**: `lua/binary_serializer.lua`

**重构日期**: 2026-01-31

#### 快速开始

```lua
local BinarySerializer = require("lua.binary_serializer")

-- 创建序列化器实例
local serializer = BinarySerializer:new()

-- 序列化数据
local data = {
    value = 123.45,
    tags = {host = "server1", region = "us-east"},
    timestamp = os.time()
}
local serialized = serializer:serialize(data)

-- 反序列化
local deserialized = serializer:deserialize(serialized)
```

#### 支持的类型

| 类型标记 | Lua类型 | 说明 |
|---------|---------|------|
| 0x00 | nil | 空值 |
| 0x01 | boolean | true/false |
| 0x02 | number (integer) | 变长整数编码 |
| 0x03 | number (double) | 8字节浮点数 |
| 0x04 | string | 长度前缀字符串 |
| 0x05 | table | 哈希表 |
| 0x06 | array | 数组 |

#### 整数编码优化

```lua
-- 自动选择最优整数类型
INT8:   -128 ~ 127          (1字节)
INT16:  -32768 ~ 32767      (2字节)
INT32:  -21亿 ~ 21亿        (4字节)
INT64:  更大范围            (8字节)
```

#### 重构改进

- **代码分区**: 清晰的常量、构造函数、编码器、解码器、工具函数分区
- **解码器映射**: 使用 `_decoders` 表提高可维护性
- **类型推断**: 自动选择最优整数编码
- **预热机制**: 提高基准测试准确性

---

### LRU缓存

**文件**: `lua/lrucache.lua`

**重构日期**: 2026-01-31

#### 快速开始

```lua
local LRUCache = require("lua.lrucache")

-- 创建缓存实例
local cache = LRUCache:new({
    max_size = 100000,      -- 最大条目数
    default_ttl = 300       -- 默认5分钟过期
})

-- 基本操作
cache:set("key1", "value1")           -- 使用默认TTL
cache:set("key2", "value2", 60)       -- 自定义60秒TTL

local value = cache:get("key1")       -- 获取值
local exists = cache:has("key1")      -- 检查存在
local count = cache:count()           -- 获取条目数

-- 删除操作
cache:delete("key1")                  -- 删除单个
cache:clear()                         -- 清空缓存
```

#### 统计信息

```lua
local stats = cache:get_stats()
print(string.format("命中率: %.2f%%", stats.hit_rate * 100))
print(string.format("总请求: %d", stats.total_requests))
print(string.format("淘汰数: %d", stats.evictions))
print(string.format("过期数: %d", stats.expirations))
```

#### 重构改进

- **链表操作**: 提取 `_remove_from_list` 公共方法消除重复代码
- **过期优化**: 使用局部变量缓存 `os.time()` 减少函数调用
- **新增方法**: `count()` 和 `has()` 提高API可用性
- **统计增强**: 添加 `total_requests` 字段完善追踪

---

### 流式合并器

**文件**: `lua/streaming_merger.lua`

**重构日期**: 2026-01-31

#### 快速开始

```lua
local StreamingMerger = require("lua.streaming_merger")

-- 创建合并器（带比较函数）
local merger = StreamingMerger:new(function(a, b)
    return a.timestamp < b.timestamp  -- 按时间戳升序
end)

-- 添加数据源
local array1 = {{timestamp = 1, value = 10}, {timestamp = 3, value = 30}}
local array2 = {{timestamp = 2, value = 20}, {timestamp = 4, value = 40}}

merger:add_source("source1", StreamingMerger.create_array_iterator(array1))
merger:add_source("source2", StreamingMerger.create_array_iterator(array2))

-- 流式获取（内存友好）
while true do
    local item = merger:next()
    if not item then break end
    print(string.format("时间: %d, 值: %d", item.timestamp, item.value))
end

-- 或一次性收集
local all_items = merger:collect_all()
```

#### 静态合并方法

```lua
-- 合并多个已排序数组
local arrays = {
    {{timestamp = 1}, {timestamp = 3}},
    {{timestamp = 2}, {timestamp = 4}},
    {{timestamp = 5}}
}

local merged = StreamingMerger.merge_sorted_arrays(arrays, function(a, b)
    return a.timestamp < b.timestamp
end)
```

#### 重构改进

- **堆优化**: 优化 `_sift_up` 和 `_sift_down` 算法，使用局部变量减少表访问
- **新增方法**: `collect_all()` 替代内联循环，提高代码复用性
- **迭代器优化**: `create_array_iterator` 使用局部变量缓存数组长度
- **预热机制**: 提高基准测试准确性

---

## 负载均衡组件

### 智能负载均衡器

**文件**: `lua/smart_load_balancer.lua`

#### 快速开始

```lua
local SmartLoadBalancer = require("lua.smart_load_balancer")

-- 创建负载均衡器
local lb = SmartLoadBalancer:new({
    algorithm = "adaptive",
    health_check_interval = 10000
})

-- 添加后端节点
lb:add_node("node1", {
    host = "192.168.1.1",
    port = 8080,
    weight = 3,
    max_connections = 100
})

lb:add_node("node2", {
    host = "192.168.1.2",
    port = 8080,
    weight = 2,
    max_connections = 100
})

lb:add_node("node3", {
    host = "192.168.1.3",
    port = 8080,
    weight = 1,
    max_connections = 100
})
```

#### 选择节点

```lua
-- 选择节点处理请求
local node = lb:select_node()
if node then
    -- 发送请求到选中节点
    local response, latency = send_request(node.host, node.port)
    
    -- 更新节点指标
    lb:update_node_metrics(node.id, latency, response.success)
else
    -- 无可用节点
    error("无健康节点可用")
end
```

#### 算法切换

```lua
-- 支持的算法: round_robin, weighted_rr, least_conn, least_time, adaptive
lb:switch_algorithm("least_response_time")

-- 获取当前算法
print("当前算法: " .. lb.algorithm)

-- 获取支持的算法列表
local algorithms = SmartLoadBalancer.get_supported_algorithms()
for _, algo in ipairs(algorithms) do
    print("支持算法: " .. algo)
end
```

#### 健康检查

```lua
-- 手动触发健康检查
lb:health_check()

-- 获取健康节点
local healthy_nodes = lb:get_healthy_nodes()
print(string.format("健康节点数: %d", #healthy_nodes))

-- 获取统计信息
local stats = lb:get_stats()
print(string.format("总请求数: %d", stats.stats.total_requests))
print(string.format("成功率: %.2f%%", 
    (stats.stats.successful_requests / stats.stats.total_requests) * 100))
```

---

## 监控组件

### 性能监控器

**文件**: `lua/performance_monitor.lua`

#### 快速开始

```lua
local PerformanceMonitor = require("lua.performance_monitor")

-- 创建监控器
local monitor = PerformanceMonitor:new({
    enabled = true,
    collection_interval = 5000,  -- 5秒收集一次
    retention_period = 3600       -- 保留1小时
})
```

#### 添加告警规则

```lua
-- CPU使用率告警
monitor:add_alert_rule({
    name = "CPU高使用率",
    metric_type = "system",
    metric_name = "cpu_usage",
    operator = ">",
    threshold = 80,
    duration = 60  -- 持续60秒触发
})

-- 内存使用率告警
monitor:add_alert_rule({
    name = "内存不足",
    metric_type = "system",
    metric_name = "memory_usage",
    operator = ">",
    threshold = 85,
    duration = 30
})

-- 错误率告警
monitor:add_alert_rule({
    name = "高错误率",
    metric_type = "application",
    metric_name = "error_rate",
    operator = ">",
    threshold = 5,  -- 5%
    duration = 120
})
```

#### 收集指标

```lua
-- 收集所有指标
local metrics = monitor:collect_all_metrics(storage_engine)

-- 访问指标
print("CPU使用率: " .. metrics.system.cpu_usage .. "%")
print("内存使用率: " .. metrics.system.memory_usage .. "%")
print("活跃连接: " .. metrics.application.active_connections)
print("缓存命中率: " .. metrics.storage.cache_hit_rate .. "%")
```

#### 生成报告

```lua
-- 生成监控报告
local report = monitor:get_report(3600)  -- 最近1小时

-- 访问报告数据
print("总收集次数: " .. report.summary.total_collections)
print("总告警数: " .. report.summary.total_alerts)

-- 查看趋势
for metric, trend in pairs(report.trends) do
    print(string.format("%s 趋势: %s", metric, trend))
end

-- 查看建议
for _, recommendation in ipairs(report.recommendations) do
    print("建议: " .. recommendation)
end
```

---

## 连接池组件

### 连接池管理器

**文件**: `lua/connection_pool.lua`

#### 快速开始

```lua
local ConnectionPool = require("lua.connection_pool")

-- 创建连接池
local pool = ConnectionPool:new({
    max_pool_size = 20,
    min_pool_size = 5,
    connection_timeout = 5000,   -- 5秒超时
    idle_timeout = 300000,       -- 5分钟空闲超时
    max_lifetime = 3600000       -- 1小时最大生命周期
})
```

#### 使用连接

```lua
-- 定义连接工厂
local function create_connection()
    -- 创建实际连接（例如Redis、数据库等）
    return {
        id = generate_connection_id(),
        socket = create_socket(),
        connect = function(self, host, port)
            -- 连接逻辑
        end,
        close = function(self)
            -- 关闭逻辑
        end,
        is_valid = function(self)
            -- 验证连接有效性
            return true
        end
    }
end

-- 获取连接
local conn, err = pool:borrow_connection("redis_primary", create_connection)
if not conn then
    error("获取连接失败: " .. err)
end

-- 使用连接
local result = conn:query("GET key")

-- 归还连接（必须）
pool:return_connection(conn)
```

#### 最佳实践

```lua
-- 使用 pcall 确保连接归还
local conn = pool:borrow_connection("target")
if conn then
    local ok, result = pcall(function()
        return conn:execute_query("SELECT * FROM data")
    end)
    
    pool:return_connection(conn)  -- 确保归还
    
    if ok then
        return result
    else
        error(result)
    end
end
```

#### 监控连接池

```lua
-- 获取统计信息
local stats = pool:get_stats()
print(string.format("总创建: %d", stats.global_stats.total_created))
print(string.format("当前活跃: %d", stats.global_stats.current_active))
print(string.format("当前空闲: %d", stats.global_stats.current_idle))

-- 清理过期连接
local cleaned = pool:cleanup_expired_connections()
print(string.format("清理连接: %d", cleaned))
```

---

## 容错组件

### 容错管理器

**文件**: `lua/fault_tolerance_manager.lua`

#### 快速开始

```lua
local FaultToleranceManager = require("lua.fault_tolerance_manager")

-- 创建容错管理器
local ft = FaultToleranceManager:new({
    heartbeat_interval = 30000,   -- 30秒心跳
    timeout_threshold = 3,        -- 3次超时标记为不健康
    suspect_threshold = 2,        -- 2次超时标记为可疑
    recovery_timeout = 300000     -- 5分钟恢复超时
})
```

#### 注册节点

```lua
-- 注册主节点
ft:register_node("tsdb-primary", {
    host = "192.168.1.10",
    port = 8080,
    role = "primary"
})

-- 注册备份节点
ft:register_node("tsdb-backup-1", {
    host = "192.168.1.11",
    port = 8080,
    role = "backup",
    backup_for = "tsdb-primary"
})

ft:register_node("tsdb-backup-2", {
    host = "192.168.1.12",
    port = 8080,
    role = "backup",
    backup_for = "tsdb-primary"
})
```

#### 心跳处理

```lua
-- 服务端：接收心跳
function on_heartbeat_received(node_id)
    ft:handle_heartbeat(node_id)
end

-- 客户端：发送心跳
function send_heartbeat(node_id)
    -- 定期发送心跳
    while true do
        send_to_server({type = "heartbeat", node_id = node_id})
        sleep(30000)  -- 30秒间隔
    end
end
```

#### 健康检查

```lua
-- 定期检查所有节点
function check_all_nodes()
    local results = ft:check_all_nodes_health()
    
    print(string.format("健康: %d, 可疑: %d, 不健康: %d, 离线: %d",
        results.healthy,
        results.suspect,
        results.unhealthy,
        results.offline))
    
    -- 获取健康节点列表
    local healthy_nodes = ft:get_healthy_nodes()
    for _, node_id in ipairs(healthy_nodes) do
        print("健康节点: " .. node_id)
    end
end
```

#### 故障转移

```lua
-- 手动触发故障转移（通常自动触发）
local success, new_primary = ft:trigger_failover("tsdb-primary")
if success then
    print("故障转移成功，新主节点: " .. new_primary)
else
    print("故障转移失败")
end

-- 执行数据同步
ft:execute_data_sync()
```

---

## 配置管理组件

### 高级配置管理器

**文件**: `lua/config_manager_advanced.lua`

#### 快速开始

```lua
local ConfigManagerAdvanced = require("lua.config_manager_advanced")

-- 创建配置管理器
local config = ConfigManagerAdvanced:new({
    config_file = "config/app.json",
    auto_save = true,
    max_history = 50
})

-- 加载配置
config:load()
```

#### 配置操作

```lua
-- 设置配置
config:set("database.host", "localhost")
config:set("database.port", 3306)
config:set("database.name", "stock_tsdb")

-- 嵌套配置
config:set("cache.redis.host", "127.0.0.1")
config:set("cache.redis.port", 6379)

-- 获取配置
local db_host = config:get("database.host")           -- "localhost"
local db_port = config:get("database.port")           -- 3306
local timeout = config:get("database.timeout", 30)    -- 30 (默认值)

-- 批量设置
config:set_batch({
    ["logging.level"] = "info",
    ["logging.format"] = "json",
    ["logging.output"] = "stdout"
})
```

#### 配置验证

```lua
-- 注册验证器
config:register_validator("database.port", function(value)
    if type(value) ~= "number" then
        return false, "端口必须是数字"
    end
    if value < 1 or value > 65535 then
        return false, "端口范围 1-65535"
    end
    return true
end)

-- 注册范围验证器
config:register_validator("logging.level", function(value)
    local valid_levels = {debug = true, info = true, warn = true, error = true}
    if not valid_levels[value] then
        return false, "日志级别必须是 debug/info/warn/error"
    end
    return true
end)

-- 设置时会自动验证
local success, err = config:set("database.port", 70000)
if not success then
    print("设置失败: " .. err)  -- "端口范围 1-65535"
end
```

#### 配置监听

```lua
-- 注册配置变更监听器
config:register_watcher("database.*", function(key, old_val, new_val)
    print(string.format("配置变更: %s = %s (旧值: %s)", 
        key, tostring(new_val), tostring(old_val)))
    
    -- 重新加载数据库连接
    if key == "database.host" or key == "database.port" then
        reload_database_connection()
    end
end)
```

#### 版本控制

```lua
-- 查看配置历史
local history = config:get_history("database.host", 10)
for _, entry in ipairs(history) do
    print(string.format("[%s] %s = %s",
        os.date("%Y-%m-%d %H:%M:%S", entry.timestamp),
        entry.key,
        tostring(entry.value)))
end

-- 回滚配置
config:rollback(1)  -- 回滚1步
config:rollback(3)  -- 回滚3步
```

#### 导入导出

```lua
-- 导出配置
local json_config = config:export("json")
local lua_config = config:export("lua")

-- 导入配置
config:import(json_string, "json", {
    merge = true,           -- 合并而非替换
    skip_validation = false -- 验证导入的配置
})
```

---

## 安全管理组件

### 安全管理器

**文件**: `lua/security_manager.lua`

#### 快速开始

```lua
local SecurityManager = require("lua.security_manager")

-- 创建安全管理器
local security = SecurityManager:new({
    enabled = true,
    token_expiry = 3600,        -- 1小时
    max_login_attempts = 5,     -- 5次尝试
    lockout_duration = 300      -- 锁定5分钟
})
```

#### 用户管理

```lua
-- 注册用户
local success, err = security:register_user(
    "john_doe",
    "SecurePass123",
    "USER",
    {email = "john@example.com", department = "engineering"}
)

if not success then
    print("注册失败: " .. err)
end

-- 密码要求：
-- - 至少8位
-- - 包含数字
-- - 包含字母
```

#### 认证流程

```lua
-- 用户登录
local success, token, session = security:login(
    "john_doe",
    "SecurePass123",
    {ip = "192.168.1.100", user_agent = "Mozilla/5.0"}
)

if success then
    print("登录成功，令牌: " .. token)
    -- 保存令牌用于后续请求
else
    print("登录失败: " .. token)  -- token参数此时是错误信息
end

-- 验证令牌
local valid, session_info = security:validate_token(token)
if valid then
    print("用户: " .. session_info.username)
    print("角色: " .. session_info.role)
else
    print("令牌无效: " .. session_info)
end

-- 用户登出
security:logout(token)
```

#### 权限控制

```lua
-- 检查权限
local has_read = security:check_permission(token, "read")
local has_write = security:check_permission(token, "write")
local has_admin = security:check_permission(token, "admin")

-- 根据权限执行操作
if has_write then
    -- 执行写操作
    write_data(data)
else
    error("权限不足")
end
```

#### API密钥

```lua
-- 生成API密钥（30天有效期）
local api_key = security:generate_api_key(
    "john_doe",
    {"read", "write"},  -- 权限
    30                   -- 有效期（天）
)

-- 验证API密钥
local valid, key_info = security:validate_api_key(api_key)
if valid then
    print("API密钥有效")
    print("所属用户: " .. key_info.username)
else
    print("API密钥无效")
end
```

#### 数据加密

```lua
-- 加密敏感数据
local sensitive_data = "信用卡号: 1234-5678-9012-3456"
local encrypted = security:encrypt(sensitive_data, "my_secret_key")

-- 解密数据
local decrypted = security:decrypt(encrypted, "my_secret_key")
print(decrypted)  -- "信用卡号: 1234-5678-9012-3456"
```

#### 审计日志

```lua
-- 查询审计日志
local logs = security:get_audit_logs({
    username = "john_doe",
    event_type = "LOGIN_SUCCESS",
    start_time = os.time() - 86400,  -- 最近24小时
    limit = 100
})

for _, log in ipairs(logs) do
    print(string.format("[%s] %s: %s",
        os.date("%Y-%m-%d %H:%M:%S", log.timestamp),
        log.event_type,
        log.description))
end
```

---

## 部署管理组件

### 部署管理器

**文件**: `lua/deployment_manager.lua`

#### 快速开始

```lua
local DeploymentManager = require("lua.deployment_manager")

-- 创建部署管理器
local deploy = DeploymentManager:new({
    environment = "production",
    version = "2.0.0",
    work_dir = "/opt/stock-tsdb",
    backup_dir = "/opt/backups"
})
```

#### 生成容器配置

```lua
-- 生成Docker配置
local configs = deploy:generate_docker_config({
    replicas = 3
})

-- Dockerfile
print(configs.dockerfile)

-- Docker Compose
print(configs.docker_compose)

-- Kubernetes
print(configs.kubernetes)

-- 保存到文件
local file = io.open("Dockerfile", "w")
file:write(configs.dockerfile)
file:close()
```

#### 执行部署

```lua
-- 执行部署
local success, deployment = deploy:deploy({
    version = "2.1.0",
    auto_rollback = true,       -- 失败自动回滚
    skip_backup = false,        -- 执行备份
    health_check = true         -- 部署后健康检查
})

if success then
    print("部署成功: " .. deployment.id)
    print("耗时: " .. (deployment.completed_at - deployment.started_at) .. "秒")
else
    print("部署失败，已自动回滚")
end
```

#### 健康检查

```lua
-- 执行健康检查
local health = deploy:health_check()

print("整体状态: " .. health.overall_status)

for check_name, check_result in pairs(health.checks) do
    print(string.format("%s: %s", 
        check_name, 
        check_result.status))
    
    if check_result.status == "fail" then
        print("  详情: " .. tostring(check_result.details))
    end
end
```

#### 部署历史

```lua
-- 获取部署历史
local history = deploy:get_deployment_history({
    status = "success",         -- 成功的部署
    environment = "production", -- 生产环境
    limit = 10                  -- 最近10次
})

for _, deployment in ipairs(history) do
    print(string.format("[%s] %s - %s",
        os.date("%Y-%m-%d %H:%M", deployment.started_at),
        deployment.version,
        deployment.status))
end
```

---

## 性能测试组件

### 性能基准测试工具

**文件**: `lua/performance_benchmark.lua`

#### 快速开始

```lua
local PerformanceBenchmark = require("lua.performance_benchmark")

-- 创建基准测试工具
local benchmark = PerformanceBenchmark:new({
    test_duration = 60,      -- 测试60秒
    warmup_duration = 10,    -- 预热10秒
    concurrency = 10         -- 10并发
})
```

#### 运行完整测试

```lua
-- 运行所有测试场景
local report = benchmark:run_full_benchmark(storage_engine)

-- 查看摘要
print("测试场景数: " .. report.summary.total_scenarios)
print("平均吞吐量: " .. report.summary.avg_throughput .. " ops/s")
print("平均延迟: " .. report.summary.avg_latency .. " ms")
```

#### 运行单个场景

```lua
-- 定义测试场景
local scenario = {
    name = "高并发写入测试",
    type = "write",
    concurrent = 50,
    batch_size = 100,
    duration = 60
}

-- 执行测试
local result = benchmark:run_scenario(scenario, storage_engine)

-- 查看结果
print("场景: " .. result.name)
print("状态: " .. result.status)
print("总操作数: " .. result.metrics.total_operations)
print("成功率: " .. result.metrics.success_rate .. "%")
print("吞吐量: " .. result.metrics.throughput_ops .. " ops/s")
print("平均延迟: " .. result.metrics.avg_latency_ms .. " ms")
print("P95延迟: " .. result.metrics.p95_latency_ms .. " ms")
print("P99延迟: " .. result.metrics.p99_latency_ms .. " ms")
```

#### 测试场景类型

```lua
-- 写入测试
local write_scenario = {
    name = "批量写入",
    type = "write",
    concurrent = 10,
    batch_size = 100
}

-- 读取测试
local read_scenario = {
    name = "范围查询",
    type = "read",
    concurrent = 10,
    time_range = "1h"  -- 1小时范围
}

-- 混合测试
local mixed_scenario = {
    name = "读写混合",
    type = "mixed",
    write_ratio = 0.3,   -- 30%写入
    read_ratio = 0.7,    -- 70%读取
    concurrent = 20
}

-- 压力测试
local stress_scenario = {
    name = "极限压力",
    type = "stress",
    concurrent = 100,
    duration = 300       -- 5分钟
}
```

#### 生成报告

```lua
-- 导出JSON报告
local json_report = benchmark:export_report(report, "json")
local file = io.open("benchmark_report.json", "w")
file:write(json_report)
file:close()

-- 导出HTML报告
local html_report = benchmark:export_report(report, "html")
local file = io.open("benchmark_report.html", "w")
file:write(html_report)
file:close()
```

---

## 最佳实践

### 1. 组件组合使用

```lua
-- 完整示例：构建高可用TSDB服务
local SmartLoadBalancer = require("lua.smart_load_balancer")
local PerformanceMonitor = require("lua.performance_monitor")
local FaultToleranceManager = require("lua.fault_tolerance_manager")
local SecurityManager = require("lua.security_manager")

-- 初始化各组件
local lb = SmartLoadBalancer:new({algorithm = "adaptive"})
local monitor = PerformanceMonitor:new({enabled = true})
local ft = FaultToleranceManager:new({})
local security = SecurityManager:new({enabled = true})

-- 注册节点并设置监控
for i = 1, 3 do
    local node_id = "node" .. i
    lb:add_node(node_id, {host = "192.168.1." .. i, port = 8080})
    ft:register_node(node_id, {host = "192.168.1." .. i, role = i == 1 and "primary" or "backup"})
end

-- 处理请求
function handle_request(request)
    -- 认证
    local valid, session = security:validate_token(request.token)
    if not valid then
        return {error = "未授权"}
    end
    
    -- 选择节点
    local node = lb:select_node()
    if not node then
        return {error = "无可用节点"}
    end
    
    -- 执行请求
    local start_time = os.clock()
    local result = process_on_node(node, request)
    local latency = (os.clock() - start_time) * 1000
    
    -- 更新指标
    lb:update_node_metrics(node.id, latency, result.success)
    monitor:collect_all_metrics()
    
    return result
end
```

### 2. 错误处理

```lua
-- 始终使用 pcall 保护关键操作
local ok, result = pcall(function()
    return component:risky_operation()
end)

if not ok then
    -- 记录错误
    logger:error("操作失败: " .. tostring(result))
    -- 降级处理
    return fallback_operation()
end
```

### 3. 资源清理

```lua
-- 确保资源正确释放
local pool = ConnectionPool:new({})
local conn = pool:borrow_connection("target")

local ok, result = pcall(function()
    return conn:execute()
end)

-- 确保归还连接
pool:return_connection(conn)

if not ok then
    error(result)
end
```

---

## 故障排除

### 常见问题

#### 1. 连接池耗尽
```lua
-- 增加连接池大小
local pool = ConnectionPool:new({
    max_pool_size = 50,  -- 增加上限
    min_pool_size = 10   -- 保持最小连接
})
```

#### 2. 负载不均衡
```lua
-- 切换到自适应算法
lb:switch_algorithm("adaptive")

-- 调整节点权重
lb:add_node("node1", {weight = 5})  -- 更高权重
```

#### 3. 频繁告警
```lua
-- 调整告警阈值
monitor:add_alert_rule({
    name = "CPU告警",
    threshold = 90,      -- 提高阈值
    duration = 120       -- 延长持续时间
})
```

---

## 参考文档

- [优化方案完整指南](../OPTIMIZATION_SCHEMES_COMPLETE_GUIDE.md)
- [V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md)
- [项目文档索引](../DOCUMENTATION_INDEX.md)
