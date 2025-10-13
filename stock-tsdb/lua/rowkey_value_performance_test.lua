-- RowKey与Value编码插件性能对比测试
-- 对比股票行情和IOT业务编码方案的性能差异

local plugin_manager = require "lua.rowkey_value_plugin"
local PluginAdapter = require "lua.tsdb_plugin_adapter"

local PerformanceTest = {}
PerformanceTest.__index = PerformanceTest

function PerformanceTest:new()
    local obj = setmetatable({}, PerformanceTest)
    obj.test_results = {}
    obj.test_data = {}
    return obj
end

-- 生成测试数据
function PerformanceTest:generate_test_data()
    local stock_data = {}
    local iot_data = {}
    
    -- 生成股票行情测试数据
    for i = 1, 10000 do
        local timestamp = 1640995200 + i  -- 2022-01-01开始
        local stock_code = string.format("%06d", 600000 + (i % 1000))
        
        table.insert(stock_data, {
            key = {
                stock_code = stock_code,
                timestamp = timestamp,
                market = i % 2 == 0 and "SH" or "SZ"
            },
            value = {
                open = 10.0 + math.random() * 90,
                high = 10.0 + math.random() * 90,
                low = 10.0 + math.random() * 90,
                close = 10.0 + math.random() * 90,
                volume = math.random() * 1000000,
                amount = math.random() * 10000000
            }
        })
    end
    
    -- 生成IOT测试数据
    for i = 1, 10000 do
        local timestamp = 1640995200 + i
        local device_id = string.format("device_%04d", i % 1000)
        local metric_types = {"temperature", "humidity", "pressure", "light", "sound", "motion"}
        local locations = {"room1", "room2", "outdoor", "lab", "office"}
        
        table.insert(iot_data, {
            key = {
                device_id = device_id,
                timestamp = timestamp,
                metric_type = metric_types[(i % #metric_types) + 1],
                location = locations[(i % #locations) + 1]
            },
            value = {
                value = math.random() * 100,
                quality = i % 100 == 0 and 0 or 1,  -- 1%的数据质量有问题
                unit = metric_types[(i % #metric_types) + 1] == "temperature" and "C" or "unit"
            }
        })
    end
    
    self.test_data = {
        stock = stock_data,
        iot = iot_data
    }
    
    return self.test_data
end

-- 运行单个插件的性能测试
function PerformanceTest:test_single_plugin(plugin_name, data_type)
    local plugin = plugin_manager.default_manager:get_plugin(plugin_name)
    if not plugin then
        return {error = "插件不存在: " .. plugin_name}
    end
    
    local test_data = self.test_data[data_type]
    if not test_data then
        return {error = "测试数据类型不存在: " .. data_type}
    end
    
    print(string.format("开始测试插件: %s, 数据类型: %s, 数据量: %d", 
        plugin_name, data_type, #test_data))
    
    local results = {
        plugin_name = plugin_name,
        data_type = data_type,
        test_timestamp = os.time(),
        test_data_count = #test_data,
        encode_results = {},
        decode_results = {},
        memory_analysis = {},
        compression_analysis = {},
        error = nil  -- 添加错误字段
    }
    
    -- 编码性能测试
    print("  执行编码性能测试...")
    local encode_start = os.clock()
    local encoded_data = {}
    local total_key_size = 0
    local total_value_size = 0
    
    for i, data in ipairs(test_data) do
        local key, value = data.key, data.value
        
        -- 根据数据类型调用不同的编码方法
        local encoded_key, qualifier
        local encoded_value
        
        if data_type == "stock" then
            encoded_key, qualifier = plugin:encode_rowkey(key.stock_code, key.timestamp, key.market)
            encoded_value = plugin:encode_value(value)
        elseif data_type == "iot" then
            encoded_key, qualifier = plugin:encode_rowkey(key.device_id, key.timestamp, key.metric_type, key.location)
            encoded_value = plugin:encode_value(value)
        end
        
        table.insert(encoded_data, {
            key = encoded_key,
            value = encoded_value,
            qualifier = qualifier,
            original_data = data
        })
        
        total_key_size = total_key_size + #encoded_key
        total_value_size = total_value_size + #encoded_value
    end
    
    local encode_total_time = os.clock() - encode_start
    results.encode_results = {
        total_time = encode_total_time,
        avg_time_per_record = encode_total_time / #test_data,
        records_per_second = #test_data / encode_total_time,
        total_key_size = total_key_size,
        total_value_size = total_value_size,
        avg_key_size = total_key_size / #test_data,
        avg_value_size = total_value_size / #test_data,
        total_encoded_size = total_key_size + total_value_size
    }
    
    -- 解码性能测试
    print("  执行解码性能测试...")
    local decode_start = os.clock()
    local decode_count = 0
    local decode_errors = 0
    
    for _, item in ipairs(encoded_data) do
        local decoded_key = plugin:decode_rowkey(item.key)
        local decoded_value = plugin:decode_value(item.value)
        
        if decoded_key and decoded_value then
            decode_count = decode_count + 1
        else
            decode_errors = decode_errors + 1
        end
    end
    
    local decode_total_time = os.clock() - decode_start
    results.decode_results = {
        total_time = decode_total_time,
        avg_time_per_record = decode_total_time / decode_count,
        records_per_second = decode_count / decode_total_time,
        success_count = decode_count,
        error_count = decode_errors
    }
    
    -- 内存使用分析
    results.memory_analysis = {
        bytes_per_record = results.encode_results.total_encoded_size / #test_data,
        key_compression_ratio = results.encode_results.avg_key_size / 50,  -- 假设原始key平均50字节
        value_compression_ratio = results.encode_results.avg_value_size / 100,  -- 假设原始value平均100字节
        total_efficiency = #test_data / (results.encode_results.total_encoded_size / 1024)  -- 记录数/KB
    }
    
    -- 压缩分析（模拟）
    results.compression_analysis = {
        theoretical_compression_ratio = plugin_name == "iot_data" and 0.3 or 0.8,  -- IOT数据压缩率更高
        key_encoding_efficiency = results.encode_results.avg_key_size < 30 and "high" or "low",
        value_encoding_efficiency = results.encode_results.avg_value_size < 50 and "high" or "low"
    }
    
    print(string.format("  编码性能: %.0f 记录/秒, 平均 %.4f 秒/记录", 
        results.encode_results.records_per_second, 
        results.encode_results.avg_time_per_record))
    
    print(string.format("  解码性能: %.0f 记录/秒, 平均 %.4f 秒/记录", 
        results.decode_results.records_per_second,
        results.decode_results.avg_time_per_record))
    
    print(string.format("  存储效率: %.2f 字节/记录, %.2f 记录/KB",
        results.memory_analysis.bytes_per_record,
        results.memory_analysis.total_efficiency))
    
    return results
end

-- 对比两个插件的性能
function PerformanceTest:compare_plugins(plugin1_name, plugin2_name, data_type)
    print(string.format("\n=== 对比测试: %s vs %s ===", plugin1_name, plugin2_name))
    
    local results1 = self:test_single_plugin(plugin1_name, data_type)
    local results2 = self:test_single_plugin(plugin2_name, data_type)
    
    -- 检查测试结果是否有效
    if results1.error or not results1.encode_results then
        print(string.format("  警告: %s 测试失败: %s", plugin1_name, results1.error or "未知错误"))
        return {error = string.format("%s 测试失败", plugin1_name)}
    end
    
    if results2.error or not results2.encode_results then
        print(string.format("  警告: %s 测试失败: %s", plugin2_name, results2.error or "未知错误"))
        return {error = string.format("%s 测试失败", plugin2_name)}
    end
    
    local comparison = {
        plugin1 = plugin1_name,
        plugin2 = plugin2_name,
        data_type = data_type,
        test_timestamp = os.time(),
        encode_comparison = {},
        decode_comparison = {},
        memory_comparison = {},
        recommendations = {}
    }
    
    -- 编码性能对比
    comparison.encode_comparison = {
        speed_ratio = results1.encode_results.records_per_second / results2.encode_results.records_per_second,
        size_ratio = results1.encode_results.total_encoded_size / results2.encode_results.total_encoded_size,
        winner = results1.encode_results.records_per_second > results2.encode_results.records_per_second and plugin1_name or plugin2_name,
        size_winner = results1.encode_results.total_encoded_size < results2.encode_results.total_encoded_size and plugin1_name or plugin2_name
    }
    
    -- 解码性能对比
    comparison.decode_comparison = {
        speed_ratio = results1.decode_results.records_per_second / results2.decode_results.records_per_second,
        winner = results1.decode_results.records_per_second > results2.decode_results.records_per_second and plugin1_name or plugin2_name
    }
    
    -- 内存对比
    comparison.memory_comparison = {
        efficiency_ratio = results1.memory_analysis.total_efficiency / results2.memory_analysis.total_efficiency,
        winner = results1.memory_analysis.total_efficiency > results2.memory_analysis.total_efficiency and plugin1_name or plugin2_name
    }
    
    -- 生成建议
    local encode_winner = comparison.encode_comparison.winner
    local size_winner = comparison.encode_comparison.size_winner
    local decode_winner = comparison.decode_comparison.winner
    local efficiency_winner = comparison.memory_comparison.winner
    
    if encode_winner == size_winner then
        table.insert(comparison.recommendations, 
            string.format("%s 在编码性能和存储大小方面都表现更好", encode_winner))
    else
        table.insert(comparison.recommendations,
            string.format("%s 编码性能更好，但 %s 存储效率更高", encode_winner, size_winner))
    end
    
    table.insert(comparison.recommendations,
        string.format("%s 解码性能更好", decode_winner))
    
    table.insert(comparison.recommendations,
        string.format("%s 整体存储效率更高", efficiency_winner))
    
    -- 场景化建议
    if data_type == "stock" then
        table.insert(comparison.recommendations, "股票行情数据建议使用JSON格式，便于调试和兼容性")
    elseif data_type == "iot" then
        table.insert(comparison.recommendations, "IOT数据建议使用二进制格式，存储效率更高")
    end
    
    self.test_results[string.format("%s_vs_%s_%s", plugin1_name, plugin2_name, data_type)] = {
        plugin1_results = results1,
        plugin2_results = results2,
        comparison = comparison
    }
    
    return comparison
end

-- 运行完整的性能对比测试
function PerformanceTest:run_full_comparison()
    print("=== RowKey与Value编码插件性能对比测试 ===")
    print("生成测试数据...")
    self:generate_test_data()
    
    -- 股票行情数据对比
    print("\n--- 股票行情数据性能对比 ---")
    local stock_comparison = self:compare_plugins("stock_quote", "iot_data", "stock")
    
    -- IOT数据对比
    print("\n--- IOT数据性能对比 ---")
    local iot_comparison = self:compare_plugins("stock_quote", "iot_data", "iot")
    
    -- 生成最终报告
    local final_report = {
        test_timestamp = os.time(),
        test_summary = {
            total_test_records = #self.test_data.stock + #self.test_data.iot,
            plugins_tested = {"stock_quote", "iot_data"},
            data_types = {"stock", "iot"}
        },
        stock_comparison = stock_comparison,
        iot_comparison = iot_comparison,
        overall_recommendations = {}
    }
    
    -- 生成总体建议
    final_report.overall_recommendations = {
        "股票行情业务：保持现有的JSON编码方案，便于调试和系统兼容性",
        "IOT业务：采用二进制编码方案，显著提高存储效率和传输性能",
        "混合部署：可以同时使用两种插件，根据业务类型自动选择",
        "性能优化：对于高频写入场景，建议使用二进制格式减少序列化开销"
    }
    
    return final_report
end

-- 生成性能对比报告
function PerformanceTest:generate_performance_report()
    local report = self:run_full_comparison()
    
    print("\n=== 性能对比报告 ===")
    print(string.format("测试时间: %s", os.date("%Y-%m-%d %H:%M:%S", report.test_timestamp)))
    print(string.format("总测试记录数: %d", report.test_summary.total_test_records))
    
    print("\n--- 股票行情数据对比 ---")
    local stock_comp = report.stock_comparison
    print(string.format("编码性能: %s 胜出 (%.2fx)", stock_comp.encode_comparison.winner, stock_comp.encode_comparison.speed_ratio))
    print(string.format("存储大小: %s 胜出 (%.2fx)", stock_comp.encode_comparison.size_winner, stock_comp.encode_comparison.size_ratio))
    print(string.format("解码性能: %s 胜出 (%.2fx)", stock_comp.decode_comparison.winner, stock_comp.decode_comparison.speed_ratio))
    
    print("\n--- IOT数据对比 ---")
    local iot_comp = report.iot_comparison
    print(string.format("编码性能: %s 胜出 (%.2fx)", iot_comp.encode_comparison.winner, iot_comp.encode_comparison.speed_ratio))
    print(string.format("存储大小: %s 胜出 (%.2fx)", iot_comp.encode_comparison.size_winner, iot_comp.encode_comparison.size_ratio))
    print(string.format("解码性能: %s 胜出 (%.2fx)", iot_comp.decode_comparison.winner, iot_comp.decode_comparison.speed_ratio))
    
    print("\n--- 总体建议 ---")
    for _, recommendation in ipairs(report.overall_recommendations) do
        print("• " .. recommendation)
    end
    
    return report
end

return PerformanceTest