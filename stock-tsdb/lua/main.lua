--
-- 股票行情数据TSDB系统主模块
-- 纯Lua实现版本
--

local tsdb = {}
local config = require "config"
local logger = require "logger"
local storage = require "storage"
local tsdb_core = require "tsdb_core"
local api_server = require "api_server"
local cluster_manager = require "cluster_manager"
local monitor = require "monitor"

-- 系统状态常量
local SYSTEM_STATUS = {
    STOPPED = "stopped",
    STARTING = "starting",
    RUNNING = "running",
    STOPPING = "stopping",
    ERROR = "error"
}

-- 股票行情数据TSDB系统类
local StockTsdbSystem = {}
StockTsdbSystem.__index = StockTsdbSystem

function StockTsdbSystem:new(config_path)
    local obj = setmetatable({}, StockTsdbSystem)
    obj.config_path = config_path or "config/app.conf"
    obj.config = nil
    obj.logger = nil
    obj.storage_engine = nil
    obj.tsdb_core = nil
    obj.api_server = nil
    obj.cluster_manager = nil
    obj.monitor = nil
    obj.stats = {
        start_time = 0,
        uptime = 0,
        errors = 0
    }
    obj.is_initialized = false
    obj.is_running = false
    obj.status = SYSTEM_STATUS.STOPPED
    return obj
end

function StockTsdbSystem:initialize()
    -- 初始化系统
    if self.is_initialized then
        return true
    end
    
    print("[StockTSDB] 开始初始化系统...")
    
    -- 1. 加载配置
    local success, result = pcall(function()
        self.config = config.load_config(self.config_path)
        return self.config
    end)
    
    if not success then
        print("[StockTSDB] 加载配置失败: " .. tostring(result))
        return false
    end
    
    -- 2. 初始化日志系统
    success, result = pcall(function()
        self.logger = logger.create_logger({
            level = self.config:get_string("log.level", "INFO"),
            file = self.config:get_string("log.file", "logs/stock-tsdb.log"),
            max_size = self.config:get_int("log.max_size", 100) * 1024 * 1024,  -- MB
            max_files = self.config:get_int("log.max_files", 10)
        })
        return self.logger
    end)
    
    if not success then
        print("[StockTSDB] 初始化日志系统失败: " .. tostring(result))
        return false
    end
    
    self.logger:info("股票行情数据TSDB系统初始化开始")
    
    -- 3. 初始化存储引擎
    success, result = pcall(function()
        self.storage_engine = storage.create_engine({
            data_dir = self.config:get_string("storage.data_dir", "data"),
            write_buffer_size = self.config:get_int("rocksdb.write_buffer_size", 64) * 1024 * 1024,  -- MB
            max_write_buffer_number = self.config:get_int("rocksdb.max_write_buffer_number", 4),
            target_file_size_base = self.config:get_int("rocksdb.target_file_size_base", 64) * 1024 * 1024,  -- MB
            max_bytes_for_level_base = self.config:get_int("rocksdb.max_bytes_for_level_base", 256) * 1024 * 1024,  -- MB
            compression = self.config:get_string("rocksdb.compression", "lz4")
        })
        
        -- 初始化存储引擎
        local init_success = self.storage_engine:init()
        if not init_success then
            return false, "存储引擎初始化失败"
        end
        
        return self.storage_engine
    end)
    
    if not success then
        self.logger:error("初始化存储引擎失败: " .. tostring(result))
        return false
    end
    
    -- 4. 初始化TSDB核心
    success, result = pcall(function()
        self.tsdb_core = tsdb_core.create_tsdb({
            storage_engine = self.storage_engine,
            block_size = self.config:get_int("storage.block_size", 4096),
            compression = self.config:get_string("storage.compression", "lz4"),
            cache_size = self.config:get_int("storage.cache_size", 256) * 1024 * 1024  -- MB
        })
        return self.tsdb_core
    end)
    
    if not success then
        self.logger:error("初始化TSDB核心失败: " .. tostring(result))
        return false
    end
    
    -- 5. 初始化API服务器
    success, result = pcall(function()
        self.api_server = api_server.create_server({
            host = self.config:get_string("api.host", "0.0.0.0"),
            port = self.config:get_int("api.port", 8080),
            ssl_enabled = self.config:get_bool("api.ssl_enabled", false),
            ssl_cert = self.config:get_string("api.ssl_cert", ""),
            ssl_key = self.config:get_string("api.ssl_key", ""),
            tsdb_core = self.tsdb_core
        })
        return self.api_server
    end)
    
    if not success then
        self.logger:error("初始化API服务器失败: " .. tostring(result))
        return false
    end
    
    -- 6. 初始化集群管理器
    success, result = pcall(function()
        self.cluster_manager = cluster_manager.create_manager({
            cluster_name = self.config:get_string("cluster.name", "stock-tsdb-cluster"),
            node_id = self.config:get_string("cluster.node_id", "node-1"),
            seed_nodes = self.config:get_list("cluster.seed_nodes", {}),
            gossip_port = self.config:get_int("cluster.gossip_port", 9090),
            replication_factor = self.config:get_int("cluster.replication_factor", 3)
        })
        return self.cluster_manager
    end)
    
    if not success then
        self.logger:warn("初始化集群管理器失败: " .. tostring(result))
        -- 集群管理器不是必需的，继续运行
    end
    
    -- 7. 初始化监控器
    success, result = pcall(function()
        self.monitor = monitor.create_monitor({
            metrics_port = self.config:get_int("monitor.metrics_port", 9091),
            collect_interval = self.config:get_int("monitor.collect_interval", 10)
        })
        return self.monitor
    end)
    
    if not success then
        self.logger:warn("初始化监控器失败: " .. tostring(result))
        -- 监控器不是必需的，继续运行
    end
    
    self.is_initialized = true
    self.status = SYSTEM_STATUS.STOPPED
    self.logger:info("股票行情数据TSDB系统初始化完成")
    
    return true
