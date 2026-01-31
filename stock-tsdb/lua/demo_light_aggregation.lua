-- 轻度汇总数据库演示程序
-- 展示时间维度、其他维度聚合、异步计算和查询功能

local LightAggregationController = require "light_aggregation_controller"

-- 演示配置
local demo_config = {
    time_dimensions = {
        HOUR = { enabled = true, compression = "separator" },
        DAY = { enabled = true, compression = "separator" },
        WEEK = { enabled = true, compression = "separator" },
        MONTH = { enabled = true, compression = "separator" }
    },
    other_dimensions = {
        code = { enabled = true, compression = "prefix" },
        market = { enabled = true, compression = "prefix" },
        industry = { enabled = true, compression = "prefix" },
        region = { enabled = true, compression = "prefix" }
    },
    aggregation_functions = {
        COUNT = { enabled = true },
        SUM = { enabled = true },
        AVG = { enabled = true },
        MAX = { enabled = true },
        MIN = { enabled = true }
    },
    compression = {
        separator = { enabled = true, delimiter = "|" },
        prefix = { enabled = true },
        lz4 = { enabled = false }
    },
    zmq = {
        enabled = false,  -- 演示时禁用异步，便于观察结果
        endpoints = {
            client = "tcp://localhost:5555",
            processor = "tcp://*:5555"
        },
        timeout = 5000
    },
    aggregation = {
        buffer_size = 100,
        flush_interval = 30,
        retention_days = 7
    },
    storage = {
        db_path = "/tmp/light_aggregation_demo",
        create_if_missing = true,
        error_if_exists = false
    },
    monitoring = {
        enabled = true,
        stats_interval = 10
    }
}

-- 生成演示数据
local function generate_demo_data()
    local data_points = {}
    
    -- 股票数据
    local stocks = {
        { code = "000001", name = "平安银行", market = "SZ", industry = "金融", region = "华南" },
        { code = "000002", name = "万科A", market = "SZ", industry = "房地产", region = "华南" },
        { code = "600000", name = "浦发银行", market = "SH", industry = "金融", region = "华东" },
        { code = "600036", name = "招商银行", market = "SH", industry = "金融", region = "华东" },
        { code = "601318", name = "中国平安", market = "SH", industry = "保险", region = "华南" }
    }
    
    local current_time = os.time()
    
    -- 为每只股票生成24小时的数据（每小时1个数据点）
    for _, stock in ipairs(stocks) do
        for hour = 0, 23 do
            local timestamp = current_time - (hour * 3600)
            local base_price = 10 + math.random() * 90  -- 10-100之间的基础价格
            local price_variation = math.random() * 5 - 2.5  -- -2.5到+2.5的价格波动
            local volume = math.random(10000, 1000000)  -- 成交量
            
            table.insert(data_points, {
                timestamp = timestamp,
                value = base_price + price_variation,
                volume = volume,
                dimensions = {
                    code = stock.code,
                    market = stock.market,
                    industry = stock.industry,
                    region = stock.region
                }
            })
        end
    end
    
    return data_points
end

