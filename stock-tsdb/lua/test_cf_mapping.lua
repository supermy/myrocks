-- 测试维度到CF的映射
print("=== 测试维度到CF映射 ===")

-- 导入light_aggregation_storage模块
local ok, storage_module = pcall(require, "light_aggregation_storage")
if not ok then
    print("❌ 无法加载light_aggregation_storage模块:", storage_module)
    os.exit(1)
end

-- 测试维度映射
local test_dimensions = {
    "HOUR", "DAY", "WEEK", "MONTH",  -- 时间维度
    "STOCK_CODE", "MARKET", "INDUSTRY",  -- 业务维度
    "UNKNOWN_DIMENSION"  -- 未知维度
}

print("维度到CF映射测试:")
for _, dimension in ipairs(test_dimensions) do
    -- 直接调用get_cf_for_dimension函数
    local cf_name = storage_module.get_cf_for_dimension(dimension)
    print(string.format("  %s -> %s", dimension, cf_name or "nil"))
end

print("✅ 维度映射测试完成")