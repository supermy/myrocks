-- 业务实例管理器
-- 负责启动和管理不同业务的独立数据库实例

local BusinessInstanceManager = {}
BusinessInstanceManager.__index = BusinessInstanceManager

-- 导入必要的模块
local tsdb = require "tsdb"
local logger = require "logger"
local config = require "config"

function BusinessInstanceManager:new(instance_config_path)
    local obj = setmetatable({}, BusinessInstanceManager)
    obj.instance_config_path = instance_config_path or "business_instance_config.json"
    obj.instances = {}
    obj.instance_configs = {}
    obj.is_running = false
    
    -- 加载实例配置
    obj:load_instance_configs()
    
    return obj
end

-- 加载业务实例配置
function BusinessInstanceManager:load_instance_configs()
    local file = io.open(self.instance_config_path, "r")
    if not file then
        error("无法打开业务实例配置文件: " .. self.instance_config_path)
    end
    
    local content = file:read("*a")
    file:close()
    
    -- 解析JSON配置
    local json = require "cjson"
    local config_data = json.decode(content)
    
    self.instance_configs = config_data.business_instances or {}
    self.manager_config = config_data.instance_manager or {}
    
    print("[业务实例管理器] 加载了 " .. table_size(self.instance_configs) .. " 个业务实例配置")
end

-- 获取业务实例配置
function BusinessInstanceManager:get_instance_config(business_type)
    return self.instance_configs[business_type]
end

-- 获取所有业务实例配置
function BusinessInstanceManager:get_all_instance_configs()
    return self.instance_configs
end

-- 启动业务实例
function BusinessInstanceManager:start_instance(business_type)
    local instance_config = self:get_instance_config(business_type)
    if not instance_config then
        error("找不到业务类型配置: " .. business_type)
    end
    
    if self.instances[business_type] then
        print("[业务实例管理器] 业务实例已启动: " .. business_type)
        return true
    end
    
    print("[业务实例管理器] 启动业务实例: " .. business_type)
    
    -- 创建实例特定的配置
    local instance_config = self:create_instance_config(instance_config)
    
    -- 启动TSDB实例
    local success, instance = pcall(function()
        return tsdb:new(instance_config)
    end)
    
    if not success then
        error("启动业务实例失败: " .. business_type .. " - " .. tostring(instance))
    end
    
    -- 初始化实例
    local init_success, init_error = pcall(function()
        return instance:init()
    end)
    
    if not init_success then
        error("初始化业务实例失败: " .. business_type .. " - " .. tostring(init_error))
    end
    
    self.instances[business_type] = {
        instance = instance,
        config = instance_config,
        status = "running",
        start_time = os.time()
    }
    
    print("[业务实例管理器] 业务实例启动成功: " .. business_type)
    return true
end

-- 创建实例特定的配置
function BusinessInstanceManager:create_instance_config(instance_config)
    local config = {
        server = {
            port = instance_config.port,
            bind = "127.0.0.1",
            max_connections = instance_config.max_connections or 1000
        },
        storage = {
            data_dir = instance_config.data_dir,
            log_dir = "./logs/" .. instance_config.instance_id,
            block_size = 30,
            compression_level = 6,
            enable_compression = true
        },
        rocksdb = {
            write_buffer_size = (instance_config.write_buffer_size or 64) .. "MB",
            max_file_size = "128MB",
            target_file_size_base = "64MB",
            block_cache_size = (instance_config.block_cache_size or 256) .. "MB",
            enable_statistics = true
        },
        cluster = {
            node_id = instance_config.instance_id,
            cluster_mode = "single",
            master_host = "127.0.0.1",
            master_port = instance_config.port + 1000
        },
        data_retention = {
            hot_data_days = instance_config.cold_hot_config.hot_data_days,
            warm_data_days = 30,
            cold_data_days = 365,
            auto_cleanup = true,
            cleanup_interval = 24
        },
        performance = {
            batch_size = 1000,
            query_cache_size = 10000,
            write_rate_limit = 0,
            query_concurrency = 8
        },
        monitoring = {
            enable_monitoring = true,
            monitor_port = instance_config.port + 2000,
            monitor_retention = 24
        },
        logging = {
            log_level = self.manager_config.log_level or "info",
            max_log_size = 100,
            log_retention_days = 7,
            enable_console_log = true,
            enable_file_log = true
        }
    }
    
    return config
