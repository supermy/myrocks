# CSV->LuaJIT->RocksDB 数据流压力测试

## 概述

本压力测试专门针对Stock-TSDB系统中的CSV数据通过LuaJIT处理并存储到RocksDB的完整数据流链路进行性能测试。测试覆盖三个关键阶段：

1. **CSV解析阶段** - CSV数据的解析和验证
2. **LuaJIT处理阶段** - 使用LuaJIT优化的数据处理逻辑
3. **RocksDB存储阶段** - 数据批量写入RocksDB存储引擎

## 测试架构

```
CSV数据 → LuaJIT解析 → LuaJIT处理 → RocksDB存储
    ↓          ↓            ↓           ↓
性能监控 → 性能监控 → 性能监控 → 性能监控
```

## 测试脚本

### 主要脚本文件

- `csv-luajit-rocksdb-stress-test.lua` - 核心压力测试脚本
- `run-csv-luajit-rocksdb-stress-test.sh` - 启动脚本

### Makefile 目标

```bash
# 快速测试
make test-csv-luajit-rocksdb-quick

# 标准测试
make test-csv-luajit-rocksdb-standard

# 压力测试
make test-csv-luajit-rocksdb-stress

# 完整测试（包含所有模式）
make test-csv-luajit-rocksdb-full

# 运行所有CSV->LuaJIT->RocksDB测试
make test-csv-luajit-rocksdb
```

## 测试配置

### 数据流配置

```lua
config.data_flow_stages = {
    "csv_parsing",      -- CSV解析阶段
    "luajit_processing", -- LuaJIT处理阶段  
    "rocksdb_storage"    -- RocksDB存储阶段
}
```

### 并发配置

- **快速测试**: 1线程, 10请求/线程, 30秒
- **标准测试**: 3线程, 50请求/线程, 60秒  
- **压力测试**: 5线程, 100请求/线程, 120秒

### 数据类型支持

- `stock_quotes` - 股票行情数据
- `iot_data` - IOT设备数据  
- `financial_quotes` - 金融行情数据

### 批处理大小

测试支持多种批处理大小：100、500、1000行/批次

## 使用方法

### 1. 直接使用脚本

```bash
# 快速测试
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -m quick

# 标准测试
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -m standard

# 压力测试
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -m stress

# 自定义参数
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -t 5 -r 100 -d 120

# 保存结果到文件
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -m stress -o results.json
```

### 2. 使用Makefile

```bash
# 运行完整测试套件
make test-csv-luajit-rocksdb-full

# 运行特定测试模式
make test-csv-luajit-rocksdb-stress
```

### 3. 命令行参数

| 参数 | 缩写 | 说明 | 默认值 |
|------|------|------|--------|
| `--threads` | `-t` | 并发线程数 | 3 |
| `--requests` | `-r` | 每个线程请求数 | 50 |
| `--duration` | `-d` | 测试持续时间(秒) | 60 |
| `--mode` | `-m` | 测试模式(quick/standard/stress) | standard |
| `--output` | `-o` | 结果输出文件 | - |
| `--verbose` | `-v` | 详细输出模式 | false |
| `--help` | `-h` | 显示帮助信息 | - |

## 测试模式说明

### 快速测试 (quick)
- 目的：快速验证基本功能
- 配置：1线程, 10请求/线程, 30秒
- 适用场景：开发调试、功能验证

### 标准测试 (standard)  
- 目的：常规性能测试
- 配置：3线程, 50请求/线程, 60秒
- 适用场景：日常性能监控、回归测试

### 压力测试 (stress)
- 目的：极限性能测试
- 配置：5线程, 100请求/线程, 120秒
- 适用场景：容量规划、性能瓶颈分析

## 性能指标

### 整体性能指标

- **总请求数**: 处理的请求总数
- **成功请求**: 成功处理的请求数
- **错误率**: 失败请求占总请求的比例
- **平均延迟**: 每个请求的平均处理时间
- **吞吐量**: 每秒处理的请求数(RPS)
- **数据处理量**: 处理的总数据量(MB)

### 各阶段性能指标

#### CSV解析阶段
- 平均解析时间
- 最大/最小解析时间
- 解析吞吐量(记录/秒)

#### LuaJIT处理阶段
- 平均处理时间
- 最大/最小处理时间  
- 处理吞吐量(记录/秒)
- 内存使用情况
- JIT编译时间

#### RocksDB存储阶段
- 平均存储时间
- 最大/最小存储时间
- 存储吞吐量(记录/秒)
- 写入放大系数
- 压缩统计信息

## 测试结果分析

### 结果文件格式

测试结果保存为JSON格式，包含以下结构：

