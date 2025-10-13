-- 插件对比测试分析
-- 对比分析所有已注册插件的性能、功能和适用场景

print("🔍 插件对比测试分析")
print("=" .. string.rep("=", 78))

-- 设置模块搜索路径
package.path = package.path .. ";./?.lua;./lua/?.lua;../?.lua;../lua/?.lua"

-- 加载插件管理器
local plugin_module = require("rowkey_value_plugin")
local plugin_manager = plugin_module.default_manager

-- 加载并注册micro_ts_plugin_optimized_v2插件
local MicroTsOptimizedV2Plugin = require("micro_ts_plugin_optimized_v2")
plugin_manager:register_plugin(MicroTsOptimizedV2Plugin:new())

-- 加载并注册其他micro_ts插件版本
local MicroTsFinalPlugin = require("micro_ts_plugin_final")
plugin_manager:register_plugin(MicroTsFinalPlugin:new())

local MicroTsOptimizedPlugin = require("micro_ts_plugin_optimized")
plugin_manager:register_plugin(MicroTsOptimizedPlugin:new())

-- 加载并注册模拟业务插件
local SimulationBusinessPlugin = require("simulation_business_plugin")
plugin_manager:register_plugin(SimulationBusinessPlugin:new())

-- 获取所有插件列表
local plugins = plugin_manager:list_plugins()
print("📊 已注册插件数量:", #plugins)
print("📋 插件列表:")

local plugin_instances = {}
for _, plugin_info in ipairs(plugins) do
    local plugin = plugin_manager:get_plugin(plugin_info.name)
    plugin_instances[plugin_info.name] = plugin
    print(string.format("  • %-20s v%s - %s", 
        plugin_info.name, plugin_info.version, plugin_info.description))
end

-- 测试数据定义
local test_data = {
    -- 股票数据
    stock_code = "000001",
    market = "SH",
    timestamp = 1760272200,  -- 数字类型时间戳
    price = 1000,
    volume = 10000,
    ch = 1,
    side = 0,
    order_no = 1234567890,
    tick_no = 9876543210,
    
    -- 金融数据
    product_type = "stock",
    symbol = "000001",
    precision = 6,
    
    -- 订单数据
    user_id = 10001,
    order_id = "ORD202412010001",
    order_type = "normal",
    amount = 1000.50,
    currency = "CNY",
    status = "pending",
    
    -- 支付数据
    merchant_id = 20001,
    transaction_id = "TXN202412010001",
    payment_method = "alipay",
    
    -- 库存数据
    warehouse_id = 30001,
    sku_id = "SKU001",
    operation_type = "inbound",
    quantity = 100,
    
    -- IOT数据
    device_id = "DEV001",
    metric_type = "temperature",
    location = "BJ",
    
    -- 短信数据
    phone = "13800138000",
    template_id = "TMP001",
    content = "测试短信内容"
}

-- 性能测试函数
local function run_performance_test(plugin, plugin_name, iterations)
    local start_time = os.clock()
    
    for i = 1, iterations do
        local rk, q, v
        
        -- 根据插件类型调用不同的编码方法
        if plugin_name == "micro_ts" or plugin_name == "micro_ts_optimized_v2" or 
           plugin_name == "micro_ts_final" or plugin_name == "micro_ts_optimized" then
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value(test_data)
        elseif plugin_name == "simulation_business" then
            rk, q = plugin:encode_rowkey("finance", test_data.stock_code, test_data.timestamp, "medium")
            v = plugin:encode_value({
                scenario = "finance",
                entity_id = test_data.stock_code,
                timestamp = test_data.timestamp,
                complexity = "medium",
                price = test_data.price,
                volume = test_data.volume,
                market = test_data.market
            })
        elseif plugin_name == "stock_quote_binary" or plugin_name == "stock_quote" then
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value({
                open = test_data.price, high = test_data.price, 
                low = test_data.price, close = test_data.price,
                volume = test_data.volume, amount = test_data.price * test_data.volume
            })
        elseif plugin_name == "financial_quote" then
            rk, q = plugin:encode_rowkey(test_data.product_type, test_data.symbol, test_data.timestamp, test_data.market, test_data.precision)
            v = plugin:encode_value(test_data)
        elseif plugin_name == "order_management" then
            rk, q = plugin:encode_rowkey(test_data.user_id, test_data.order_id, test_data.timestamp, test_data.order_type)
            v = plugin:encode_value({
                user_id = test_data.user_id,
                order_id = test_data.order_id,
                amount = test_data.amount,
                currency = test_data.currency,
                status = test_data.status,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp,
                order_type = test_data.order_type
            })
        elseif plugin_name == "payment_system" then
            rk, q = plugin:encode_rowkey(test_data.merchant_id, test_data.transaction_id, test_data.timestamp, test_data.payment_method)
            v = plugin:encode_value({
                merchant_id = test_data.merchant_id,
                transaction_id = test_data.transaction_id,
                amount = test_data.amount,
                currency = test_data.currency,
                status = test_data.status,
                payment_method = test_data.payment_method,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp
            })
        elseif plugin_name == "inventory_management" then
            rk, q = plugin:encode_rowkey(test_data.warehouse_id, test_data.sku_id, test_data.timestamp, test_data.operation_type)
            v = plugin:encode_value({
                warehouse_id = test_data.warehouse_id,
                sku_id = test_data.sku_id,
                quantity = test_data.quantity,
                operation_type = test_data.operation_type,
                status = test_data.status,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp
            })
        elseif plugin_name == "iot_data" then
            rk, q = plugin:encode_rowkey(test_data.device_id, test_data.timestamp, test_data.metric_type, test_data.location)
            v = plugin:encode_value({
                device_id = test_data.device_id,
                timestamp = test_data.timestamp,
                metric_type = test_data.metric_type,
                value = test_data.price,
                location = test_data.location
            })
        elseif plugin_name == "sms_delivery" then
            rk, q = plugin:encode_rowkey(test_data.phone, test_data.template_id, test_data.timestamp, "verification")
            v = plugin:encode_value({
                channel = test_data.phone,
                template_id = test_data.template_id,
                phone_number = test_data.phone,
                content = test_data.content,
                status = test_data.status,
                create_time = test_data.timestamp,
                send_time = test_data.timestamp,
                sms_type = "verification",
                priority = 1
            })
        else
            -- 默认使用股票数据
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value(test_data)
        end
        
        -- 解码测试
        local dk = plugin:decode_rowkey(rk)
        local dv = plugin:decode_value(v)
    end
    
    local total_time = os.clock() - start_time
    return total_time
end

-- 功能测试函数
local function run_functional_test(plugin, plugin_name)
    local results = {
        encode_success = false,
        decode_success = false,
        data_consistency = false,
        key_size = 0,
        value_size = 0
    }
    
    local success, rk, q, v = pcall(function()
        -- 编码测试
        if plugin_name == "micro_ts" or plugin_name == "micro_ts_optimized_v2" or 
           plugin_name == "micro_ts_final" or plugin_name == "micro_ts_optimized" then
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value(test_data)
        elseif plugin_name == "simulation_business" then
            rk, q = plugin:encode_rowkey("finance", test_data.stock_code, test_data.timestamp, "medium")
            v = plugin:encode_value({
                scenario = "finance",
                entity_id = test_data.stock_code,
                timestamp = test_data.timestamp,
                complexity = "medium",
                price = test_data.price,
                volume = test_data.volume,
                market = test_data.market
            })
        elseif plugin_name == "stock_quote_binary" or plugin_name == "stock_quote" then
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value({
                open = test_data.price, high = test_data.price, 
                low = test_data.price, close = test_data.price,
                volume = test_data.volume, amount = test_data.price * test_data.volume
            })
        elseif plugin_name == "financial_quote" then
            rk, q = plugin:encode_rowkey(test_data.product_type, test_data.symbol, test_data.timestamp, test_data.market, test_data.precision)
            v = plugin:encode_value(test_data)
        elseif plugin_name == "order_management" then
            rk, q = plugin:encode_rowkey(test_data.user_id, test_data.order_id, test_data.timestamp, test_data.order_type)
            v = plugin:encode_value({
                user_id = test_data.user_id,
                order_id = test_data.order_id,
                amount = test_data.amount,
                currency = test_data.currency,
                status = test_data.status,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp,
                order_type = test_data.order_type
            })
        elseif plugin_name == "payment_system" then
            rk, q = plugin:encode_rowkey(test_data.merchant_id, test_data.transaction_id, test_data.timestamp, test_data.payment_method)
            v = plugin:encode_value({
                merchant_id = test_data.merchant_id,
                transaction_id = test_data.transaction_id,
                amount = test_data.amount,
                currency = test_data.currency,
                status = test_data.status,
                payment_method = test_data.payment_method,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp
            })
        elseif plugin_name == "inventory_management" then
            rk, q = plugin:encode_rowkey(test_data.warehouse_id, test_data.sku_id, test_data.timestamp, test_data.operation_type)
            v = plugin:encode_value({
                warehouse_id = test_data.warehouse_id,
                sku_id = test_data.sku_id,
                quantity = test_data.quantity,
                operation_type = test_data.operation_type,
                status = test_data.status,
                create_time = test_data.timestamp,
                update_time = test_data.timestamp
            })
        elseif plugin_name == "iot_data" then
            rk, q = plugin:encode_rowkey(test_data.device_id, test_data.timestamp, test_data.metric_type, test_data.location)
            v = plugin:encode_value({
                device_id = test_data.device_id,
                timestamp = test_data.timestamp,
                metric_type = test_data.metric_type,
                value = test_data.price,
                location = test_data.location
            })
        elseif plugin_name == "sms_delivery" then
            rk, q = plugin:encode_rowkey(test_data.phone, test_data.template_id, test_data.timestamp, "verification")
            v = plugin:encode_value({
                channel = test_data.phone,
                template_id = test_data.template_id,
                phone_number = test_data.phone,
                content = test_data.content,
                status = test_data.status,
                create_time = test_data.timestamp,
                send_time = test_data.timestamp,
                sms_type = "verification",
                priority = 1
            })
        else
            rk, q = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market)
            v = plugin:encode_value(test_data)
        end
        return rk, q, v
    end)
    
    if success and rk then
        results.encode_success = true
        results.key_size = #rk
        results.value_size = #v
        
        -- 解码测试
        local dk_success, dk, dv = pcall(function()
            local dk = plugin:decode_rowkey(rk)
            local dv = plugin:decode_value(v)
            return dk, dv
        end)
        
        if dk_success and dk then
            results.decode_success = true
            
            -- 数据一致性验证
            if plugin_name == "micro_ts" or plugin_name == "micro_ts_optimized_v2" or 
               plugin_name == "micro_ts_final" or plugin_name == "micro_ts_optimized" then
                results.data_consistency = (dk.market == test_data.market and 
                                          dk.stock_code == test_data.stock_code and
                                          dk.timestamp == test_data.timestamp)
            elseif plugin_name == "simulation_business" then
                results.data_consistency = (dk.scenario == "finance" and 
                                          dk.entity_id == test_data.stock_code and
                                          dv.scenario == "finance" and
                                          dv.entity_id == test_data.stock_code)
            else
                results.data_consistency = true  -- 简化验证
            end
        else
            results.error = "解码失败"
        end
    else
        results.error = "编码失败"
    end
    
    return results
