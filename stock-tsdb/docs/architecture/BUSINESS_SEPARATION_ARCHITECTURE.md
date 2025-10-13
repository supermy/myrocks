# 业务数据分离架构文档

## 概述

本项目实现了股票行情、IOT、金融行情、订单、支付、库存、短信下发等业务数据的独立数据库实例管理，确保不同业务数据互不干扰，实现数据隔离和性能优化。

## 架构设计

### 1. 核心组件

#### 1.1 业务实例管理器 (BusinessInstanceManager)
- **位置**: `lua/business_instance_manager.lua`
- **功能**: 负责管理所有业务实例的生命周期
- **特性**:
  - 实例启动/停止控制
  - 健康状态监控
  - 配置动态加载
  - 故障自动恢复

#### 1.2 业务路由管理器 (BusinessRouter)
- **位置**: `lua/business_router.lua`
- **功能**: 负责将业务请求路由到对应的数据库实例
- **特性**:
  - 基于键前缀的自动业务类型识别
  - 路由缓存机制
  - 批量请求优化
  - 健康检查

#### 1.3 统一数据访问层 (UnifiedDataAccess)
- **位置**: `lua/unified_data_access.lua`
- **功能**: 为上层应用提供透明的多实例访问接口
- **特性**:
  - 自动路由透明化
  - 数据缓存机制
  - 批量操作支持
  - 统计监控

### 2. 业务实例配置

#### 2.1 配置文件
- **位置**: `business_instance_config.json`
- **内容**: 定义7个业务实例的详细配置

#### 2.2 业务实例列表

| 业务类型 | 端口 | 数据目录 | 压缩算法 | 最大连接数 | 冷热分离 |
|---------|------|----------|----------|------------|----------|
| 股票行情 | 6380 | ./data/stock_quotes | lz4 | 100 | 启用 |
| IOT数据 | 6381 | ./data/iot_data | snappy | 200 | 启用 |
| 金融行情 | 6382 | ./data/financial_quotes | lz4 | 150 | 启用 |
| 订单数据 | 6383 | ./data/orders | zstd | 50 | 禁用 |
| 支付数据 | 6384 | ./data/payments | zstd | 50 | 禁用 |
| 库存数据 | 6385 | ./data/inventory | snappy | 30 | 禁用 |
| 短信下发 | 6386 | ./data/sms | lz4 | 100 | 启用 |

### 3. 数据访问模式

#### 3.1 键命名规范
每个业务使用特定的键前缀：
- 股票行情: `stock:`
- IOT数据: `iot:`
- 金融行情: `financial:`
- 订单数据: `order:`
- 支付数据: `payment:`
- 库存数据: `inventory:`
- 短信下发: `sms:`

#### 3.2 自动路由机制
统一数据访问层根据键前缀自动识别业务类型，并将请求路由到对应的数据库实例。

## 使用方式

### 1. 启动所有业务实例
```bash
luajit start_business_instances.lua
```

### 2. 使用统一数据访问层
```lua
local UnifiedDataAccess = require "unified_data_access"
local data_access = UnifiedDataAccess:new()

-- 设置数据（自动路由）
data_access:set("stock:SH600000", stock_data)
data_access:set("iot:sensor:001", iot_data)

-- 获取数据（自动路由）
local stock_value = data_access:get("stock:SH600000")
local iot_value = data_access:get("iot:sensor:001")

-- 批量操作
local batch_results = data_access:mget({"stock:SH600000", "iot:sensor:001"})
```

### 3. 运行演示脚本
```bash
luajit demo_business_separation.lua
```

## 性能优化特性

### 1. 缓存机制
- 支持数据缓存，减少数据库访问
- 可配置的TTL时间
- 缓存命中率监控

### 2. 批量操作
- 支持批量获取和设置
- 按业务类型分组优化
- 减少网络开销

### 3. 连接池
- 每个实例独立的连接池
- 连接数限制和超时控制
- 连接复用优化

## 监控和管理

### 1. 健康检查
- 实例可达性检查
- 自动故障检测
- 状态监控面板

### 2. 统计信息
- 请求成功率统计
- 缓存命中率统计
- 性能指标监控

### 3. 配置管理
- 动态配置重载
- 运行时参数调整
- 配置版本控制

## 测试验证

### 1. 功能测试
- 数据路由正确性
- 缓存功能验证
- 批量操作测试

### 2. 性能测试
- 单实例性能基准
- 多实例并发测试
- 缓存效果评估

### 3. 集成测试
- 与现有系统集成
- 业务场景验证
- 故障恢复测试

## 部署说明

### 1. 环境要求
- LuaJIT 2.0+
- cjson.so 库文件
- 足够的磁盘空间
- 网络端口可用性

### 2. 目录结构
```
stock-tsdb/
├── lua/                    # Lua脚本目录
│   ├── business_instance_manager.lua
│   ├── business_router.lua
│   └── unified_data_access.lua
├── data/                   # 数据目录
│   ├── stock_quotes/       # 股票行情数据
│   ├── iot_data/          # IOT数据
│   └── ...                # 其他业务数据
├── lib/                    # 库文件目录
│   └── cjson.so           # JSON解析库
├── business_instance_config.json  # 实例配置
├── start_business_instances.lua    # 启动脚本
├── demo_business_separation.lua    # 演示脚本
└── test_business_instances.lua     # 测试脚本
```

## 优势总结

1. **数据隔离**: 每个业务数据完全独立，互不干扰
2. **性能优化**: 根据业务特性定制化配置
3. **可扩展性**: 支持新业务实例的快速添加
4. **透明访问**: 上层应用无需关心底层实例分布
5. **监控完善**: 全面的健康检查和性能监控
6. **容错性强**: 自动故障检测和恢复机制

## 后续规划

1. **集群支持**: 实现实例的分布式部署
2. **负载均衡**: 动态流量分配和负载管理
3. **数据迁移**: 在线数据迁移和重新平衡
4. **安全增强**: 访问控制和加密传输
5. **容器化**: Docker容器化部署支持

---

*本文档最后更新: 2024-01-15*