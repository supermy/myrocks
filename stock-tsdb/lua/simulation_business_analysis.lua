-- 模拟业务测试与对比分析脚本
-- 测试各种业务场景下的插件性能表现

local plugin_module = require("lua.rowkey_value_plugin")
local simulation_plugin = require("lua.simulation_business_plugin")

-- 获取插件管理器
local plugin_manager = plugin_module.default_manager

-- 注册模拟业务插件
local sim_plugin = simulation_plugin:new()
plugin_manager:register_plugin(sim_plugin)

-- 测试数据生成函数
local function generate_test_data(scenario, complexity, count)
    local test_data = {}
    for i = 1, count do
        local data = {
            scenario = scenario,
            entity_id = 1000 + i,
            timestamp = os.time() + i * 60,  -- 每分钟一条数据
            complexity = complexity,
            data_type = "test"
        }
        
        -- 根据场景添加特定字段
        if scenario == "ecommerce" then
            data.order_amount = math.random(10, 1000)
            data.product_count = math.random(1, 10)
            data.user_level = math.random() > 0.5 and "vip" or "normal"
            data.payment_method = math.random() > 0.5 and "alipay" or "wechat"
        elseif scenario == "finance" then
            data.price = math.random(50, 200)
            data.volume = math.random(1000, 10000)
            data.market = math.random() > 0.5 and "SH" or "SZ"
            data.symbol = string.format("%06d", math.random(1, 999999))
        elseif scenario == "iot" then
            data.value = math.random(20, 30)
            data.quality = math.random(90, 100)
            data.sensor_type = "temperature"
            data.battery_level = math.random(80, 100)
        elseif scenario == "logistics" then
            data.package_status = math.random() > 0.5 and "in_transit" or "delivered"
            data.location = "warehouse_" .. math.random(1, 10)
            data.estimated_delivery = "2024-01-01"
            data.weight = math.random(0.5, 5.0)
        elseif scenario == "social" then
            data.post_type = math.random() > 0.5 and "text" or "image"
            data.like_count = math.random(0, 100)
            data.comment_count = math.random(0, 50)
            data.share_count = math.random(0, 20)
        end
        
        table.insert(test_data, data)
    end
    return test_data
end

-- 性能测试函数
local function performance_test(plugin, test_data, iterations)
    local start_time = os.clock()
    
    for i = 1, iterations do
        for _, data in ipairs(test_data) do
            -- 编码测试
            local rowkey, qualifier = plugin:encode_rowkey(
                data.scenario, data.entity_id, data.timestamp, data.complexity
            )
            local value = plugin:encode_value(data)
            
            -- 解码测试
            local decoded_key = plugin:decode_rowkey(rowkey)
            local decoded_value = plugin:decode_value(value)
        end
    end
    
    local end_time = os.clock()
    return end_time - start_time
end

-- 存储效率分析函数
local function storage_efficiency_analysis(plugin, test_data)
    local total_key_size = 0
    local total_value_size = 0
    local sample_count = 0
    
    for _, data in ipairs(test_data) do
        local rowkey, qualifier = plugin:encode_rowkey(
            data.scenario, data.entity_id, data.timestamp, data.complexity
        )
        local value = plugin:encode_value(data)
        
        total_key_size = total_key_size + #rowkey + #qualifier
        total_value_size = total_value_size + #value
        sample_count = sample_count + 1
    end
    
    local avg_key_size = total_key_size / sample_count
    local avg_value_size = total_value_size / sample_count
    local compression_rate = (1 - (avg_key_size + avg_value_size) / 1024) * 100  -- 相对于1KB的压缩率
    
    return {
        avg_key_size = avg_key_size,
        avg_value_size = avg_value_size,
        compression_rate = compression_rate
    }
end

