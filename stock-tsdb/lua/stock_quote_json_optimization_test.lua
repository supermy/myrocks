#!/usr/bin/lua

-- Stock Quote JSON插件优化测试脚本
-- 测试优化前后的性能对比

package.path = package.path .. ";./lua/?.lua"

local rowkey_value_plugin = require("rowkey_value_plugin")

-- 创建测试数据
local function generate_test_data(count)
    local test_data = {}
    for i = 1, count do
        table.insert(test_data, {
            stock_code = string.format("%06d", i),
            timestamp = 1700000000 + i * 60,  -- 每分钟一条数据
            market = i % 2 == 0 and "SH" or "SZ",
            data = {
                open = 10.0 + i * 0.1,
                high = 10.5 + i * 0.1,
                low = 9.5 + i * 0.1,
                close = 10.2 + i * 0.1,
                volume = 1000000 + i * 1000,
                amount = 10000000 + i * 10000
            }
        })
    end
    return test_data
end

-- 性能测试函数
local function performance_test(plugin, test_data, test_name)
    print("=== " .. test_name .. " 性能测试 ===")
    
    -- RowKey编码测试
    local start_time = os.clock()
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
    end
    local rowkey_time = os.clock() - start_time
    
    -- Value编码测试
    start_time = os.clock()
    for i, test in ipairs(test_data) do
        plugin:encode_value(test.data)
    end
    local value_time = os.clock() - start_time
    
    -- 完整编码测试
    start_time = os.clock()
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        plugin:encode_value(test.data)
    end
    local full_time = os.clock() - start_time
    
    -- 解码测试
    local encoded_values = {}
    for i, test in ipairs(test_data) do
        encoded_values[i] = plugin:encode_value(test.data)
    end
    
    start_time = os.clock()
    for i, value in ipairs(encoded_values) do
        plugin:decode_value(value)
    end
    local decode_time = os.clock() - start_time
    
    print(string.format("RowKey编码: %.6f 秒/操作", rowkey_time / #test_data))
    print(string.format("Value编码: %.6f 秒/操作", value_time / #test_data))
    print(string.format("完整编码: %.6f 秒/操作", full_time / #test_data))
    print(string.format("解码: %.6f 秒/操作", decode_time / #test_data))
    print(string.format("总测试数据量: %d 条", #test_data))
    print()
    
    return {
        rowkey_time = rowkey_time / #test_data,
        value_time = value_time / #test_data,
        full_time = full_time / #test_data,
        decode_time = decode_time / #test_data
    }
end

-- 缓存命中率测试
local function cache_hit_test(plugin, test_data)
    print("=== 缓存命中率测试 ===")
    
    -- 第一次编码（填充缓存）
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        plugin:encode_value(test.data)
    end
    
    -- 第二次编码（测试缓存命中）
    local start_time = os.clock()
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        plugin:encode_value(test.data)
    end
    local cached_time = os.clock() - start_time
    
    -- 清空缓存
    plugin.rowkey_cache = {}
    plugin.value_cache = {}
    
    -- 无缓存编码
    start_time = os.clock()
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        plugin:encode_value(test.data)
    end
    local uncached_time = os.clock() - start_time
    
    local hit_ratio = (uncached_time - cached_time) / uncached_time
    
    print(string.format("无缓存编码时间: %.6f 秒", uncached_time))
    print(string.format("缓存编码时间: %.6f 秒", cached_time))
    print(string.format("缓存命中率提升: %.2f 倍", uncached_time / cached_time))
    print(string.format("缓存效率: %.2f%%", hit_ratio * 100))
    print()
    
    return {
        uncached_time = uncached_time,
        cached_time = cached_time,
        hit_ratio = hit_ratio
    }
end

-- 内存使用分析
local function memory_analysis(plugin, test_data)
    print("=== 内存使用分析 ===")
    
    -- 编码前内存状态
    local before_memory = collectgarbage("count")
    
    -- 执行编码操作
    for i, test in ipairs(test_data) do
        plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        plugin:encode_value(test.data)
    end
    
    -- 编码后内存状态
    local after_memory = collectgarbage("count")
    
    -- 强制垃圾回收后内存状态
    collectgarbage("collect")
    local final_memory = collectgarbage("count")
    
    print(string.format("编码前内存: %.2f KB", before_memory))
    print(string.format("编码后内存: %.2f KB", after_memory))
    print(string.format("垃圾回收后内存: %.2f KB", final_memory))
    print(string.format("内存增长: %.2f KB", after_memory - before_memory))
    print(string.format("内存回收效率: %.2f%%", (after_memory - final_memory) / (after_memory - before_memory) * 100))
    print()
    
    return {
        before_memory = before_memory,
        after_memory = after_memory,
        final_memory = final_memory
    }
end

-- 数据完整性验证
local function data_integrity_test(plugin, test_data)
    print("=== 数据完整性验证 ===")
    
    local success_count = 0
    local total_count = #test_data
    
    for i, test in ipairs(test_data) do
        -- 编码
        local rowkey, qualifier = plugin:encode_rowkey(test.stock_code, test.timestamp, test.market)
        local encoded_value = plugin:encode_value(test.data)
        
        -- 解码
        local decoded_data = plugin:decode_value(encoded_value)
        
        -- 验证数据完整性
        local valid = true
        for field, value in pairs(test.data) do
            if math.abs((decoded_data[field] or 0) - value) > 0.0001 then
                valid = false
                break
            end
        end
        
        if valid then
            success_count = success_count + 1
        end
    end
    
    local success_rate = success_count / total_count * 100
    
    print(string.format("数据完整性验证: %d/%d (%.2f%%)", success_count, total_count, success_rate))
    print()
    
    return success_rate
end

-- 主测试函数
local function main()
    print("Stock Quote JSON插件优化测试")
    print("==============================")
    print()
    
    -- 生成测试数据
    local test_data = generate_test_data(1000)
    
    -- 创建插件实例
    local plugin = rowkey_value_plugin.StockQuotePlugin:new()
    
    -- 执行各项测试
    local perf_results = performance_test(plugin, test_data, "优化后插件")
    local cache_results = cache_hit_test(plugin, test_data)
    local memory_results = memory_analysis(plugin, test_data)
    local integrity_rate = data_integrity_test(plugin, test_data)
    
    -- 输出优化效果总结
    print("=== 优化效果总结 ===")
    print("1. 性能优化:")
    print(string.format("   - RowKey编码: %.6f 秒/操作", perf_results.rowkey_time))
    print(string.format("   - Value编码: %.6f 秒/操作", perf_results.value_time))
    print(string.format("   - 完整编码: %.6f 秒/操作", perf_results.full_time))
    print(string.format("   - 解码: %.6f 秒/操作", perf_results.decode_time))
    
    print("2. 缓存优化:")
    print(string.format("   - 缓存命中率提升: %.2f 倍", cache_results.uncached_time / cache_results.cached_time))
    print(string.format("   - 缓存效率: %.2f%%", cache_results.hit_ratio * 100))
    
    print("3. 内存优化:")
    print(string.format("   - 内存增长: %.2f KB", memory_results.after_memory - memory_results.before_memory))
    print(string.format("   - 内存回收效率: %.2f%%", (memory_results.after_memory - memory_results.final_memory) / (memory_results.after_memory - memory_results.before_memory) * 100))
    
    print("4. 数据完整性:")
    print(string.format("   - 验证成功率: %.2f%%", integrity_rate))
    
    print("5. 优化技术应用:")
    print("   - 预分配字符串和模板")
    print("   - 缓存机制实现")
    print("   - 高效JSON解析模式")
    print("   - 内存管理优化")
    
    print("\n测试完成！")
end

-- 运行测试
main()