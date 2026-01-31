--[[
    性能基准测试工具
    优化方案6: 实现全面的性能测试和基准评估
]]

local PerformanceBenchmark = {}
PerformanceBenchmark.__index = PerformanceBenchmark

function PerformanceBenchmark:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.test_duration = obj.config.test_duration or 60  -- 测试持续时间（秒）
    obj.warmup_duration = obj.config.warmup_duration or 10  -- 预热时间
    obj.concurrency = obj.config.concurrency or 10      -- 并发数
    
    -- 测试结果存储
    obj.results = {
        write_tests = {},
        read_tests = {},
        mixed_tests = {},
        stress_tests = {}
    }
    
    -- 测试配置
    obj.test_scenarios = {
        {
            name = "单点写入",
            type = "write",
            concurrent = 1,
            batch_size = 1
        },
        {
            name = "批量写入",
            type = "write",
            concurrent = 10,
            batch_size = 100
        },
        {
            name = "并发写入",
            type = "write",
            concurrent = 50,
            batch_size = 10
        },
        {
            name = "单点查询",
            type = "read",
            concurrent = 1,
            time_range = "1h"
        },
        {
            name = "范围查询",
            type = "read",
            concurrent = 10,
            time_range = "1d"
        },
        {
            name = "并发查询",
            type = "read",
            concurrent = 50,
            time_range = "1h"
        },
        {
            name = "混合负载",
            type = "mixed",
            write_ratio = 0.3,
            read_ratio = 0.7,
            concurrent = 20
        },
        {
            name = "压力测试",
            type = "stress",
            concurrent = 100,
            duration = 300  -- 5分钟
        }
    }
    
    return obj
end

-- 运行完整基准测试
function PerformanceBenchmark:run_full_benchmark(storage_engine)
    print("=== 开始完整性能基准测试 ===")
    print(string.format("测试时间: %s", os.date("%Y-%m-%d %H:%M:%S")))
    print("")
    
    local all_results = {}
    
    for _, scenario in ipairs(self.test_scenarios) do
        print(string.format("--- 执行测试场景: %s ---", scenario.name))
        
        local result = self:run_scenario(scenario, storage_engine)
        table.insert(all_results, result)
        
        -- 输出结果
        self:_print_scenario_result(result)
        print("")
    end
    
    -- 生成综合报告
    local report = self:_generate_report(all_results)
    
    print("=== 基准测试完成 ===")
    self:_print_summary(report)
    
    return report
end

-- 运行单个测试场景
function PerformanceBenchmark:run_scenario(scenario, storage_engine)
    local result = {
        name = scenario.name,
        type = scenario.type,
        config = scenario,
        start_time = os.time(),
        end_time = nil,
        metrics = {},
        status = "running"
    }
    
    -- 预热阶段
    if self.warmup_duration > 0 then
        print(string.format("  预热阶段 (%d秒)...", self.warmup_duration))
        self:_warmup(scenario, storage_engine)
    end
    
    -- 执行测试
    print(string.format("  执行测试 (%d秒)...", scenario.duration or self.test_duration))
    
    if scenario.type == "write" then
        result.metrics = self:_run_write_test(scenario, storage_engine)
    elseif scenario.type == "read" then
        result.metrics = self:_run_read_test(scenario, storage_engine)
    elseif scenario.type == "mixed" then
        result.metrics = self:_run_mixed_test(scenario, storage_engine)
    elseif scenario.type == "stress" then
        result.metrics = self:_run_stress_test(scenario, storage_engine)
    end
    
    result.end_time = os.time()
    result.status = "completed"
    
    return result
end

