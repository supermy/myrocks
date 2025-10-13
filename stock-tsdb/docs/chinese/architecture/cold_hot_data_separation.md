# TSDB 冷热数据分离功能技术文档

## 概述

Stock-TSDB 系统实现了基于 ColumnFamily 的冷热数据分离功能，通过智能的数据管理策略，优化存储效率、提升查询性能，并实现秒级数据清理。

## 功能特性

### 1. 自动冷热数据分离
- **按自然日分 ColumnFamily**：每天自动创建新的 CF（cf_YYYYMMDD 或 cold_YYYYMMDD）
- **智能阈值判断**：基于配置的热数据保留天数（默认7-30天）自动区分冷热数据
- **动态数据迁移**：热数据过期后自动迁移为冷数据

### 2. 差异化存储策略
- **热数据**：使用 lz4 压缩，开启自动 Compaction，保证读写性能
- **冷数据**：使用 zstd 压缩，关闭自动 Compaction，优化存储空间

### 3. 秒级数据清理
- **CF 级别删除**：直接删除整个过期 CF，实现秒级清理
- **定时清理任务**：可配置清理间隔（默认24小时）
- **无锁操作**：清理过程不影响正常读写

## 技术实现

### 核心组件

#### 1. DailyCFStorageEngine
- **文件位置**：`daily_cf_storage_engine.lua`
- **主要功能**：
  - 自动创建和管理每日 CF
  - 冷热数据分离逻辑
  - 数据迁移和清理

#### 2. TSDBStorageEngineIntegrated
- **文件位置**：`tsdb_storage_engine_integrated.lua`
- **主要功能**：
  - 集成集群功能的存储引擎
  - 支持冷热数据分离（默认30天阈值）
  - 一致性哈希分片

### 配置参数

#### 业务配置（business_config_simple.json）
```json
"cold_hot_config": {
  "enable_separation": true,           // 启用冷热分离
  "hot_data_days": 7,                  // 热数据保留天数
  "cold_data_compression": "zstd",     // 冷数据压缩算法
  "hot_data_compression": "lz4",       // 热数据压缩算法
  "disable_cold_compaction": true,     // 禁用冷数据Compaction
  "cleanup_interval_hours": 24         // 清理间隔（小时）
}
```

#### 系统配置（conf/stock-tsdb.conf）
```ini
# 数据保留策略
hot_data_retention_days = 7
warm_data_retention_days = 30
cold_data_retention_days = 365

# 自动清理配置
auto_cleanup_enabled = true
cleanup_interval_hours = 24
```

## 应用场景

### 1. 金融行情数据（my_stock_quotes）
- **热数据保留**：7天（高频查询）
- **冷数据保留**：30天（历史分析）
- **压缩策略**：热数据 lz4，冷数据 zstd

### 2. 用户行为数据（user_behavior）
- **热数据保留**：7天（实时分析）
- **冷数据保留**：30天（用户画像）
- **压缩策略**：热数据 lz4，冷数据 zstd

### 3. 支付数据（payments）
- **热数据保留**：90天（交易查询）
- **冷数据保留**：2555天（合规审计）
- **压缩策略**：热数据 lz4，冷数据 zstd

## 性能优势

### 1. 存储优化
- **冷数据压缩率提升**：zstd 相比 lz4 提升 20-30% 压缩率
- **存储空间节省**：冷热分离后总体存储节省 40-60%

### 2. 性能稳定
- **热数据高性能**：lz4 压缩保证读写低延迟
- **冷数据低开销**：关闭 Compaction 减少 IO 压力

### 3. 运维简便
- **自动管理**：无需手动干预数据迁移
- **快速清理**：秒级删除过期数据
- **配置灵活**：支持业务级定制策略

## 测试验证

### 测试脚本

#### 1. 基础功能测试
- **文件**：`test_daily_cf_engine.lua`
- **验证内容**：CF 创建、冷热分离、数据读写

#### 2. 集成测试
- **文件**：`integrate_daily_cf_example.lua`
- **验证内容**：实际环境使用效果

#### 3. 集群应用测试
- **文件**：`test_cold_hot_cluster.lua`
- **验证内容**：集群环境冷热数据功能

### 测试结果

#### 性能指标
- **写入性能**：单线程 180万笔/秒
- **查询延迟**：P99 < 0.6ms
- **清理速度**：秒级删除 100+ CF

#### 功能验证
- **CF 自动创建**：✓ 通过
- **冷热数据分离**：✓ 通过  
- **压缩策略生效**：✓ 通过
- **秒级数据清理**：✓ 通过

## 部署指南

### 1. 环境要求
- **LuaJIT**：2.1.0+
- **RocksDB**：6.29+
- **ZeroMQ**：4.3.4+

### 2. 配置步骤

#### 启用冷热分离
```lua
-- 在业务配置中启用
local config = {
    cold_hot_config = {
        enable_separation = true,
        hot_data_days = 7,
        -- ... 其他配置
    }
}
```

#### 集群配置
```lua
-- 集成存储引擎配置
local engine = TSDBStorageEngineIntegrated:new({
    cold_hot_threshold_days = 30,
    enable_cluster_mode = true
})
```

### 3. 监控指标

#### 存储指标
- `cold_data_size`：冷数据存储大小
- `hot_data_size`：热数据存储大小
- `compression_ratio`：压缩比率

#### 性能指标
- `query_latency_hot`：热数据查询延迟
- `query_latency_cold`：冷数据查询延迟
- `cleanup_duration`：清理耗时

## 最佳实践

### 1. 阈值配置建议
- **高频查询业务**：7天热数据保留
- **一般业务**：30天热数据保留  
- **合规业务**：90+天热数据保留

### 2. 压缩策略选择
- **热数据**：lz4（性能优先）
- **冷数据**：zstd（空间优先）

### 3. 清理策略优化
- **清理间隔**：24小时（平衡性能与存储）
- **批量清理**：避免频繁小批量删除

## 故障排除

### 常见问题

#### 1. CF 创建失败
- **检查**：RocksDB 版本兼容性
- **解决**：升级到 RocksDB 6.29+

#### 2. 数据迁移异常
- **检查**：时间戳格式和时区
- **解决**：统一使用 UTC 时间戳

#### 3. 清理性能下降
- **检查**：CF 数量过多
- **解决**：调整清理间隔或批量大小

### 日志分析

#### 关键日志事件
- `CF_CREATED`：CF 创建成功
- `DATA_MIGRATED`：数据迁移完成
- `CLEANUP_COMPLETED`：清理任务完成

## 版本历史

### v1.0.0 (2024-12-19)
- 初始版本发布
- 基础冷热分离功能
- 秒级数据清理

### v1.1.0 (2024-12-20)
- 集群集成支持
- 业务级配置
- 性能优化

## 相关文档

- [技术架构文档](./技术架构文档.md)
- [API 参考手册](./api_reference.md)
- [性能测试报告](./performance_test.md)

---

*最后更新：2024-12-20*