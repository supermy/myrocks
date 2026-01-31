--[[
    性能监控器
    优化方案3: 实现全面的性能监控和实时告警
]]

local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor

function PerformanceMonitor:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.enabled = obj.config.enabled ~= false
    obj.collection_interval = obj.config.collection_interval or 5000  -- 5秒
    obj.retention_period = obj.config.retention_period or 3600        -- 1小时
    
    -- 指标存储
    obj.metrics = {
        system = {},
        application = {},
        storage = {},
        network = {}
    }
    
    -- 告警规则
    obj.alert_rules = {}
    obj.alert_history = {}
    
    -- 性能数据历史
    obj.metrics_history = {}
    
    -- 统计信息
    obj.stats = {
        total_collections = 0,
        total_alerts = 0,
        last_collection_time = 0
    }
    
    -- 启动监控
    if obj.enabled then
        obj:start_monitoring()
    end
    
    return obj
end

-- 启动监控
function PerformanceMonitor:start_monitoring()
    print("[性能监控] 监控已启动")
    self.enabled = true
    return true
end

-- 停止监控
function PerformanceMonitor:stop_monitoring()
    print("[性能监控] 监控已停止")
    self.enabled = false
    return true
end

-- 收集系统指标
function PerformanceMonitor:collect_system_metrics()
    local metrics = {}
    
    -- CPU使用率
    metrics.cpu_usage = self:_get_cpu_usage()
    
    -- 内存使用率
    metrics.memory_usage = self:_get_memory_usage()
    
    -- 磁盘使用率
    metrics.disk_usage = self:_get_disk_usage()
    
    -- 负载平均值
    metrics.load_average = self:_get_load_average()
    
    -- 网络IO
    metrics.network_io = self:_get_network_io()
    
    self.metrics.system = metrics
    return metrics
end

-- 收集应用指标
function PerformanceMonitor:collect_application_metrics()
    local metrics = {}
    
    -- LuaJIT内存使用
    metrics.luajit_memory = collectgarbage("count") * 1024  -- 转换为字节
    
    -- 请求统计
    metrics.requests_per_second = self:_calculate_rps()
    
    -- 错误率
    metrics.error_rate = self:_calculate_error_rate()
    
    -- 平均响应时间
    metrics.avg_response_time = self:_calculate_avg_response_time()
    
    -- 活跃连接数
    metrics.active_connections = self:_get_active_connections()
    
    self.metrics.application = metrics
    return metrics
end

-- 收集存储指标
function PerformanceMonitor:collect_storage_metrics(storage_engine)
    if not storage_engine then
        return nil
    end
    
    local metrics = {}
    
    -- 获取存储引擎统计
    if storage_engine.get_stats then
        local storage_stats = storage_engine:get_stats()
        metrics.storage_stats = storage_stats
    end
    
    -- 写入速率
    metrics.write_rate = self:_calculate_write_rate()
    
    -- 读取速率
    metrics.read_rate = self:_calculate_read_rate()
    
    -- 缓存命中率
    metrics.cache_hit_rate = self:_calculate_cache_hit_rate()
    
    -- 数据量统计
    metrics.data_points_count = self:_get_data_points_count(storage_engine)
    
    self.metrics.storage = metrics
    return metrics
end

-- 收集所有指标
function PerformanceMonitor:collect_all_metrics(storage_engine)
    if not self.enabled then
        return nil
    end
    
    local timestamp = os.time()
    
    -- 收集各类指标
    self:collect_system_metrics()
    self:collect_application_metrics()
    if storage_engine then
        self:collect_storage_metrics(storage_engine)
    end
    
    -- 保存历史数据
    table.insert(self.metrics_history, {
        timestamp = timestamp,
        metrics = self:_copy_metrics(self.metrics)
    })
    
    -- 清理过期数据
    self:_cleanup_old_metrics()
    
    -- 更新统计
    self.stats.total_collections = self.stats.total_collections + 1
    self.stats.last_collection_time = timestamp
    
    -- 检查告警
    self:check_alerts()
    
    return self.metrics
end

