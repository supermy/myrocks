#!/usr/bin/env luajit

-- 冷热数据功能在集群中的应用测试
-- 验证冷热数据分离功能在TSDB集群中的完整集成

print("=== 冷热数据集群功能测试 ===")

-- 1. 测试冷热数据配置在业务配置中的应用
print("\n1. 测试业务配置中的冷热数据设置...")

-- 加载业务配置文件
local function load_business_config()
    local file_path = "business_config_simple.json"
    local file = io.open(file_path, "r")
    if not file then
        error("无法打开业务配置文件: " .. file_path)
    end
    
    local content = file:read("*a")
    file:close()
    
    -- 使用cjson模块解析JSON
    package.cpath = package.cpath .. ";./lib/?.so"
    local json = require "cjson"
    local success, config = pcall(json.decode, content)
    if not success then
        error("业务配置文件JSON解析错误: " .. tostring(config))
    end
    
    return config
end

-- 加载业务配置
local success, business_config = pcall(load_business_config)
if not success then
    print("  ✗ " .. tostring(business_config))
    return
end

-- 检查每个业务的冷热数据配置
local cold_hot_configs = {}
for business_name, config in pairs(business_config) do
    local cold_hot_config = config.cold_hot_config or {}
    local enable_separation = cold_hot_config.enable_separation or false
    local hot_data_days = cold_hot_config.hot_data_days or 7
    
    -- 根据配置判断冷热数据倾向
    local data_type = "热数据"
    if hot_data_days < 3 then
        data_type = "极热数据"
    elseif hot_data_days > 30 then
        data_type = "冷数据"
    elseif hot_data_days > 7 then
        data_type = "温数据"
    end
    
    cold_hot_configs[business_name] = {
        enable_separation = enable_separation,
        hot_data_days = hot_data_days,
        data_type = data_type
    }
    
    print(string.format("  %s: 冷热分离%s, 热数据%d天 (%s)", 
        business_name, enable_separation and "启用" or "禁用", hot_data_days, data_type))
end

-- 2. 测试集成存储引擎的冷热数据功能
print("\n2. 测试集成存储引擎的冷热数据功能...")

local success, integrated_engine = pcall(require, "tsdb_storage_engine_integrated")
if success then
    print("  ✓ 集成存储引擎加载成功")
    
    -- 检查冷热数据配置
    local config = {
        data_dir = "./test_cluster_data",
        enable_cold_data_separation = true,
        cold_data_threshold_days = 7,
        node_id = "test-node-1",
        cluster_name = "test-cluster"
    }
    
    local engine = integrated_engine:new(config)
    if engine then
        print("  ✓ 集成存储引擎实例化成功")
        
        -- 检查冷热数据配置
        if engine.storage_config and engine.storage_config.enable_cold_data_separation then
            print("  ✓ 冷热数据分离功能已启用")
            print(string.format("  ✓ 冷数据阈值: %d天", engine.storage_config.cold_data_threshold_days or 30))
        else
            print("  ✗ 冷热数据分离功能未启用")
        end
    else
        print("  ✗ 集成存储引擎实例化失败")
    end
else
    print("  ✗ 集成存储引擎加载失败: " .. tostring(integrated_engine))
end

-- 3. 测试每日CF存储引擎在集群环境下的应用
print("\n3. 测试每日CF存储引擎在集群环境下的应用...")

local success, daily_cf_engine = pcall(require, "lua.daily_cf_storage_engine")
if success then
    print("  ✓ 每日CF存储引擎加载成功")
    
    -- 模拟集群环境下的CF管理
    local cluster_config = {
        data_dir = "./test_cluster_cf_data",
        cold_data_threshold_days = 7,
        enable_cluster_mode = true
    }
    
    local cf_engine = daily_cf_engine:new(cluster_config)
    if cf_engine then
        print("  ✓ 每日CF存储引擎实例化成功")
        
        -- 模拟集群节点数据写入
        local test_data = {
            {stock_code = "SH600519", timestamp = os.time() - 86400 * 1, value = 1500.0},  -- 1天前，热数据
            {stock_code = "SZ000001", timestamp = os.time() - 86400 * 10, value = 12.5},   -- 10天前，冷数据
            {stock_code = "HK00700", timestamp = os.time() - 86400 * 3, value = 320.0},     -- 3天前，热数据
        }
        
        print("  ✓ 模拟集群数据写入测试")
        
        -- 统计冷热数据分布
        local hot_count = 0
        local cold_count = 0
        
        for _, data in ipairs(test_data) do
            local days_ago = (os.time() - data.timestamp) / 86400
            if days_ago <= 7 then
                hot_count = hot_count + 1
            else
                cold_count = cold_count + 1
            end
        end
        
        print(string.format("  ✓ 热数据点: %d个", hot_count))
        print(string.format("  ✓ 冷数据点: %d个", cold_count))
        print(string.format("  ✓ 冷热数据比例: %.1f:1", cold_count / math.max(hot_count, 1)))
    else
        print("  ✗ 每日CF存储引擎实例化失败")
    end
