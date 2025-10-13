--
-- 性能监控Lua脚本
-- 提供系统性能监控和指标收集功能
--

local monitor = {}
local ffi = require "ffi"

-- 加载工具函数并设置模块路径
local utils = require "commons.utils"
utils.setup_module_paths()
local cjson = utils.safe_require_cjson()

-- FFI定义系统调用
ffi.cdef[[
    // 时间相关
    int gettimeofday(struct timeval *tv, void *tz);
    int clock_gettime(int clk_id, struct timespec *tp);
    
    // 内存相关
    typedef struct {
        unsigned long total;
        unsigned long free;
        unsigned long available;
        unsigned long buffers;
        unsigned long cached;
        unsigned long active;
        unsigned long inactive;
    } meminfo_t;
    
    // CPU相关
    typedef struct {
        unsigned long user;
        unsigned long nice;
        unsigned long system;
        unsigned long idle;
        unsigned long iowait;
        unsigned long irq;
        unsigned long softirq;
        unsigned long steal;
    } cpu_stat_t;
    
    // 磁盘相关
    typedef struct {
        unsigned long read_ios;
        unsigned long read_merges;
        unsigned long read_sectors;
        unsigned long read_ticks;
        unsigned long write_ios;
        unsigned long write_merges;
        unsigned long write_sectors;
        unsigned long write_ticks;
        unsigned long in_flight;
        unsigned long io_ticks;
        unsigned long time_in_queue;
    } disk_stat_t;
    
    // 进程相关
    typedef struct {
        int pid;
        char comm[256];
        char state;
        int ppid;
        int pgrp;
        int session;
        int tty_nr;
        int tpgid;
        unsigned long flags;
        unsigned long minflt;
        unsigned long cminflt;
        unsigned long majflt;
        unsigned long cmajflt;
        unsigned long utime;
        unsigned long stime;
        long cutime;
        long cstime;
        long priority;
        long nice;
        long num_threads;
        long itrealvalue;
        unsigned long long starttime;
        unsigned long vsize;
        long rss;
    } proc_stat_t;
    
    // 文件操作
    FILE *fopen(const char *path, const char *mode);
    size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
    int fclose(FILE *fp);
    char *fgets(char *s, int size, FILE *stream);
]]

-- 性能监控器
local PerformanceMonitor = {}
PerformanceMonitor.__index = PerformanceMonitor

function PerformanceMonitor:new(config)
    local obj = setmetatable({}, PerformanceMonitor)
    obj.config = config or {}
    obj.metrics = {}
    obj.alerts = {}
    obj.thresholds = {
        cpu_usage = 80.0,      -- CPU使用率阈值 (%)
        memory_usage = 85.0,   -- 内存使用率阈值 (%)
        disk_usage = 90.0,     -- 磁盘使用率阈值 (%)
        io_wait = 20.0,        -- IO等待时间阈值 (%)
        response_time = 1000,  -- 响应时间阈值 (ms)
        error_rate = 5.0       -- 错误率阈值 (%)
    }
    obj.is_running = false
    obj.start_time = 0
    obj.sample_interval = config.sample_interval or 5  -- 采样间隔 (秒)
    obj.history_size = config.history_size or 360      -- 历史数据大小 (1小时，5秒间隔)
    
    -- 初始化指标历史数据
    obj.metric_history = {
        cpu = {},
        memory = {},
        disk = {},
        network = {},
        rocksdb = {},
        queries = {},
        errors = {}
    }
    
    return obj
end

function PerformanceMonitor:initialize()
    -- 初始化性能监控器
    self.is_running = true
    self.start_time = os.time()
    
    -- 启动监控线程
    self:start_monitoring_threads()
    
    return true
end

function PerformanceMonitor:stop()
    -- 停止性能监控器
    self.is_running = false
end

function PerformanceMonitor:start_monitoring_threads()
    -- 启动监控线程
    
    -- 系统资源监控线程
    self.system_thread = coroutine.create(function()
        while self.is_running do
            self:collect_system_metrics()
            coroutine.yield()
        end
    end)
    
    -- 应用性能监控线程
    self.app_thread = coroutine.create(function()
        while self.is_running do
            self:collect_app_metrics()
            coroutine.yield()
        end
    end)
    
    -- 告警检查线程
    self.alert_thread = coroutine.create(function()
        while self.is_running do
            self:check_alerts()
            coroutine.yield()
        end
    end)
