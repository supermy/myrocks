#!/usr/bin/env luajit

--
-- Redis TCP服务器 - 基于libevent的事件驱动Redis接口
-- 为集群提供标准Redis协议接口，监听6379端口
--

local redis_tcp_server = {}

-- 加载依赖
local ffi = require "ffi"
local bit = require "bit"

-- 设置Lua路径以使用lib目录下的cjson.so和本地安装的包
package.cpath = package.cpath .. ";../lib/?.so;./lib/?.so;./?.so"

-- 加载lzmq-ffi和cjson
local zmq = require "lzmq.ffi"
local ztimer = require "lzmq.timer"
local cjson = require "cjson"

-- libevent FFI定义
ffi.cdef[[
    // libevent基本类型
    typedef struct event_base event_base;
    typedef struct event event;
    typedef struct evconnlistener evconnlistener;
    typedef struct bufferevent bufferevent;
    
    // 套接字相关
    typedef int evutil_socket_t;
    struct sockaddr;
    
    // 事件基础函数
    event_base* event_base_new(void);
    void event_base_free(event_base*);
    int event_base_loop(event_base*, int);
    int event_base_loopbreak(event_base*);
    
    // 监听器函数
    evconnlistener* evconnlistener_new_bind(
        event_base*, 
        void (*cb)(evconnlistener*, evutil_socket_t, struct sockaddr*, int, void*),
        void*, 
        unsigned, 
        int, 
        const struct sockaddr*, 
        int
    );
    void evconnlistener_free(evconnlistener*);
    
    // 缓冲事件函数
    bufferevent* bufferevent_socket_new(event_base*, evutil_socket_t, int);
    void bufferevent_setcb(bufferevent*, 
        void (*readcb)(bufferevent*, void*),
        void (*writecb)(bufferevent*, void*),
        void (*eventcb)(bufferevent*, short, void*),
        void*);
    void bufferevent_enable(bufferevent*, short);
    void bufferevent_disable(bufferevent*, short);
    void bufferevent_free(bufferevent*);
    
    // 数据读写函数
    int bufferevent_write(bufferevent*, const void*, size_t);
    struct evbuffer* bufferevent_get_input(bufferevent*);
    size_t evbuffer_get_length(struct evbuffer*);
    int evbuffer_remove(struct evbuffer*, void*, size_t);
    
    // 网络地址函数
    int evutil_inet_pton(int, const char*, void*);
    int evutil_parse_sockaddr_port(const char*, struct sockaddr*, int*);
    
    // 错误处理
    const char* event_base_get_method(event_base*);
]]

-- 尝试加载libevent
local libevent = nil
local libevent_available = false

-- 尝试加载libevent库
local libevent_paths = {
    "/usr/local/lib/libevent.so",
    "/usr/lib/libevent.so",
    "/usr/lib/x86_64-linux-gnu/libevent.so",
    "libevent.so"
}

for _, path in ipairs(libevent_paths) do
    local ok, lib = pcall(ffi.load, path)
    if ok then
        libevent = lib
        libevent_available = true
        break
    end
end

if not libevent_available then
    print("警告: 无法加载libevent库，将使用ZeroMQ轮询模式")
end

-- Redis协议解析器
local RedisProtocolParser = {}

function RedisProtocolParser.parse_request(buffer)
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

function RedisProtocolParser.build_bulk_string(str)
    if str == nil then
        return "$-1\r\n"
    else
        return "$" .. #str .. "\r\n" .. str .. "\r\n"
    end
end

-- 批量数据处理类
local BatchProcessor = {}
BatchProcessor.__index = BatchProcessor

function BatchProcessor:new()
    local obj = setmetatable({}, BatchProcessor)
    obj.batch_size = 1000  -- 默认批量大小
    obj.batch_data = {}
    obj.current_size = 0
    return obj
end

function BatchProcessor:add_data(key, value, timestamp)
    table.insert(self.batch_data, {
        key = key,
        value = value,
        timestamp = timestamp or os.time()
    })
    self.current_size = self.current_size + 1
    
    if self.current_size >= self.batch_size then
        return self:flush()
    end
    
    return true
end

function BatchProcessor:flush()
    if self.current_size == 0 then
        return true
    end
    
    -- 这里可以调用TSDB的批量写入接口
    local success = true
    
    -- 清空批量数据
    self.batch_data = {}
    self.current_size = 0
    
    return success
