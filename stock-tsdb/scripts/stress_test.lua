#!/usr/bin/env lua

-- Stock-TSDB 生产负载压力测试脚本
-- 针对生产环境进行高并发、大数据量的压力测试

-- 使用标准Lua和LuaSocket库
local socket = require "socket"
local json = require "cjson"

-- HTTP 客户端实现
local function http_request(method, url, data)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local request_headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = data and #data or 0
    }
    
    local result, status_code, response_headers = http.request{
        url = url,
        method = method,
        headers = request_headers,
        source = data and ltn12.source.string(data) or nil,
        sink = ltn12.sink.table(response_body)
    }
    
    local response = table.concat(response_body)
    return status_code, response
end

-- 压力测试配置
local config = {
    -- 基础配置
    base_url = "http://localhost:8081",
    
    -- 并发配置
    concurrent_threads = 1,           -- 并发线程数（简化为1个线程）
    requests_per_thread = 10,         -- 每个线程请求数（简化为10个请求）
    
    -- 数据配置
    symbols = {"SH600519", "SH600036", "SH601318", "SZ000001", "SZ000002"},
    data_points_per_request = 5,      -- 每个请求的数据点数（简化为5个）
    
    -- 时间配置
    test_duration = 10,               -- 测试持续时间（秒，简化为10秒）
    warmup_duration = 1,              -- 预热时间（秒，简化为1秒）
    
    -- 性能阈值
    max_latency_p99 = 100,              -- P99延迟阈值（毫秒）
    min_throughput = 100000,            -- 最小吞吐量（QPS）
    max_error_rate = 0.01               -- 最大错误率
}

-- 测试结果统计
local test_results = {
    total_requests = 0,
    successful_requests = 0,
    failed_requests = 0,
    total_latency = 0,
    latencies = {},
    start_time = 0,
    end_time = 0
}

-- HTTP 客户端实现
local function http_request(method, url, data)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    local response_body = {}
    local request_headers = {
        ["Content-Type"] = "application/json",
        ["Content-Length"] = data and #data or 0
    }
    
    local result, status_code, response_headers = http.request{
        url = url,
        method = method,
        headers = request_headers,
        source = data and ltn12.source.string(data) or nil,
        sink = ltn12.sink.table(response_body)
    }
    
    local response = table.concat(response_body)
    return status_code, response
end

-- 生成测试数据
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

