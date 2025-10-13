-- 插件综合测试与对比分析脚本

-- 加载插件管理器
local plugin_module = require "lua.rowkey_value_plugin"

-- 获取所有可用插件
local plugin_manager = plugin_module.default_manager
local plugins_list = plugin_manager:list_plugins()

-- 提取插件名称列表
local plugins = {}
for i, plugin_info in ipairs(plugins_list) do
    table.insert(plugins, plugin_info.name)
end

print("===================================================")
print("📊 插件综合测试与对比分析")
print("===================================================")
print()

-- 测试数据定义
local test_data = {
    stock_quote = {
        stock_code = "000001",
        timestamp = 1760227200,
        market = "SH",
        data = {open = 10.5, high = 11.2, low = 10.1, close = 10.8, volume = 1000000, amount = 10800000}
    },
    financial_quote = {
        product_type = "stock",
        market = "SH",
        code = "000001",
        timestamp = 1760227200,
        data = {price = 10.8, volume = 1000000, change = 0.3, change_rate = 0.028}
    },
    order_management = {
        user_id = "10001",
        order_id = "ORD202412010001",
        timestamp = 1760227200,
        priority = "normal",
        data = {amount = 299.99, quantity = 2, status = "pending", product_id = "PROD001"}
    },
    payment_system = {
        merchant_id = "20001",
        transaction_id = "TXN202412010001",
        timestamp = 1760263200,
        payment_method = "alipay",
        data = {amount = 299.99, currency = "CNY", status = "success", risk_score = 0}
    },
    inventory_management = {
        warehouse_id = "30001",
        sku_id = "SKU001",
        timestamp = 1760227200,
        operation = "inbound",
        data = {quantity = 100, location = "A-01-01", operator = "user001"}
    },
    sms_delivery = {
        channel = "aliyun",
        template_id = "TMP001",
        timestamp = 1760263200,
        type = "verification",
        data = {phone = "13800138000", content = "您的验证码是123456", status = "sent"}
    },
    iot_data = {
        device_id = "DEV001",
        sensor_type = "temperature",
        timestamp = 1760227200,
        data = {value = 25.5, unit = "celsius", battery = 85}
    }
}

-- 性能测试函数
local function performance_test(plugin, test_name, test_args)
    local start_time = os.clock()
    local iterations = 1000
    
    for i = 1, iterations do
        local rowkey, qualifier = plugin:encode_rowkey(unpack(test_args))
        local value = plugin:encode_value(test_data[test_name].data)
        
        local decoded_rowkey = plugin:decode_rowkey(rowkey)
        local decoded_value = plugin:decode_value(value)
    end
    
    local end_time = os.clock()
    local total_time = (end_time - start_time) * 1000  -- 转换为毫秒
    local avg_time = total_time / iterations
    
    return total_time, avg_time
end

-- 存储效率分析函数
local function storage_efficiency_analysis(plugin, test_name, test_args)
    local rowkey, qualifier = plugin:encode_rowkey(unpack(test_args))
    local value = plugin:encode_value(test_data[test_name].data)
    
    local rowkey_size = #rowkey
    local value_size = #value
    local total_size = rowkey_size + value_size
    
    -- 计算压缩率（假设原始数据大小）
    local original_size_estimate = 200  -- 估计原始数据大小
    local compression_ratio = (1 - total_size / original_size_estimate) * 100
    
    return rowkey_size, value_size, total_size, compression_ratio
end

-- 功能完整性检查函数
local function functionality_check(plugin)
    local checks = {
        encode_rowkey = true,
        decode_rowkey = true,
        encode_value = true,
        decode_value = true,
        get_info = true
    }
    
    for method, required in pairs(checks) do
        if required and not plugin[method] then
            checks[method] = false
        end
    end
    
    return checks
end

