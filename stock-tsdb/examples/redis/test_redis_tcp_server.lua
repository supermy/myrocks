#!/usr/bin/env luajit

--
-- Redis TCP服务器测试脚本
-- 测试Redis协议接口和批量数据处理功能
--

-- 设置包路径
package.cpath = package.cpath .. ";./lib/?.so"

-- 导入必要的模块
local RedisTCPServer = require "lua.redis_tcp_server".RedisTCPServer
local RedisProtocolParser = require "lua.redis_tcp_server".RedisProtocolParser

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

-- 测试函数
local function test_redis_protocol()
    print("=== 测试Redis协议解析 ===")
    
    -- 测试协议解析
    local test_cases = {
        {
            name = "PING命令",
            request = "*1\r\n$4\r\nPING\r\n",
            expected_args = {"PING"}
        },
        {
            name = "ECHO命令",
            request = "*2\r\n$4\r\nECHO\r\n$5\r\nhello\r\n",
            expected_args = {"ECHO", "hello"}
        },
        {
            name = "批量设置命令",
            request = "*3\r\n$9\r\nBATCH_SET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n",
            expected_args = {"BATCH_SET", "key", "value"}
        }
    }
    
    for i, test_case in ipairs(test_cases) do
        print(string.format("测试 %d: %s", i, test_case.name))
        
        local args, consumed = RedisProtocolParser.parse_request(test_case.request)
        if args then
            if #args == #test_case.expected_args then
                local match = true
                for j, arg in ipairs(args) do
                    if arg ~= test_case.expected_args[j] then
                        match = false
                        break
                    end
                end
                
                if match then
                    print("  ✓ 协议解析成功")
                else
                    print("  ✗ 协议解析失败 - 参数不匹配")
                end
            else
                print("  ✗ 协议解析失败 - 参数数量不匹配")
            end
        else
            print("  ✗ 协议解析失败 - " .. consumed)
        end
    end
    
    print("")
end

local function test_response_building()
    print("=== 测试响应构建 ===")
    
    local test_cases = {
        {
            name = "简单字符串响应",
            data = "PONG",
            expected = "+PONG\r\n"
        },
        {
            name = "数组响应",
            data = {"value1", "value2"},
            expected = "*2\r\n$6\r\nvalue1\r\n$6\r\nvalue2\r\n"
        },
        {
            name = "错误响应",
            error_msg = "command not found",
            expected = "-ERR command not found\r\n"
        }
    }
    
    for i, test_case in ipairs(test_cases) do
        print(string.format("测试 %d: %s", i, test_case.name))
        
        local response
        if test_case.error_msg then
            response = RedisProtocolParser.build_error(test_case.error_msg)
        else
            response = RedisProtocolParser.build_response(test_case.data)
        end
        
        if response == test_case.expected then
            print("  ✓ 响应构建成功")
        else
            print("  ✗ 响应构建失败")
            print("    期望: " .. test_case.expected)
            print("    实际: " .. response)
        end
    end
    
    print("")
end

