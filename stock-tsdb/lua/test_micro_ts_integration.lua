-- micro_ts插件集成测试
-- 测试插件在插件管理器中的注册和使用

print("🚀 测试micro_ts插件集成功能")
print("=" .. string.rep("=", 78))

-- 加载插件管理器
local plugin_module = require("lua.rowkey_value_plugin")

-- 使用默认插件管理器实例（已包含所有注册的插件）
local plugin_manager = plugin_module.default_manager

-- 测试插件注册
print("📋 测试插件注册:")
local plugins = plugin_manager:list_plugins()
print("  已注册插件数量:", #plugins)

-- 查找micro_ts插件
local micro_ts_plugin = nil
print("  已注册插件列表:")
for _, plugin_info in ipairs(plugins) do
    print("    -", plugin_info.name)
    if plugin_info.name == "micro_ts" then
        micro_ts_plugin = plugin_manager:get_plugin("micro_ts")
        print("  ✅ 找到micro_ts插件")
        break
    end
end

if not micro_ts_plugin then
    print("  ❌ 未找到micro_ts插件")
    os.exit(1)
end

-- 测试插件基本信息
print("\n🔍 测试插件基本信息:")
print("  插件名称:", micro_ts_plugin:get_name())
print("  插件版本:", micro_ts_plugin:get_version())
print("  插件描述:", micro_ts_plugin:get_description())

-- 测试编码功能
print("\n🔧 测试编码功能:")
local test_data = {
    stock_code = "000001",
    market = "SH",
    timestamp = 1760272200,
    price = 1000,
    volume = 10000,
    ch = 1,
    side = 0,
    order_no = 1234567890,
    tick_no = 9876543210
}

local rowkey, qualifier = micro_ts_plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
local value = micro_ts_plugin:encode_value(test_data)
print("  ✅ 编码成功")
print("  RowKey长度:", #rowkey, "字节")
print("  Qualifier长度:", #qualifier, "字节")
print("  Value长度:", #value, "字节")

-- 测试解码功能
print("\n🔍 测试解码功能:")
local decoded_key = micro_ts_plugin:decode_rowkey(rowkey)
local decoded_value = micro_ts_plugin:decode_value(value)

print("  ✅ 解码成功")
print("  解码Key - 市场:", decoded_key.market)
print("  解码Key - 股票代码:", decoded_key.stock_code)
print("  解码Key - 时间戳:", decoded_key.timestamp)
print("  解码Value - 价格:", decoded_value.price)
print("  解码Value - 成交量:", decoded_value.volume)

-- 验证数据一致性
print("\n✅ 验证数据一致性:")
local key_match = decoded_key.market == test_data.market and 
                 decoded_key.stock_code == test_data.stock_code and
                 decoded_key.timestamp == test_data.timestamp
                 
local value_match = decoded_value.price == test_data.price and
                   decoded_value.volume == test_data.volume and
                   decoded_value.ch == test_data.ch and
                   decoded_value.side == test_data.side

if key_match and value_match then
    print("  ✅ 数据一致性验证通过")
else
    print("  ❌ 数据一致性验证失败")
    os.exit(1)
end

-- 测试默认插件设置
print("\n⚙️  测试默认插件设置:")
local default_plugin = plugin_manager:get_default_plugin()
print("  当前默认插件:", default_plugin and default_plugin:get_name() or "无")

-- 设置micro_ts为默认插件
plugin_manager:set_default_plugin("micro_ts")
local new_default = plugin_manager:get_default_plugin()
print("  设置后默认插件:", new_default and new_default:get_name() or "无")

if new_default and new_default:get_name() == "micro_ts" then
    print("  ✅ 默认插件设置成功")
else
    print("  ❌ 默认插件设置失败")
end

-- 性能对比测试
print("\n⚡ 性能对比测试:")
local iterations = 10000

-- micro_ts插件性能测试
local start_time = os.clock()
for i = 1, iterations do
    local rk, q = micro_ts_plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
    local v = micro_ts_plugin:encode_value(test_data)
    local dk = micro_ts_plugin:decode_rowkey(rk)
    local dv = micro_ts_plugin:decode_value(v)
end
local micro_ts_time = os.clock() - start_time

-- 获取其他插件进行对比
local other_plugins = {}
for _, plugin_name in ipairs(plugins) do
    if plugin_name ~= "micro_ts" then
        local plugin = plugin_manager:get_plugin(plugin_name)
        if plugin and plugin.encode_rowkey then
            table.insert(other_plugins, {
                name = plugin_name,
                plugin = plugin
            })
        end
    end
end

-- 测试其他插件性能
local other_times = {}
for _, plugin_info in ipairs(other_plugins) do
    local start = os.clock()
    for i = 1, iterations do
        local rk, q, v = plugin_info.plugin:encode_rowkey(test_data)
        local dk = plugin_info.plugin:decode_rowkey(rk)
        local dv = plugin_info.plugin:decode_value(v)
    end
    other_times[plugin_info.name] = os.clock() - start
end

-- 输出性能结果
print("  测试迭代次数:", iterations)
print("  micro_ts插件时间:", string.format("%.3f", micro_ts_time), "秒")
print("  micro_ts插件吞吐量:", string.format("%.0f", iterations / micro_ts_time), "ops/sec")

for plugin_name, time in pairs(other_times) do
    print("  " .. plugin_name .. "时间:", string.format("%.3f", time), "秒")
    print("  " .. plugin_name .. "吞吐量:", string.format("%.0f", iterations / time), "ops/sec")
    local speedup = time / micro_ts_time
    print("  性能提升倍数:", string.format("%.1f", speedup), "x")
end

print("\n🎉 micro_ts插件集成测试完成")
print("=" .. string.rep("=", 78))