# Stock-TSDB - 基于RocksDB的高性能时序数据库

## 项目简介

Stock-TSDB是一个专门为股票行情数据设计的高性能时序数据库，基于RocksDB和LuaJIT实现。通过V3存储引擎重构，提供了插件化架构和统一API接口，支持基础版本和集成版本两种部署模式，适用于从单机到分布式的各种金融数据处理场景。

## 🌟 核心特性

### V3存储引擎 (最新版)
- **30秒定长块存储** - 优化压缩率和查询性能
- **微秒级时间戳精度** - 满足高频交易需求  
- **冷热数据分离** - 自动优化存储成本
- **插件化架构** - 支持多种存储引擎实现
- **统一API接口** - 简化开发和使用

### 技术特点
- **纯Lua实现**：完全使用Lua语言编写，易于扩展和维护
- **高性能存储**：基于RocksDB，提供高效的键值存储
- **时序数据优化**：专为时间序列数据设计的存储结构
- **LuaJIT FFI**：直接调用RocksDB C API，性能优异
- **轻量级部署**：无外部依赖，易于部署和运行
- **分布式支持**：集成版本支持集群部署和高可用
- **生产级脚本**：完整的部署、监控、备份、维护解决方案

## 系统架构

### V3存储引擎架构

#### 基础版本架构 (高性能单机)
```
┌─────────────────┐
│   Application   │
└────────┬────────┘
         │
┌────────▼────────┐
│ V3StorageEngine │
└────────┬────────┘
         │
┌────────▼────────┐
│     RocksDB     │
└─────────────────┘
```

#### 集成版本架构 (分布式集群)
```
┌─────────────────┐
│   Application   │
└────────┬────────┘
         │
┌────────▼────────┐
│TSDBStorageEngine│
│   Integrated    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼───┐ ┌───▼───┐
│Consul │ │Cluster│
│  HA   │ │Manager│
└───┬───┘ └───┬───┘
    │         │
    └────┬────┘
         │
┌────────▼────────┐
│  StorageEngine  │
└────────┬────────┘
         │
┌────────▼────────┐
│     RocksDB     │
└─────────────────┘
```

### 版本选择指南

| 版本 | 适用场景 | 性能特点 | 部署复杂度 |
|------|----------|----------|------------|
| **V3基础版** | 单机高性能需求 | 写入: 200-350万点/秒<br>查询: 1000-1200万点/秒 | ⭐ 简单 |
| **V3集成版** | 分布式集群需求 | 写入: 30-55万点/秒<br>查询: 10-57万点/秒 | ⭐⭐⭐ 复杂 |

> **选择建议**: 数据规模 < 100万点/天 推荐基础版，需要分布式部署选择集成版

## 系统要求

- LuaJIT 2.1+
- RocksDB 6.0+
- macOS/Linux系统

## 安装步骤

### 1. 安装RocksDB

**macOS:**
```bash
brew install rocksdb
```

**Ubuntu/Debian:**
```bash
sudo apt-get install librocksdb-dev
```

### 2. 安装LuaJIT

**macOS:**
```bash
brew install luajit
```

**Ubuntu/Debian:**
```bash
sudo apt-get install luajit
```

## 🚀 快速开始

### 环境检查
```bash
# 系统健康检查
make health-check

# 快速验证测试
make test-quick
```

### 运行测试

```bash
# V3基础版本测试
make test-v3-basic

# V3集成版本测试  
make test-v3-integrated

# 版本对比测试
make test-v3-comparison

# 完整测试套件
make test-v3

# 运行基础功能测试
luajit tests/simple_test.lua

# 运行综合测试
luajit tests/comprehensive_test.lua

# 运行集群测试
luajit tests/tsdb_cluster_test.lua

# 运行性能对比测试
luajit tests/performance_comparison_test.lua

# 运行集成测试
luajit tests/integrated_tsdb_test.lua
```

### 选择存储引擎

