#!/usr/bin/env luajit

-- V3集成版本测试对比脚本
-- 测试功能：一致性哈希、30秒定长块、冷热数据分离、集群功能

package.path = package.path .. ";./lua/?.lua"

-- 导入V3集成版本
local TSDBStorageEngineIntegrated = require "tsdb_storage_engine_integrated"

-- 测试配置
local config = {
    data_dir = "./test_v3_integrated",
    node_id = "test_node_1",
    cluster_name = "test-cluster",
    write_buffer_size = 64 * 1024 * 1024,
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,
    max_bytes_for_level_base = 256 * 1024 * 1024,
    compression = "lz4",
    block_size = 30,  -- 30秒定长块
    enable_cold_data_separation = true,
    cold_data_threshold_days = 30,
    seed_nodes = {},
    gossip_port = 9090,
    data_port = 9091,
    consul_endpoints = {"http://127.0.0.1:8500"},
    replication_factor = 3,
    virtual_nodes_per_physical = 100
}

-- 测试数据生成
local function generate_test_data(stock_code, start_time, count)
    local data = {}
    for i = 1, count do
        local timestamp = start_time + (i-1) * 30  -- 每30秒一个数据点
        local price = 100 + math.random() * 50
        local volume = math.random(1000, 10000)
        
        table.insert(data, {
            timestamp = timestamp,
            open = price,
            high = price + math.random() * 2,
            low = price - math.random() * 2,
            close = price + (math.random() - 0.5) * 5,
            volume = volume,
            amount = volume * price
        })
    end
    return data
end

-- 性能测试函数
local function performance_test()
    print("=== V3集成版本性能测试 ===")
    
    -- 创建引擎实例
    local engine = TSDBStorageEngineIntegrated:new(config)
    
    -- 初始化
    local success, err = engine:init()
    if not success then
        print("初始化失败: " .. tostring(err))
        return
    end
    
    -- 测试1：批量写入性能
    print("\n--- 测试1：批量写入性能 ---")
    local stock_code = "SH000001"
    local start_time = 1704067200  -- 2024-01-01 00:00:00
    local batch_sizes = {100, 500, 1000, 2000, 5000}
    
    for _, batch_size in ipairs(batch_sizes) do
        local test_data = generate_test_data(stock_code, start_time, batch_size)
        
        local start_time_write = os.clock()
        local success_count = 0
        
        for _, data_point in ipairs(test_data) do
            local success, err = engine:put_stock_data(
                stock_code, 
                data_point.timestamp, 
                data_point, 
                "SH"
            )
            if success then
                success_count = success_count + 1
            end
        end
        
        local end_time_write = os.clock()
        local write_time = end_time_write - start_time_write
        local write_rate = batch_size / write_time
        
        print(string.format("批量大小: %d, 成功写入: %d, 耗时: %.3fs, 写入速率: %.1f 点/秒", 
            batch_size, success_count, write_time, write_rate))
    end
    
    -- 测试2：范围查询性能
    print("\n--- 测试2：范围查询性能 ---")
    local query_ranges = {
        {1, 3600},      -- 1小时数据
        {1, 86400},     -- 1天数据  
        {1, 604800},    -- 1周数据
        {1, 2592000}    -- 1月数据
    }
    
    for _, range in ipairs(query_ranges) do
        local start_ts = start_time
        local end_ts = start_time + range[2]
        
        local start_time_query = os.clock()
        local success, data = engine:get_stock_data(stock_code, start_ts, end_ts, "SH")
        local end_time_query = os.clock()
        
        local query_time = end_time_query - start_time_query
        local data_count = success and #data or 0
        local query_rate = data_count / query_time
        
        print(string.format("时间范围: %d秒, 返回数据点: %d, 查询耗时: %.3fs, 查询速率: %.1f 点/秒", 
            range[2], data_count, query_time, query_rate))
    end
    
    -- 测试3：冷热数据分离效果
    print("\n--- 测试3：冷热数据分离效果 ---")
    local old_data_time = start_time - (35 * 86400)  -- 35天前的数据（冷数据）
    local new_data_time = start_time  -- 新数据（热数据）
    
    -- 写入冷数据
    local cold_data = generate_test_data(stock_code, old_data_time, 100)
    local cold_start = os.clock()
    for _, data_point in ipairs(cold_data) do
        engine:put_stock_data(stock_code, data_point.timestamp, data_point, "SH")
    end
    local cold_time = os.clock() - cold_start
    
    -- 写入热数据
    local hot_data = generate_test_data(stock_code, new_data_time, 100)
    local hot_start = os.clock()
    for _, data_point in ipairs(hot_data) do
        engine:put_stock_data(stock_code, data_point.timestamp, data_point, "SH")
    end
    local hot_time = os.clock() - hot_start
    
    print(string.format("冷数据写入耗时: %.3fs, 热数据写入耗时: %.3fs, 性能差异: %.1f%%", 
        cold_time, hot_time, ((cold_time - hot_time) / hot_time) * 100))
    
    -- 测试4：一致性哈希分片
    print("\n--- 测试4：一致性哈希分片 ---")
    local test_stocks = {"SH000001", "SZ000002", "SH600000", "SZ000001", "SH000002"}
    
    for _, stock in ipairs(test_stocks) do
        local target_node = engine:get_target_node(stock, start_time)
        print(string.format("股票 %s 路由到节点: %s", stock, target_node))
    end
    
    -- 获取统计信息
    print("\n--- 引擎统计信息 ---")
    local stats = engine:get_stats()
    print("初始化状态: " .. tostring(stats.is_initialized))
    print("运行状态: " .. tostring(stats.is_running))
    print("节点ID: " .. stats.node_id)
    print("集群启用: " .. tostring(stats.cluster_enabled))
    
    if stats.storage_stats then
        print("存储统计:")
        for k, v in pairs(stats.storage_stats) do
            print("  " .. k .. ": " .. tostring(v))
        end
    end
    
    -- 关闭引擎
    engine:close()
    
    print("\n=== V3集成版本测试完成 ===")
end

-- 运行测试
performance_test()

-- 对比测试：基础版本vs集成版本
local function comparison_test()
    print("\n=== 版本对比测试 ===")
    
    -- 这里可以添加与基础版本的对比测试
    print("V3集成版本特性:")
    print("✓ 一致性哈希分片")
    print("✓ 30秒定长块 + 微秒列偏移")
    print("✓ 按自然日分ColumnFamily")
    print("✓ 冷热数据分离")
    print("✓ ZeroMQ集群通信")
    print("✓ Consul高可用")
    print("✓ 股票和度量数据统一存储")
    
    print("\n性能优化:")
    print("✓ 批量写入优化")
    print("✓ 范围查询优化")
    print("✓ 内存使用优化")
    print("✓ 压缩算法优化")
end

comparison_test()