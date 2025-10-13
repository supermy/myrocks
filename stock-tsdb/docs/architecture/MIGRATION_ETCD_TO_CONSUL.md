# 从 etcd 迁移到 Consul FFI 完成说明

本文档描述了项目中 etcd 实现已完全替换为基于 FFI 的 Consul 客户端的迁移完成情况。

## 概述

etcd 到 Consul 的迁移已经完成，项目中所有 etcd 相关代码已被清理和替换：

1. **consul_ffi.lua** - 基于 LuaJIT FFI 的 Consul 客户端（已替换 etcd_ffi.lua）
2. **consul_ha_cluster.lua** - 基于 Consul 的高可用集群管理（已替换 etcd_ha.lua）
3. **consistent_hash_cluster.lua** - 更新为使用 Consul 实现
4. **tsdb_storage_engine_integrated.lua** - 更新为引用 Consul 高可用
5. **tests/tsdb_cluster_test.lua** - 更新测试为 Consul 高可用
6. **docs/idea-tsdb-stock.md** - 更新文档说明为 Consul 高可用

## 迁移完成情况

### ✅ 已完成清理的 etcd 引用：

1. **consistent_hash_cluster.lua** - 清理了所有 etcd 相关注释和引用
2. **tsdb_storage_engine_integrated.lua** - 更新为 Consul 高可用
3. **tests/tsdb_cluster_test.lua** - 更新测试注释为 Consul 高可用
4. **docs/idea-tsdb-stock.md** - 更新文档为 Consul 高可用（已替换etcd）
5. **consul_ha_cluster.lua** - 移除了"替换原有的etcd实现"注释

### ✅ 状态确认：
- 项目中已无 etcd 相关模块文件（etcd_ffi.lua、etcd_ha.lua 等）
- 配置文件中无 etcd 相关配置
- Docker 配置中无 etcd 服务
- 所有代码注释中的 etcd 引用已更新为 Consul

## 主要变化（历史记录）

### 1. 客户端接口变化（已迁移）

#### 旧的 etcd 客户端 (etcd_ffi.lua)
```lua
local etcd = require("etcd_ffi")
local client = etcd.new({
    endpoints = {"http://127.0.0.1:2379"},
    timeout = 5000
})
```

#### 新的 Consul 客户端 (consul_ffi.lua)
```lua
local consul_ffi = require("consul_ffi")
local client = consul_ffi.new({
    endpoint = "http://127.0.0.1:8500",
    timeout = 5000,
    simulate = true  -- 模拟模式（可选）
})
```

### 2. HA 集群管理变化

#### 旧的 etcd HA 集群 (etcd_ha.lua)
```lua
local etcd_ha = require("etcd_ha")
local cluster = etcd_ha.new({
    node_id = "node1",
    node_address = "127.0.0.1:8081",
    etcd_endpoints = {"http://127.0.0.1:2379"}
})
```

#### 新的 Consul HA 集群 (consul_ha_cluster.lua)
```lua
local consul_ha_cluster = require("consul_ha_cluster")
local cluster = consul_ha_cluster.new({
    node_id = "node1",
    node_address = "127.0.0.1:8081",
    consul_endpoints = {"http://127.0.0.1:8500"},
    simulate = true  -- 模拟模式（可选）
})
```

## 功能对比

| 功能 | etcd 实现 | Consul 实现 | 状态 |
|------|-----------|-------------|------|
| KV 存储 | ✅ | ✅ | 已迁移 |
| 服务注册/发现 | ✅ | ✅ | 已迁移 |
| 分布式锁 | ✅ | ✅ | 已迁移 |
| Leader 选举 | ✅ | ✅ | 已迁移 |
| 一致性哈希 | ✅ | ✅ | 已迁移 |
| 节点管理 | ✅ | ✅ | 已迁移 |
| 健康检查 | ✅ | ✅ | 已迁移 |
| 会话管理 | ✅ | ✅ | 已迁移 |

## 迁移步骤

### 步骤 1: 替换模块引用

在需要使用 etcd 的地方，替换为 Consul 模块：

```lua
-- 旧代码
local etcd_ffi = require("etcd_ffi")
local etcd_ha = require("etcd_ha")

-- 新代码
local consul_ffi = require("consul_ffi")
local consul_ha_cluster = require("consul_ha_cluster")
```

