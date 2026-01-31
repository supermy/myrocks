--
-- ZeroMQ集群管理Lua脚本
-- 提供分布式集群功能
--

local cluster = {}
local zmq = require "zmq"
local ffi = require "ffi"

-- 加载工具函数并设置模块路径
local utils = require "commons.utils"
utils.setup_module_paths()
local cjson = utils.safe_require_cjson()

-- FFI定义ZeroMQ C接口
ffi.cdef[[
    // ZeroMQ基本类型
typedef void *void;
typedef struct zmq_msg_t {
        unsigned char [64] _;
} zmq_msg_t;

    // 上下文和套接字
typedef void *zmq_ctx_t;
typedef void *zmq_socket_t;

zmq_ctx_t zmq_ctx_new(void);
int zmq_ctx_destroy(zmq_ctx_t);
int zmq_ctx_set(zmq_ctx_t, int option, int value);
int zmq_ctx_get(zmq_ctx_t, int option);

    // 套接字操作
zmq_socket_t zmq_socket(zmq_ctx_t, int type);
int zmq_close(zmq_socket_t);
int zmq_bind(zmq_socket_t, const char *addr);
int zmq_connect(zmq_socket_t, const char *addr);
int zmq_setsockopt(zmq_socket_t, int option, const void *optval, size_t optvallen);
int zmq_getsockopt(zmq_socket_t, int option, void *optval, size_t *optvallen);

    // 消息操作
int zmq_msg_init(zmq_msg_t *msg);
int zmq_msg_init_size(zmq_msg_t *msg, size_t size);
int zmq_msg_init_data(zmq_msg_t *msg, void *data, size_t size, void (*ffn)(void *, void *), void *hint);
size_t zmq_msg_size(zmq_msg_t *msg);
void *zmq_msg_data(zmq_msg_t *msg);
int zmq_msg_close(zmq_msg_t *msg);

    // 发送和接收
int zmq_msg_send(zmq_msg_t *msg, zmq_socket_t socket, int flags);
int zmq_msg_recv(zmq_msg_t *msg, zmq_socket_t socket, int flags);

    // 错误处理
const char *zmq_strerror(int errnum);
int zmq_errno(void);

    // 常量
static const int ZMQ_REQ = 3;
static const int ZMQ_REP = 4;
static const int ZMQ_PUB = 1;
static const int ZMQ_SUB = 2;
static const int ZMQ_PUSH = 5;
static const int ZMQ_PULL = 6;
static const int ZMQ_DEALER = 5;
static const int ZMQ_ROUTER = 6;
static const int ZMQ_PAIR = 0;

static const int ZMQ_SNDMORE = 1;
static const int ZMQ_DONTWAIT = 2;
]]

-- 集群节点状态
local NODE_STATUS = {
    UNKNOWN = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    DISCONNECTED = 3,
    ERROR = 4
}

-- 消息类型
local MESSAGE_TYPES = {
    HEARTBEAT = "heartbeat",
    DATA_SYNC = "data_sync",
    DATA_REQUEST = "data_request",
    CLUSTER_INFO = "cluster_info",
    NODE_JOIN = "node_join",
    NODE_LEAVE = "node_leave",
    LEADER_ELECTION = "leader_election",
    CONFIG_UPDATE = "config_update"
}

-- 集群管理器
local ClusterManager = {}
ClusterManager.__index = ClusterManager

function ClusterManager:new(config)
    local obj = setmetatable({}, ClusterManager)
    obj.config = config or {}
    obj.nodes = {}
    obj.local_node = nil
    obj.leader_node = nil
    obj.zmq_context = nil
    obj.sockets = {}
    obj.message_handlers = {}
    obj.is_running = false
    obj.message_queue = {}
    obj.stats = {
        messages_sent = 0,
        messages_received = 0,
        bytes_sent = 0,
        bytes_received = 0,
        errors = 0
    }
    
    -- 初始化本地节点
    obj.local_node = {
        id = config.node_id or 0,
        host = config.host or "127.0.0.1",
        port = config.port or 5555,
        status = NODE_STATUS.UNKNOWN,
        last_heartbeat = 0,
        role = config.role or "follower"
    }
    
    return obj
end

function ClusterManager:initialize()
    -- 初始化ZeroMQ上下文
    self.zmq_context = ffi.C.zmq_ctx_new()
    if self.zmq_context == nil then
        return false, "创建ZeroMQ上下文失败"
    end
    
    -- 设置上下文选项
    ffi.C.zmq_ctx_set(self.zmq_context, 1, 1)  -- IO线程数
    ffi.C.zmq_ctx_set(self.zmq_context, 2, 1000)  -- 最大套接字数
    
    -- 注册消息处理器
    self:register_handlers()
    
    return true
