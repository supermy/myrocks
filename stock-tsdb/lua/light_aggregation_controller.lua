-- 轻度汇总数据库主控制器模块
-- 集成配置管理、时间维度聚合、其他维度聚合、ZeroMQ异步计算和存储引擎

local LightAggregationController = {}
LightAggregationController.__index = LightAggregationController

-- 导入依赖模块
local LightAggregationConfig = require "light_aggregation_config"
local TimeDimensionAggregator = require "time_dimension_aggregator"
local OtherDimensionAggregator = require "other_dimension_aggregator"
local ZMQAsyncAggregation = require "zmq_async_aggregation"
local LightAggregationStorage = require "light_aggregation_storage"

-- 创建轻度汇总控制器
function LightAggregationController:new(config)
    local obj = setmetatable({}, LightAggregationController)
    
    -- 初始化配置
    obj.config = LightAggregationConfig:new(config)
    
    -- 初始化组件
    obj.time_aggregator = nil
    obj.other_aggregator = nil
    obj.storage_engine = nil
    obj.zmq_client = nil
    obj.processor = nil
    
    -- 状态管理
    obj.is_initialized = false
    obj.is_running = false
    obj.stats = {
        data_points_processed = 0,
        aggregation_results_stored = 0,
        errors = 0,
        last_error = nil,
        startup_time = nil,
        last_activity = nil
    }
    
    return obj
end