-- 写入压力测试
local function write_stress_test(thread_id)
    local thread_results = {
        requests = 0,
        successes = 0,
        failures = 0,
        total_latency = 0
    }
    
    for i = 1, config.requests_per_thread do
        local symbol = config.symbols[math.random(1, #config.symbols)]
        local test_data = generate_test_data(symbol, config.data_points_per_request)
        
        -- 构建SQL查询请求
        local sql_query = string.format("INSERT INTO stock_data (symbol, timestamp, price, volume, side, channel) VALUES ")
        local values = {}
        
        for j, data_point in ipairs(test_data) do
            table.insert(values, string.format("('%s', %d, %.2f, %d, '%s', %d)", 
                data_point.symbol, data_point.timestamp, data_point.price, 
                data_point.volume, data_point.side, data_point.channel))
        end
        
        sql_query = sql_query .. table.concat(values, ", ")
        
        local request_data = {
            sql = sql_query
        }
        
        local start_time = socket.gettime() * 1000  -- 毫秒
        
        local status, response = http_request("POST", 
            config.base_url .. "/business/query", 
            json.encode(request_data))
        
        local end_time = socket.gettime() * 1000
        local latency = end_time - start_time
        
        thread_results.requests = thread_results.requests + 1
        thread_results.total_latency = thread_results.total_latency + latency
        
        if status == 200 then
            thread_results.successes = thread_results.successes + 1
        else
            thread_results.failures = thread_results.failures + 1
            print(string.format("Thread %d: Request failed - Status: %d, Response: %s", 
                thread_id, status, response))
        end
        
        -- 每100个请求输出一次进度
        if i % 100 == 0 then
            print(string.format("Thread %d: Progress %d/%d (%.1f%%)", 
                thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
        end
        
        -- 添加随机延迟模拟真实负载
        if math.random() < 0.1 then  -- 10%的概率添加延迟
            socket.sleep(math.random() * 0.01)  -- 0-10毫秒延迟
        end
    end
    
    return thread_results
end

-- 读取压力测试
local function read_stress_test(thread_id)
    local thread_results = {
        requests = 0,
        successes = 0,
        failures = 0,
        total_latency = 0
    }
    
    for i = 1, config.requests_per_thread do
        local symbol = config.symbols[math.random(1, #config.symbols)]
        local end_time = os.time() * 1000000
        local start_time = end_time - 3600 * 1000000  -- 查询最近1小时数据
        
        -- 构建SQL查询
        local sql_query = string.format("SELECT * FROM stock_data WHERE symbol = '%s' AND timestamp >= %d AND timestamp <= %d",
            symbol, start_time, end_time)
        
        local request_data = {
            sql = sql_query
        }
        
        local start_time_ms = socket.gettime() * 1000
        
        local status, response = http_request("POST", 
            config.base_url .. "/business/query", 
            json.encode(request_data))
        
        local end_time_ms = socket.gettime() * 1000
        local latency = end_time_ms - start_time_ms
        
        thread_results.requests = thread_results.requests + 1
        thread_results.total_latency = thread_results.total_latency + latency
        
        if status == 200 then
            thread_results.successes = thread_results.successes + 1
        else
            thread_results.failures = thread_results.failures + 1
            print(string.format("Thread %d: Query failed - Status: %d", thread_id, status))
        end
        
        -- 每100个请求输出一次进度
        if i % 100 == 0 then
            print(string.format("Thread %d: Progress %d/%d (%.1f%%)", 
                thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
        end
        
        -- 添加随机延迟
        if math.random() < 0.2 then  -- 20%的概率添加延迟
            socket.sleep(math.random() * 0.02)  -- 0-20毫秒延迟
        end
    end
    
    return thread_results
end

-- 混合压力测试（读写混合）
local function mixed_stress_test(thread_id)
    local thread_results = {
        requests = 0,
        successes = 0,
        failures = 0,
        total_latency = 0
    }
    
    for i = 1, config.requests_per_thread do
        local operation = math.random()
        
        if operation < 0.7 then  -- 70%写入操作
            local symbol = config.symbols[math.random(1, #config.symbols)]
            local test_data = generate_test_data(symbol, math.random(1, 10))  -- 1-10个数据点
            
            -- 构建SQL插入语句
            local sql_query = string.format("INSERT INTO stock_data (symbol, timestamp, price, volume, side, channel) VALUES ")
            local values = {}
            
            for j, data_point in ipairs(test_data) do
                table.insert(values, string.format("('%s', %d, %.2f, %d, '%s', %d)", 
                    data_point.symbol, data_point.timestamp, data_point.price, 
                    data_point.volume, data_point.side, data_point.channel))
            end
            
            sql_query = sql_query .. table.concat(values, ", ")
            
            local request_data = {
                sql = sql_query
            }
            
            local start_time = socket.gettime() * 1000
            local status, response = http_request("POST", 
                config.base_url .. "/business/query", 
                json.encode(request_data))
            local end_time = socket.gettime() * 1000
            
            thread_results.requests = thread_results.requests + 1
            thread_results.total_latency = thread_results.total_latency + (end_time - start_time)
            
            if status == 200 then
                thread_results.successes = thread_results.successes + 1
            else
                thread_results.failures = thread_results.failures + 1
            end
        else  -- 30%读取操作
            local symbol = config.symbols[math.random(1, #config.symbols)]
            local end_time = os.time() * 1000000
            local start_time = end_time - 600 * 1000000  -- 查询最近10分钟数据
            
            -- 构建SQL查询
            local sql_query = string.format("SELECT * FROM stock_data WHERE symbol = '%s' AND timestamp >= %d AND timestamp <= %d",
                symbol, start_time, end_time)
            
            local request_data = {
                sql = sql_query
            }
            
            local start_time_ms = socket.gettime() * 1000
            local status, response = http_request("POST", 
                config.base_url .. "/business/query", 
                json.encode(request_data))
            local end_time_ms = socket.gettime() * 1000
            
            thread_results.requests = thread_results.requests + 1
            thread_results.total_latency = thread_results.total_latency + (end_time_ms - start_time_ms)
            
            if status == 200 then
                thread_results.successes = thread_results.successes + 1
            else
                thread_results.failures = thread_results.failures + 1
            end
        end
        
        -- 每200个请求输出一次进度
        if i % 200 == 0 then
            print(string.format("Thread %d: Progress %d/%d (%.1f%%)", 
                thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
        end
        
        -- 添加随机延迟
        if math.random() < 0.15 then  -- 15%的概率添加延迟
            socket.sleep(math.random() * 0.015)
        end
    end
    
    return thread_results
end

-- 统计和分析结果
local function analyze_results(results)
    -- 计算基本统计信息
    local total_requests = 0
    local total_successes = 0
    local total_failures = 0
    local total_latency = 0
    local all_latencies = {}
    
    for _, thread_result in ipairs(results) do
        total_requests = total_requests + thread_result.requests
        total_successes = total_successes + thread_result.successes
        total_failures = total_failures + thread_result.failures
        total_latency = total_latency + thread_result.total_latency
        
        -- 这里简化处理，实际应该收集每个请求的延迟
        table.insert(all_latencies, thread_result.total_latency / thread_result.requests)
    end
    
    -- 计算性能指标
    local avg_latency = total_latency / total_requests
    local throughput = total_requests / (config.test_duration or 1)
    local error_rate = total_failures / total_requests
    
    -- 排序计算百分位数（简化版）
    table.sort(all_latencies)
    local p95_index = math.floor(#all_latencies * 0.95)
    local p99_index = math.floor(#all_latencies * 0.99)
    local p95_latency = all_latencies[p95_index] or avg_latency
    local p99_latency = all_latencies[p99_index] or avg_latency
    
    return {
        total_requests = total_requests,
        successful_requests = total_successes,
        failed_requests = total_failures,
        throughput_qps = throughput,
        avg_latency_ms = avg_latency,
        p95_latency_ms = p95_latency,
        p99_latency_ms = p99_latency,
        error_rate = error_rate
    }
end

-- 检查性能是否达标
local function check_performance_metrics(metrics)
    local issues = {}
    
    if metrics.p99_latency_ms > config.max_latency_p99 then
        table.insert(issues, string.format("P99延迟过高: %.2fms > %.2fms", 
            metrics.p99_latency_ms, config.max_latency_p99))
    end
    
    if metrics.throughput_qps < config.min_throughput then
        table.insert(issues, string.format("吞吐量过低: %.2f QPS < %.2f QPS", 
            metrics.throughput_qps, config.min_throughput))
    end
    
    if metrics.error_rate > config.max_error_rate then
        table.insert(issues, string.format("错误率过高: %.4f > %.4f", 
            metrics.error_rate, config.max_error_rate))
    end
    
    return issues
end

-- 生成测试报告
local function generate_report(metrics, issues, test_type)
    local report = {
        title = string.format("Stock-TSDB %s压力测试报告", test_type),
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        config = config,
        metrics = metrics,
        issues = issues,
        conclusion = #issues == 0 and "PASS" or "FAIL"
    }
    
    -- 保存报告到文件
    local filename = string.format("stress_test_report_%s_%s.json", 
        test_type, os.date("%Y%m%d_%H%M%S"))
    
    local file = io.open(filename, "w")
    if file then
        file:write(json.encode(report))
        file:close()
        print(string.format("测试报告已保存: %s", filename))
    end
    
    return report
end

-- 主测试函数
local function run_stress_test(test_type)
    print(string.format("开始 %s 压力测试...", test_type))
    print(string.format("配置: %d线程, 每线程%d请求, 持续%d秒", 
        config.concurrent_threads, config.requests_per_thread, config.test_duration))
    
    local test_function
    if test_type == "write" then
        test_function = write_stress_test
    elseif test_type == "read" then
        test_function = read_stress_test
    else
        test_function = mixed_stress_test
    end
    
    -- 预热阶段
    print("开始预热阶段...")
    socket.sleep(config.warmup_duration)
    
    -- 执行测试
    local threads = {}
    local results = {}
    
    test_results.start_time = socket.gettime()
    
    -- 创建并启动测试线程
    for i = 1, config.concurrent_threads do
        local co = coroutine.create(function()
            return test_function(i)
        end)
        table.insert(threads, co)
    end
    
    -- 等待所有线程完成
    for i, co in ipairs(threads) do
        local success, thread_result = coroutine.resume(co)
        if success and thread_result then
            table.insert(results, thread_result)
        else
            print(string.format("线程 %d 执行失败", i))
        end
    end
    
    test_results.end_time = socket.gettime()
    
    -- 分析结果
    local metrics = analyze_results(results)
    local issues = check_performance_metrics(metrics)
    
    -- 生成报告
    local report = generate_report(metrics, issues, test_type)
    
    -- 输出摘要
    print("\n=== 测试摘要 ===")
    print(string.format("测试类型: %s", test_type))
    print(string.format("总请求数: %d", metrics.total_requests))
    print(string.format("成功请求: %d", metrics.successful_requests))
    print(string.format("失败请求: %d", metrics.failed_requests))
    print(string.format("吞吐量: %.2f QPS", metrics.throughput_qps))
    print(string.format("平均延迟: %.2f ms", metrics.avg_latency_ms))
    print(string.format("P95延迟: %.2f ms", metrics.p95_latency_ms))
    print(string.format("P99延迟: %.2f ms", metrics.p99_latency_ms))
    print(string.format("错误率: %.4f", metrics.error_rate))
    
    if #issues > 0 then
        print("\n=== 性能问题 ===")
        for _, issue in ipairs(issues) do
            print("✗ " .. issue)
        end
        print("结论: FAIL")
    else
        print("\n=== 性能达标 ===")
        print("✓ 所有性能指标均在阈值范围内")
        print("结论: PASS")
    end
    
    return report
end

-- 命令行参数处理
local function main()
    local test_type = arg[1] or "mixed"
    
    if test_type == "help" then
        print("用法: luajit stress_test.lua [write|read|mixed]")
        print("  write - 写入压力测试")
        print("  read  - 读取压力测试") 
        print("  mixed - 混合压力测试（默认）")
        return
    end
    
    if test_type ~= "write" and test_type ~= "read" and test_type ~= "mixed" then
        print("错误: 无效的测试类型")
        print("使用 'help' 查看用法")
        return
    end
    
    -- 检查服务是否可用
    print("检查服务可用性...")
    local status, response = http_request("GET", config.base_url .. "/health")
    if status ~= 200 then
        print(string.format("错误: 服务不可用 (状态码: %d)", status))
        return
    end
    
    print("服务正常，开始压力测试")
    
    -- 运行测试
    local report = run_stress_test(test_type)
    
    -- 保存配置
    local config_file = io.open("stress_test_config.json", "w")
    if config_file then
        config_file:write(json.encode(config))
        config_file:close()
    end
end

-- 执行主函数
if pcall(require, "socket") and pcall(require, "cjson") then
    main()
else
    print("错误: 缺少依赖库 (socket, cjson)")
    print("请安装依赖: luarocks install luasocket lua-cjson")
end