Stock-TSDB提供两种V3存储引擎，根据需求选择：

#### V3基础引擎 (高性能单机)
```lua
local TSDBStorageEngineV3 = require "../tsdb_storage_engine_v3"
local config = {
    data_dir = "./data",
    block_size = 30,
    enable_cold_data_separation = true
}
local engine = TSDBStorageEngineV3:new(config)
engine:init()
```

#### V3集成引擎 (分布式集群)
```lua
local TSDBStorageEngineIntegrated = require "lua/tsdb_storage_engine_integrated"
local config = {
    data_dir = "./data",
    block_size = 30,
    enable_cold_data_separation = true,
    cluster_mode = true,
    consul_servers = {"127.0.0.1:8500"}
}
local engine = TSDBStorageEngineIntegrated:new(config)
engine:init()
```

## 📁 项目结构

### 核心文件
```bash
.
├── README.md                          # 项目说明文档 (本文件)
├── LICENSE                             # 开源许可证
├── Makefile                           # 构建文件
├── stock-tsdb                         # 可执行文件
├── server.log                         # 服务日志文件
├── tsdb_storage_engine_v3.lua        # V3存储引擎实现
├── lua/                               # Lua核心代码
│   ├── README.md                      # Lua模块说明
│   ├── main.lua                       # 程序入口
│   ├── api.lua                        # API接口封装
│   ├── tsdb.lua                       # 时间序列数据库主模块
│   ├── storage.lua                    # 存储模块包装器
│   ├── tsdb_storage_engine_integrated.lua # 集成存储引擎(V3集群版)
│   ├── config.lua                     # 配置管理
│   ├── logger.lua                     # 日志模块
│   ├── monitor.lua                    # 监控模块
│   ├── cluster.lua                    # 集群管理
│   └── event_server.lua               # 事件服务器
├── tests/                             # 测试脚本
│   ├── simple_test.lua                # 基础功能测试
│   ├── comprehensive_test.lua       # 综合测试
│   ├── tsdb_cluster_test.lua        # 集群测试
│   ├── integrated_tsdb_test.lua     # 集成测试
│   ├── performance_comparison_test.lua # 性能对比测试
│   └── run_all_tests.lua              # 批量测试执行器
├── conf/                              # 配置文件
│   ├── stock-tsdb.conf                # 主配置文件
│   └── stock-tsdb.service             # systemd服务配置
├── bin/                               # 可执行文件
├── lib/                               # 库文件
├── logs/                              # 日志文件
├── data/                              # 数据文件
│   ├── test_data/                     # 测试数据
│   └── comprehensive_test_data/       # 综合测试数据
└── obj/                               # 编译中间文件
```

### 📚 文档目录
```bash
docs/                                  # 文档目录
├── ARCHITECTURE.md                    # 系统架构文档
├── CHANGELOG.md                       # 版本变更记录
├── CLUSTER_ARCHITECTURE.md            # 集群架构文档
├── FFI_SUMMARY.md                     # FFI接口摘要
├── SCHEME_A_IMPLEMENTATION.md         # 方案A实现文档
├── V3_STORAGE_ENGINE_COMPLETE_GUIDE.md # V3存储引擎完整指南 ⭐
├── V3_VERSION_COMPARISON_REPORT.md      # V3版本对比报告
├── V3_INTEGRATED_SUMMARY.md           # V3集成版本总结
├── MAKEFILE_IMPROVEMENTS.md           # Makefile改进文档
├── DOCUMENTATION_INDEX.md             # 文档索引
├── CONSUL_INTEGRATION_SUMMARY.md      # Consul集成总结
├── CONSUL_PRODUCTION_DEPLOYMENT.md     # Consul生产部署
├── MIGRATION_ETCD_TO_CONSUL.md         # ETCD到Consul迁移指南
└── PRODUCTION_SCRIPTS_GUIDE.md         # 生产环境脚本使用指南
```

