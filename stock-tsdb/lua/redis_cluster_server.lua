--
-- 基于libevent的Redis协议集群服务器
-- 监听6379端口，集成ZeroMQ集群通信
--

local redis_cluster_server = {}

-- 加载依赖
local ffi = require "ffi"

-- 设置Lua路径以使用lib目录下的cjson.so和本地安装的包
package.cpath = package.cpath .. ";../lib/?.so;./lib/?.so;./?.so"

-- 加载lzmq-ffi和cjson
local zmq = require "lzmq.ffi"
local ztimer = require "lzmq.timer"
local cjson = require "cjson"

-- Redis协议解析器（复用event_server中的实现）
local RedisProtocolParser = {}

function RedisProtocolParser.parse_request(buffer)
    -- 简化的Redis协议解析
    if not buffer or #buffer == 0 then
        return nil, "empty buffer"
    end
    
    -- 检查是否是数组格式
    if buffer:sub(1, 1) ~= "*" then
        return nil, "invalid protocol format"
    end
    
    local args = {}
    local pos = 2
    
    -- 解析数组长度
    local line_end = buffer:find("\r\n", pos)
    if not line_end then
        return nil, "incomplete request"
    end
    
    local array_len = tonumber(buffer:sub(pos, line_end - 1))
    if not array_len or array_len < 0 then
        return nil, "invalid array length"
    end
    
    pos = line_end + 2
    
    -- 解析每个参数
    for i = 1, array_len do
        if buffer:sub(pos, pos) ~= "$" then
            return nil, "invalid bulk string format"
        end
        
        pos = pos + 1
        line_end = buffer:find("\r\n", pos)
        if not line_end then
            return nil, "incomplete bulk string length"
        end
        
        local str_len = tonumber(buffer:sub(pos, line_end - 1))
        if not str_len or str_len < 0 then
            return nil, "invalid string length"
        end
        
        pos = line_end + 2
        
        -- 检查是否有足够的数据
        if pos + str_len + 2 > #buffer then
            return nil, "incomplete bulk string data"
        end
        
        local arg = buffer:sub(pos, pos + str_len - 1)
        table.insert(args, arg)
        
        pos = pos + str_len + 2
    end
    
    return args, pos - 1
end

function RedisProtocolParser.build_response(data)
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

function RedisProtocolParser.build_error(error_msg)
    return "-" .. tostring(error_msg) .. "\r\n"
end

function RedisProtocolParser.build_ok()
    return "+OK\r\n"
end

-- 客户端连接类
local ClientConnection = {}
ClientConnection.__index = ClientConnection

function ClientConnection:new(socket, address)
    local obj = setmetatable({}, ClientConnection)
    obj.socket = socket
    obj.address = address
    obj.buffer = ""
    obj.last_active = os.time()
    obj.authenticated = false
    obj.closed = false
    return obj
end

function ClientConnection:send(data)
    if self.closed then
        return false
    end
    
    local result, err = self.socket:send(data)
    if not result then
        self.closed = true
        return false, err
    end
    
    self.last_active = os.time()
    return true
end

function ClientConnection:receive()
    if self.closed then
        return nil, "connection closed"
    end
    
    local data, err = self.socket:recv(zmq.ZMQ_DONTWAIT)
    if not data then
        if err == zmq.EAGAIN then
            return nil, "no data available"
        else
            self.closed = true
            return nil, err
        end
    end
    
    self.buffer = self.buffer .. data
    self.last_active = os.time()
    return data
end

function ClientConnection:close()
    if not self.closed then
        self.socket:close()
        self.closed = true
    end
end

-- Redis集群服务器类
local RedisClusterServer = {}
RedisClusterServer.__index = RedisClusterServer

