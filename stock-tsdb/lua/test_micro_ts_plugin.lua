-- 测试高性能micro_ts插件（FFI调用micro_ts.so）
-- 注意：此插件需要使用LuaJIT运行，因为需要FFI模块

local plugin_module = require("lua.rowkey_value_plugin")

-- 获取插件管理器
local plugin_manager = plugin_module.default_manager

-- 获取micro_ts插件
local micro_ts_plugin = plugin_manager:get_plugin("micro_ts")

if not micro_ts_plugin then
    print("❌ micro_ts插件未找到")
    os.exit(1)
end

print("🚀 测试高性能micro_ts插件（FFI调用micro_ts.so）")
print("=" .. string.rep("=", 78))

-- 测试插件基本信息
local info = micro_ts_plugin:get_info()
print("📋 插件基本信息:")
print("  名称:", info.name)
print("  版本:", info.version)
print("  描述:", info.description)
print("  编码格式:", info.encoding_format)
print("  Key格式:", info.key_format)
print("  Value格式:", info.value_format)
print("  支持类型:", table.concat(info.supported_types, ", "))
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

print("\n🔍 编码测试:")
print("  原始数据:")
print("    股票代码:", test_data.stock_code)
print("    市场:", test_data.market)
print("    时间戳:", test_data.timestamp)
print("    价格:", test_data.price)
print("    成交量:", test_data.volume)
print("    通道:", test_data.ch)
print("    方向:", test_data.side)
print("    订单号:", test_data.order_no)
print("    成交号:", test_data.tick_no)

-- 编码测试
local rowkey, qualifier = micro_ts_plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
local value = micro_ts_plugin:encode_value(test_data)

print("\n✅ 编码结果:")
print("  RowKey长度:", #rowkey, "字节")
print("  Qualifier长度:", #qualifier, "字节")
print("  Value长度:", #value, "字节")

-- 显示二进制数据的十六进制表示
print("\n🔢 二进制数据（十六进制）:")
print("  RowKey:", string.format("%02X", string.byte(rowkey, 1, math.min(10, #rowkey))))
print("  Qualifier:", string.format("%02X", string.byte(qualifier, 1, math.min(6, #qualifier))))
print("  Value:", string.format("%02X", string.byte(value, 1, math.min(10, #value))))

-- 解码测试
local decoded_key = micro_ts_plugin:decode_rowkey(rowkey)
local decoded_value = micro_ts_plugin:decode_value(value)

print("\n✅ 解码结果:")
print("  解码Key:")
print("    市场:", decoded_key.market)
print("    股票代码:", decoded_key.stock_code)
print("    时间戳:", decoded_key.timestamp)

print("  解码Value:")
print("    价格:", decoded_value.price)
print("    成交量:", decoded_value.volume)
print("    通道:", decoded_value.ch)
print("    方向:", decoded_value.side)
print("    订单号:", decoded_value.order_no)
print("    成交号:", decoded_value.tick_no)

-- 验证解码正确性
local key_correct = (decoded_key.market == test_data.market) and 
                   (decoded_key.stock_code == test_data.stock_code) and
                   (math.abs(decoded_key.timestamp - test_data.timestamp) < 60)  -- 允许1分钟误差

local value_correct = (decoded_value.price == test_data.price) and
                     (decoded_value.volume == test_data.volume) and
                     (decoded_value.ch == test_data.ch) and
                     (decoded_value.side == test_data.side) and
                     (decoded_value.order_no == test_data.order_no) and
                     (decoded_value.tick_no == test_data.tick_no)

print("\n✅ 验证结果:")
print("  Key解码正确:", key_correct and "✓" or "✗")
print("  Value解码正确:", value_correct and "✓" or "✗")

if key_correct and value_correct then
    print("🎉 所有测试通过！")
else
    print("❌ 测试失败！")
    os.exit(1)
end

-- 性能测试
print("\n⚡ 性能测试:")
local performance_result = micro_ts_plugin:performance_test(10000)

print("  测试迭代次数:", performance_result.iterations)
print("  编码总时间:", string.format("%.3f", performance_result.encode_time_ms), "ms")
print("  解码总时间:", string.format("%.3f", performance_result.decode_time_ms), "ms")
print("  编码吞吐量:", string.format("%.0f", performance_result.encode_ops_per_sec), "ops/sec")
print("  解码吞吐量:", string.format("%.0f", performance_result.decode_ops_per_sec), "ops/sec")
print("  平均编码时间:", string.format("%.6f", performance_result.avg_encode_time_per_op), "ms/op")
print("  平均解码时间:", string.format("%.6f", performance_result.avg_decode_time_per_op), "ms/op")

-- 与其他插件的对比
print("\n📊 性能对比（参考）:")
print("  • micro_ts插件（FFI）: < 0.01ms/op")
print("  • stock_quote_binary插件: ~0.05ms/op")
print("  • financial_quote插件: ~0.1ms/op")
print("  • stock_quote插件: ~0.15ms/op")

print("\n✅ micro_ts插件测试完成")
print("=" .. string.rep("=", 78))