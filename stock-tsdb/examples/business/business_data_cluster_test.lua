#!/usr/bin/env luajit

--
-- 业务数据Redis+TSDB集群综合测试脚本
-- 测试股票行情、IOT、金融行情、订单、支付、库存、短信下发等7个业务场景
--

package.cpath = package.cpath .. ";./lib/?.so"
package.path = package.path .. ";./lua/?.lua"

local RedisTCPServer = require "lua.redis_tcp_server".RedisTCPServer
local BusinessInstanceManager = require "lua.business_instance_manager"
local UnifiedDataAccess = require "lua.unified_data_access"

-- 模拟TSDB接口
local MockTSDB = {}
MockTSDB.__index = MockTSDB

function MockTSDB:new()
    local obj = setmetatable({}, MockTSDB)
    obj.data_store = {}
    obj.batch_buffer = {}
    obj.stats = {
        write_count = 0,
        read_count = 0,
        batch_count = 0
    }
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
    
    self.stats.write_count = self.stats.write_count + 1
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
    
    self.stats.read_count = self.stats.read_count + 1
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
    
    self.stats.batch_count = self.stats.batch_count + 1
    return true
end

function MockTSDB:flush_batch()
    for key, points in pairs(self.batch_buffer) do
        if not self.data_store[key] then
            self.data_store[key] = {}
        end
        
        for _, point in ipairs(points) do
            table.insert(self.data_store[key], {
                timestamp = point.timestamp,
                value = point.value,
                data_type = "float",
                quality = 100
            })
        end
    end
    
    self.batch_buffer = {}
    return true
end

function MockTSDB:get_stats()
    return self.stats
end

