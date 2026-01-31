# Stock-TSDB 压力测试配置说明

## 📋 配置概述

本文档详细说明压力测试的配置参数、性能阈值和优化建议，帮助用户根据实际需求调整测试参数。

## ⚙️ 默认配置

### 基础配置参数

```lua
-- scripts/stress_test.lua 中的默认配置
local config = {
    -- 基础配置
    base_url = "http://localhost:8081",           -- 服务地址
    
    -- 并发配置
    concurrent_threads = 1,                      -- 并发线程数（简化测试）
    requests_per_thread = 10,                     -- 每个线程请求数（简化测试）
    
    -- 数据配置
    symbols = {"SH600519", "SH600036", "SH601318", "SZ000001", "SZ000002"},
    data_points_per_request = 5,                  -- 每个请求的数据点数
    
    -- 时间配置
    test_duration = 10,                          -- 测试持续时间（秒）
    warmup_duration = 1,                         -- 预热时间（秒）
    
    -- 性能阈值
    max_latency_p99 = 100,                       -- P99延迟阈值（毫秒）
    min_throughput = 100000,                     -- 最小吞吐量（QPS）
    max_error_rate = 0.01                        -- 最大错误率
}
```

## 🔧 配置详解

### 1. 基础配置

#### base_url
- **类型**: 字符串
- **默认值**: `"http://localhost:8081"`
- **说明**: Stock-TSDB 业务Web服务器的地址
- **支持的端点**:
  - `/health` - 健康检查
  - `/business/query` - SQL查询接口
  - `/business/tables` - 表列表查询
  - `/business/schema` - 表结构查询

#### symbols
- **类型**: 字符串数组
- **默认值**: 5个常见股票代码
- **说明**: 测试使用的股票代码，用于生成测试数据
- **示例**: `{"SH600519", "SH600036", "SH601318", "SZ000001", "SZ000002"}`

### 2. 并发配置

#### concurrent_threads
- **类型**: 整数
- **默认值**: 1（简化测试）
- **生产建议**: 10-100
- **说明**: 并发执行的线程数量，影响系统负载

#### requests_per_thread
- **类型**: 整数
- **默认值**: 10（简化测试）
- **生产建议**: 1000-10000
- **说明**: 每个线程发送的请求数量

### 3. 数据配置

#### data_points_per_request
- **类型**: 整数
- **默认值**: 5
- **生产建议**: 10-100
- **说明**: 每个请求包含的数据点数量

### 4. 时间配置

#### test_duration
- **类型**: 整数（秒）
- **默认值**: 10
- **生产建议**: 300-1800（5-30分钟）
- **说明**: 测试的总持续时间

#### warmup_duration
- **类型**: 整数（秒）
- **默认值**: 1
- **生产建议**: 30-60
- **说明**: 预热阶段持续时间，让系统达到稳定状态

### 5. 性能阈值

#### max_latency_p99
- **类型**: 数值（毫秒）
- **默认值**: 100
- **说明**: P99延迟的最大允许值
- **生产标准**: < 100ms

#### min_throughput
- **类型**: 数值（QPS）
- **默认值**: 100000
- **说明**: 最小吞吐量要求
- **生产标准**: > 10,000 QPS

#### max_error_rate
- **类型**: 数值（0-1）
- **默认值**: 0.01
- **说明**: 最大错误率阈值
- **生产标准**: < 1%

## 🚀 生产环境配置示例

### 高负载测试配置

```lua
local config = {
    base_url = "http://localhost:8081",
    
    -- 高并发配置
    concurrent_threads = 50,                      -- 50个并发线程
    requests_per_thread = 10000,                  -- 每线程10000个请求
    
    -- 大数据量配置
    data_points_per_request = 100,               -- 每请求100个数据点
    
    -- 长时间运行
    test_duration = 300,                         -- 测试5分钟
    warmup_duration = 30,                        -- 预热30秒
    
    -- 严格性能标准
    max_latency_p99 = 50,                        -- P99延迟<50ms
    min_throughput = 50000,                      -- 吞吐量>50,000 QPS
    max_error_rate = 0.005                       -- 错误率<0.5%
}
```

### 稳定性测试配置

```lua
local config = {
    base_url = "http://localhost:8081",
    
    -- 中等负载
    concurrent_threads = 10,                      -- 10个并发线程
    requests_per_thread = 5000,                   -- 每线程5000个请求
    
    -- 标准数据量
    data_points_per_request = 50,                 -- 每请求50个数据点
    
    -- 长时间稳定性测试
    test_duration = 1800,                         -- 测试30分钟
    warmup_duration = 60,                         -- 预热1分钟
    
    -- 稳定性标准
    max_latency_p99 = 100,                        -- P99延迟<100ms
    min_throughput = 10000,                       -- 吞吐量>10,000 QPS
    max_error_rate = 0.01                         -- 错误率<1%
}
```