end

function StockTsdbSystem:start()
    -- 启动系统
    if not self.is_initialized then
        return false, "系统未初始化"
    end
    
    if self.is_running then
        return false, "系统已在运行"
    end
    
    self.status = SYSTEM_STATUS.STARTING
    self.logger:info("启动股票行情数据TSDB系统")
    
    -- 初始化存储引擎（如果尚未初始化）
    if not self.storage_engine.is_opened then
        local success = self.storage_engine:init()
        if not success then
            self.status = SYSTEM_STATUS.ERROR
            return false, "初始化存储引擎失败"
        end
    end
    
    -- 启动API服务器
    local success, error = self.api_server:start()
    if not success then
        self.status = SYSTEM_STATUS.ERROR
        return false, "启动API服务器失败: " .. error
    end
    
    -- 启动集群管理器
    if self.cluster_manager then
        success, error = self.cluster_manager:start()
        if not success then
            self.logger:warn("启动集群管理器失败: " .. error)
        end
    end
    
    -- 启动监控器
    if self.monitor then
        success, error = self.monitor:start()
        if not success then
            self.logger:warn("启动监控器失败: " .. error)
        end
    end
    
    self.is_running = true
    self.status = SYSTEM_STATUS.RUNNING
    self.stats.start_time = os.time()
    self.logger:info("股票行情数据TSDB系统启动成功")
    
    return true
end

function StockTsdbSystem:stop()
    -- 停止系统
    if not self.is_running then
        return false, "系统未运行"
    end
    
    self.status = SYSTEM_STATUS.STOPPING
    self.logger:info("停止股票行情数据TSDB系统")
    
    -- 停止监控器
    if self.monitor then
        self.monitor:stop()
    end
    
    -- 停止集群管理器
    if self.cluster_manager then
        self.cluster_manager:stop()
    end
    
    -- 停止API服务器
    if self.api_server then
        self.api_server:stop()
    end
    
    -- 关闭存储引擎
    if self.storage_engine then
        self.storage_engine:shutdown()
    end
    
    self.is_running = false
    self.status = SYSTEM_STATUS.STOPPED
    self.logger:info("股票行情数据TSDB系统已停止")
end

function StockTsdbSystem:restart()
    -- 重启系统
    self:stop()
    local success = self:initialize()
    if not success then
        return false, "初始化失败"
    end
    return self:start()
end

function StockTsdbSystem:get_status()
    -- 获取系统状态
    local status = {
        status = self.status,
        is_running = self.is_running,
        is_initialized = self.is_initialized,
        stats = self.stats
    }
    
    -- 获取各组件状态
    if self.storage_engine then
        local success, stats = self.storage_engine:get_statistics()
        status.storage = {
            status = success and "ok" or "error",
            stats = stats
        }
    end
    
    if self.api_server then
        status.api = self.api_server:get_status()
    end
    
    if self.cluster_manager then
        status.cluster = self.cluster_manager:get_cluster_status()
    end
    
    if self.monitor then
        status.monitor = self.monitor:get_current_metrics()
    end
    
    return status
end

function StockTsdbSystem:get_metrics()
    -- 获取性能监控指标
    if not self.monitor then
        return nil, "性能监控器未启用"
    end
    
    return self.monitor:get_current_metrics()
end

function StockTsdbSystem:get_alerts(level, time_range)
    -- 获取告警信息
    if not self.monitor then
        return nil, "性能监控器未启用"
    end
    
    return self.monitor:get_alerts(level, time_range)
end

function StockTsdbSystem:export_metrics(format)
    -- 导出指标数据
    if not self.monitor then
        return nil, "性能监控器未启用"
    end
    
    format = format or "json"
    if format == "json" then
        return self.monitor:export_metrics_json()
    elseif format == "prometheus" then
        return self.monitor:export_metrics_prometheus()
    else
        return nil, "不支持的导出格式: " .. format
    end
end

function StockTsdbSystem:reload_config()
    -- 重新加载配置
    self.logger:info("重新加载配置")
    
    local success, result = pcall(function()
        return config.load_config(self.config_path)
    end)
    
    if success then
        self.config = result
        self.logger:info("配置重新加载成功")
        return true
    else
        self.logger:error("配置重新加载失败: " .. tostring(result))
        return false
    end
end

function StockTsdbSystem:execute_command(command, args)
    -- 执行命令
    if command == "status" then
        return self:get_status()
    elseif command == "metrics" then
        return self:get_metrics()
    elseif command == "alerts" then
        return self:get_alerts(args.level, args.time_range)
    elseif command == "export_metrics" then
        return self:export_metrics(args.format)
    elseif command == "reload_config" then
        return self:reload_config()
    elseif command == "stop" then
        self:stop()
        return true
    elseif command == "restart" then
        return self:restart()
    else
        return nil, "未知命令: " .. command
    end
end

-- 系统工厂函数
function tsdb.create_system(config_path)
    return StockTsdbSystem:new(config_path)
end

-- 导出函数
return tsdb