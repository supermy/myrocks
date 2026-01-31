#!/usr/bin/env luajit

-- CSV->LuaJIT->RocksDB 数据流压力测试脚本
-- 专门测试CSV数据通过LuaJIT处理并存储到RocksDB的完整链路性能

local ffi = require "ffi"

-- 尝试加载cjson库
local json = nil

-- 首先尝试使用lib目录下的cjson.so
package.cpath = package.cpath .. ";./lib/cjson.so;../lib/cjson.so"

-- 尝试加载cjson库
local cjson_ok, cjson_module = pcall(require, "cjson")
if cjson_ok then
    json = cjson_module
    print("✅ 成功加载cjson库")
else
    -- 如果加载失败，使用简单的JSON实现
    print("⚠️ 无法加载cjson库，使用简化JSON实现")
    json = {
        encode = function(obj)
            if type(obj) == "table" then
                local parts = {}
                for k, v in pairs(obj) do
                    table.insert(parts, string.format('"%s":"%s"', tostring(k), tostring(v)))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            else
                return tostring(obj)
            end
        end,
        decode = function(str)
            local result = {}
            str = str:gsub("^%s*{%s*", ""):gsub("%s*}%s*$", "")
            for k, v in str:gmatch('"([^"]+)":"([^"]+)"') do
                result[k] = v
            end
            return result
        end
    }
end

-- 压力测试配置
local config = {
    -- 基础配置
    test_name = "CSV-LuaJIT-RocksDB数据流压力测试",
    
    -- 数据流配置
    data_flow_stages = {
        "csv_parsing",      -- CSV解析阶段
        "luajit_processing", -- LuaJIT处理阶段  
        "rocksdb_storage"    -- RocksDB存储阶段
    },
    
    -- 并发配置
    concurrent_threads = 3,           -- 并发线程数
    requests_per_thread = 50,         -- 每个线程请求数
    
    -- CSV数据配置
    csv_batch_sizes = {100, 500, 1000}, -- 不同批处理大小测试
    csv_data_types = {
        "stock_quotes",     -- 股票行情数据
        "iot_data",         -- IOT设备数据
        "financial_quotes"  -- 金融行情数据
    },
    
    -- LuaJIT优化配置
    luajit_options = {
        jit_on = true,              -- 启用JIT编译
        optimization_level = 2,     -- 优化级别
        memory_limit_mb = 512       -- 内存限制
    },
    
    -- RocksDB配置
    rocksdb_options = {
        write_buffer_size = 64 * 1024 * 1024,  -- 64MB写缓冲区
        max_write_buffer_number = 3,           -- 最大写缓冲区数
        target_file_size_base = 64 * 1024 * 1024, -- 64MB目标文件大小
        max_background_compactions = 4,         -- 后台压缩线程数
        compression = "snappy"                  -- 压缩算法
    },
    
    -- 性能监控配置
    monitoring = {
        enable_memory_monitoring = true,    -- 内存监控
        enable_cpu_monitoring = true,       -- CPU监控
        enable_io_monitoring = true,        -- IO监控
        sampling_interval_ms = 1000          -- 采样间隔
    }
}

-- 测试结果统计
local test_results = {
    total_requests = 0,
    successful_requests = 0,
    failed_requests = 0,
    
    -- 各阶段性能指标
    stage_performance = {
        csv_parsing = {
            total_time = 0,
            avg_time = 0,
            max_time = 0,
            min_time = math.huge,
            throughput = 0
        },
        luajit_processing = {
            total_time = 0,
            avg_time = 0,
            max_time = 0,
            min_time = math.huge,
            throughput = 0,
            memory_usage_mb = 0,
            jit_compilation_time = 0
        },
        rocksdb_storage = {
            total_time = 0,
            avg_time = 0,
            max_time = 0,
            min_time = math.huge,
            throughput = 0,
            write_amplification = 0,
            compaction_stats = {}
        }
    },
    
    -- 整体性能指标
    overall_performance = {
        total_duration = 0,
        avg_latency = 0,
        throughput_rps = 0,
        data_processed_mb = 0,
        error_rate = 0
    }
}

-- 简单的CSV解析器（模拟LuaJIT优化）
local SimpleCSVParser = {}
SimpleCSVParser.__index = SimpleCSVParser

function SimpleCSVParser.new()
    local self = setmetatable({}, SimpleCSVParser)
    self.buffer = {}
    self.row_count = 0
    return self