-- 演示1: 基本使用流程
local function demo_basic_usage()
    print("🎯 演示1: 基本使用流程")
    print("=" .. string.rep("=", 60))
    
    -- 创建控制器
    print("1. 创建轻度汇总数据库控制器...")
    local controller = LightAggregationController:new(demo_config)
    
    -- 初始化
    print("2. 初始化控制器...")
    local ok, err = controller:initialize()
    if not ok then
        print("❌ 初始化失败:", err)
        return false
    end
    print("✅ 初始化成功")
    
    -- 启动
    print("3. 启动控制器...")
    ok, err = controller:start()
    if not ok then
        print("❌ 启动失败:", err)
        return false
    end
    print("✅ 启动成功")
    
    -- 生成演示数据
    print("4. 生成演示数据...")
    local demo_data = generate_demo_data()
    print("   生成数据点数量:", #demo_data)
    
    -- 处理数据
    print("5. 处理数据并生成聚合结果...")
    ok, err = controller:process_batch_data(demo_data)
    if not ok then
        print("❌ 数据处理失败:", err)
        return false
    end
    print("✅ 数据处理成功")
    
    -- 获取统计信息
    print("6. 获取统计信息...")
    local stats = controller:get_stats()
    print("   数据点处理数量:", stats.controller.data_points_processed)
    print("   聚合结果存储数量:", stats.controller.aggregation_results_stored)
    
    return controller
end

-- 演示2: 时间维度聚合查询
local function demo_time_dimension_query(controller)
    print("\n🎯 演示2: 时间维度聚合查询")
    print("=" .. string.rep("=", 60))
    
    local current_time = os.time()
    
    -- 查询小时维度聚合
    print("1. 查询小时维度聚合结果...")
    local hour_query = {
        dimension_type = "time",
        dimension = "HOUR",
        start_time = os.date("%Y%m%d%H", current_time - 86400),  -- 24小时前
        end_time = os.date("%Y%m%d%H", current_time)
    }
    
    local hour_results, hour_err = controller:query_aggregated_data(hour_query)
    if hour_err then
        print("❌ 小时维度查询失败:", hour_err)
    else
        print("✅ 小时维度查询成功")
        print("   查询到聚合结果数量:", #hour_results)
        
        if #hour_results > 0 then
            print("   最近3个小时的聚合结果:")
            for i = 1, math.min(3, #hour_results) do
                local result = hour_results[i]
                print("     ", result.key, "->", result.value)
            end
        end
    end
    
    -- 查询天维度聚合
    print("\n2. 查询天维度聚合结果...")
    local day_query = {
        dimension_type = "time",
        dimension = "DAY",
        start_time = os.date("%Y%m%d", current_time - 7 * 86400),  -- 7天前
        end_time = os.date("%Y%m%d", current_time)
    }
    
    local day_results, day_err = controller:query_aggregated_data(day_query)
    if day_err then
        print("❌ 天维度查询失败:", day_err)
    else
        print("✅ 天维度查询成功")
        print("   查询到聚合结果数量:", #day_results)
        
        if #day_results > 0 then
            print("   最近3天的聚合结果:")
            for i = 1, math.min(3, #day_results) do
                local result = day_results[i]
                print("     ", result.key, "->", result.value)
            end
        end
    end
    
    return true
end

-- 演示3: 其他维度聚合查询
local function demo_other_dimension_query(controller)
    print("\n🎯 演示3: 其他维度聚合查询")
    print("=" .. string.rep("=", 60))
    
    -- 查询股票代码维度聚合
    print("1. 查询股票代码维度聚合结果...")
    local code_query = {
        dimension_type = "other",
        dimension = "code",
        value = "000001"  -- 平安银行
    }
    
    local code_results, code_err = controller:query_aggregated_data(code_query)
    if code_err then
        print("❌ 股票代码维度查询失败:", code_err)
    else
        print("✅ 股票代码维度查询成功")
        print("   查询到聚合结果数量:", #code_results)
        
        if #code_results > 0 then
            print("   平安银行的聚合结果:")
            for i = 1, math.min(3, #code_results) do
                local result = code_results[i]
                print("     ", result.key, "->", result.value)
            end
        end
    end
    
    -- 查询行业维度聚合
    print("\n2. 查询行业维度聚合结果...")
    local industry_query = {
        dimension_type = "other",
        dimension = "industry",
        value = "金融"
    }
    
    local industry_results, industry_err = controller:query_aggregated_data(industry_query)
    if industry_err then
        print("❌ 行业维度查询失败:", industry_err)
    else
        print("✅ 行业维度查询成功")
        print("   查询到聚合结果数量:", #industry_results)
        
        if #industry_results > 0 then
            print("   金融行业的聚合结果:")
            for i = 1, math.min(3, #industry_results) do
                local result = industry_results[i]
                print("     ", result.key, "->", result.value)
            end
        end
    end
    
    return true
end

-- 演示4: 性能监控和健康检查
local function demo_monitoring_and_health(controller)
    print("\n🎯 演示4: 性能监控和健康检查")
    print("=" .. string.rep("=", 60))
    
    -- 获取详细统计信息
    print("1. 获取详细统计信息...")
    local stats = controller:get_stats()
    
    print("   控制器状态:")
    print("     - 是否初始化:", stats.controller.is_initialized)
    print("     - 是否运行:", stats.controller.is_running)
    print("     - 启动时间:", os.date("%Y-%m-%d %H:%M:%S", stats.controller.startup_time))
    print("     - 最后活动时间:", os.date("%Y-%m-%d %H:%M:%S", stats.controller.last_activity))
    print("     - 数据点处理数量:", stats.controller.data_points_processed)
    print("     - 聚合结果存储数量:", stats.controller.aggregation_results_stored)
    print("     - 错误数量:", stats.controller.errors)
    
    -- 健康检查
    print("\n2. 执行健康检查...")
    local health = controller:health_check()
    
    print("   健康状态:", health.status)
    print("   运行时间:", health.uptime, "秒")
    print("   组件状态:")
    for _, component in ipairs(health.components) do
        print("     -", component.name, ":", component.status)
    end
    
    -- 配置摘要
    print("\n3. 配置摘要:")
    print("   启用时间维度:", table.concat(stats.configuration.enabled_time_dimensions, ", "))
    print("   启用其他维度:", table.concat(stats.configuration.enabled_other_dimensions, ", "))
    print("   启用聚合函数:", table.concat(stats.configuration.enabled_aggregation_functions, ", "))
    
    return true
end

-- 演示5: 实时数据处理
local function demo_real_time_processing(controller)
    print("\n🎯 演示5: 实时数据处理")
    print("=" .. string.rep("=", 60))
    
    -- 模拟实时数据流
    print("1. 模拟实时数据流处理...")
    
    local real_time_data = {
        {
            timestamp = os.time(),
            value = 105.5,
            volume = 50000,
            dimensions = {
                code = "000001",
                market = "SZ",
                industry = "金融",
                region = "华南"
            }
        },
        {
            timestamp = os.time() + 60,  -- 1分钟后
            value = 106.2,
            volume = 60000,
            dimensions = {
                code = "000001",
                market = "SZ", 
                industry = "金融",
                region = "华南"
            }
        },
        {
            timestamp = os.time() + 120,  -- 2分钟后
            value = 105.8,
            volume = 45000,
            dimensions = {
                code = "000001",
                market = "SZ",
                industry = "金融",
                region = "华南"
            }
        }
    }
    
    -- 逐个处理实时数据点
    for i, data_point in ipairs(real_time_data) do
        print("   处理第" .. i .. "个实时数据点...")
        local ok, err = controller:process_data_point(data_point)
        if ok then
            print("     ✅ 处理成功")
        else
            print("     ❌ 处理失败:", err)
        end
    end
    
    -- 手动刷新缓冲区
    print("\n2. 手动刷新缓冲区...")
    local flushed_count = controller:flush_all_buffers()
    print("   刷新了", flushed_count, "个聚合结果")
    
    -- 查询最新的聚合结果
    print("\n3. 查询最新的聚合结果...")
    local query = {
        dimension_type = "time",
        dimension = "HOUR",
        start_time = os.date("%Y%m%d%H", os.time() - 3600),
        end_time = os.date("%Y%m%d%H", os.time() + 3600)
    }
    
    local results, err = controller:query_aggregated_data(query)
    if err then
        print("❌ 查询失败:", err)
    else
        print("✅ 查询成功")
        print("   查询到聚合结果数量:", #results)
        
        if #results > 0 then
            print("   最新的聚合结果:")
            for i = 1, math.min(2, #results) do
                local result = results[i]
                print("     ", result.key, "->", result.value)
            end
        end
    end
    
    return true
end

-- 主演示函数
local function run_demo()
    print("🚀 轻度汇总数据库演示程序")
    print("=" .. string.rep("=", 60))
    print("本演示展示基于时间维度（小时、天、周、月）和其他维度（股票代码、市场、行业、地区）")
    print("的轻度汇总数据库功能，采用分隔符压缩和前缀压缩技术。")
    print()
    
    -- 运行演示
    local controller = demo_basic_usage()
    if not controller then
        print("❌ 基本使用演示失败")
        return false
    end
    
    demo_time_dimension_query(controller)
    demo_other_dimension_query(controller)
    demo_monitoring_and_health(controller)
    demo_real_time_processing(controller)
    
    -- 停止控制器
    print("\n🎯 演示结束: 停止控制器")
    print("=" .. string.rep("=", 60))
    
    local ok, err = controller:stop()
    if not ok then
        print("❌ 停止失败:", err)
        return false
    end
    
    print("✅ 控制器停止成功")
    print("\n🎉 所有演示完成!")
    print("轻度汇总数据库功能演示成功，展示了时间维度聚合、其他维度聚合、实时数据处理和监控功能。")
    
    return true
end

-- 运行演示
if arg and arg[0]:find("demo_light_aggregation") then
    local success = run_demo()
    os.exit(success and 0 or 1)
end

return {
    run_demo = run_demo,
    generate_demo_data = generate_demo_data,
    demo_config = demo_config
}