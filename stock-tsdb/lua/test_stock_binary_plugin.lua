-- 测试股票行情二进制编码插件

local plugin_module = require("lua.rowkey_value_plugin")

-- 获取插件管理器
local plugin_manager = plugin_module.default_manager

-- 获取二进制编码插件
local binary_plugin = plugin_module.StockQuoteBinaryPlugin:new()

print("🚀 测试股票行情二进制编码插件")
print("=" .. string.rep("=", 78))

-- 测试插件基本信息
local info = binary_plugin:get_info()
print("📋 插件基本信息:")
print("  名称:", info.name)
print("  版本:", info.version)
print("  描述:", info.description)
print("  编码格式:", info.encoding_format)
print("  Key格式:", info.key_format)
print("  Value格式:", info.value_format)
print("  支持类型:", table.concat(info.supported_types, ", "))

-- 测试数据
local test_data = {
    stock_code = "000001",
    market = "SH",
    timestamp = os.time(),
    open = 10.50,
    high = 11.20,
    low = 10.30,
    close = 10.80,
    volume = 1000000,
    amount = 10800000.00
}

print("\n🔍 编码测试:")
print("  原始数据:")
print("    股票代码:", test_data.stock_code)
print("    市场:", test_data.market)
print("    时间戳:", test_data.timestamp)
print("    开盘价:", test_data.open)
print("    最高价:", test_data.high)
print("    最低价:", test_data.low)
print("    收盘价:", test_data.close)
print("    成交量:", test_data.volume)
print("    成交额:", test_data.amount)

-- 编码测试
local rowkey, qualifier = binary_plugin:encode_rowkey(
    test_data.stock_code, test_data.timestamp, test_data.market
)
local value = binary_plugin:encode_value(test_data)

print("\n  编码结果:")
print("    RowKey长度:", #rowkey, "字节")
print("    Qualifier:", qualifier)
print("    Value长度:", #value, "字节")
print("    总存储大小:", #rowkey + #qualifier + #value, "字节")

-- 解码测试
print("\n🔍 解码测试:")
local decoded_key = binary_plugin:decode_rowkey(rowkey)
local decoded_value = binary_plugin:decode_value(value)

print("  解码Key结果:")
print("    类型:", decoded_key.type)
print("    市场:", decoded_key.market)
print("    股票代码:", decoded_key.code)
print("    时间戳:", decoded_key.timestamp)

print("  解码Value结果:")
print("    开盘价:", decoded_value.open)
print("    最高价:", decoded_value.high)
print("    最低价:", decoded_value.low)
print("    收盘价:", decoded_value.close)
print("    成交量:", decoded_value.volume)
print("    成交额:", decoded_value.amount)

-- 性能对比测试
print("\n⚡ 性能对比测试")
print("-" .. string.rep("-", 78))

-- 获取JSON编码插件
local json_plugin = plugin_module.StockQuotePlugin:new()

local iterations = 1000
local test_count = 100

-- 生成测试数据
local test_data_list = {}
for i = 1, test_count do
    table.insert(test_data_list, {
        stock_code = string.format("%06d", i),
        market = "SH",
        timestamp = os.time() + i,
        open = 10.0 + i * 0.01,
        high = 11.0 + i * 0.01,
        low = 9.5 + i * 0.01,
        close = 10.5 + i * 0.01,
        volume = 1000000 + i * 1000,
        amount = 10000000 + i * 10000
    })
end

-- 测试二进制编码性能
local binary_start = os.clock()
for iter = 1, iterations do
    for _, data in ipairs(test_data_list) do
        local rowkey, qualifier = binary_plugin:encode_rowkey(
            data.stock_code, data.timestamp, data.market
        )
        local value = binary_plugin:encode_value(data)
        local decoded_key = binary_plugin:decode_rowkey(rowkey)
        local decoded_value = binary_plugin:decode_value(value)
    end
end
local binary_end = os.clock()
local binary_time = binary_end - binary_start

-- 测试JSON编码性能
local json_start = os.clock()
for iter = 1, iterations do
    for _, data in ipairs(test_data_list) do
        local rowkey, qualifier = json_plugin:encode_rowkey(
            data.stock_code, data.timestamp, data.market
        )
        local value = json_plugin:encode_value(data)
        local decoded_key = json_plugin:decode_rowkey(rowkey)
        local decoded_value = json_plugin:decode_value(value)
    end
end
local json_end = os.clock()
local json_time = json_end - json_start

-- 计算存储效率
local binary_key_size = 0
local binary_value_size = 0
local json_key_size = 0
local json_value_size = 0

for _, data in ipairs(test_data_list) do
    local b_rowkey, b_qualifier = binary_plugin:encode_rowkey(
        data.stock_code, data.timestamp, data.market
    )
    local b_value = binary_plugin:encode_value(data)
    
    local j_rowkey, j_qualifier = json_plugin:encode_rowkey(
        data.stock_code, data.timestamp, data.market
    )
    local j_value = json_plugin:encode_value(data)
    
    binary_key_size = binary_key_size + #b_rowkey + #b_qualifier
    binary_value_size = binary_value_size + #b_value
    json_key_size = json_key_size + #j_rowkey + #j_qualifier
    json_value_size = json_value_size + #j_value
end

local binary_avg_key = binary_key_size / test_count
local binary_avg_value = binary_value_size / test_count
local json_avg_key = json_key_size / test_count
local json_avg_value = json_value_size / test_count

print("📊 性能对比结果:")
print("  二进制编码:")
print("    总时间:", string.format("%.3f", binary_time), "秒")
print("    平均时间:", string.format("%.6f", binary_time / (iterations * test_count)), "秒/操作")
print("    平均Key大小:", string.format("%.1f", binary_avg_key), "字节")
print("    平均Value大小:", string.format("%.1f", binary_avg_value), "字节")
print("    总存储大小:", string.format("%.1f", binary_avg_key + binary_avg_value), "字节")

print("  JSON编码:")
print("    总时间:", string.format("%.3f", json_time), "秒")
print("    平均时间:", string.format("%.6f", json_time / (iterations * test_count)), "秒/操作")
print("    平均Key大小:", string.format("%.1f", json_avg_key), "字节")
print("    平均Value大小:", string.format("%.1f", json_avg_value), "字节")
print("    总存储大小:", string.format("%.1f", json_avg_key + json_avg_value), "字节")

print("\n📈 性能提升:")
local time_improvement = ((json_time - binary_time) / json_time) * 100
local storage_improvement = ((json_avg_key + json_avg_value - binary_avg_key - binary_avg_value) / (json_avg_key + json_avg_value)) * 100
print("  性能提升:", string.format("%.1f%%", time_improvement))
print("  存储效率提升:", string.format("%.1f%%", storage_improvement))

print("\n✅ 测试完成")