end

function PerformanceMonitor:collect_system_metrics()
    -- 收集系统指标
    local metrics = {}
    
    -- CPU使用率
    local cpu_usage = self:get_cpu_usage()
    metrics.cpu = {
        usage = cpu_usage,
        user = 0,
        system = 0,
        idle = 0,
        iowait = 0,
        timestamp = os.time()
    }
    
    -- 内存使用情况
    local memory_info = self:get_memory_info()
    metrics.memory = {
        total = memory_info.total,
        used = memory_info.used,
        free = memory_info.free,
        cached = memory_info.cached,
        buffers = memory_info.buffers,
        usage_percent = memory_info.usage_percent,
        timestamp = os.time()
    }
    
    -- 磁盘使用情况
    local disk_info = self:get_disk_info()
    metrics.disk = {
        total = disk_info.total,
        used = disk_info.used,
        free = disk_info.free,
        usage_percent = disk_info.usage_percent,
        read_rate = disk_info.read_rate,
        write_rate = disk_info.write_rate,
        timestamp = os.time()
    }
    
    -- 网络统计
    local network_info = self:get_network_info()
    metrics.network = {
        bytes_sent = network_info.bytes_sent,
        bytes_received = network_info.bytes_received,
        packets_sent = network_info.packets_sent,
        packets_received = network_info.packets_received,
        timestamp = os.time()
    }
    
    -- 保存指标
    self:save_metrics("system", metrics)
end

function PerformanceMonitor:collect_app_metrics()
    -- 收集应用指标
    local metrics = {}
    
    -- RocksDB统计
    local rocksdb_stats = self:get_rocksdb_stats()
    metrics.rocksdb = {
        block_cache_hit_rate = rocksdb_stats.block_cache_hit_rate,
        write_rate = rocksdb_stats.write_rate,
        read_rate = rocksdb_stats.read_rate,
        compaction_rate = rocksdb_stats.compaction_rate,
        memtable_size = rocksdb_stats.memtable_size,
        immutable_memtable_size = rocksdb_stats.immutable_memtable_size,
        timestamp = os.time()
    }
    
    -- 查询统计
    local query_stats = self:get_query_stats()
    metrics.queries = {
        total_queries = query_stats.total_queries,
        queries_per_second = query_stats.queries_per_second,
        average_response_time = query_stats.average_response_time,
        slow_queries = query_stats.slow_queries,
        cache_hit_rate = query_stats.cache_hit_rate,
        timestamp = os.time()
    }
    
    -- 错误统计
    local error_stats = self:get_error_stats()
    metrics.errors = {
        total_errors = error_stats.total_errors,
        errors_per_second = error_stats.errors_per_second,
        error_types = error_stats.error_types,
        timestamp = os.time()
    }
    
    -- 保存指标
    self:save_metrics("app", metrics)
end

function PerformanceMonitor:get_cpu_usage()
    -- 获取CPU使用率
    -- 简化实现，返回模拟数据
    return math.random(10, 80) + math.random()
end

function PerformanceMonitor:get_memory_info()
    -- 获取内存信息
    -- 简化实现，返回模拟数据
    local total = 8 * 1024 * 1024 * 1024  -- 8GB
    local used = math.random(1 * 1024 * 1024 * 1024, 6 * 1024 * 1024 * 1024)  -- 1-6GB
    local free = total - used
    
    return {
        total = total,
        used = used,
        free = free,
        cached = math.random(512 * 1024 * 1024, 2 * 1024 * 1024 * 1024),
        buffers = math.random(128 * 1024 * 1024, 512 * 1024 * 1024),
        usage_percent = (used / total) * 100
    }
end

function PerformanceMonitor:get_disk_info()
    -- 获取磁盘信息
    -- 简化实现，返回模拟数据
    local total = 100 * 1024 * 1024 * 1024  -- 100GB
    local used = math.random(10 * 1024 * 1024 * 1024, 80 * 1024 * 1024 * 1024)  -- 10-80GB
    local free = total - used
    
    return {
        total = total,
        used = used,
        free = free,
        usage_percent = (used / total) * 100,
        read_rate = math.random(100, 10000),      -- KB/s
        write_rate = math.random(100, 5000)       -- KB/s
    }
