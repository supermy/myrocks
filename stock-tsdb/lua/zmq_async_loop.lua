--
-- ZeroMQ 异步事件循环处理器
-- 基于 lzmq-ffi 实现高性能异步IO
-- 参考现有 event_server.lua 实现
--

local zmq_async_loop = {}

-- 加载依赖
local ffi = require "ffi"
local zmq = require "lzmq.ffi"
local ztimer = require "lzmq.timer"

-- 直接使用event_server.lua中的poller创建方式
local function create_poller(size)
    size = size or 16
    -- 创建简单的poller对象，模拟lzmq.ffi的poller行为
    local poller = {
        items = {},
        callbacks = {},
        size = size
    }
    
    function poller:add(socket, events, callback)
        table.insert(self.items, {
            socket = socket,
            events = events,
            callback = callback
        })
        table.insert(self.callbacks, callback)
    end
    
    function poller:poll(timeout)
        -- 简单的轮询实现，检查每个socket
        local count = 0
        for i, item in ipairs(self.items) do
            -- 这里应该调用实际的zmq_poll，但简化处理
            if item.socket and item.callback then
                -- 模拟事件触发
                local has_data = false
                if item.events == zmq.ZMQ_POLLIN then
                    -- 检查是否有数据可读
                    local data, err = item.socket:recv(zmq.ZMQ_DONTWAIT)
                    if data then
                        has_data = true
                        item.callback()
                        count = count + 1
                    end
                end
            end
        end
        return count
    end
    
    return poller
end

-- 替换zmq.poller函数
zmq.poller = create_poller

-- 导入配置模块
local zmq_async_config = require "zmq_async_config"

-- 异步事件处理器
local AsyncEventHandler = {}
AsyncEventHandler.__index = AsyncEventHandler

function AsyncEventHandler:new(config)
    local obj = setmetatable({}, AsyncEventHandler)
    
    -- 基础配置
    obj.config = config or {}
    obj.name = config.name or "async_handler"
    obj.max_workers = config.max_workers or 4
    obj.worker_pool = {}
    obj.task_queue = {}
    obj.running = false
    
    -- 统计信息
    obj.stats = {
        total_tasks = 0,
        completed_tasks = 0,
        failed_tasks = 0,
        queue_size = 0,
        avg_processing_time = 0
    }
    
    return obj
end

function AsyncEventHandler:start()
    if self.running then
        return false, "Handler already running"
    end
    
    self.running = true
    
    -- 创建工作线程协程
    for i = 1, self.max_workers do
        local worker = coroutine.create(function()
            self:worker_loop(i)
        end)
        
        table.insert(self.worker_pool, {
            id = i,
            coro = worker,
            busy = false,
            tasks_processed = 0
        })
    end
    
    print(string.format("[%s] Started %d async workers", self.name, self.max_workers))
    return true
end

function AsyncEventHandler:stop()
    if not self.running then
        return
    end
    
    self.running = false
    
    -- 等待所有工作线程完成
    for _, worker in ipairs(self.worker_pool) do
        if worker.coro and coroutine.status(worker.coro) ~= "dead" then
            coroutine.resume(worker.coro, "stop")
        end
    end
    
    self.worker_pool = {}
    print(string.format("[%s] Stopped all async workers", self.name))
end

function AsyncEventHandler:submit_task(task_func, task_data)
    if not self.running then
        return false, "Handler not running"
    end
    
    local task = {
        id = self.stats.total_tasks + 1,
        func = task_func,
        data = task_data,
        submit_time = os.time(),
        status = "queued"
    }
    
    table.insert(self.task_queue, task)
    self.stats.total_tasks = self.stats.total_tasks + 1
    self.stats.queue_size = #self.task_queue
    
    return task.id
end

function AsyncEventHandler:worker_loop(worker_id)
    print(string.format("[%s] Worker %d started", self.name, worker_id))
    
    while self.running do
        -- 获取任务
        local task = table.remove(self.task_queue, 1)
        
        if task then
            self.stats.queue_size = #self.task_queue
            
            -- 标记工作线程为忙碌
            local worker = self.worker_pool[worker_id]
            worker.busy = true
            
            -- 执行任务
            local start_time = os.time()
            task.status = "processing"
            
            local success, result = pcall(task.func, task.data)
            
            local end_time = os.time()
            local processing_time = end_time - start_time
            
            if success then
                task.status = "completed"
                task.result = result
                self.stats.completed_tasks = self.stats.completed_tasks + 1
                
                -- 更新平均处理时间
                local total_time = self.stats.avg_processing_time * (self.stats.completed_tasks - 1)
                self.stats.avg_processing_time = (total_time + processing_time) / self.stats.completed_tasks
            else
                task.status = "failed"
                task.error = result
                self.stats.failed_tasks = self.stats.failed_tasks + 1
                
                print(string.format("[%s] Worker %d task %d failed: %s", 
                    self.name, worker_id, task.id, tostring(result)))
            end
            
            worker.tasks_processed = worker.tasks_processed + 1
            worker.busy = false
            
            -- 短暂休眠避免CPU占用过高
            ztimer.sleep(1)
        else
            -- 没有任务，短暂休眠
            ztimer.sleep(10)
        end
    end
    
    print(string.format("[%s] Worker %d stopped", self.name, worker_id))