end

function ClusterManager:register_handlers()
    -- 注册消息处理器
    self.message_handlers[MESSAGE_TYPES.HEARTBEAT] = function(msg)
        return self:handle_heartbeat(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.DATA_SYNC] = function(msg)
        return self:handle_data_sync(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.DATA_REQUEST] = function(msg)
        return self:handle_data_request(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.CLUSTER_INFO] = function(msg)
        return self:handle_cluster_info(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.NODE_JOIN] = function(msg)
        return self:handle_node_join(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.NODE_LEAVE] = function(msg)
        return self:handle_node_leave(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.LEADER_ELECTION] = function(msg)
        return self:handle_leader_election(msg)
    end
    
    self.message_handlers[MESSAGE_TYPES.CONFIG_UPDATE] = function(msg)
        return self:handle_config_update(msg)
    end
end

function ClusterManager:start()
    -- 启动集群管理器
    if self.is_running then
        return false, "集群管理器已在运行"
    end
    
    -- 创建监听套接字
    local bind_addr = string.format("tcp://*:%d", self.local_node.port)
    local rep_socket = self:create_socket(ffi.C.ZMQ_REP)
    
    if not rep_socket then
        return false, "创建监听套接字失败"
    end
    
    local rc = ffi.C.zmq_bind(rep_socket, bind_addr)
    if rc ~= 0 then
        local error = ffi.string(ffi.C.zmq_strerror(ffi.C.zmq_errno()))
        return false, "绑定地址失败: " .. error
    end
    
    self.sockets.rep = rep_socket
    self.local_node.status = NODE_STATUS.CONNECTED
    self.is_running = true
    
    -- 连接到其他节点
    self:connect_to_peers()
    
    -- 启动工作线程
    self:start_worker_threads()
    
    return true
end

function ClusterManager:stop()
    -- 停止集群管理器
    if not self.is_running then
        return
    end
    
    self.is_running = false
    
    -- 关闭所有套接字
    for name, socket in pairs(self.sockets) do
        if socket then
            ffi.C.zmq_close(socket)
        end
    end
    
    -- 关闭ZeroMQ上下文
    if self.zmq_context then
        ffi.C.zmq_ctx_destroy(self.zmq_context)
        self.zmq_context = nil
    end
    
    self.local_node.status = NODE_STATUS.DISCONNECTED
end

function ClusterManager:create_socket(socket_type)
    -- 创建ZeroMQ套接字
    local socket = ffi.C.zmq_socket(self.zmq_context, socket_type)
    if socket == nil then
        return nil
    end
    
    -- 设置套接字选项
    local linger = ffi.new("int[1]", 1000)  -- 1秒超时
    ffi.C.zmq_setsockopt(socket, 17, linger, ffi.sizeof("int"))  -- ZMQ_LINGER
    
    return socket
end

function ClusterManager:connect_to_peers()
    -- 连接到集群中的其他节点
    local peers = self.config.peers or {}
    
    for _, peer in ipairs(peers) do
        if peer.id ~= self.local_node.id then
            local addr = string.format("tcp://%s:%d", peer.host, peer.port)
            local req_socket = self:create_socket(ffi.C.ZMQ_REQ)
            
            if req_socket then
                local rc = ffi.C.zmq_connect(req_socket, addr)
                if rc == 0 then
                    self.nodes[peer.id] = {
                        id = peer.id,
                        host = peer.host,
                        port = peer.port,
                        socket = req_socket,
                        status = NODE_STATUS.CONNECTING,
                        last_heartbeat = 0
                    }
                else
                    ffi.C.zmq_close(req_socket)
                end
            end
        end
    end
end

