-- 轻度汇总数据库测试用例
-- 测试时间维度、其他维度聚合、ZeroMQ异步计算和存储引擎功能

local LightAggregationController = require "light_aggregation_controller"
local LightAggregationConfig = require "light_aggregation_config"

-- 测试配置 - 使用LightAggregationConfig的默认配置并覆盖部分设置
local test_config = {
    -- ZeroMQ异步配置
    zmq = {
        enabled = false,  -- 测试时禁用异步，便于验证结果
        port = 5555,
        send_timeout = 5000,
        recv_timeout = 5000
    },
    
    -- 汇总计算配置
    aggregation = {
        enabled = true,
        batch_size = 1000,
        flush_interval = 60,      -- 秒
        retention_days = 30,     -- 数据保留天数
        max_memory_usage = 1024 * 1024 * 100, -- 100MB
        enable_compression = true
    },
    
    -- RocksDB存储配置
    storage = {
        path = "/tmp/light_aggregation_test",
        create_if_missing = true,
        error_if_exists = false
    },
    
    -- 监控配置
    monitoring = {
        enabled = true,
        stats_interval = 30,     -- 秒
        enable_prometheus = false
    }
}

-- 使用配置模块创建正确的配置结构
local config_manager = LightAggregationConfig:new(test_config)
local valid, errors = config_manager:validate()
if not valid then
    print("❌ 配置验证失败:")
    for _, err in ipairs(errors) do
        print("   -", err)
    end
    os.exit(1)
end