function RedisClusterServer:new(config)
    local obj = setmetatable({}, RedisClusterServer)
    obj.config = config or {}
    obj.port = config.port or 6379  -- Redis标准端口
    obj.bind_addr = config.bind_addr or "127.0.0.1"
    obj.max_connections = config.max_connections or 10000
    obj.tsdb = config.tsdb
    
    -- 集群配置
    obj.node_id = config.node_id or "redis_node_" .. tostring(math.random(1000, 9999))
    obj.cluster_nodes = config.cluster_nodes or {}
    obj.cluster_port = config.cluster_port or 5555  -- 集群通信端口
    
    obj.context = nil
    obj.router_socket = nil
    obj.cluster_socket = nil
    obj.poller = nil
    obj.running = false
    
    obj.clients = {}
    obj.command_handlers = {}
    
    -- 集群状态
    obj.cluster_peers = {}
    obj.cluster_state = "initializing"
    
    obj.stats = {
        total_connections = 0,
        current_connections = 0,
        total_commands = 0,
        total_errors = 0,
        bytes_received = 0,
        bytes_sent = 0,
        cluster_messages_sent = 0,
        cluster_messages_received = 0
    }
    
    return obj
end

function RedisClusterServer:start()
    -- 创建ZMQ上下文
    self.context = zmq.init(1)
    if not self.context then
        return false, "Failed to create ZMQ context"
    end
    
    -- 创建ROUTER socket用于处理客户端连接
    self.router_socket = self.context:socket(zmq.ROUTER)
    if not self.router_socket then
        return false, "Failed to create ROUTER socket"
    end
    
    -- 设置socket选项
    self.router_socket:setopt_int(zmq.ROUTER_MANDATORY, 1)
    self.router_socket:setopt_int(zmq.SNDHWM, 1000)
    self.router_socket:setopt_int(zmq.RCVHWM, 1000)
    
    -- 绑定Redis服务端口
    local bind_addr = "tcp://" .. self.bind_addr .. ":" .. self.port
    local result, err = self.router_socket:bind(bind_addr)
    if not result then
        return false, "Failed to bind to " .. bind_addr .. ": " .. tostring(err)
    end
    
    -- 创建集群通信socket
    self.cluster_socket = self.context:socket(zmq.DEALER)
    if not self.cluster_socket then
        return false, "Failed to create cluster socket"
    end
    
    -- 设置集群socket选项
    self.cluster_socket:setopt_str(zmq.IDENTITY, self.node_id)
    self.cluster_socket:setopt_int(zmq.SNDHWM, 1000)
    self.cluster_socket:setopt_int(zmq.RCVHWM, 1000)
    
    -- 连接到集群节点
    for _, node_addr in ipairs(self.cluster_nodes) do
        local result, err = self.cluster_socket:connect("tcp://" .. node_addr)
        if result then
            print("Connected to cluster node: " .. node_addr)
            self.cluster_peers[node_addr] = {
                connected = true,
                last_seen = os.time()
            }
        else
            print("Failed to connect to cluster node " .. node_addr .. ": " .. tostring(err))
        end
    end
    
    -- 绑定集群监听端口
    local cluster_bind_addr = "tcp://" .. self.bind_addr .. ":" .. self.cluster_port
    local result, err = self.cluster_socket:bind(cluster_bind_addr)
    if not result then
        print("Warning: Failed to bind cluster port " .. self.cluster_port .. ": " .. tostring(err))
    else
        print("Cluster listening on " .. cluster_bind_addr)
    end
    
    -- 创建poller
    self.poller = zmq.poller.new(3)
    self.poller:add(self.router_socket, zmq.POLLIN, function()
        self:handle_router_events()
    end)
    
    self.poller:add(self.cluster_socket, zmq.POLLIN, function()
        self:handle_cluster_events()
    end)
    
    -- 初始化命令处理器
    self:init_commands()
    
    self.running = true
    self.cluster_state = "running"
    
    print(string.format("Redis cluster server started on %s:%d (Node ID: %s)", self.bind_addr, self.port, self.node_id))
    
    -- 发送集群加入消息
    self:send_cluster_message("JOIN", {
        node_id = self.node_id,
        address = self.bind_addr .. ":" .. self.port,
        cluster_address = self.bind_addr .. ":" .. self.cluster_port
    })
    
    -- 启动事件循环
    self:event_loop()
    
    return true
end

