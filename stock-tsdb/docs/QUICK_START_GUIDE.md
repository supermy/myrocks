# Stock-TSDB 快速启动指南

## 🚀 5分钟快速开始

### 第一步：环境准备

确保系统满足以下要求：
- **操作系统**: Linux/macOS
- **内存**: 至少2GB可用内存
- **磁盘空间**: 至少1GB可用空间
- **依赖**: LuaJIT 2.1+

```bash
# 检查LuaJIT是否安装
luajit -v

# 如果没有安装，使用包管理器安装
# Ubuntu/Debian:
sudo apt-get install luajit

# CentOS/RHEL:
sudo yum install luajit

# macOS:
brew install luajit
```

### 第二步：一键安装

```bash
# 下载项目（如果尚未下载）
git clone https://github.com/your-repo/stock-tsdb.git
cd stock-tsdb

# 运行安装脚本
./scripts/install.sh
```

安装脚本会自动：
- 检查系统依赖
- 创建必要目录结构
- 生成默认配置文件
- 设置环境变量

### 第三步：选择部署模式

#### 选项A：单机极致性能版（推荐新手）

```bash
# 部署单机版
./scripts/deploy_standalone.sh

# 启动服务
./scripts/start-standalone.sh

# 检查服务状态
./scripts/health-check.sh
```

#### 选项B：集群可扩展版（生产环境）

```bash
# 部署3节点集群
./scripts/deploy_cluster.sh --nodes 3

# 启动集群
./scripts/manage-nodes start-all

# 检查集群状态
./scripts/cluster-health.sh
```

## 📊 快速数据操作

### 导入示例数据

```bash
# 下载示例数据（可选）
curl -o examples/stock_sample.csv https://example.com/stock_sample.csv

# 导入股票数据
./scripts/csv-import.sh --file examples/stock_sample.csv --type stock_quote

# 导入IOT数据示例
./scripts/csv-import.sh --file examples/iot_sample.csv --type iot_metric
```

### 基本数据查询

```bash
# 查询股票价格数据
./scripts/query.sh --metric stock.price --start "2024-01-01" --end "2024-01-31"

# 查询IOT温度数据
./scripts/query.sh --metric iot.temperature --tag device_id=sensor_001

# JSON格式输出
./scripts/query.sh --metric stock.volume --output json --limit 10
```

## 🔧 常用管理命令

### 服务管理

```bash
# 单机版服务管理
./scripts/start-standalone.sh          # 启动服务
./scripts/start-standalone.sh stop      # 停止服务
./scripts/start-standalone.sh restart   # 重启服务
./scripts/start-standalone.sh status    # 查看状态

# 集群版服务管理
./scripts/manage-nodes start-all        # 启动所有节点
./scripts/manage-nodes stop-all         # 停止所有节点
./scripts/manage-nodes restart-all     # 重启所有节点
./scripts/manage-nodes status          # 查看节点状态
```

### 监控与健康检查

```bash
# 基础健康检查
./scripts/health-check.sh

# 完整健康检查
./scripts/health-check.sh --mode full

# 性能检查
./scripts/health-check.sh --mode performance

# 连续监控
./scripts/health-check.sh --check-interval 30 --check-count 10
```

### 数据备份与恢复

```bash
# 数据备份
./scripts/backup.sh --output backup_$(date +%Y%m%d).tar.gz

# 数据恢复
./scripts/restore.sh --input backup_20240101.tar.gz
```

## ⚡ 性能优化快速配置

### 单机版性能优化

编辑 `config/standalone_high_performance.lua`：

```lua
-- 内存配置（根据服务器内存调整）
performance.memory_pool_size = "4GB"

-- 批量大小优化
batch_size = 2000

-- 启用压缩
compression_type = "lz4"

-- JIT优化
enable_luajit_optimization = true
```

### 集群版扩展配置

编辑 `config/cluster_scalable.lua`：