end

function PerformanceMonitor:get_network_info()
    -- 获取网络信息
    -- 简化实现，返回模拟数据
    return {
        bytes_sent = math.random(1000000, 10000000),
        bytes_received = math.random(1000000, 10000000),
        packets_sent = math.random(1000, 10000),
        packets_received = math.random(1000, 10000)
    }
end

function PerformanceMonitor:get_rocksdb_stats()
    -- 获取RocksDB统计信息
    -- 简化实现，返回模拟数据
    return {
        block_cache_hit_rate = math.random(80, 99) + math.random(),
        write_rate = math.random(1000, 10000),      -- 写入速率 (ops/s)
        read_rate = math.random(5000, 50000),       -- 读取速率 (ops/s)
        compaction_rate = math.random(100, 1000),   -- 压缩速率 (MB/s)
        memtable_size = math.random(64 * 1024 * 1024, 256 * 1024 * 1024),  -- MemTable大小
        immutable_memtable_size = math.random(32 * 1024 * 1024, 128 * 1024 * 1024)
    }
end

function PerformanceMonitor:get_query_stats()
    -- 获取查询统计信息
    -- 简化实现，返回模拟数据
    return {
        total_queries = math.random(100000, 1000000),
        queries_per_second = math.random(100, 1000),
        average_response_time = math.random(1, 100),  -- ms
        slow_queries = math.random(0, 10),
        cache_hit_rate = math.random(80, 99) + math.random()
    }
end

function PerformanceMonitor:get_error_stats()
    -- 获取错误统计信息
    -- 简化实现，返回模拟数据
    return {
        total_errors = math.random(10, 1000),
        errors_per_second = math.random(0, 5),
        error_types = {
            timeout = math.random(1, 100),
            not_found = math.random(1, 50),
            internal = math.random(1, 20)
        }
    }
end

function PerformanceMonitor:save_metrics(category, metrics)
    -- 保存指标数据
    self.metrics[category] = metrics
    
    -- 保存到历史数据
    for metric_type, data in pairs(metrics) do
        if not self.metric_history[metric_type] then
            self.metric_history[metric_type] = {}
        end
        
        table.insert(self.metric_history[metric_type], data)
        
        -- 限制历史数据大小
        if #self.metric_history[metric_type] > self.history_size then
            table.remove(self.metric_history[metric_type], 1)
        end
    end
end

function PerformanceMonitor:check_alerts()
    -- 检查告警
    local alerts = {}
    
    -- 检查系统指标告警
    if self.metrics.system then
        if self.metrics.system.cpu.usage > self.thresholds.cpu_usage then
            table.insert(alerts, {
                level = "warning",
                type = "cpu_usage",
                message = string.format("CPU使用率过高: %.1f%%", self.metrics.system.cpu.usage),
                value = self.metrics.system.cpu.usage,
                threshold = self.thresholds.cpu_usage,
                timestamp = os.time()
            })
        end
        
        if self.metrics.system.memory.usage_percent > self.thresholds.memory_usage then
            table.insert(alerts, {
                level = "warning",
                type = "memory_usage",
                message = string.format("内存使用率过高: %.1f%%", self.metrics.system.memory.usage_percent),
                value = self.metrics.system.memory.usage_percent,
                threshold = self.thresholds.memory_usage,
                timestamp = os.time()
            })
        end
        
        if self.metrics.system.disk.usage_percent > self.thresholds.disk_usage then
            table.insert(alerts, {
                level = "critical",
                type = "disk_usage",
                message = string.format("磁盘使用率过高: %.1f%%", self.metrics.system.disk.usage_percent),
                value = self.metrics.system.disk.usage_percent,
                threshold = self.thresholds.disk_usage,
                timestamp = os.time()
            })
        end
    end
    
    -- 检查应用指标告警
    if self.metrics.app then
        if self.metrics.app.queries.average_response_time > self.thresholds.response_time then
            table.insert(alerts, {
                level = "warning",
                type = "response_time",
                message = string.format("查询响应时间过长: %.1fms", self.metrics.app.queries.average_response_time),
                value = self.metrics.app.queries.average_response_time,
                threshold = self.thresholds.response_time,
                timestamp = os.time()
            })
        end
        
        if self.metrics.app.errors.error_rate > self.thresholds.error_rate then
            table.insert(alerts, {
                level = "warning",
                type = "error_rate",
                message = string.format("错误率过高: %.1f%%", self.metrics.app.errors.error_rate),
                value = self.metrics.app.errors.error_rate,
                threshold = self.thresholds.error_rate,
                timestamp = os.time()
            })
        end
    end
    
    -- 保存告警
    for _, alert in ipairs(alerts) do
        table.insert(self.alerts, alert)
    end
    
    return alerts