-- 业务测试数据定义 - 基于Redis哈希的优化版本
local BUSINESS_TEST_DATA = {
    -- 股票行情数据 - 使用哈希存储多维度数据
    stock = {
        prefix = "stock:",
        hash_fields = {"price", "volume", "change", "high", "low", "open", "prev_close"},
        data = {
            {
                key = "stock:000001", 
                timestamp = os.time(), 
                hash_data = {
                    price = "10.50", 
                    volume = "1000000", 
                    change = "+0.25", 
                    high = "10.75", 
                    low = "10.20", 
                    open = "10.30", 
                    prev_close = "10.25"
                }
            },
            {
                key = "stock:000002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    price = "15.20", 
                    volume = "500000", 
                    change = "-0.10", 
                    high = "15.50", 
                    low = "15.00", 
                    open = "15.30", 
                    prev_close = "15.30"
                }
            },
            {
                key = "stock:000003", 
                timestamp = os.time() + 2, 
                hash_data = {
                    price = "8.75", 
                    volume = "750000", 
                    change = "+0.05", 
                    high = "8.80", 
                    low = "8.65", 
                    open = "8.70", 
                    prev_close = "8.70"
                }
            }
        }
    },
    
    -- IOT传感器数据 - 哈希存储传感器多维度信息
    iot = {
        prefix = "iot:",
        hash_fields = {"temperature", "humidity", "pressure", "voltage", "status", "battery"},
        data = {
            {
                key = "iot:sensor:001", 
                timestamp = os.time(), 
                hash_data = {
                    temperature = "25.6", 
                    humidity = "65.2", 
                    pressure = "1013.25", 
                    voltage = "220.5", 
                    status = "normal", 
                    battery = "85"
                }
            },
            {
                key = "iot:sensor:002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    temperature = "23.8", 
                    humidity = "68.5", 
                    pressure = "1012.80", 
                    voltage = "219.8", 
                    status = "warning", 
                    battery = "72"
                }
            }
        }
    },
    
    -- 金融行情数据 - 哈希存储汇率和商品价格
    finance = {
        prefix = "finance:",
        hash_fields = {"bid", "ask", "high", "low", "change", "volume"},
        data = {
            {
                key = "finance:usd:cny", 
                timestamp = os.time(), 
                hash_data = {
                    bid = "7.2450", 
                    ask = "7.2550", 
                    high = "7.2600", 
                    low = "7.2400", 
                    change = "+0.0010", 
                    volume = "1000000000"
                }
            },
            {
                key = "finance:gold", 
                timestamp = os.time() + 1, 
                hash_data = {
                    bid = "1979.50", 
                    ask = "1981.50", 
                    high = "1985.00", 
                    low = "1975.00", 
                    change = "-2.50", 
                    volume = "50000"
                }
            }
        }
    },
    
    -- 订单数据 - 哈希存储订单详细信息
    order = {
        prefix = "order:",
        hash_fields = {"amount", "status", "user_id", "product_id", "quantity", "create_time"},
        data = {
            {
                key = "order:001", 
                timestamp = os.time(), 
                hash_data = {
                    amount = "1000.00", 
                    status = "pending", 
                    user_id = "user_001", 
                    product_id = "product_001", 
                    quantity = "2", 
                    create_time = tostring(os.time())
                }
            },
            {
                key = "order:002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    amount = "2500.50", 
                    status = "completed", 
                    user_id = "user_002", 
                    product_id = "product_002", 
                    quantity = "5", 
                    create_time = tostring(os.time() + 1)
                }
            }
        }
    },
    
    -- 支付数据 - 哈希存储支付详细信息
    payment = {
        prefix = "payment:",
        hash_fields = {"amount", "status", "method", "user_id", "order_id", "transaction_id"},
        data = {
            {
                key = "payment:001", 
                timestamp = os.time(), 
                hash_data = {
                    amount = "500.00", 
                    status = "success", 
                    method = "alipay", 
                    user_id = "user_001", 
                    order_id = "order_001", 
                    transaction_id = "txn_001"
                }
            },
            {
                key = "payment:002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    amount = "1200.50", 
                    status = "failed", 
                    method = "wechat", 
                    user_id = "user_002", 
                    order_id = "order_002", 
                    transaction_id = "txn_002"
                }
            }
        }
    },
    
    -- 库存数据 - 哈希存储库存详细信息
    inventory = {
        prefix = "inventory:",
        hash_fields = {"quantity", "warehouse", "sku", "category", "last_updated", "min_stock"},
        data = {
            {
                key = "inventory:product:001", 
                timestamp = os.time(), 
                hash_data = {
                    quantity = "1000", 
                    warehouse = "warehouse_001", 
                    sku = "SKU001", 
                    category = "electronics", 
                    last_updated = tostring(os.time()), 
                    min_stock = "100"
                }
            },
            {
                key = "inventory:product:002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    quantity = "500", 
                    warehouse = "warehouse_002", 
                    sku = "SKU002", 
                    category = "clothing", 
                    last_updated = tostring(os.time() + 1), 
                    min_stock = "50"
                }
            }
        }
    },
    
    -- 短信下发数据 - 哈希存储短信详细信息
    sms = {
        prefix = "sms:",
        hash_fields = {"status", "phone", "content", "send_time", "template_id", "retry_count"},
        data = {
            {
                key = "sms:delivery:001", 
                timestamp = os.time(), 
                hash_data = {
                    status = "delivered", 
                    phone = "13800138000", 
                    content = "验证码：123456", 
                    send_time = tostring(os.time()), 
                    template_id = "template_001", 
                    retry_count = "0"
                }
            },
            {
                key = "sms:delivery:002", 
                timestamp = os.time() + 1, 
                hash_data = {
                    status = "failed", 
                    phone = "13900139000", 
                    content = "订单确认通知", 
                    send_time = tostring(os.time() + 1), 
                    template_id = "template_002", 
                    retry_count = "2"
                }
            }
        }
    }
}

-- 模拟客户端对象
local mock_client = { id = "test_client_001" }