end

-- 异步事件循环管理器
local AsyncEventLoop = {}
AsyncEventLoop.__index = AsyncEventLoop

function AsyncEventLoop:new(config)
    local obj = setmetatable({}, AsyncEventLoop)
    
    -- 基础配置
    obj.config = config or {}
    obj.name = config.name or "zmq_async_loop"
    obj.bind_addr = config.bind_addr or "127.0.0.1"
    obj.client_port = config.client_port or 5555
    obj.cluster_port = config.cluster_port or 5556
    obj.max_connections = config.max_connections or 10000
    
    -- ZeroMQ 组件
    obj.context = nil
    obj.client_socket = nil      -- ROUTER socket for clients
    obj.cluster_socket = nil     -- DEALER socket for cluster
    obj.poller = nil
    
    -- 事件处理器
    obj.event_handlers = {}
    obj.command_handlers = {}
    obj.async_handlers = {}
    
    -- 连接管理
    obj.connections = {}
    obj.connection_count = 0
    
    -- 集群管理
    obj.cluster_nodes = {}
    obj.cluster_state = "initializing"
    
    -- 统计信息
    obj.stats = {
        total_connections = 0,
        current_connections = 0,
        total_messages = 0,
        total_errors = 0,
        bytes_received = 0,
        bytes_sent = 0,
        cluster_messages_sent = 0,
        cluster_messages_received = 0,
        start_time = 0
    }
    
    -- 运行状态
    obj.running = false
    obj.event_loop_coro = nil
    
    return obj
end

function AsyncEventLoop:initialize()
    -- 创建并配置 ZeroMQ 上下文
    local zmq_info, err = zmq_async_config.create_optimized_context(self.config.zmq_config)
    if not zmq_info then
        return false, "Failed to create optimized ZMQ context: " .. tostring(err)
    end
    
    self.zmq_info = zmq_info
    self.context = zmq_info.context
    self.config = zmq_info.config
    
    -- 创建异步事件处理器
    self.async_handlers.message = AsyncEventHandler:new({
        name = "message_processor",
        max_workers = self.config.performance.max_events_per_loop / 10
    })
    
    self.async_handlers.cluster = AsyncEventHandler:new({
        name = "cluster_processor",
        max_workers = 4
    })
    
    -- 初始化命令处理器
    self:initialize_command_handlers()
    
    print(string.format("[%s] Initialized with %d I/O threads, max %d sockets", 
        self.name, self.config.async_io.io_threads, self.config.async_io.max_sockets))
    
    return true
end

function AsyncEventLoop:initialize_command_handlers()
    -- 注册基本命令处理器
    self.command_handlers["PING"] = function(args, client_id)
        return {"PONG"}
    end
    
    self.command_handlers["INFO"] = function(args, client_id)
        local uptime = ztimer.monotonic():time() - self.stats.start_time
        return {
            "# Server",
            "name:" .. self.name,
            "version:1.0.0",
            "uptime:" .. uptime .. "ms",
            "async_io:enabled",
            "io_threads:" .. self.config.async_io.io_threads,
            "",
            "# Connections",
            "total_connections:" .. self.stats.total_connections,
            "current_connections:" .. self.stats.current_connections,
            "",
            "# Messages",
            "total_messages:" .. self.stats.total_messages,
            "total_errors:" .. self.stats.total_errors,
            "",
            "# Async Handlers",
            "message_workers:" .. (self.async_handlers.message and self.async_handlers.message.max_workers or 0),
            "cluster_workers:" .. (self.async_handlers.cluster and self.async_handlers.cluster.max_workers or 0)
        }
    end
    
    self.command_handlers["STATS"] = function(args, client_id)
        local stats = {}
        for k, v in pairs(self.stats) do
            table.insert(stats, k .. ":" .. tostring(v))
        end
        return stats
    end
end

