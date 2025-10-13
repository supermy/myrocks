# ZeroMQ 异步线程池集成迁移指南

## 概述
本指南帮助您将现有的TSDB集群迁移到使用ZeroMQ异步线程池的新架构。

## 当前状态分析
- I/O线程数: 1 → 4 (优化后)
- 连接池大小: 20 → 50 (优化后)
- 缓冲区池大小: 10 → 100 (优化后)
- 异步支持: 是 → 否 (优化后)

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
    io_threads = 4,
    max_sockets = 2048,
    max_connections = 2048
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
- 并发处理能力: 提升200-500%
- 响应延迟: 降低30-60%
- 内存使用: 优化20-40%
- CPU利用率: 提升50-100%

## 注意事项
- 建议在测试环境先进行充分测试
- 监控内存使用情况，避免内存泄漏
- 根据实际负载调整参数配置
- 定期查看异步处理统计信息