```json
{
  "total_requests": 150,
  "successful_requests": 148,
  "failed_requests": 2,
  "stage_performance": {
    "csv_parsing": {
      "total_time": 12.345,
      "avg_time": 0.082,
      "max_time": 0.156,
      "min_time": 0.045,
      "throughput": 12195.2
    },
    "luajit_processing": {
      "total_time": 8.912,
      "avg_time": 0.059,
      "max_time": 0.102,
      "min_time": 0.032,
      "throughput": 16835.1
    },
    "rocksdb_storage": {
      "total_time": 25.678,
      "avg_time": 0.171,
      "max_time": 0.289,
      "min_time": 0.098,
      "throughput": 5842.3
    }
  },
  "overall_performance": {
    "total_duration": 46.935,
    "avg_latency": 0.313,
    "throughput_rps": 3.196,
    "data_processed_mb": 14.7,
    "error_rate": 0.013
  }
}
```

### 性能瓶颈分析

测试报告会自动识别性能瓶颈：

```
=== 性能瓶颈分析 ===
性能瓶颈: rocksdb_storage (0.171秒)

=== 优化建议 ===
建议调整RocksDB参数，优化批处理大小和压缩策略
```

## 依赖要求

### 系统依赖

- **LuaJIT**: 必须安装LuaJIT 2.0+
- **LuaSocket**: HTTP通信和网络功能
- **lua-cjson**: JSON数据处理

### 安装依赖

```bash
# 使用Homebrew安装LuaJIT
brew install luajit

# 使用LuaRocks安装Lua模块
luarocks install luasocket
luarocks install lua-cjson
```

### 环境要求

- **操作系统**: macOS/Linux
- **内存**: 至少1GB可用内存
- **存储**: 至少100MB可用磁盘空间
- **网络**: 本地网络连接（用于服务通信）

## 故障排除

### 常见问题

#### 1. 依赖缺失错误
```
[ERROR] LuaSocket 模块未安装
```
**解决方案**: 安装缺失的Lua模块
```bash
luarocks install luasocket
```

#### 2. 权限错误
```
[ERROR] 无法创建临时文件
```
**解决方案**: 确保对/tmp目录有写权限

#### 3. 内存不足
```
[ERROR] 内存分配失败
```
**解决方案**: 减少并发线程数或批处理大小

#### 4. 服务连接失败
```
[ERROR] 无法连接到RocksDB服务
```
**解决方案**: 确保相关服务正在运行

### 调试模式

启用详细输出模式获取更多信息：

```bash
./scripts/dev/run-csv-luajit-rocksdb-stress-test.sh -v -m quick
```

## 最佳实践

### 测试环境准备

1. **清理环境**: 测试前清理临时文件和旧结果
2. **服务检查**: 确保相关服务正常运行
3. **资源监控**: 监控系统资源使用情况
4. **备份数据**: 重要数据提前备份

### 测试执行策略

1. **渐进测试**: 从快速测试开始，逐步增加负载
2. **多次运行**: 每个测试模式运行3-5次取平均值
3. **环境隔离**: 在专用测试环境中执行
4. **结果对比**: 与基线性能进行对比分析

### 性能优化建议

#### CSV解析优化
- 使用更高效的字符串处理算法
- 减少不必要的内存分配
- 批量处理数据

#### LuaJIT优化
- 启用JIT编译优化
- 减少全局变量使用
- 使用局部变量和表预分配

#### RocksDB优化
- 调整批处理大小
- 优化压缩策略
- 合理设置缓存大小

## 扩展开发

### 添加新的数据类型

在`generate_test_csv_data`函数中添加新的数据类型：

```lua
elseif data_type == "new_data_type" then
    headers = {"field1", "field2", "field3"}
    -- 生成测试数据逻辑
end
```

### 自定义性能监控

在测试脚本中添加自定义监控指标：

```lua
-- 添加自定义监控
local custom_metrics = {
    custom_metric_1 = 0,
    custom_metric_2 = {}
}
```

### 集成到CI/CD

将测试集成到持续集成流程：

```yaml
# GitHub Actions示例
- name: Run CSV->LuaJIT->RocksDB Stress Test
  run: |
    make test-csv-luajit-rocksdb-standard
    # 检查性能阈值
    python scripts/check_performance.py
```

## 相关文档

- [CSV导入导出压力测试文档](./README-csv-stress-test.md)
- [Stock-TSDB技术架构文档](../docs/technical_architecture.md)
- [性能测试最佳实践](../docs/performance_testing_guide.md)

## 技术支持

如有问题或建议，请联系：
- 项目维护者: [联系方式]
- 问题反馈: [GitHub Issues链接]
- 文档更新: [文档仓库链接]

---

**最后更新**: 2024年
**版本**: 1.0.0