-- micro_ts插件多版本对比测试
-- 比较原版、第一版优化和第二版优化的性能差异

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
    
    return {
        name = name,
        encode_ops_per_sec = performance_result.encode_ops_per_sec,
        decode_ops_per_sec = performance_result.decode_ops_per_sec,
        avg_encode_time = performance_result.avg_encode_time_per_op,
        avg_decode_time = performance_result.avg_decode_time_per_op,
        total_ops_per_sec = performance_result.encode_ops_per_sec + performance_result.decode_ops_per_sec
    }
end

-- 主测试函数
local function run_comparison_test()
    print("🔬 micro_ts插件多版本对比测试")
    print("=" .. string.rep("=", 78))
    
    -- 加载原版插件
    local MicroTsPlugin = require("lua.micro_ts_plugin")
    local original_plugin = MicroTsPlugin:new()
    
    -- 加载第一版优化插件
    local MicroTsPluginOptimized = require("lua.micro_ts_plugin_optimized")
    local optimized_plugin = MicroTsPluginOptimized:new()
    
    -- 加载第二版优化插件
    local MicroTsPluginOptimizedV2 = require("lua.micro_ts_plugin_optimized_v2")
    local optimized_v2_plugin = MicroTsPluginOptimizedV2:new()
    
    -- 加载最终优化插件
    local MicroTsPluginFinal = require("lua.micro_ts_plugin_final")
    local final_plugin = MicroTsPluginFinal:new()
    
    -- 测试原版插件
    local original_results = test_plugin(original_plugin, "原版micro_ts")
    
    -- 测试第一版优化插件
    local optimized_results = test_plugin(optimized_plugin, "第一版优化micro_ts")
    
    -- 测试第二版优化插件
    local optimized_v2_results = test_plugin(optimized_v2_plugin, "第二版优化micro_ts")
    
    -- 测试最终优化插件
    local final_results = test_plugin(final_plugin, "最终优化micro_ts")
    
    -- 性能对比
    print("\n📊 性能对比:")
    print("=" .. string.rep("=", 78))
    print("指标                    原版              第一版优化        第二版优化        最终优化        最佳提升")
    print("-" .. string.rep("-", 110))
    
    local v1_encode_improvement = (optimized_results.encode_ops_per_sec / original_results.encode_ops_per_sec - 1) * 100
    local v1_decode_improvement = (optimized_results.decode_ops_per_sec / original_results.decode_ops_per_sec - 1) * 100
    local v2_encode_improvement = (optimized_v2_results.encode_ops_per_sec / original_results.encode_ops_per_sec - 1) * 100
    local v2_decode_improvement = (optimized_v2_results.decode_ops_per_sec / original_results.decode_ops_per_sec - 1) * 100
    local final_encode_improvement = (final_results.encode_ops_per_sec / original_results.encode_ops_per_sec - 1) * 100
    local final_decode_improvement = (final_results.decode_ops_per_sec / original_results.decode_ops_per_sec - 1) * 100
    
    local best_encode_improvement = math.max(v1_encode_improvement, v2_encode_improvement, final_encode_improvement)
    local best_decode_improvement = math.max(v1_decode_improvement, v2_decode_improvement, final_decode_improvement)
    
    print(string.format("编码吞吐量 (ops/sec)    %-16.0f  %-16.0f  %-16.0f  %-16.0f  %+6.2f%%", 
        original_results.encode_ops_per_sec, 
        optimized_results.encode_ops_per_sec,
        optimized_v2_results.encode_ops_per_sec,
        final_results.encode_ops_per_sec,
        best_encode_improvement))
    
    print(string.format("解码吞吐量 (ops/sec)    %-16.0f  %-16.0f  %-16.0f  %-16.0f  %+6.2f%%", 
        original_results.decode_ops_per_sec, 
        optimized_results.decode_ops_per_sec,
        optimized_v2_results.decode_ops_per_sec,
        final_results.decode_ops_per_sec,
        best_decode_improvement))
    
    print(string.format("总吞吐量 (ops/sec)      %-16.0f  %-16.0f  %-16.0f  %-16.0f  N/A", 
        original_results.total_ops_per_sec, 
        optimized_results.total_ops_per_sec,
        optimized_v2_results.total_ops_per_sec,
        final_results.total_ops_per_sec))
    
    -- 优化总结
    print("\n✅ 优化总结:")
    print("=" .. string.rep("=", 78))
    
    local best_encode_version = "原版"
    local best_decode_version = "原版"
    
    if final_encode_improvement > v2_encode_improvement and final_encode_improvement > v1_encode_improvement then
        best_encode_version = "最终优化"
    elseif v2_encode_improvement > v1_encode_improvement then
        best_encode_version = "第二版优化"
    elseif v1_encode_improvement > 0 then
        best_encode_version = "第一版优化"
    end
    
    if final_decode_improvement > v2_decode_improvement and final_decode_improvement > v1_decode_improvement then
        best_decode_version = "最终优化"
    elseif v2_decode_improvement > v1_decode_improvement then
        best_decode_version = "第二版优化"
    elseif v1_decode_improvement > 0 then
        best_decode_version = "第一版优化"
    end
    
    print("🏆 最佳编码性能版本: " .. best_encode_version)
    print("🏆 最佳解码性能版本: " .. best_decode_version)
    
    -- 各版本特点
    print("\n🔧 各版本特点:")
    print("原版micro_ts:")
    print("  ✓ 基础FFI实现")
    print("  ✓ 简单缓存策略")
    print("  ✓ 预分配缓冲区")
    
    print("\n第一版优化micro_ts:")
    print("  ✓ LRU缓存策略")
    print("  ✓ 缓冲池管理")
    print("  ✓ 性能监控")
    print("  ✓ 错误处理")
    print("  ✗ 引入额外开销")
    
    print("\n第二版优化micro_ts:")
    print("  ✓ 精简缓存策略")
    print("  ✓ 预分配解码缓冲区")
    print("  ✓ 减少函数调用开销")
    print("  ✓ 专注核心性能")
    
    print("\n最终优化micro_ts:")
    print("  ✓ 极简缓存策略 (500项)")
    print("  ✓ 预编译常用字符串操作")
    print("  ✓ 手动解析时间戳")
    print("  ✓ 减少FFI调用开销")
    print("  ✓ 优化内存分配")
    
    -- 推荐使用场景
    print("\n💡 推荐使用场景:")
    if final_encode_improvement > 0 and final_decode_improvement > 0 then
        print("🚀 最终优化: 适用于所有场景，性能最佳")
    elseif v2_encode_improvement > 0 and v2_decode_improvement > 0 then
        print("🚀 第二版优化: 适用于需要平衡性能和功能的场景")
    elseif v1_encode_improvement > 0 and v1_decode_improvement > 0 then
        print("🚀 第一版优化: 适用于需要详细监控和缓存的场景")
    else
        print("⚠️  原版: 适用于简单场景，性能稳定")
    end
    
    print("\n✅ micro_ts插件多版本对比测试完成")
    print("=" .. string.rep("=", 78))
end

-- 运行测试
run_comparison_test()