### 🚀 生产环境脚本
```bash
├── install.sh                         # 基础安装脚本
├── uninstall.sh                       # 卸载脚本
├── stock-tsdb.sh                      # 服务管理脚本
├── production_deploy.sh               # 生产环境部署脚本
├── monitor_production.sh              # 生产环境监控脚本
├── backup_production.sh               # 生产环境备份脚本
├── maintain_production.sh             # 生产环境维护脚本
├── Dockerfile                         # Docker容器配置
└── docker-compose.yml                 # Docker Compose配置
```
## 数据模型

### RowKey设计
```
[股票代码(8字节)][时间戳(8字节)][数据类型(1字节)]
```

RowKey由三部分组成：
- **股票代码**: 8字节，左对齐填充空格，支持最多8位股票代码
- **时间戳**: 8字节，大端序存储的微秒级时间戳
- **数据类型**: 1字节，标识数据类型（价格、成交量等）

### Value结构
```
[数据块JSON序列化数据]
```

Value存储的是按时间分块的JSON序列化数据，包含：
- 数据块元信息（起始时间、结束时间、数据点数量等）
- 数据点数组（时间戳、值、质量码）

### 数据分块策略

为了优化查询性能，数据按30秒时间窗口进行分块：
- 每个数据块包含最多30000个数据点（假设1KHz采样频率）
- 数据块在写入时进行LZ4压缩以节省存储空间
- 查询时按块读取，减少磁盘I/O操作

## 核心功能

### 1. 数据点操作
- **单点写入/读取**: 支持精确时间戳的数据点写入和读取
- **批量写入**: 支持批量数据点写入，提高写入性能
- **条件更新**: 支持基于条件的数据更新操作
- **数据质量码**: 支持数据质量标识，便于数据有效性管理

### 2. 范围查询
- **时间范围查询**: 支持指定时间范围内的数据查询
- **最新N条记录查询**: 支持获取最新的N条数据记录
- **高效迭代器**: 基于RocksDB迭代器实现高效的数据遍历

### 3. 统计功能
- **数据库统计信息**: 提供详细的数据库性能统计信息
- **性能指标收集**: 收集并展示系统性能指标
- **缓存统计**: 提供数据块缓存命中率等缓存相关统计

### 4. 存储管理
- **数据压缩**: 使用LZ4算法进行数据压缩，节省存储空间
- **数据删除**: 支持按时间范围的数据删除操作
- **存储引擎状态管理**: 提供存储引擎的初始化、关闭等状态管理功能
- **列族管理**: 支持RocksDB列族功能，实现数据分类存储

### 5. 高级功能
- **数据分块**: 按时间窗口对数据进行分块存储，优化查询性能
- **内存缓存**: 实现LRU缓存机制，提高热点数据访问速度
- **配置管理**: 支持灵活的配置参数管理
- **监控告警**: 提供系统监控和告警功能

## 性能优化

### 1. FFI直接调用
通过LuaJIT FFI直接调用RocksDB C API，避免了Lua与C之间的转换开销，提供了接近原生C的性能。

### 2. 批量操作
- **批量写入**: 支持批量数据写入操作，减少系统调用次数
- **批量读取**: 支持批量数据读取，提高查询效率
- **WriteBatch**: 使用RocksDB的WriteBatch功能，原子性地应用多个写操作

### 3. LZ4压缩
- 使用LZ4压缩算法平衡压缩率和性能
- 针对时序数据特点优化压缩策略
- 支持配置压缩级别以适应不同性能要求

### 4. 读写优化
- 分别优化读写选项，针对不同场景提供最佳配置
- 使用单独的读写选项对象，避免锁竞争
- 针对时序数据访问模式优化缓存策略

### 5. 内存缓存
- 实现LRU缓存机制，缓存热点数据块
- 可配置的缓存大小和过期时间
- 缓存命中率统计，便于性能调优