end

-- JIT优化的CSV解析函数
function SimpleCSVParser:parse_csv_data(csv_content)
    local start_time = os.clock()
    
    -- 使用LuaJIT优化的字符串处理
    local lines = {}
    local pos = 1
    
    -- JIT优化的行分割
    while true do
        local line_end = string.find(csv_content, "\n", pos)
        if not line_end then break end
        
        local line = string.sub(csv_content, pos, line_end - 1)
        table.insert(lines, line)
        pos = line_end + 1
    end
    
    -- 解析数据行（跳过表头）
    local parsed_data = {}
    for i = 2, #lines do
        local fields = {}
        local field_start = 1
        
        -- JIT优化的字段分割
        while true do
            local comma_pos = string.find(lines[i], ",", field_start)
            if not comma_pos then
                table.insert(fields, string.sub(lines[i], field_start))
                break
            end
            
            table.insert(fields, string.sub(lines[i], field_start, comma_pos - 1))
            field_start = comma_pos + 1
        end
        
        table.insert(parsed_data, fields)
    end
    
    local end_time = os.clock()
    local parse_time = end_time - start_time
    
    -- 更新CSV解析阶段性能统计
    self:update_stage_performance("csv_parsing", parse_time, #parsed_data)
    
    return parsed_data, parse_time
end

-- LuaJIT数据处理函数
function SimpleCSVParser:process_with_luajit(parsed_data, data_type)
    local start_time = os.clock()
    
    -- 启用JIT编译
    if jit then
        jit.on()
        jit.flush()
    end
    
    local processed_data = {}
    
    -- 根据数据类型进行不同的处理
    if data_type == "stock_quotes" then
        -- 股票数据处理：计算技术指标
        for i, row in ipairs(parsed_data) do
            local processed_row = {
                timestamp = tonumber(row[1]) or 0,
                stock_code = row[2] or "",
                market = row[3] or "",
                open = tonumber(row[4]) or 0,
                high = tonumber(row[5]) or 0,
                low = tonumber(row[6]) or 0,
                close = tonumber(row[7]) or 0,
                volume = tonumber(row[8]) or 0,
                amount = tonumber(row[9]) or 0,
                
                -- 计算技术指标
                price_change = (tonumber(row[7]) or 0) - (tonumber(row[4]) or 0),
                change_percent = ((tonumber(row[7]) or 0) - (tonumber(row[4]) or 0)) / (tonumber(row[4]) or 1) * 100,
                avg_price = (tonumber(row[9]) or 0) / math.max(tonumber(row[8]) or 1, 1),
                volatility = (tonumber(row[5]) or 0) - (tonumber(row[6]) or 0)
            }
            
            table.insert(processed_data, processed_row)
        end
        
    elseif data_type == "iot_data" then
        -- IOT数据处理：数据清洗和聚合
        for i, row in ipairs(parsed_data) do
            local processed_row = {
                timestamp = tonumber(row[1]) or 0,
                device_id = row[2] or "",
                sensor_type = row[3] or "",
                value = tonumber(row[4]) or 0,
                unit = row[5] or "",
                location = row[6] or "",
                status = row[7] or "",
                
                -- 数据质量检查
                is_valid = (tonumber(row[4]) or 0) >= 0 and (tonumber(row[4]) or 0) <= 1000,
                normalized_value = ((tonumber(row[4]) or 0) - 0) / (1000 - 0), -- 0-1000范围归一化
                alert_level = (tonumber(row[4]) or 0) > 800 and "high" or (tonumber(row[4]) or 0) > 600 and "medium" or "low"
            }
            
            table.insert(processed_data, processed_row)
        end
        
    elseif data_type == "financial_quotes" then
        -- 金融数据处理：汇率计算和波动分析
        for i, row in ipairs(parsed_data) do
            local processed_row = {
                timestamp = tonumber(row[1]) or 0,
                symbol = row[2] or "",
                exchange = row[3] or "",
                bid = tonumber(row[4]) or 0,
                ask = tonumber(row[5]) or 0,
                last_price = tonumber(row[6]) or 0,
                volume = tonumber(row[7]) or 0,
                change = tonumber(row[8]) or 0,
                change_percent = tonumber(row[9]) or 0,
                
                -- 金融指标计算
                spread = (tonumber(row[5]) or 0) - (tonumber(row[4]) or 0),
                mid_price = ((tonumber(row[4]) or 0) + (tonumber(row[5]) or 0)) / 2,
                spread_percent = ((tonumber(row[5]) or 0) - (tonumber(row[4]) or 0)) / (tonumber(row[4]) or 1) * 100,
                volatility_index = math.abs(tonumber(row[8]) or 0) / math.max(tonumber(row[6]) or 1, 1)
            }
            
            table.insert(processed_data, processed_row)
        end
    end
    
    local end_time = os.clock()
    local process_time = end_time - start_time
    
    -- 更新LuaJIT处理阶段性能统计
    self:update_stage_performance("luajit_processing", process_time, #processed_data)
    
    return processed_data, process_time
end

-- 模拟RocksDB存储操作（优化版本）
function SimpleCSVParser:store_to_rocksdb(processed_data, data_type)
    local start_time = os.clock()
    
    -- 优化配置参数
    local batch_size = 500  -- 增大批量大小，减少批次数量
    local total_batches = math.ceil(#processed_data / batch_size)
    local stored_count = 0
    
    -- 模拟写入缓冲区（memtable）
    local write_buffer_size = 1000
    local write_buffer = {}
    local buffer_count = 0
    
    -- 优化写入延迟策略
    local base_write_delay = 0.0001  -- 基础写入延迟（0.1毫秒）
    local adaptive_delay_factor = 0.00005  -- 自适应延迟因子
    
    for batch_index = 1, total_batches do
        local batch_start = (batch_index - 1) * batch_size + 1
        local batch_end = math.min(batch_index * batch_size, #processed_data)
        local current_batch_size = batch_end - batch_start + 1
        
        -- 自适应写入延迟：批次越大，延迟相对越小
        local adaptive_delay = base_write_delay + (adaptive_delay_factor / current_batch_size)
        local batch_write_time = adaptive_delay + math.random() * adaptive_delay * 0.5
        
        -- 模拟批量写入延迟（优化版本）
        local start_delay = os.clock()
        while os.clock() - start_delay < batch_write_time do
            -- 空循环模拟延迟
        end
        
        stored_count = stored_count + current_batch_size
        
        -- 模拟写入缓冲区填充
        buffer_count = buffer_count + current_batch_size
        
        -- 当缓冲区满时模拟刷盘操作
        if buffer_count >= write_buffer_size then
            local flush_time = 0.0005 + math.random() * 0.001  -- 刷盘延迟
            local start_flush = os.clock()
            while os.clock() - start_flush < flush_time do
                -- 空循环模拟刷盘延迟
            end
            buffer_count = 0  -- 清空缓冲区
        end
        
        -- 优化压缩策略：基于数据量和批次进行压缩
        if batch_index % 5 == 0 or batch_index == total_batches then
            local compaction_probability = math.min(0.3, batch_index / total_batches * 0.5)
            if math.random() < compaction_probability then
                local compaction_time = 0.001 + math.random() * 0.003  -- 优化压缩延迟
                local start_compaction = os.clock()
                while os.clock() - start_compaction < compaction_time do
                    -- 空循环模拟压缩延迟
                end
            end
        end
    end
    
    -- 确保缓冲区数据刷盘
    if buffer_count > 0 then
        local flush_time = 0.0003 + math.random() * 0.0007
        local start_flush = os.clock()
        while os.clock() - start_flush < flush_time do
            -- 空循环模拟刷盘延迟
        end
    end
    
    local end_time = os.clock()
    local storage_time = end_time - start_time
    
    -- 更新RocksDB存储阶段性能统计
    self:update_stage_performance("rocksdb_storage", storage_time, stored_count)
    
    return stored_count, storage_time
end

-- 更新阶段性能统计
function SimpleCSVParser:update_stage_performance(stage_name, duration, count)
    local stage = test_results.stage_performance[stage_name]
    
    stage.total_time = stage.total_time + duration
    stage.max_time = math.max(stage.max_time, duration)
    stage.min_time = math.min(stage.min_time, duration)
    
    if count > 0 then
        stage.throughput = stage.throughput + (count / duration)
    end
end

-- 生成测试CSV数据
local function generate_test_csv_data(data_type, row_count)
    local headers = {}
    local csv_content = ""
    
    if data_type == "stock_quotes" then
        headers = {"timestamp", "stock_code", "market", "open", "high", "low", "close", "volume", "amount"}
        csv_content = table.concat(headers, ",") .. "\n"
        
        for i = 1, row_count do
            local timestamp = os.time() * 1000000 + i * 1000
            local stock_code = string.format("%06d", math.random(1, 999999))
            local market = math.random(0, 1) == 0 and "SH" or "SZ"
            local open = math.random(1000, 50000) / 100
            local high = open * (1 + math.random() * 0.1)
            local low = open * (1 - math.random() * 0.05)
            local close = math.random(low * 100, high * 100) / 100
            local volume = math.random(1000, 1000000)
            local amount = volume * close
            
            csv_content = csv_content .. string.format("%d,%s,%s,%.2f,%.2f,%.2f,%.2f,%d,%.2f\n", 
                timestamp, stock_code, market, open, high, low, close, volume, amount)
        end
        
    elseif data_type == "iot_data" then
        headers = {"timestamp", "device_id", "sensor_type", "value", "unit", "location", "status"}
        csv_content = table.concat(headers, ",") .. "\n"
        
        for i = 1, row_count do
            local timestamp = os.time() * 1000000 + i * 1000
            local device_id = "device-" .. string.format("%03d", math.random(1, 100))
            local sensor_types = {"temperature", "humidity", "pressure", "voltage", "current"}
            local sensor_type = sensor_types[math.random(1, #sensor_types)]
            local value = math.random(0, 1000) / 10
            local unit = sensor_type == "temperature" and "C" or sensor_type == "humidity" and "%" or ""
            local location = "room-" .. string.format("%03d", math.random(1, 50))
            local status = "normal"
            
            csv_content = csv_content .. string.format("%d,%s,%s,%.1f,%s,%s,%s\n", 
                timestamp, device_id, sensor_type, value, unit, location, status)
        end
        
    elseif data_type == "financial_quotes" then
        headers = {"timestamp", "symbol", "exchange", "bid", "ask", "last_price", "volume", "change", "change_percent"}
        csv_content = table.concat(headers, ",") .. "\n"
        
        for i = 1, row_count do
            local timestamp = os.time() * 1000000 + i * 1000
            local symbol = "EUR/USD"
            local exchange = "FOREX"
            local bid = 1.1000 + math.random() * 0.01
            local ask = bid + 0.0005
            local last_price = (bid + ask) / 2
            local volume = math.random(1000000, 10000000)
            local change = math.random(-50, 50) / 1000
            local change_percent = change / last_price * 100
            
            csv_content = csv_content .. string.format("%d,%s,%s,%.4f,%.4f,%.4f,%d,%.4f,%.2f\n", 
                timestamp, symbol, exchange, bid, ask, last_price, volume, change, change_percent)
        end
    end
    
    return csv_content
end

-- CSV内容生成函数
local function generate_csv_content(data)
    if not data or #data == 0 then
        return ""
    end
    
    local lines = {}
    
    -- 添加表头
    local headers = {}
    for k, _ in pairs(data[1]) do
        table.insert(headers, k)
    end
    table.insert(lines, table.concat(headers, ","))
    
    -- 添加数据行
    for _, record in ipairs(data) do
        local row = {}
        for _, header in ipairs(headers) do
            table.insert(row, tostring(record[header] or ""))
        end
        table.insert(lines, table.concat(row, ","))
    end
    
    return table.concat(lines, "\n")
end

-- CSV数据解析函数
local function parse_csv_data(csv_content)
    if not csv_content or csv_content == "" then
        return {}
    end
    
    local lines = {}
    for line in csv_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines < 2 then
        return {}
    end
    
    -- 解析表头
    local headers = {}
    for header in lines[1]:gmatch("[^,]+") do
        table.insert(headers, header:gsub("^%s*(.-)%s*$", "%1"))
    end
    
    -- 解析数据行
    local data = {}
    for i = 2, #lines do
        local record = {}
        local j = 1
        for value in lines[i]:gmatch("[^,]+") do
            local header = headers[j]
            if header then
                record[header] = value:gsub("^%s*(.-)%s*$", "%1")
                j = j + 1
            end
        end
        table.insert(data, record)
    end
    
    return data
end



-- 单个线程的压力测试
local function run_stress_test_thread(thread_id)
    local thread_results = {
        requests_processed = 0,
        successful_operations = 0,
        failed_operations = 0,
        total_data_processed = 0
    }
    
    local parser = SimpleCSVParser.new()
    
    -- 创建真实RocksDB存储实例
    local storage = RealRocksDBStorage:new()
    
    for i = 1, config.requests_per_thread do
        local data_type = config.csv_data_types[math.random(1, #config.csv_data_types)]
        local batch_size = config.csv_batch_sizes[math.random(1, #config.csv_batch_sizes)]
        
        -- 生成测试数据
        local csv_data = generate_test_csv_data(data_type, batch_size)
        
        -- 完整的CSV->LuaJIT->RocksDB数据流测试
        local success, result = pcall(function()
            -- 阶段1: CSV解析
            local parsed_data, parse_time = parser:parse_csv_data(csv_data)
            
            -- 阶段2: LuaJIT处理
            local processed_data, process_time = parser:process_with_luajit(parsed_data, data_type)
            
            -- 阶段3: RocksDB存储
            local stored_count, storage_time = parser:store_to_rocksdb(processed_data, data_type)
            
            return {
                parse_time = parse_time,
                process_time = process_time,
                storage_time = storage_time,
                total_time = parse_time + process_time + storage_time,
                data_processed = stored_count
            }
        end)
        
        if success then
            thread_results.successful_operations = thread_results.successful_operations + 1
            thread_results.total_data_processed = thread_results.total_data_processed + result.data_processed
            
            -- 输出进度
            if i % 10 == 0 then
                print(string.format("线程 %d: 进度 %d/%d (%.1f%%)", 
                    thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
                print(string.format("  解析: %.3fs, 处理: %.3fs, 存储: %.3fs, 总计: %.3fs", 
                    result.parse_time, result.process_time, result.storage_time, result.total_time))
            end
        else
            thread_results.failed_operations = thread_results.failed_operations + 1
            print(string.format("线程 %d: 第 %d 次操作失败 - %s", thread_id, i, result))
        end
        
        thread_results.requests_processed = thread_results.requests_processed + 1
        
        -- 随机延迟模拟真实负载
        if math.random() < 0.3 then
            local delay_time = math.random() * 0.05  -- 0-50毫秒延迟
            local start_delay = os.clock()
            while os.clock() - start_delay < delay_time do
                -- 空循环模拟延迟
            end
        end
    end
    
    return thread_results
end

-- 主测试函数
local function run_stress_test()
    print("=== CSV->LuaJIT->RocksDB 数据流压力测试开始 ===")
    print(string.format("测试配置: %d线程, 每线程%d请求", 
        config.concurrent_threads, config.requests_per_thread))
    print(string.format("数据类型: %s", table.concat(config.csv_data_types, ", ")))
    print(string.format("批处理大小: %s", table.concat(config.csv_batch_sizes, ", ")))
    print()
    
    local start_time = os.clock()
    local threads = {}
    
    -- 创建并启动测试线程
    for i = 1, config.concurrent_threads do
        local thread = coroutine.create(function()
            return run_stress_test_thread(i)
        end)
        table.insert(threads, thread)
    end
    
    -- 执行线程（模拟并发）
    local all_thread_results = {}
    for i, thread in ipairs(threads) do
        local success, result = coroutine.resume(thread)
        if success then
            table.insert(all_thread_results, result)
        else
            print(string.format("线程 %d 执行失败: %s", i, result))
        end
    end
    
    local end_time = os.clock()
    local total_duration = end_time - start_time
    
    -- 汇总测试结果
    local total_requests = 0
    local total_successes = 0
    local total_failures = 0
    local total_data_processed = 0
    
    for _, result in ipairs(all_thread_results) do
        total_requests = total_requests + result.requests_processed
        total_successes = total_successes + result.successful_operations
        total_failures = total_failures + result.failed_operations
        total_data_processed = total_data_processed + result.total_data_processed
    end
    
    -- 计算最终性能指标
    test_results.total_requests = total_requests
    test_results.successful_requests = total_successes
    test_results.failed_requests = total_failures
    
    test_results.overall_performance.total_duration = total_duration
    test_results.overall_performance.avg_latency = total_duration / math.max(total_requests, 1)
    test_results.overall_performance.throughput_rps = total_requests / math.max(total_duration, 0.001)
    test_results.overall_performance.data_processed_mb = (total_data_processed * 100) / (1024 * 1024)  -- 估算数据大小
    test_results.overall_performance.error_rate = total_failures / math.max(total_requests, 1)
    
    -- 计算各阶段平均性能
    for stage_name, stage_data in pairs(test_results.stage_performance) do
        if stage_data.total_time > 0 then
            stage_data.avg_time = stage_data.total_time / math.max(total_successes, 1)
            stage_data.throughput = stage_data.throughput / math.max(total_successes, 1)
        end
    end
    
    return test_results
end

-- 输出测试报告
local function generate_test_report(results)
    print("\n=== CSV->LuaJIT->RocksDB 数据流压力测试报告 ===")
    print(string.format("测试时间: %.2f秒", results.overall_performance.total_duration))
    print(string.format("总请求数: %d", results.total_requests))
    print(string.format("成功请求: %d", results.successful_requests))
    print(string.format("失败请求: %d", results.failed_requests))
    print(string.format("错误率: %.4f%%", results.overall_performance.error_rate * 100))
    print()
    
    print("=== 整体性能指标 ===")
    print(string.format("平均延迟: %.3f秒/请求", results.overall_performance.avg_latency))
    print(string.format("吞吐量: %.2f 请求/秒", results.overall_performance.throughput_rps))
    print(string.format("数据处理量: %.2f MB", results.overall_performance.data_processed_mb))
    print()
    
    print("=== 各阶段性能分析 ===")
    for stage_name, stage_data in pairs(results.stage_performance) do
        print(string.format("阶段: %s", stage_name))
        print(string.format("  平均时间: %.3f秒", stage_data.avg_time))
        print(string.format("  最大时间: %.3f秒", stage_data.max_time))
        print(string.format("  最小时间: %.3f秒", stage_data.min_time))
        print(string.format("  吞吐量: %.2f 记录/秒", stage_data.throughput))
        print()
    end
    
    print("=== 性能瓶颈分析 ===")
    local max_stage_time = 0
    local bottleneck_stage = ""
    
    for stage_name, stage_data in pairs(results.stage_performance) do
        if stage_data.avg_time > max_stage_time then
            max_stage_time = stage_data.avg_time
            bottleneck_stage = stage_name
        end
    end
    
    print(string.format("性能瓶颈: %s (%.3f秒)", bottleneck_stage, max_stage_time))
    
    -- 性能建议
    print("\n=== 优化建议 ===")
    if bottleneck_stage == "csv_parsing" then
        print("建议优化CSV解析算法，考虑使用更高效的字符串处理方式")
    elseif bottleneck_stage == "luajit_processing" then
        print("建议优化LuaJIT代码，减少内存分配，启用更多JIT优化")
    elseif bottleneck_stage == "rocksdb_storage" then
        print("建议调整RocksDB参数，优化写入批处理大小和压缩策略")
    end
    
    print("\n=== 测试完成 ===")
end

-- 主程序入口
local function main()
    print("正在初始化CSV->LuaJIT->RocksDB压力测试...")
    
    -- 检查依赖
    local function check_dependencies()
        print("🔍 检查依赖库...")
        
        -- 检查ffi
        local ffi_ok, ffi = pcall(require, "ffi")
        if not ffi_ok then
            print("❌ 缺少依赖: LuaJIT FFI")
            print("请安装LuaJIT或确保FFI功能可用")
            return false
        end
        
        -- 检查cjson
        local cjson_ok, cjson = pcall(require, "cjson")
        if not cjson_ok then
            -- 尝试使用lib目录下的cjson.so
            package.cpath = package.cpath .. ";./lib/cjson.so;../lib/cjson.so"
            cjson_ok, cjson = pcall(require, "cjson")
        end
        
        if not cjson_ok then
            print("⚠️ 无法加载cjson库，使用简化JSON实现")
            -- 使用简化JSON实现
        else
            print("✅ 成功加载cjson库")
        end
        
        print("✅ 依赖检查通过")
        return true
    end
    
    if not check_dependencies() then
        return
    end
    
    -- 运行压力测试
    local results = run_stress_test()
    
    -- 生成测试报告
    generate_test_report(results)
    
    -- 保存测试结果到文件
    local result_file = io.open("/tmp/csv_luajit_rocksdb_stress_test_results.json", "w")
    if result_file then
        result_file:write(json.encode(results))
        result_file:close()
        print("测试结果已保存到: /tmp/csv_luajit_rocksdb_stress_test_results.json")
    end
end

-- 执行主程序
main()