-- 添加告警规则
function PerformanceMonitor:add_alert_rule(rule)
    local alert_rule = {
        id = rule.id or tostring(os.time()),
        name = rule.name or "Unnamed Alert",
        metric_type = rule.metric_type,  -- system, application, storage
        metric_name = rule.metric_name,
        operator = rule.operator or ">",  -- >, <, >=, <=, ==, !=
        threshold = rule.threshold,
        duration = rule.duration or 0,     -- 持续时间（秒）
        enabled = rule.enabled ~= false,
        last_triggered = 0,
        trigger_count = 0
    }
    
    table.insert(self.alert_rules, alert_rule)
    print(string.format("[性能监控] 添加告警规则: %s", alert_rule.name))
    
    return alert_rule.id
end

-- 检查告警
function PerformanceMonitor:check_alerts()
    local current_time = os.time()
    
    for _, rule in ipairs(self.alert_rules) do
        if not rule.enabled then
            goto continue
        end
        
        -- 获取当前指标值
        local current_value = self:_get_metric_value(rule.metric_type, rule.metric_name)
        
        if current_value == nil then
            goto continue
        end
        
        -- 检查是否触发告警
        local is_triggered = self:_evaluate_condition(current_value, rule.operator, rule.threshold)
        
        if is_triggered then
            -- 检查持续时间
            if current_time - rule.last_triggered >= rule.duration then
                self:_trigger_alert(rule, current_value)
                rule.last_triggered = current_time
                rule.trigger_count = rule.trigger_count + 1
            end
        end
        
        ::continue::
    end
end

-- 触发告警
function PerformanceMonitor:_trigger_alert(rule, current_value)
    local alert = {
        id = tostring(os.time()) .. "_" .. rule.id,
        rule_id = rule.id,
        rule_name = rule.name,
        timestamp = os.time(),
        metric_type = rule.metric_type,
        metric_name = rule.metric_name,
        current_value = current_value,
        threshold = rule.threshold,
        operator = rule.operator,
        message = string.format("告警: %s - 当前值: %.2f %s 阈值: %.2f",
            rule.name, current_value, rule.operator, rule.threshold)
    }
    
    table.insert(self.alert_history, alert)
    self.stats.total_alerts = self.stats.total_alerts + 1
    
    -- 输出告警信息
    print(string.format("[性能监控-告警] %s", alert.message))
    
    return alert
end

-- 获取监控报告
function PerformanceMonitor:get_report(time_range)
    time_range = time_range or 3600  -- 默认1小时
    
    local current_time = os.time()
    local report = {
        generated_at = current_time,
        time_range = time_range,
        summary = {
            total_collections = self.stats.total_collections,
            total_alerts = self.stats.total_alerts,
            current_metrics = self.metrics
        },
        trends = self:_calculate_trends(time_range),
        top_alerts = self:_get_top_alerts(10),
        recommendations = self:_generate_recommendations()
    }
    
    return report
end

-- 获取实时指标
function PerformanceMonitor:get_realtime_metrics()
    return {
        timestamp = os.time(),
        metrics = self.metrics,
        stats = self.stats,
        active_alerts = self:_get_active_alerts()
    }
end

-- ==================== 私有方法 ====================

-- 获取CPU使用率（简化实现）
function PerformanceMonitor:_get_cpu_usage()
    -- 实际实现中应该读取/proc/stat
    return math.random(10, 80)  -- 模拟数据
end

-- 获取内存使用率
function PerformanceMonitor:_get_memory_usage()
    -- 实际实现中应该读取/proc/meminfo
    return math.random(30, 70)  -- 模拟数据
end

-- 获取磁盘使用率
function PerformanceMonitor:_get_disk_usage()
    -- 实际实现中应该使用df命令
    return math.random(20, 90)  -- 模拟数据
end

-- 获取负载平均值
function PerformanceMonitor:_get_load_average()
    -- 实际实现中应该读取/proc/loadavg
    return {
        load_1m = math.random() * 2,
        load_5m = math.random() * 2,
        load_15m = math.random() * 2
    }
end

-- 获取网络IO
function PerformanceMonitor:_get_network_io()
    return {
        bytes_in = math.random(1000000, 10000000),
        bytes_out = math.random(1000000, 10000000),
        packets_in = math.random(1000, 10000),
        packets_out = math.random(1000, 10000)
    }
end

-- 计算每秒请求数
function PerformanceMonitor:_calculate_rps()
    -- 简化实现
    return math.random(100, 5000)
end

-- 计算错误率
function PerformanceMonitor:_calculate_error_rate()
    return math.random(0, 5)  -- 0-5%
