--
-- ZeroMQ 异步线程池配置模块
-- 基于 lzmq-ffi 实现高性能异步IO
-- 参考现有集群代码实现
--

local zmq_async_config = {}

-- ZeroMQ 常量定义（与 C API 对应）
local ZMQ_CONSTANTS = {
    -- 上下文选项
    ZMQ_IO_THREADS = 1,          -- I/O 线程数
    ZMQ_MAX_SOCKETS = 2,         -- 最大套接字数
    ZMQ_SOCKET_LIMIT = 3,        -- 套接字限制
    ZMQ_THREAD_PRIORITY = 3,     -- 线程优先级
    ZMQ_THREAD_SCHED_POLICY = 4, -- 线程调度策略
    
    -- 套接字选项
    ZMQ_AFFINITY = 4,           -- CPU 亲和性
    ZMQ_IDENTITY = 5,             -- 套接字标识
    ZMQ_SUBSCRIBE = 6,            -- 订阅选项
    ZMQ_UNSUBSCRIBE = 7,          -- 取消订阅
    ZMQ_RATE = 8,                 -- 速率限制
    ZMQ_RECOVERY_IVL = 9,         -- 恢复间隔
    ZMQ_SNDBUF = 11,              -- 发送缓冲区大小
    ZMQ_RCVBUF = 12,              -- 接收缓冲区大小
    ZMQ_RCVMORE = 13,             -- 是否还有更多消息
    ZMQ_FD = 14,                  -- 文件描述符
    ZMQ_EVENTS = 15,              -- 事件标志
    ZMQ_TYPE = 16,                -- 套接字类型
    ZMQ_LINGER = 17,              -- 关闭时等待时间
    ZMQ_RECONNECT_IVL = 18,       -- 重连间隔
    ZMQ_BACKLOG = 19,             -- 监听队列长度
    ZMQ_RECONNECT_IVL_MAX = 21,   -- 最大重连间隔
    ZMQ_MAXMSGSIZE = 22,          -- 最大消息大小
    ZMQ_SNDHWM = 23,              -- 发送高水位
    ZMQ_RCVHWM = 24,              -- 接收高水位
    ZMQ_MULTICAST_HOPS = 25,        -- 多播跳数
    ZMQ_RCVTIMEO = 27,            -- 接收超时
    ZMQ_SNDTIMEO = 28,            -- 发送超时
    ZMQ_IPV4ONLY = 31,            -- 仅IPv4
    ZMQ_ROUTER_MANDATORY = 33,    -- ROUTER必须模式
    ZMQ_TCP_KEEPALIVE = 34,       -- TCP保活
    ZMQ_TCP_KEEPALIVE_CNT = 35,   -- TCP保活计数
    ZMQ_TCP_KEEPALIVE_IDLE = 36,  -- TCP保活空闲时间
    ZMQ_TCP_KEEPALIVE_INTVL = 37, -- TCP保活间隔
    ZMQ_TCP_ACCEPT_FILTER = 38,   -- TCP接受过滤器
    
    -- 套接字类型
    ZMQ_PAIR = 0,                 -- 配对套接字
    ZMQ_PUB = 1,                  -- 发布套接字
    ZMQ_SUB = 2,                  -- 订阅套接字
    ZMQ_REQ = 3,                  -- 请求套接字
    ZMQ_REP = 4,                  -- 响应套接字
    ZMQ_DEALER = 5,               -- 经销商套接字
    ZMQ_ROUTER = 6,               -- 路由器套接字
    ZMQ_PULL = 7,                 -- 拉取套接字
    ZMQ_PUSH = 8,                 -- 推送套接字
    ZMQ_XPUB = 9,                 -- 扩展发布套接字
    ZMQ_XSUB = 10,                -- 扩展订阅套接字
    
    -- 轮询事件
    ZMQ_POLLIN = 1,               -- 可读事件
    ZMQ_POLLOUT = 2,              -- 可写事件
    ZMQ_POLLERR = 4,              -- 错误事件
    
    -- 发送/接收标志
    ZMQ_DONTWAIT = 1,             -- 非阻塞
    ZMQ_SNDMORE = 2,              -- 还有更多消息
}