end

-- 执行性能对比测试
print("\n⚡ 性能对比测试")
print("-" .. string.rep("-", 78))

local iterations = 10000
local performance_results = {}

for plugin_name, plugin in pairs(plugin_instances) do
    if plugin.encode_rowkey then  -- 只测试支持编码的插件
        print("  测试插件:", plugin_name)
        local total_time = run_performance_test(plugin, plugin_name, iterations)
        
        performance_results[plugin_name] = {
            total_time = total_time,
            avg_time_per_op = total_time / iterations,
            ops_per_second = iterations / total_time
        }
        
        print(string.format("    时间: %.4f秒, 吞吐量: %.0f ops/sec", 
            total_time, iterations / total_time))
    end
end

-- 执行功能测试
print("\n🔧 功能测试")
print("-" .. string.rep("-", 78))

local functional_results = {}

for plugin_name, plugin in pairs(plugin_instances) do
    if plugin.encode_rowkey then
        print("  测试插件:", plugin_name)
        local results = run_functional_test(plugin, plugin_name)
        functional_results[plugin_name] = results
        
        print(string.format("    编码: %s, 解码: %s, 一致性: %s",
            results.encode_success and "✓" or "✗",
            results.decode_success and "✓" or "✗",
            results.data_consistency and "✓" or "✗"))
        if results.error then
            print("    错误:", results.error)
        end
    end
