#!/usr/bin/env luajit

-- CSV->LuaJIT->真实RocksDB数据流压力测试脚本 v2
-- 使用真实的RocksDB数据库，修复了所有错误

package.path = package.path .. ";./lua/?.lua"

local ffi = require "ffi"

-- 加载RocksDB FFI模块
local RocksDBFFI = require "rocksdb_ffi"

-- 检查cjson库
local cjson_ok, cjson_module = pcall(require, "cjson")
if cjson_ok then
    cjson = cjson_module
    print("✅ 成功加载cjson库")
else
    -- 尝试添加lib目录路径
    package.cpath = package.cpath .. ";./lib/cjson.so;../lib/cjson.so"
    cjson_ok, cjson_module = pcall(require, "cjson")
    if cjson_ok then
        cjson = cjson_module
        print("✅ 成功加载cjson库")
    else
        print("⚠️ 无法加载cjson库，使用简化JSON实现")
        -- 简化JSON实现
        cjson = {
            encode = function(t)
                local parts = {}
                for k, v in pairs(t) do
                    table.insert(parts, string.format('"%s":"%s"', k, tostring(v)))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        }
    end
end

-- 测试配置
local config = {
    num_threads = 3,
    requests_per_thread = 50,
    csv_data_types = {"stock_quotes", "iot_data", "financial_quotes"},
    csv_batch_sizes = {100, 200, 500},
    database_path = "/tmp/test_real_rocksdb_stress_db"
}

-- 测试结果统计
local test_results = {
    total_requests = 0,
    successful_requests = 0,
    failed_requests = 0,
    total_data_processed = 0,
    total_time = 0,
    stage_performance = {
        csv_parsing = {total_time = 0, max_time = 0, min_time = math.huge, throughput = 0},
        luajit_processing = {total_time = 0, max_time = 0, min_time = math.huge, throughput = 0},
        rocksdb_storage = {total_time = 0, max_time = 0, min_time = math.huge, throughput = 0}
    }
}

-- CSV解析器类
local SimpleCSVParser = {}
SimpleCSVParser.__index = SimpleCSVParser

function SimpleCSVParser.new()
    local self = setmetatable({}, SimpleCSVParser)
    return self
end

