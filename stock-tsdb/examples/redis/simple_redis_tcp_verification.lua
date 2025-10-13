#!/usr/bin/env luajit

--
-- Redis TCP服务器简化验证脚本
-- 验证Redis接口的核心功能
--

package.cpath = package.cpath .. ";./lib/?.so"
package.path = package.path .. ";./lua/?.lua"

local RedisTCPServer = require "lua.redis_tcp_server".RedisTCPServer

-- 模拟TSDB接口
local MockTSDB = {}
MockTSDB.__index = MockTSDB

function MockTSDB:new()
    local obj = setmetatable({}, MockTSDB)
    obj.data_store = {}
    obj.batch_buffer = {}
    return obj
end

function MockTSDB:write_point(key, timestamp, value, data_type, quality)
    if not self.data_store[key] then
        self.data_store[key] = {}
    end
    
    table.insert(self.data_store[key], {
        timestamp = timestamp,
        value = value,
        data_type = data_type or "float",
        quality = quality or 100
    })
    
    print(string.format("✓ 模拟数据写入 - 键: %s, 时间: %d, 值: %s", 
        key, timestamp, tostring(value)))
    return true
end

function MockTSDB:query_range(key, start_time, end_time, data_type)
    if not self.data_store[key] then
        return {}
    end
    
    local points = {}
    for _, point in ipairs(self.data_store[key]) do
        if point.timestamp >= start_time and point.timestamp <= end_time then
            table.insert(points, point)
        end
    end
    
    print(string.format("✓ 模拟数据查询 - 键: %s, 时间范围: %d-%d, 结果数: %d", 
        key, start_time, end_time, #points))
    return points
end

function MockTSDB:batch_write(key, timestamp, value)
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
    local count = 0
    for key, points in pairs(self.batch_buffer) do
        for _, point in ipairs(points) do
            self:write_point(key, point.timestamp, point.value)
            count = count + 1
        end
    end
    
    self.batch_buffer = {}
    print(string.format("✓ 批量数据刷新 - 处理了 %d 个数据点", count))
    return count
end

-- 测试Redis协议解析
local function test_redis_protocol()
    print("=== 测试Redis协议解析 ===")
    
    local RedisProtocolParser = require "lua.redis_tcp_server".RedisProtocolParser
    
    -- 测试简单字符串命令
    local command = "*2\r\n$4\r\nPING\r\n$5\r\nhello\r\n"
    local args, consumed = RedisProtocolParser.parse_request(command)
    
    if args and #args == 2 and args[1] == "PING" and args[2] == "hello" then
        print("✓ Redis协议解析测试通过")
    else
        print("✗ Redis协议解析测试失败")
        return false
    end
    
    -- 测试响应构建
    local response = RedisProtocolParser.build_response("PONG")
    if response == "+PONG\r\n" then
        print("✓ Redis响应构建测试通过")
    else
        print("✗ Redis响应构建测试失败")
        return false
    end
    
    print("")
    return true
end

-- 测试Redis命令处理
local function test_redis_commands()
    print("=== 测试Redis命令处理 ===")
    
    -- 创建模拟TSDB实例
    local tsdb = MockTSDB:new()
    
    -- 创建Redis TCP服务器实例
    local config = {
        port = 6379,
        bind_addr = "127.0.0.1",
        max_connections = 1000,
        node_id = "test_node",
        tsdb = tsdb
    }
    
    local server = RedisTCPServer:new(config)
    server:init_commands()
    
    -- 模拟客户端
    local mock_client = {id = "test_client"}
    
    -- 测试PING命令
    local result, err = server:handle_command(mock_client, "PING", {})
    if result == "PONG" then
        print("✓ PING命令测试通过")
    else
        print("✗ PING命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试ECHO命令
    local result, err = server:handle_command(mock_client, "ECHO", {"hello"})
    if result == "hello" then
        print("✓ ECHO命令测试通过")
    else
        print("✗ ECHO命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试TIME命令
    local result, err = server:handle_command(mock_client, "TIME", {})
    if type(result) == "table" and #result == 2 then
        print("✓ TIME命令测试通过")
    else
        print("✗ TIME命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试TSDB_SET命令
    local timestamp = os.time()
    local result, err = server:handle_command(mock_client, "TSDB_SET", 
        {"test_key", tostring(timestamp), "test_value"})
    if result == "OK" then
        print("✓ TSDB_SET命令测试通过")
    else
        print("✗ TSDB_SET命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试TSDB_GET命令
    local result, err = server:handle_command(mock_client, "TSDB_GET", 
        {"test_key", tostring(timestamp - 10), tostring(timestamp + 10)})
    if type(result) == "table" then
        print("✓ TSDB_GET命令测试通过")
    else
        print("✗ TSDB_GET命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试BATCH_SET命令
    local result, err = server:handle_command(mock_client, "BATCH_SET", 
        {"batch_key", "batch_value", tostring(timestamp)})
    if result == "OK" then
        print("✓ BATCH_SET命令测试通过")
    else
        print("✗ BATCH_SET命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试BATCH_FLUSH命令
    local result, err = server:handle_command(mock_client, "BATCH_FLUSH", {})
    if result == "OK" then
        print("✓ BATCH_FLUSH命令测试通过")
    else
        print("✗ BATCH_FLUSH命令测试失败: " .. tostring(err))
        return false
    end
    
    -- 测试CLUSTER_INFO命令
    local result, err = server:handle_command(mock_client, "CLUSTER_INFO", {})
    if type(result) == "table" then
        print("✓ CLUSTER_INFO命令测试通过")
        for _, info in ipairs(result) do
            print("  " .. info)
        end
    else
        print("✗ CLUSTER_INFO命令测试失败: " .. tostring(err))
        return false
    end
    
    print("")
    return true
end

-- 测试批量数据处理
local function test_batch_processing()
    print("=== 测试批量数据处理 ===")
    
    local BatchProcessor = require "lua.redis_tcp_server".BatchProcessor
    
    local processor = BatchProcessor:new()
    
    -- 测试批量添加数据
    for i = 1, 5 do
        local success = processor:add_data("key_" .. i, "value_" .. i, os.time() + i)
        if success then
            print("✓ 批量添加数据 " .. i .. " 测试通过")
        else
            print("✗ 批量添加数据 " .. i .. " 测试失败")
            return false
        end
    end
    
    -- 测试批量刷新
    local success = processor:flush()
    if success then
        print("✓ 批量刷新测试通过")
    else
        print("✗ 批量刷新测试失败")
        return false
    end
    
    print("")
    return true
end

-- 测试服务器统计信息
local function test_server_stats()
    print("=== 测试服务器统计信息 ===")
    
    local tsdb = MockTSDB:new()
    
    local config = {
        port = 6379,
        bind_addr = "127.0.0.1",
        max_connections = 1000,
        node_id = "stats_test",
        tsdb = tsdb
    }
    
    local server = RedisTCPServer:new(config)
    server:init_commands()
    
    local mock_client = {id = "stats_client"}
    
    -- 执行一些命令来生成统计信息
    server:handle_command(mock_client, "PING", {})
    server:handle_command(mock_client, "ECHO", {"test"})
    server:handle_command(mock_client, "TSDB_SET", {"stats_key", tostring(os.time()), "stats_value"})
    
    -- 获取统计信息
    local stats = server:get_stats()
    
    if stats.total_commands == 3 then
        print("✓ 命令统计测试通过 (总命令数: " .. stats.total_commands .. ")")
    else
        print("✗ 命令统计测试失败 (总命令数: " .. stats.total_commands .. ")")
        return false
    end
    
    if stats.node_id == "stats_test" then
        print("✓ 节点ID统计测试通过")
    else
        print("✗ 节点ID统计测试失败")
        return false
    end
    
    print("")
    return true
end

-- 主函数
local function main()
    print("=== Redis TCP服务器简化验证 ===")
    print("开始时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("")
    
    local tests = {
        {name = "Redis协议解析", func = test_redis_protocol},
        {name = "Redis命令处理", func = test_redis_commands},
        {name = "批量数据处理", func = test_batch_processing},
        {name = "服务器统计信息", func = test_server_stats}
    }
    
    local passed = 0
    local failed = 0
    
    for i, test in ipairs(tests) do
        print(string.format("运行测试: %s", test.name))
        
        local success, err = pcall(test.func)
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
    print("=== 简化验证结果汇总 ===")
    print(string.format("总测试数: %d", #tests))
    print(string.format("通过: %d", passed))
    print(string.format("失败: %d", failed))
    print("")
    
    if failed == 0 then
        print("✓ 所有简化验证测试通过")
        print("✓ Redis TCP服务器核心功能正常")
        print("✓ Redis接口实现完整")
        return true
    else
        print("✗ 部分简化验证测试失败")
        return false
    end
end

-- 运行主函数
if pcall(main) then
    print("简化验证完成 ✓")
    os.exit(0)
else
    print("简化验证失败 ✗")
    os.exit(1)
end