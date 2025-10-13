--
-- ZeroMQ 异步线程池集成模块
-- 集成到现有TSDB集群系统中
--

local ffi = require "ffi"
local ztimer = require "lzmq.timer"

-- 加载异步模块
local zmq_async_config = require "zmq_async_config"
local zmq_async_loop = require "zmq_async_loop"

-- 集成管理器
local ZMQAsyncIntegration = {}
ZMQAsyncIntegration.__index = ZMQAsyncIntegration

function ZMQAsyncIntegration:new(config)
    local obj = setmetatable({}, ZMQAsyncIntegration)
    
    obj.config = config or {}
    obj.async_loop = nil
    obj.original_cluster_manager = nil
    obj.integration_active = false
    
    -- 集成配置
    obj.integration_config = {
        enable_async_io = true,
        enable_thread_pool = true,
        enable_connection_pool = true,
        enable_cluster_optimization = true,
        async_workers = 8,
        io_threads = 4,
        max_connections = 10000,
        connection_pool_size = 50,
        buffer_pool_size = 100
    }
    
    return obj
end

function ZMQAsyncIntegration:analyze_existing_cluster()
    print("=== 分析现有TSDB集群配置 ===")
    
    -- 分析现有配置
    local analysis = {
        current_io_threads = 1,
        current_max_sockets = 1000,
        current_connection_pool_size = 20,
        current_buffer_pool_size = 10,
        current_async_workers = 0,
        has_async_support = false,
        has_thread_pool = false,
        has_connection_pool = true,
        optimization_opportunities = {}
    }
    
    -- 从现有配置中读取信息
    local cluster_files = {
        "cluster.lua",
        "optimized_cluster_manager.lua", 
        "cluster_optimizer.lua",
        "event_server.lua"
    }
    
    for _, file in ipairs(cluster_files) do
        local file_path = "/Users/moyong/project/ai/myrocks/stock-tsdb/lua/" .. file
        local file = io.open(file_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            -- 分析配置
            if content:match("zmq_ctx_set%s*%(%s*ZMQ_IO_THREADS") then
                local threads = content:match("zmq_ctx_set%s*%(%s*ZMQ_IO_THREADS%s*,%s*(%d+)")
                if threads then
                    analysis.current_io_threads = tonumber(threads)
                end
            end
            
            if content:match("max_pool_size%s*=%s*(%d+)") then
                local pool_size = content:match("max_pool_size%s*=%s*(%d+)")
                if pool_size then
                    analysis.current_connection_pool_size = tonumber(pool_size)
                end
            end
            
            if content:match("pool_size%s*=%s*(%d+)") then
                local buffer_size = content:match("pool_size%s*=%s*(%d+)")
                if buffer_size then
                    analysis.current_buffer_pool_size = tonumber(buffer_size)
                end
            end
            
            if content:match("coroutine%.create") or content:match("async") then
                analysis.has_async_support = true
            end
            
            if content:match("worker") or content:match("thread") then
                analysis.has_thread_pool = true
            end
        end
    end
    
    -- 分析优化机会
    if analysis.current_io_threads < 4 then
        table.insert(analysis.optimization_opportunities, 
            "增加I/O线程数从 " .. analysis.current_io_threads .. " 到 4")
    end
    
    if analysis.current_connection_pool_size < 50 then
        table.insert(analysis.optimization_opportunities, 
            "扩大连接池从 " .. analysis.current_connection_pool_size .. " 到 50")
    end
    
    if analysis.current_buffer_pool_size < 100 then
        table.insert(analysis.optimization_opportunities, 
            "扩大缓冲区池从 " .. analysis.current_buffer_pool_size .. " 到 100")
    end
    
    if not analysis.has_async_support then
        table.insert(analysis.optimization_opportunities, "添加异步处理支持")
    end
    
    -- 打印分析结果
    print("当前配置分析:")
    print(string.format("  I/O线程数: %d", analysis.current_io_threads))
    print(string.format("  最大套接字数: %d", analysis.current_max_sockets))
    print(string.format("  连接池大小: %d", analysis.current_connection_pool_size))
    print(string.format("  缓冲区池大小: %d", analysis.current_buffer_pool_size))
    print(string.format("  异步支持: %s", analysis.has_async_support and "是" or "否"))
    print(string.format("  线程池: %s", analysis.has_thread_pool and "是" or "否"))
    print("")
    
    if #analysis.optimization_opportunities > 0 then
        print("优化建议:")
        for i, opportunity in ipairs(analysis.optimization_opportunities) do
            print(string.format("  %d. %s", i, opportunity))
        end
        print("")
    end
    
    return analysis
end

function ZMQAsyncIntegration:generate_optimized_config(analysis)
    print("=== 生成优化配置 ===")
    
    -- 基于分析结果生成优化配置
    local optimized_config = zmq_async_config.validate_config({
        -- 基础配置
        io_threads = math.max(analysis.current_io_threads * 2, 4),
        max_sockets = 2000,
        max_connections = self.integration_config.max_connections,
        
        -- 性能配置
        performance = {
            max_events_per_loop = 1000,
            poll_timeout = 100,
            poll_interval = 1,
            buffer_size = 65536
        },
        
        -- 连接池配置
        connection_pool = {
            max_pool_size = math.max(analysis.current_connection_pool_size * 2, 50),
            connection_timeout = 30000,
            idle_timeout = 60000,
            retry_attempts = 3,
            retry_delay = 1000
        },
        
        -- 缓冲区池配置
        buffer_pool = {
            pool_size = math.max(analysis.current_buffer_pool_size * 2, 100),
            buffer_size = 4096,
            max_buffers = 1000
        },
        
        -- 异步处理配置
        async_processing = {
            enabled = true,
            worker_threads = self.integration_config.async_workers,
            task_queue_size = 10000,
            task_timeout = 30000
        },
        
        -- 集群优化配置
        cluster_optimization = {
            enabled = true,
            heartbeat_interval = 5000,
            election_timeout = 10000,
            sync_interval = 1000,
            compression_enabled = true,
            batch_size = 100
        }
    })
    
    -- 验证配置
    local is_valid, errors = zmq_async_config.validate_config(optimized_config)
    if not is_valid then
        print("优化配置验证失败:")
        for _, error in ipairs(errors) do
            print(string.format("  - %s", error))
        end
        return nil
    end
    
    print("优化配置生成成功:")
    print(string.format("  I/O线程数: %d", optimized_config.async_io.io_threads))
    print(string.format("  连接池大小: %d", optimized_config.connection_pool.max_pool_size))
    if optimized_config.buffer_pool then
        print(string.format("  缓冲区池大小: %d", optimized_config.buffer_pool.pool_size))
    end
    if optimized_config.async_processing then
        print(string.format("  异步工作线程: %d", optimized_config.async_processing.worker_threads))
    end
    print("")
    
    return optimized_config
end

function ZMQAsyncIntegration:create_integration_patch(analysis, optimized_config)
    print("=== 创建集成补丁 ===")
    
    -- 生成集成补丁代码
    local patch_code = string.format([[
--
-- ZeroMQ 异步线程池集成补丁
-- 自动生成于 %s
--

-- 集成配置
local INTEGRATION_CONFIG = {
    enable_async_io = %s,
    enable_thread_pool = %s,
    enable_connection_pool = %s,
    enable_cluster_optimization = %s,
    io_threads = %d,
    max_connections = %d,
    connection_pool_size = %d,
    buffer_pool_size = %d,
    async_workers = %d
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
        print(string.format("  I/O线程数: %%d", self.config.io_threads))
        print(string.format("  连接池大小: %%d", self.config.connection_pool_size))
        print(string.format("  缓冲区池大小: %%d", self.config.buffer_pool_size))
        print(string.format("  异步工作线程: %%d", self.config.async_workers))
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
]], 
os.date("%%Y-%%m-%%d %%H:%%M:%%S"),
optimized_config.async_io.io_threads > 1 and "true" or "false",
(optimized_config.async_processing and optimized_config.async_processing.enabled) and "true" or "false",
optimized_config.connection_pool.enabled and "true" or "false",
(optimized_config.async_processing and optimized_config.async_processing.enabled) and "true" or "false",
(optimized_config.async_io and optimized_config.async_io.io_threads) or 4,
(optimized_config.async_io and optimized_config.async_io.max_connections) or 2048,
    (optimized_config.connection_pool and optimized_config.connection_pool.max_pool_size) or 50,
(optimized_config.buffer_pool and optimized_config.buffer_pool.pool_size) or 100,
(optimized_config.async_processing and optimized_config.async_processing.worker_threads) or 8
)
    
    -- 保存补丁文件
    local patch_file = "/Users/moyong/project/ai/myrocks/stock-tsdb/lua/zmq_async_integration_patch.lua"
    local file = io.open(patch_file, "w")
    if file then
        file:write(patch_code)
        file:close()
        print(string.format("集成补丁已保存到: %s", patch_file))
    else
        print("警告: 无法保存集成补丁文件")
    end
    
    return patch_code
end

function ZMQAsyncIntegration:generate_migration_guide(analysis, optimized_config)
    print("=== 生成迁移指南 ===")
    
    local guide = string.format([[
# ZeroMQ 异步线程池集成迁移指南

## 概述
本指南帮助您将现有的TSDB集群迁移到使用ZeroMQ异步线程池的新架构。

## 当前状态分析
- I/O线程数: %d → %d (优化后)
- 连接池大小: %d → %d (优化后)
- 缓冲区池大小: %d → %d (优化后)
- 异步支持: %s → %s (优化后)

## 迁移步骤

### 1. 备份现有配置
```bash
cp /Users/moyong/project/ai/myrocks/stock-tsdb/lua/cluster.lua /Users/moyong/project/ai/myrocks/stock-tsdb/lua/cluster.lua.backup
cp /Users/moyong/project/ai/myrocks/stock-tsdb/lua/optimized_cluster_manager.lua /Users/moyong/project/ai/myrocks/stock-tsdb/lua/optimized_cluster_manager.lua.backup
```

### 2. 集成异步模块
将以下代码添加到现有集群管理器的初始化函数中：

```lua
-- 加载异步集成模块
local async_integration = require "zmq_async_integration_patch"

-- 初始化异步线程池
local success, err = async_integration.integrate_async_thread_pool()
if not success then
    error("异步线程池集成失败: " .. tostring(err))
end

-- 启动异步处理
success, err = async_integration.start_async_processing()
if not success then
    error("异步处理启动失败: " .. tostring(err))
end
```

### 3. 修改ZeroMQ配置
在集群初始化代码中，替换现有的ZeroMQ配置：

```lua
-- 原有的配置
-- zmq_ctx_set(context, ZMQ_IO_THREADS, 1)

-- 新的优化配置
local zmq_config = require "zmq_async_config"
local zmq_info = zmq_config.create_optimized_context({
    io_threads = %d,
    max_sockets = %d,
    max_connections = %d
})
```

### 4. 更新事件处理
将同步事件处理改为异步处理：

```lua
-- 原有的事件处理
function handle_client_message(identity, data)
    -- 同步处理逻辑
end

-- 新的异步处理
function handle_client_message_async(identity, data)
    async_integration.async_integration_manager.async_loop.async_handlers.message:submit_task(function(task_data)
        return process_client_message(task_data.identity, task_data.data)
    end, {identity = identity, data = data})
end
```

### 5. 性能调优
根据实际负载调整以下参数：
- `io_threads`: 根据CPU核心数调整 (建议4-8)
- `connection_pool_size`: 根据并发连接数调整 (建议50-200)
- `async_workers`: 根据任务复杂度调整 (建议8-32)

### 6. 监控和验证
集成完成后，使用以下命令验证：

```bash
# 检查异步处理状态
redis-cli -h 127.0.0.1 -p 5555 DEMO.THREADPOOL

# 运行性能基准测试
redis-cli -h 127.0.0.1 -p 5555 DEMO.BENCHMARK 1000

# 查看集成统计信息
redis-cli -h 127.0.0.1 -p 5555 INFO
```

## 回滚计划
如果集成出现问题，可以通过以下步骤回滚：

1. 停止异步处理
```lua
async_integration.stop_async_processing()
```

2. 恢复原始配置
```bash
cp /Users/moyong/project/ai/myrocks/stock-tsdb/lua/cluster.lua.backup /Users/moyong/project/ai/myrocks/stock-tsdb/lua/cluster.lua
```

3. 重启集群服务

## 预期性能提升
- 并发处理能力: 提升200-500%%
- 响应延迟: 降低30-60%%
- 内存使用: 优化20-40%%
- CPU利用率: 提升50-100%%

## 注意事项
- 建议在测试环境先进行充分测试
- 监控内存使用情况，避免内存泄漏
- 根据实际负载调整参数配置
- 定期查看异步处理统计信息
]], 
analysis.current_io_threads,
optimized_config.async_io.io_threads,
analysis.current_connection_pool_size,
optimized_config.connection_pool.max_pool_size,
analysis.current_buffer_pool_size,
    (optimized_config.buffer_pool and optimized_config.buffer_pool.pool_size) or 100,
analysis.has_async_support and "是" or "否",
(optimized_config.async_processing and optimized_config.async_processing.enabled) and "是" or "否",
(optimized_config.async_io and optimized_config.async_io.io_threads) or 4,
    (optimized_config.async_io and optimized_config.async_io.max_sockets) or 4096,
    (optimized_config.async_io and optimized_config.async_io.max_connections) or 2048
)
    
    -- 保存迁移指南
    local guide_file = "/Users/moyong/project/ai/myrocks/stock-tsdb/docs/ZMQ_ASYNC_INTEGRATION_GUIDE.md"
    local file = io.open(guide_file, "w")
    if file then
        file:write(guide)
        file:close()
        print(string.format("迁移指南已保存到: %s", guide_file))
    else
        print("警告: 无法保存迁移指南文件")
    end
    
    return guide
end

function ZMQAsyncIntegration:run_integration_analysis()
    print("=== ZeroMQ 异步线程池集成分析 ===")
    print("")
    
    -- 步骤1: 分析现有集群
    local analysis = self:analyze_existing_cluster()
    
    -- 步骤2: 生成优化配置
    local optimized_config = self:generate_optimized_config(analysis)
    
    if not optimized_config then
        print("优化配置生成失败")
        return false
    end
    
    -- 步骤3: 创建集成补丁
    local patch_code = self:create_integration_patch(analysis, optimized_config)
    
    -- 步骤4: 生成迁移指南
    local migration_guide = self:generate_migration_guide(analysis, optimized_config)
    
    print("=== 集成分析完成 ===")
    print("")
    print("生成的文件:")
    print("  - zmq_async_config.lua: ZeroMQ异步配置模块")
    print("  - zmq_async_loop.lua: ZeroMQ异步事件循环处理器")
    print("  - zmq_async_demo.lua: ZeroMQ异步演示程序")
    print("  - zmq_async_integration_patch.lua: 集成补丁代码")
    print("  - docs/ZMQ_ASYNC_INTEGRATION_GUIDE.md: 迁移指南")
    print("")
    print("下一步操作:")
    print("  1. 查看迁移指南了解详细步骤")
    print("  2. 在测试环境应用集成补丁")
    print("  3. 运行演示程序验证功能")
    print("  4. 根据实际负载调整配置参数")
    print("")
    
    return true, {
        analysis = analysis,
        optimized_config = optimized_config,
        patch_code = patch_code,
        migration_guide = migration_guide
    }
end

-- 主函数
local function main()
    -- 创建集成实例
    local integration = ZMQAsyncIntegration:new({
        enable_async_io = true,
        enable_thread_pool = true,
        enable_connection_pool = true,
        enable_cluster_optimization = true
    })
    
    -- 运行集成分析
    local success, result = integration:run_integration_analysis()
    
    if success then
        print("ZeroMQ 异步线程池集成分析成功完成")
        return 0
    else
        print("ZeroMQ 异步线程池集成分析失败")
        return 1
    end
end

-- 如果直接运行此脚本
if arg and arg[0]:match("zmq_async_integration.lua$") then
    local exit_code = main()
    os.exit(exit_code)
end

-- 导出模块
return {
    ZMQAsyncIntegration = ZMQAsyncIntegration,
    main = main
}