-- 测试函数
local function test_basic_redis_commands(server)
    print("测试基础Redis命令...")
    
    -- 测试PING命令
    local response = server:handle_command(mock_client, "PING", {})
    assert(response == "PONG", "PING命令失败: " .. tostring(response))
    
    -- 测试ECHO命令
    response = server:handle_command(mock_client, "ECHO", {"hello world"})
    assert(response == "hello world", "ECHO命令失败: " .. tostring(response))
    
    -- 测试TIME命令
    response = server:handle_command(mock_client, "TIME", {})
    assert(type(response) == "table" and #response == 2, "TIME命令失败: " .. tostring(response))
    
    print("✓ 基础Redis命令测试通过")
    return true
end

local function test_business_data_operations(server, business_type)
    local business = BUSINESS_TEST_DATA[business_type]
    print("测试" .. business_type .. "业务数据操作...")
    
    -- 测试HASH_SET命令 - 使用专门的哈希数据结构
    for _, data in ipairs(business.data) do
        -- 将哈希数据序列化为JSON字符串存储
        local hash_json = require("cjson").encode(data.hash_data)
        local response = server:handle_command(mock_client, "HASH_SET", {
            data.key, 
            tostring(data.timestamp), 
            hash_json
        })
        assert(response == "OK", 
            business_type .. " HASH_SET失败: " .. tostring(response))
    end
    
    -- 测试HASH_GET命令
    for _, data in ipairs(business.data) do
        local start_time = data.timestamp - 10
        local end_time = data.timestamp + 10
        local response = server:handle_command(mock_client, "HASH_GET", {
            data.key, 
            tostring(start_time), 
            tostring(end_time)
        })
        assert(type(response) == "table", 
            business_type .. " HASH_GET失败: " .. tostring(response))
        
        -- 验证返回的数据包含哈希字段
        if #response > 0 then
            local point_data = require("cjson").decode(response[2])
            assert(type(point_data) == "table", "返回数据不是有效的哈希结构")
            
            -- 验证必要的哈希字段存在
            for _, field in ipairs(business.hash_fields) do
                assert(point_data[field] ~= nil, "缺少哈希字段: " .. field)
            end
        end
    end
    
    -- 测试HASH_FIELDS命令 - 查询特定字段
    for _, data in ipairs(business.data) do
        local start_time = data.timestamp - 10
        local end_time = data.timestamp + 10
        
        -- 选择前3个字段进行测试
        local test_fields = {}
        for i = 1, math.min(3, #business.hash_fields) do
            table.insert(test_fields, business.hash_fields[i])
        end
        
        local args = {data.key, tostring(start_time), tostring(end_time)}
        for _, field in ipairs(test_fields) do
            table.insert(args, field)
        end
        
        local response = server:handle_command(mock_client, "HASH_FIELDS", args)
        assert(type(response) == "table", 
            business_type .. " HASH_FIELDS失败: " .. tostring(response))
    end
    
    print("✓ " .. business_type .. "业务数据操作测试通过")
    return true
end

local function test_batch_operations(server)
    print("测试批量操作命令...")
    
    -- 批量添加数据 - 使用哈希数据结构
    for business_type, business in pairs(BUSINESS_TEST_DATA) do
        for _, data in ipairs(business.data) do
            -- 将哈希数据序列化为JSON字符串存储
            local hash_json = require("cjson").encode(data.hash_data)
            local response = server:handle_command(mock_client, "BATCH_SET", {
                data.key,
                hash_json,
                tostring(data.timestamp)
            })
            assert(response == "OK", 
                "BATCH_SET失败: " .. tostring(response))
        end
    end
    
    -- 批量刷新数据
    local response = server:handle_command(mock_client, "BATCH_FLUSH", {})
    assert(response == "OK", "BATCH_FLUSH失败: " .. tostring(response))
    
    print("✓ 批量操作命令测试通过")
    return true
end

local function test_cluster_operations(server)
    print("测试集群操作命令...")
    
    -- 测试CLUSTER_INFO命令
    local response = server:handle_command(mock_client, "CLUSTER_INFO", {})
    assert(type(response) == "table", "CLUSTER_INFO失败: " .. tostring(response))
    
    print("✓ 集群操作命令测试通过")
    return true
end

local function test_performance(server, tsdb)
    print("测试性能...")
    
    local start_time = os.clock()
    local iterations = 100
    
    -- 性能测试：批量写入 - 使用哈希数据结构
    for i = 1, iterations do
        for business_type, business in pairs(BUSINESS_TEST_DATA) do
            for _, data in ipairs(business.data) do
                -- 为性能测试创建新的哈希数据
                local perf_hash_data = {}
                for field, value in pairs(data.hash_data) do
                    perf_hash_data[field] = value .. "_perf_" .. i
                end
                local hash_json = require("cjson").encode(perf_hash_data)
                
                local success, response = pcall(server.handle_command, server, mock_client, "BATCH_SET", {
                    data.key .. "_perf_" .. i,
                    hash_json,
                    tostring(data.timestamp + i)
                })
                if not success then
                    print("性能测试中BATCH_SET失败: " .. tostring(response))
                    return false
                end
            end
        end
    end
    
    local success, response = pcall(server.handle_command, server, mock_client, "BATCH_FLUSH", {})
    if not success then
        print("性能测试中BATCH_FLUSH失败: " .. tostring(response))
        return false
    end
    
    local end_time = os.clock()
    local elapsed = end_time - start_time
    local total_operations = iterations * 14  -- 14 = 7业务 × 2数据点
    local qps = total_operations / elapsed
    
    print(string.format("性能测试: %d次操作, %.3f秒, %.2f次/秒", 
        total_operations, elapsed, qps))
    
    print("✓ 性能测试通过")
    return true
end

local function test_error_handling(server)
    print("测试错误处理...")
    
    -- 测试无效命令 - 使用pcall安全调用
    local success, response = pcall(server.handle_command, server, mock_client, "INVALID_COMMAND", {})
    if success then
        -- 如果命令有效但返回错误消息
        assert(response == nil or type(response) == "string" and (response:match("ERR") or response:match("unknown")), 
            "无效命令处理失败: " .. tostring(response))
    else
        -- 如果命令执行出错，这也是预期的错误处理
        print("✓ 无效命令正确触发错误")
    end
    
    -- 测试HASH_SET命令参数不足
    success, response = pcall(server.handle_command, server, mock_client, "HASH_SET", {"test_key"})
    if success then
        assert(response == nil or type(response) == "string" and (response:match("ERR") or response:match("wrong")), 
            "参数不足处理失败: " .. tostring(response))
    else
        print("✓ 参数不足正确触发错误")
    end
    
    -- 测试无效JSON数据
    success, response = pcall(server.handle_command, server, mock_client, "HASH_SET", {
        "test_key", 
        tostring(os.time()), 
        "{invalid json}"
    })
    if success then
        assert(response == nil or type(response) == "string" and (response:match("ERR") or response:match("invalid")), 
            "无效JSON处理失败: " .. tostring(response))
    else
        print("✓ 无效JSON正确触发错误")
    end
    
    -- 测试无效时间戳
    success, response = pcall(server.handle_command, server, mock_client, "HASH_SET", {
        "test_key", 
        "invalid_timestamp", 
        "{}"
    })
    if success then
        assert(response == nil or type(response) == "string" and (response:match("ERR") or response:match("invalid")), 
            "无效时间戳处理失败: " .. tostring(response))
    else
        print("✓ 无效时间戳正确触发错误")
    end
    
    print("✓ 错误处理测试通过")
    return true
end

local function test_boundary_conditions(server)
    print("测试边界条件...")
    
    -- 测试超大哈希数据
    local large_hash_data = {}
    for i = 1, 50 do
        large_hash_data["field_" .. i] = "value_" .. i .. string.rep("x", 100)
    end
    local large_json = require("cjson").encode(large_hash_data)
    
    local response = server:handle_command(mock_client, "HASH_SET", {
        "large_data_key", 
        tostring(os.time()), 
        large_json
    })
    assert(response == "OK", "超大哈希数据处理失败")
    
    -- 测试空哈希数据
    response = server:handle_command(mock_client, "HASH_SET", {
        "empty_data_key", 
        tostring(os.time()), 
        "{}"
    })
    assert(response == "OK", "空哈希数据处理失败")
    
    -- 测试特殊字符键名
    local special_key = "key:with:special:chars@#$%"
    local test_data = {field1 = "value1", field2 = "value2"}
    local test_json = require("cjson").encode(test_data)
    
    response = server:handle_command(mock_client, "HASH_SET", {
        special_key, 
        tostring(os.time()), 
        test_json
    })
    assert(response == "OK", "特殊字符键名处理失败")
    
    -- 测试时间边界条件
    local future_time = os.time() + 365 * 24 * 60 * 60  -- 一年后
    response = server:handle_command(mock_client, "HASH_SET", {
        "future_key", 
        tostring(future_time), 
        test_json
    })
    assert(response == "OK", "未来时间处理失败")
    
    print("✓ 边界条件测试通过")
    return true
end

local function test_data_consistency(server)
    print("测试数据一致性...")
    
    -- 测试数据写入和读取的一致性
    local test_key = "consistency_test_key"
    local test_timestamp = os.time()
    local test_hash_data = {
        field1 = "value1",
        field2 = "value2", 
        field3 = "value3",
        numeric_field = "123.45",
        boolean_field = "true"
    }
    local test_json = require("cjson").encode(test_hash_data)
    
    -- 写入数据
    local response = server:handle_command(mock_client, "HASH_SET", {
        test_key, 
        tostring(test_timestamp), 
        test_json
    })
    assert(response == "OK", "数据写入失败")
    
    -- 立即读取验证
    response = server:handle_command(mock_client, "HASH_GET", {
        test_key, 
        tostring(test_timestamp - 10), 
        tostring(test_timestamp + 10)
    })
    assert(type(response) == "table" and #response >= 2, "数据读取失败")
    
    -- 验证数据一致性
    local point_data = require("cjson").decode(response[2])
    assert(type(point_data) == "table", "返回数据格式错误")
    
    for field, expected_value in pairs(test_hash_data) do
        assert(point_data[field] == expected_value, 
            string.format("字段%s不一致: 期望%s, 实际%s", field, expected_value, tostring(point_data[field])))
    end
    
    -- 测试字段查询一致性
    response = server:handle_command(mock_client, "HASH_FIELDS", {
        test_key, 
        tostring(test_timestamp - 10), 
        tostring(test_timestamp + 10),
        "field1", "field2"
    })
    assert(type(response) == "table", "字段查询失败")
    
    print("✓ 数据一致性测试通过")
    return true
end

local function test_concurrent_operations(server)
    print("测试并发操作...")
    
    -- 模拟并发写入
    local concurrent_clients = {}
    for i = 1, 5 do
        concurrent_clients[i] = { id = "concurrent_client_" .. i }
    end
    
    local success_count = 0
    local test_key = "concurrent_test_key"
    local base_timestamp = os.time()
    
    -- 并发写入测试
    for i, client in ipairs(concurrent_clients) do
        local test_data = {
            client_id = client.id,
            sequence = tostring(i),
            timestamp = tostring(base_timestamp + i)
        }
        local test_json = require("cjson").encode(test_data)
        
        local response = server:handle_command(client, "HASH_SET", {
            test_key, 
            tostring(base_timestamp + i), 
            test_json
        })
        
        if response == "OK" then
            success_count = success_count + 1
        end
    end
    
    assert(success_count == #concurrent_clients, "并发写入失败: " .. success_count .. "/" .. #concurrent_clients)
    
    -- 验证并发写入的数据
    local response = server:handle_command(mock_client, "HASH_GET", {
        test_key, 
        tostring(base_timestamp), 
        tostring(base_timestamp + 10)
    })
    assert(type(response) == "table" and #response >= 2 * #concurrent_clients, "并发数据验证失败")
    
    print("✓ 并发操作测试通过")
    return true
end

-- 主函数
local function main()
    print("=== 业务数据Redis+TSDB集群综合测试 ===")
    print("开始时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("")
    
    -- 创建模拟TSDB实例
    print("初始化模拟TSDB...")
    local tsdb = MockTSDB:new()
    
    -- 创建Redis TCP服务器实例
    print("创建Redis TCP服务器...")
    local config = {
        port = 6379,
        bind_addr = "127.0.0.1",
        max_connections = 10000,
        node_id = "business_test_" .. os.date("%Y%m%d_%H%M%S"),
        tsdb = tsdb
    }
    
    local server = RedisTCPServer:new(config)
    server:init_commands()
    
    -- 运行各项测试
    local tests = {
        {name = "基础Redis命令", func = function() return test_basic_redis_commands(server) end},
        {name = "股票行情业务", func = function() return test_business_data_operations(server, "stock") end},
        {name = "IOT传感器业务", func = function() return test_business_data_operations(server, "iot") end},
        {name = "金融行情业务", func = function() return test_business_data_operations(server, "finance") end},
        {name = "订单业务", func = function() return test_business_data_operations(server, "order") end},
        {name = "支付业务", func = function() return test_business_data_operations(server, "payment") end},
        {name = "库存业务", func = function() return test_business_data_operations(server, "inventory") end},
        {name = "短信下发业务", func = function() return test_business_data_operations(server, "sms") end},
        {name = "批量操作命令", func = function() return test_batch_operations(server) end},
        {name = "集群操作命令", func = function() return test_cluster_operations(server) end},
        {name = "错误处理测试", func = function() return test_error_handling(server) end},
        {name = "边界条件测试", func = function() return test_boundary_conditions(server) end},
        {name = "数据一致性测试", func = function() return test_data_consistency(server) end},
        {name = "并发操作测试", func = function() return test_concurrent_operations(server) end},
        {name = "性能测试", func = function() return test_performance(server, tsdb) end}
    }
    
    local passed = 0
    local failed = 0
    local failed_tests = {}
    
    for i, test in ipairs(tests) do
        print(string.format("运行测试[%d/%d]: %s", i, #tests, test.name))
        
        local success, err = pcall(test.func)
        if success then
            passed = passed + 1
            print("✓ 测试完成")
        else
            failed = failed + 1
            table.insert(failed_tests, {name = test.name, error = tostring(err)})
            print("✗ 测试失败: " .. tostring(err))
        end
        
        print("")
    end
    
    -- 输出测试结果
    print("=== 业务数据测试结果汇总 ===")
    print(string.format("总测试数: %d", #tests))
    print(string.format("通过测试: %d", passed))
    print(string.format("失败测试: %d", failed))
    print(string.format("成功率: %.1f%%", passed / #tests * 100))
    
    -- 输出TSDB统计信息
    local stats = tsdb:get_stats()
    print("")
    print("=== TSDB存储统计 ===")
    print(string.format("写入次数: %d", stats.write_count))
    print(string.format("读取次数: %d", stats.read_count))
    print(string.format("批量操作: %d", stats.batch_count))
    
    -- 输出服务器统计信息
    local server_stats = server:get_stats()
    print("")
    print("=== Redis TCP服务器统计 ===")
    print(string.format("处理命令数: %d", server_stats.commands_processed or 0))
    print(string.format("批量操作数: %d", server_stats.batch_operations or 0))
    print(string.format("错误数: %d", server_stats.errors or 0))
    
    -- 输出失败测试详情
    if #failed_tests > 0 then
        print("")
        print("=== 失败测试详情 ===")
        for _, failed_test in ipairs(failed_tests) do
            print(string.format("测试: %s", failed_test.name))
            print(string.format("错误: %s", failed_test.error))
            print("")
        end
    end
    
    print("测试结束时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    
    if failed == 0 then
        print("🎉 所有业务数据测试通过！Redis+TSDB集群运行正常。")
        os.exit(0)
    else
        print("❌ 部分测试失败，请检查系统配置。")
        os.exit(1)
    end
end

-- 运行主函数
main()