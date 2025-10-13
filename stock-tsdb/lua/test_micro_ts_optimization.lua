-- micro_ts插件优化版本对比测试
-- 比较原版和优化版的性能差异

local function test_plugin(plugin, name)
    print("\n🚀 测试 " .. name .. " 插件")
    print("=" .. string.rep("=", 78))
    
    -- 测试插件基本信息
    local info = plugin:get_info()
    print("📋 插件基本信息:")
    print("  名称:", info.name)
    print("  版本:", info.version)
    print("  描述:", info.description)
    print("  编码格式:", info.encoding_format)
    print("  特性:", table.concat(info.features, ", "))
    
    -- 测试数据
    local test_data = {
        stock_code = "000001",
        timestamp = os.time(),
        market = "SH",
        price = 1000,
        volume = 10000,
        ch = 1,
        side = 0,
        order_no = 1234567890,
        tick_no = 9876543210
    }
    
    -- 功能测试
    print("\n🔍 功能测试:")
    local rowkey, qualifier = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
    local value = plugin:encode_value(test_data)
    
    print("  编码结果:")
    print("    RowKey长度:", #rowkey, "字节")
    print("    Qualifier长度:", #qualifier, "字节")
    print("    Value长度:", #value, "字节")
    
    local decoded_key = plugin:decode_rowkey(rowkey)
    local decoded_value = plugin:decode_value(value)
    
    print("  解码结果:")
    print("    市场:", decoded_key.market)
    print("    股票代码:", decoded_key.stock_code)
    print("    价格:", decoded_value.price)
    print("    成交量:", decoded_value.volume)
    
    -- 验证解码正确性
    local key_correct = (decoded_key.market == test_data.market) and 
                       (decoded_key.stock_code == test_data.stock_code)
    
    local value_correct = (decoded_value.price == test_data.price) and
                         (decoded_value.volume == test_data.volume)
    
    print("  验证结果:")
    print("    Key解码正确:", key_correct and "✓" or "✗")
    print("    Value解码正确:", value_correct and "✓" or "✗")
    
    -- 性能测试
    print("\n⚡ 性能测试:")
    local performance_result = plugin:performance_test(50000)
    
    print("  测试迭代次数:", performance_result.iterations)
    print("  编码吞吐量:", string.format("%.0f", performance_result.encode_ops_per_sec), "ops/sec")
    print("  解码吞吐量:", string.format("%.0f", performance_result.decode_ops_per_sec), "ops/sec")
    print("  平均编码时间:", string.format("%.6f", performance_result.avg_encode_time_per_op), "ms/op")
    print("  平均解码时间:", string.format("%.6f", performance_result.avg_decode_time_per_op), "ms/op")
    
    if performance_result.cache_hit_rate then
        print("  缓存命中率:", string.format("%.2f", performance_result.cache_hit_rate), "%")
        print("  缓存命中次数:", performance_result.cache_hits)
        print("  缓存未命中次数:", performance_result.cache_misses)
    end
    
    if performance_result.error_count then
        print("  错误次数:", performance_result.error_count)
    end
    
    return {
        name = name,
        encode_ops_per_sec = performance_result.encode_ops_per_sec,
        decode_ops_per_sec = performance_result.decode_ops_per_sec,
        avg_encode_time = performance_result.avg_encode_time_per_op,
        avg_decode_time = performance_result.avg_decode_time_per_op,
        cache_hit_rate = performance_result.cache_hit_rate or 0,
        errors = performance_result.error_count or 0
    }
end

-- 主测试函数
local function run_comparison_test()
    print("🔬 micro_ts插件优化版本对比测试")
    print("=" .. string.rep("=", 78))
    
    -- 加载原版插件
    local MicroTsPlugin = require("lua.micro_ts_plugin")
    local original_plugin = MicroTsPlugin:new()
    
    -- 加载优化版插件
    local MicroTsPluginOptimized = require("lua.micro_ts_plugin_optimized")
    local optimized_plugin = MicroTsPluginOptimized:new()
    
    -- 测试原版插件
    local original_results = test_plugin(original_plugin, "原版micro_ts")
    
    -- 测试优化版插件
    local optimized_results = test_plugin(optimized_plugin, "优化版micro_ts")
    
    -- 性能对比
    print("\n📊 性能对比:")
    print("=" .. string.rep("=", 78))
    print("指标                    原版              优化版            提升")
    print("-" .. string.rep("-", 70))
    
    local encode_improvement = (optimized_results.encode_ops_per_sec / original_results.encode_ops_per_sec - 1) * 100
    local decode_improvement = (optimized_results.decode_ops_per_sec / original_results.decode_ops_per_sec - 1) * 100
    local encode_time_improvement = (1 - optimized_results.avg_encode_time / original_results.avg_encode_time) * 100
    local decode_time_improvement = (1 - optimized_results.avg_decode_time / original_results.avg_decode_time) * 100
    
    print(string.format("编码吞吐量 (ops/sec)    %-16.0f  %-16.0f  %+6.2f%%", 
        original_results.encode_ops_per_sec, 
        optimized_results.encode_ops_per_sec, 
        encode_improvement))
    
    print(string.format("解码吞吐量 (ops/sec)    %-16.0f  %-16.0f  %+6.2f%%", 
        original_results.decode_ops_per_sec, 
        optimized_results.decode_ops_per_sec, 
        decode_improvement))
    
    print(string.format("平均编码时间 (ms/op)    %-16.6f  %-16.6f  %+6.2f%%", 
        original_results.avg_encode_time, 
        optimized_results.avg_encode_time, 
        encode_time_improvement))
    
    print(string.format("平均解码时间 (ms/op)    %-16.6f  %-16.6f  %+6.2f%%", 
        original_results.avg_decode_time, 
        optimized_results.avg_decode_time, 
        decode_time_improvement))
    
    print(string.format("缓存命中率 (%%)         %-16.2f  %-16.2f  N/A", 
        original_results.cache_hit_rate, 
        optimized_results.cache_hit_rate))
    
    print(string.format("错误次数                %-16d  %-16d  N/A", 
        original_results.errors, 
        optimized_results.errors))
    
    -- 优化总结
    print("\n✅ 优化总结:")
    print("=" .. string.rep("=", 78))
    
    if encode_improvement > 0 then
        print("🚀 编码性能提升: " .. string.format("%.2f%%", encode_improvement))
    else
        print("⚠️  编码性能下降: " .. string.format("%.2f%%", math.abs(encode_improvement)))
    end
    
    if decode_improvement > 0 then
        print("🚀 解码性能提升: " .. string.format("%.2f%%", decode_improvement))
    else
        print("⚠️  解码性能下降: " .. string.format("%.2f%%", math.abs(decode_improvement)))
    end
    
    if optimized_results.cache_hit_rate > original_results.cache_hit_rate then
        print("🎯 缓存命中率提升: " .. string.format("%.2f%%", optimized_results.cache_hit_rate - original_results.cache_hit_rate))
    end
    
    -- 优化版特有功能
    print("\n🔧 优化版特有功能:")
    local optimized_info = optimized_plugin:get_info()
    for _, feature in ipairs(optimized_info.features) do
        if string.find(feature, "cache") or string.find(feature, "pool") or 
           string.find(feature, "monitor") or string.find(feature, "error") then
            print("  ✓ " .. feature)
        end
    end
    
    -- 详细性能统计
    print("\n📈 优化版详细性能统计:")
    local stats = optimized_plugin:get_performance_stats()
    print("  总编码次数:", stats.encode_count)
    print("  总解码次数:", stats.decode_count)
    print("  总缓存命中:", stats.cache_hits)
    print("  总缓存未命中:", stats.cache_misses)
    print("  总运行时间:", string.format("%.3f", stats.runtime), "秒")
    
    -- 缓存和缓冲池状态
    print("\n💾 缓存和缓冲池状态:")
    print("  RowKey缓存使用:", optimized_info.cache_stats.current_usage, "/", optimized_info.cache_stats.size)
    print("  缓冲区使用情况:")
    print("    Key缓冲区:", optimized_info.buffer_pool_stats.key_buffers, "/", optimized_plugin.buffer_pool.pool_size)
    print("    Qual缓冲区:", optimized_info.buffer_pool_stats.qual_buffers, "/", optimized_plugin.buffer_pool.pool_size)
    print("    Value缓冲区:", optimized_info.buffer_pool_stats.value_buffers, "/", optimized_plugin.buffer_pool.pool_size)
    
    print("\n✅ micro_ts插件优化版本对比测试完成")
    print("=" .. string.rep("=", 78))
end

-- 运行测试
run_comparison_test()