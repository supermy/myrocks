#!/usr/bin/lua

-- 性能优化测试脚本
-- 测试二进制编码插件的优化效果

-- 设置模块搜索路径
package.path = package.path .. ";./?.lua;./lua/?.lua;../?.lua;../lua/?.lua"

-- 加载插件管理器
local rowkey_value_plugin = require("rowkey_value_plugin")
local micro_ts_plugin_optimized_v2 = require("micro_ts_plugin_optimized_v2")

print("🚀 二进制编码插件性能优化测试")
print("==================================================")

-- 获取插件管理器
local plugin_manager = rowkey_value_plugin.default_manager

-- 注册新插件
local micro_ts_opt_instance = micro_ts_plugin_optimized_v2:new()
plugin_manager:register_plugin(micro_ts_opt_instance)

-- 获取二进制编码插件
local binary_plugin = plugin_manager:get_plugin("stock_quote_binary")
local micro_ts_opt_plugin = plugin_manager:get_plugin("micro_ts_optimized_v2")
if not binary_plugin then
    print("❌ 无法找到二进制编码插件")
    return
end

print("📋 测试配置:")
print("   测试次数: 100000")
print("   缓存大小: 1000")
print("   测试数据: 随机股票行情数据")
print()

-- 生成测试数据
local test_data = {}
local stock_codes = {"000001", "000002", "000003", "000004", "000005", "600000", "600001", "600002"}
local markets = {"SH", "SZ"}

