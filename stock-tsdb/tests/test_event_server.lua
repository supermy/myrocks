#!/usr/bin/env luajit

-- 测试事件驱动服务器

-- 添加当前目录到Lua模块路径
package.path = package.path .. ";./lua/?.lua;./?.lua;/usr/local/lib/lua/5.2/?.lua;/usr/local/share/lua/5.2/?.lua"
package.cpath = package.cpath .. ";/usr/local/lib/lua/5.1/?.so;/usr/local/lib/lua/5.2/?.so"

local event_server = require "event_server"

-- 模拟TSDB接口
local MockTSDB = {}
MockTSDB.__index = MockTSDB

function MockTSDB:new()
    local obj = setmetatable({}, MockTSDB)
    obj.data = {}
    return obj
end

function MockTSDB:write_point(key, timestamp, value, data_type, quality)
    if not self.data[key] then
        self.data[key] = {}
    end
    
    table.insert(self.data[key], {
        timestamp = timestamp,
        value = value,
        data_type = data_type,
        quality = quality
    })
    
    return true
end

function MockTSDB:query_range(key, start_time, end_time, data_type)
    if not self.data[key] then
        return nil, "Key not found"
    end
    
    local points = {}
    for _, point in ipairs(self.data[key]) do
        if point.timestamp >= start_time and point.timestamp <= end_time then
            table.insert(points, point)
        end
    end
    
    return points
end

-- 创建测试服务器
local function test_event_server()
    print("=== 测试事件驱动服务器 ===")
    
    -- 创建模拟TSDB
    local mock_tsdb = MockTSDB:new()
    
    -- 创建事件驱动服务器
    local server = event_server.create_server({
        port = 6380,  -- 使用6380端口避免冲突
        bind_addr = "127.0.0.1",
        max_connections = 100,
        tsdb = mock_tsdb
    })
    
    -- 启动服务器（在后台线程中）
    local server_thread = coroutine.create(function()
        print("启动事件驱动服务器...")
        local success, err = server:start()
        if not success then
            print("服务器启动失败: " .. tostring(err))
            return
        end
    end)
    
    -- 启动服务器线程
    coroutine.resume(server_thread)
    
    -- 等待服务器启动
    print("等待服务器启动...")
    os.execute("sleep 2")
    
    -- 测试Redis客户端连接
    print("\n=== 测试Redis客户端连接 ===")
    
    -- 测试PING命令
    local ping_cmd = "*1\r\n$4\r\nPING\r\n"
    print("发送PING命令...")
    
    -- 使用nc测试连接
    local result = os.execute("echo '" .. ping_cmd .. "' | nc -w 1 127.0.0.1 6380")
    
    if result then
        print("PING命令测试成功")
    else
        print("PING命令测试失败")
    end
    
    -- 测试TS.ADD命令
    local ts_add_cmd = "*5\r\n$6\r\nTS.ADD\r\n$8\r\ntest:key\r\n$10\r\n1700000000\r\n$3\r\n100\r\n$3\r\n100\r\n"
    print("\n发送TS.ADD命令...")
    
    result = os.execute("echo '" .. ts_add_cmd .. "' | nc -w 1 127.0.0.1 6380")
    
    if result then
        print("TS.ADD命令测试成功")
    else
        print("TS.ADD命令测试失败")
    end
    
    -- 测试TS.RANGE命令
    local ts_range_cmd = "*4\r\n$8\r\nTS.RANGE\r\n$8\r\ntest:key\r\n$10\r\n1600000000\r\n$10\r\n1800000000\r\n"
    print("\n发送TS.RANGE命令...")
    
    result = os.execute("echo '" .. ts_range_cmd .. "' | nc -w 1 127.0.0.1 6380")
    
    if result then
        print("TS.RANGE命令测试成功")
    else
        print("TS.RANGE命令测试失败")
    end
    
    -- 测试INFO命令
    local info_cmd = "*1\r\n$4\r\nINFO\r\n"
    print("\n发送INFO命令...")
    
    result = os.execute("echo '" .. info_cmd .. "' | nc -w 1 127.0.0.1 6380")
    
    if result then
        print("INFO命令测试成功")
    else
        print("INFO命令测试失败")
    end
    
    -- 停止服务器
    print("\n停止服务器...")
    server:stop()
    
    print("\n=== 测试完成 ===")
end

-- 运行测试
if pcall(test_event_server) then
    print("事件驱动服务器测试通过")
else
    print("事件驱动服务器测试失败")
end