-- 主测试函数
local function run_comprehensive_analysis()
    local results = {}
    
    print("🔍 插件列表与基本信息:")
    print("-" .. string.rep("-", 80))
    
    for i, plugin_name in ipairs(plugins) do
        local plugin = plugin_manager:get_plugin(plugin_name)
        local info = plugin:get_info()
        
        print(string.format("%-25s | %-8s | %s", 
            plugin_name, info.version, info.description))
        
        results[plugin_name] = {
            info = info,
            performance = {},
            storage = {},
            functionality = {}
        }
    end
    
    print()
    print("⚡ 性能测试结果 (1000次迭代):")
    print("-" .. string.rep("-", 80))
    
    -- 性能测试
    for plugin_name, _ in pairs(results) do
        local plugin = plugin_manager:get_plugin(plugin_name)
        local test_args = {}
        
        -- 根据插件类型设置测试参数
        if plugin_name == "stock_quote" then
            test_args = {"000001", 1760227200, "SH"}
        elseif plugin_name == "financial_quote" then
            test_args = {"stock", "SH", "000001", 1760227200}
        elseif plugin_name == "order_management" then
            test_args = {"10001", "ORD202412010001", 1760227200, "normal"}
        elseif plugin_name == "payment_system" then
            test_args = {"20001", "TXN202412010001", 1760263200, "alipay"}
        elseif plugin_name == "inventory_management" then
            test_args = {"30001", "SKU001", 1760227200, "inbound"}
        elseif plugin_name == "sms_delivery" then
            test_args = {"aliyun", "TMP001", 1760263200, "verification"}
        elseif plugin_name == "iot_data" then
            test_args = {"DEV001", "temperature", 1760227200}
        end
        
        local total_time, avg_time = performance_test(plugin, plugin_name, test_args)
        results[plugin_name].performance = {
            total_time = total_time,
            avg_time = avg_time
        }
        
        print(string.format("%-25s | %8.2f ms | %6.3f ms/次", 
            plugin_name, total_time, avg_time))
    end
    
    print()
    print("💾 存储效率分析:")
    print("-" .. string.rep("-", 80))
    
    -- 存储效率分析
    for plugin_name, _ in pairs(results) do
        local plugin = plugin_manager:get_plugin(plugin_name)
        local test_args = {}
        
        -- 根据插件类型设置测试参数
        if plugin_name == "stock_quote" then
            test_args = {"000001", 1760227200, "SH"}
        elseif plugin_name == "financial_quote" then
            test_args = {"stock", "SH", "000001", 1760227200}
        elseif plugin_name == "order_management" then
            test_args = {"10001", "ORD202412010001", 1760227200, "normal"}
        elseif plugin_name == "payment_system" then
            test_args = {"20001", "TXN202412010001", 1760263200, "alipay"}
        elseif plugin_name == "inventory_management" then
            test_args = {"30001", "SKU001", 1760227200, "inbound"}
        elseif plugin_name == "sms_delivery" then
            test_args = {"aliyun", "TMP001", 1760263200, "verification"}
        elseif plugin_name == "iot_data" then
            test_args = {"DEV001", "temperature", 1760227200}
        end
        
        local rowkey_size, value_size, total_size, compression_ratio = 
            storage_efficiency_analysis(plugin, plugin_name, test_args)
        
        results[plugin_name].storage = {
            rowkey_size = rowkey_size,
            value_size = value_size,
            total_size = total_size,
            compression_ratio = compression_ratio
        }
        
        print(string.format("%-25s | RK:%3d B | V:%3d B | 总计:%3d B | 压缩率:%5.1f%%", 
            plugin_name, rowkey_size, value_size, total_size, compression_ratio))
    end
    
    print()
    print("🔧 功能完整性检查:")
    print("-" .. string.rep("-", 80))
    
    -- 功能完整性检查
    for plugin_name, _ in pairs(results) do
        local plugin = plugin_manager:get_plugin(plugin_name)
        local checks = functionality_check(plugin)
        
        results[plugin_name].functionality = checks
        
        local status = "✅ 完整"
        for method, passed in pairs(checks) do
            if not passed then
                status = "❌ 缺失"
                break
            end
        end
        
        print(string.format("%-25s | %s", plugin_name, status))
    end
    
    print()
    print("📈 综合对比分析:")
    print("-" .. string.rep("-", 80))
    
    -- 综合排名
    local ranked_plugins = {}
    for plugin_name, result in pairs(results) do
        local score = 0
        
        -- 性能得分（越低越好）
        score = score + (100 - result.performance.avg_time * 10)
        
        -- 存储效率得分（越高越好）
        score = score + result.storage.compression_ratio
        
        -- 功能完整性得分
        local func_score = 0
        for _, passed in pairs(result.functionality) do
            if passed then func_score = func_score + 20 end
        end
        score = score + func_score
        
        table.insert(ranked_plugins, {
            name = plugin_name,
            score = score,
            performance = result.performance.avg_time,
            storage = result.storage.total_size,
            compression = result.storage.compression_ratio
        })
    end
    
    -- 按得分排序
    table.sort(ranked_plugins, function(a, b) return a.score > b.score end)
    
    for i, plugin in ipairs(ranked_plugins) do
        local rank_icon = ""
        if i == 1 then rank_icon = "🥇"
        elseif i == 2 then rank_icon = "🥈"
        elseif i == 3 then rank_icon = "🥉"
        else rank_icon = "  " .. i end
        
        print(string.format("%s %-22s | 总分:%5.1f | 性能:%5.3f ms | 存储:%3d B | 压缩率:%5.1f%%", 
            rank_icon, plugin.name, plugin.score, plugin.performance, plugin.storage, plugin.compression))
    end
    
    print()
    print("💡 优化建议:")
    print("-" .. string.rep("-", 80))
    
    -- 提供优化建议
    for i, plugin in ipairs(ranked_plugins) do
        local suggestions = {}
        
        if plugin.performance > 0.1 then
            table.insert(suggestions, "性能优化")
        end
        
        if plugin.compression < 50 then
            table.insert(suggestions, "存储压缩")
        end
        
        if plugin.storage > 150 then
            table.insert(suggestions, "编码精简")
        end
        
        if #suggestions > 0 then
            print(string.format("%-25s: %s", plugin.name, table.concat(suggestions, ", ")))
        else
            print(string.format("%-25s: ✅ 表现良好", plugin.name))
        end
    end
    
    print()
    print("===================================================")
    print("🎯 测试完成 - 共分析 " .. #plugins .. " 个插件")
    print("===================================================")
    
    return results
end

-- 运行测试
local results = run_comprehensive_analysis()