#!/usr/bin/env luajit

-- V3基础版本测试脚本
package.path = package.path .. ";./?.lua;./lua/?.lua"

local ffi = require("ffi")
local V3StorageEngine = require("tsdb_storage_engine_v3")

-- 创建V3基础版本存储引擎
local function create_v3_engine()
    local config = {
        data_dir = "./test_v3_basic",
        block_size = 30,  -- 30秒块
        enable_compression = true,
        compression_type = "lz4"
    }
    
    local engine = V3StorageEngine:new(config)
    local success, err = engine:initialize()
    
    if not success then
        print("V3基础版本引擎初始化失败: " .. tostring(err))
        return nil
    end
    
    return engine
end

-- 生成测试数据
local function generate_test_data(stock_code, num_points, start_time)
    local data = {}
    local current_time = start_time or os.time()
    
    for i = 1, num_points do
        table.insert(data, {
            timestamp = current_time + i,
            open = 100 + math.random(-10, 10),
            high = 105 + math.random(-5, 15),
            low = 95 + math.random(-5, 10),
            close = 100 + math.random(-8, 8),
            volume = math.random(1000, 10000),
            amount = math.random(100000, 1000000)
        })
    end
    
    return data
end

-- 性能测试函数
local function performance_test()
    print("=== V3基础版本性能测试 ===")
    
    -- 创建引擎
    local engine = create_v3_engine()
    if not engine then
        return
    end
    
    print("[V3基础引擎] 初始化完成")
    
    -- 测试1：批量写入性能
    print("\n--- 测试1：批量写入性能 ---")
    local batch_sizes = {100, 500, 1000, 2000, 5000}
    local stock_code = "SH000001"
    
    for _, batch_size in ipairs(batch_sizes) do
        local test_data = generate_test_data(stock_code, batch_size, os.time())
        
        local start_time = os.clock()
        local success_count = 0
        
        for i, data_point in ipairs(test_data) do
            local success, err = engine:write_point(stock_code, data_point.timestamp, data_point.close, data_point)
            if success then
                success_count = success_count + 1
            end
        end
        
        local end_time = os.clock()
        local elapsed = end_time - start_time
        local rate = success_count / elapsed
        
        print(string.format("批量大小: %d, 成功写入: %d, 耗时: %.3fs, 写入速率: %.1f 点/秒", 
              batch_size, success_count, elapsed, rate))
    end
    
    -- 测试2：范围查询性能
    print("\n--- 测试2：范围查询性能 ---")
    local time_ranges = {3600, 86400, 604800, 2592000}  -- 1小时, 1天, 1周, 1月
    local base_time = os.time() - 86400  -- 使用昨天的时间作为基准
    
    for _, time_range in ipairs(time_ranges) do
        local start_ts = base_time - time_range
        local end_ts = base_time + time_range
        
        local start_time = os.clock()
        local success, results = engine:read_point(stock_code, start_ts, end_ts, {})
        local end_time = os.clock()
        
        local elapsed = end_time - start_time
        local num_points = results and #results or 0
        local rate = elapsed > 0 and (num_points / elapsed) or 0
        
        print(string.format("时间范围: %d秒, 返回数据点: %d, 查询耗时: %.3fs, 查询速率: %.1f 点/秒", 
              time_range, num_points, elapsed, rate))
    end
    
    -- 测试3：内存使用统计
    print("\n--- 测试3：内存使用统计 ---")
    if engine.get_stats then
        local stats = engine:get_stats()
        print("写入总数: " .. tostring(stats.write_count or "N/A"))
        print("读取总数: " .. tostring(stats.read_count or "N/A"))
        print("内存使用: " .. tostring(stats.memory_usage or "N/A"))
    else
        print("统计信息不可用")
    end
    
    -- 关闭引擎
    print("\n--- 关闭引擎 ---")
    if engine.close then
        local success, err = pcall(function() engine:close() end)
        if success then
            print("V3基础引擎已正常关闭")
        else
            print("关闭引擎时出错: " .. tostring(err))
        end
    end
    
    print("\n=== V3基础版本测试完成 ===")
end

-- 运行测试
performance_test()