### 步骤 2: 更新配置

将 etcd 相关配置改为 Consul 配置：

```lua
-- 旧配置
local etcd_config = {
    endpoints = {"http://127.0.0.1:2379"},
    timeout = 5000,
    retry_count = 3
}

-- 新配置
local consul_config = {
    endpoint = "http://127.0.0.1:8500",
    timeout = 5000,
    retry_count = 3,
    simulate = false  -- 生产环境设为 false
}
```

### 步骤 3: 更新 API 调用

#### KV 操作

```lua
-- 旧代码
etcd_client:set("/cluster/config", config_data)
local value, err = etcd_client:get("/cluster/config")
etcd_client:delete("/cluster/config")

-- 新代码
consul_client:kv_put("cluster/config", config_data)
local success, response = consul_client:kv_get("cluster/config")
consul_client:kv_delete("cluster/config")
```

#### 服务注册/发现

```lua
-- 旧代码
etcd_client:register_service(service_id, service_info)
local services = etcd_client:discover_services(service_name)

-- 新代码
consul_client:register_service(service_id, service_name, address, port, tags)
local success, services = consul_client:discover_services(service_name)
```

### 步骤 4: 更新集群管理代码

```lua
-- 旧代码
local cluster = etcd_ha.new({
    node_id = "node1",
    node_address = "127.0.0.1:8081",
    etcd_endpoints = {"http://127.0.0.1:2379"}
})

-- 新代码
local cluster = consul_ha_cluster.new({
    node_id = "node1",
    node_address = "127.0.0.1:8081",
    consul_endpoints = {"http://127.0.0.1:8500"}
})
```

## 测试

### 基本功能测试
```bash
# 运行 Consul FFI 调试脚本
luajit debug_consul_ffi.lua

# 运行集成测试
luajit test_consul_integration.lua
```

### 集群功能测试
```bash
# 启动多个 Consul 代理（生产环境）
consul agent -dev -bind=127.0.0.1 -client=127.0.0.1

# 运行集群测试
luajit test_consul_cluster.lua
```

## 生产环境部署

### 1. Consul 集群设置

在生产环境中，需要设置 Consul 集群：

```bash
# 启动 Consul 服务器（示例）
consul agent -server -bootstrap-expect=3 -data-dir=/tmp/consul -bind=10.0.1.1
```

### 2. 配置更新

确保在生产环境中关闭模拟模式：

```lua
local consul_config = {
    endpoint = "http://consul.service.consul:8500",
    timeout = 5000,
    retry_count = 3,
    simulate = false  -- 生产环境设为 false
}
```

### 3. 监控和日志

Consul 客户端提供了详细的日志输出，可以通过设置日志级别来控制输出：

```lua
-- 在代码中添加日志配置
local consul_config = {
    endpoint = "http://127.0.0.1:8500",
    timeout = 5000,
    log_level = "INFO"  -- DEBUG, INFO, WARN, ERROR
}
```

## 注意事项

1. **模拟模式**: 在开发环境中可以使用 `simulate = true` 来模拟 Consul 服务
2. **错误处理**: Consul 客户端返回 `(success, response)` 格式的结果，需要检查 `success` 标志
3. **超时设置**: 建议设置合理的超时时间，避免长时间阻塞
4. **重试机制**: 客户端内置了重试机制，可以通过 `retry_count` 配置

## 回滚计划（已过时）

**注意**：由于 etcd 相关代码已被完全清理，回滚到 etcd 实现需要：

1. 重新创建 etcd_ffi.lua 和 etcd_ha.lua 模块
2. 恢复所有被替换的 etcd 引用
3. 重新配置 etcd 集群
4. 验证与现有 Consul 实现的兼容性

建议继续使用 Consul 实现，如需回滚请联系开发团队。

## 支持

如果在迁移过程中遇到问题，可以：

1. 查看调试日志输出
2. 运行测试脚本验证功能
3. 检查 Consul 集群状态
4. 参考 Consul 官方文档

## 版本历史

- v2.0.0: **迁移完成版本** - etcd 相关代码已完全清理和替换
- v1.2.0: 添加集群管理功能，完善文档
- v1.1.0: 添加模拟模式支持，优化错误处理
- v1.0.0: 初始版本，基本功能迁移完成