-- 默认配置
local DEFAULT_CONFIG = {
    -- 异步IO配置
    async_io = {
        enabled = true,                    -- 启用异步IO
        io_threads = 4,                    -- I/O线程数（推荐：CPU核心数）
        max_sockets = 2048,                -- 最大套接字数
        thread_priority = 0,               -- 线程优先级（0-正常，1-高）
        thread_sched_policy = "normal",    -- 线程调度策略
    },
    
    -- 连接池配置
    connection_pool = {
        enabled = true,                    -- 启用连接池
        max_pool_size = 20,                -- 连接池大小
        connection_timeout = 5000,         -- 连接超时（毫秒）
        idle_timeout = 300000,             -- 空闲超时（毫秒）
        heartbeat_interval = 30000,        -- 心跳间隔（毫秒）
        max_retry_attempts = 3,            -- 最大重试次数
        retry_delay = 1000,                -- 重试延迟（毫秒）
    },
    
    -- 套接字优化
    socket_options = {
        -- 缓冲区配置
        send_buffer_size = 256 * 1024,     -- 发送缓冲区大小（字节）
        recv_buffer_size = 256 * 1024,     -- 接收缓冲区大小（字节）
        send_hwm = 1000,                   -- 发送高水位
        recv_hwm = 1000,                    -- 接收高水位
        
        -- TCP优化
        tcp_keepalive = 1,                 -- TCP保活（0-禁用，1-启用）
        tcp_keepalive_cnt = 3,             -- TCP保活探测次数
        tcp_keepalive_idle = 60,           -- TCP保活空闲时间（秒）
        tcp_keepalive_intvl = 10,          -- TCP保活间隔（秒）
        
        -- 重连配置
        reconnect_ivl = 100,               -- 重连间隔（毫秒）
        reconnect_ivl_max = 30000,         -- 最大重连间隔（毫秒）
        
        -- 关闭配置
        linger = 1000,                     -- 关闭等待时间（毫秒）
        
        -- 消息大小限制
        max_msg_size = 100 * 1024 * 1024,  -- 最大消息大小（100MB）
        
        -- 超时配置
        send_timeout = 5000,               -- 发送超时（毫秒）
        recv_timeout = 5000,               -- 接收超时（毫秒）
        
        -- 监听队列
        backlog = 128,                     -- 监听队列长度
    },
    
    -- 性能调优
    performance = {
        -- 批处理配置
        batch_size = 1000,                 -- 批处理大小
        batch_timeout = 10,                -- 批处理超时（毫秒）
        
        -- 轮询配置
        poll_timeout = 100,                -- 轮询超时（毫秒）
        poll_interval = 1,                 -- 轮询间隔（毫秒）
        
        -- 事件处理
        max_events_per_loop = 1000,        -- 每循环最大事件数
        event_batch_size = 100,              -- 事件批处理大小
    },
    
    -- 集群配置
    cluster = {
        -- 节点发现
        discovery_enabled = true,            -- 启用节点发现
        discovery_interval = 5000,         -- 节点发现间隔（毫秒）
        discovery_timeout = 3000,            -- 节点发现超时（毫秒）
        
        -- 故障检测
        failure_detection_enabled = true,    -- 启用故障检测
        failure_detection_interval = 10000,  -- 故障检测间隔（毫秒）
        failure_detection_timeout = 5000,    -- 故障检测超时（毫秒）
        
        -- 负载均衡
        load_balancing_enabled = true,       -- 启用负载均衡
        load_balancing_algorithm = "least_connections", -- 负载均衡算法
        
        -- 数据同步
        data_sync_enabled = true,            -- 启用数据同步
        data_sync_interval = 5000,         -- 数据同步间隔（毫秒）
        data_sync_batch_size = 1000,       -- 数据同步批处理大小
    }
}