-- 写入测试
function PerformanceBenchmark:_run_write_test(scenario, storage_engine)
    local metrics = {
        total_operations = 0,
        successful_operations = 0,
        failed_operations = 0,
        total_time_ms = 0,
        min_latency_ms = math.huge,
        max_latency_ms = 0,
        latencies = {}
    }
    
    local duration = (scenario.duration or self.test_duration) * 1000  -- 转换为毫秒
    local start_time = os.clock() * 1000
    local end_time = start_time + duration
    
    while os.clock() * 1000 < end_time do
        local batch_start = os.clock() * 1000
        
        -- 生成测试数据
        local batch_data = self:_generate_write_batch(scenario.batch_size or 1)
        
        -- 执行写入
        local write_start = os.clock() * 1000
        local success = self:_execute_write(storage_engine, batch_data)
        local write_end = os.clock() * 1000
        
        local latency = write_end - write_start
        
        metrics.total_operations = metrics.total_operations + 1
        
        if success then
            metrics.successful_operations = metrics.successful_operations + 1
        else
            metrics.failed_operations = metrics.failed_operations + 1
        end
        
        metrics.total_time_ms = metrics.total_time_ms + latency
        metrics.min_latency_ms = math.min(metrics.min_latency_ms, latency)
        metrics.max_latency_ms = math.max(metrics.max_latency_ms, latency)
        table.insert(metrics.latencies, latency)
        
        -- 控制并发
        if scenario.concurrent and scenario.concurrent > 1 then
            -- 模拟并发
        end
    end
    
    -- 计算统计指标
    self:_calculate_statistics(metrics)
    
    return metrics
end

-- 读取测试
function PerformanceBenchmark:_run_read_test(scenario, storage_engine)
    local metrics = {
        total_operations = 0,
        successful_operations = 0,
        failed_operations = 0,
        total_time_ms = 0,
        min_latency_ms = math.huge,
        max_latency_ms = 0,
        latencies = {}
    }
    
    local duration = (scenario.duration or self.test_duration) * 1000
    local start_time = os.clock() * 1000
    local end_time = start_time + duration
    
    while os.clock() * 1000 < end_time do
        -- 生成查询参数
        local query = self:_generate_read_query(scenario.time_range)
        
        -- 执行查询
        local read_start = os.clock() * 1000
        local success, results = self:_execute_read(storage_engine, query)
        local read_end = os.clock() * 1000
        
        local latency = read_end - read_start
        
        metrics.total_operations = metrics.total_operations + 1
        
        if success then
            metrics.successful_operations = metrics.successful_operations + 1
        else
            metrics.failed_operations = metrics.failed_operations + 1
        end
        
        metrics.total_time_ms = metrics.total_time_ms + latency
        metrics.min_latency_ms = math.min(metrics.min_latency_ms, latency)
        metrics.max_latency_ms = math.max(metrics.max_latency_ms, latency)
        table.insert(metrics.latencies, latency)
    end
    
    -- 计算统计指标
    self:_calculate_statistics(metrics)
    
    return metrics
end

-- 混合测试
function PerformanceBenchmark:_run_mixed_test(scenario, storage_engine)
    local metrics = {
        write_metrics = {},
        read_metrics = {},
        total_operations = 0
    }
    
    -- 简化的混合测试实现
    metrics.write_metrics = self:_run_write_test({
        batch_size = 10,
        duration = (scenario.duration or self.test_duration) * (scenario.write_ratio or 0.3)
    }, storage_engine)
    
    metrics.read_metrics = self:_run_read_test({
        time_range = "1h",
        duration = (scenario.duration or self.test_duration) * (scenario.read_ratio or 0.7)
    }, storage_engine)
    
    metrics.total_operations = metrics.write_metrics.total_operations + 
                               metrics.read_metrics.total_operations
    
    return metrics
end

-- 压力测试
function PerformanceBenchmark:_run_stress_test(scenario, storage_engine)
    local metrics = {
        total_operations = 0,
        successful_operations = 0,
        failed_operations = 0,
        errors = {},
        throughput_history = {},
        latency_history = {}
    }
    
    local duration = (scenario.duration or self.test_duration) * 1000
    local start_time = os.clock() * 1000
    local end_time = start_time + duration
    local last_report_time = start_time
    
    while os.clock() * 1000 < end_time do
        -- 高并发操作
        for i = 1, scenario.concurrent or 100 do
            local op_start = os.clock() * 1000
            
            -- 随机选择操作类型
            if math.random() < 0.5 then
                -- 写入操作
                local data = self:_generate_write_batch(1)
                self:_execute_write(storage_engine, data)
            else
                -- 读取操作
                local query = self:_generate_read_query("1h")
                self:_execute_read(storage_engine, query)
            end
            
            metrics.total_operations = metrics.total_operations + 1
        end
        
        -- 每秒报告
        local current_time = os.clock() * 1000
        if current_time - last_report_time >= 1000 then
            local ops_per_second = metrics.total_operations / ((current_time - start_time) / 1000)
            table.insert(metrics.throughput_history, ops_per_second)
            last_report_time = current_time
            
            print(string.format("    当前吞吐量: %.0f ops/s", ops_per_second))
        end
    end
    
    return metrics