-- CSV数据解析
function SimpleCSVParser:parse_csv_data(csv_content)
    local start_time = os.clock()
    
    if not csv_content or csv_content == "" then
        return {}, 0
    end
    
    local lines = {}
    for line in csv_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines < 2 then
        return {}, 0
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
        if next(record) ~= nil then  -- 确保record不为空
            table.insert(data, record)
        end
    end
    
    local end_time = os.clock()
    local parse_time = end_time - start_time
    
    -- 更新CSV解析阶段性能统计
    self:update_stage_performance("csv_parsing", parse_time, #data)
    
    return data, parse_time
end

-- LuaJIT数据处理
function SimpleCSVParser:process_with_luajit(parsed_data, data_type)
    local start_time = os.clock()
    
    local processed_data = {}
    
    for i, record in ipairs(parsed_data) do
        local processed_record = {}
        
        -- 根据数据类型进行不同的处理
        if data_type == "stock_quotes" then
            processed_record = {
                timestamp = tonumber(record.timestamp) or 0,
                stock_code = record.stock_code or "",
                market = record.market or "",
                open = tonumber(record.open) or 0,
                high = tonumber(record.high) or 0,
                low = tonumber(record.low) or 0,
                close = tonumber(record.close) or 0,
                volume = tonumber(record.volume) or 0,
                amount = tonumber(record.amount) or 0,
                processed_at = os.time()
            }
            
            -- 计算涨跌幅
            if processed_record.open > 0 then
                processed_record.change = processed_record.close - processed_record.open
                processed_record.change_percent = (processed_record.change / processed_record.open) * 100
            else
                processed_record.change = 0
                processed_record.change_percent = 0
            end
            
        elseif data_type == "iot_data" then
            processed_record = {
                timestamp = tonumber(record.timestamp) or 0,
                device_id = record.device_id or "",
                sensor_type = record.sensor_type or "",
                value = tonumber(record.value) or 0,
                unit = record.unit or "",
                location = record.location or "",
                status = record.status or "normal",
                processed_at = os.time()
            }
            
            -- 数据质量检查
            if processed_record.value < 0 or processed_record.value > 1000 then
                processed_record.status = "warning"
            end
            
        elseif data_type == "financial_quotes" then
            processed_record = {
                timestamp = tonumber(record.timestamp) or 0,
                symbol = record.symbol or "",
                exchange = record.exchange or "",
                bid = tonumber(record.bid) or 0,
                ask = tonumber(record.ask) or 0,
                last_price = tonumber(record.last_price) or 0,
                volume = tonumber(record.volume) or 0,
                change = tonumber(record.change) or 0,
                change_percent = tonumber(record.change_percent) or 0,
                processed_at = os.time()
            }
            
            -- 计算价差
            processed_record.spread = processed_record.ask - processed_record.bid
        end
        
        table.insert(processed_data, processed_record)
    end
    
    local end_time = os.clock()
    local process_time = end_time - start_time
    
    -- 更新LuaJIT处理阶段性能统计
    self:update_stage_performance("luajit_processing", process_time, #processed_data)
    
    return processed_data, process_time
end

-- 真实RocksDB存储操作
function SimpleCSVParser:store_to_real_rocksdb(db, write_options, processed_data, data_type)
    local start_time = os.clock()
    local stored_count = 0
    
    -- 使用WriteBatch进行批量写入
    local batch = RocksDBFFI.create_writebatch()
    local batch_size = 100
    
    for i, record in ipairs(processed_data) do
        -- 生成RocksDB键
        local key = string.format("%s:%d:%d", data_type, record.timestamp, i)
        
        -- 序列化记录为JSON
        local value = cjson.encode(record)
        
        -- 添加到WriteBatch
        RocksDBFFI.writebatch_put(batch, key, value)
        stored_count = stored_count + 1
        
        -- 批量提交
        if i % batch_size == 0 or i == #processed_data then
            local success, err = RocksDBFFI.write_batch(db, write_options, batch)
            if not success then
                print("批量写入失败:", err)
                return stored_count, os.clock() - start_time
            end
            
            -- 清空batch
            RocksDBFFI.writebatch_clear(batch)
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
    
    if count > 0 and duration > 0 then
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

-- 单个线程的压力测试
local function run_stress_test_thread(thread_id, db, write_options)
    local thread_results = {
        requests_processed = 0,
        successful_operations = 0,
        failed_operations = 0,
        total_data_processed = 0
    }
    
    local parser = SimpleCSVParser.new()
    
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
            
            -- 阶段3: 真实RocksDB存储
            local stored_count, storage_time = parser:store_to_real_rocksdb(db, write_options, processed_data, data_type)
            
            return {
                parse_time = parse_time,
                process_time = process_time,
                storage_time = storage_time,
                total_time = parse_time + process_time + storage_time,
                data_processed = #processed_data
            }
        end)
        
        if success then
            thread_results.requests_processed = thread_results.requests_processed + 1
            thread_results.successful_operations = thread_results.successful_operations + 1
            thread_results.total_data_processed = thread_results.total_data_processed + result.data_processed
            
            -- 每10个请求输出一次进度
            if i % 10 == 0 then
                print(string.format("线程 %d: 进度 %d/%d (%.1f%%)", 
                    thread_id, i, config.requests_per_thread, (i / config.requests_per_thread) * 100))
                print(string.format("  解析: %.3fs, 处理: %.3fs, 存储: %.3fs, 总计: %.3fs", 
                    result.parse_time, result.process_time, result.storage_time, result.total_time))
            end
        else
            thread_results.requests_processed = thread_results.requests_processed + 1
            thread_results.failed_operations = thread_results.failed_operations + 1
            print(string.format("线程 %d: 请求 %d 失败 - %s", thread_id, i, result))
        end
    end
    
    return thread_results
end

-- 主测试函数
local function main()
    print("=== CSV->LuaJIT->真实RocksDB数据流压力测试 v2 ===")
    print("使用真实的RocksDB数据库进行测试")
    print("==================================================")
    
    -- 创建RocksDB数据库
    print("正在初始化RocksDB数据库...")
    
    local options = RocksDBFFI.create_options()
    RocksDBFFI.set_create_if_missing(options, true)
    RocksDBFFI.set_compression(options, 1)  -- SNAPPY压缩
    
    local write_options = RocksDBFFI.create_write_options()
    
    -- 打开数据库
    local rocksdb = RocksDBFFI.get_library()
    local errptr = ffi.new("char*[1]")
    local db = rocksdb.rocksdb_open(options, config.database_path, errptr)
    
    if errptr[0] ~= nil then
        local error_msg = ffi.string(errptr[0])
        rocksdb.rocksdb_free(errptr[0])
        print("❌ 打开RocksDB数据库失败:", error_msg)
        return
    end
    
    print("✅ RocksDB数据库初始化成功")
    
    local start_time = os.clock()
    
    -- 创建线程池
    local threads = {}
    for i = 1, config.num_threads do
        table.insert(threads, coroutine.create(function()
            return run_stress_test_thread(i, db, write_options)
        end))
    end
    
    -- 执行线程
    local thread_results = {}
    for i, thread in ipairs(threads) do
        local success, result = coroutine.resume(thread)
        if success then
            thread_results[i] = result
        else
            print("线程", i, "执行失败:", result)
        end
    end
    
    local end_time = os.clock()
    test_results.total_time = end_time - start_time
    
    -- 汇总结果
    for _, result in ipairs(thread_results) do
        test_results.total_requests = test_results.total_requests + result.requests_processed
        test_results.successful_requests = test_results.successful_requests + result.successful_operations
        test_results.failed_requests = test_results.failed_requests + result.failed_operations
        test_results.total_data_processed = test_results.total_data_processed + result.total_data_processed
    end
    
    -- 关闭数据库
    if db then
        rocksdb.rocksdb_close(db)
        print("✅ RocksDB数据库已关闭")
    end
    
    -- 输出测试报告
    print("\n=== CSV->LuaJIT->真实RocksDB数据流压力测试报告 ===")
    print(string.format("测试时间: %.2f秒", test_results.total_time))
    print(string.format("总请求数: %d", test_results.total_requests))
    print(string.format("成功请求: %d", test_results.successful_requests))
    print(string.format("失败请求: %d", test_results.failed_requests))
    
    if test_results.total_requests > 0 then
        print(string.format("错误率: %.4f", test_results.failed_requests / test_results.total_requests))
    else
        print("错误率: 1.0000")
    end
    
    print("\n=== 整体性能指标 ===")
    if test_results.total_requests > 0 then
        local avg_latency = test_results.total_time / test_results.total_requests
        local throughput = test_results.total_requests / test_results.total_time
        local data_processed_mb = test_results.total_data_processed * 100 / (1024 * 1024)  -- 估算数据量
        
        print(string.format("平均延迟: %.3f秒/请求", avg_latency))
        print(string.format("吞吐量: %.2f 请求/秒", throughput))
        print(string.format("数据处理量: %.2f MB", data_processed_mb))
    else
        print("无成功请求，无法计算性能指标")
    end
    
    print("\n=== 各阶段性能分析 ===")
    for stage_name, stats in pairs(test_results.stage_performance) do
        if test_results.total_requests > 0 then
            local avg_time = stats.total_time / test_results.total_requests
            local throughput = stats.throughput / test_results.total_requests
            
            print(string.format("阶段: %s", stage_name))
            print(string.format("  平均时间: %.3f秒", avg_time))
            print(string.format("  最大时间: %.3f秒", stats.max_time))
            print(string.format("  最小时间: %.3f秒", stats.min_time))
            print(string.format("  吞吐量: %.2f 记录/秒", throughput))
        else
            print(string.format("阶段: %s - 无数据", stage_name))
        end
    end
    
    -- 性能瓶颈分析
    if test_results.total_requests > 0 then
        local max_stage_time = 0
        local bottleneck_stage = ""
        
        for stage_name, stats in pairs(test_results.stage_performance) do
            local avg_time = stats.total_time / test_results.total_requests
            if avg_time > max_stage_time then
                max_stage_time = avg_time
                bottleneck_stage = stage_name
            end
        end
        
        print("\n=== 性能瓶颈分析 ===")
        print(string.format("性能瓶颈: %s (%.3f秒)", bottleneck_stage, max_stage_time))
        
        print("\n=== 优化建议 ===")
        if bottleneck_stage == "rocksdb_storage" then
            print("建议调整RocksDB参数，优化写入批处理大小和压缩策略")
        elseif bottleneck_stage == "csv_parsing" then
            print("建议优化CSV解析算法，减少字符串处理开销")
        elseif bottleneck_stage == "luajit_processing" then
            print("建议优化LuaJIT数据处理逻辑，减少计算复杂度")
        end
    end
    
    print("\n=== 测试完成 ===")
    
    -- 保存测试结果
    local results_file = "/tmp/csv_luajit_real_rocksdb_stress_test_v2_results.json"
    local file = io.open(results_file, "w")
    if file then
        -- 使用简化JSON保存，避免NaN/Infinity问题
        local safe_results = {
            config = config,
            results = {
                total_requests = test_results.total_requests,
                successful_requests = test_results.successful_requests,
                failed_requests = test_results.failed_requests,
                total_time = test_results.total_time,
                total_data_processed = test_results.total_data_processed
            },
            timestamp = os.time()
        }
        
        if cjson_ok then
            file:write(cjson.encode(safe_results))
        else
            file:write("{\"config\":{\"num_threads\":" .. config.num_threads .. "},\"results\":{\"total_requests\":" .. test_results.total_requests .. "}}")
        end
        file:close()
        print("测试结果已保存到:", results_file)
    end
end

-- 运行主函数
main()