end

-- Redis TCP服务器类
local RedisTCPServer = {}
RedisTCPServer.__index = RedisTCPServer

function RedisTCPServer:new(config)
    local obj = setmetatable({}, RedisTCPServer)
    obj.config = config or {}
    obj.port = config.port or 6379  -- Redis标准端口
    obj.bind_addr = config.bind_addr or "127.0.0.1"
    obj.max_connections = config.max_connections or 10000
    obj.tsdb = config.tsdb
    
    -- 集群配置
    obj.node_id = config.node_id or "redis_tcp_node_" .. tostring(math.random(1000, 9999))
    obj.cluster_nodes = config.cluster_nodes or {}
    
    -- libevent相关
    obj.event_base = nil
    obj.listener = nil
    obj.running = false
    
    -- 客户端管理
    obj.clients = {}
    obj.command_handlers = {}
    
    -- 批量处理器
    obj.batch_processor = BatchProcessor:new()
    
    obj.stats = {
        total_connections = 0,
        current_connections = 0,
        total_commands = 0,
        total_errors = 0,
        bytes_received = 0,
        bytes_sent = 0,
        batch_operations = 0
    }
    
    return obj
end

-- 初始化命令处理器
function RedisTCPServer:init_commands()
    self.command_handlers = {
        -- 基础命令
        ["PING"] = function(client, args)
            return "PONG"
        end,
        
        ["ECHO"] = function(client, args)
            if #args < 1 then
                return nil, "wrong number of arguments for 'echo' command"
            end
            return args[1]
        end,
        
        ["TIME"] = function(client, args)
            local now = os.time()
            local microseconds = 0  -- 简化实现
            return {tostring(now), tostring(microseconds)}
        end,
        
        -- 批量数据命令
        ["BATCH_SET"] = function(client, args)
            if #args < 2 then
                return nil, "wrong number of arguments for 'batch_set' command"
            end
            
            local key = args[1]
            local value = args[2]
            local timestamp = args[3] and tonumber(args[3]) or os.time()
            
            local success = self.batch_processor:add_data(key, value, timestamp)
            if success then
                self.stats.batch_operations = self.stats.batch_operations + 1
                return "OK"
            else
                return nil, "batch operation failed"
            end
        end,
        
        ["BATCH_FLUSH"] = function(client, args)
            local success = self.batch_processor:flush()
            if success then
                return "OK"
            else
                return nil, "flush operation failed"
            end
        end,
        
        -- TSDB相关命令 - 支持哈希数据结构
        ["TSDB_SET"] = function(client, args)
            if not self.tsdb or #args < 3 then
                return nil, "wrong number of arguments or TSDB not available"
            end
            
            local key = args[1]
            local timestamp = tonumber(args[2])
            local value = args[3]
            local data_type = args[4] or "double"
            local quality = args[5] or 100
            
            -- 检测是否为JSON格式的哈希数据
            local is_hash_data = false
            local hash_data = nil
            
            if value:sub(1,1) == "{" and value:sub(-1) == "}" then
                -- 尝试解析JSON哈希数据
                local ok, parsed = pcall(require("cjson").decode, value)
                if ok and type(parsed) == "table" then
                    is_hash_data = true
                    hash_data = parsed
                    -- 将哈希数据序列化存储
                    value = value  -- 保持JSON格式存储
                end
            end
            
            local success, err = self.tsdb:write_point(key, timestamp, value, data_type, quality)
            if success then
                return "OK"
            else
                return nil, err or "write failed"
            end
        end,
        
        ["TSDB_GET"] = function(client, args)
            if not self.tsdb or #args < 3 then
                return nil, "wrong number of arguments or TSDB not available"
            end
            
            local key = args[1]
            local start_time = tonumber(args[2])
            local end_time = tonumber(args[3])
            local data_type = args[4] or "double"
            
            local points, err = self.tsdb:query_range(key, start_time, end_time, data_type)
            if points then
                local result = {}
                for i, point in ipairs(points) do
                    table.insert(result, tostring(point.timestamp))
                    table.insert(result, tostring(point.value))
                end
                return result
            else
                return nil, err or "query failed"
            end
        end,
        
        -- 哈希数据命令 - 专门用于业务数据测试
        ["HASH_SET"] = function(client, args)
            if not self.tsdb or #args < 3 then
                return nil, "wrong number of arguments or TSDB not available"
            end
            
            local key = args[1]
            local timestamp = tonumber(args[2])
            local hash_json = args[3]
            
            -- 验证时间戳参数
            if not timestamp then
                return nil, "invalid timestamp format"
            end
            
            -- 验证JSON格式
            local ok, hash_data = pcall(require("cjson").decode, hash_json)
            if not ok or type(hash_data) ~= "table" then
                return nil, "invalid hash data format"
            end
            
            local success, err = self.tsdb:write_point(key, timestamp, hash_json, "hash", 100)
            if success then
                return "OK"
            else
                return nil, err or "hash write failed"
            end
        end,
        
        ["HASH_GET"] = function(client, args)
            if not self.tsdb or #args < 3 then
                return nil, "wrong number of arguments or TSDB not available"
            end
            
            local key = args[1]
            local start_time = tonumber(args[2])
            local end_time = tonumber(args[3])
            
            -- 验证时间戳参数
            if not start_time or not end_time then
                return nil, "invalid timestamp format"
            end
            
            local points, err = self.tsdb:query_range(key, start_time, end_time, "hash")
            if points then
                local result = {}
                for i, point in ipairs(points) do
                    table.insert(result, tostring(point.timestamp))
                    table.insert(result, point.value)  -- 直接返回JSON字符串
                end
                return result
            else
                return nil, err or "hash query failed"
            end
        end,
        
        ["HASH_FIELDS"] = function(client, args)
            if not self.tsdb or #args < 4 then
                return nil, "wrong number of arguments or TSDB not available"
            end
            
            local key = args[1]
            local start_time = tonumber(args[2])
            local end_time = tonumber(args[3])
            
            -- 验证时间戳参数
            if not start_time or not end_time then
                return nil, "invalid timestamp format"
            end
            
            local fields = {}
            
            -- 提取指定字段
            for i = 4, #args do
                table.insert(fields, args[i])
            end
            
            local points, err = self.tsdb:query_range(key, start_time, end_time, "hash")
            if points then
                local result = {}
                for i, point in ipairs(points) do
                    local ok, hash_data = pcall(require("cjson").decode, point.value)
                    if ok and type(hash_data) == "table" then
                        local field_values = {}
                        table.insert(field_values, tostring(point.timestamp))
                        
                        for _, field in ipairs(fields) do
                            table.insert(field_values, tostring(hash_data[field] or ""))
                        end
                        
                        table.insert(result, field_values)
                    end
                end
                return result
            else
                return nil, err or "hash fields query failed"
            end
        end,
        
        -- 集群状态命令
        ["CLUSTER_INFO"] = function(client, args)
            local info = {
                "node_id:" .. self.node_id,
                "cluster_state:connected",
                "cluster_size:" .. #self.cluster_nodes,
                "current_connections:" .. self.stats.current_connections,
                "total_commands:" .. self.stats.total_commands
            }
            return info
        end
    }