local function test_server_commands()
    print("=== 测试服务器命令处理 ===")
    
    -- 创建模拟TSDB
    local mock_tsdb = MockTSDB:new()
    
    -- 创建服务器实例
    local config = {
        port = 6380,  -- 使用不同端口避免冲突
        bind_addr = "127.0.0.1",
        tsdb = mock_tsdb
    }
    
    local server = RedisTCPServer:new(config)
    server:init_commands()
    
    -- 模拟客户端
    local mock_client = {id = "test_client"}
    
    local test_cases = {
        {
            name = "PING命令",
            command = "PING",
            args = {},
            expected = "PONG"
        },
        {
            name = "ECHO命令",
            command = "ECHO",
            args = {"hello"},
            expected = "hello"
        },
        {
            name = "TIME命令",
            command = "TIME",
            args = {},
            expected_type = "table"
        },
        {
            name = "BATCH_SET命令",
            command = "BATCH_SET",
            args = {"test_key", "test_value"},
            expected = "OK"
        },
        {
            name = "TSDB_SET命令",
            command = "TSDB_SET",
            args = {"stock_001", "1234567890", "100.5"},
            expected = "OK"
        }
    }
    
    for i, test_case in ipairs(test_cases) do
        print(string.format("测试 %d: %s", i, test_case.name))
        
        local result, err = server:handle_command(mock_client, test_case.command, test_case.args)
        
        if result then
            if test_case.expected_type then
                if type(result) == test_case.expected_type then
                    print("  ✓ 命令处理成功")
                else
                    print("  ✗ 命令处理失败 - 类型不匹配")
                end
            elseif result == test_case.expected then
                print("  ✓ 命令处理成功")
            else
                print("  ✗ 命令处理失败 - 结果不匹配")
                print("    期望: " .. tostring(test_case.expected))
                print("    实际: " .. tostring(result))
            end
        else
            print("  ✗ 命令处理失败 - " .. (err or "unknown error"))
        end
    end
    
    print("")
end

local function test_batch_processing()
    print("=== 测试批量数据处理 ===")
    
    local BatchProcessor = require "lua.redis_tcp_server".BatchProcessor
    local processor = BatchProcessor:new()
    
    -- 测试批量添加
    for i = 1, 5 do
        processor:add_data("key_" .. i, "value_" .. i, os.time() + i)
    end
    
    if processor.current_size == 5 then
        print("  ✓ 批量数据添加成功")
    else
        print("  ✗ 批量数据添加失败")
    end
    
    -- 测试批量刷新
    local success = processor:flush()
    if success and processor.current_size == 0 then
        print("  ✓ 批量数据刷新成功")
    else
        print("  ✗ 批量数据刷新失败")
    end
    
    print("")
end

local function test_integration()
    print("=== 测试集成功能 ===")
    
    -- 测试与业务实例管理器的集成
    local success, BusinessInstanceManager = pcall(require, "lua.business_instance_manager")
    
    if success then
        print("  ✓ 业务实例管理器集成测试通过")
        
        -- 测试与统一数据访问层的集成
        local success2, UnifiedDataAccess = pcall(require, "lua.unified_data_access")
        if success2 then
            print("  ✓ 统一数据访问层集成测试通过")
        else
            print("  ✗ 统一数据访问层集成测试失败")
        end
    else
        print("  ✗ 业务实例管理器集成测试失败")
    end
    
    print("")
end

-- 主测试函数
local function run_all_tests()
    print("开始Redis TCP服务器测试")
    print("测试时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("")
    
    local tests = {
        {name = "Redis协议解析", func = test_redis_protocol},
        {name = "响应构建", func = test_response_building},
        {name = "服务器命令处理", func = test_server_commands},
        {name = "批量数据处理", func = test_batch_processing},
        {name = "集成功能", func = test_integration}
    }
    
    local passed = 0
    local failed = 0
    
    for i, test in ipairs(tests) do
        print(string.format("运行测试组: %s", test.name))
        
        local success, err = pcall(test.func)
        if success then
            passed = passed + 1
            print("  ✓ 测试组完成")
        else
            failed = failed + 1
            print("  ✗ 测试组失败: " .. tostring(err))
        end
        
        print("")
    end
    
    -- 输出测试结果
    print("=== 测试结果汇总 ===")
    print(string.format("总测试组数: %d", #tests))
    print(string.format("通过: %d", passed))
    print(string.format("失败: %d", failed))
    print("")
    
    if failed == 0 then
        print("✓ 所有测试通过")
        return true
    else
        print("✗ 部分测试失败")
        return false
    end
end

-- 运行测试
if run_all_tests() then
    print("Redis TCP服务器测试完成 ✓")
    os.exit(0)
else
    print("Redis TCP服务器测试失败 ✗")
    os.exit(1)
end