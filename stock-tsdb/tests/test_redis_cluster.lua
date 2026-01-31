#!/usr/bin/env luajit
--
-- Redis集群服务器测试脚本
--

-- 设置Lua路径以使用lib目录下的cjson.so和本地安装的包
package.cpath = package.cpath .. ";../lib/?.so;./lib/?.so;./?.so"

local socket = require "socket"

-- Redis协议构建函数
local function build_redis_command(args)
    local cmd = "*" .. #args .. "\r\n"
    for _, arg in ipairs(args) do
        cmd = cmd .. "$" .. #tostring(arg) .. "\r\n" .. tostring(arg) .. "\r\n"
    end
    return cmd
end

-- 解析Redis响应
local function parse_redis_response(response)
    if not response or #response == 0 then
        return nil, "empty response"
    end
    
    local first_char = response:sub(1, 1)
    
    if first_char == "+" then
        -- 简单字符串
        local line_end = response:find("\r\n")
        if line_end then
            return response:sub(2, line_end - 1)
        end
    elseif first_char == "-" then
        -- 错误
        local line_end = response:find("\r\n")
        if line_end then
            return nil, response:sub(2, line_end - 1)
        end
    elseif first_char == ":" then
        -- 整数
        local line_end = response:find("\r\n")
        if line_end then
            return tonumber(response:sub(2, line_end - 1))
        end
    elseif first_char == "$" then
        -- 批量字符串
        local line_end = response:find("\r\n")
        if not line_end then
            return nil, "incomplete bulk string"
        end
        
        local str_len = tonumber(response:sub(2, line_end - 1))
        if str_len == -1 then
            return nil  -- nil
        end
        
        local data_start = line_end + 2
        local data_end = data_start + str_len - 1
        
        if data_end > #response then
            return nil, "incomplete bulk string data"
        end
        
        return response:sub(data_start, data_end)
    elseif first_char == "*" then
        -- 数组
        local line_end = response:find("\r\n")
        if not line_end then
            return nil, "incomplete array"
        end
        
        local array_len = tonumber(response:sub(2, line_end - 1))
        if array_len == -1 then
            return nil  -- nil
        end
        
        local result = {}
        local pos = line_end + 2
        
        for i = 1, array_len do
            local item, consumed = parse_redis_response(response:sub(pos))
            if not item then
                return nil, "failed to parse array item " .. i
            end
            table.insert(result, item)
            pos = pos + consumed
        end
        
        return result, pos - 1
    end
    
    return nil, "unknown response format"
end

-- 发送Redis命令
local function send_redis_command(host, port, command_args)
    local client = socket.tcp()
    client:settimeout(5)  -- 5秒超时
    
    local success, err = client:connect(host, port)
    if not success then
        return nil, "连接失败: " .. tostring(err)
    end
    
    local cmd = build_redis_command(command_args)
    local bytes_sent, err = client:send(cmd)
    if not bytes_sent then
        client:close()
        return nil, "发送失败: " .. tostring(err)
    end
    
    local response, err = client:receive("*a")  -- 接收所有数据
    client:close()
    
    if not response then
        return nil, "接收失败: " .. tostring(err)
    end
    
    return parse_redis_response(response)
end

-- 测试函数
local function test_ping()
    print("测试 PING 命令...")
    local result, err = send_redis_command("127.0.0.1", 6379, {"PING"})
    if result == "PONG" then
        print("✓ PING 测试通过")
        return true
    else
        print("✗ PING 测试失败: " .. tostring(err))
        return false
    end
end

local function test_echo()
    print("测试 ECHO 命令...")
    local test_msg = "Hello Redis Cluster!"
    local result, err = send_redis_command("127.0.0.1", 6379, {"ECHO", test_msg})
    if result == test_msg then
        print("✓ ECHO 测试通过")
        return true
    else
        print("✗ ECHO 测试失败: " .. tostring(err))
        return false
    end
end

local function test_info()
    print("测试 INFO 命令...")
    local result, err = send_redis_command("127.0.0.1", 6379, {"INFO"})
    if result and type(result) == "string" and result:find("redis_version") then
        print("✓ INFO 测试通过")
        return true
    else
        print("✗ INFO 测试失败: " .. tostring(err))
        return false
    end
end

local function test_cluster_info()
    print("测试 CLUSTER INFO 命令...")
    local result, err = send_redis_command("127.0.0.1", 6379, {"CLUSTER", "INFO"})
    if result and type(result) == "string" and result:find("cluster_state") then
        print("✓ CLUSTER INFO 测试通过")
        return true
    else
        print("✗ CLUSTER INFO 测试失败: " .. tostring(err))
        return false
    end
end

local function test_cluster_nodes()
    print("测试 CLUSTER NODES 命令...")
    local result, err = send_redis_command("127.0.0.1", 6379, {"CLUSTER", "NODES"})
    if result and type(result) == "string" and result:find("myself") then
        print("✓ CLUSTER NODES 测试通过")
        return true
    else
        print("✗ CLUSTER NODES 测试失败: " .. tostring(err))
        return false
    end
end

local function test_ts_commands()
    print("测试 TS.ADD 命令...")
    local timestamp = os.time()
    local value = 123.45
    
    local result, err = send_redis_command("127.0.0.1", 6379, {"TS.ADD", "test_key", timestamp, value})
    if result == "OK" then
        print("✓ TS.ADD 测试通过")
        
        -- 测试 TS.RANGE
        print("测试 TS.RANGE 命令...")
        local start_time = timestamp - 60
        local end_time = timestamp + 60
        
        local range_result, range_err = send_redis_command("127.0.0.1", 6379, {"TS.RANGE", "test_key", start_time, end_time})
        if range_result and type(range_result) == "table" then
            print("✓ TS.RANGE 测试通过")
            return true
        else
            print("✗ TS.RANGE 测试失败: " .. tostring(range_err))
            return false
        end
    else
        print("✗ TS.ADD 测试失败: " .. tostring(err))
        return false
    end
end

local function test_unknown_command()
    print("测试未知命令处理...")
    local result, err = send_redis_command("127.0.0.1", 6379, {"UNKNOWN_COMMAND"})
    if err and err:find("unknown command") then
        print("✓ 未知命令处理测试通过")
        return true
    else
        print("✗ 未知命令处理测试失败: " .. tostring(err))
        return false
    end
end

-- 主测试函数
local function main()
    print("=== Redis集群服务器测试 ===")
    print("")
    
    local tests = {
        test_ping,
        test_echo,
        test_info,
        test_cluster_info,
        test_cluster_nodes,
        test_ts_commands,
        test_unknown_command
    }
    
    local passed = 0
    local total = #tests
    
    for i, test_func in ipairs(tests) do
        local success = test_func()
        if success then
            passed = passed + 1
        end
        print("")
    end
    
    print("=== 测试结果 ===")
    print(string.format("通过: %d/%d", passed, total))
    
    if passed == total then
        print("✓ 所有测试通过！")
        os.exit(0)
    else
        print("✗ 部分测试失败")
        os.exit(1)
    end
end

-- 运行测试
if arg and arg[1] == "--help" then
    print("用法: lua test_redis_cluster.lua")
    print("")
    print("测试Redis集群服务器的功能")
    print("需要先启动Redis集群服务器: make redis-server-daemon")
    os.exit(0)
end

main()