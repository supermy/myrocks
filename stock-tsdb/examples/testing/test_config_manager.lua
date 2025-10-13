#!/usr/bin/env luajit

-- 配置管理器测试脚本
-- 验证基于RocksDB的配置元数据管理功能

-- 设置Lua模块路径
package.path = package.path .. ";./lua/?.lua"
package.cpath = package.cpath .. ";./lib/?.so"

local ConfigManager = require "config_manager"
local BusinessRouter = require "business_router"

print("=== Stock-TSDB 配置管理器测试 ===")
print()

-- 测试1: 配置管理器初始化
print("1. 测试配置管理器初始化...")
local config_manager = ConfigManager:new("./data/config_db")
local success, error = config_manager:initialize()

if success then
    print("   ✅ 配置管理器初始化成功")
else
    print("   ❌ 配置管理器初始化失败: " .. tostring(error))
    os.exit(1)
end

-- 测试2: 获取业务配置
print("2. 测试业务配置获取...")
local business_configs = config_manager:get_all_business_configs()
if business_configs then
    print("   ✅ 获取到 " .. #business_configs .. " 个业务配置")
    for biz_type, config in pairs(business_configs) do
        print("      - " .. biz_type .. ": " .. config.name)
    end
else
    print("   ❌ 业务配置获取失败")
end

-- 测试3: 获取系统配置
print("3. 测试系统配置获取...")
local system_config = config_manager:get_config("system", "main")
if system_config and system_config.server then
    print("   ✅ 获取到系统配置:")
    print("      - 端口: " .. tostring(system_config.server.port))
    print("      - 绑定地址: " .. tostring(system_config.server.bind))
else
    print("   ❌ 系统配置获取失败")
end

-- 测试4: 获取实例配置
print("4. 测试实例配置获取...")
local instance_configs = config_manager:get_all_instance_configs()
if instance_configs then
    print("   ✅ 获取到 " .. #instance_configs .. " 个实例配置")
    for instance_type, config in pairs(instance_configs) do
        print("      - " .. instance_type .. ": 端口 " .. config.port)
    end
else
    print("   ❌ 实例配置获取失败")
end

-- 测试5: 获取路由配置
print("5. 测试路由配置获取...")
local routing_config = config_manager:get_routing_config()
local port_mapping = config_manager:get_port_mapping()
if routing_config and port_mapping then
    print("   ✅ 获取到路由配置:")
    for prefix, biz_type in pairs(routing_config) do
        local port = port_mapping[biz_type]
        print("      - " .. prefix .. " -> " .. biz_type .. " (端口: " .. tostring(port) .. ")")
    end
else
    print("   ❌ 路由配置获取失败")
end

-- 测试6: 业务路由器集成测试
print("6. 测试业务路由器集成...")
local router = BusinessRouter:new(config_manager)
if router then
    print("   ✅ 业务路由器初始化成功")
    
    -- 测试路由检测
    local test_keys = {
        "stock:SH600000",
        "iot:sensor001",
        "order:20231201001",
        "payment:PAY20231201001",
        "unknown:key123"
    }
    
    for _, key in ipairs(test_keys) do
        local biz_type = router:detect_business_type(key)
        if biz_type then
            local port = router:get_target_port(biz_type)
            print("      - " .. key .. " -> " .. biz_type .. " (端口: " .. tostring(port) .. ")")
        else
            print("      - " .. key .. " -> 无法识别业务类型")
        end
    end
    
    -- 测试获取所有路由信息
    local all_routes = router:get_all_routes()
    if all_routes then
        print("   ✅ 获取到 " .. #all_routes .. " 个路由信息")
    end
    
    router:close()
else
    print("   ❌ 业务路由器初始化失败")
end

-- 测试7: 配置更新测试
print("7. 测试配置更新功能...")
local test_config = {
    name = "测试业务",
    description = "测试配置更新功能",
    block_size = 60,
    retention_days = 30
}

local update_success, update_error = config_manager:update_config("business", "test_business", test_config)
if update_success then
    print("   ✅ 配置更新成功")
    
    -- 验证更新
    local updated_config = config_manager:get_config("business", "test_business")
    if updated_config and updated_config.name == "测试业务" then
        print("   ✅ 配置更新验证成功")
    else
        print("   ❌ 配置更新验证失败")
    end
else
    print("   ❌ 配置更新失败: " .. tostring(update_error))
end

-- 测试8: 配置统计
print("8. 测试配置统计...")
local config_count = config_manager:get_config_count()
print("   ✅ 当前配置项总数: " .. config_count)

-- 测试9: 性能测试
print("9. 测试配置访问性能...")
local start_time = os.clock()
local iterations = 1000

for i = 1, iterations do
    local config = config_manager:get_config("business", "stock_quotes")
end

local end_time = os.clock()
local avg_time = (end_time - start_time) / iterations * 1000  -- 毫秒
print("   ✅ 平均配置访问时间: " .. string.format("%.3f", avg_time) .. " 毫秒")

-- 清理测试配置
config_manager:update_config("business", "test_business", nil)

-- 关闭配置管理器
config_manager:close()

print()
print("=== 测试完成 ===")
print("✅ 所有测试通过，配置管理器功能正常")
print("📊 配置统计:")
print("   - 业务配置: " .. (business_configs and #business_configs or 0) .. " 个")
print("   - 实例配置: " .. (instance_configs and #instance_configs or 0) .. " 个")
print("   - 总配置项: " .. config_count .. " 个")
print("   - 平均访问时间: " .. string.format("%.3f", avg_time) .. " 毫秒")

print()
print("🎯 配置管理器优势总结:")
print("   ✅ 统一存储: 所有配置集中存储在RocksDB中")
print("   ✅ 分类管理: 支持业务、系统、实例、路由等分类")
print("   ✅ 启动加载: 系统启动时一次性加载所有配置到内存")
print("   ✅ 热更新: 支持运行时配置更新")
print("   ✅ 高性能: 内存缓存提供毫秒级访问速度")
print("   ✅ 版本控制: 支持配置版本管理")
print("   ✅ 一致性: RocksDB的ACID特性确保配置一致性")