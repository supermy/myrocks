-- 业务实例管理器
-- 负责启动和管理不同业务的独立数据库实例

local BusinessInstanceManager = {}
BusinessInstanceManager.__index = BusinessInstanceManager

-- 导入必要的模块
local RocksDBFFI = require "rocksdb_ffi"
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
        logger.error("Instance config not found: " .. business_type)
        return false, "Instance config not found"
    end
    
    if self.instances[business_type] then
        logger.warn("Instance already started: " .. business_type)
        return true, "Instance already running"
    end
    
    -- 创建实例配置
    local config = self:create_instance_config(instance_config)
    
    -- 确保数据目录存在
    local data_dir = config.storage.data_dir
    local cmd = "mkdir -p " .. data_dir
    os.execute(cmd)
    
    -- 创建RocksDB数据库
    local options = RocksDBFFI.create_options()
    RocksDBFFI.set_create_if_missing(options, true)
    
    if config.storage.rocksdb_options.compression == "snappy" then
        RocksDBFFI.set_compression(options, 1)  -- Snappy压缩
    end
    
    local db, err = RocksDBFFI.open_database(options, data_dir)
    if not db then
        logger.error("Failed to create RocksDB instance: " .. business_type .. ", error: " .. tostring(err))
        return false, "Failed to create RocksDB instance: " .. tostring(err)
    end
    
    -- 保存实例
    self.instances[business_type] = {
        db = db,
        config = config,
        is_running = true,
        start_time = os.time(),
        data_dir = data_dir,
        options = options
    }
    
    logger.info("RocksDB instance started successfully: " .. business_type .. " at " .. data_dir)
    return true, "RocksDB instance started successfully"
end

-- 创建实例特定的配置
function BusinessInstanceManager:create_instance_config(instance_config)
    local config = {
        storage = {
            data_dir = instance_config.data_dir,
            rocksdb_options = {
                write_buffer_size = instance_config.write_buffer_size or 64 * 1024 * 1024,
                block_cache_size = instance_config.block_cache_size or 128 * 1024 * 1024,
                max_write_buffer_number = instance_config.max_write_buffer_number or 4,
                min_write_buffer_number_to_merge = instance_config.min_write_buffer_number_to_merge or 1,
                compression = instance_config.compression or "snappy",
                create_if_missing = true,
                error_if_exists = false
            }
        },
        data_retention = {
            hot_data_days = instance_config.hot_data_days or 7,
            warm_data_days = instance_config.warm_data_days or 30,
            cold_data_days = instance_config.cold_data_days or 365
        },
        performance = {
            batch_size = instance_config.batch_size or 1000,
            query_cache_size = instance_config.query_cache_size or 10000
        },
        monitor = {
            port = instance_config.monitor_port or 9090
        }
    }
    
    return config
end

-- 停止业务实例
function BusinessInstanceManager:stop_instance(business_type)
    local instance_info = self.instances[business_type]
    if not instance_info then
        logger.warn("Instance not found: " .. business_type)
        return false, "Instance not found"
    end
    
    if not instance_info.is_running then
        logger.warn("Instance already stopped: " .. business_type)
        return true, "Instance already stopped"
    end
    
    -- 关闭RocksDB数据库
    if instance_info.db then
        RocksDBFFI.close_database(instance_info.db)
    end
    
    -- 清理选项
    if instance_info.options then
        -- 选项会在垃圾回收时自动销毁
        instance_info.options = nil
    end
    
    -- 更新实例状态
    instance_info.is_running = false
    instance_info.stop_time = os.time()
    
    logger.info("RocksDB instance stopped successfully: " .. business_type)
    return true, "RocksDB instance stopped successfully"
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