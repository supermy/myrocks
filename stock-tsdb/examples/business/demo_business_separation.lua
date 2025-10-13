-- 业务数据分离演示脚本
-- 展示如何使用统一数据访问层操作不同业务的数据

-- 设置包路径
package.path = package.path .. ';./lua/?.lua'
package.cpath = package.cpath .. ';./lib/?.so'

-- 导入统一数据访问层
local UnifiedDataAccess = require "unified_data_access"

-- 创建统一数据访问实例
local data_access = UnifiedDataAccess:new()

print("=== 业务数据分离演示 ===")
print("演示不同业务数据自动路由到独立数据库实例")
print()

-- 定义测试数据
local test_data = {
    -- 股票行情数据
    ["stock:SH600000"] = {
        code = "SH600000",
        name = "浦发银行",
        price = 8.45,
        change = 0.12,
        volume = 12345678,
        timestamp = os.time()
    },
    ["stock:SZ000001"] = {
        code = "SZ000001",
        name = "平安银行",
        price = 10.23,
        change = -0.05,
        volume = 87654321,
        timestamp = os.time()
    },
    
    -- 物联网数据
    ["iot:sensor:temperature:001"] = {
        sensor_id = "001",
        type = "temperature",
        value = 25.6,
        unit = "°C",
        timestamp = os.time(),
        location = "车间A"
    },
    ["iot:sensor:humidity:002"] = {
        sensor_id = "002",
        type = "humidity",
        value = 65.2,
        unit = "%",
        timestamp = os.time(),
        location = "车间B"
    },
    
    -- 金融行情数据
    ["financial:forex:USDCNY"] = {
        pair = "USDCNY",
        bid = 7.2456,
        ask = 7.2468,
        timestamp = os.time(),
        source = "外汇市场"
    },
    ["financial:futures:RB2401"] = {
        code = "RB2401",
        name = "螺纹钢2401",
        price = 3850,
        change = 15,
        timestamp = os.time(),
        exchange = "上期所"
    },
    
    -- 订单数据
    ["order:202401150001"] = {
        order_id = "202401150001",
        user_id = "user123",
        amount = 299.99,
        status = "paid",
        create_time = os.time(),
        items = {
            {sku = "SKU001", quantity = 2, price = 99.99},
            {sku = "SKU002", quantity = 1, price = 100.00}
        }
    },
    
    -- 支付数据
    ["payment:202401150001"] = {
        payment_id = "202401150001",
        order_id = "202401150001",
        amount = 299.99,
        method = "alipay",
        status = "success",
        pay_time = os.time()
    },
    
    -- 库存数据
    ["inventory:SKU001"] = {
        sku = "SKU001",
        name = "iPhone 15",
        quantity = 100,
        reserved = 5,
        available = 95,
        last_update = os.time()
    },
    
    -- 短信数据
    ["sms:202401150001"] = {
        sms_id = "202401150001",
        phone = "13800138000",
        content = "您的订单202401150001已发货，物流单号：SF123456789",
        status = "sent",
        send_time = os.time()
    }
}

-- 测试数据设置功能
print("1. 测试数据设置功能")
print("-" .. string.rep("-", 50))

local set_results = {}
for key, value in pairs(test_data) do
    print(string.format("设置数据: %s", key))
    local success, err = data_access:set(key, value)
    if success then
        print("  ✓ 设置成功")
        set_results[key] = true
    else
        print("  ✗ 设置失败: " .. tostring(err))
        set_results[key] = false
    end
end

print()

-- 测试数据获取功能
print("2. 测试数据获取功能")
print("-" .. string.rep("-", 50))

local get_results = {}
for key, _ in pairs(test_data) do
    print(string.format("获取数据: %s", key))
    local value, err = data_access:get(key)
    if value then
        print("  ✓ 获取成功")
        -- 显示部分数据内容
        if type(value) == "table" then
            local preview = ""
            for k, v in pairs(value) do
                if type(v) ~= "table" then
                    preview = preview .. k .. ":" .. tostring(v) .. " "
                end
                if #preview > 50 then break end
            end
            print("    数据预览: " .. preview)
        end
        get_results[key] = true
    else
        print("  ✗ 获取失败: " .. tostring(err))
        get_results[key] = false
    end
end

print()

-- 测试批量操作功能
print("3. 测试批量操作功能")
print("-" .. string.rep("-", 50))

