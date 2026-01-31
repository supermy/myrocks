# CSV导入导出压力测试

## 概述

CSV导入导出压力测试是Stock-TSDB系统的重要组成部分，用于验证系统在高并发、大数据量场景下的CSV数据处理能力。测试支持多种业务类型，包括股票行情、IOT设备数据、金融行情、订单数据、支付数据等。

## 测试脚本

### 主要脚本

1. **csv-stress-test.lua** - 核心压力测试脚本
   - 支持导入、导出、混合三种测试模式
   - 支持多种业务类型的数据生成
   - 包含完整的性能指标统计

2. **run-csv-stress-test.sh** - 压力测试启动脚本
   - 提供命令行参数配置
   - 自动检查依赖和服务状态
   - 环境准备和清理

### 测试配置

压力测试的主要配置参数：

```lua
local config = {
    base_url = "http://localhost:8081",           -- 服务地址
    concurrent_threads = 5,                       -- 并发线程数
    requests_per_thread = 100,                   -- 每个线程请求数
    csv_rows_per_request = 1000,                 -- 每个CSV请求的数据行数
    test_duration = 300,                         -- 测试持续时间（秒）
    warmup_duration = 30,                        -- 预热时间（秒）
    max_latency_p99 = 5000,                      -- P99延迟阈值（毫秒）
    min_throughput = 100,                        -- 最小吞吐量（请求/秒）
    max_error_rate = 0.05                        -- 最大错误率
}
```

## 使用方法

### 1. 使用Makefile命令（推荐）

```bash
# 运行CSV导入压力测试
make test-csv-stress-import

# 运行CSV导出压力测试
make test-csv-stress-export

# 运行CSV混合压力测试
make test-csv-stress-mixed

# 运行所有CSV压力测试
make test-csv-stress

# 运行完整CSV压力测试（包含所有模式）
make test-csv-stress-full
```

### 2. 使用启动脚本

```bash
# 基本用法
./scripts/dev/run-csv-stress-test.sh

# 指定测试类型和参数
./scripts/dev/run-csv-stress-test.sh --type import --threads 10 --requests 200 --duration 600

# 仅测试导出
./scripts/dev/run-csv-stress-test.sh -t export -c 5 -r 100 -d 300

# 显示帮助信息
./scripts/dev/run-csv-stress-test.sh --help
```

### 3. 直接运行Lua脚本

```bash
# 运行混合压力测试（默认）
luajit scripts/dev/csv-stress-test.lua

# 指定测试类型
luajit scripts/dev/csv-stress-test.lua import
luajit scripts/dev/csv-stress-test.lua export
luajit scripts/dev/csv-stress-test.lua mixed
```

## 测试模式

### 1. 导入测试（import）
- 生成测试CSV文件
- 通过HTTP API导入数据
- 统计导入成功率和性能指标

### 2. 导出测试（export）
- 通过HTTP API导出数据到CSV文件
- 验证导出文件的完整性
- 统计导出成功率和性能指标

### 3. 混合测试（mixed）
- 同时进行导入和导出操作
- 模拟真实生产环境负载
- 60%导入 + 40%导出的比例

## 支持的业务类型

| 业务类型 | 描述 | 数据字段示例 |
|---------|------|-------------|
| stock_quotes | 股票行情数据 | timestamp, stock_code, market, open, high, low, close, volume, amount |
| iot_data | IOT设备数据 | timestamp, device_id, sensor_type, value, unit, location, status |
| financial_quotes | 金融行情数据 | timestamp, symbol, exchange, bid, ask, last_price, volume, change, change_percent |
| orders | 订单数据 | timestamp, order_id, user_id, product_id, quantity, price, status, payment_method |
| payments | 支付数据 | timestamp, payment_id, order_id, amount, currency, status, payment_gateway, user_id |

## 性能指标

压力测试会统计以下关键性能指标：

### 基础指标
- **总请求数**：完成的请求总数
- **成功率**：成功请求的比例
- **错误率**：失败请求的比例

### 延迟指标
- **平均延迟**：所有请求的平均响应时间
- **P95延迟**：95%请求的响应时间
- **P99延迟**：99%请求的响应时间

### 吞吐量指标
- **吞吐量**：每秒处理的请求数（QPS）
- **数据量**：导入/导出的数据行数

## 依赖要求

### 系统依赖
- LuaJIT 2.1+
- LuaSocket 库
- lua-cjson 库