function ClusterManager:send_message(node_id, message_type, data)
    -- 发送消息到指定节点
    local node = self.nodes[node_id]
    if not node or not node.socket then
        return false, "节点不存在或不可用"
    end
    
    -- 构建消息
    local message = {
        type = message_type,
        from = self.local_node.id,
        to = node_id,
        timestamp = os.time(),
        data = data or {}
    }
    
    local message_str = cjson.encode(message)
    
    -- 创建ZeroMQ消息
    local msg = ffi.new("zmq_msg_t")
    local rc = ffi.C.zmq_msg_init_size(msg, #message_str)
    if rc ~= 0 then
        return false, "初始化消息失败"
    end
    
    -- 复制消息数据
    local data_ptr = ffi.C.zmq_msg_data(msg)
    ffi.copy(data_ptr, message_str, #message_str)
    
    -- 发送消息
    rc = ffi.C.zmq_msg_send(msg, node.socket, 0)
    ffi.C.zmq_msg_close(msg)
    
    if rc == -1 then
        local error = ffi.string(ffi.C.zmq_strerror(ffi.C.zmq_errno()))
        return false, "发送消息失败: " .. error
    end
    
    -- 更新统计信息
    self.stats.messages_sent = self.stats.messages_sent + 1
    self.stats.bytes_sent = self.stats.bytes_sent + #message_str
    
    return true
end

function ClusterManager:broadcast_message(message_type, data)
    -- 广播消息到所有节点
    local success_count = 0
    local errors = {}
    
    for node_id, node in pairs(self.nodes) do
        local success, error = self:send_message(node_id, message_type, data)
        if success then
            success_count = success_count + 1
        else
            table.insert(errors, string.format("节点%d: %s", node_id, error))
        end
    end
    
    return success_count, errors
end

function ClusterManager:receive_message(timeout_ms)
    -- 接收消息（带超时）
    if not self.sockets.rep then
        return nil, "没有监听套接字"
    end
    
    -- 设置接收超时
    local timeout = ffi.new("int[1]", timeout_ms or 1000)
    ffi.C.zmq_setsockopt(self.sockets.rep, 27, timeout, ffi.sizeof("int"))  -- ZMQ_RCVTIMEO
    
    -- 接收消息
    local msg = ffi.new("zmq_msg_t")
    local rc = ffi.C.zmq_msg_init(msg)
    if rc ~= 0 then
        return nil, "初始化消息失败"
    end
    
    rc = ffi.C.zmq_msg_recv(msg, self.sockets.rep, 0)
    if rc == -1 then
        local errno = ffi.C.zmq_errno()
        if errno == 11 then  -- EAGAIN
            ffi.C.zmq_msg_close(msg)
            return nil, "接收超时"
        end
        
        local error = ffi.string(ffi.C.zmq_strerror(errno))
        ffi.C.zmq_msg_close(msg)
        return nil, "接收消息失败: " .. error
    end
    
    -- 获取消息数据
    local size = ffi.C.zmq_msg_size(msg)
    local data_ptr = ffi.C.zmq_msg_data(msg)
    local message_str = ffi.string(data_ptr, size)
    
    ffi.C.zmq_msg_close(msg)
    
    -- 更新统计信息
    self.stats.messages_received = self.stats.messages_received + 1
    self.stats.bytes_received = self.stats.bytes_received + #message_str
    
    -- 解析消息
    local success, message = pcall(cjson.decode, message_str)
    if not success then
        return nil, "解析消息失败: " .. message
    end
    
    return message
end

function ClusterManager:handle_heartbeat(message)
    -- 处理心跳消息
    local node_id = message.from
    local node = self.nodes[node_id]
    
    if node then
        node.last_heartbeat = message.timestamp
        node.status = NODE_STATUS.CONNECTED
        
        -- 回复心跳
        self:send_message(node_id, MESSAGE_TYPES.HEARTBEAT, {
            status = "alive",
            load = 0.5,  -- 负载信息
            uptime = os.time() - self.start_time
        })
    end
    
    return true
end

function ClusterManager:handle_data_sync(message)
    -- 处理数据同步消息
    local data = message.data
    
    -- 这里应该调用存储引擎进行数据同步
    -- 简化处理，直接返回成功
    
    return true, "数据同步成功"
end

function ClusterManager:handle_data_request(message)
    -- 处理数据请求消息
    local request = message.data
    
    -- 这里应该查询本地存储并返回数据
    -- 简化处理，返回空数据
    
    return true, {
        symbol = request.symbol,
        data = {},
        timestamp = os.time()
    }
end

function ClusterManager:handle_cluster_info(message)
    -- 处理集群信息消息
    local cluster_info = {
        nodes = {},
        leader = self.leader_node,
        local_node = self.local_node
    }
    
    -- 收集所有节点信息
    for node_id, node in pairs(self.nodes) do
        table.insert(cluster_info.nodes, {
            id = node_id,
            host = node.host,
            port = node.port,
            status = node.status,
            last_heartbeat = node.last_heartbeat
        })
    end
    
    return true, cluster_info
end

function ClusterManager:handle_node_join(message)
    -- 处理节点加入消息
    local node_info = message.data
    
    -- 添加新节点
    self.nodes[node_info.id] = {
        id = node_info.id,
        host = node_info.host,
        port = node_info.port,
        status = NODE_STATUS.CONNECTED,
        last_heartbeat = os.time()
    }
    
    return true, "节点加入成功"
end

function ClusterManager:handle_node_leave(message)
    -- 处理节点离开消息
    local node_id = message.from
    
    -- 从节点列表中移除
    if self.nodes[node_id] then
        self.nodes[node_id] = nil
    end
    
    return true, "节点离开成功"
end

function ClusterManager:handle_leader_election(message)
    -- 处理领导者选举消息
    local election_data = message.data
    
    -- 简化处理，直接接受新的领导者
    self.leader_node = election_data.leader_id
    
    return true, "领导者选举成功"
end

function ClusterManager:handle_config_update(message)
    -- 处理配置更新消息
    local config_data = message.data
    
    -- 这里应该更新本地配置
    -- 简化处理，直接返回成功
    
    return true, "配置更新成功"
end

function ClusterManager:start_worker_threads()
    -- 启动工作线程
    
    -- 心跳线程
    self.heartbeat_thread = coroutine.create(function()
        while self.is_running do
            self:send_heartbeat()
            coroutine.yield()
        end
    end)
    
    -- 消息处理线程
    self.message_thread = coroutine.create(function()
        while self.is_running do
            local message, error = self:receive_message(1000)
            if message then
                self:process_message(message)
            end
            coroutine.yield()
        end
    end)
    
    -- 监控线程
    self.monitor_thread = coroutine.create(function()
        while self.is_running do
            self:monitor_cluster()
            coroutine.yield()
        end
    end)
    
    self.start_time = os.time()
end

function ClusterManager:send_heartbeat()
    -- 发送心跳消息
    local heartbeat_data = {
        node_id = self.local_node.id,
        status = self.local_node.status,
        timestamp = os.time(),
        load = 0.5,  -- 负载信息
        uptime = os.time() - self.start_time
    }
    
    self:broadcast_message(MESSAGE_TYPES.HEARTBEAT, heartbeat_data)
end

function ClusterManager:process_message(message)
    -- 处理接收到的消息
    local handler = self.message_handlers[message.type]
    
    if handler then
        local success, result = pcall(handler, message)
        if not success then
            self.stats.errors = self.stats.errors + 1
        end
    else
        self.stats.errors = self.stats.errors + 1
    end
end

function ClusterManager:monitor_cluster()
    -- 监控集群状态
    local current_time = os.time()
    
    -- 检查节点心跳超时
    for node_id, node in pairs(self.nodes) do
        if node.status == NODE_STATUS.CONNECTED then
            local time_since_heartbeat = current_time - node.last_heartbeat
            if time_since_heartbeat > 30 then  -- 30秒超时
                node.status = NODE_STATUS.DISCONNECTED
            end
        end
    end
    
    -- 检查领导者状态
    if self.leader_node then
        local leader = self.nodes[self.leader_node]
        if leader and leader.status ~= NODE_STATUS.CONNECTED then
            -- 触发领导者选举
            self:trigger_leader_election()
        end
    end
end

function ClusterManager:trigger_leader_election()
    -- 触发领导者选举
    local election_data = {
        candidate_id = self.local_node.id,
        term = os.time(),
        last_log_index = 0,
        last_log_term = 0
    }
    
    self:broadcast_message(MESSAGE_TYPES.LEADER_ELECTION, election_data)
end

function ClusterManager:get_cluster_status()
    -- 获取集群状态
    local status = {
        local_node = self.local_node,
        leader_node = self.leader_node,
        nodes = {},
        stats = self.stats,
        is_running = self.is_running
    }
    
    -- 收集所有节点状态
    for node_id, node in pairs(self.nodes) do
        table.insert(status.nodes, {
            id = node_id,
            host = node.host,
            port = node.port,
            status = node.status,
            last_heartbeat = node.last_heartbeat
        })
    end
    
    return status
end

function ClusterManager:get_stats()
    -- 获取统计信息
    return self.stats
end

function ClusterManager:is_leader()
    -- 检查是否为领导者节点
    return self.local_node.id == self.leader_node
end

function ClusterManager:get_local_node()
    -- 获取本地节点信息
    return self.local_node
end

-- 集群工厂函数
function cluster.create_manager(config)
    return ClusterManager:new(config)
end

-- 导出函数和常量
cluster.NODE_STATUS = NODE_STATUS
cluster.MESSAGE_TYPES = MESSAGE_TYPES
cluster.ClusterManager = ClusterManager

return cluster