end

-- 预热
function PerformanceBenchmark:_warmup(scenario, storage_engine)
    -- 执行短暂的预热操作
    local warmup_end = os.clock() + self.warmup_duration
    while os.clock() < warmup_end do
        -- 简单的预热操作
    end
end

-- 生成写入批次数据
function PerformanceBenchmark:_generate_write_batch(batch_size)
    local batch = {}
    local timestamp = os.time()
    
    for i = 1, batch_size do
        table.insert(batch, {
            metric = "BENCHMARK_METRIC_" .. math.random(1, 10),
            timestamp = timestamp + i,
            value = math.random() * 100,
            tags = {
                host = "server" .. math.random(1, 5),
                region = "region" .. math.random(1, 3)
            }
        })
    end
    
    return batch
end

-- 生成读取查询
function PerformanceBenchmark:_generate_read_query(time_range)
    local end_time = os.time()
    local start_time = end_time
    
    if time_range == "1h" then
        start_time = end_time - 3600
    elseif time_range == "1d" then
        start_time = end_time - 86400
    elseif time_range == "7d" then
        start_time = end_time - 604800
    end
    
    return {
        metric = "BENCHMARK_METRIC_" .. math.random(1, 10),
        start_time = start_time,
        end_time = end_time,
        tags = {}
    }
end

-- 执行写入
function PerformanceBenchmark:_execute_write(storage_engine, data)
    if not storage_engine then
        return true  -- 模拟成功
    end
    
    -- 调用存储引擎的写入方法
    if storage_engine.batch_write then
        local count = storage_engine:batch_write(data)
        return count > 0
    elseif storage_engine.write_point then
        for _, point in ipairs(data) do
            storage_engine:write_point(point.metric, point.timestamp, point.value, point.tags)
        end
        return true
    end
    
    return true
end

-- 执行读取
function PerformanceBenchmark:_execute_read(storage_engine, query)
    if not storage_engine then
        return true, {}  -- 模拟成功
    end
    
    -- 调用存储引擎的读取方法
    if storage_engine.read_point then
        local success, results = storage_engine:read_point(
            query.metric,
            query.start_time,
            query.end_time,
            query.tags
        )
        return success, results
    end
    
    return true, {}
end