-- 测试数据生成器
local function generate_test_data(count, start_time)
    local data_points = {}
    start_time = start_time or os.time() - 3600  -- 默认从1小时前开始
    
    local codes = {"000001", "000002", "000003", "600000", "600001"}
    local markets = {"SH", "SZ"}
    local industries = {"金融", "科技", "制造", "能源", "医疗"}
    local regions = {"华东", "华北", "华南", "西南", "西北"}
    
    for i = 1, count do
        local timestamp = start_time + (i * 60)  -- 每分钟一个数据点
        local value = 100 + math.random() * 50  -- 100-150之间的随机值
        
        table.insert(data_points, {
            timestamp = timestamp,
            value = value,
            dimensions = {
                code = codes[math.random(#codes)],
                market = markets[math.random(#markets)],
                industry = industries[math.random(#industries)],
                region = regions[math.random(#regions)]
            }
        })
    end
    
    return data_points
end

-- 测试用例1: 基本功能测试
local function test_basic_functionality()
    print("=== 测试1: 基本功能测试 ===")
    
    -- 创建控制器
    local controller = LightAggregationController:new(config_manager)
    
    -- 初始化
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    print("✅ 控制器初始化成功")
    
    -- 启动
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    print("✅ 控制器启动成功")
    
    -- 生成测试数据
    local test_data = generate_test_data(10)
    
    -- 处理数据
    ok, err = controller:process_batch_data(test_data)
    if not ok then
        print("❌ 数据处理失败:", err)
        return false
    end
    print("✅ 数据处理成功")
    
    -- 获取统计信息
    local stats = controller:get_stats()
    print("📊 统计信息:")
    print("   数据点处理数量:", stats.controller.data_points_processed)
    print("   聚合结果存储数量:", stats.controller.aggregation_results_stored)
    
    -- 停止控制器
    ok, err = controller:stop()
    if not ok then
        print("❌ 停止失败:", err)
        return false
    end
    print("✅ 控制器停止成功")
    
    return true
end

-- 测试用例2: 时间维度聚合测试
local function test_time_dimension_aggregation()
    print("\n=== 测试2: 时间维度聚合测试 ===")
    
    local controller = LightAggregationController:new(config_manager)
    
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    
    -- 生成跨越多个时间维度的数据
    local test_data = generate_test_data(100, os.time() - 86400)  -- 24小时内的数据
    
    ok, err = controller:process_batch_data(test_data)
    if not ok then
        print("❌ 数据处理失败:", err)
        return false
    end
    
    -- 查询时间维度聚合结果
    local query = {
        dimension_type = "time",
        dimension = "HOUR",
        start_time = os.date("%Y%m%d%H", os.time() - 3600),
        end_time = os.date("%Y%m%d%H", os.time() + 3600)
    }
    
    local results, query_err = controller:query_aggregated_data(query)
    if query_err then
        print("❌ 查询失败:", query_err)
        return false
    end
    
    print("✅ 时间维度聚合测试成功")
    print("   查询到聚合结果数量:", #results)
    
    if #results > 0 then
        print("   示例聚合结果:")
        for i = 1, math.min(3, #results) do
            print("     ", results[i].key, "->", results[i].value)
        end
    end
    
    controller:stop()
    return true
end

-- 测试用例3: 其他维度聚合测试
local function test_other_dimension_aggregation()
    print("\n=== 测试3: 其他维度聚合测试 ===")
    
    local controller = LightAggregationController:new(config_manager)
    
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    
    -- 生成特定维度的测试数据
    local test_data = {}
    for i = 1, 50 do
        table.insert(test_data, {
            timestamp = os.time() - (i * 60),
            value = 100 + math.random() * 50,
            dimensions = {
                code = "000001",  -- 固定股票代码
                market = "SH",
                industry = "金融",
                region = "华东"
            }
        })
    end
    
    ok, err = controller:process_batch_data(test_data)
    if not ok then
        print("❌ 数据处理失败:", err)
        return false
    end
    
    -- 查询其他维度聚合结果
    local query = {
        dimension_type = "other",
        dimension = "code",
        value = "000001"
    }
    
    local results, query_err = controller:query_aggregated_data(query)
    if query_err then
        print("❌ 查询失败:", query_err)
        return false
    end
    
    print("✅ 其他维度聚合测试成功")
    print("   查询到聚合结果数量:", #results)
    
    controller:stop()
    return true
end

-- 测试用例4: 性能测试
local function test_performance()
    print("\n=== 测试4: 性能测试 ===")
    
    local controller = LightAggregationController:new(config_manager)
    
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    
    -- 生成大量测试数据
    local start_time = os.time()
    local test_data = generate_test_data(1000)
    
    -- 批量处理
    ok, err = controller:process_batch_data(test_data)
    if not ok then
        print("❌ 数据处理失败:", err)
        return false
    end
    
    local end_time = os.time()
    local processing_time = end_time - start_time
    
    -- 获取统计信息
    local stats = controller:get_stats()
    
    print("✅ 性能测试完成")
    print("   处理数据量:", #test_data, "条")
    print("   处理时间:", processing_time, "秒")
    print("   吞吐量:", #test_data / processing_time, "条/秒")
    print("   聚合结果数量:", stats.controller.aggregation_results_stored)
    
    controller:stop()
    return true
end

-- 测试用例5: 错误处理测试
local function test_error_handling()
    print("\n=== 测试5: 错误处理测试 ===")
    
    local controller = LightAggregationController:new(config_manager)
    
    -- 测试无效数据
    local invalid_data = {
        { timestamp = "invalid", value = 100 },  -- 无效时间戳
        { value = 100 },  -- 缺少时间戳
        { timestamp = os.time() }  -- 缺少值
    }
    
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    
    -- 处理无效数据
    ok, err = controller:process_batch_data(invalid_data)
    if ok then
        print("❌ 错误处理测试失败: 应该拒绝无效数据")
        return false
    end
    
    print("✅ 错误处理测试成功")
    print("   正确拒绝了无效数据:", err)
    
    controller:stop()
    return true
end

-- 测试用例6: 健康检查测试
local function test_health_check()
    print("\n=== 测试6: 健康检查测试 ===")
    
    local controller = LightAggregationController:new(config_manager)
    
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    
    -- 执行健康检查
    local health = controller:health_check()
    
    print("✅ 健康检查完成")
    print("   整体状态:", health.status)
    print("   运行时间:", health.uptime, "秒")
    print("   组件数量:", #health.components)
    
    for _, component in ipairs(health.components) do
        print("   组件", component.name, "状态:", component.status)
    end
    
    controller:stop()
    return true
end

-- 主测试函数
local function run_all_tests()
    print("🚀 开始轻度汇总数据库测试套件")
    print("=" .. string.rep("=", 50))
    
    local tests = {
        { name = "基本功能测试", func = test_basic_functionality },
        { name = "时间维度聚合测试", func = test_time_dimension_aggregation },
        { name = "其他维度聚合测试", func = test_other_dimension_aggregation },
        { name = "性能测试", func = test_performance },
        { name = "错误处理测试", func = test_error_handling },
        { name = "健康检查测试", func = test_health_check }
    }
    
    local passed = 0
    local failed = 0
    
    for i, test in ipairs(tests) do
        local success = test.func()
        if success then
            passed = passed + 1
            print("✅", test.name, "通过")
        else
            failed = failed + 1
            print("❌", test.name, "失败")
        end
        print("-" .. string.rep("-", 50))
    end
    
    print("📊 测试结果汇总:")
    print("   通过:", passed, "项")
    print("   失败:", failed, "项")
    print("   总计:", #tests, "项")
    
    if failed == 0 then
        print("🎉 所有测试通过! 轻度汇总数据库功能正常")
    else
        print("⚠️  有", failed, "项测试失败，请检查相关功能")
    end
    
    return failed == 0
end

-- 运行测试
if arg and arg[0]:find("test_light_aggregation") then
    local success = run_all_tests()
    os.exit(success and 0 or 1)
end

return {
    run_all_tests = run_all_tests,
    generate_test_data = generate_test_data,
    test_config = test_config
}