function RedisClusterServer:stop()
    if not self.running then
        return
    end
    
    self.running = false
    self.cluster_state = "stopping"
    
    -- 发送集群离开消息
    self:send_cluster_message("LEAVE", {
        node_id = self.node_id,
        reason = "normal shutdown"
    })
    
    -- 关闭所有客户端连接
    for client_id, client in pairs(self.clients) do
        client:close()
    end
    self.clients = {}
    
    -- 关闭socket和上下文
    if self.router_socket then
        self.router_socket:close()
        self.router_socket = nil
    end
    
    if self.cluster_socket then
        self.cluster_socket:close()
        self.cluster_socket = nil
    end
    
    if self.context then
        self.context:term()
        self.context = nil
    end
    
    print("Redis cluster server stopped")
end

function RedisClusterServer:handle_router_events()
    -- 处理ROUTER socket事件
    while true do
        local msg = self.router_socket:recv(zmq.DONTWAIT)
        if not msg then
            break
        end
        
        -- ROUTER socket消息格式: [identity, empty, data]
        local identity = msg
        local empty = self.router_socket:recv(zmq.DONTWAIT)
        local data = self.router_socket:recv(zmq.DONTWAIT)
        
        if identity and data then
            self:handle_client_message(identity, data)
        end
    end
end

function RedisClusterServer:handle_cluster_events()
    -- 处理集群socket事件
    while true do
        local msg = self.cluster_socket:recv(zmq.DONTWAIT)
        if not msg then
            break
        end
        
        -- 解析集群消息
        local success, message = pcall(cjson.decode, msg)
        if success and message then
            self:process_cluster_message(message)
        else
            print("Failed to parse cluster message: " .. tostring(msg))
        end
        
        self.stats.cluster_messages_received = self.stats.cluster_messages_received + 1
    end
end

function RedisClusterServer:process_cluster_message(message)
    if not message.type then
        return
    end
    
    local handler = self.cluster_handlers[message.type]
    if handler then
        pcall(handler, self, message)
    end
end

function RedisClusterServer:send_cluster_message(msg_type, data)
    local message = {
        type = msg_type,
        from = self.node_id,
        timestamp = os.time(),
        data = data or {}
    }
    
    local json_msg = cjson.encode(message)
    local result, err = self.cluster_socket:send(json_msg)
    
    if result then
        self.stats.cluster_messages_sent = self.stats.cluster_messages_sent + 1
        return true
    else
        print("Failed to send cluster message: " .. tostring(err))
        return false
    end
end

