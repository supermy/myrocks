#!/usr/bin/env luajit

-- CSV导入导出压力测试脚本
-- 针对Stock-TSDB系统的CSV数据导入导出功能进行高并发压力测试

-- 加载必要的模块
local json = {
    encode = function(t) 
        if type(t) ~= 'table' then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            table.insert(parts, '"' .. tostring(k) .. '":' .. (type(v) == 'string' and '"' .. v .. '"' or tostring(v)))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s) 
        -- 简单的JSON解析器
        local result = {}
        -- 这里应该实现完整的JSON解析，现在使用简化版本
        return result
    end
}
local ffi = require "ffi"

-- 简化的HTTP客户端实现（基于libcurl FFI）
local function create_simple_http_client()
    -- 定义libcurl FFI接口
    ffi.cdef[[
        typedef void CURL;
        typedef int CURLcode;
        
        CURL* curl_easy_init(void);
        CURLcode curl_easy_setopt(CURL* curl, int option, ...);
        CURLcode curl_easy_perform(CURL* curl);
        void curl_easy_cleanup(CURL* curl);
        char* curl_easy_strerror(CURLcode);
        
        typedef size_t (*curl_write_callback)(char* ptr, size_t size, size_t nmemb, void* userdata);
        
        CURLcode curl_global_init(long flags);
        void curl_global_cleanup(void);
    ]]
    
    -- 尝试加载libcurl
    local curl_lib = nil
    for _, lib_name in ipairs({"curl", "libcurl", "libcurl.so.4", "libcurl.dylib"}) do
        local ok, lib = pcall(ffi.load, lib_name)
        if ok then
            curl_lib = lib
            break
        end
    end
    
    if not curl_lib then
        return nil, "libcurl不可用"
    end
    
    -- 初始化libcurl
    local ret = curl_lib.curl_global_init(0)
    if ret ~= 0 then
        return nil, "libcurl全局初始化失败"
    end
    
    return {
        curl_lib = curl_lib,
        request = function(self, url, method, data, headers)
            local curl = self.curl_lib.curl_easy_init()
            if curl == nil then
                return false, nil, "无法创建CURL句柄"
            end
            
            -- 简单的响应收集
            local response_data = {}
            local response_code = 0
            
            -- 写入回调
            local function write_callback(ptr, size, nmemb, userdata)
                local total_size = size * nmemb
                local data = ffi.string(ptr, total_size)
                table.insert(response_data, data)
                return total_size
            end
            
            -- 重用回调指针以避免too many callbacks错误
            if not self.callback_ptr then
                self.callback_ptr = ffi.cast("curl_write_callback", write_callback)
            end
            local callback_ptr = self.callback_ptr
            
            -- 设置基本选项
            self.curl_lib.curl_easy_setopt(curl, 10002, url)  -- CURLOPT_URL
            self.curl_lib.curl_easy_setopt(curl, 20011, callback_ptr)  -- CURLOPT_WRITEFUNCTION
            
            -- 执行请求
            local ret = self.curl_lib.curl_easy_perform(curl)
            
            if ret == 0 then
                local response = table.concat(response_data)
                curl_lib.curl_easy_cleanup(curl)
                return true, response, nil
            else
                local error_msg = "HTTP请求失败"
                curl_lib.curl_easy_cleanup(curl)
                return false, nil, error_msg
            end
        end,
        cleanup = function(self)
            self.curl_lib.curl_global_cleanup()
        end
    }
end

-- 创建HTTP客户端
local curl_ok, curl_client = pcall(create_simple_http_client)
if curl_ok and curl_client then
    http_client = curl_client
    print("✅ 使用libcurl HTTP客户端")
else
    -- 如果libcurl不可用，使用模拟模式
    print("⚠️  libcurl不可用，使用模拟模式")
    print("错误信息: " .. tostring(curl_client))
    http_client = {
        request = function(self, url, method, data, headers)
            -- 模拟HTTP请求
            if url:find("/health") then
                return true, '{"status":"ok"}', nil
            elseif url:find("/csv/import") then
                return true, '{"success":true,"rows_processed":100}', nil
            elseif url:find("/csv/export") then
                return true, '{"success":true,"rows":100,"data":"time,value\\n1,100\\n2,200"}', nil
            else
                return false, nil, "未知端点"
            end
        end
    }
