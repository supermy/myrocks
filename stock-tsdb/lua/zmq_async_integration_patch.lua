--
-- ZeroMQ 异步线程池集成补丁
-- 自动生成于 %Y-%m-%d %H:%M:%S
--

-- 集成配置
local INTEGRATION_CONFIG = {
    enable_async_io = true,
    enable_thread_pool = false,
    enable_connection_pool = true,
    enable_cluster_optimization = false,
    io_threads = 4,
    max_connections = 2048,
    connection_pool_size = 50,
    buffer_pool_size = 100,
    async_workers = 8
}

-- 加载异步模块
local zmq_async_config = require "zmq_async_config"
local zmq_async_loop = require "zmq_async_loop"

-- 集成管理器
local AsyncIntegrationManager = {}
AsyncIntegrationManager.__index = AsyncIntegrationManager

function AsyncIntegrationManager:new(config)
    local obj = setmetatable({}, AsyncIntegrationManager)
    obj.config = config or INTEGRATION_CONFIG
    obj.async_loop = nil
    obj.integration_active = false
    return obj
end

function AsyncIntegrationManager:initialize_async_context()
    -- 创建优化的ZeroMQ上下文
    local zmq_config = zmq_async_config.create_default_config({
        io_threads = self.config.io_threads,
        max_connections = self.config.max_connections,
        connection_pool = {
            max_pool_size = self.config.connection_pool_size,
            connection_timeout = 30000,
            idle_timeout = 60000
        },
        buffer_pool = {
            pool_size = self.config.buffer_pool_size,
            buffer_size = 4096
        },
        async_processing = {
            enabled = self.config.enable_thread_pool,
            worker_threads = self.config.async_workers,
            task_queue_size = 10000,
            task_timeout = 30000
        }
    })
    
    -- 验证配置
    local is_valid, errors = zmq_async_config.validate_config(zmq_config)
    if not is_valid then
        return false, "配置验证失败: " .. table.concat(errors, ", ")
    end
    
    -- 创建异步事件循环
    self.async_loop = zmq_async_loop.create_event_loop({
        name = "integrated_async_loop",
        bind_addr = "127.0.0.1",
        client_port = 5555,
        cluster_port = 5556,
        max_connections = self.config.max_connections,
        zmq_config = zmq_config
    })
    
    return self.async_loop:initialize()
end

function AsyncIntegrationManager:start_async_processing()
    if not self.async_loop then
        return false, "异步循环未初始化"
    end
    
    local success, err = self.async_loop:start()
    if success then
        self.integration_active = true
        print("异步处理集成已启动")
        print(string.format("  I/O线程数: %d", self.config.io_threads))
        print(string.format("  连接池大小: %d", self.config.connection_pool_size))
        print(string.format("  缓冲区池大小: %d", self.config.buffer_pool_size))
        print(string.format("  异步工作线程: %d", self.config.async_workers))
    end
    
    return success, err
end

function AsyncIntegrationManager:stop_async_processing()
    if self.async_loop then
        self.async_loop:stop()
        self.integration_active = false
        print("异步处理集成已停止")
    end
end

function AsyncIntegrationManager:get_stats()
    if not self.async_loop then
        return {}
    end
    
    return {
        integration_active = self.integration_active,
        io_threads = self.config.io_threads,
        max_connections = self.config.max_connections,
        connection_pool_size = self.config.connection_pool_size,
        buffer_pool_size = self.config.buffer_pool_size,
        async_workers = self.config.async_workers,
        stats = self.async_loop.stats or {}
    }
end

-- 全局集成管理器实例
local async_integration_manager = AsyncIntegrationManager:new()

-- 集成函数
function integrate_async_thread_pool()
    return async_integration_manager:initialize_async_context()
end

function start_async_processing()
    return async_integration_manager:start_async_processing()
end

function stop_async_processing()
    return async_integration_manager:stop_async_processing()
end

function get_async_integration_stats()
    return async_integration_manager:get_stats()
end

-- 导出函数
return {
    integrate_async_thread_pool = integrate_async_thread_pool,
    start_async_processing = start_async_processing,
    stop_async_processing = stop_async_processing,
    get_async_integration_stats = get_async_integration_stats,
    async_integration_manager = async_integration_manager
}