function RedisClusterServer:handle_client_message(identity, data)
    local client_id = ffi.string(identity, #identity)
    
    -- 查找或创建客户端连接
    local client = self.clients[client_id]
    if not client then
        client = ClientConnection:new({
            send = function(_, data)
                return self.router_socket:send(identity, zmq.SNDMORE) and
                       self.router_socket:send("", zmq.SNDMORE) and
                       self.router_socket:send(data)
            end,
            recv = function() return data end,
            close = function()
                self.clients[client_id] = nil
                self.stats.current_connections = self.stats.current_connections - 1
            end
        }, client_id)
        
        self.clients[client_id] = client
        self.stats.total_connections = self.stats.total_connections + 1
        self.stats.current_connections = self.stats.current_connections + 1
        
        print("New Redis client connected: " .. client_id)
    end
    
    -- 处理客户端数据
    client.buffer = client.buffer .. data
    self.stats.bytes_received = self.stats.bytes_received + #data
    
    -- 解析和处理请求
    while true do
        local args, consumed = RedisProtocolParser.parse_request(client.buffer)
        if not args then
            break
        end
        
        -- 移除已处理的数据
        client.buffer = client.buffer:sub(consumed + 1)
        
        -- 处理命令
        self:process_command(client, args)
    end
end

function RedisClusterServer:process_command(client, args)
    if #args == 0 then
        return
    end
    
    local cmd_name = string.upper(args[1])
    self.stats.total_commands = self.stats.total_commands + 1
    
    local handler = self.command_handlers[cmd_name]
    if not handler then
        local response = RedisProtocolParser.build_error("ERR unknown command '" .. cmd_name .. "'")
        client:send(response)
        self.stats.bytes_sent = self.stats.bytes_sent + #response
        self.stats.total_errors = self.stats.total_errors + 1
        return
    end
    
    -- 执行命令
    local success, response = pcall(handler, self, args)
    if not success then
        response = RedisProtocolParser.build_error("ERR internal server error")
        self.stats.total_errors = self.stats.total_errors + 1
    end
    
    -- 发送响应
    if response then
        client:send(response)
        self.stats.bytes_sent = self.stats.bytes_sent + #response
    end
end

function RedisClusterServer:event_loop()
    local timer = ztimer.monotonic()
    local last_cleanup = timer:time()
    local last_heartbeat = timer:time()
    
    while self.running do
        -- 处理网络事件（超时100ms）
        self.poller:poll(100)
        
        -- 定期清理空闲连接（每30秒）
        local now = timer:time()
        if now - last_cleanup >= 30000 then
            self:cleanup_idle_connections()
            last_cleanup = now
        end
        
        -- 发送心跳（每10秒）
        if now - last_heartbeat >= 10000 then
            self:send_cluster_message("HEARTBEAT", {
                node_id = self.node_id,
                status = self.cluster_state,
                stats = self.stats
            })
            last_heartbeat = now
        end
        
        -- 短暂休眠避免CPU占用过高
        zmq.sleep(1)  -- 休眠1ms
    end
end

function RedisClusterServer:cleanup_idle_connections()
    local now = os.time()
    local timeout = 300  -- 5分钟超时
    
    for client_id, client in pairs(self.clients) do
        if now - client.last_active > timeout then
            print("Closing idle connection: " .. client_id)
            client:close()
            self.clients[client_id] = nil
            self.stats.current_connections = self.stats.current_connections - 1
        end
    end
end

-- 集群消息处理器
RedisClusterServer.cluster_handlers = {}

function RedisClusterServer.cluster_handlers.JOIN(self, message)
    print("Redis cluster node joined: " .. message.data.node_id)
    self.cluster_peers[message.data.cluster_address] = {
        node_id = message.data.node_id,
        address = message.data.address,
        connected = true,
        last_seen = os.time()
    }
    
    -- 发送欢迎消息
    self:send_cluster_message("WELCOME", {
        node_id = self.node_id,
        cluster_size = #self.cluster_peers
    })
end

function RedisClusterServer.cluster_handlers.LEAVE(self, message)
    print("Redis cluster node left: " .. message.data.node_id)
    for addr, peer in pairs(self.cluster_peers) do
        if peer.node_id == message.data.node_id then
            self.cluster_peers[addr] = nil
            break
        end
    end
end

function RedisClusterServer.cluster_handlers.HEARTBEAT(self, message)
    for addr, peer in pairs(self.cluster_peers) do
        if peer.node_id == message.data.node_id then
            peer.last_seen = os.time()
            break
        end
    end
end

function RedisClusterServer.cluster_handlers.WELCOME(self, message)
    print("Welcome from Redis cluster, current size: " .. message.data.cluster_size)
end

-- 初始化Redis命令处理器
function RedisClusterServer:init_commands()
    -- Redis标准命令
    self.command_handlers["PING"] = function(self, args)
        if #args > 1 then
            return RedisProtocolParser.build_response({args[2]})
        else
            return RedisProtocolParser.build_response({"PONG"})
        end
    end
    
    self.command_handlers["ECHO"] = function(self, args)
        if #args < 2 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'ECHO' command")
        end
        return RedisProtocolParser.build_response({args[2]})
    end
    
    self.command_handlers["SET"] = function(self, args)
        if #args < 3 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'SET' command")
        end
        
        -- 这里可以集成到TSDB存储
        return RedisProtocolParser.build_ok()
    end
    
    self.command_handlers["GET"] = function(self, args)
        if #args < 2 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'GET' command")
        end
        
        -- 这里可以集成到TSDB查询
        return RedisProtocolParser.build_response({"nil"})
    end
    
    -- TSDB扩展命令
    self.command_handlers["TS.ADD"] = function(self, args)
        if #args < 3 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'TS.ADD' command")
        end
        
        local key = args[1]
        local timestamp = tonumber(args[2])
        local value = tonumber(args[3])
        
        if not timestamp or not value then
            return RedisProtocolParser.build_error("ERR invalid timestamp or value")
        end
        
        -- 调用TSDB写入数据
        local success, err = self.tsdb:write_point(key, timestamp * 1000, value, 0, 100)
        if not success then
            return RedisProtocolParser.build_error("ERR " .. tostring(err))
        end
        
        return RedisProtocolParser.build_ok()
    end
    
    self.command_handlers["TS.RANGE"] = function(self, args)
        if #args < 3 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'TS.RANGE' command")
        end
        
        local key = args[1]
        local start = tonumber(args[2])
        local end_time = tonumber(args[3])
        
        if not start or not end_time then
            return RedisProtocolParser.build_error("ERR invalid start or end time")
        end
        
        -- 调用TSDB查询数据
        local points, err = self.tsdb:query_range(key, start * 1000, end_time * 1000, 0)
        if not points then
            return RedisProtocolParser.build_error("ERR " .. tostring(err))
        end
        
        local result = {}
        for i, point in ipairs(points) do
            table.insert(result, tostring(point.timestamp / 1000))
            table.insert(result, tostring(point.value))
        end
        
        return RedisProtocolParser.build_response(result)
    end
    
    -- 集群命令
    self.command_handlers["CLUSTER"] = function(self, args)
        if #args < 2 then
            return RedisProtocolParser.build_error("ERR wrong number of arguments for 'CLUSTER' command")
        end
        
        local subcommand = string.upper(args[2])
        
        if subcommand == "INFO" then
            local info = {
                "cluster_state:" .. self.cluster_state,
                "cluster_slots_assigned:16384",
                "cluster_slots_ok:16384",
                "cluster_slots_pfail:0",
                "cluster_slots_fail:0",
                "cluster_known_nodes:" .. (#self.cluster_peers + 1),
                "cluster_size:" .. (#self.cluster_peers + 1),
                "cluster_current_epoch:1",
                "cluster_my_epoch:1",
                "cluster_stats_messages_sent:" .. self.stats.cluster_messages_sent,
                "cluster_stats_messages_received:" .. self.stats.cluster_messages_received
            }
            
            return RedisProtocolParser.build_response(table.concat(info, "\r\n"))
            
        elseif subcommand == "NODES" then
            local nodes = {}
            
            -- 添加当前节点
            table.insert(nodes, self.node_id .. " " .. self.bind_addr .. ":" .. self.port .. "@" .. self.cluster_port .. " myself,master - 0 0 0 connected")
            
            -- 添加其他节点
            for addr, peer in pairs(self.cluster_peers) do
                table.insert(nodes, peer.node_id .. " " .. peer.address .. "@" .. addr:match(":(%d+)$") .. " master - 0 0 0 connected")
            end
            
            return RedisProtocolParser.build_response(table.concat(nodes, "\n"))
            
        else
            return RedisProtocolParser.build_error("ERR unknown subcommand '" .. subcommand .. "'")
        end
    end
    
    -- INFO命令
    self.command_handlers["INFO"] = function(self, args)
        local info = {
            "# Server",
            "redis_version:6.2.6",
            "redis_mode:cluster",
            "os:macOS",
            "arch_bits:64",
            "tcp_port:" .. self.port,
            "",
            "# Stats",
            "total_connections:" .. self.stats.total_connections,
            "total_commands_processed:" .. self.stats.total_commands,
            "total_net_input_bytes:" .. self.stats.bytes_received,
            "total_net_output_bytes:" .. self.stats.bytes_sent,
            "",
            "# Cluster",
            "cluster_enabled:1",
            "cluster_state:" .. self.cluster_state,
            "cluster_node_id:" .. self.node_id,
            "cluster_known_nodes:" .. (#self.cluster_peers + 1)
        }
        
        return RedisProtocolParser.build_response(table.concat(info, "\r\n"))
    end
end

-- 创建Redis集群服务器
function redis_cluster_server.create_server(config)
    return RedisClusterServer:new(config)
end

return redis_cluster_server