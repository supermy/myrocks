--
-- ZeroMQ 异步线程池演示程序
-- 展示如何使用 zmq_async_config 和 zmq_async_loop 模块
--

local ffi = require "ffi"
local ztimer = require "lzmq.timer"

-- 加载异步模块
local zmq_async_config = require "zmq_async_config"
local zmq_async_loop = require "zmq_async_loop"

-- 创建演示类
local ZMQAsyncDemo = {}
ZMQAsyncDemo.__index = ZMQAsyncDemo

function ZMQAsyncDemo:new(config)
    local obj = setmetatable({}, ZMQAsyncDemo)
    
    obj.config = config or {}
    obj.event_loop = nil
    obj.running = false
    obj.demo_tasks = {}
    
    -- 解析命令行参数
    if arg then
        for i = 1, #arg do
            if arg[i] == "--port" and i < #arg then
                obj.config.port = tonumber(arg[i+1])
            elseif arg[i] == "--interactive" then
                obj.config.interactive = true
            end
        end
    end
    
    return obj
end

function ZMQAsyncDemo:initialize()
    print("=== ZeroMQ 异步线程池演示 ===")
    print("")
    
    -- 显示模块信息
    local info = zmq_async_loop.get_info()
    print(string.format("模块版本: %s", info.version))
    print(string.format("模块描述: %s", info.description))
    print("特性列表:")
    for _, feature in ipairs(info.features) do
        print(string.format("  - %s", feature))
    end
    print("")
    
    -- 创建优化配置
    local zmq_config = zmq_async_config.validate_config({
        io_threads = 4,                    -- 使用4个I/O线程
        max_sockets = 2000,                -- 最大2000个套接字
        max_connections = 10000,           -- 最大10000个连接
        performance = {
            max_events_per_loop = 1000,    -- 每循环最多处理1000个事件
            poll_timeout = 100,            -- 轮询超时100ms
            poll_interval = 1              -- 轮询间隔1ms
        },
        connection_pool = {
            max_pool_size = 50,            -- 连接池最大50个连接
            connection_timeout = 30000,    -- 连接超时30秒
            idle_timeout = 60000           -- 空闲超时60秒
        }
    })
    
    -- 验证配置
    local is_valid, errors = zmq_config, nil
    if not is_valid then
        print("配置验证失败:")
        for _, error in ipairs(errors) do
            print(string.format("  - %s", error))
        end
        return false
    end
    
    print("配置验证通过")
    print(string.format("I/O线程数: %d", zmq_config.async_io.io_threads))
    print(string.format("最大套接字数: %d", zmq_config.async_io.max_sockets))
    print(string.format("最大连接数: %d", zmq_config.connection_pool.max_pool_size))
    print("")
    
    -- 创建事件循环
    local client_port = self.config.port or 5555
    local cluster_port = client_port + 1
    
    self.event_loop = zmq_async_loop.create_event_loop({
        name = "demo_async_loop",
        bind_addr = "127.0.0.1",
        client_port = client_port,
        cluster_port = cluster_port,
        max_connections = zmq_config.connection_pool.max_pool_size,
        zmq_config = zmq_config
    })
    
    -- 注册自定义命令处理器
    self:register_demo_commands()
    
    -- 初始化事件循环
    local success, err = self.event_loop:initialize()
    if not success then
        print(string.format("初始化失败: %s", err))
        return false
    end
    
    print("事件循环初始化成功")
    return true
end

function ZMQAsyncDemo:register_demo_commands()
    -- 注册演示命令
    self.event_loop.command_handlers["DEMO.ECHO"] = function(args, client_id)
        return {"DEMO.ECHO.RESPONSE", table.concat(args, " ", 2)}
    end
    
    self.event_loop.command_handlers["DEMO.ASYNC"] = function(args, client_id)
        -- 异步处理演示
        local task_data = {
            client_id = client_id,
            task_type = "async_demo",
            data = table.concat(args, " ", 2)
        }
        
        -- 提交异步任务
        local task_id = self.event_loop.async_handlers.message:submit_task(function(data)
            -- 模拟耗时操作
            ztimer.sleep(100)  -- 100ms
            return {
                "DEMO.ASYNC.RESPONSE",
                string.format("Task %d completed for client %s", data.task_id or 0, data.client_id),
                string.format("Data: %s", data.data)
            }
        end, task_data)
        
        return {"DEMO.ASYNC.ACCEPTED", tostring(task_id)}
    end
    
    self.event_loop.command_handlers["DEMO.BENCHMARK"] = function(args, client_id)
        -- 性能基准测试
        local count = tonumber(args[2]) or 1000
        local start_time = ztimer.monotonic():time()
        
        local completed = 0
        for i = 1, count do
            self.event_loop.async_handlers.message:submit_task(function(data)
                -- 模拟轻量级处理
                local result = data.num * 2
                completed = completed + 1
                return result
            end, {num = i})
        end
        
        local end_time = ztimer.monotonic():time()
        local duration = end_time - start_time
        
        return {
            "DEMO.BENCHMARK.RESULT",
            string.format("Tasks: %d", count),
            string.format("Duration: %dms", duration),
            string.format("Throughput: %.2f tasks/ms", count / duration)
        }
    end
    
    self.event_loop.command_handlers["DEMO.THREADPOOL"] = function(args, client_id)
        -- 线程池状态
        local message_stats = self.event_loop.async_handlers.message.stats
        local cluster_stats = self.event_loop.async_handlers.cluster.stats
        
        return {
            "DEMO.THREADPOOL.STATUS",
            string.format("Message Workers: %d/%d", 
                message_stats.completed_tasks, message_stats.total_tasks),
            string.format("Message Queue: %d", message_stats.queue_size),
            string.format("Cluster Workers: %d/%d", 
                cluster_stats.completed_tasks, cluster_stats.total_tasks),
            string.format("Cluster Queue: %d", cluster_stats.queue_size)
        }
    end
