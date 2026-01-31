# Stock-TSDB 压力测试指南

## 📋 概述

本文档详细介绍了 Stock-TSDB 系统的压力测试方案、配置方法、执行步骤和结果分析。压力测试用于验证系统在高并发、大数据量场景下的性能和稳定性。

## 🚀 快速开始

### 前置条件

1. **服务运行**: 确保业务Web服务器正在运行
   ```bash
   cd /Users/moyong/project/ai/myrocks/stock-tsdb
   luajit web/start_business_web.lua
   ```

2. **依赖安装**: 确保已安装必要的Lua依赖
   ```bash
   luarocks install luasocket lua-cjson
   ```

### 快速测试

使用 Makefile 目标快速运行压力测试：

```bash
# 写入压力测试
make stress-test-write

# 读取压力测试  
make stress-test-read

# 混合压力测试
make stress-test-mixed

# 完整测试套件
make stress-test-all
```

## 📊 测试类型

### 1. 写入压力测试 (write)
- **目的**: 测试数据写入性能
- **特点**: 批量插入股票交易数据
- **SQL操作**: INSERT INTO stock_data

### 2. 读取压力测试 (read)  
- **目的**: 测试数据查询性能
- **特点**: 随机查询股票数据
- **SQL操作**: SELECT FROM stock_data

### 3. 混合压力测试 (mixed)
- **目的**: 测试读写混合场景性能
- **特点**: 70%写入 + 30%读取操作
- **场景**: 模拟真实交易环境

## ⚙️ 配置参数

### 基础配置
```lua
{
    base_url = "http://localhost:8081",           -- 服务地址
    concurrent_threads = 1,                      -- 并发线程数
    requests_per_thread = 10,                     -- 每线程请求数
    data_points_per_request = 5,                  -- 每请求数据点数
    test_duration = 10,                          -- 测试持续时间(秒)
    warmup_duration = 1,                         -- 预热时间(秒)
    symbols = ["SH600519", "SH600036", "SH601318", "SZ000001", "SZ000002"]
}
```

### 性能阈值
```lua
{
    max_latency_p99 = 100,        -- P99延迟阈值(毫秒)
    min_throughput = 100000,      -- 最小吞吐量(QPS)
    max_error_rate = 0.01         -- 最大错误率
}
```

## 🔧 手动执行

### 基本用法
```bash
cd /Users/moyong/project/ai/myrocks/stock-tsdb

# 设置Lua环境
eval "$(luarocks path)"

# 运行压力测试
lua scripts/stress_test.lua write     # 写入测试
lua scripts/stress_test.lua read      # 读取测试  
lua scripts/stress_test.lua mixed     # 混合测试
lua scripts/stress_test.lua help      # 帮助信息
```

### 生产环境配置

对于生产环境测试，建议修改配置参数：

```lua
-- 高负载配置
concurrent_threads = 50              -- 50个并发线程
requests_per_thread = 10000          -- 每线程10000个请求
data_points_per_request = 100        -- 每请求100个数据点
test_duration = 300                  -- 测试5分钟
warmup_duration = 30                 -- 预热30秒
```

## 📈 测试结果分析

### 关键指标

1. **吞吐量 (Throughput)**
   - 单位: QPS (Queries Per Second)
   - 目标: > 100,000 QPS

2. **延迟 (Latency)**
   - 平均延迟: < 10ms
   - P95延迟: < 50ms  
   - P99延迟: < 100ms

3. **错误率 (Error Rate)**
   - 目标: < 1%

### 测试报告示例

```json
{
  "title": "Stock-TSDB write压力测试报告",
  "timestamp": "2025-10-13 23:46:05",
  "config": {...},
  "metrics": {
    "total_requests": 10,
    "successful_requests": 10,
    "failed_requests": 0,
    "throughput_qps": 1.00,
    "avg_latency_ms": 6.13,
    "p95_latency_ms": 6.13,
    "p99_latency_ms": 6.13,
    "error_rate": 0.0000
  },
  "issues": ["吞吐量过低: 1.00 QPS < 100000.00 QPS"],
  "conclusion": "FAIL"
}
```

## 🔍 问题诊断

### 常见问题

1. **404错误**
   - **原因**: 路由配置错误
   - **解决**: 确保使用正确的API路由 `/business/query`

2. **JSON编码错误**
   - **原因**: json.encode参数错误
   - **解决**: 使用 `json.encode(data)` 而非 `json.encode(data, {indent = true})`

3. **服务不可用**
   - **原因**: Web服务器未启动
   - **解决**: 检查服务状态并重新启动

### 性能问题分析

1. **吞吐量过低**
   - 检查网络连接
   - 优化数据库配置
   - 增加并发线程数

2. **延迟过高**
   - 检查系统资源使用情况
   - 优化SQL查询
   - 调整数据库索引

## 📁 文件结构

```
stock-tsdb/
├── scripts/
│   └── stress_test.lua              # 压力测试主脚本
├── stress_test_config.json          # 测试配置文件
├── stress_test_report_*.json        # 测试报告文件
└── docs/
    └── STRESS_TEST_GUIDE.md         # 本文档
```

## 🛠️ 自定义测试

### 修改测试数据

编辑 `scripts/stress_test.lua` 中的 `generate_test_data` 函数：

```lua
local function generate_test_data(symbol, count)
    local data_points = {}
    local base_time = os.time() * 1000000  -- 微秒时间戳
    
    for i = 1, count do
        local timestamp = base_time + i * 1000  -- 1毫秒间隔
        local price = 100.0 + math.random() * 100  -- 100-200元价格
        local volume = math.random(100, 10000)     -- 100-10000股
        
        table.insert(data_points, {
            symbol = symbol,
            timestamp = timestamp,
            price = price,
            volume = volume,
            side = math.random(0, 1) == 0 and "B" or "S",
            channel = math.random(0, 10)
        })
    end
    
    return data_points
end
```

### 添加新的测试类型

在 `run_stress_test` 函数中添加新的测试类型：

```lua
local test_function
if test_type == "write" then
    test_function = write_stress_test
elseif test_type == "read" then
    test_function = read_stress_test
elseif test_type == "custom" then
    test_function = custom_stress_test  -- 自定义测试函数
else
    test_function = mixed_stress_test
end
```

## 📞 技术支持

### 日志查看

测试过程中会输出详细日志：

```
检查服务可用性...
服务正常，开始压力测试
开始 write 压力测试...
配置: 1线程, 每线程10请求, 持续10秒
开始预热阶段...
测试报告已保存: stress_test_report_write_20251013_234605.json

=== 测试摘要 ===
测试类型: write
总请求数: 10
成功请求: 10
失败请求: 0
吞吐量: 1.00 QPS
平均延迟: 6.13 ms
P95延迟: 6.13 ms
P99延迟: 6.13 ms
错误率: 0.0000
```

### 问题反馈

遇到问题时请提供：
1. 完整的错误日志
2. 测试配置文件内容
3. 系统环境信息
4. 复现步骤

## 🔄 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| 1.0 | 2025-10-13 | 初始版本，支持三种测试类型 |
| 1.1 | 2025-10-13 | 修复404错误和JSON编码问题 |

---

**📌 提示**: 本文档会随压力测试工具的发展持续更新，建议定期查看最新版本。