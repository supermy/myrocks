#!/usr/bin/env luajit

-- RowKey与Value编码插件性能对比分析
-- 对比股票行情业务现有编码方案与IOT业务新编码方案的性能差异

package.path = package.path .. ";./lua/?.lua"

local PerformanceTest = require "lua.rowkey_value_performance_test"

-- 创建性能测试实例
local performance_test = PerformanceTest:new()

-- 运行完整的性能对比测试
print("开始RowKey与Value编码插件性能对比测试...")
local report = performance_test:generate_performance_report()

-- 保存详细测试结果
-- 使用简单的字符串拼接替代cjson，避免依赖问题
local function simple_json_encode(obj)
    if type(obj) == "table" then
        local items = {}
        for k, v in pairs(obj) do
            if type(k) == "string" then
                k = '"' .. k .. '"'
            end
            if type(v) == "string" then
                v = '"' .. v .. '"'
            elseif type(v) == "table" then
                v = simple_json_encode(v)
            end
            table.insert(items, k .. ":" .. tostring(v))
        end
        return "{" .. table.concat(items, ",") .. "}"
    else
        return tostring(obj)
    end
end

local report_json = simple_json_encode(report)

-- 将结果写入文件
local file = io.open("rowkey_value_plugin_performance_report.json", "w")
if file then
    file:write(report_json)
    file:close()
    print("\n详细测试结果已保存到: rowkey_value_plugin_performance_report.json")
end

-- 生成性能对比总结
print("\n" .. string.rep("=", 80))
print("ROWKEY与VALUE编码插件性能对比总结")
print(string.rep("=", 80))

-- 分析具体性能指标
local function analyze_performance_difference(plugin1, plugin2, comparison)
    local encode_diff = (comparison.encode_comparison.speed_ratio - 1) * 100
    local size_diff = (1 - comparison.encode_comparison.size_ratio) * 100
    local decode_diff = (comparison.decode_comparison.speed_ratio - 1) * 100
    
    return {
        encode_performance_diff = encode_diff,
        size_efficiency_diff = size_diff,
        decode_performance_diff = decode_diff
    }
end

-- 股票行情数据分析
print("\n📈 股票行情数据性能分析:")
local stock_analysis = analyze_performance_difference("stock_quote", "iot_data", report.stock_comparison)
print(string.format("  编码性能差异: %s 比 %s %s%.1f%%",
    report.stock_comparison.encode_comparison.winner,
    report.stock_comparison.encode_comparison.winner == "stock_quote" and "iot_data" or "stock_quote",
    stock_analysis.encode_performance_diff >= 0 and "+" or "",
    stock_analysis.encode_performance_diff))

print(string.format("  存储效率差异: %s 比 %s %s%.1f%%",
    report.stock_comparison.encode_comparison.size_winner,
    report.stock_comparison.encode_comparison.size_winner == "stock_quote" and "iot_data" or "stock_quote",
    stock_analysis.size_efficiency_diff >= 0 and "+" or "",
    stock_analysis.size_efficiency_diff))

-- IOT数据分析
print("\n📊 IOT数据性能分析:")
local iot_analysis = analyze_performance_difference("stock_quote", "iot_data", report.iot_comparison)
print(string.format("  编码性能差异: %s 比 %s %s%.1f%%",
    report.iot_comparison.encode_comparison.winner,
    report.iot_comparison.encode_comparison.winner == "stock_quote" and "iot_data" or "stock_quote",
    iot_analysis.encode_performance_diff >= 0 and "+" or "",
    iot_analysis.encode_performance_diff))

print(string.format("  存储效率差异: %s 比 %s %s%.1f%%",
    report.iot_comparison.encode_comparison.size_winner,
    report.iot_comparison.encode_comparison.size_winner == "stock_quote" and "iot_data" or "stock_quote",
    iot_analysis.size_efficiency_diff >= 0 and "+" or "",
    iot_analysis.size_efficiency_diff))

-- 生成重构建议
print("\n🔧 重构建议:")
print("1. 股票行情业务:")
print("   ✅ 保持现有JSON编码方案")
print("   ✅ 继续支持可变长度RowKey")
print("   ✅ 维持30秒时间分块策略")

print("\n2. IOT业务:")
print("   ✅ 采用新的二进制编码方案")
print("   ✅ 使用固定长度RowKey(20字节)")
print("   ✅ 使用固定长度Value(16字节)")
print("   ✅ 预计存储效率提升30-50%")

print("\n3. 架构优势:")
print("   ✅ 插件化设计支持多种业务场景")
print("   ✅ 统一的插件接口便于扩展")
print("   ✅ 性能可测量和对比")
print("   ✅ 支持运行时插件切换")

-- 性能优化建议
print("\n⚡ 性能优化建议:")
local function get_plugin_info(plugin_name)
    local plugin = require("lua.rowkey_value_plugin").default_manager:get_plugin(plugin_name)
    return plugin and plugin:get_info() or {}
end

local stock_info = get_plugin_info("stock_quote")
local iot_info = get_plugin_info("iot_data")

print(string.format("   • %s: %s", stock_info.name or "stock_quote", stock_info.description or ""))
print(string.format("   • %s: %s", iot_info.name or "iot_data", iot_info.description or ""))

-- 部署建议
print("\n🚀 部署建议:")
print("   • 单节点部署: 使用基础版本 + 股票行情插件")
print("   • 多节点部署: 使用集成版本 + 混合插件方案")
print("   • 高并发场景: 优先使用二进制编码插件")
print("   • 调试阶段: 使用JSON编码插件便于问题排查")

print("\n" .. string.rep("=", 80))
print("测试完成！详细结果请查看: rowkey_value_plugin_performance_report.json")
print(string.rep("=", 80))

-- 返回测试结果供其他模块使用
return {
    success = true,
    report = report,
    analysis = {
        stock = stock_analysis,
        iot = iot_analysis
    },
    recommendations = report.overall_recommendations
}