end

function ZMQAsyncDemo:start()
    if self.running then
        return false, "Demo already running"
    end
    
    print("启动异步事件循环...")
    local success, err = self.event_loop:start()
    if not success then
        print(string.format("启动失败: %s", err))
        return false
    end
    
    self.running = true
    print("异步事件循环启动成功")
    print("")
    print("可用命令:")
    print("  - PING: 测试连接")
    print("  - INFO: 获取服务器信息")
    print("  - STATS: 获取统计信息")
    print("  - DEMO.ECHO <message>: 回声测试")
    print("  - DEMO.ASYNC <data>: 异步处理演示")
    print("  - DEMO.BENCHMARK <count>: 性能基准测试")
    print("  - DEMO.THREADPOOL: 线程池状态")
    print("")
    print("使用 redis-cli 连接测试:")
    print(string.format("  redis-cli -h 127.0.0.1 -p %d", self.event_loop.client_port))
    print("")
    
    -- 启动演示任务
    self:start_demo_tasks()
    
    return true
end

function ZMQAsyncDemo:start_demo_tasks()
    -- 启动统计打印任务
    local stats_task = coroutine.create(function()
        while self.running do
            self.event_loop:print_stats()
            ztimer.sleep(30000)  -- 每30秒打印一次
        end
    end)
    
    table.insert(self.demo_tasks, stats_task)
    
    -- 启动连接清理任务
    local cleanup_task = coroutine.create(function()
        while self.running do
            self.event_loop:cleanup_idle_connections()
            ztimer.sleep(60000)  -- 每60秒清理一次
        end
    end)
    
    table.insert(self.demo_tasks, cleanup_task)
    
    print("演示任务已启动")
end

function ZMQAsyncDemo:stop()
    if not self.running then
        return
    end
    
    print("停止演示...")
    self.running = false
    
    -- 停止演示任务
    for _, task in ipairs(self.demo_tasks) do
        if coroutine.status(task) ~= "dead" then
            coroutine.resume(task, "stop")
        end
    end
    
    -- 停止事件循环
    if self.event_loop then
        self.event_loop:stop()
    end
    
    print("演示已停止")
end

function ZMQAsyncDemo:run_interactive()
    print("进入交互模式，输入 'quit' 退出")
    print("")
    
    while self.running do
        io.write("demo> ")
        local input = io.read()
        
        if input == "quit" then
            break
        elseif input == "stats" then
            self.event_loop:print_stats()
        elseif input == "help" then
            print("可用命令:")
            print("  stats - 显示统计信息")
            print("  help - 显示帮助")
            print("  quit - 退出")
        else
            print("未知命令，输入 'help' 查看帮助")
        end
    end
    
    print("退出交互模式")
end

-- 主函数
local function main()
    -- 创建演示实例
    local demo = ZMQAsyncDemo:new({
        name = "zmq_async_demo",
        interactive = true
    })
    
    -- 初始化
    local success = demo:initialize()
    if not success then
        print("演示初始化失败")
        return 1
    end
    
    -- 启动
    success = demo:start()
    if not success then
        print("演示启动失败")
        return 1
    end
    
    -- 运行交互模式（可选）
    if demo.config.interactive then
        demo:run_interactive()
    else
        -- 运行指定时间后自动停止
        print("运行60秒后自动停止...")
        ztimer.sleep(60000)
    end
    
    -- 停止
    demo:stop()
    
    print("演示完成")
    return 0
end

-- 如果直接运行此脚本
if arg and arg[0]:match("zmq_async_demo.lua$") then
    local exit_code = main()
    os.exit(exit_code)
end

-- 导出模块
return {
    ZMQAsyncDemo = ZMQAsyncDemo,
    main = main
}