```lua
-- 增加节点数量
./scripts/deploy_cluster.sh --nodes 5

-- 调整数据副本数
sharding.replication_factor = 3

-- 启用自动扩展
scalability.auto_scaling = true
```

## 🐛 常见问题解决

### 问题1：端口被占用

```bash
# 检查端口占用
netstat -tulpn | grep 6379

# 修改端口配置
vi config/standalone_high_performance.lua
# 修改 network.port = 6380
```

### 问题2：内存不足

```bash
# 检查内存使用
free -h

# 调整内存配置
vi config/standalone_high_performance.lua
# 修改 performance.memory_pool_size = "1GB"
```

### 问题3：服务无法启动

```bash
# 查看详细日志
tail -f logs/standalone.log

# 检查依赖
./scripts/install.sh --check-deps
```

### 问题4：数据导入失败

```bash
# 检查CSV文件格式
head -5 your_data.csv

# 试运行验证
./scripts/csv-import.sh --file data.csv --type stock_quote --dry-run --validate
```

## 📈 性能基准测试

### 单机版性能测试

```bash
# 启动性能测试
./scripts/performance-test.sh --mode standalone --duration 300

# 预期性能指标（参考）
# - 写入吞吐量: 10,000+ 记录/秒
# - 查询延迟: < 10ms
# - 并发连接: 1,000+
```

### 集群版性能测试

```bash
# 集群性能测试
./scripts/performance-test.sh --mode cluster --nodes 3 --duration 300

# 预期性能指标（参考）
# - 写入吞吐量: 30,000+ 记录/秒
# - 查询延迟: < 20ms
# - 可扩展性: 线性扩展
```

## 🔄 升级与维护

### 版本升级

```bash
# 备份数据
./scripts/backup.sh

# 下载新版本
git pull origin main

# 重新安装
./scripts/install.sh --upgrade

# 恢复数据
./scripts/restore.sh
```

### 日常维护

```bash
# 检查系统状态
./scripts/health-check.sh --mode full

# 清理日志文件
./scripts/cleanup-logs.sh

# 优化存储
./scripts/optimize-storage.sh
```

## 📚 下一步学习

### 进阶功能

1. **自定义插件开发** - 参考 `examples/plugins/`
2. **API集成** - 查看 `docs/API_REFERENCE.md`
3. **监控告警** - 配置 Prometheus + Grafana
4. **高可用部署** - 多数据中心部署指南

### 相关文档

- [详细架构说明](docs/SIMPLIFIED_DEPLOYMENT_ARCHITECTURE.md)
- [API参考手册](docs/API_REFERENCE.md)
- [性能优化指南](docs/PERFORMANCE_OPTIMIZATION.md)
- [故障排除手册](docs/TROUBLESHOOTING_GUIDE.md)

### 社区支持

- 📖 [完整文档](https://github.com/your-repo/stock-tsdb/docs)
- 💬 [社区讨论](https://github.com/your-repo/stock-tsdb/discussions)
- 🐛 [问题反馈](https://github.com/your-repo/stock-tsdb/issues)
- 📧 [技术支持](mailto:support@example.com)

---

## 🎯 快速参考卡片

### 紧急命令

```bash
# 紧急停止所有服务
./scripts/stop-all-services.sh

# 快速备份
./scripts/quick-backup.sh

# 系统状态检查
./scripts/emergency-check.sh
```

### 重要文件位置

- **配置文件**: `config/` 目录
- **数据文件**: `data/` 目录
- **日志文件**: `logs/` 目录
- **脚本文件**: `scripts/` 目录
- **文档文件**: `docs/` 目录

### 关键端口

- **单机版服务端口**: 6379
- **集群版服务端口**: 6379-6381
- **监控端口**: 9090
- **健康检查端口**: 9290

---

💡 **提示**: 遇到问题时，首先运行 `./scripts/health-check.sh` 进行基础诊断！