for i = 1, 100000 do
    local stock_code = stock_codes[math.random(#stock_codes)]
    local market = markets[math.random(#markets)]
    local timestamp = 1760268000 + math.random(86400)  -- 一天内的时间戳
    
    test_data[i] = {
        stock_code = stock_code,
        market = market,
        timestamp = timestamp,
        data = {
            open = math.random(1000) / 100,
            high = math.random(1000) / 100,
            low = math.random(1000) / 100,
            close = math.random(1000) / 100,
            volume = math.random(1000000),
            amount = math.random(10000000) / 100
        }
    }
end

print("🔍 开始性能测试...")

-- 测试RowKey编码性能
local rowkey_start_time = os.clock()
for i = 1, #test_data do
    local item = test_data[i]
    binary_plugin:encode_rowkey(item.stock_code, item.timestamp, item.market)
end
local rowkey_end_time = os.clock()
local rowkey_total_time = rowkey_end_time - rowkey_start_time

-- 测试Value编码性能
local value_start_time = os.clock()
for i = 1, #test_data do
    local item = test_data[i]
    binary_plugin:encode_value(item.data)
end
local value_end_time = os.clock()
local value_total_time = value_end_time - value_start_time

-- 测试完整编码性能（RowKey + Value）
local full_start_time = os.clock()
for i = 1, #test_data do
    local item = test_data[i]
    binary_plugin:encode_rowkey(item.stock_code, item.timestamp, item.market)
    binary_plugin:encode_value(item.data)
end
local full_end_time = os.clock()
local full_total_time = full_end_time - full_start_time

-- 测试缓存命中率（重复编码相同数据）
local cache_test_start_time = os.clock()
for i = 1, 10000 do
    -- 重复编码前100个数据项
    local item = test_data[(i % 100) + 1]
    binary_plugin:encode_rowkey(item.stock_code, item.timestamp, item.market)
    binary_plugin:encode_value(item.data)
end
local cache_test_end_time = os.clock()
local cache_test_total_time = cache_test_end_time - cache_test_start_time

print("📊 性能测试结果:")
print("==================================================")
local binary_results = {
    rowkey_time = rowkey_total_time,
    rowkey_ops = #test_data / rowkey_total_time,
    value_time = value_total_time,
    value_ops = #test_data / value_total_time,
    full_time = full_total_time,
    full_ops = #test_data / full_total_time
}

print(string.format("二进制编码插件 - RowKey编码: %.3f秒, %.0f次/秒", 
      binary_results.rowkey_time, binary_results.rowkey_ops))
print(string.format("二进制编码插件 - Value编码: %.3f秒, %.0f次/秒", 
      binary_results.value_time, binary_results.value_ops))
print(string.format("二进制编码插件 - 完整编码: %.3f秒, %.0f次/秒", 
      binary_results.full_time, binary_results.full_ops))

-- 对新插件进行同样的性能测试
if micro_ts_opt_plugin then
    print("\n🔍 micro_ts_optimized_v2 插件性能测试:")
    local test_count = #test_data
    
    -- RowKey编码测试
    local start_time = os.clock()
    for i = 1, test_count do
        local test_item = test_data[i]
        micro_ts_opt_plugin:encode_rowkey(test_item.stock_code, test_item.timestamp, test_item.market)
    end
    local rowkey_time = os.clock() - start_time
    local rowkey_ops = test_count / rowkey_time
    
    -- Value编码测试
    start_time = os.clock()
    for i = 1, test_count do
        local test_item = test_data[i]
        micro_ts_opt_plugin:encode_value(test_item)
    end
    local value_time = os.clock() - start_time
    local value_ops = test_count / value_time
    
    -- 完整编码测试
    start_time = os.clock()
    for i = 1, test_count do
        local test_item = test_data[i]
        local rk, q = micro_ts_opt_plugin:encode_rowkey(test_item.stock_code, test_item.timestamp, test_item.market)
        local v = micro_ts_opt_plugin:encode_value(test_item)
    end
    local full_time = os.clock() - start_time
    local full_ops = test_count / full_time
    
    print(string.format("micro_ts_optimized_v2 - RowKey编码: %.3f秒, %.0f次/秒", 
          rowkey_time, rowkey_ops))
    print(string.format("micro_ts_optimized_v2 - Value编码: %.3f秒, %.0f次/秒", 
          value_time, value_ops))
    print(string.format("micro_ts_optimized_v2 - 完整编码: %.3f秒, %.0f次/秒", 
          full_time, full_ops))
    
    -- 性能对比
    print("\n📊 性能对比分析:")
    print(string.format("RowKey编码性能提升: %.2fx", rowkey_ops / binary_results.rowkey_ops))
    print(string.format("Value编码性能提升: %.2fx", value_ops / binary_results.value_ops))
    print(string.format("完整编码性能提升: %.2fx", full_ops / binary_results.full_ops))
else
    print("\n❌ 无法找到micro_ts_optimized_v2插件")
end

print(string.format("缓存测试性能: %.6f 秒/操作 (总计 %.3f 秒)", cache_test_total_time / 10000, cache_test_total_time))

-- 计算缓存命中率提升
local cache_hit_improvement = (full_total_time / #test_data) / (cache_test_total_time / 10000)
print(string.format("缓存命中率提升: %.2f 倍", cache_hit_improvement))

-- 测试解码性能
local decode_start_time = os.clock()
for i = 1, 10000 do
    local item = test_data[i]
    local rowkey, qualifier = binary_plugin:encode_rowkey(item.stock_code, item.timestamp, item.market)
    local value = binary_plugin:encode_value(item.data)
    
    -- 解码测试
    binary_plugin:decode_rowkey(rowkey)
    binary_plugin:decode_value(value)
end
local decode_end_time = os.clock()
local decode_total_time = decode_end_time - decode_start_time

print(string.format("解码性能: %.6f 秒/操作 (总计 %.3f 秒)", decode_total_time / 10000, decode_total_time))

-- 内存使用分析
print("\n💾 内存使用分析:")
print("==================================================")
if binary_plugin.get_memory_usage then
    local binary_mem = binary_plugin:get_memory_usage()
    print(string.format("二进制编码插件 - RowKey缓存大小: %d KB", binary_mem.rowkey_cache_kb or 0))
    print(string.format("二进制编码插件 - Value缓存大小: %d KB", binary_mem.value_cache_kb or 0))
    print(string.format("二进制编码插件 - 总内存使用: %d KB", binary_mem.total_kb or 0))
end

if micro_ts_opt_plugin and micro_ts_opt_plugin.get_memory_usage then
    local micro_ts_mem = micro_ts_opt_plugin:get_memory_usage()
    print(string.format("micro_ts_optimized_v2 - RowKey缓存大小: %d KB", micro_ts_mem.rowkey_cache_kb or 0))
    print(string.format("micro_ts_optimized_v2 - Value缓存大小: %d KB", micro_ts_mem.value_cache_kb or 0))
    print(string.format("micro_ts_optimized_v2 - 总内存使用: %d KB", micro_ts_mem.total_kb or 0))
end

-- 验证数据完整性
print("\n🔍 数据完整性验证:")
print("==================================================")
local success_count = 0
local total_tests = 100

for i = 1, total_tests do
    local item = test_data[i]
    local rowkey, qualifier = binary_plugin:encode_rowkey(item.stock_code, item.timestamp, item.market)
    local value = binary_plugin:encode_value(item.data)
    
    -- 解码验证
    local decoded_key = binary_plugin:decode_rowkey(rowkey)
    local decoded_value = binary_plugin:decode_value(value)
    
    if decoded_key.market == item.market and 
       decoded_key.code == item.stock_code and
       math.abs(decoded_value.open - item.data.open) < 0.01 then
        success_count = success_count + 1
    end
end

print(string.format("数据完整性验证: %d/%d 成功", success_count, total_tests))

print("\n✅ 性能优化测试完成")
print("==================================================")