#!/usr/bin/env luajit

--
-- Redis TCP服务器集成验证脚本
-- 验证Redis接口的实际运行和客户端连接
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
    return count
end

-- 测试Redis客户端连接
local function test_redis_client_connection()
    print("=== 测试Redis客户端连接 ===")
    
    -- 使用socket库创建TCP客户端
    local socket = require("socket")
    
    local client, err = socket.connect("127.0.0.1", 6379)
    if not client then
        print("✗ 无法连接到Redis TCP服务器: " .. tostring(err))
        return false
    end
    
    client:settimeout(5)  -- 5秒超时
    
    -- 测试PING命令
    local ping_command = "*1\r\n$4\r\nPING\r\n"
    local bytes_sent, err = client:send(ping_command)
    if not bytes_sent then
        print("✗ 发送PING命令失败: " .. tostring(err))
        client:close()
        return false
    end
    
    local response, err = client:receive()
    if not response then
        print("✗ 接收PING响应失败: " .. tostring(err))
        client:close()
        return false
    end
    
    if response == "+PONG" then
        print("✓ PING命令测试通过")
    else
        print("✗ PING响应不正确: " .. response)
        client:close()
        return false
    end
    
    -- 测试SET命令（使用自定义TSDB_SET）
    local timestamp = os.time()
    local set_command = string.format("*4\r\n$7\r\nTSDB_SET\r\n$8\r\ntest_key\r\n$%d\r\n%d\r\n$5\r\nvalue\r\n", 
        #tostring(timestamp), timestamp)
    
    bytes_sent, err = client:send(set_command)
    if not bytes_sent then
        print("✗ 发送TSDB_SET命令失败: " .. tostring(err))
        client:close()
        return false
    end
    
    response, err = client:receive()
    if not response then
        print("✗ 接收TSDB_SET响应失败: " .. tostring(err))
        client:close()
        return false
    end
    
    if response == "+OK" then
        print("✓ TSDB_SET命令测试通过")
    else
        print("✗ TSDB_SET响应不正确: " .. response)
        client:close()
        return false
    end
    
    -- 测试GET命令（使用自定义TSDB_GET）
    local get_command = string.format("*4\r\n$7\r\nTSDB_GET\r\n$8\r\ntest_key\r\n$%d\r\n%d\r\n$%d\r\n%d\r\n", 
        #tostring(timestamp - 10), timestamp - 10, #tostring(timestamp + 10), timestamp + 10)
    
    bytes_sent, err = client:send(get_command)
    if not bytes_sent then
        print("✗ 发送TSDB_GET命令失败: " .. tostring(err))
        client:close()
        return false
    end
    
    response, err = client:receive()
    if not response then
        print("✗ 接收TSDB_GET响应失败: " .. tostring(err))
        client:close()
        return false
    end
    
    -- TSDB_GET应该返回数组响应
    if response:sub(1, 1) == "*" then
        print("✓ TSDB_GET命令测试通过")
    else
        print("✗ TSDB_GET响应不正确: " .. response)
        client:close()
        return false
    end
    
    client:close()
    print("✓ 所有Redis客户端连接测试通过")
    return true
end

-- 主函数
local function main()
    print("=== Redis TCP服务器集成验证 ===")
    print("开始时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("")
    
    -- 创建模拟TSDB实例
    print("初始化模拟TSDB...")
    local tsdb = MockTSDB:new()
    
    -- 创建Redis TCP服务器配置
    local config = {
        port = 6379,
        bind_addr = "127.0.0.1",
        max_connections = 1000,
        node_id = "integration_verify_" .. os.date("%Y%m%d_%H%M%S"),
        tsdb = tsdb,
        cluster_nodes = {
            {host = "127.0.0.1", port = 5555}
        }
    }
    
    -- 创建Redis TCP服务器实例
    print("创建Redis TCP服务器...")
    local server = RedisTCPServer:new(config)
    
    -- 初始化命令处理器
    server:init_commands()
    
    -- 启动服务器（非阻塞模式）
    print("启动Redis TCP服务器...")
    local success, err = server:start(false)  -- 非阻塞模式
    
    if not success then
        print("✗ 服务器启动失败: " .. tostring(err))
        return false
    end
    
    print("✓ Redis TCP服务器启动成功")
    
    -- 等待服务器完全启动
    print("等待服务器启动完成...")
    for i = 1, 10 do
        if server.running then
            break
        end
        socket = require("socket")
        socket.sleep(0.5)
    end
    
    if not server.running then
        print("✗ 服务器启动超时")
        server:stop()
        return false
    end
    
    -- 运行客户端连接测试
    print("")
    local client_test_success = test_redis_client_connection()
    
    -- 停止服务器
    print("")
    print("停止Redis TCP服务器...")
    server:stop()
    
    -- 输出服务器统计信息
    print("")
    print("=== 服务器统计信息 ===")
    local stats = server:get_stats()
    for key, value in pairs(stats) do
        print(string.format("  %s: %s", key, tostring(value)))
    end
    
    print("")
    if client_test_success then
        print("✓ Redis TCP服务器集成验证成功")
        print("✓ Redis接口功能正常")
        print("✓ 客户端连接测试通过")
        return true
    else
        print("✗ Redis TCP服务器集成验证失败")
        return false
    end
end

-- 运行主函数
if pcall(main) then
    print("集成验证完成 ✓")
    os.exit(0)
else
    print("集成验证失败 ✗")
    os.exit(1)
end