# Stock-TSDB 项目设计文档

## 项目概述

采用 **一致性哈希 + ZeroMQ(LZMA-FFI) + RocksDB** 的 LuaJIT 编程实现 Open-TSDB，支持集群部署，通过 LuaJIT FFI 调用 Consul 实现高可用，专门用于股市行情数据处理。

借鉴 Kvrocks 处理元数据与数据 RocksDB 的 ColumnFamily（CF），按自然日分 ColumnFamily，实现冷热数据分离。

**核心特性：** 30秒定长块 + 微秒列偏移，优化达到生产级别使用。

## 开发策略

**先性能优化，再配置多业务；先集群，再 Redis 接口**

## 系统架构

### 分片时序集群数据库设计

* **数据分区**：采用一致性哈希算法
* **业务逻辑**：Lua 脚本实现，支持配置化和热更新
* **数据存储**：RocksDB（分块 + 列偏移）
* **分布式集群**：ZeroMQ 实现
* **高可用**：Consul 服务发现

## 关键技术点

### 1. LuaJIT FFI 集成

```bash
luarocks install --local lzmq-ffi
lzmq-ffi
luajit rocksdb
luajit consul
```

### 2. ZeroMQ 消息中间件

通过 `PUSH/PULL` 模式构建分布式线程池。

### 3. RowKey + Qualifier 机制

**`30秒定长块 + 微秒列偏移`**

可以通过 LuaJIT 定制不同业务的 rowkey+value，支持热更新。

### 4. 冷热数据分离

#### 借鉴 Kvrocks 的元数据与数据 CF 处理

##### * 按自然日分 ColumnFamily（CF）

```
每天自动新建一个 CF
冷数据 CF 可单独设置 ZSTD 压缩 + 关闭自动 Compaction
想删 30 天前数据，直接 Drop 整个 CF，秒级完成，不产生 Compaction 抖动。
```

##### * 按市场分 DB 实例

## 接口设计

### Redis 兼容接口

* **网络层**：LuaJIT FFI + libevent 建立 6379 接口
* **事件驱动**：libevent 实现
* **数据接口**：提供批量数据接口
* **集成测试**：联调集成版与 Redis 接口
* **测试验证**：Lua5.2 + socket 测试 6379 接口

## 配置管理

### 元数据管理（Makefile）

```
元数据初始化
查询列表
元数据修改
```

## 业务支持

### 多业务隔离

```
股票行情、IOT、金融行情、订单、支付、库存、短信下发
复制到不同的 DB 实例，互不干扰。
```

### 维度表设计

对不同业务指标 tag 进行编码。

### 后台管理页面

业务数据数据 :聚合函数,支持 SQL 支持 ,页面查看数据


## 生产就绪建议

### 短期改进（1-2周）：

1. 修复依赖库 ：安装cjson库提升JSON处理性能
2. 安全加固 ：添加基础认证机制
3. 监控完善 ：集成Prometheus监控

### 中期规划（1-2月）：

1. 高可用部署 ：实现主从复制和故障转移
2. 性能优化 ：针对生产负载进行压力测试
3. 文档完善 ：编写生产部署和维护文档

### 长期目标（3-6月）：

1. 云原生支持 ：Kubernetes部署方案
2. 多租户支持 ：企业级功能完善
3. 生态集成 ：与主流监控系统深度集成
