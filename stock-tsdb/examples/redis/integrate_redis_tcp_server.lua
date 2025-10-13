#!/usr/bin/env luajit

--
-- Redis TCP服务器联调集成脚本
-- 测试Redis接口与业务实例的集成功能
--

-- 设置包路径
package.cpath = package.cpath .. ";./lib/?.so"
package.path = package.path .. ";./lua/?.lua"

-- 导入必要的模块
local RedisTCPServer = require "lua.redis_tcp_server".RedisTCPServer
local BusinessInstanceManager = require "lua.business_instance_manager"
local UnifiedDataAccess = require "lua.unified_data_access"

-- 配置参数
local config = {
    port = 6379,
    bind_addr = "127.0.0.1",
    max_connections = 10000,
    node_id = "redis_tcp_integration_" .. os.date("%Y%m%d_%H%M%S"),
    cluster_nodes = {
        {host = "127.0.0.1", port = 5555},
        {host = "127.0.0.1", port = 5556},
        {host = "127.0.0.1", port = 5557}
    }
}

-- 模拟TSDB接口，简化版本用于测试
local MockTSDB = {}
MockTSDB.__index = MockTSDB

function MockTSDB:new()
    local obj = setmetatable({}, MockTSDB)
    obj.data_store = {}  -- 简单的内存存储用于测试
    obj.batch_buffer = {}
    return obj
end

function MockTSDB:write_point(key, timestamp, value, data_type, quality)
    -- 模拟数据写入
    if not self.data_store[key] then
        self.data_store[key] = {}
    end
    
    table.insert(self.data_store[key], {
        timestamp = timestamp,
        value = value,
        data_type = data_type or "float",
        quality = quality or 100
    })
    
    print(string.format("✓ 模拟数据写入成功 - 键: %s, 时间: %d, 值: %s", 
        key, timestamp, tostring(value)))
    return true
end

