# Stock-TSDB 简化使用指南

## 概述

Stock-TSDB 提供两套简化部署方案：
- **单机极致性能版**：追求最高性能的单机部署
- **集群可扩展版**：支持水平扩展和高可用性的集群部署

## 快速开始

### 1. 一键安装

```bash
# 下载并运行安装脚本
curl -sSL https://raw.githubusercontent.com/your-repo/stock-tsdb/main/scripts/install.sh | bash

# 或者直接运行本地脚本
./scripts/install.sh
```

### 2. 选择部署模式

#### 单机极致性能版
```bash
# 部署单机版
./scripts/deploy_standalone.sh

# 启动服务
./scripts/start-standalone.sh
```

#### 集群可扩展版
```bash
# 部署集群版（默认3节点）
./scripts/deploy_cluster.sh --nodes 3

# 启动集群
./scripts/manage-nodes start-all
```

## 配置说明

### 单机版配置

配置文件：`config/standalone_high_performance.lua`

```lua
-- 主要配置项说明
storage.data_dir = "./data/standalone"    -- 数据目录
network.port = 6379                       -- 服务端口
performance.memory_pool_size = "2GB"       -- 内存池大小
```

### 集群版配置

配置文件：`config/cluster_scalable.lua`

```lua
-- 主要配置项说明
cluster.enabled = true                    -- 启用集群模式
service_discovery.servers = {"127.0.0.1:8500"}  -- Consul地址
sharding.replication_factor = 2           -- 数据副本数
```

## 数据操作

### CSV数据导入

```bash
# 导入股票数据
./scripts/csv-import.sh --file stock_data.csv --type stock_quote

# 导入IOT数据
./scripts/csv-import.sh --file iot_data.csv --type iot_metric
```

### 数据查询

```bash
# 查询股票数据
./scripts/query.sh --metric stock.price --start 2024-01-01 --end 2024-01-31

# 批量查询
./scripts/batch-query.sh --config query_config.json
```

## 监控与管理

### 服务状态检查

```bash
# 检查单机版状态
./scripts/health-check.sh

# 检查集群版状态
./scripts/cluster-health.sh
```

### 性能监控

```bash
# 查看性能指标
./scripts/metrics.sh

# 生成性能报告
./scripts/performance-report.sh
```

## 系统管理

### 启动/停止服务

```bash
# 单机版
./scripts/start-standalone.sh
./scripts/stop-standalone.sh

# 集群版
./scripts/manage-nodes start-all
./scripts/manage-nodes stop-all
./scripts/manage-nodes status
```

### 数据备份与恢复

```bash
# 备份数据
./scripts/backup.sh --output backup.tar.gz

# 恢复数据
./scripts/restore.sh --input backup.tar.gz
```

## 故障排除

### 常见问题

1. **端口冲突**
   ```bash
   # 修改配置文件中的端口号
   vi config/standalone_high_performance.lua
   ```

2. **内存不足**
   ```bash
   # 调整内存配置
   vi config/standalone_high_performance.lua
   # 修改 performance.memory_pool_size
   ```

3. **集群节点无法连接**
   ```bash
   # 检查Consul服务
   ./scripts/cluster-health.sh
   ```

### 日志查看

```bash
# 查看单机版日志
tail -f logs/standalone.log

# 查看集群版日志
tail -f logs/cluster-node-1.log
```

## 性能优化建议

### 单机版优化

1. **内存配置**：根据服务器内存调整 `memory_pool_size`
2. **批量操作**：使用批量导入和查询提高性能
3. **缓存配置**：启用缓存减少磁盘I/O

### 集群版优化

1. **节点数量**：根据数据量和并发调整节点数
2. **分片策略**：合理设置数据分片和副本数
3. **负载均衡**：使用HAProxy进行请求分发

## 扩展功能

### 自定义插件

```lua
-- 创建自定义数据插件
local MyPlugin = {}

function MyPlugin:process_data(data)
    -- 自定义数据处理逻辑
    return processed_data
end

return MyPlugin
```

### API集成

```bash
# REST API接口
curl -X GET "http://localhost:6379/api/metrics"
curl -X POST "http://localhost:6379/api/data" -d @data.json
```

## 技术支持

- **文档**：查看 `docs/` 目录下的详细文档
- **示例**：参考 `examples/` 目录的使用示例
- **问题反馈**：通过GitHub Issues提交问题

## 版本信息

- 当前版本：v3.0.0
- 支持系统：Linux/macOS
- 依赖环境：LuaJIT, RocksDB

---

💡 **提示**：更多详细配置和高级功能请参考完整文档。