### 6. 数据分块
- 按时间窗口对数据进行分块存储
- 减少单次查询需要读取的数据量
- 提高范围查询性能

### 7. 列族优化
- 使用RocksDB列族功能实现数据分类存储
- 不同类型数据可采用不同存储策略
- 提高存储管理灵活性

## API参考

### 存储引擎API

```lua
-- 创建存储引擎
local engine = StorageEngine:new(db_path, options)

-- 初始化存储引擎
engine:init()

-- 写入单个数据点
engine:put(key, value)

-- 读取单个数据点
local value = engine:get(key)

-- 删除数据点
engine:delete(key)

-- 批量写入
engine:batch_put(pairs)

-- 范围查询
local iterator = engine:create_iterator(start_key, end_key)
-- 遍历结果
iterator:seek_to_first()
while iterator:valid() do
    local key = iterator:key()
    local value = iterator:value()
    iterator:next()
end
iterator:destroy()

-- 获取统计信息
local stats = engine:get_statistics()

-- 压缩数据库
engine:compact_range()

-- 关闭存储引擎
engine:close()
```

### TSDB核心API

```lua
-- 写入单个数据点
tsdb.write_point(symbol, timestamp, value, data_type, quality)

-- 批量写入数据点
tsdb.write_points(symbol, points, data_type)

-- 读取单个数据点
local point = tsdb.read_point(symbol, timestamp, data_type)

-- 读取时间范围数据
local points = tsdb.read_range(symbol, start_time, end_time, data_type)

-- 获取统计信息
local stats = tsdb.get_stats()

-- 获取配置
local config = tsdb.get_config()
```

### Redis协议API

```bash
# 添加数据点
TS.ADD symbol:type timestamp value [quality]

# 范围查询
TS.RANGE symbol:type start_time end_time

# 查询单个数据点
TS.GET symbol:type timestamp

# 获取信息
TS.INFO symbol:type

# 通用命令
PING [message]
INFO [section]
CONFIG GET parameter
CONFIG SET parameter value
```

## 使用示例

### Lua API使用示例

```lua
local tsdb = require "tsdb"

-- 初始化存储引擎
local engine = StorageEngine:new("./data", {})
engine:init()

-- 写入数据点
local success, err = tsdb.write_point("SH600000", 1640995200000000, 12.5, DATA_TYPES.PRICE, 100)

-- 批量写入
local points = {
    {timestamp = 1640995200000000, value = 12.5, quality = 100},
    {timestamp = 1640995201000000, value = 12.6, quality = 100},
    {timestamp = 1640995202000000, value = 12.4, quality = 100}
}
local result = tsdb.write_points("SH600000", points, DATA_TYPES.PRICE)

-- 查询数据
local data_points = tsdb.read_range("SH600000", 1640995200000000, 1640995202000000, DATA_TYPES.PRICE)

-- 获取统计信息
local stats = tsdb.get_stats()
```

### Redis客户端使用示例

```bash
# 使用redis-cli连接
redis-cli -p 6379

# 添加数据点
TS.ADD SH600000:PRICE 1640995200000000 12.5

# 查询范围数据
TS.RANGE SH600000:PRICE 1640995200000000 1640995202000000

# 查询单个数据点
TS.GET SH600000:PRICE 1640995200000000
```

## 测试说明

项目包含两个测试脚本：
1. `simple_test.lua` - 基础功能测试，验证核心API
2. `comprehensive_test.lua` - 综合测试，包含更多边界情况和列族功能

运行测试前请确保已正确安装RocksDB和LuaJIT。

### 测试结果

- `simple_test.lua` - 所有测试通过，包括存储引擎的初始化、数据写入/读取、批量操作、范围查询、统计信息获取、数据压缩和删除等功能
- `comprehensive_test.lua` - 所有功能测试通过，包括列族管理功能，最后有轻微的资源清理问题但不影响使用

## 存储方案切换

Stock-TSDB提供两种存储方案：

