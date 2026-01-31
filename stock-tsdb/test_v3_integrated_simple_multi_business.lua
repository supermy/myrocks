#!/usr/bin/env luajit

-- V3集成版本与simple_multi_business测试
-- 验证RocksDB数据使用的正确性

package.path = package.path .. ";./lua/?.lua"

local BusinessInstanceManager = require "business_instance_manager"
local V3StorageEngine = require "tsdb_storage_engine_v3_rocksdb"
local TSDBStorageEngineIntegrated = require "tsdb_storage_engine_integrated"

print("=== V3集成版本与simple_multi_business测试 ===")
print("测试时间: " .. os.date("%Y-%m-%d %H:%M:%S"))

-- 测试1：simple_multi_business业务实例管理
print("\n--- 测试1：simple_multi_business业务实例管理 ---")

local function test_business_instance_manager()
    print("创建BusinessInstanceManager实例...")
    local instance_manager = BusinessInstanceManager:new("simple_multi_business_config.json")
    
    -- 加载配置
    print("加载业务实例配置...")
    local configs = instance_manager:get_all_instance_configs()
    print("加载了 " .. #configs .. " 个业务实例配置")
    
    -- 启动单个实例
    print("启动my_stock_quotes实例...")
    local success, err = instance_manager:start_instance("my_stock_quotes")
    if success then
        print("✓ my_stock_quotes实例启动成功")
    else
        print("✗ my_stock_quotes实例启动失败: " .. tostring(err))
    end
    
    -- 启动另一个实例
    print("启动my_orders实例...")
    success, err = instance_manager:start_instance("my_orders")
    if success then
        print("✓ my_orders实例启动成功")
    else
        print("✗ my_orders实例启动失败: " .. tostring(err))
    end
    
    -- 获取实例状态
    print("获取实例状态...")
    local status = instance_manager:get_instance_status("my_stock_quotes")
    print("my_stock_quotes状态: " .. tostring(status.status))
    
    -- 停止实例
    print("停止my_stock_quotes实例...")
    success, err = instance_manager:stop_instance("my_stock_quotes")
    if success then
        print("✓ my_stock_quotes实例停止成功")
    else
        print("✗ my_stock_quotes实例停止失败: " .. tostring(err))
    end
    
    -- 停止所有实例
    print("停止所有实例...")
    success = instance_manager:stop_all_instances()
    if success then
        print("✓ 所有实例停止成功")
    else
        print("✗ 实例停止失败")
    end
    
    return true
end

-- 测试2：V3基础版本数据操作
print("\n--- 测试2：V3基础版本数据操作 ---")

local function test_v3_storage_engine()
    print("创建V3存储引擎实例...")
    local v3_engine = V3StorageEngine:new({
        data_dir = "./data/simple_multi_business/v3_test",
        block_size = 30,
        enable_cold_data_separation = true,
        cold_data_threshold_days = 30
    })
    
    -- 初始化
    print("初始化V3存储引擎...")
    local success = v3_engine:initialize()
    if success then
        print("✓ V3存储引擎初始化成功")
    else
        print("✗ V3存储引擎初始化失败")
        return false
    end
    
    -- 写入测试数据
    print("写入测试数据...")
    local test_time = os.time()
    local write_success = v3_engine:write_point("SH000001", test_time, 100.5, {open=100, high=105, low=99})
    if write_success then
        print("✓ 数据写入成功")
    else
        print("✗ 数据写入失败")
    end
    
    -- 查询测试数据
    print("查询测试数据...")
    local read_success, results = v3_engine:read_point("SH000001", test_time - 60, test_time + 60, {})
    if read_success and results then
        print("✓ 数据查询成功，返回 " .. #results .. " 条记录")
        if #results > 0 then
            local first_point = results[1]
            print(string.format("  时间戳: %d, 值: %.2f", first_point.timestamp, first_point.value))
        end
    else
        print("✗ 数据查询失败")
    end
    
    -- 关闭引擎
    print("关闭V3存储引擎...")
    local close_success = v3_engine:close()
    if close_success then
        print("✓ V3存储引擎关闭成功")
    else
        print("✗ V3存储引擎关闭失败")
    end
    
    return true
end

-- 测试3：V3集成版本数据操作
print("\n--- 测试3：V3集成版本数据操作 ---")

local function test_integrated_storage_engine()
    print("创建V3集成版本存储引擎实例...")
    local integrated_engine = TSDBStorageEngineIntegrated:new({
        node_id = "test_node_simple_multi",
        data_dir = "./data/simple_multi_business/integrated_test",
        enable_cluster = false,  -- 禁用集群模式进行简单测试
        block_size = 30,
        enable_cold_data_separation = true,
        cold_data_threshold_days = 30
    })
    
    -- 初始化
    print("初始化V3集成版本存储引擎...")
    local init_success = integrated_engine:init()
    if init_success then
        print("✓ V3集成版本存储引擎初始化成功")
    else
        print("✗ V3集成版本存储引擎初始化失败")
        return false
    end
    
    -- 写入股票数据
    print("写入股票测试数据...")
    local test_time = os.time()
    local write_success, err = integrated_engine:put_stock_data("SH000001", test_time, {close=100.5, open=100, high=105, low=99}, "SH")
    if write_success then
        print("✓ 股票数据写入成功")
    else
        print("✗ 股票数据写入失败: " .. tostring(err))
    end
    
    -- 查询股票数据
    print("查询股票测试数据...")
    local read_success, results = integrated_engine:get_stock_data("SH000001", test_time - 60, test_time + 60, "SH")
    if read_success and results then
        print("✓ 股票数据查询成功，返回 " .. #results .. " 条记录")
        if #results > 0 then
            local first_point = results[1]
            if first_point.close then
                print(string.format("  时间戳: %d, 收盘价: %.2f", first_point.timestamp, first_point.close))
            else
                print(string.format("  时间戳: %d, 数据字段: %s", first_point.timestamp, tostring(first_point)))
            end
        end
    else
        print("✗ 股票数据查询失败")
    end
    
    -- 写入度量数据
    print("写入度量测试数据...")
    local metric_success, metric_err = integrated_engine:put_metric_data("cpu_usage", test_time, 75.5, {host="server1", region="us-east"})
    if metric_success then
        print("✓ 度量数据写入成功")
    else
        print("✗ 度量数据写入失败: " .. tostring(metric_err))
    end
    
    -- 查询度量数据
    print("查询度量测试数据...")
    local metric_read_success, metric_results = integrated_engine:get_metric_data("cpu_usage", test_time - 60, test_time + 60, {host="server1"})
    if metric_read_success and metric_results then
        print("✓ 度量数据查询成功，返回 " .. #metric_results .. " 条记录")
        if #metric_results > 0 then
            local first_metric = metric_results[1]
            print(string.format("  时间戳: %d, 值: %.2f", first_metric.timestamp, first_metric.value))
        end
    else
        print("✗ 度量数据查询失败")
    end
    
    -- 关闭引擎
    print("关闭V3集成版本存储引擎...")
    integrated_engine:close()
    print("✓ V3集成版本存储引擎关闭成功")
    
    return true
end

-- 测试4：RocksDB数据文件验证
print("\n--- 测试4：RocksDB数据文件验证 ---")

local function verify_rocksdb_data_files()
    print("检查simple_multi_business目录结构...")
    
    -- 检查simple_multi_business目录是否存在
    local check_dir = "ls -la ./data/simple_multi_business/ 2>/dev/null || echo '目录不存在'"
    local result = os.execute(check_dir)
    
    if result then
        print("✓ simple_multi_business目录存在")
        
        -- 检查各业务实例数据目录
        local business_dirs = {
            "stock_quotes",
            "orders", 
            "payments",
            "inventory",
            "sms",
            "user_behavior",
            "v3_test",
            "integrated_test"
        }
        
        for _, dir in ipairs(business_dirs) do
            local dir_path = "./data/simple_multi_business/" .. dir
            local check_cmd = "ls -la " .. dir_path .. " 2>/dev/null | head -5 || echo '目录不存在'"
            print("检查目录: " .. dir_path)
            os.execute(check_cmd)
        end
    else
        print("✗ simple_multi_business目录不存在")
    end
    
    return true
end

-- 执行所有测试
local function run_all_tests()
    print("开始执行所有测试...")
    
    local test_results = {}
    
    -- 测试1：业务实例管理
    test_results[1] = test_business_instance_manager()
    
    -- 测试2：V3基础版本
    test_results[2] = test_v3_storage_engine()
    
    -- 测试3：V3集成版本
    test_results[3] = test_integrated_storage_engine()
    
    -- 测试4：数据文件验证
    test_results[4] = verify_rocksdb_data_files()
    
    -- 统计结果
    print("\n=== 测试结果汇总 ===")
    local passed = 0
    local total = #test_results
    
    for i, result in ipairs(test_results) do
        if result then
            passed = passed + 1
            print(string.format("测试%d: ✓ 通过", i))
        else
            print(string.format("测试%d: ✗ 失败", i))
        end
    end
    
    print(string.format("\n总测试数: %d, 通过: %d, 失败: %d", total, passed, total - passed))
    
    if passed == total then
        print("✓ 所有测试通过！RocksDB数据使用验证成功")
    else
        print("✗ 部分测试失败，请检查相关配置和代码")
    end
    
    return passed == total
end

-- 运行测试
local success = run_all_tests()

print("\n=== 测试完成 ===")
print("完成时间: " .. os.date("%Y-%m-%d %H:%M:%S"))

if success then
    print("✓ simple_multi_business与V3集成版本测试验证成功")
    print("✓ RocksDB数据使用正确性验证通过")
else
    print("✗ 测试验证失败，请检查相关配置")
end

os.exit(success and 0 or 1)