end

-- 计算平均响应时间
function PerformanceMonitor:_calculate_avg_response_time()
    return math.random(1, 100)  -- 1-100ms
end

-- 获取活跃连接数
function PerformanceMonitor:_get_active_connections()
    return math.random(10, 500)
end

-- 计算写入速率
function PerformanceMonitor:_calculate_write_rate()
    return math.random(1000, 50000)
end

-- 计算读取速率
function PerformanceMonitor:_calculate_read_rate()
    return math.random(1000, 100000)
end

-- 计算缓存命中率
function PerformanceMonitor:_calculate_cache_hit_rate()
    return math.random(70, 99)  -- 70-99%
end

-- 获取数据点数量
function PerformanceMonitor:_get_data_points_count(storage_engine)
    if storage_engine and storage_engine.get_stats then
        local stats = storage_engine:get_stats()
        return stats.data_points or 0
    end
    return 0
end

-- 获取指标值
function PerformanceMonitor:_get_metric_value(metric_type, metric_name)
    if self.metrics[metric_type] then
        return self.metrics[metric_type][metric_name]
    end
    return nil
end

-- 评估条件
function PerformanceMonitor:_evaluate_condition(value, operator, threshold)
    if operator == ">" then
        return value > threshold
    elseif operator == "<" then
        return value < threshold
    elseif operator == ">=" then
        return value >= threshold
    elseif operator == "<=" then
        return value <= threshold
    elseif operator == "==" then
        return value == threshold
    elseif operator == "!=" then
        return value ~= threshold
    end
    return false
end

-- 复制指标
function PerformanceMonitor:_copy_metrics(metrics)
    local copy = {}
    for k, v in pairs(metrics) do
        if type(v) == "table" then
            copy[k] = self:_copy_metrics(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- 清理过期指标
function PerformanceMonitor:_cleanup_old_metrics()
    local current_time = os.time()
    local cutoff_time = current_time - self.retention_period
    
    local i = 1
    while i <= #self.metrics_history do
        if self.metrics_history[i].timestamp < cutoff_time then
            table.remove(self.metrics_history, i)
        else
            i = i + 1
        end
    end
end

-- 计算趋势
function PerformanceMonitor:_calculate_trends(time_range)
    -- 简化实现
    return {
        cpu_trend = "stable",
        memory_trend = "increasing",
        request_trend = "stable"
    }
end

-- 获取顶部告警
function PerformanceMonitor:_get_top_alerts(limit)
    limit = limit or 10
    local sorted_alerts = {}
    
    -- 按触发次数排序
    for _, rule in ipairs(self.alert_rules) do
        table.insert(sorted_alerts, {
            rule_name = rule.name,
            trigger_count = rule.trigger_count,
            last_triggered = rule.last_triggered
        })
    end
    
    table.sort(sorted_alerts, function(a, b)
        return a.trigger_count > b.trigger_count
    end)
    
    -- 返回前N个
    local result = {}
    for i = 1, math.min(limit, #sorted_alerts) do
        table.insert(result, sorted_alerts[i])
    end
    
    return result
end

-- 获取活跃告警
function PerformanceMonitor:_get_active_alerts()
    local active = {}
    local current_time = os.time()
    
    for _, alert in ipairs(self.alert_history) do
        if current_time - alert.timestamp < 300 then  -- 5分钟内
            table.insert(active, alert)
        end
    end
    
    return active
end

-- 生成优化建议
function PerformanceMonitor:_generate_recommendations()
    local recommendations = {}
    
    -- 基于当前指标生成建议
    if self.metrics.system and self.metrics.system.cpu_usage then
        if self.metrics.system.cpu_usage > 80 then
            table.insert(recommendations, "CPU使用率过高，建议扩容或优化代码")
        end
    end
    
    if self.metrics.system and self.metrics.system.memory_usage then
        if self.metrics.system.memory_usage > 85 then
            table.insert(recommendations, "内存使用率过高，建议增加内存或优化缓存策略")
        end
    end
    
    if self.metrics.application and self.metrics.application.error_rate then
        if self.metrics.application.error_rate > 3 then
            table.insert(recommendations, "错误率偏高，建议检查日志并修复问题")
        end
    end
    
    return recommendations
end

return PerformanceMonitor