1. **现有实现(V1)** - 基于字符串键值的通用存储方案
2. **方案A(V2)** - 基于定长RowKey+大端字节序+30秒分块策略的高效存储方案

### 性能对比

| 方案 | 写入性能 | 查询性能 | 存储效率 |
|------|---------|---------|---------|
| V1(现有实现) | 567,395 QPS | 350,680 QPS | 中等 |
| V2(方案A) | 160,855 QPS (-71.7%) | 153,419 QPS (-56.3%) | 高 |

### 方案选择建议

- **选择V1(现有实现)**：对写入和查询性能要求较高，适合实时交易系统
- **选择V2(方案A)**：对存储空间有严格要求，适合历史数据归档和分析系统

### 切换方法

#### 使用V1(现有实现)
```lua
local StorageEngine = require "storage_engine"
local engine = StorageEngine:new("./data", {})
engine:init()
```

#### 使用V2(方案A)
```lua
local StorageEngine = require "storage_engine_v2"
local engine = StorageEngine:new("./data", {})
engine:init()
```

注意：两种方案的数据格式不兼容，请勿在同一个数据目录中混用。

## 🚀 部署说明

Stock-TSDB 提供多种部署方式以适应不同的环境需求。

### 📋 环境要求
- **LuaJIT**: 2.0.5+
- **RocksDB**: 6.0+
- **ZeroMQ**: 4.3+ (集成版本)
- **Consul**: 1.8+ (集成版本)

### 🔧 快速部署

#### 1. 系统健康检查
```bash
make health-check
```

#### 2. 快速验证
```bash
make test-quick
```

#### 3. 基础安装
项目提供了完整的安装脚本，支持 macOS 和 Linux 系统：

```bash
# 克隆项目
git clone <repository-url>
cd stock-tsdb

# 运行安装脚本
./install.sh
```

### 🐳 Docker 部署

项目提供了 Dockerfile 和 docker-compose.yml 文件，支持容器化部署：

```bash
# 使用 Docker 运行
docker build -t stock-tsdb .
docker run -d -p 6379:6379 -p 5555:5555 -p 8080:8080 --name stock-tsdb stock-tsdb

# 或使用 Docker Compose
docker-compose up -d
```

### 🏭 生产环境部署

#### 完整生产部署脚本
```bash
# 基础部署
./production_deploy.sh deploy

# 集成版部署（含监控）
./production_deploy.sh deploy integrated

# 升级部署
./production_deploy.sh upgrade

# 回滚到上一版本
./production_deploy.sh rollback

# 备份当前版本
./production_deploy.sh backup

# 恢复指定版本
./production_deploy.sh restore 20231201-120000
```

#### 系统服务管理
安装完成后，可以使用系统服务管理命令：

**Linux (systemd):**
```bash
# 启动服务
sudo systemctl start stock-tsdb

# 设置开机自启
sudo systemctl enable stock-tsdb

# 查看状态
sudo systemctl status stock-tsdb

# 停止服务
sudo systemctl stop stock-tsdb
```

**macOS:**
```bash
# 启动服务
stock-tsdb-server -c /usr/local/etc/stock-tsdb.conf -d

# 停止服务
killall stock-tsdb-server
```

#### 手动管理脚本
项目提供了 `stock-tsdb.sh` 脚本用于手动管理服务：

```bash
# 启动服务
./stock-tsdb.sh start

# 停止服务
./stock-tsdb.sh stop

# 重启服务
./stock-tsdb.sh restart

# 查看状态
./stock-tsdb.sh status

# 查看日志
./stock-tsdb.sh logs
```

## ⚙️ 配置说明

配置文件位于 `/usr/local/etc/stock-tsdb.conf`（安装后）或 `conf/stock-tsdb.conf`（开发环境）。

### 主要配置项
- **网络设置**：端口、绑定地址
- **数据存储**：数据目录、压缩算法
- **性能调优**：批量大小、并发数
- **集群配置**：节点ID、主节点地址
- **监控设置**：监控端口、告警阈值
- **市场配置**：支持上海/深圳/香港/美国交易所