end

function PerformanceMonitor:get_current_metrics()
    -- 获取当前指标
    return self.metrics
end

function PerformanceMonitor:get_metric_history(metric_type, time_range)
    -- 获取指标历史数据
    local history = self.metric_history[metric_type] or {}
    
    if time_range then
        local cutoff_time = os.time() - time_range
        local filtered_history = {}
        
        for _, data in ipairs(history) do
            if data.timestamp >= cutoff_time then
                table.insert(filtered_history, data)
            end
        end
        
        return filtered_history
    end
    
    return history
end

function PerformanceMonitor:get_alerts(level, time_range)
    -- 获取告警信息
    local filtered_alerts = {}
    local cutoff_time = time_range and (os.time() - time_range) or 0
    
    for _, alert in ipairs(self.alerts) do
        local match_level = not level or alert.level == level
        local match_time = alert.timestamp >= cutoff_time
        
        if match_level and match_time then
            table.insert(filtered_alerts, alert)
        end
    end
    
    return filtered_alerts
end

function PerformanceMonitor:clear_alerts()
    -- 清除告警
    self.alerts = {}
end

function PerformanceMonitor:set_threshold(metric_type, threshold)
    -- 设置告警阈值
    self.thresholds[metric_type] = threshold
end

function PerformanceMonitor:get_threshold(metric_type)
    -- 获取告警阈值
    return self.thresholds[metric_type]
end

function PerformanceMonitor:export_metrics(format)
    -- 导出指标数据
    format = format or "json"
    
    if format == "json" then
        return cjson.encode({
            timestamp = os.time(),
            metrics = self.metrics,
            alerts = self.alerts
        })
    elseif format == "prometheus" then
        -- Prometheus格式
        local output = {}
        
        -- CPU指标
        if self.metrics.system and self.metrics.system.cpu then
            table.insert(output, string.format("cpu_usage_percent %.1f", self.metrics.system.cpu.usage))
        end
        
        -- 内存指标
        if self.metrics.system and self.metrics.system.memory then
            table.insert(output, string.format("memory_usage_percent %.1f", self.metrics.system.memory.usage_percent))
            table.insert(output, string.format("memory_used_bytes %d", self.metrics.system.memory.used))
            table.insert(output, string.format("memory_free_bytes %d", self.metrics.system.memory.free))
        end
        
        -- 磁盘指标
        if self.metrics.system and self.metrics.system.disk then
            table.insert(output, string.format("disk_usage_percent %.1f", self.metrics.system.disk.usage_percent))
            table.insert(output, string.format("disk_read_rate_kbps %d", self.metrics.system.disk.read_rate))
            table.insert(output, string.format("disk_write_rate_kbps %d", self.metrics.system.disk.write_rate))
        end
        
        -- 查询指标
        if self.metrics.app and self.metrics.app.queries then
            table.insert(output, string.format("queries_per_second %d", self.metrics.app.queries.queries_per_second))
            table.insert(output, string.format("query_response_time_ms %.1f", self.metrics.app.queries.average_response_time))
            table.insert(output, string.format("cache_hit_rate_percent %.1f", self.metrics.app.queries.cache_hit_rate))
        end
        
        return table.concat(output, "\n")
    end
    
    return nil, "不支持的导出格式"
end

-- 性能监控器工厂函数
function monitor.create_monitor(config)
    return PerformanceMonitor:new(config)
end

-- 导出函数和常量
monitor.PerformanceMonitor = PerformanceMonitor
monitor.THRESHOLDS = {
    cpu_usage = 80.0,
    memory_usage = 85.0,
    disk_usage = 90.0,
    io_wait = 20.0,
    response_time = 1000,
    error_rate = 5.0
}

return monitor