-- 主测试函数
local function run_simulation_analysis()
    print("🚀 开始模拟业务测试与对比分析")
    print("=" .. string.rep("=", 78))
    
    -- 获取所有插件
    local plugins_list = plugin_manager:list_plugins()
    local plugins = {}
    for _, plugin_info in ipairs(plugins_list) do
        local plugin = plugin_manager:get_plugin(plugin_info.name)
        if plugin then
            table.insert(plugins, {
                name = plugin_info.name,
                plugin = plugin
            })
        end
    end
    
    -- 测试场景定义
    local test_scenarios = {
        {name = "电商业务", scenario = "ecommerce", complexity = "medium", data_count = 100},
        {name = "金融业务", scenario = "finance", complexity = "complex", data_count = 100},
        {name = "物联网业务", scenario = "iot", complexity = "simple", data_count = 100},
        {name = "物流业务", scenario = "logistics", complexity = "medium", data_count = 100},
        {name = "社交业务", scenario = "social", complexity = "complex", data_count = 100}
    }
    
    local results = {}
    
    -- 对每个场景进行测试
    for _, scenario_config in ipairs(test_scenarios) do
        print(string.format("\n📊 测试场景: %s", scenario_config.name))
        print("-" .. string.rep("-", 78))
        
        -- 生成测试数据
        local test_data = generate_test_data(
            scenario_config.scenario, 
            scenario_config.complexity, 
            scenario_config.data_count
        )
        
        local scenario_results = {}
        
        -- 对每个插件进行测试
        for _, plugin_info in ipairs(plugins) do
            local plugin_name = plugin_info.name
            local plugin = plugin_info.plugin
            
            -- 性能测试
            local iterations = 10
            local total_time = performance_test(plugin, test_data, iterations)
            local avg_time_per_op = (total_time * 1000) / (iterations * #test_data)  -- 毫秒/操作
            
            -- 存储效率分析
            local efficiency = storage_efficiency_analysis(plugin, test_data)
            
            -- 记录结果
            scenario_results[plugin_name] = {
                avg_time_per_op = avg_time_per_op,
                avg_key_size = efficiency.avg_key_size,
                avg_value_size = efficiency.avg_value_size,
                compression_rate = efficiency.compression_rate
            }
            
            print(string.format("  %-20s: %.3f ms/op, Key: %.1fB, Value: %.1fB, 压缩率: %.1f%%", 
                plugin_name, avg_time_per_op, efficiency.avg_key_size, 
                efficiency.avg_value_size, efficiency.compression_rate))
        end
        
        results[scenario_config.name] = scenario_results
    end
    
    -- 综合对比分析
    print("\n🎯 综合对比分析")
    print("=" .. string.rep("=", 78))
    
    -- 计算每个插件的综合得分
    local plugin_scores = {}
    
    for plugin_name, _ in pairs(results[test_scenarios[1].name]) do
        plugin_scores[plugin_name] = {
            performance_score = 0,
            storage_score = 0,
            total_score = 0
        }
    end
    
    -- 对每个场景计算得分
    for scenario_name, scenario_results in pairs(results) do
        -- 找到最佳性能
        local best_performance = math.huge
        for _, result in pairs(scenario_results) do
            if result.avg_time_per_op < best_performance then
                best_performance = result.avg_time_per_op
            end
        end
        
        -- 找到最佳存储效率
        local best_storage = math.huge
        for _, result in pairs(scenario_results) do
            local total_size = result.avg_key_size + result.avg_value_size
            if total_size < best_storage then
                best_storage = total_size
            end
        end
        
        -- 计算每个插件的得分
        for plugin_name, result in pairs(scenario_results) do
            -- 性能得分（越低越好，归一化到0-100）
            local perf_score = (best_performance / result.avg_time_per_op) * 50
            
            -- 存储得分（越小越好，归一化到0-100）
            local total_size = result.avg_key_size + result.avg_value_size
            local storage_score = (best_storage / total_size) * 50
            
            plugin_scores[plugin_name].performance_score = plugin_scores[plugin_name].performance_score + perf_score
            plugin_scores[plugin_name].storage_score = plugin_scores[plugin_name].storage_score + storage_score
        end
    end
    
    -- 计算总分并排序
    local ranked_plugins = {}
    for plugin_name, scores in pairs(plugin_scores) do
        scores.total_score = scores.performance_score + scores.storage_score
        table.insert(ranked_plugins, {
            name = plugin_name,
            performance_score = scores.performance_score,
            storage_score = scores.storage_score,
            total_score = scores.total_score
        })
    end
    
    table.sort(ranked_plugins, function(a, b) return a.total_score > b.total_score end)
    
    -- 输出排名
    print("排名 | 插件名称           | 性能得分 | 存储得分 | 综合得分 | 推荐场景")
    print("----|-------------------|----------|----------|----------|-----------------")
    
    for i, plugin in ipairs(ranked_plugins) do
        local recommendation = ""
        if plugin.name == "iot_data" then
            recommendation = "高频IOT数据"
        elseif plugin.name == "stock_quote" or plugin.name == "financial_quote" then
            recommendation = "金融行情数据"
        elseif plugin.name == "simulation_business" then
            recommendation = "多业务场景测试"
        else
            recommendation = "通用业务数据"
        end
        
        print(string.format("%2d  | %-17s | %7.1f  | %7.1f  | %7.1f  | %s", 
            i, plugin.name, plugin.performance_score, 
            plugin.storage_score, plugin.total_score, recommendation))
    end
    
    -- 场景适配性分析
    print("\n🔍 场景适配性分析")
    print("-" .. string.rep("-", 78))
    
    for _, scenario_config in ipairs(test_scenarios) do
        local scenario_name = scenario_config.name
        local scenario_results = results[scenario_name]
        
        -- 找到该场景下表现最好的插件
        local best_plugin = ""
        local best_score = -1
        
        for plugin_name, result in pairs(scenario_results) do
            if result and result.avg_time_per_op and result.avg_time_per_op > 0 then
                local score = (1 / result.avg_time_per_op) * 0.6 + 
                             (1 / (result.avg_key_size + result.avg_value_size)) * 0.4
                if score > best_score then
                    best_score = score
                    best_plugin = plugin_name
                end
            end
        end
        
        if best_plugin ~= "" and scenario_results[best_plugin] then
            print(string.format("%-10s: 推荐使用 %s 插件 (性能: %.3f ms/op, 存储: %.1fB)", 
                scenario_name, best_plugin, 
                scenario_results[best_plugin].avg_time_per_op,
                scenario_results[best_plugin].avg_key_size + scenario_results[best_plugin].avg_value_size))
        else
            print(string.format("%-10s: 暂无推荐插件", scenario_name))
        end
    end
    
    -- 优化建议
    print("\n💡 优化建议")
    print("-" .. string.rep("-", 78))
    
    local top_plugin = ranked_plugins[1]
    print(string.format("🏆 综合表现最佳: %s 插件 (得分: %.1f)", top_plugin.name, top_plugin.total_score))
    
    if top_plugin.performance_score > top_plugin.storage_score then
        print("💪 优势: 性能表现突出，适合高频数据处理场景")
    else
        print("💾 优势: 存储效率高，适合存储空间敏感场景")
    end
    
    -- 针对不同插件的优化建议
    for _, plugin in ipairs(ranked_plugins) do
        if plugin.name == "iot_data" then
            print("📈 IOT数据插件: 已采用二进制编码，存储效率极高，适合IOT高频数据场景")
        elseif plugin.name == "simulation_business" then
            print("🎭 模拟业务插件: 支持多种业务场景测试，适合业务原型开发和性能对比")
        elseif plugin.name == "stock_quote" or plugin.name == "financial_quote" then
            print("📊 行情数据插件: JSON格式可读性好，适合需要灵活查询的金融场景")
        else
            print(string.format("🔧 %s插件: 通用业务场景表现良好，可根据具体需求调整编码策略", plugin.name))
        end
    end
    
    print("\n✅ 模拟业务测试与对比分析完成")
    print(string.format("📋 共测试 %d 个业务场景，%d 个插件", #test_scenarios, #plugins))
end

-- 运行分析
run_simulation_analysis()