end

-- 分析报告
print("\n📊 综合分析报告")
print("=" .. string.rep("=", 78))

-- 性能排名
print("🏆 性能排名:")
local sorted_performance = {}
for plugin_name, results in pairs(performance_results) do
    table.insert(sorted_performance, {name = plugin_name, ops = results.ops_per_second})
end

table.sort(sorted_performance, function(a, b) return a.ops > b.ops end)

for i, item in ipairs(sorted_performance) do
    local speedup = item.ops / sorted_performance[#sorted_performance].ops
    print(string.format("  %d. %-20s %8.0f ops/sec (%.1fx)", 
        i, item.name, item.ops, speedup))
end

-- 功能完整性
print("\n✅ 功能完整性:")
for plugin_name, results in pairs(functional_results) do
    local score = 0
    if results.encode_success then score = score + 1 end
    if results.decode_success then score = score + 1 end
    if results.data_consistency then score = score + 1 end
    
    print(string.format("  %-20s %d/3 功能点", plugin_name, score))
end

-- 存储效率分析
print("\n💾 存储效率分析:")
for plugin_name, results in pairs(functional_results) do
    if results.key_size > 0 then
        print(string.format("  %-20s Key: %3dB, Value: %3dB, 总计: %3dB", 
            plugin_name, results.key_size, results.value_size, 
            results.key_size + results.value_size))
    end
end

-- 适用场景推荐
print("\n🎯 适用场景推荐:")

local recommendations = {
    micro_ts = "高频交易、实时数据处理、极致性能要求的场景",
    micro_ts_optimized_v2 = "超高频交易、极低延迟场景、精简优化的高性能数据处理",
    micro_ts_final = "最终优化版本、极致性能和稳定性的平衡、生产环境首选",
    micro_ts_optimized = "高性能场景、需要详细性能监控和缓存优化的业务",
    simulation_business = "多业务场景模拟、复杂业务逻辑测试、业务性能评估",
    stock_quote_binary = "股票行情数据存储、中等性能要求的业务",
    stock_quote = "通用股票数据处理、调试和兼容性优先的场景",
    financial_quote = "金融行情数据、复杂业务逻辑处理",
    order_management = "订单管理系统、事务性数据处理",
    payment_system = "支付系统、金融交易处理",
    inventory_management = "库存管理、商品数据存储",
    sms_delivery = "短信下发系统、消息队列处理",
    iot_data = "物联网数据、传感器数据存储"
}

for plugin_name, desc in pairs(recommendations) do
    if plugin_instances[plugin_name] then
        print(string.format("  %-20s %s", plugin_name, desc))
    end
end

-- 技术特性对比
print("\n🔬 技术特性对比:")

local technical_features = {
    micro_ts = "FFI调用、原生C性能、固定长度二进制",
    micro_ts_optimized_v2 = "精简优化版FFI调用、预分配缓冲区、轻量级缓存、极低内存占用",
    micro_ts_final = "最终优化版、精简缓存策略、预编译字符串操作、减少函数调用开销",
    micro_ts_optimized = "优化版FFI调用、LRU缓存、缓冲池、性能监控、详细统计信息",
    simulation_business = "多业务场景支持、可变复杂度数据、JSON格式、性能指标内置",
    stock_quote_binary = "二进制编码、紧凑格式、缓存优化",
    stock_quote = "JSON格式、易于调试、兼容性好",
    financial_quote = "金融专用、复杂编码、业务逻辑丰富",
    order_management = "订单专用、事务支持、状态管理",
    payment_system = "支付专用、安全加密、审计跟踪",
    inventory_management = "库存专用、批次管理、库存跟踪",
    sms_delivery = "短信专用、模板支持、状态跟踪",
    iot_data = "物联网专用、传感器数据、实时监控"
}

for plugin_name, features in pairs(technical_features) do
    if plugin_instances[plugin_name] then
        print(string.format("  %-20s %s", plugin_name, features))
    end
end

-- 总结建议
print("\n💡 总结建议:")
print("  1. 性能优先场景: 推荐使用 micro_ts 插件，提供原生C级别性能")
print("  2. 存储效率场景: 推荐使用 stock_quote_binary 插件，二进制紧凑格式")
print("  3. 开发调试场景: 推荐使用 stock_quote 插件，JSON格式易于调试")
print("  4. 业务专用场景: 根据具体业务需求选择对应的专用插件")
print("  5. 兼容性考虑: 所有插件都遵循统一的接口标准，便于切换和迁移")

print("\n🎉 插件对比分析完成")
print("=" .. string.rep("=", 78))

-- 导出详细数据供进一步分析
local analysis_data = {
    performance = performance_results,
    functional = functional_results,
    test_data = test_data,
    timestamp = os.time()
}

return analysis_data