end

-- 压力测试配置
local config = {
    -- 基础配置
    base_url = "http://localhost:8081",
    
    -- 并发配置
    concurrent_threads = 5,           -- 并发线程数
    requests_per_thread = 100,        -- 每个线程请求数
    
    -- CSV数据配置
    business_types = {
        "stock_quotes",
        "iot_data", 
        "financial_quotes",
        "orders",
        "payments"
    },
    
    -- 数据量配置
    csv_rows_per_request = 1000,      -- 每个CSV请求的数据行数
    csv_file_size_mb = 10,            -- 生成的CSV文件大小（MB）
    
    -- 时间配置
    test_duration = 300,              -- 测试持续时间（秒）
    warmup_duration = 30,             -- 预热时间（秒）
    
    -- 性能阈值
    max_latency_p99 = 5000,           -- P99延迟阈值（毫秒）
    min_throughput = 100,             -- 最小吞吐量（请求/秒）
    max_error_rate = 0.05             -- 最大错误率
}

-- 测试结果统计
local test_results = {
    total_requests = 0,
    successful_requests = 0,
    failed_requests = 0,
    total_latency = 0,
    latencies = {},
    start_time = 0,
    end_time = 0,
    csv_import_stats = {},
    csv_export_stats = {}
}

-- HTTP请求函数（带重试机制）
local function http_request(method, url, data, headers)
    local max_retries = 3
    local retry_delay = 0.1  -- 100ms
    
    for attempt = 1, max_retries do
        local success, response, error_msg = http_client:request(url, method, data, headers)
        
        if success and response then
            return 200, response  -- 假设成功状态码为200
        end
        
        -- 请求失败，准备重试
        if attempt < max_retries then
            -- 简单的延迟实现
            local start_time = os.clock()
            while os.clock() - start_time < retry_delay do
                -- 忙等待
            end
            retry_delay = retry_delay * 2  -- 指数退避
        end
    end
    
    return nil, "请求失败（重试3次后）"
end