### 环境变量配置
```bash
# 监控告警配置
export ALERT_THRESHOLD_CPU=80
export ALERT_THRESHOLD_MEM=85
export ALERT_WEBHOOK_URL="https://hooks.slack.com/services/xxx"
export ALERT_EMAIL="admin@example.com"

# 备份配置
export BACKUP_ENCRYPTION_KEY="your-secret-key"
export BACKUP_REMOTE_HOST="backup.example.com"
export BACKUP_RETENTION_DAYS=30
```

## 🔧 生产环境管理

### 📊 监控管理
```bash
# 执行完整健康检查
./monitor_production.sh check

# 启动实时监控模式
./monitor_production.sh realtime

# 获取性能指标
./monitor_production.sh metrics

# 执行告警检查
./monitor_production.sh alert

# 生成监控报告
./monitor_production.sh report
```

### 💾 备份管理
```bash
# 执行全量备份
./backup_production.sh full

# 执行增量备份
./backup_production.sh incremental

# 列出所有备份
./backup_production.sh list all

# 验证备份文件
./backup_production.sh verify /var/backup/stock-tsdb/full/backup-file.tar.gz

# 恢复备份
./backup_production.sh restore /var/backup/stock-tsdb/full/backup-file.tar.gz

# 清理过期备份
./backup_production.sh cleanup
```

### 🔧 系统维护
```bash
# 执行完整维护流程
./maintain_production.sh full

# 健康检查
./maintain_production.sh health

# 日志清理
./maintain_production.sh logs

# 性能优化
./maintain_production.sh optimize

# 故障排除
./maintain_production.sh troubleshoot
```

### 📋 自动化配置

#### Crontab 定时任务
```bash
# 编辑定时任务
crontab -e

# 添加以下配置
# 每4小时执行增量备份
0 */4 * * * /path/to/stock-tsdb/backup_production.sh incremental

# 每天凌晨2点执行全量备份
0 2 * * * /path/to/stock-tsdb/backup_production.sh full

# 每天凌晨4点清理过期备份
0 4 * * * /path/to/stock-tsdb/backup_production.sh cleanup

# 每小时执行健康检查
0 * * * * /path/to/stock-tsdb/monitor_production.sh check

# 每天凌晨1点执行系统维护
0 1 * * * /path/to/stock-tsdb/maintain_production.sh full
```

#### Systemd 定时器 (Linux)
```bash
# 创建定时器配置
sudo systemctl enable stock-tsdb-backup.timer
sudo systemctl enable stock-tsdb-monitor.timer
sudo systemctl enable stock-tsdb-maintain.timer
```

详细配置请参考 [生产环境脚本使用指南](PRODUCTION_SCRIPTS_GUIDE.md)

## 📖 相关文档

- [📋 V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md) - 🌟 **推荐优先阅读**
- [📊 V3版本对比报告](V3_VERSION_COMPARISON_REPORT.md) - 详细性能对比
- [🚀 V3集成版本总结](V3_INTEGRATED_SUMMARY.md) - 分布式架构特性
- [🔧 生产环境脚本使用指南](PRODUCTION_SCRIPTS_GUIDE.md) - 完整运维指南
- [📚 文档索引](DOCUMENTATION_INDEX.md) - 完整文档导航

## 🤝 贡献指南

欢迎提交Issue和Pull Request！

1. Fork项目
2. 创建功能分支
3. 提交更改
4. 发起Pull Request

### 开发建议
- 首先阅读 [V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md)
- 运行 `make health-check` 检查开发环境
- 使用 `make test-v3` 进行完整测试
- 遵循项目编码规范

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

感谢所有为项目贡献代码、文档和反馈的开发者们！

---

**📌 提示**: 本文档会随项目发展持续更新，建议定期查看最新版本。