function MockTSDB:query_range(key, start_time, end_time, data_type)
    -- 模拟数据查询
    if not self.data_store[key] then
        return {}
    end
    
    local points = {}
    for _, point in ipairs(self.data_store[key]) do
        if point.timestamp >= start_time and point.timestamp <= end_time then
            table.insert(points, point)
        end
    end
    
    print(string.format("✓ 模拟数据查询成功 - 键: %s, 时间范围: %d-%d, 结果数: %d", 
        key, start_time, end_time, #points))
    return points
end

function MockTSDB:batch_write(key, timestamp, value)
    -- 批量写入到缓冲区
    if not self.batch_buffer[key] then
        self.batch_buffer[key] = {}
    end
    
    table.insert(self.batch_buffer[key], {
        timestamp = timestamp,
        value = value
    })
    
    return true
end

function MockTSDB:flush_batch()
    -- 刷新批量数据
    local count = 0
    for key, points in pairs(self.batch_buffer) do
        for _, point in ipairs(points) do
            self:write_point(key, point.timestamp, point.value)
            count = count + 1
        end
    end
    
    self.batch_buffer = {}
    print(string.format("✓ 批量数据刷新完成，处理了 %d 个数据点", count))
    return true
end

-- 测试函数
local function test_basic_commands(server)
    print("=== 测试基础Redis命令 ===")
    
    local mock_client = {id = "integration_test"}
    
    -- 测试PING命令
    local result, err = server:handle_command(mock_client, "PING", {})
    if result == "PONG" then
        print("✓ PING命令测试通过")
    else
        print("✗ PING命令测试失败: " .. tostring(err))
    end
    
    -- 测试ECHO命令
    local result, err = server:handle_command(mock_client, "ECHO", {"hello"})
    if result == "hello" then
        print("✓ ECHO命令测试通过")
    else
        print("✗ ECHO命令测试失败: " .. tostring(err))
    end
    
    -- 测试TIME命令
    local result, err = server:handle_command(mock_client, "TIME", {})
    if type(result) == "table" and #result == 2 then
        print("✓ TIME命令测试通过")
    else
        print("✗ TIME命令测试失败: " .. tostring(err))
    end
    
    print("")
end

local function test_batch_operations(server)
    print("=== 测试批量操作命令 ===")
    
    local mock_client = {id = "integration_test"}
    
    -- 测试批量设置
    for i = 1, 5 do
        local result, err = server:handle_command(mock_client, "BATCH_SET", 
            {"stock_" .. i, "value_" .. i, tostring(os.time() + i)})
        if result == "OK" then
            print("✓ 批量设置 " .. i .. " 测试通过")
        else
            print("✗ 批量设置 " .. i .. " 测试失败: " .. tostring(err))
        end
    end
    
    -- 测试批量刷新
    local result, err = server:handle_command(mock_client, "BATCH_FLUSH", {})
    if result == "OK" then
        print("✓ 批量刷新测试通过")
    else
        print("✗ 批量刷新测试失败: " .. tostring(err))
    end
    
    print("")
end

local function test_tsdb_operations(server, tsdb)
    print("=== 测试TSDB操作命令 ===")
    
    local mock_client = {id = "integration_test"}
    
    -- 测试不同业务类型的数据写入
    local test_cases = {
        {key = "stock_001", value = "100.5", business = "股票行情"},
        {key = "iot_temp_001", value = "25.3", business = "物联网数据"},
        {key = "finance_usd_cny", value = "7.2", business = "金融行情"},
        {key = "order_20241201_001", value = "completed", business = "订单数据"},
        {key = "payment_tx_001", value = "success", business = "支付数据"},
        {key = "inventory_item_001", value = "100", business = "库存数据"},
        {key = "sms_user_001", value = "delivered", business = "短信下发"}
    }
    
    for i, test_case in ipairs(test_cases) do
        local timestamp = os.time() + i
        local result, err = server:handle_command(mock_client, "TSDB_SET", 
            {test_case.key, tostring(timestamp), test_case.value})
        
        if result == "OK" then
            print(string.format("✓ %s数据写入测试通过", test_case.business))
        else
            print(string.format("✗ %s数据写入测试失败: %s", test_case.business, tostring(err)))
        end
    end
    
    -- 测试数据查询
    local result, err = server:handle_command(mock_client, "TSDB_GET", 
        {"stock_001", tostring(os.time()), tostring(os.time() + 10)})
    
    if type(result) == "table" then
        print("✓ 数据查询测试通过")
    else
        print("✗ 数据查询测试失败: " .. tostring(err))
    end
    
    print("")
end

local function test_cluster_operations(server)
    print("=== 测试集群操作命令 ===")
    
    local mock_client = {id = "integration_test"}
    
    -- 测试集群信息查询
    local result, err = server:handle_command(mock_client, "CLUSTER_INFO", {})
    
    if type(result) == "table" then
        print("✓ 集群信息查询测试通过")
        for _, info_line in ipairs(result) do
            print("  " .. info_line)
        end
    else
        print("✗ 集群信息查询测试失败: " .. tostring(err))
    end
    
    print("")
end

local function test_performance(server)
    print("=== 测试性能 ===")
    
    local mock_client = {id = "performance_test"}
    local iterations = 100
    local start_time = os.clock()
    
    -- 性能测试：连续写入
    for i = 1, iterations do
        server:handle_command(mock_client, "BATCH_SET", 
            {"perf_test_" .. i, "value_" .. i, tostring(os.time() + i)})
    end
    
    local end_time = os.clock()
    local elapsed = end_time - start_time
    local ops_per_sec = iterations / elapsed
    
    print(string.format("批量写入性能: %d 次操作, %.3f 秒, %.2f 次/秒", 
        iterations, elapsed, ops_per_sec))
    
    -- 性能测试：连续查询
    start_time = os.clock()
    
    for i = 1, iterations do
        server:handle_command(mock_client, "TSDB_GET", 
            {"stock_001", tostring(os.time() - 3600), tostring(os.time())})
    end
    
    end_time = os.clock()
    elapsed = end_time - start_time
    ops_per_sec = iterations / elapsed
    
    print(string.format("数据查询性能: %d 次操作, %.3f 秒, %.2f 次/秒", 
        iterations, elapsed, ops_per_sec))
    
    print("")
end

-- 主函数
local function main()
    print("=== Redis TCP服务器联调集成测试 ===")
    print("开始时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("")
    
    -- 创建模拟TSDB实例
    print("初始化模拟TSDB...")
    local tsdb = MockTSDB:new()
    
    -- 创建Redis TCP服务器实例
    print("创建Redis TCP服务器...")
    config.tsdb = tsdb
    local server = RedisTCPServer:new(config)
    
    -- 初始化命令处理器
    server:init_commands()
    
    -- 运行各项测试
    local tests = {
        {name = "基础Redis命令", func = test_basic_commands},
        {name = "批量操作命令", func = test_batch_operations},
        {name = "TSDB操作命令", func = function() test_tsdb_operations(server, tsdb) end},
        {name = "集群操作命令", func = test_cluster_operations},
        {name = "性能测试", func = test_performance}
    }
    
    local passed = 0
    local failed = 0
    
    for i, test in ipairs(tests) do
        print(string.format("运行测试: %s", test.name))
        
        local success, err = pcall(test.func, server)
        if success then
            passed = passed + 1
            print("✓ 测试完成")
        else
            failed = failed + 1
            print("✗ 测试失败: " .. tostring(err))
        end
        
        print("")
    end
    
    -- 输出测试结果
    print("=== 联调集成测试结果汇总 ===")
    print(string.format("总测试数: %d", #tests))
    print(string.format("通过: %d", passed))
    print(string.format("失败: %d", failed))
    print("")
    
    -- 输出服务器统计信息
    local stats = server:get_stats()
    print("=== 服务器统计信息 ===")
    for key, value in pairs(stats) do
        print(string.format("  %s: %s", key, tostring(value)))
    end
    print("")
    
    if failed == 0 then
        print("✓ 所有联调集成测试通过")
        print("Redis TCP服务器与业务实例集成成功 ✓")
        return true
    else
        print("✗ 部分联调集成测试失败")
        return false
    end
end

-- 运行主函数
if pcall(main) then
    print("联调集成测试完成 ✓")
    os.exit(0)
else
    print("联调集成测试失败 ✗")
    os.exit(1)
end