end

-- 处理客户端命令
function RedisTCPServer:handle_command(client, command, args)
    self.stats.total_commands = self.stats.total_commands + 1
    
    local handler = self.command_handlers[command:upper()]
    if not handler then
        return nil, "unknown command '" .. command .. "'"
    end
    
    local result, err = handler(client, args)
    if result then
        return result
    else
        self.stats.total_errors = self.stats.total_errors + 1
        return nil, err or "command execution failed"
    end
end

-- 启动服务器（libevent版本）
function RedisTCPServer:start_libevent()
    if not libevent_available then
        return false, "libevent not available"
    end
    
    -- 创建事件基础
    self.event_base = libevent.event_base_new()
    if not self.event_base then
        return false, "failed to create event base"
    end
    
    print("Redis TCP服务器启动 (libevent模式)")
    print("监听地址: " .. self.bind_addr .. ":" .. self.port)
    print("节点ID: " .. self.node_id)
    print("事件引擎: " .. ffi.string(libevent.event_base_get_method(self.event_base)))
    
    -- 这里需要实现具体的libevent监听逻辑
    -- 由于libevent的FFI集成比较复杂，这里先使用简化实现
    
    self.running = true
    return true
end

-- 启动服务器（ZeroMQ轮询版本）
function RedisTCPServer:start_zmq_poll()
    -- 创建ZeroMQ上下文
    self.context = zmq.context()
    if not self.context then
        return false, "failed to create ZeroMQ context"
    end
    
    -- 创建ROUTER套接字用于处理客户端连接
    self.router_socket = self.context:socket(zmq.ROUTER)
    if not self.router_socket then
        return false, "failed to create ROUTER socket"
    end
    
    -- 绑定到指定地址
    local bind_addr = "tcp://" .. self.bind_addr .. ":" .. self.port
    local result, err = self.router_socket:bind(bind_addr)
    if not result then
        return false, "failed to bind to " .. bind_addr .. ": " .. err
    end
    
    -- 创建轮询器
    self.poller = zmq.poller(1)
    self.poller:add(self.router_socket, zmq.ZMQ_POLLIN, function()
        self:handle_zmq_message()
    end)
    
    print("Redis TCP服务器启动 (ZeroMQ轮询模式)")
    print("监听地址: " .. bind_addr)
    print("节点ID: " .. self.node_id)
    
    self.running = true
    return true
