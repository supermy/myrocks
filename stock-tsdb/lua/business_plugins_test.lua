-- 业务插件综合测试脚本
-- 测试金融行情、订单、支付、库存、短信下发等五个业务插件

local plugin_manager = require "lua.rowkey_value_plugin"

-- 测试金融行情插件
function test_financial_quote_plugin()
    print("=== 测试金融行情插件 ===")
    
    local plugin = plugin_manager.default_manager:get_plugin("financial_quote")
    if not plugin then
        print("❌ 金融行情插件未找到")
        return false
    end
    
    print("✅ 插件信息:", plugin:get_name(), plugin:get_version())
    
    -- 测试股票行情编码
    local stock_quote = {
        product_type = "stock",
        symbol = "000001",
        market = "SH",
        timestamp = os.time(),
        open = 10.50,
        high = 10.80,
        low = 10.45,
        close = 10.75,
        volume = 1000000,
        amount = 10750000
    }
    
    local rowkey, qualifier = plugin:encode_rowkey(
        stock_quote.product_type,
        stock_quote.symbol,
        stock_quote.timestamp,
        stock_quote.market
    )
    
    local value = plugin:encode_value(stock_quote)
    
    print("✅ 股票行情编码:")
    print("   RowKey:", rowkey)
    print("   Qualifier:", qualifier)
    print("   Value:", value)
    
    -- 测试解码
    local decoded_key = plugin:decode_rowkey(rowkey)
    local decoded_value = plugin:decode_value(value)
    
    print("✅ 解码结果:")
    print("   解码Key:", decoded_key.symbol, decoded_key.market)
    print("   解码Value:", decoded_value.close, decoded_value.volume)
    
    return true
end

