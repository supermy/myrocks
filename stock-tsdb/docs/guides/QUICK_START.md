# Stock-TSDB 快速开始指南

本文档将指导您快速安装、配置和运行 Stock-TSDB 时序数据库系统。

## 系统要求

### 基础要求
- **操作系统**: Linux (推荐 Ubuntu 18.04+ / CentOS 7+), macOS 10.14+
- **内存**: 至少 4GB RAM
- **磁盘空间**: 至少 10GB 可用空间

### 软件依赖
- **LuaJIT**: 2.0.5+
- **LuaRocks**: 3.0.0+
- **Redis**: 5.0+ (用于元数据存储)
- **curl**: 用于 API 测试

## 快速安装

### 1. 克隆项目
```bash
git clone https://github.com/your-org/stock-tsdb.git
cd stock-tsdb
```

### 2. 安装依赖
```bash
# 使用项目提供的安装脚本
./scripts/install/install.sh

# 或者手动安装依赖
make deps-install
```

### 3. 构建项目
```bash
make build
```

## 快速启动

### 启动开发环境（推荐）
```bash
# 一键启动所有服务
make dev-start
```

此命令将启动：
- Redis 集群服务器 (端口: 6379)
- 元数据 Web 服务器 (端口: 8080) 
- 业务数据 Web 服务器 (端口: 8081)

### 分别启动服务
```bash
# 启动 Redis 集群
make redis-cluster-start

# 启动元数据 Web 服务器
make metadata-web-server

# 启动业务数据 Web 服务器
make business-web-server
```

## 验证安装

### 1. 健康检查
```bash
# 检查所有服务状态
make health-check

# 或者使用状态检查脚本
./scripts/check_project_status.sh -c all
```

### 2. 测试 API
```bash
# 测试元数据 API
make metadata-api-test

# 测试业务数据 API
make business-api-test
```

## 基本使用

### 1. 创建数据表
```bash
# 创建 IoT 设备数据表
curl -X POST http://localhost:8080/metadata/table/create \
  -H "Content-Type: application/json" \
  -d '{
    "table_name": "iot_data",
    "columns": [
      {"name": "device_id", "type": "string"},
      {"name": "timestamp", "type": "timestamp"},
      {"name": "value", "type": "double"}
    ]
  }'
```

### 2. 插入数据
```bash
# 插入 IoT 设备数据
curl -X POST http://localhost:8081/business/insert \
  -H "Content-Type: application/json" \
  -d '{
    "table": "iot_data",
    "data": [
      {"device_id": "device_001", "timestamp": 1672531200, "value": 25.5},
      {"device_id": "device_002", "timestamp": 1672531200, "value": 30.2}
    ]
  }'
```

### 3. 查询数据
```bash
# 查询特定设备数据
curl -X POST http://localhost:8081/business/query \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT * FROM iot_data WHERE device_id = \"device_001\" AND timestamp >= 1672531200 AND timestamp <= 1672617600"
  }'

# 聚合查询
curl -X POST http://localhost:8081/business/query \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"
  }'
```

## 配置说明

### 配置文件位置
- **主配置**: `conf/config.lua`
- **Redis 配置**: `conf/redis.conf`
- **Web 服务器配置**: `conf/web_server.conf`

### 重要配置项
```lua
-- 数据存储路径
DATA_DIR = "/var/lib/stock-tsdb/data"

-- Redis 连接配置
REDIS_HOST = "127.0.0.1"
REDIS_PORT = 6379

-- Web 服务器端口
METADATA_PORT = 8080
BUSINESS_PORT = 8081

-- 性能调优
BATCH_SIZE = 1000
CACHE_SIZE = 10000
```

## 生产环境部署

### 1. 生产环境安装
```bash
./scripts/install/production_deploy.sh
```

### 2. 监控设置
```bash
# 启动监控
./scripts/install/monitor_production.sh
```

### 3. 备份策略
```bash
# 配置自动备份
./scripts/install/backup_production.sh
```

## 故障排除

### 常见问题

#### 1. 端口被占用
```bash
# 检查端口占用
netstat -tuln | grep 8080

# 停止占用进程或修改配置端口
```

#### 2. 依赖缺失
```bash
# 重新安装依赖
make deps-reinstall

# 检查 Lua 依赖
luarocks list
```

#### 3. 权限问题
```bash
# 确保脚本有执行权限
chmod +x scripts/*.sh
chmod +x scripts/install/*.sh
```

### 日志文件
- **Redis 日志**: `logs/redis.log`
- **元数据服务器日志**: `logs/metadata_web.log`
- **业务数据服务器日志**: `logs/business_web.log`
- **系统日志**: `logs/system.log`

## 下一步

### 深入学习
- 阅读 [架构文档](../architecture/SYSTEM_ARCHITECTURE.md) 了解系统设计
- 查看 [API 参考](../API_REFERENCE.md) 了解完整 API
- 学习 [性能优化指南](../guides/PERFORMANCE_OPTIMIZATION.md)

### 开发扩展
- 查看 [开发指南](../guides/DEVELOPMENT_GUIDE.md)
- 了解 [插件系统](../guides/PLUGIN_SYSTEM.md)
- 参与 [贡献指南](../CONTRIBUTING.md)

## 获取帮助

- **文档索引**: [DOCUMENTATION_INDEX.md](../DOCUMENTATION_INDEX.md)
- **问题报告**: [GitHub Issues](https://github.com/your-org/stock-tsdb/issues)
- **社区讨论**: [Discussions](https://github.com/your-org/stock-tsdb/discussions)

---

**注意**: 本文档基于 Stock-TSDB 最新版本编写，具体功能可能因版本不同而有所差异。

*最后更新: $(date +%Y-%m-%d)*