-- 配置验证和优化
function zmq_async_config.validate_config(config)
    local validated_config = {}
    
    -- 合并默认配置
    for k, v in pairs(DEFAULT_CONFIG) do
        validated_config[k] = validated_config[k] or {}
        if config and config[k] then
            for sk, sv in pairs(v) do
                validated_config[k][sk] = config[k][sk] or sv
            end
        else
            validated_config[k] = v
        end
    end
    
    -- 性能优化建议
    local optimizations = {}
    
    -- I/O线程数优化
    if validated_config.async_io.io_threads < 2 then
        table.insert(optimizations, "建议增加 I/O 线程数到 2-4 个以提高并发性能")
    end
    
    -- 套接字数优化
    if validated_config.async_io.max_sockets < 1024 then
        table.insert(optimizations, "建议增加最大套接字数到 1024 以上以支持更多并发连接")
    end
    
    -- 缓冲区优化
    if validated_config.socket_options.send_buffer_size < 65536 then
        table.insert(optimizations, "建议增加发送缓冲区大小到 64KB 以上")
    end
    
    if validated_config.socket_options.recv_buffer_size < 65536 then
        table.insert(optimizations, "建议增加接收缓冲区大小到 64KB 以上")
    end
    
    -- TCP保活优化
    if validated_config.socket_options.tcp_keepalive == 0 then
        table.insert(optimizations, "建议启用 TCP 保活以检测死连接")
    end
    
    -- 连接池优化
    if validated_config.connection_pool.max_pool_size < 10 then
        table.insert(optimizations, "建议增加连接池大小到 10 以上")
    end
    
    return validated_config, optimizations
end

-- 创建优化的 ZeroMQ 上下文
function zmq_async_config.create_optimized_context(config)
    local ffi = require "ffi"
    
    -- 加载 ZeroMQ C 库
    local zmq = ffi.load("zmq")
    
    -- 检查是否已经定义了ZeroMQ类型
    local zmq_types_defined = pcall(function()
        ffi.typeof("zmq_msg_t")
    end)
    
    -- 如果类型未定义，则定义ZeroMQ C API
    if not zmq_types_defined then
        ffi.cdef[[
            typedef void *zmq_ctx_t;
            typedef void *zmq_socket_t;
            
            zmq_ctx_t zmq_ctx_new(void);
            int zmq_ctx_destroy(zmq_ctx_t);
            int zmq_ctx_set(zmq_ctx_t, int option, int value);
            int zmq_ctx_get(zmq_ctx_t, int option);
            
            zmq_socket_t zmq_socket(zmq_ctx_t, int type);
            int zmq_close(zmq_socket_t);
            int zmq_setsockopt(zmq_socket_t, int option, const void *optval, size_t optvallen);
            int zmq_getsockopt(zmq_socket_t, int option, void *optval, size_t *optvallen);
            
            int zmq_bind(zmq_socket_t, const char *addr);
            int zmq_connect(zmq_socket_t, const char *addr);
            
            typedef struct zmq_msg_t {
                unsigned char [64] _;
            } zmq_msg_t;
            
            int zmq_msg_init(zmq_msg_t *msg);
            int zmq_msg_init_size(zmq_msg_t *msg, size_t size);
            int zmq_msg_init_data(zmq_msg_t *msg, void *data, size_t size, void (*ffn)(void *, void *), void *hint);
            size_t zmq_msg_size(zmq_msg_t *msg);
            void *zmq_msg_data(zmq_msg_t *msg);
            int zmq_msg_close(zmq_msg_t *msg);
            
            int zmq_msg_send(zmq_msg_t *msg, zmq_socket_t socket, int flags);
            int zmq_msg_recv(zmq_msg_t *msg, zmq_socket_t socket, int flags);
            
            int zmq_poll(zmq_pollitem_t *items, int nitems, long timeout);
            
            typedef struct zmq_pollitem_t {
                void *socket;
                int fd;
                short events;
                short revents;
            } zmq_pollitem_t;
            
            const char *zmq_strerror(int errnum);
            int zmq_errno(void);
        ]]
    end
    
    -- 验证配置
    local validated_config, optimizations = zmq_async_config.validate_config(config)
    
    -- 创建上下文
    local ctx = zmq.zmq_ctx_new()
    if ctx == nil then
        return nil, "Failed to create ZMQ context"
    end
    
    -- 设置 I/O 线程数
    local rc = zmq.zmq_ctx_set(ctx, ZMQ_CONSTANTS.ZMQ_IO_THREADS, validated_config.async_io.io_threads)
    if rc ~= 0 then
        zmq.zmq_ctx_destroy(ctx)
        return nil, "Failed to set IO threads"
    end
    
    -- 设置最大套接字数
    rc = zmq.zmq_ctx_set(ctx, ZMQ_CONSTANTS.ZMQ_MAX_SOCKETS, validated_config.async_io.max_sockets)
    if rc ~= 0 then
        zmq.zmq_ctx_destroy(ctx)
        return nil, "Failed to set max sockets"
    end
    
    -- 设置线程优先级（如果支持）
    if validated_config.async_io.thread_priority > 0 then
        rc = zmq.zmq_ctx_set(ctx, ZMQ_CONSTANTS.ZMQ_THREAD_PRIORITY, validated_config.async_io.thread_priority)
        if rc ~= 0 then
            print("Warning: Failed to set thread priority")
        end
    end
    
    return {
        context = ctx,
        config = validated_config,
        optimizations = optimizations,
        zmq_lib = zmq
    }