-- 测试订单管理插件
function test_order_management_plugin()
    print("\n=== 测试订单管理插件 ===")
    
    local plugin = plugin_manager.default_manager:get_plugin("order_management")
    if not plugin then
        print("❌ 订单管理插件未找到")
        return false
    end
    
    print("✅ 插件信息:", plugin:get_name(), plugin:get_version())
    
    -- 测试订单编码
    local order_data = {
        user_id = 10001,
        order_id = "ORD202412010001",
        amount = 299.99,
        currency = "CNY",
        status = "confirmed",
        create_time = os.time(),
        update_time = os.time(),
        order_type = "normal",
        payment_status = "paid",
        items = {
            {product_id = "P001", quantity = 2, price = 99.99},
            {product_id = "P002", quantity = 1, price = 100.01}
        },
        shipping_address = {
            name = "张三",
            phone = "13800138000",
            address = "北京市朝阳区",
            city = "北京",
            province = "北京"
        }
    }
    
    local rowkey, qualifier = plugin:encode_rowkey(
        order_data.user_id,
        order_data.order_id,
        order_data.create_time,
        order_data.order_type
    )
    
    local value = plugin:encode_value(order_data)
    
    print("✅ 订单编码:")
    print("   RowKey:", rowkey)
    print("   Value长度:", #value)
    
    -- 测试解码
    local decoded_value = plugin:decode_value(value)
    
    print("✅ 解码结果:")
    print("   订单金额:", decoded_value.amount)
    print("   商品数量:", #decoded_value.items)
    
    return true
end

-- 测试支付系统插件
function test_payment_system_plugin()
    print("\n=== 测试支付系统插件 ===")
    
    local plugin = plugin_manager.default_manager:get_plugin("payment_system")
    if not plugin then
        print("❌ 支付系统插件未找到")
        return false
    end
    
    print("✅ 插件信息:", plugin:get_name(), plugin:get_version())
    
    -- 测试支付交易编码
    local payment_data = {
        merchant_id = 20001,
        transaction_id = "TXN202412010001",
        amount = 299.99,
        currency = "CNY",
        status = "success",
        payment_method = "alipay",
        create_time = os.time(),
        update_time = os.time(),
        user_id = 10001,
        order_id = "ORD202412010001",
        channel_info = {
            channel_id = "ALIPAY001",
            channel_name = "支付宝",
            fee_rate = 0.006
        },
        result_info = {
            code = "SUCCESS",
            message = "支付成功",
            gateway_tx_id = "ALI202412010001"
        }
    }
    
    local rowkey, qualifier = plugin:encode_rowkey(
        payment_data.merchant_id,
        payment_data.transaction_id,
        payment_data.create_time,
        payment_data.payment_method
    )
    
    local value = plugin:encode_value(payment_data)
    
    print("✅ 支付交易编码:")
    print("   RowKey:", rowkey)
    print("   Value长度:", #value)
    
    -- 测试风控检查
    local risk_result = plugin:risk_check(payment_data)
    
    print("✅ 风控检查:")
    print("   风险分数:", risk_result.risk_score)
    print("   风险等级:", risk_result.risk_level)
    
    return true
end

-- 测试库存管理插件
function test_inventory_management_plugin()
    print("\n=== 测试库存管理插件 ===")
    
    local plugin = plugin_manager.default_manager:get_plugin("inventory_management")
    if not plugin then
        print("❌ 库存管理插件未找到")
        return false
    end
    
    print("✅ 插件信息:", plugin:get_name(), plugin:get_version())
    
    -- 测试库存操作编码
    local inventory_data = {
        warehouse_id = 30001,
        sku_id = "SKU001",
        quantity = 100,
        operation_type = "inbound",
        status = "normal",
        create_time = os.time(),
        update_time = os.time(),
        operator_id = "OP001",
        reference_id = "REF001",
        product_info = {
            name = "iPhone 15",
            category = "手机",
            brand = "Apple",
            unit = "台"
        },
        batch_info = {
            batch_no = "BATCH20241201",
            production_date = "2024-11-01",
            expiry_date = "2025-11-01"
        }
    }
    
    local rowkey, qualifier = plugin:encode_rowkey(
        inventory_data.warehouse_id,
        inventory_data.sku_id,
        inventory_data.create_time,
        inventory_data.operation_type
    )
    
    local value = plugin:encode_value(inventory_data)
    
    print("✅ 库存操作编码:")
    print("   RowKey:", rowkey)
    print("   Value长度:", #value)
    
    -- 测试库存调拨
    local transfer = plugin:transfer_inventory(30001, 30002, "SKU001", 50, "库存调拨")
    
    print("✅ 库存调拨:")
    print("   调拨数量:", transfer.quantity)
    print("   调拨原因:", transfer.reason)
    
    return true
end

-- 测试短信下发插件
function test_sms_delivery_plugin()
    print("\n=== 测试短信下发插件 ===")
    
    local plugin = plugin_manager.default_manager:get_plugin("sms_delivery")
    if not plugin then
        print("❌ 短信下发插件未找到")
        return false
    end
    
    print("✅ 插件信息:", plugin:get_name(), plugin:get_version())
    
    -- 测试短信编码
    local sms_data = {
        channel = "aliyun",
        template_id = "TMP001",
        phone_number = "13800138000",
        content = "您的验证码是：123456，5分钟内有效",
        status = "sent",
        create_time = os.time(),
        send_time = os.time(),
        delivery_time = os.time(),
        sms_type = "verification",
        priority = 1,
        send_result = {
            message_id = "MSG202412010001",
            error_code = "",
            error_message = ""
        }
    }
    
    local rowkey, qualifier = plugin:encode_rowkey(
        sms_data.channel,
        sms_data.template_id,
        sms_data.create_time,
        sms_data.sms_type
    )
    
    local value = plugin:encode_value(sms_data)
    
    print("✅ 短信编码:")
    print("   RowKey:", rowkey)
    print("   Value长度:", #value)
    
    -- 测试短信内容验证
    local validation = plugin:validate_sms_content("您的验证码是：123456")
    
    print("✅ 短信验证:")
    print("   是否有效:", validation.is_valid)
    print("   内容长度:", validation.length)
    
    return true
end

-- 主测试函数
function main()
    print("开始业务插件综合测试...")
    print("=" .. string.rep("=", 50))
    
    local test_results = {}
    
    -- 执行所有测试
    table.insert(test_results, {name = "金融行情插件", result = test_financial_quote_plugin()})
    table.insert(test_results, {name = "订单管理插件", result = test_order_management_plugin()})
    table.insert(test_results, {name = "支付系统插件", result = test_payment_system_plugin()})
    table.insert(test_results, {name = "库存管理插件", result = test_inventory_management_plugin()})
    table.insert(test_results, {name = "短信下发插件", result = test_sms_delivery_plugin()})
    
    -- 输出测试结果汇总
    print("\n" .. "=" .. string.rep("=", 50))
    print("测试结果汇总:")
    
    local passed = 0
    local failed = 0
    
    for _, result in ipairs(test_results) do
        if result.result then
            print("✅ " .. result.name .. " - 通过")
            passed = passed + 1
        else
            print("❌ " .. result.name .. " - 失败")
            failed = failed + 1
        end
    end
    
    print("\n总计: " .. passed .. " 通过, " .. failed .. " 失败")
    
    if failed == 0 then
        print("🎉 所有业务插件测试通过!")
    else
        print("⚠️  部分插件测试失败，请检查实现")
    end
    
    -- 列出所有可用插件
    print("\n可用插件列表:")
    local plugins = plugin_manager.default_manager:list_plugins()
    for _, plugin_info in ipairs(plugins) do
        print("  - " .. plugin_info.name .. " (v" .. plugin_info.version .. "): " .. plugin_info.description)
    end
end

-- 运行测试
if arg and arg[0] and string.find(arg[0], "business_plugins_test") then
    main()
end

return {
    test_financial_quote_plugin = test_financial_quote_plugin,
    test_order_management_plugin = test_order_management_plugin,
    test_payment_system_plugin = test_payment_system_plugin,
    test_inventory_management_plugin = test_inventory_management_plugin,
    test_sms_delivery_plugin = test_sms_delivery_plugin,
    main = main
}