end

-- 停止业务实例
function BusinessInstanceManager:stop_instance(business_type)
    local instance_info = self.instances[business_type]
    if not instance_info then
        print("[业务实例管理器] 业务实例未运行: " .. business_type)
        return true
    end
    
    print("[业务实例管理器] 停止业务实例: " .. business_type)
    
    -- 停止实例
    if instance_info.instance and instance_info.instance.close then
        pcall(function()
            instance_info.instance:close()
        end)
    end
    
    self.instances[business_type] = nil
    print("[业务实例管理器] 业务实例停止成功: " .. business_type)
    return true
end

-- 启动所有业务实例
function BusinessInstanceManager:start_all_instances()
    if self.is_running then
        print("[业务实例管理器] 实例管理器已在运行")
        return true
    end
    
    print("[业务实例管理器] 启动所有业务实例...")
    
    local success_count = 0
    local total_count = 0
    
    for business_type, config in pairs(self.instance_configs) do
        total_count = total_count + 1
        local success = pcall(function()
            return self:start_instance(business_type)
        end)
        
        if success then
            success_count = success_count + 1
        else
            print("[业务实例管理器] 启动业务实例失败: " .. business_type)
        end
    end
    
    self.is_running = true
    print(string.format("[业务实例管理器] 启动完成: %d/%d 个实例启动成功", success_count, total_count))
    return success_count == total_count
end

-- 停止所有业务实例
function BusinessInstanceManager:stop_all_instances()
    if not self.is_running then
        print("[业务实例管理器] 实例管理器未运行")
        return true
    end
    
    print("[业务实例管理器] 停止所有业务实例...")
    
    for business_type, _ in pairs(self.instances) do
        pcall(function()
            self:stop_instance(business_type)
        end)
    end
    
    self.instances = {}
    self.is_running = false
    print("[业务实例管理器] 所有业务实例已停止")
    return true
end

-- 获取实例状态
function BusinessInstanceManager:get_instance_status(business_type)
    local instance_info = self.instances[business_type]
    if not instance_info then
        return {
            status = "stopped",
            business_type = business_type,
            message = "实例未运行"
        }
    end
    
    return {
        status = instance_info.status,
        business_type = business_type,
        instance_id = instance_info.config.instance_id,
        port = instance_info.config.port,
        start_time = instance_info.start_time,
        uptime = os.time() - instance_info.start_time
    }
end

-- 获取所有实例状态
function BusinessInstanceManager:get_all_instances_status()
    local statuses = {}
    
    for business_type, _ in pairs(self.instance_configs) do
        statuses[business_type] = self:get_instance_status(business_type)
    end
    
    return statuses
end

-- 健康检查
function BusinessInstanceManager:health_check()
    if not self.is_running then
        return {
            healthy = false,
            message = "实例管理器未运行"
        }
    end
    
    local healthy_count = 0
    local total_count = 0
    local details = {}
    
    for business_type, instance_info in pairs(self.instances) do
        total_count = total_count + 1
        
        -- 简单的健康检查：检查实例是否还在运行
        if instance_info.status == "running" then
            healthy_count = healthy_count + 1
            details[business_type] = "healthy"
        else
            details[business_type] = "unhealthy"
        end
    end
    
    return {
        healthy = healthy_count == total_count,
        healthy_count = healthy_count,
        total_count = total_count,
        details = details
    }
end

-- 重新加载配置
function BusinessInstanceManager:reload_config()
    print("[业务实例管理器] 重新加载配置...")
    
    -- 保存当前运行状态
    local was_running = self.is_running
    
    if was_running then
        self:stop_all_instances()
    end
    
    -- 重新加载配置
    self:load_instance_configs()
    
    if was_running then
        self:start_all_instances()
    end
    
    print("[业务实例管理器] 配置重新加载完成")
    return true
end

-- 辅助函数：计算表大小
function table_size(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return BusinessInstanceManager