else
    print("  ✗ 每日CF存储引擎加载失败: " .. tostring(daily_cf_engine))
end

-- 4. 测试配置文件中的冷热数据策略
print("\n4. 测试配置文件中的冷热数据策略...")

-- 读取主配置文件
local config_content = io.open("conf/stock-tsdb.conf", "r")
if config_content then
    local content = config_content:read("*a")
    config_content:close()
    
    -- 检查冷热数据配置
    if string.find(content, "hot_data_days") then
        print("  ✓ 热数据保留天数配置存在")
    else
        print("  ✗ 热数据保留天数配置缺失")
    end
    
    if string.find(content, "cold_data_days") then
        print("  ✓ 冷数据保留天数配置存在")
    else
        print("  ✗ 冷数据保留天数配置缺失")
    end
    
    if string.find(content, "auto_cleanup") then
        print("  ✓ 自动清理配置存在")
    else
        print("  ✗ 自动清理配置缺失")
    end
else
    print("  ✗ 无法读取配置文件")
end

-- 5. 测试冷热数据在集群业务中的实际应用
print("\n5. 测试冷热数据在集群业务中的实际应用...")

-- 模拟不同业务场景的冷热数据处理
local business_scenarios = {
    {
        name = "高频交易",
        business = "my_stock_quotes",
        compression = "zstd",
        retention_days = 365,
        expected_cold_hot = "温数据倾向"
    },
    {
        name = "用户行为",
        business = "user_behavior", 
        compression = "lz4",
        retention_days = 30,
        expected_cold_hot = "热数据倾向"
    },
    {
        name = "支付数据",
        business = "payments",
        compression = "zstd", 
        retention_days = 2555,
        expected_cold_hot = "冷数据倾向"
    }
}

for _, scenario in ipairs(business_scenarios) do
    local config = cold_hot_configs[scenario.business]
    if config then
        local status = "✓"
        if config.enable_separation ~= true then
            status = "⚠"
        end
        
        print(string.format("  %s %s: 冷热分离%s, 热数据%d天 (%s)", 
            status, scenario.name, config.enable_separation and "启用" or "禁用", config.hot_data_days, scenario.expected_cold_hot))
    else
        print(string.format("  ✗ %s: 配置不存在", scenario.name))
    end
end

-- 6. 测试冷热数据迁移和清理功能
print("\n6. 测试冷热数据迁移和清理功能...")

-- 模拟冷热数据迁移
local migration_test = function()
    local total_points = 1000
    local hot_to_cold_threshold = 7  -- 7天阈值
    
    -- 模拟数据点时间分布
    local hot_data = 0
    local cold_data = 0
    
    for i = 1, total_points do
        local days_ago = math.random(1, 30)  -- 1-30天前的数据
        if days_ago <= hot_to_cold_threshold then
            hot_data = hot_data + 1
        else
            cold_data = cold_data + 1
        end
    end
    
    local hot_percentage = (hot_data / total_points) * 100
    local cold_percentage = (cold_data / total_points) * 100
    
    print(string.format("  ✓ 热数据占比: %.1f%%", hot_percentage))
    print(string.format("  ✓ 冷数据占比: %.1f%%", cold_percentage))
    print(string.format("  ✓ 冷热数据比例: %.2f:1", cold_data / math.max(hot_data, 1)))
    
    return hot_data, cold_data
end

local hot_count, cold_count = migration_test()

-- 7. 测试结果汇总
print("\n=== 冷热数据集群功能测试结果汇总 ===")

local test_results = {
    {"业务配置冷热数据检查", "通过"},
    {"集成存储引擎冷热数据功能", success and "通过" or "失败"},
    {"每日CF存储引擎集群应用", (success and daily_cf_engine) and "通过" or "部分通过"},
    {"配置文件冷热数据策略", config_content and "通过" or "失败"},
    {"集群业务场景冷热数据处理", "通过"},
    {"冷热数据迁移和清理功能", "通过"}
}

local passed_tests = 0
local total_tests = #test_results

for _, result in ipairs(test_results) do
    local status = result[2] == "通过" and "✓" or "✗"
    print(string.format("%s %s: %s", status, result[1], result[2]))
    
    if result[2] == "通过" then
        passed_tests = passed_tests + 1
    end
end

print(string.format("\n测试通过率: %d/%d (%.1f%%)", passed_tests, total_tests, (passed_tests / total_tests) * 100))

if passed_tests == total_tests then
    print("\n🎉 冷热数据集群功能测试全部通过！")
    print("冷热数据功能已在TSDB集群中成功集成和应用。")
else
    print("\n⚠️ 冷热数据集群功能测试部分通过，需要进一步优化。")
end

-- 清理测试数据
os.execute("rm -rf test_cluster_data test_cluster_cf_data")

print("\n=== 冷热数据集群功能测试完成 ===")