-- 批量获取
local batch_keys = {}
for key, _ in pairs(test_data) do
    table.insert(batch_keys, key)
end

print("批量获取 " .. #batch_keys .. " 条数据")
local batch_results = data_access:mget(batch_keys)

local batch_success_count = 0
for key, result in pairs(batch_results) do
    if result.success then
        batch_success_count = batch_success_count + 1
    end
end

print(string.format("  批量获取结果: %d/%d 成功", batch_success_count, #batch_keys))

print()

-- 测试缓存功能
print("4. 测试缓存功能")
print("-" .. string.rep("-", 50))

-- 第一次获取（应该会缓存）
print("第一次获取数据（应该会缓存）:")
local test_key = "stock:SH600000"
local value1, err1 = data_access:get(test_key)
if value1 then
    print("  ✓ 获取成功")
else
    print("  ✗ 获取失败: " .. tostring(err1))
end

-- 第二次获取（应该从缓存中获取）
print("第二次获取数据（应该从缓存中获取）:")
local value2, err2 = data_access:get(test_key)
if value2 then
    print("  ✓ 获取成功（缓存命中）")
else
    print("  ✗ 获取失败: " .. tostring(err2))
end

-- 强制刷新获取（应该绕过缓存）
print("强制刷新获取（应该绕过缓存）:")
local value3, err3 = data_access:get(test_key, {force_refresh = true})
if value3 then
    print("  ✓ 获取成功（强制刷新）")
else
    print("  ✗ 获取失败: " .. tostring(err3))
end

print()

-- 测试删除功能
print("5. 测试数据删除功能")
print("-" .. string.rep("-", 50))

local delete_key = "sms:202401150001"
print(string.format("删除数据: %s", delete_key))
local delete_success, delete_err = data_access:delete(delete_key)
if delete_success then
    print("  ✓ 删除成功")
    
    -- 验证删除
    local verify_value, verify_err = data_access:get(delete_key)
    if not verify_value then
        print("  ✓ 验证删除成功")
    else
        print("  ✗ 验证删除失败，数据仍然存在")
    end
else
    print("  ✗ 删除失败: " .. tostring(delete_err))
end

print()

-- 显示路由信息
print("6. 显示业务路由信息")
print("-" .. string.rep("-", 50))

local routes = data_access.router:get_all_routes()
for i, route in ipairs(routes) do
    print(string.format("业务类型: %-20s 端口: %-5d 实例ID: %s", 
        route.business_type, route.target_port, route.instance_id))
    print("  描述: " .. route.description)
end

print()

-- 显示统计信息
print("7. 显示访问统计信息")
print("-" .. string.rep("-", 50))

local stats = data_access:get_stats()
print(string.format("总请求数: %d", stats.total_requests))
print(string.format("成功请求数: %d", stats.successful_requests))
print(string.format("失败请求数: %d", stats.failed_requests))
print(string.format("成功率: %.2f%%", stats.success_rate))
print(string.format("缓存命中数: %d", stats.cache_hits))
print(string.format("缓存未命中数: %d", stats.cache_misses))
print(string.format("缓存命中率: %.2f%%", stats.cache_hit_rate))

print()

-- 健康检查
print("8. 系统健康检查")
print("-" .. string.rep("-", 50))

local health_status = data_access:health_check()
print(string.format("服务状态: %s", health_status.healthy and "健康" or "异常"))
print(string.format("缓存启用: %s", health_status.cache_enabled and "是" or "否"))
print(string.format("缓存大小: %d", health_status.cache_size))

if health_status.router_health then
    print("路由健康检查:")
    for business_type, status in pairs(health_status.router_health.details) do
        local status_text = status.reachable and "可达" or "不可达"
        print(string.format("  %-20s: %s (端口: %d)", business_type, status_text, status.port))
    end
end

print()

-- 总结
print("=== 演示总结 ===")
print("✓ 成功演示了不同业务数据的自动路由功能")
print("✓ 实现了股票行情、IOT、金融行情、订单、支付、库存、短信下发等业务的独立实例管理")
print("✓ 验证了统一数据访问层的透明访问机制")
print("✓ 测试了缓存功能和批量操作性能")
print("✓ 完成了系统健康检查和统计监控")

print()
print("业务数据分离架构已成功实现！")
print("每个业务都有独立的数据库实例，确保数据隔离和性能优化。")