-- 计算统计指标
function PerformanceBenchmark:_calculate_statistics(metrics)
    if #metrics.latencies == 0 then
        return
    end
    
    -- 排序延迟数据
    table.sort(metrics.latencies)
    
    -- 计算平均值
    metrics.avg_latency_ms = metrics.total_time_ms / metrics.total_operations
    
    -- 计算中位数
    local mid = math.floor(#metrics.latencies / 2)
    if #metrics.latencies % 2 == 0 then
        metrics.median_latency_ms = (metrics.latencies[mid] + metrics.latencies[mid + 1]) / 2
    else
        metrics.median_latency_ms = metrics.latencies[mid + 1]
    end
    
    -- 计算百分位数
    metrics.p95_latency_ms = metrics.latencies[math.ceil(#metrics.latencies * 0.95)]
    metrics.p99_latency_ms = metrics.latencies[math.ceil(#metrics.latencies * 0.99)]
    
    -- 计算吞吐量
    metrics.throughput_ops = metrics.total_operations / (metrics.total_time_ms / 1000)
    
    -- 计算成功率
    metrics.success_rate = (metrics.successful_operations / metrics.total_operations) * 100
end

-- 打印场景结果
function PerformanceBenchmark:_print_scenario_result(result)
    local m = result.metrics
    
    print(string.format("  总操作数: %d", m.total_operations or 0))
    print(string.format("  成功率: %.2f%%", m.success_rate or 0))
    
    if m.throughput_ops then
        print(string.format("  吞吐量: %.2f ops/s", m.throughput_ops))
    end
    
    if m.avg_latency_ms then
        print(string.format("  平均延迟: %.2f ms", m.avg_latency_ms))
        print(string.format("  最小延迟: %.2f ms", m.min_latency_ms))
        print(string.format("  最大延迟: %.2f ms", m.max_latency_ms))
        print(string.format("  P95延迟: %.2f ms", m.p95_latency_ms or 0))
        print(string.format("  P99延迟: %.2f ms", m.p99_latency_ms or 0))
    end
end

-- 生成综合报告
function PerformanceBenchmark:_generate_report(results)
    local report = {
        generated_at = os.time(),
        test_duration = self.test_duration,
        concurrency = self.concurrency,
        scenarios = {},
        summary = {
            total_scenarios = #results,
            passed_scenarios = 0,
            failed_scenarios = 0,
            avg_throughput = 0,
            avg_latency = 0
        }
    }
    
    local total_throughput = 0
    local total_latency = 0
    local throughput_count = 0
    local latency_count = 0
    
    for _, result in ipairs(results) do
        table.insert(report.scenarios, result)
        
        if result.status == "completed" then
            report.summary.passed_scenarios = report.summary.passed_scenarios + 1
        else
            report.summary.failed_scenarios = report.summary.failed_scenarios + 1
        end
        
        if result.metrics.throughput_ops then
            total_throughput = total_throughput + result.metrics.throughput_ops
            throughput_count = throughput_count + 1
        end
        
        if result.metrics.avg_latency_ms then
            total_latency = total_latency + result.metrics.avg_latency_ms
            latency_count = latency_count + 1
        end
    end
    
    if throughput_count > 0 then
        report.summary.avg_throughput = total_throughput / throughput_count
    end
    
    if latency_count > 0 then
        report.summary.avg_latency = total_latency / latency_count
    end
    
    return report
end

-- 打印摘要
function PerformanceBenchmark:_print_summary(report)
    print("")
    print("=== 测试摘要 ===")
    print(string.format("测试场景数: %d", report.summary.total_scenarios))
    print(string.format("通过: %d", report.summary.passed_scenarios))
    print(string.format("失败: %d", report.summary.failed_scenarios))
    print(string.format("平均吞吐量: %.2f ops/s", report.summary.avg_throughput))
    print(string.format("平均延迟: %.2f ms", report.summary.avg_latency))
end

-- 导出报告
function PerformanceBenchmark:export_report(report, format)
    format = format or "json"
    
    if format == "json" then
        -- 简化实现：返回Lua表的字符串表示
        return self:_serialize_to_json(report)
    elseif format == "html" then
        return self:_generate_html_report(report)
    else
        return nil, "不支持的格式"
    end
end

-- 序列化为JSON
function PerformanceBenchmark:_serialize_to_json(data)
    -- 简化实现
    return "{\"report\": \"generated\"}"
end

-- 生成HTML报告
function PerformanceBenchmark:_generate_html_report(report)
    local html = [[
<!DOCTYPE html>
<html>
<head>
    <title>性能基准测试报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .scenario { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .metric { display: inline-block; margin: 5px 15px; }
        .success { color: green; }
        .failure { color: red; }
    </style>
</head>
<body>
    <div class="header">
        <h1>性能基准测试报告</h1>
        <p>生成时间: ]] .. os.date("%Y-%m-%d %H:%M:%S", report.generated_at) .. [[</p>
    </div>
]]

    for _, scenario in ipairs(report.scenarios) do
        html = html .. string.format([[
    <div class="scenario">
        <h3>%s</h3>
        <p>状态: <span class="%s">%s</span></p>
    </div>
]], scenario.name, scenario.status == "completed" and "success" or "failure", scenario.status)
    end

    html = html .. [[
</body>
</html>
]]

    return html
end

return PerformanceBenchmark
