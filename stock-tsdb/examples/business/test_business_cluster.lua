-- 业务数据TSDB集群综合测试脚本
-- 测试股票行情、IOT、金融行情、订单、支付、库存、短信下发等业务场景

local optimized_cluster_manager = require "lua.optimized_cluster_manager"

-- 测试配置
local TEST_CONFIG = {
    cluster_name = "business-test-cluster",
    local_node_id = "business_test_node",
    cluster_port = 5555,
    data_path = "./data/testdb_business",
    consul_endpoints = {"http://127.0.0.1:8500"},
    shard_count = 8,
    replica_count = 2
}

-- 业务测试数据定义
local BUSINESS_TEST_DATA = {
    -- 股票行情数据
    stock_quotes = {
        {
            stock_code = "000001",
            market = "SH",
            timestamp = os.time(),
            price = 10.50,
            volume = 1000000,
            amount = 10500000,
            open = 10.45,
            high = 10.80,
            low = 10.40,
            close = 10.75
        },
        {
            stock_code = "000002",
            market = "SZ",
            timestamp = os.time() + 1,
            price = 15.20,
            volume = 500000,
            amount = 7600000,
            open = 15.10,
            high = 15.50,
            low = 15.00,
            close = 15.25
        }
    },
    
    -- IOT传感器数据
    iot_sensors = {
        {
            device_id = "sensor_001",
            metric_type = "temperature",
            timestamp = os.time(),
            value = 25.6,
            unit = "°C",
            location = "room_101",
            battery_level = 85
        },
        {
            device_id = "sensor_002",
            metric_type = "humidity",
            timestamp = os.time(),
            value = 65.2,
            unit = "%",
            location = "room_102",
            battery_level = 92
        }
    },
    
    -- 金融行情数据
    financial_quotes = {
        {
            product_type = "stock",
            symbol = "AAPL",
            market = "NASDAQ",
            timestamp = os.time(),
            price = 182.63,
            volume = 25000000,
            change = 1.25,
            change_percent = 0.69
        },
        {
            product_type = "future",
            symbol = "CLF24",
            market = "CME",
            timestamp = os.time(),
            price = 75.42,
            volume = 150000,
            change = -0.35,
            change_percent = -0.46
        }
    },
    
    -- 订单数据
    orders = {
        {
            order_id = "ORD202412010001",
            user_id = 10001,
            product_id = "PROD001",
            quantity = 10,
            price = 99.99,
            total_amount = 999.90,
            status = "pending",
            create_time = os.time(),
            update_time = os.time()
        },
        {
            order_id = "ORD202412010002",
            user_id = 10002,
            product_id = "PROD002",
            quantity = 5,
            price = 199.99,
            total_amount = 999.95,
            status = "completed",
            create_time = os.time() - 3600,
            update_time = os.time()
        }
    },
    
    -- 支付数据
    payments = {
        {
            payment_id = "PAY202412010001",
            order_id = "ORD202412010001",
            user_id = 10001,
            amount = 999.90,
            currency = "CNY",
            payment_method = "alipay",
            status = "success",
            create_time = os.time(),
            complete_time = os.time() + 5
        },
        {
            payment_id = "PAY202412010002",
            order_id = "ORD202412010002",
            user_id = 10002,
            amount = 999.95,
            currency = "CNY",
            payment_method = "wechat",
            status = "processing",
            create_time = os.time()
        }
    },
    
    -- 库存数据
    inventory = {
        {
            sku_id = "SKU001",
            warehouse_id = "WH001",
            product_name = "iPhone 15",
            quantity = 1000,
            reserved = 50,
            available = 950,
            last_update = os.time()
        },
        {
            sku_id = "SKU002",
            warehouse_id = "WH002",
            product_name = "MacBook Pro",
            quantity = 500,
            reserved = 25,
            available = 475,
            last_update = os.time()
        }
    },
    
    -- 短信下发数据
    sms_deliveries = {
        {
            sms_id = "SMS202412010001",
            phone = "13800138000",
            template_id = "TMP001",
            content = "您的订单ORD202412010001已发货，预计明天送达",
            status = "sent",
            send_time = os.time(),
            retry_count = 0
        },
        {
            sms_id = "SMS202412010002",
            phone = "13900139000",
            template_id = "TMP002",
            content = "您的支付PAY202412010002已成功，金额999.95元",
            status = "pending",
            send_time = os.time()
        }
    }
}