### 安装依赖
```bash
# 使用LuaRocks安装依赖
luarocks install luasocket
luarocks install lua-cjson

# 或者使用系统包管理器
# Ubuntu/Debian
sudo apt-get install luarocks liblua5.1-0-dev
sudo luarocks install luasocket
sudo luarocks install lua-cjson

# macOS
brew install luarocks
luarocks install luasocket
luarocks install lua-cjson
```

## 测试环境要求

### 硬件要求
- **内存**：至少4GB可用内存
- **CPU**：多核处理器（建议4核以上）
- **磁盘**：足够的临时空间用于CSV文件生成

### 软件要求
- **Stock-TSDB服务**：运行在 http://localhost:8081
- **Redis服务**：用于数据存储（如果使用集群模式）

## 测试结果解读

### 通过标准
测试结果需要满足以下性能阈值：
- P99延迟 ≤ 5000ms
- 吞吐量 ≥ 100 QPS
- 错误率 ≤ 5%

### 结果示例
```
=== CSV导入导出压力测试结果 ===
测试类型: mixed
总请求数: 500
成功请求数: 485
失败请求数: 15
成功率: 97.00%
错误率: 3.00%
平均延迟: 245.67ms
P95延迟: 489.23ms
P99延迟: 1234.56ms
吞吐量: 83.33 请求/秒
导入数据行数: 485000
导出数据行数: 200000

=== 性能阈值检查 ===
✅ P99延迟正常: 1234.56ms <= 5000.00ms
❌ 吞吐量不足: 83.33 < 100.00
✅ 错误率正常: 3.00% <= 5.00%

⚠️  部分性能指标未达到要求，需要优化！
```

## 故障排除

### 常见问题

1. **服务连接失败**
   ```
   错误: Stock-TSDB服务未运行或无法连接
   ```
   **解决方案**：确保Stock-TSDB服务在 http://localhost:8081 上运行

2. **依赖库缺失**
   ```
   错误: 未找到 LuaSocket 库
   ```
   **解决方案**：运行 `luarocks install luasocket lua-cjson`

3. **权限问题**
   ```
   错误: 无法创建临时文件
   ```
   **解决方案**：确保对/tmp目录有写权限

4. **内存不足**
   ```
   错误: 内存分配失败
   ```
   **解决方案**：减少并发线程数或每个请求的数据量

### 调试模式

启用详细日志输出：
```bash
# 修改csv-stress-test.lua中的debug配置
local debug_mode = true
```

## 最佳实践

### 测试环境准备
1. 在生产环境相似的硬件上运行测试
2. 确保网络连接稳定
3. 关闭不必要的后台进程
4. 预留足够的系统资源

### 测试参数调优
1. **轻量级测试**：用于快速验证功能
   ```bash
   ./run-csv-stress-test.sh --threads 2 --requests 10 --duration 30
   ```

2. **标准测试**：用于常规性能验证
   ```bash
   ./run-csv-stress-test.sh --threads 5 --requests 100 --duration 300
   ```

3. **压力测试**：用于极限性能测试
   ```bash
   ./run-csv-stress-test.sh --threads 10 --requests 500 --duration 600
   ```

### 结果分析
1. 关注P99延迟和吞吐量的平衡
2. 监控系统资源使用情况
3. 记录测试环境配置
4. 与历史测试结果对比

## 扩展开发

### 添加新的业务类型

1. 在 `csv-stress-test.lua` 的 `generate_csv_data` 函数中添加新的业务类型
2. 更新 `business_types` 配置
3. 添加对应的数据生成逻辑

### 自定义测试逻辑

修改测试脚本中的以下函数：
- `csv_import_stress_test()` - 导入测试逻辑
- `csv_export_stress_test()` - 导出测试逻辑
- `mixed_stress_test()` - 混合测试逻辑
- `calculate_performance_metrics()` - 性能指标计算

## 相关文档

- [CSV数据管理器文档](../lua/csv_data_manager.lua)
- [CSV导入导出测试文档](../../tests/csv_import_export_test.lua)
- [Stock-TSDB API文档](../../docs/api.md)

## 版本历史

- v1.0.0 (2024-01-01): 初始版本，支持基本CSV压力测试
- v1.1.0 (2024-01-15): 添加混合测试模式和性能阈值检查
- v1.2.0 (2024-02-01): 优化测试脚本，添加更多业务类型支持

## 技术支持

如有问题或建议，请联系开发团队或提交Issue到项目仓库。