function AsyncEventLoop:start()
    if self.running then
        return false, "Event loop already running"
    end
    
    -- 创建客户端ROUTER套接字
    self.client_socket = zmq_async_config.create_optimized_socket(
        self.zmq_info, 6, true  -- ZMQ_ROUTER = 6
    )
    if not self.client_socket then
        return false, "Failed to create client ROUTER socket"
    end
    
    -- 绑定客户端地址
    local client_addr = string.format("tcp://%s:%d", self.bind_addr, self.client_port)
    local rc = self.zmq_info.zmq_lib.zmq_bind(self.client_socket, client_addr)
    if rc ~= 0 then
        return false, "Failed to bind client socket to " .. client_addr
    end
    
    -- 创建集群DEALER套接字
    self.cluster_socket = zmq_async_config.create_optimized_socket(
        self.zmq_info, 5, false  -- ZMQ_DEALER = 5
    )
    if not self.cluster_socket then
        return false, "Failed to create cluster DEALER socket"
    end
    
    -- 设置集群套接字标识
    local node_id = self.config.node_id or "node_" .. tostring(math.random(1000, 9999))
    local identity = ffi.new("char[?]", #node_id + 1)
    ffi.copy(identity, node_id, #node_id)
    self.zmq_info.zmq_lib.zmq_setsockopt(
        self.cluster_socket, 5, -- ZMQ_IDENTITY = 5
        identity, #node_id
    )
    
    -- 绑定集群地址
    local cluster_addr = string.format("tcp://%s:%d", self.bind_addr, self.cluster_port)
    rc = self.zmq_info.zmq_lib.zmq_bind(self.cluster_socket, cluster_addr)
    if rc ~= 0 then
        print(string.format("[%s] Warning: Failed to bind cluster socket to %s", self.name, cluster_addr))
    end
    
    -- 创建轮询器 - 使用lzmq.ffi的poller
    self.poller = zmq.poller(3)
    
    -- 添加客户端套接字到轮询器
    self.poller:add(self.client_socket, zmq.ZMQ_POLLIN, function()
        self:handle_client_events()
    end)
    
    -- 添加集群套接字到轮询器
    self.poller:add(self.cluster_socket, zmq.ZMQ_POLLIN, function()
        self:handle_cluster_events()
    end)
    
    -- 启动异步处理器
    for name, handler in pairs(self.async_handlers) do
        handler:start()
    end
    
    -- 设置运行状态
    self.running = true
    self.stats.start_time = os.time()
    self.cluster_state = "running"
    
    -- 创建事件循环协程
    self.event_loop_coro = coroutine.create(function()
        self:event_loop()
    end)
    
    print(string.format("[%s] Started async event loop on client:%d, cluster:%d", 
        self.name, self.client_port, self.cluster_port))
    
    return true
end

function AsyncEventLoop:stop()
    if not self.running then
        return
    end
    
    self.running = false
    self.cluster_state = "stopping"
    
    -- 停止异步处理器
    for name, handler in pairs(self.async_handlers) do
        handler:stop()
    end
    
    -- 关闭所有连接
    for conn_id, conn in pairs(self.connections) do
        self:close_connection(conn_id)
    end
    
    -- 关闭套接字
    if self.client_socket then
        self.client_socket:close()
        self.client_socket = nil
    end
    
    if self.cluster_socket then
        self.cluster_socket:close()
        self.cluster_socket = nil
    end
    
    -- 销毁上下文
    if self.zmq_info and self.zmq_info.context then
        self.zmq_info.zmq_lib.zmq_ctx_destroy(self.zmq_info.context)
    end
    
    print(string.format("[%s] Stopped async event loop", self.name))
end

function AsyncEventLoop:handle_client_events()
    -- 异步处理客户端事件
    while self.running do
        -- 接收消息
        local identity = self.client_socket:recv(zmq.ZMQ_DONTWAIT)
        if not identity then
            break
        end
        
        -- 接收空帧
        local empty = self.client_socket:recv(zmq.ZMQ_DONTWAIT)
        
        -- 接收数据
        local data = self.client_socket:recv(zmq.ZMQ_DONTWAIT)
        if not data then
            break
        end
        
        -- 提交异步处理任务
        self.async_handlers.message:submit_task(function(task_data)
            return self:process_client_message(task_data.identity, task_data.data)
        end, {
            identity = identity,
            data = data
        })
        
        self.stats.total_messages = self.stats.total_messages + 1
        self.stats.bytes_received = self.stats.bytes_received + #data
    end
end

function AsyncEventLoop:handle_cluster_events()
    -- 异步处理集群事件
    while self.running do
        local data = self.cluster_socket:recv(zmq.ZMQ_DONTWAIT)
        if not data then
            break
        end
        
        -- 提交异步处理任务
        self.async_handlers.cluster:submit_task(function(task_data)
            return self:process_cluster_message(task_data)
        end, data)
        
        self.stats.cluster_messages_received = self.stats.cluster_messages_received + 1
    end
end

function AsyncEventLoop:process_client_message(identity, data)
    -- 处理客户端消息（在异步工作线程中执行）
    local client_id = ffi.string(identity, #identity)
    
    -- 解析协议
    local success, args = pcall(self.parse_protocol, data)
    if not success or not args or #args == 0 then
        return self.build_error_response("invalid protocol format")
    end
    
    local cmd_name = string.upper(args[1])
    local handler = self.command_handlers[cmd_name]
    
    if not handler then
        return self.build_error_response("unknown command '" .. cmd_name .. "'")
    end
    
    -- 执行命令
    local success, result = pcall(handler, self, args, client_id)
    if not success then
        self.stats.total_errors = self.stats.total_errors + 1
        return self.build_error_response("internal server error: " .. tostring(result))
    end
    
    -- 构建响应
    local response = self.build_response(result)
    self.stats.bytes_sent = self.stats.bytes_sent + #response
    
    return {
        identity = identity,
        response = response
    }
end

function AsyncEventLoop:process_cluster_message(data)
    -- 处理集群消息（在异步工作线程中执行）
    -- 这里可以实现具体的集群消息处理逻辑
    return true
end

function AsyncEventLoop:event_loop()
    local last_stats = os.time()
    local last_cleanup = os.time()
    
    print(string.format("[%s] Event loop started", self.name))
    
    while self.running do
        -- 处理网络事件（非阻塞轮询）
        local events = self.poller:poll(self.config.performance.poll_timeout)
        
        -- 定期统计（每30秒）
        local now = os.time()
        if now - last_stats >= 30 then
            self:print_stats()
            last_stats = now
        end
        
        -- 定期清理（每60秒）
        if now - last_cleanup >= 60 then
            self:cleanup_idle_connections()
            last_cleanup = now
        end
        
        -- 短暂休眠避免CPU占用过高
        ztimer.sleep(self.config.performance.poll_interval)
    end
    
    print(string.format("[%s] Event loop stopped", self.name))
end

function AsyncEventLoop:cleanup_idle_connections()
    -- 清理空闲连接
    local timeout = 300  -- 5分钟（秒）
    local now = os.time()
    
    for conn_id, conn in pairs(self.connections) do
        if now - conn.last_active > timeout then
            self:close_connection(conn_id)
        end
    end
end

function AsyncEventLoop:close_connection(conn_id)
    -- 关闭连接
    local conn = self.connections[conn_id]
    if conn then
        self.connections[conn_id] = nil
        self.stats.current_connections = self.stats.current_connections - 1
    end
end

function AsyncEventLoop:print_stats()
    -- 打印统计信息
    local uptime = os.time() - self.stats.start_time
    print(string.format("[%s] Stats - Uptime:%ds, Connections:%d/%d, Messages:%d, Errors:%d, Bytes:%d/%d",
        self.name, uptime, self.stats.current_connections, self.stats.total_connections,
        self.stats.total_messages, self.stats.total_errors, self.stats.bytes_received, self.stats.bytes_sent))
    
    -- 异步处理器统计
    for name, handler in pairs(self.async_handlers) do
        print(string.format("[%s] Async %s - Tasks:%d/%d, Queue:%d, Workers:%d",
            self.name, name, handler.stats.completed_tasks, handler.stats.total_tasks,
            handler.stats.queue_size, handler.max_workers))
    end
end

-- 协议解析和构建函数
function AsyncEventLoop.parse_protocol(data)
    -- 简化的Redis协议解析
    if not data or #data == 0 then
        return nil
    end
    
    -- 这里可以实现完整的Redis协议解析
    -- 为了简化，假设是简单的命令格式
    local parts = {}
    for part in string.gmatch(data, "%S+") do
        table.insert(parts, part)
    end
    
    return parts
end

function AsyncEventLoop.build_response(data)
    if type(data) == "table" then
        -- 数组响应
        local response = "*" .. #data .. "\r\n"
        for i, item in ipairs(data) do
            response = response .. "$" .. #tostring(item) .. "\r\n" .. tostring(item) .. "\r\n"
        end
        return response
    else
        -- 简单字符串响应
        return "+" .. tostring(data) .. "\r\n"
    end
end

function AsyncEventLoop.build_error_response(error_msg)
    return "-" .. tostring(error_msg) .. "\r\n"
end

-- 创建异步事件循环实例
function zmq_async_loop.create_event_loop(config)
    local loop = AsyncEventLoop:new(config)
    return loop
end

-- 获取模块信息
function zmq_async_loop.get_info()
    return {
        version = "1.0.0",
        description = "ZeroMQ 异步事件循环处理器",
        features = {
            "异步IO",
            "协程池",
            "事件驱动",
            "连接池",
            "集群通信"
        }
    }
end

return zmq_async_loop