-- 初始化控制器
function LightAggregationController:initialize()
    if self.is_initialized then
        return true, "控制器已初始化"
    end
    
    -- 验证配置
    local config_valid, config_errors = self.config:validate()
    if not config_valid then
        return false, "配置验证失败: " .. table.concat(config_errors, ", ")
    end
    
    local ok, err = pcall(function()
        -- 初始化时间维度聚合器
        if #self.config:get_enabled_time_dimensions() > 0 then
            self.time_aggregator = TimeDimensionAggregator:new(self.config)
        end
        
        -- 初始化其他维度聚合器
        if #self.config:get_enabled_other_dimensions() > 0 then
            self.other_aggregator = OtherDimensionAggregator:new(self.config)
        end
        
        -- 初始化存储引擎
        self.storage_engine = LightAggregationStorage:new(self.config)
        local storage_ok, storage_err = self.storage_engine:open()
        if not storage_ok then
            error("存储引擎初始化失败: " .. storage_err)
        end
        
        -- 初始化ZeroMQ客户端
        if self.config.zmq and self.config.zmq.enabled then
            self.zmq_client = ZMQAsyncAggregation.ZMQAsyncAggregation:new(self.config)
            local zmq_ok, zmq_err = self.zmq_client:initialize()
            if not zmq_ok then
                error("ZeroMQ客户端初始化失败: " .. zmq_err)
            end
        end
        
        self.is_initialized = true
        self.stats.startup_time = os.time()
        self.stats.last_activity = os.time()
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "控制器初始化失败: " .. tostring(err)
    end
    
    return true, "控制器初始化成功"
end

-- 启动控制器
function LightAggregationController:start()
    if not self.is_initialized then
        local ok, err = self:initialize()
        if not ok then
            return false, err
        end
    end
    
    if self.is_running then
        return true, "控制器已在运行"
    end
    
    self.is_running = true
    
    -- 启动后台任务（如果启用）
    if self.config.monitoring and self.config.monitoring.enabled then
        self:start_background_tasks()
    end
    
    return true, "控制器启动成功"
end

-- 停止控制器
function LightAggregationController:stop()
    if not self.is_running then
        return true, "控制器已停止"
    end
    
    self.is_running = false
    
    -- 停止后台任务
    self:stop_background_tasks()
    
    -- 刷新所有缓冲区
    self:flush_all_buffers()
    
    -- 关闭组件
    if self.zmq_client then
        self.zmq_client:close()
    end
    
    if self.storage_engine then
        self.storage_engine:close()
    end
    
    return true, "控制器停止成功"
end

-- 处理单个数据点
function LightAggregationController:process_data_point(data_point)
    if not self.is_running then
        return false, "控制器未运行"
    end
    
    self.stats.last_activity = os.time()
    
    -- 同步处理（如果ZeroMQ禁用）
    if not self.config.zmq or not self.config.zmq.enabled then
        return self:process_data_point_sync(data_point)
    end
    
    -- 异步处理（通过ZeroMQ）
    local ok, err = self.zmq_client:send_data_point(data_point)
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "异步处理失败: " .. tostring(err)
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + 1
    return true, "数据点已发送到异步处理器"
end

-- 同步处理数据点
function LightAggregationController:process_data_point_sync(data_point)
    local results = {}
    
    -- 处理时间维度聚合
    if self.time_aggregator then
        self.time_aggregator:process_data_point(data_point)
    end
    
    -- 处理其他维度聚合
    if self.other_aggregator then
        self.other_aggregator:process_data_point(data_point)
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + 1
    
    -- 检查是否需要刷新缓冲区
    self:check_buffer_flush()
    
    return true, "数据点同步处理成功"
end

-- 处理批量数据点
function LightAggregationController:process_batch_data(data_points)
    if not self.is_running then
        return false, "控制器未运行"
    end
    
    self.stats.last_activity = os.time()
    
    -- 同步处理（如果ZeroMQ禁用）
    if not self.config.zmq or not self.config.zmq.enabled then
        print("DEBUG: 使用同步处理模式")
        return self:process_batch_data_sync(data_points)
    end
    
    -- 异步处理（通过ZeroMQ）
    local ok, err = self.zmq_client:send_batch_data(data_points)
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "批量异步处理失败: " .. tostring(err)
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + #data_points
    return true, "批量数据已发送到异步处理器"
end

-- 同步处理批量数据
function LightAggregationController:process_batch_data_sync(data_points)
    local results = {}
    local valid_data_points = {}
    local invalid_count = 0
    
    -- 数据验证：过滤无效数据点
    for i, data_point in ipairs(data_points) do
        local is_valid = true
        local error_msg = ""
        
        -- 检查时间戳
        if not data_point.timestamp then
            is_valid = false
            error_msg = "缺少时间戳"
        elseif type(data_point.timestamp) ~= "number" then
            -- 尝试转换时间戳
            local converted_timestamp = tonumber(data_point.timestamp)
            if converted_timestamp then
                data_point.timestamp = converted_timestamp
            else
                is_valid = false
                error_msg = "无效的时间戳格式"
            end
        end
        
        -- 检查值
        if is_valid and not data_point.value then
            is_valid = false
            error_msg = "缺少值"
        elseif is_valid and type(data_point.value) ~= "number" then
            -- 尝试转换值
            local converted_value = tonumber(data_point.value)
            if converted_value then
                data_point.value = converted_value
            else
                is_valid = false
                error_msg = "无效的值格式"
            end
        end
        
        if is_valid then
            table.insert(valid_data_points, data_point)
        else
            invalid_count = invalid_count + 1
            print("⚠️  数据点", i, "无效:", error_msg)
        end
    end
    
    -- 如果所有数据点都无效，返回错误
    if #valid_data_points == 0 and #data_points > 0 then
        return false, "所有数据点都无效，拒绝处理"
    end
    
    -- 处理有效的时间维度聚合
    if self.time_aggregator and #valid_data_points > 0 then
        local time_results = self.time_aggregator:process_batch(valid_data_points)
        for _, result in ipairs(time_results) do
            table.insert(results, result)
        end
    end
    
    -- 处理有效的其他维度聚合
    if self.other_aggregator and #valid_data_points > 0 then
        local other_results = self.other_aggregator:process_batch(valid_data_points)
        for _, result in ipairs(other_results) do
            table.insert(results, result)
        end
    end
    
    -- 存储聚合结果
    if #results > 0 then
        local ok, err = self.storage_engine:store_aggregation_results(results)
        if ok then
            self.stats.aggregation_results_stored = self.stats.aggregation_results_stored + #results
        else
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
        end
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + #valid_data_points
    
    local message = "批量数据同步处理成功"
    if invalid_count > 0 then
        message = message .. ", 过滤了 " .. invalid_count .. " 个无效数据点"
    end
    if #results > 0 then
        message = message .. ", 存储了 " .. #results .. " 个聚合结果"
    end
    
    return true, message
end

-- 检查缓冲区刷新
function LightAggregationController:check_buffer_flush()
    local current_time = os.time()
    local flush_interval = self.config.config.aggregation.flush_interval
    
    -- 检查时间维度聚合器
    if self.time_aggregator then
        local time_buffer = self.time_aggregator.buffers
        for dimension, buffer in pairs(time_buffer) do
            if buffer.count > 0 and (current_time - buffer.last_update) >= flush_interval then
                self:flush_time_dimension_buffer(dimension)
            end
        end
    end
    
    -- 检查其他维度聚合器
    if self.other_aggregator then
        local other_buffer = self.other_aggregator.buffers
        for dimension, buffer in pairs(other_buffer) do
            if buffer.count > 0 and (current_time - buffer.last_update) >= flush_interval then
                self:flush_other_dimension_buffer(dimension)
            end
        end
    end
end

-- 刷新时间维度缓冲区
function LightAggregationController:flush_time_dimension_buffer(dimension)
    if not self.time_aggregator then
        return 0
    end
    
    local results = self.time_aggregator:flush_dimension_buffer(dimension)
    if results and #results > 0 then
        local ok, err = self.storage_engine:store_aggregation_results(results)
        if ok then
            self.stats.aggregation_results_stored = self.stats.aggregation_results_stored + #results
            return #results
        else
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
        end
    end
    
    return 0
end

-- 刷新其他维度缓冲区
function LightAggregationController:flush_other_dimension_buffer(dimension)
    if not self.other_aggregator then
        return 0
    end
    
    local results = self.other_aggregator:flush_dimension_buffer(dimension)
    if results and #results > 0 then
        local ok, err = self.storage_engine:store_aggregation_results(results)
        if ok then
            self.stats.aggregation_results_stored = self.stats.aggregation_results_stored + #results
            return #results
        else
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
        end
    end
    
    return 0
end

-- 刷新所有缓冲区
function LightAggregationController:flush_all_buffers()
    local total_flushed = 0
    
    -- 刷新时间维度缓冲区
    if self.time_aggregator then
        local time_results = self.time_aggregator:flush_all_buffers()
        if time_results and #time_results > 0 then
            local ok, err = self.storage_engine:store_aggregation_results(time_results)
            if ok then
                total_flushed = total_flushed + #time_results
            end
        end
    end
    
    -- 刷新其他维度缓冲区
    if self.other_aggregator then
        local other_results = self.other_aggregator:flush_all_buffers()
        if other_results and #other_results > 0 then
            local ok, err = self.storage_engine:store_aggregation_results(other_results)
            if ok then
                total_flushed = total_flushed + #other_results
            end
        end
    end
    
    self.stats.aggregation_results_stored = self.stats.aggregation_results_stored + total_flushed
    return total_flushed
end

-- 查询聚合数据
function LightAggregationController:query_aggregated_data(query)
    if not self.is_running then
        return nil, "控制器未运行"
    end
    
    return self.storage_engine:query_aggregated_data(query)
end

-- 获取统计信息
function LightAggregationController:get_stats()
    local stats = {
        controller = {
            is_initialized = self.is_initialized,
            is_running = self.is_running,
            startup_time = self.stats.startup_time,
            last_activity = self.stats.last_activity,
            data_points_processed = self.stats.data_points_processed,
            aggregation_results_stored = self.stats.aggregation_results_stored,
            errors = self.stats.errors,
            last_error = self.stats.last_error
        },
        configuration = self.config:get_summary()
    }
    
    -- 时间维度聚合器统计
    if self.time_aggregator then
        stats.time_aggregator = self.time_aggregator:get_all_stats()
    end
    
    -- 其他维度聚合器统计
    if self.other_aggregator then
        stats.other_aggregator = self.other_aggregator:get_all_stats()
    end
    
    -- 存储引擎统计
    if self.storage_engine then
        stats.storage_engine = self.storage_engine:get_stats()
    end
    
    -- ZeroMQ客户端统计
    if self.zmq_client then
        stats.zmq_client = self.zmq_client:get_stats()
    end
    
    return stats
end

-- 清理过期数据
function LightAggregationController:cleanup_expired_data()
    if not self.is_running then
        return 0, "控制器未运行"
    end
    
    local retention_days = self.config.config.aggregation.retention_days
    local total_cleaned = 0
    
    -- 清理时间维度聚合器缓冲区
    if self.time_aggregator then
        local time_cleaned = self.time_aggregator:cleanup_expired_data(retention_days)
        total_cleaned = total_cleaned + time_cleaned
    end
    
    -- 清理其他维度聚合器缓冲区
    if self.other_aggregator then
        local other_cleaned = self.other_aggregator:cleanup_expired_data(retention_days)
        total_cleaned = total_cleaned + other_cleaned
    end
    
    -- 清理存储引擎过期数据
    local storage_cleaned, storage_err = self.storage_engine:delete_expired_data(retention_days)
    if storage_cleaned then
        total_cleaned = total_cleaned + storage_cleaned
    end
    
    return total_cleaned, "清理了 " .. total_cleaned .. " 条过期数据"
end

-- 启动后台任务
function LightAggregationController:start_background_tasks()
    -- 监控统计任务
    self.monitor_task = function()
        while self.is_running do
            -- 定期检查缓冲区状态
            self:check_buffer_flush()
            
            -- 定期清理过期数据
            if os.time() % 3600 == 0 then  -- 每小时清理一次
                self:cleanup_expired_data()
            end
            
            -- 休眠一段时间
            os.execute("sleep " .. self.config.config.monitoring.stats_interval)
        end
    end
    
    -- 启动监控任务（在单独的协程中）
    -- 注意：在实际环境中需要使用协程或线程
end

-- 停止后台任务
function LightAggregationController:stop_background_tasks()
    -- 停止监控任务
    self.monitor_task = nil
end

-- 导出配置
function LightAggregationController:export_config()
    return self.config:to_json()
end

-- 导入配置
function LightAggregationController:import_config(json_config)
    if self.is_running then
        return false, "无法在运行时导入配置"
    end
    
    local ok, err = self.config:from_json(json_config)
    if not ok then
        return false, "配置导入失败: " .. tostring(err)
    end
    
    -- 重新初始化组件
    self.is_initialized = false
    return self:initialize()
end

-- 测试功能
function LightAggregationController:test_functionality()
    if not self.is_running then
        return false, "控制器未运行"
    end
    
    -- 创建测试数据
    local test_data = {
        {
            timestamp = os.time(),
            value = 100.5,
            dimensions = {
                code = "000001",
                market = "SH",
                industry = "金融",
                region = "华东"
            }
        },
        {
            timestamp = os.time() - 300,
            value = 99.8,
            dimensions = {
                code = "000001", 
                market = "SH",
                industry = "金融",
                region = "华东"
            }
        }
    }
    
    -- 处理测试数据
    local ok, err = self:process_batch_data(test_data)
    if not ok then
        return false, "测试失败: " .. tostring(err)
    end
    
    -- 查询测试结果
    local query = {
        dimension_type = "time",
        dimension = "HOUR",
        start_time = os.date("%Y%m%d%H", os.time() - 3600),
        end_time = os.date("%Y%m%d%H", os.time() + 3600)
    }
    
    local results, query_err = self:query_aggregated_data(query)
    if query_err then
        return false, "查询测试失败: " .. tostring(query_err)
    end
    
    return true, "功能测试通过，处理了 " .. #test_data .. " 个数据点"
end

-- 健康检查
function LightAggregationController:health_check()
    local health = {
        status = "healthy",
        components = {},
        last_activity = self.stats.last_activity,
        uptime = os.time() - (self.stats.startup_time or os.time())
    }
    
    -- 检查时间维度聚合器
    if self.time_aggregator then
        table.insert(health.components, {
            name = "time_aggregator",
            status = "healthy"
        })
    end
    
    -- 检查其他维度聚合器
    if self.other_aggregator then
        table.insert(health.components, {
            name = "other_aggregator", 
            status = "healthy"
        })
    end
    
    -- 检查存储引擎
    if self.storage_engine then
        local storage_ok, _ = self.storage_engine:check_integrity()
        table.insert(health.components, {
            name = "storage_engine",
            status = storage_ok and "healthy" or "unhealthy"
        })
        
        if not storage_ok then
            health.status = "degraded"
        end
    end
    
    -- 检查ZeroMQ客户端
    if self.zmq_client then
        local zmq_ok, _ = self.zmq_client:check_connection()
        table.insert(health.components, {
            name = "zmq_client",
            status = zmq_ok and "healthy" or "unhealthy"
        })
        
        if not zmq_ok then
            health.status = "degraded"
        end
    end
    
    -- 检查错误计数
    if self.stats.errors > 10 then
        health.status = "degraded"
    end
    
    return health
end

return LightAggregationController