-- 测试股票行情业务
local function test_stock_quote_business(cluster)
    print("\n=== 测试股票行情业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, quote in ipairs(BUSINESS_TEST_DATA.stock_quotes) do
        local key = string.format("stock_quote_%s_%s_%d", quote.stock_code, quote.market, quote.timestamp)
        local value = {
            price = quote.price,
            volume = quote.volume,
            amount = quote.amount,
            open = quote.open,
            high = quote.high,
            low = quote.low,
            close = quote.close,
            timestamp = quote.timestamp
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 股票行情写入成功: %s (价格: %.2f)", key, quote.price))
            success_count = success_count + 1
        else
            print(string.format("❌ 股票行情写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.price == quote.price then
            print(string.format("✅ 股票行情读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 股票行情读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试IOT业务
local function test_iot_business(cluster)
    print("\n=== 测试IOT业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, sensor in ipairs(BUSINESS_TEST_DATA.iot_sensors) do
        local key = string.format("iot_%s_%s_%d", sensor.device_id, sensor.metric_type, sensor.timestamp)
        local value = {
            value = sensor.value,
            unit = sensor.unit,
            location = sensor.location,
            battery_level = sensor.battery_level,
            timestamp = sensor.timestamp
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ IOT数据写入成功: %s (值: %.1f%s)", key, sensor.value, sensor.unit))
            success_count = success_count + 1
        else
            print(string.format("❌ IOT数据写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.value == sensor.value then
            print(string.format("✅ IOT数据读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ IOT数据读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试金融行情业务
local function test_financial_business(cluster)
    print("\n=== 测试金融行情业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, quote in ipairs(BUSINESS_TEST_DATA.financial_quotes) do
        local key = string.format("financial_%s_%s_%s_%d", quote.product_type, quote.symbol, quote.market, quote.timestamp)
        local value = {
            price = quote.price,
            volume = quote.volume,
            change = quote.change,
            change_percent = quote.change_percent,
            timestamp = quote.timestamp
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 金融行情写入成功: %s (价格: %.2f)", key, quote.price))
            success_count = success_count + 1
        else
            print(string.format("❌ 金融行情写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.price == quote.price then
            print(string.format("✅ 金融行情读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 金融行情读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试订单业务
local function test_order_business(cluster)
    print("\n=== 测试订单业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, order in ipairs(BUSINESS_TEST_DATA.orders) do
        local key = string.format("order_%s", order.order_id)
        local value = {
            user_id = order.user_id,
            product_id = order.product_id,
            quantity = order.quantity,
            price = order.price,
            total_amount = order.total_amount,
            status = order.status,
            create_time = order.create_time,
            update_time = order.update_time
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 订单写入成功: %s (金额: %.2f)", key, order.total_amount))
            success_count = success_count + 1
        else
            print(string.format("❌ 订单写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.total_amount == order.total_amount then
            print(string.format("✅ 订单读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 订单读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试支付业务
local function test_payment_business(cluster)
    print("\n=== 测试支付业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, payment in ipairs(BUSINESS_TEST_DATA.payments) do
        local key = string.format("payment_%s", payment.payment_id)
        local value = {
            order_id = payment.order_id,
            user_id = payment.user_id,
            amount = payment.amount,
            currency = payment.currency,
            payment_method = payment.payment_method,
            status = payment.status,
            create_time = payment.create_time,
            complete_time = payment.complete_time
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 支付写入成功: %s (金额: %.2f)", key, payment.amount))
            success_count = success_count + 1
        else
            print(string.format("❌ 支付写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.amount == payment.amount then
            print(string.format("✅ 支付读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 支付读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试库存业务
local function test_inventory_business(cluster)
    print("\n=== 测试库存业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, item in ipairs(BUSINESS_TEST_DATA.inventory) do
        local key = string.format("inventory_%s_%s", item.warehouse_id, item.sku_id)
        local value = {
            product_name = item.product_name,
            quantity = item.quantity,
            reserved = item.reserved,
            available = item.available,
            last_update = item.last_update
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 库存写入成功: %s (可用: %d)", key, item.available))
            success_count = success_count + 1
        else
            print(string.format("❌ 库存写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.available == item.available then
            print(string.format("✅ 库存读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 库存读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 测试短信下发业务
local function test_sms_business(cluster)
    print("\n=== 测试短信下发业务 ===")
    local success_count = 0
    local total_count = 0
    
    for i, sms in ipairs(BUSINESS_TEST_DATA.sms_deliveries) do
        local key = string.format("sms_%s", sms.sms_id)
        local value = {
            phone = sms.phone,
            template_id = sms.template_id,
            content = sms.content,
            status = sms.status,
            send_time = sms.send_time,
            retry_count = sms.retry_count
        }
        
        -- 写入数据
        local success, result = cluster:put_data(key, value)
        if success then
            print(string.format("✅ 短信写入成功: %s (状态: %s)", key, sms.status))
            success_count = success_count + 1
        else
            print(string.format("❌ 短信写入失败: %s - %s", key, result))
        end
        
        -- 读取数据
        success, result = cluster:get_data(key)
        if success and result and result.status == sms.status then
            print(string.format("✅ 短信读取成功: %s", key))
            success_count = success_count + 1
        else
            print(string.format("❌ 短信读取失败: %s", key))
        end
        
        total_count = total_count + 2
    end
    
    return success_count, total_count
end

-- 主测试函数
local function run_business_tests()
    print("🚀 开始业务数据TSDB集群综合测试")
    print("===================================================")
    
    -- 初始化集群
    print("=== 初始化业务测试集群 ===")
    local cluster = optimized_cluster_manager.OptimizedClusterManager:new(TEST_CONFIG)
    
    local success, err = cluster:initialize()
    if not success then
        print("❌ 集群初始化失败:", err)
        return false
    end
    print("✅ 集群初始化成功")
    
    -- 启动集群
    success, err = cluster:start()
    if not success then
        print("❌ 集群启动失败:", err)
        return false
    end
    print("✅ 集群启动成功")
    
    -- 执行各业务测试
    local total_success = 0
    local total_operations = 0
    
    local stock_success, stock_total = test_stock_quote_business(cluster)
    local iot_success, iot_total = test_iot_business(cluster)
    local financial_success, financial_total = test_financial_business(cluster)
    local order_success, order_total = test_order_business(cluster)
    local payment_success, payment_total = test_payment_business(cluster)
    local inventory_success, inventory_total = test_inventory_business(cluster)
    local sms_success, sms_total = test_sms_business(cluster)
    
    total_success = stock_success + iot_success + financial_success + order_success + 
                    payment_success + inventory_success + sms_success
    total_operations = stock_total + iot_total + financial_total + order_total + 
                      payment_total + inventory_total + sms_total
    
    -- 停止集群
    print("\n=== 停止业务测试集群 ===")
    success, err = cluster:stop()
    if not success then
        print("❌ 集群停止失败:", err)
        return false
    end
    print("✅ 集群停止成功")
    
    -- 输出测试结果
    print("\n===================================================")
    print("📊 业务数据TSDB集群测试结果汇总")
    print("===================================================")
    print(string.format("📈 股票行情业务: %d/%d 操作成功", stock_success, stock_total))
    print(string.format("📱 IOT业务: %d/%d 操作成功", iot_success, iot_total))
    print(string.format("💰 金融行情业务: %d/%d 操作成功", financial_success, financial_total))
    print(string.format("🛒 订单业务: %d/%d 操作成功", order_success, order_total))
    print(string.format("💳 支付业务: %d/%d 操作成功", payment_success, payment_total))
    print(string.format("📦 库存业务: %d/%d 操作成功", inventory_success, inventory_total))
    print(string.format("📨 短信下发业务: %d/%d 操作成功", sms_success, sms_total))
    print("---------------------------------------------------")
    print(string.format("🎯 总计: %d/%d 操作成功 (%.1f%%)", 
        total_success, total_operations, (total_success / total_operations) * 100))
    
    if total_success == total_operations then
        print("🎉 所有业务数据测试通过! TSDB集群功能正常")
        return true
    else
        print("⚠️  部分业务数据测试失败，请检查集群配置")
        return false
    end
end

-- 运行测试
if arg and arg[0] and string.find(arg[0], "test_business_cluster") then
    local success = run_business_tests()
    os.exit(success and 0 or 1)
end

return {
    run_business_tests = run_business_tests,
    BUSINESS_TEST_DATA = BUSINESS_TEST_DATA
}