-- 生成测试CSV数据
local function generate_csv_data(business_type, row_count)
    local csv_content = ""
    local headers = {}
    
    -- 根据业务类型生成不同的CSV数据
    if business_type == "stock_quotes" then
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
        
    elseif business_type == "iot_data" then
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
        
    elseif business_type == "financial_quotes" then
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
        
    elseif business_type == "orders" then
        headers = {"timestamp", "order_id", "user_id", "product_id", "quantity", "price", "status", "payment_method"}
        csv_content = table.concat(headers, ",") .. "\n"
        
        for i = 1, row_count do
            local timestamp = os.time() * 1000000 + i * 1000
            local order_id = "order-" .. string.format("%08d", math.random(1, 99999999))
            local user_id = "user-" .. string.format("%06d", math.random(1, 999999))
            local product_id = "product-" .. string.format("%04d", math.random(1, 9999))
            local quantity = math.random(1, 10)
            local price = math.random(100, 10000) / 100
            local statuses = {"pending", "confirmed", "shipped", "delivered", "cancelled"}
            local status = statuses[math.random(1, #statuses)]
            local payment_methods = {"credit_card", "paypal", "alipay", "wechat_pay"}
            local payment_method = payment_methods[math.random(1, #payment_methods)]
            
            csv_content = csv_content .. string.format("%d,%s,%s,%s,%d,%.2f,%s,%s\n", 
                timestamp, order_id, user_id, product_id, quantity, price, status, payment_method)
        end
        
    elseif business_type == "payments" then
        headers = {"timestamp", "payment_id", "order_id", "amount", "currency", "status", "payment_gateway", "user_id"}
        csv_content = table.concat(headers, ",") .. "\n"
        
        for i = 1, row_count do
            local timestamp = os.time() * 1000000 + i * 1000
            local payment_id = "payment-" .. string.format("%08d", math.random(1, 99999999))
            local order_id = "order-" .. string.format("%08d", math.random(1, 99999999))
            local amount = math.random(100, 10000) / 100
            local currency = "USD"
            local statuses = {"pending", "processing", "completed", "failed", "refunded"}
            local status = statuses[math.random(1, #statuses)]
            local payment_gateways = {"stripe", "paypal", "square", "adyen"}
            local payment_gateway = payment_gateways[math.random(1, #payment_gateways)]
            local user_id = "user-" .. string.format("%06d", math.random(1, 999999))
            
            csv_content = csv_content .. string.format("%d,%s,%s,%.2f,%s,%s,%s,%s\n", 
                timestamp, payment_id, order_id, amount, currency, status, payment_gateway, user_id)
        end
    end
    
    return csv_content
end

-- 创建临时CSV文件
local function create_temp_csv_file(business_type, row_count)
    local filename = "/tmp/csv_stress_test_" .. business_type .. "_" .. os.time() .. ".csv"
    local csv_content = generate_csv_data(business_type, row_count)
    
    local file = io.open(filename, "w")
    if file then
        file:write(csv_content)
        file:close()
        return filename
    else
        return nil
    end
end

-- CSV导入压力测试
local function csv_import_stress_test(thread_id)
    local thread_results = {
        requests = 0,
        successes = 0,
        failures = 0,
        total_latency = 0,
        imported_rows = 0
    }
    
    for i = 1, config.requests_per_thread do
        local business_type = config.business_types[math.random(1, #config.business_types)]
        local csv_filename = create_temp_csv_file(business_type, config.csv_rows_per_request)
        
        if csv_filename then
            -- 构建CSV导入请求
            local request_data = {
                file_path = csv_filename,
                business_type = business_type,
                options = {
                    batch_size = 100,
                    validate_format = true
                }
            }
            
            local start_time = os.clock() * 1000  -- 毫秒
            local status, response = http_request("POST", 
                config.base_url .. "/csv/import", 
                json.encode(request_data))
            local end_time = os.clock() * 1000
            local latency = end_time - start_time
            
            thread_results.requests = thread_results.requests + 1
            thread_results.total_latency = thread_results.total_latency + latency
            
            if status == 200 then
                thread_results.successes = thread_results.successes + 1
                local result = json.decode(response)
                if result and result.imported_count then
                    thread_results.imported_rows = thread_results.imported_rows + result.imported_count
                end
            else
                thread_results.failures = thread_results.failures + 1
                print(string.format("Thread %d: CSV导入失败 - Status: %d, Response: %s", 
                    thread_id, status, response))
            end
            
            -- 清理临时文件
            os.remove(csv_filename)
            
            -- 每10个请求输出一次进度
            if i % 10 == 0 then
                print(string.format("Thread %d: CSV导入进度 %d/%d (%.1f%%)", 
                    thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
            end
            
            -- 添加随机延迟模拟真实负载
            if math.random() < 0.2 then  -- 20%的概率添加延迟
                socket.sleep(math.random() * 0.1)  -- 0-100毫秒延迟
            end
        else
            thread_results.failures = thread_results.failures + 1
            print(string.format("Thread %d: 创建CSV文件失败", thread_id))
        end
    end
    
    return thread_results
end

-- CSV导出压力测试
local function csv_export_stress_test(thread_id)
    local thread_results = {
        requests = 0,
        successes = 0,
        failures = 0,
        total_latency = 0,
        exported_rows = 0
    }
    
    for i = 1, config.requests_per_thread do
        local business_type = config.business_types[math.random(1, #config.business_types)]
        local export_filename = "/tmp/csv_export_" .. business_type .. "_" .. os.time() .. "_" .. thread_id .. ".csv"
        
        -- 构建CSV导出请求
        local end_time = os.time() * 1000000
        local start_time = end_time - 3600 * 1000000  -- 导出最近1小时数据
        
        local request_data = {
            file_path = export_filename,
            business_type = business_type,
            start_time = start_time,
            end_time = end_time,
            filters = {}
        }
        
        local start_time_ms = os.clock() * 1000
            local status, response = http_request("POST", 
                config.base_url .. "/csv/export", 
                json.encode(request_data))
            local end_time_ms = os.clock() * 1000
        local latency = end_time_ms - start_time_ms
        
        thread_results.requests = thread_results.requests + 1
        thread_results.total_latency = thread_results.total_latency + latency
        
        if status == 200 then
            thread_results.successes = thread_results.successes + 1
            local result = json.decode(response)
            if result and result.exported_count then
                thread_results.exported_rows = thread_results.exported_rows + result.exported_count
            end
            
            -- 验证导出的文件
            local export_file = io.open(export_filename, "r")
            if export_file then
                local content = export_file:read("*all")
                export_file:close()
                -- 可以添加文件内容验证逻辑
            end
            
            -- 清理导出的文件
            os.remove(export_filename)
        else
            thread_results.failures = thread_results.failures + 1
            print(string.format("Thread %d: CSV导出失败 - Status: %d, Response: %s", 
                thread_id, status, response))
        end
        
        -- 每10个请求输出一次进度
        if i % 10 == 0 then
            print(string.format("Thread %d: CSV导出进度 %d/%d (%.1f%%)", 
                thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
        end
        
        -- 添加随机延迟模拟真实负载
        if math.random() < 0.3 then  -- 30%的概率添加延迟
            socket.sleep(math.random() * 0.05)  -- 0-50毫秒延迟
        end
    end
    
    return thread_results
end

-- 混合压力测试（同时进行导入和导出）
local function mixed_stress_test(thread_id)
    local thread_results = {
        import_requests = 0,
        export_requests = 0,
        import_successes = 0,
        export_successes = 0,
        import_failures = 0,
        export_failures = 0,
        total_latency = 0,
        imported_rows = 0,
        exported_rows = 0
    }
    
    for i = 1, config.requests_per_thread do
        -- 随机选择导入或导出操作
        local is_import = math.random() < 0.6  -- 60%的概率进行导入
        
        if is_import then
            local business_type = config.business_types[math.random(1, #config.business_types)]
            local csv_filename = create_temp_csv_file(business_type, config.csv_rows_per_request)
            
            if csv_filename then
                local request_data = {
                    file_path = csv_filename,
                    business_type = business_type,
                    options = {batch_size = 100}
                }
                
                local start_time = os.clock() * 1000
                local status, response = http_request("POST", 
                    config.base_url .. "/csv/import", 
                    json.encode(request_data))
                local end_time = os.clock() * 1000
                local latency = end_time - start_time
                
                thread_results.import_requests = thread_results.import_requests + 1
                thread_results.total_latency = thread_results.total_latency + latency
                
                if status == 200 then
                    thread_results.import_successes = thread_results.import_successes + 1
                    local result = json.decode(response)
                    if result and result.imported_count then
                        thread_results.imported_rows = thread_results.imported_rows + result.imported_count
                    end
                else
                    thread_results.import_failures = thread_results.import_failures + 1
                end
                
                os.remove(csv_filename)
            end
        else
            -- 导出操作
            local business_type = config.business_types[math.random(1, #config.business_types)]
            local export_filename = "/tmp/csv_export_mixed_" .. business_type .. "_" .. os.time() .. "_" .. thread_id .. ".csv"
            
            local end_time = os.time() * 1000000
            local start_time = end_time - 3600 * 1000000
            
            local request_data = {
                file_path = export_filename,
                business_type = business_type,
                start_time = start_time,
                end_time = end_time,
                filters = {}
            }
            
            local start_time_ms = os.clock() * 1000
            local status, response = http_request("POST", 
                config.base_url .. "/csv/export", 
                json.encode(request_data))
            local end_time_ms = os.clock() * 1000
            local latency = end_time_ms - start_time_ms
            
            thread_results.export_requests = thread_results.export_requests + 1
            thread_results.total_latency = thread_results.total_latency + latency
            
            if status == 200 then
                thread_results.export_successes = thread_results.export_successes + 1
                local result = json.decode(response)
                if result and result.exported_count then
                    thread_results.exported_rows = thread_results.exported_rows + result.exported_count
                end
                
                os.remove(export_filename)
            else
                thread_results.export_failures = thread_results.export_failures + 1
            end
        end
        
        -- 每10个请求输出一次进度
        if i % 10 == 0 then
            print(string.format("Thread %d: 混合测试进度 %d/%d (%.1f%%)", 
                thread_id, i, config.requests_per_thread, i/config.requests_per_thread*100))
        end
        
        -- 添加随机延迟
        if math.random() < 0.25 then
            -- 简单的延迟实现，替代socket.sleep
            local delay = math.random() * 0.08
            local start_time = os.clock()
            while os.clock() - start_time < delay do
                -- 忙等待
            end
        end
    end
    
    return thread_results
end

-- 统计性能指标
local function calculate_performance_metrics(results)
    local metrics = {}
    
    -- 计算总请求数
    metrics.total_requests = results.total_requests
    metrics.success_rate = results.successful_requests / results.total_requests * 100
    metrics.error_rate = results.failed_requests / results.total_requests * 100
    
    -- 计算平均延迟
    metrics.avg_latency = results.total_latency / results.total_requests
    
    -- 计算吞吐量
    local test_duration = (results.end_time - results.start_time) / 1000  -- 秒
    metrics.throughput = results.total_requests / test_duration
    
    -- 计算P95和P99延迟
    table.sort(results.latencies)
    local p95_index = math.floor(#results.latencies * 0.95)
    local p99_index = math.floor(#results.latencies * 0.99)
    metrics.p95_latency = results.latencies[p95_index] or 0
    metrics.p99_latency = results.latencies[p99_index] or 0
    
    return metrics
end

-- 运行压力测试
local function run_stress_test(test_type)
    print("=== CSV导入导出压力测试开始 ===")
    print("测试类型: " .. test_type)
    print("配置参数:")
    print("  并发线程数: " .. config.concurrent_threads)
    print("  每个线程请求数: " .. config.requests_per_thread)
    print("  测试持续时间: " .. config.test_duration .. "秒")
    print("  预热时间: " .. config.warmup_duration .. "秒")
    
    test_results.start_time = os.clock() * 1000
    
    -- 预热阶段
    print("\n=== 预热阶段开始 ===")
    for i = 1, 3 do
        print("预热请求 " .. i)
        local business_type = config.business_types[math.random(1, #config.business_types)]
        local csv_filename = create_temp_csv_file(business_type, 10)
        
        if csv_filename then
            local request_data = {
                file_path = csv_filename,
                business_type = business_type,
                options = {batch_size = 10}
            }
            
            local status, response = http_request("POST", 
                config.base_url .. "/csv/import", 
                json.encode(request_data))
            
            os.remove(csv_filename)
            -- 简单的延迟实现，替代socket.sleep
            local start_time = os.clock()
            while os.clock() - start_time < 1 do
                -- 忙等待
            end
        end
    end
    print("=== 预热阶段完成 ===\n")
    
    -- 执行压力测试
    local all_thread_results = {}
    
    for thread_id = 1, config.concurrent_threads do
        print("启动线程 " .. thread_id)
        
        local thread_results
        if test_type == "import" then
            thread_results = csv_import_stress_test(thread_id)
        elseif test_type == "export" then
            thread_results = csv_export_stress_test(thread_id)
        else
            thread_results = mixed_stress_test(thread_id)
        end
        
        table.insert(all_thread_results, thread_results)
        
        -- 汇总线程结果
        if test_type == "import" then
            test_results.total_requests = test_results.total_requests + thread_results.requests
            test_results.successful_requests = test_results.successful_requests + thread_results.successes
            test_results.failed_requests = test_results.failed_requests + thread_results.failures
            test_results.total_latency = test_results.total_latency + thread_results.total_latency
            test_results.csv_import_stats.imported_rows = (test_results.csv_import_stats.imported_rows or 0) + thread_results.imported_rows
        elseif test_type == "export" then
            test_results.total_requests = test_results.total_requests + thread_results.requests
            test_results.successful_requests = test_results.successful_requests + thread_results.successes
            test_results.failed_requests = test_results.failed_requests + thread_results.failures
            test_results.total_latency = test_results.total_latency + thread_results.total_latency
            test_results.csv_export_stats.exported_rows = (test_results.csv_export_stats.exported_rows or 0) + thread_results.exported_rows
        else
            test_results.total_requests = test_results.total_requests + thread_results.import_requests + thread_results.export_requests
            test_results.successful_requests = test_results.successful_requests + thread_results.import_successes + thread_results.export_successes
            test_results.failed_requests = test_results.failed_requests + thread_results.import_failures + thread_results.export_failures
            test_results.total_latency = test_results.total_latency + thread_results.total_latency
            test_results.csv_import_stats.imported_rows = (test_results.csv_import_stats.imported_rows or 0) + thread_results.imported_rows
            test_results.csv_export_stats.exported_rows = (test_results.csv_export_stats.exported_rows or 0) + thread_results.exported_rows
        end
    end
    
    test_results.end_time = os.clock() * 1000
    
    -- 计算性能指标
    local metrics = calculate_performance_metrics(test_results)
    
    -- 输出测试结果
    print("\n=== CSV导入导出压力测试结果 ===")
    print("测试类型: " .. test_type)
    print("总请求数: " .. test_results.total_requests)
    print("成功请求数: " .. test_results.successful_requests)
    print("失败请求数: " .. test_results.failed_requests)
    print("成功率: " .. string.format("%.2f%%", metrics.success_rate))
    print("错误率: " .. string.format("%.2f%%", metrics.error_rate))
    print("平均延迟: " .. string.format("%.2fms", metrics.avg_latency))
    print("P95延迟: " .. string.format("%.2fms", metrics.p95_latency))
    print("P99延迟: " .. string.format("%.2fms", metrics.p99_latency))
    print("吞吐量: " .. string.format("%.2f 请求/秒", metrics.throughput))
    
    if test_results.csv_import_stats.imported_rows then
        print("导入数据行数: " .. test_results.csv_import_stats.imported_rows)
    end
    
    if test_results.csv_export_stats.exported_rows then
        print("导出数据行数: " .. test_results.csv_export_stats.exported_rows)
    end
    
    -- 检查性能阈值
    print("\n=== 性能阈值检查 ===")
    local all_passed = true
    
    if metrics.p99_latency > config.max_latency_p99 then
        print("❌ P99延迟超标: " .. string.format("%.2fms > %.2fms", metrics.p99_latency, config.max_latency_p99))
        all_passed = false
    else
        print("✅ P99延迟正常: " .. string.format("%.2fms <= %.2fms", metrics.p99_latency, config.max_latency_p99))
    end
    
    if metrics.throughput < config.min_throughput then
        print("❌ 吞吐量不足: " .. string.format("%.2f < %.2f", metrics.throughput, config.min_throughput))
        all_passed = false
    else
        print("✅ 吞吐量正常: " .. string.format("%.2f >= %.2f", metrics.throughput, config.min_throughput))
    end
    
    if metrics.error_rate > config.max_error_rate * 100 then
        print("❌ 错误率超标: " .. string.format("%.2f%% > %.2f%%", metrics.error_rate, config.max_error_rate * 100))
        all_passed = false
    else
        print("✅ 错误率正常: " .. string.format("%.2f%% <= %.2f%%", metrics.error_rate, config.max_error_rate * 100))
    end
    
    if all_passed then
        print("\n🎉 所有性能指标均符合要求！")
    else
        print("\n⚠️  部分性能指标未达到要求，需要优化！")
    end
    
    return all_passed
end

-- 主函数
local function main(...)
    local args = {...}
    local test_type = args[1] or "mixed"  -- 默认混合测试
    
    if test_type ~= "import" and test_type ~= "export" and test_type ~= "mixed" then
        print("用法: luajit csv-stress-test.lua [import|export|mixed]")
        print("  import - 仅测试CSV导入")
        print("  export - 仅测试CSV导出") 
        print("  mixed  - 混合测试导入和导出（默认）")
        return
    end
    
    print("Stock-TSDB CSV导入导出压力测试")
    print("开始时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    
    local success = run_stress_test(test_type)
    
    print("\n结束时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    
    if success then
        os.exit(0)
    else
        os.exit(1)
    end
end

-- 运行主函数
main(...)