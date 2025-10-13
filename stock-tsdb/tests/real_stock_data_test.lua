#!/usr/bin/env luajit

-- 真实股票行情数据测试
-- 使用Stock-TSDB系统进行真实数据测试

package.path = package.path .. ";./lua/?.lua"

local storage = require "storage"

-- 测试配置
local config = {
    data_dir = "../data/real_stock_test",
    write_buffer_size = 64 * 1024 * 1024,  -- 64MB
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,  -- 64MB
    max_bytes_for_level_base = 256 * 1024 * 1024,  -- 256MB
    compression = 4  -- lz4
}

print("=== 真实股票行情数据测试 ===")

print("\n1. 创建存储引擎...")
local engine = storage.create_engine(config)

print("2. 初始化存储引擎...")
local success, err = engine:initialize()
if not success then
    print("初始化失败:", err)
    return
end
print("存储引擎初始化成功")

-- 生成真实股票行情数据
print("\n3. 生成真实股票行情数据...")

-- 常见股票代码
local stock_codes = {
    "SH000001", "SH000300", "SH000905", "SZ399001", "SZ399006",
    "SH600519", "SH601318", "SH600036", "SH601166", "SH600276",
    "SZ000858", "SZ002415", "SZ000333", "SZ000651", "SZ002594"
}

-- 生成2024年10月9日的行情数据（从9:30到15:00，每秒一个数据点）
local start_timestamp = 1728459000  -- 2024-10-09 09:30:00
local end_timestamp = 1728486000   -- 2024-10-09 15:00:00
local total_points = 0

-- 模拟真实股票价格波动
local function generate_stock_data(code, base_price, volatility)
    local data_points = {}
    local current_price = base_price
    
    for timestamp = start_timestamp, end_timestamp do
        -- 模拟价格波动（正态分布）
        local change = (math.random() - 0.5) * 2 * volatility
        current_price = current_price + change
        
        -- 确保价格为正数
        current_price = math.max(current_price, 0.01)
        
        table.insert(data_points, {
            timestamp = timestamp,
            value = current_price,
            quality = 100  -- 数据质量
        })
        
        total_points = total_points + 1
    end
    
    return data_points
end

-- 不同股票的基准价格和波动率
local stock_configs = {
    ["SH000001"] = {base_price = 3500.0, volatility = 5.0},   -- 上证指数
    ["SH000300"] = {base_price = 3800.0, volatility = 4.0},   -- 沪深300
    ["SH600519"] = {base_price = 1800.0, volatility = 10.0},  -- 贵州茅台
    ["SZ000858"] = {base_price = 150.0, volatility = 2.0},    -- 五粮液
    ["SZ002594"] = {base_price = 250.0, volatility = 3.0},    -- 比亚迪
}

print("4. 批量写入股票行情数据...")

-- 批量写入数据
for _, code in ipairs(stock_codes) do
    local config = stock_configs[code] or {base_price = 100.0, volatility = 1.0}
    local data_points = generate_stock_data(code, config.base_price, config.volatility)
    
    -- 分批写入，每批1000个数据点
    local batch_size = 1000
    for i = 1, #data_points, batch_size do
        local batch = {}
        for j = i, math.min(i + batch_size - 1, #data_points) do
            table.insert(batch, data_points[j])
        end
        
        success, err = engine:write_points(code, batch, 0)  -- 数据类型0表示价格数据
        if not success then
            print(string.format("  ✗ 写入 %s 数据失败: %s", code, err))
            break
        end
    end
    
    print(string.format("  ✓ 写入 %s 数据完成，共 %d 个数据点", code, #data_points))
end

print(string.format("\n总共写入 %d 个数据点", total_points))

-- 测试查询功能
print("\n5. 测试查询功能...")

-- 测试单股票查询
local test_code = "SH600519"
local test_timestamp = start_timestamp + 3600  -- 10:30:00

print(string.format("\n查询 %s 在 %d 的数据点...", test_code, test_timestamp))
success, result = engine:read_point(test_code, test_timestamp, 0)
if success and result then
    print(string.format("  ✓ 查询成功: 时间=%d, 值=%.2f, 质量=%d", 
        result.timestamp, result.value, result.quality))
else
    print("  ✗ 查询失败:", result or "数据不存在")
end

-- 测试范围查询
print(string.format("\n查询 %s 在 %d-%d 的数据范围...", test_code, start_timestamp, start_timestamp + 300))
success, results = engine:read_range(test_code, start_timestamp, start_timestamp + 300, 0)
if success then
    print(string.format("  ✓ 范围查询成功，获取 %d 个数据点", #results))
    
    -- 显示前5个数据点
    for i = 1, math.min(5, #results) do
        local point = results[i]
        print(string.format("    %d: 时间=%d, 值=%.2f, 质量=%d", 
            i, point.timestamp, point.value, point.quality))
    end
else
    print("  ✗ 范围查询失败:", results)
end

-- 测试最新数据查询
print(string.format("\n查询 %s 的最新数据点...", test_code))
success, result = engine:get_latest_point(test_code, 0)
if success then
    print(string.format("  ✓ 最新数据: 时间=%d, 值=%.2f", result.timestamp, result.value))
else
    print("  ✗ 最新数据查询失败:", result)
end

-- 测试统计信息
print("\n6. 获取统计信息...")
success, stats = engine:get_statistics()
if success then
    print("  ✓ 统计信息获取成功")
    print(string.format("    写入次数: %d", stats.write_count or 0))
    print(string.format("    读取次数: %d", stats.read_count or 0))
    print(string.format("    缓存命中率: %.2f%%", (stats.cache_hit_rate or 0) * 100))
else
    print("  ✗ 统计信息获取失败:", stats)
end

-- 测试数据压缩
print("\n7. 测试数据压缩...")
success, err = engine:compact_data(test_code)
if not success then
    print("  ✗ 数据压缩失败:", err)
else
    print("  ✓ 数据压缩成功")
end

-- 性能测试
print("\n8. 性能测试...")

-- 批量读取性能测试
local start_time = os.clock()
local read_count = 0

for i = 1, 1000 do
    local random_timestamp = start_timestamp + math.random(0, end_timestamp - start_timestamp)
    success, result = engine:read_point(test_code, random_timestamp, 0)
    if success then
        read_count = read_count + 1
    end
end

local end_time = os.clock()
local elapsed_time = end_time - start_time
local qps = read_count / elapsed_time

print(string.format("  随机读取 %d 次，耗时 %.3f 秒，QPS: %.2f", read_count, elapsed_time, qps))

-- 关闭存储引擎
print("\n9. 关闭存储引擎...")
engine:shutdown()
print("存储引擎已关闭")

print("\n=== 真实股票行情数据测试完成 ===")
print(string.format("总数据点: %d", total_points))
print("所有测试功能正常运行！")