end

-- 创建优化的套接字
function zmq_async_config.create_optimized_socket(zmq_info, socket_type, is_server)
    local ffi = require "ffi"
    local zmq = zmq_info.zmq_lib
    local ctx = zmq_info.context
    local config = zmq_info.config
    
    -- 创建套接字
    local socket = zmq.zmq_socket(ctx, socket_type)
    if socket == nil then
        return nil, "Failed to create socket"
    end
    
    -- 设置套接字选项
    local opts = config.socket_options
    
    -- 缓冲区设置
    local sndbuf = ffi.new("int[1]", opts.send_buffer_size)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_SNDBUF, sndbuf, ffi.sizeof("int"))
    
    local rcvbuf = ffi.new("int[1]", opts.recv_buffer_size)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_RCVBUF, rcvbuf, ffi.sizeof("int"))
    
    -- 高水位设置
    local sndhwm = ffi.new("int[1]", opts.send_hwm)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_SNDHWM, sndhwm, ffi.sizeof("int"))
    
    local rcvhwm = ffi.new("int[1]", opts.recv_hwm)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_RCVHWM, rcvhwm, ffi.sizeof("int"))
    
    -- TCP保活设置
    if opts.tcp_keepalive > 0 then
        local keepalive = ffi.new("int[1]", opts.tcp_keepalive)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_TCP_KEEPALIVE, keepalive, ffi.sizeof("int"))
        
        local keepalive_cnt = ffi.new("int[1]", opts.tcp_keepalive_cnt)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_TCP_KEEPALIVE_CNT, keepalive_cnt, ffi.sizeof("int"))
        
        local keepalive_idle = ffi.new("int[1]", opts.tcp_keepalive_idle)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_TCP_KEEPALIVE_IDLE, keepalive_idle, ffi.sizeof("int"))
        
        local keepalive_intvl = ffi.new("int[1]", opts.tcp_keepalive_intvl)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_TCP_KEEPALIVE_INTVL, keepalive_intvl, ffi.sizeof("int"))
    end
    
    -- 重连设置
    local reconnect_ivl = ffi.new("int[1]", opts.reconnect_ivl)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_RECONNECT_IVL, reconnect_ivl, ffi.sizeof("int"))
    
    local reconnect_ivl_max = ffi.new("int[1]", opts.reconnect_ivl_max)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_RECONNECT_IVL_MAX, reconnect_ivl_max, ffi.sizeof("int"))
    
    -- 关闭设置
    local linger = ffi.new("int[1]", opts.linger)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_LINGER, linger, ffi.sizeof("int"))
    
    -- 消息大小限制
    if opts.max_msg_size > 0 then
        local max_msg_size = ffi.new("int64_t[1]", opts.max_msg_size)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_MAXMSGSIZE, max_msg_size, ffi.sizeof("int64_t"))
    end
    
    -- 超时设置
    local send_timeout = ffi.new("int[1]", opts.send_timeout)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_SNDTIMEO, send_timeout, ffi.sizeof("int"))
    
    local recv_timeout = ffi.new("int[1]", opts.recv_timeout)
    zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_RCVTIMEO, recv_timeout, ffi.sizeof("int"))
    
    -- 服务器特定设置
    if is_server then
        -- 监听队列长度
        local backlog = ffi.new("int[1]", opts.backlog)
        zmq.zmq_setsockopt(socket, ZMQ_CONSTANTS.ZMQ_BACKLOG, backlog, ffi.sizeof("int"))
    end
    
    return socket
end

-- 获取配置信息
function zmq_async_config.get_config_info()
    return {
        constants = ZMQ_CONSTANTS,
        default_config = DEFAULT_CONFIG,
        version = "1.0.0",
        description = "ZeroMQ 异步线程池配置模块"
    }
end

return zmq_async_config