## 🔄 配置修改方法

### 方法1: 直接修改脚本

编辑 `scripts/stress_test.lua` 文件中的配置部分：

```lua
-- 找到 config 变量定义位置
local config = {
    -- 修改需要的参数
    concurrent_threads = 20,
    requests_per_thread = 5000,
    test_duration = 600,
    -- ... 其他参数
}
```

### 方法2: 使用配置文件

压力测试会自动生成配置文件：

```bash
# 运行测试后生成配置文件
cat stress_test_config.json
```

可以基于生成的配置文件创建自定义配置：

```bash
# 复制默认配置
cp stress_test_config.json custom_config.json

# 修改配置参数
# 然后使用自定义配置运行测试
```

### 方法3: 命令行参数（未来支持）

计划支持命令行参数覆盖配置：

```bash
lua scripts/stress_test.lua write --threads=20 --duration=300
```

## 📊 性能指标说明

### 延迟指标

| 指标 | 说明 | 生产标准 |
|------|------|----------|
| 平均延迟 | 所有请求的平均响应时间 | < 10ms |
| P95延迟 | 95%请求的响应时间 | < 50ms |
| P99延迟 | 99%请求的响应时间 | < 100ms |

### 吞吐量指标

| 指标 | 说明 | 生产标准 |
|------|------|----------|
| QPS | 每秒处理的查询数量 | > 10,000 |
| 总请求数 | 测试期间的总请求数量 | - |

### 可靠性指标

| 指标 | 说明 | 生产标准 |
|------|------|----------|
| 错误率 | 失败请求的比例 | < 1% |
| 成功率 | 成功请求的比例 | > 99% |

## 🛠️ 配置优化建议

### 针对不同场景的优化

#### 1. 开发环境测试
- 使用简化配置快速验证功能
- 关注功能正确性而非性能

#### 2. 性能基准测试
- 使用中等负载配置
- 关注关键性能指标
- 建立性能基线

#### 3. 极限压力测试
- 使用高负载配置
- 测试系统极限能力
- 识别性能瓶颈

#### 4. 稳定性测试
- 使用长时间运行配置
- 关注内存使用和资源泄漏
- 验证系统稳定性

### 硬件资源考虑

| 资源类型 | 低负载配置 | 高负载配置 | 建议 |
|----------|------------|------------|------|
| CPU核心 | 2-4核心 | 8-16核心 | 根据并发线程数调整 |
| 内存 | 4-8GB | 16-32GB | 考虑数据缓存需求 |
| 网络带宽 | 100Mbps | 1Gbps+ | 根据吞吐量需求调整 |
| 磁盘IO | 普通HDD | SSD/NVMe | 影响数据持久化性能 |

## 🔍 故障排除

### 配置问题诊断

#### 1. 服务不可达
```bash
# 检查服务状态
curl http://localhost:8081/health
```

#### 2. 配置参数错误
- 检查数值类型是否正确
- 确认参数范围是否合理
- 验证依赖关系（如线程数 vs 请求数）

#### 3. 性能不达标
- 调整并发参数
- 优化数据量配置
- 检查系统资源使用情况

### 性能调优建议

1. **逐步增加负载**：从低负载开始，逐步增加并发和数据量
2. **监控系统资源**：测试期间监控CPU、内存、网络使用情况
3. **分析瓶颈**：根据性能指标识别系统瓶颈
4. **迭代优化**：基于测试结果进行系统优化

## 📁 配置文件示例

### 简化测试配置

```json
{
  "base_url": "http://localhost:8081",
  "concurrent_threads": 1,
  "requests_per_thread": 10,
  "data_points_per_request": 5,
  "test_duration": 10,
  "warmup_duration": 1,
  "max_latency_p99": 100,
  "min_throughput": 100000,
  "max_error_rate": 0.01
}
```

### 生产测试配置

```json
{
  "base_url": "http://prod-server:8081",
  "concurrent_threads": 50,
  "requests_per_thread": 10000,
  "data_points_per_request": 100,
  "test_duration": 300,
  "warmup_duration": 30,
  "max_latency_p99": 50,
  "min_throughput": 50000,
  "max_error_rate": 0.005
}
```

---

**📌 提示**: 配置参数应根据实际硬件环境和业务需求进行调整，建议从简化配置开始，逐步增加负载进行测试。