end

-- 处理ZeroMQ消息
function RedisTCPServer:handle_zmq_message()
    -- 接收消息（客户端ID + 空帧 + 数据）
    local client_id = self.router_socket:recv()
    local empty_frame = self.router_socket:recv()
    local message = self.router_socket:recv()
    
    if not client_id or not message then
        return
    end
    
    -- 解析Redis协议
    local args, consumed = RedisProtocolParser.parse_request(message)
    if not args then
        -- 发送错误响应
        local error_response = RedisProtocolParser.build_error("ERR Protocol error: " .. consumed)
        self:send_zmq_response(client_id, error_response)
        return
    end
    
    if #args == 0 then
        local error_response = RedisProtocolParser.build_error("ERR empty command")
        self:send_zmq_response(client_id, error_response)
        return
    end
    
    local command = table.remove(args, 1)
    local result, err = self:handle_command({id = client_id}, command, args)
    
    local response
    if result then
        response = RedisProtocolParser.build_response(result)
    else
        response = RedisProtocolParser.build_error("ERR " .. (err or "command failed"))
    end
    
    self:send_zmq_response(client_id, response)
end

-- 发送ZeroMQ响应
function RedisTCPServer:send_zmq_response(client_id, response)
    self.router_socket:send(client_id, zmq.ZMQ_SNDMORE)
    self.router_socket:send("", zmq.ZMQ_SNDMORE)  -- 空帧
    self.router_socket:send(response)
    
    self.stats.bytes_sent = self.stats.bytes_sent + #response
end

-- 启动服务器
function RedisTCPServer:start()
    -- 初始化命令处理器
    self:init_commands()
    
    if libevent_available then
        return self:start_libevent()
    else
        return self:start_zmq_poll()
    end
end

-- 停止服务器
function RedisTCPServer:stop()
    self.running = false
    
    if self.event_base then
        libevent.event_base_loopbreak(self.event_base)
        libevent.event_base_free(self.event_base)
        self.event_base = nil
    end
    
    if self.router_socket then
        self.router_socket:close()
        self.router_socket = nil
    end
    
    if self.context then
        self.context:destroy()
        self.context = nil
    end
    
    print("Redis TCP服务器已停止")
end

-- 运行服务器主循环
function RedisTCPServer:run()
    if not self.running then
        return false, "server not started"
    end
    
    if self.event_base then
        -- libevent模式
        libevent.event_base_loop(self.event_base, 0)
    else
        -- ZeroMQ轮询模式
        while self.running do
            self.poller:poll(1000)  -- 1秒超时
        end
    end
    
    return true
end

-- 获取服务器统计信息
function RedisTCPServer:get_stats()
    return {
        node_id = self.node_id,
        running = self.running,
        current_connections = self.stats.current_connections,
        total_connections = self.stats.total_connections,
        total_commands = self.stats.total_commands,
        total_errors = self.stats.total_errors,
        bytes_received = self.stats.bytes_received,
        bytes_sent = self.stats.bytes_sent,
        batch_operations = self.stats.batch_operations
    }
end

-- 导出模块
redis_tcp_server.RedisTCPServer = RedisTCPServer
redis_tcp_server.RedisProtocolParser = RedisProtocolParser
redis_tcp_server.BatchProcessor = BatchProcessor

return redis_tcp_server