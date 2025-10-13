#!/usr/bin/env luajit

-- Consul FFI 生产环境使用示例
-- Production usage example for Consul FFI integration

package.path = package.path .. ";./?.lua;/opt/stock-tsdb/lua/?.lua"

local consul_production_config = require("consul_production_config")

-- 创建Consul管理器实例
local consul_manager = consul_production_config.ConsulManager

-- 初始化函数
local function initialize_system()
    print("=== Stock TSDB 生产环境初始化 ===")
    
    -- 初始化Consul管理器
    local success, error = pcall(function()
        consul_manager:init()
    end)
    
    if not success then
        print("[错误] Consul管理器初始化失败: " .. tostring(error))
        return false
    end
    
    print("[成功] Consul管理器初始化完成")
    
    -- 检查集群状态
    local cluster_info = consul_manager:get_cluster_info()
    if cluster_info then
        print("[信息] 集群状态:")
        print("  - 节点数量: " .. cluster_info.node_count)
        print("  - Leader节点: " .. (cluster_info.leader_node or "无"))
        print("  - 当前节点: " .. cluster_info.current_node)
        print("  - 是否Leader: " .. tostring(cluster_info.is_leader))
    end
    
    return true
end

-- 存储股票数据的函数
local function store_stock_data(symbol, price, volume, timestamp)
    local key = "stocks/" .. symbol .. "/" .. timestamp
    local data = {
        symbol = symbol,
        price = price,
        volume = volume,
        timestamp = timestamp,
        node_id = consul_manager.config.cluster.node_id
    }
    
    local success, error = consul_manager:store_data(key, data, {
        consistency = "consistent",
        replication_factor = 3
    })
    
    if success then
        print("[成功] 存储股票数据: " .. symbol .. " @ " .. price)
    else
        print("[错误] 存储股票数据失败: " .. tostring(error))
    end
    
    return success
end

-- 读取股票数据的函数
local function read_stock_data(symbol, timestamp)
    local key = "stocks/" .. symbol .. "/" .. timestamp
    
    local data, error = consul_manager:read_data(key, {
        consistency = "consistent"
    })
    
    if data then
        print("[成功] 读取股票数据: " .. symbol .. " @ " .. (data.price or "未知"))
        return data
    else
        print("[错误] 读取股票数据失败: " .. tostring(error))
        return nil
    end
end

-- 获取一致性哈希节点的函数
local function get_consistent_node_for_stock(symbol)
    local node = consul_manager:get_consistent_node(symbol)
    
    if node then
        print("[信息] 股票 " .. symbol .. " 映射到节点: " .. node.id .. " (" .. node.address .. ")")
        return node
    else
        print("[警告] 无法获取一致性哈希节点")
        return nil
    end
end

-- 监控系统健康状态
local function monitor_system_health()
    print("\n=== 系统健康检查 ===")
    
    local health_info = consul_manager:monitor_health()
    
    if health_info then
        print("[信息] 健康检查时间: " .. os.date("%Y-%m-%d %H:%M:%S", health_info.timestamp))
        print("[信息] 系统健康状态: " .. (health_info.is_healthy and "健康" or "不健康"))
        
        if not health_info.is_healthy and #health_info.issues > 0 then
            print("[警告] 发现问题:")
            for _, issue in ipairs(health_info.issues) do
                print("  - " .. issue)
            end
        end
        
        if health_info.is_healthy then
            print("[成功] 系统运行正常")
        end
    else
        print("[错误] 无法获取健康信息")
    end
end

-- 批量处理股票数据
local function process_stock_batch(stocks)
    print("\n=== 批量处理股票数据 ===")
    print("[信息] 处理 " .. #stocks .. " 支股票数据")
    
    local success_count = 0
    local start_time = os.time()
    
    for _, stock in ipairs(stocks) do
        local success = store_stock_data(
            stock.symbol,
            stock.price,
            stock.volume,
            stock.timestamp
        )
        
        if success then
            success_count = success_count + 1
        end
    end
    
    local end_time = os.time()
    local duration = end_time - start_time
    
    print("[信息] 批量处理完成:")
    print("  - 成功: " .. success_count .. "/" .. #stocks)
    print("  - 耗时: " .. duration .. " 秒")
    print("  - 成功率: " .. string.format("%.1f%%", (success_count / #stocks) * 100))
end

-- 主函数
local function main()
    -- 初始化系统
    if not initialize_system() then
        print("[错误] 系统初始化失败，退出程序")
        return 1
    end
    
    -- 监控系统健康状态
    monitor_system_health()
    
    -- 模拟股票数据
    local test_stocks = {
        {symbol = "AAPL", price = 150.25, volume = 1000000, timestamp = os.time()},
        {symbol = "GOOGL", price = 2750.80, volume = 500000, timestamp = os.time()},
        {symbol = "MSFT", price = 305.15, volume = 800000, timestamp = os.time()},
        {symbol = "TSLA", price = 850.45, volume = 1200000, timestamp = os.time()},
        {symbol = "AMZN", price = 3250.60, volume = 600000, timestamp = os.time()}
    }
    
    -- 批量处理股票数据
    process_stock_batch(test_stocks)
    
    -- 测试一致性哈希
    print("\n=== 一致性哈希测试 ===")
    for _, stock in ipairs(test_stocks) do
        get_consistent_node_for_stock(stock.symbol)
    end
    
    -- 读取部分数据验证
    print("\n=== 数据验证测试 ===")
    for _, stock in ipairs(test_stocks) do
        local data = read_stock_data(stock.symbol, stock.timestamp)
        if data then
            print("[成功] 验证数据: " .. data.symbol .. " = " .. data.price)
        end
    end
    
    -- 最终健康检查
    monitor_system_health()
    
    print("\n=== 生产环境示例运行完成 ===")
    
    -- 优雅关闭
    consul_manager:cleanup()
    
    return 0
end

-- 错误处理
local success, result = pcall(main)
if not success then
    print("[严重错误] 程序异常终止: " .. tostring(result))
    consul_manager:cleanup()
    return 1
end

-- 退出程序
os.exit(result)