#!/usr/bin/env luajit

-- 配置管理器 - 基于RocksDB的配置元数据管理
-- 使用公共RocksDB FFI模块进行配置存储

-- 使用cjson库进行JSON序列化/反序列化
-- 使用本地lib目录中的cjson库
package.cpath = package.cpath .. ";./lib/?.so"

-- 尝试加载cjson模块
local json = nil
local cjson_ok, cjson_module = pcall(require, "cjson")
if cjson_ok then
    json = cjson_module
    print("[ConfigManager] 成功加载cjson库")
else
    -- 如果标准require失败，使用简单JSON实现
    print("[ConfigManager] 警告: 无法加载cjson库，使用简单JSON实现")
    json = {}
    
    -- 简单的JSON编码函数
    function json.encode(data)
        if type(data) == "table" then
            local parts = {}
            for k, v in pairs(data) do
                if type(k) == "number" then
                    table.insert(parts, json.encode(v))
                else
                    table.insert(parts, string.format('"%s":%s', k, json.encode(v)))
                end
            end
            if #parts > 0 and next(data, next(data)) == nil then
                return "[" .. table.concat(parts, ",") .. "]"
            else
                return "{" .. table.concat(parts, ",") .. "}"
            end
        elseif type(data) == "string" then
            return '"' .. data:gsub('"', '\\"') .. '"'
        elseif type(data) == "number" or type(data) == "boolean" then
            return tostring(data)
        else
            return "null"
        end
    end
    
    -- 简单的JSON解码函数（仅支持基本类型）
    function json.decode(str)
        -- 移除空白字符
        str = str:gsub("%s+", "")
        
        if str:sub(1,1) == "{" and str:sub(-1) == "}" then
            local result = {}
            local content = str:sub(2, -2)
            local key, value
            
            -- 简单的键值对解析
            for pair in content:gmatch("[^,}]+") do
                local k, v = pair:match('"([^"]+)":(.+)')
                if k and v then
                    if v:sub(1,1) == '"' then
                        result[k] = v:sub(2, -2)
                    elseif v == "true" then
                        result[k] = true
                    elseif v == "false" then
                        result[k] = false
                    elseif tonumber(v) then
                        result[k] = tonumber(v)
                    end
                end
            end
            return result
        else
            return nil
        end
    end
end

-- 使用公共RocksDB FFI模块
local RocksDBFFI = require "rocksdb_ffi"

local ConfigManager = {}
ConfigManager.__index = ConfigManager

-- 配置键前缀定义
local CONFIG_PREFIXES = {
    BUSINESS_CONFIG = "business:",      -- 业务配置
    SYSTEM_CONFIG = "system:",         -- 系统配置
    INSTANCE_CONFIG = "instance:",     -- 实例配置
    ROUTING_CONFIG = "routing:",       -- 路由配置
    METADATA_CONFIG = "metadata:",     -- 元数据配置
}

function ConfigManager:new(config_db_path)
    local obj = setmetatable({}, ConfigManager)
    obj.config_db_path = config_db_path or "./data/config_db"
    obj.is_initialized = false
    obj.config_cache = {}  -- 内存缓存，存储所有配置
    obj.config_versions = {}  -- 配置版本管理
    
    -- RocksDB相关属性
    obj.db = nil
    obj.options = nil
    obj.read_options = nil
    obj.write_options = nil
    
    return obj
end

-- 初始化配置数据库
function ConfigManager:initialize()
    if self.is_initialized then
        return true, "Already initialized"
    end
    
    -- 创建RocksDB选项
    self.options = RocksDBFFI.create_options()
    RocksDBFFI.set_create_if_missing(self.options, true)
    RocksDBFFI.set_compression(self.options, 4)  -- LZ4压缩
    
    -- 打开数据库
    local db, err = RocksDBFFI.open_database(self.options, self.config_db_path)
    if not db then
        return false, "Failed to open config database: " .. err
    end
    self.db = db
    
    -- 创建读写选项
    self.read_options = RocksDBFFI.create_read_options()
    self.write_options = RocksDBFFI.create_write_options()
    
    self.is_initialized = true
    
    -- 加载所有配置到内存缓存
    self:load_all_configs()
    
    return true, "Config manager initialized successfully"
end

-- 系统启动时一次性加载所有配置到内存
function ConfigManager:load_all_configs()
    print("[ConfigManager] 系统启动: 正在从RocksDB加载所有配置到内存...")
    
    -- 清空现有缓存
    self.config_cache = {}
    
    -- 从RocksDB加载所有配置
    local iterator = RocksDBFFI.create_iterator(self.db, self.read_options)
    RocksDBFFI.iterator_seek_to_first(iterator)
    
    local loaded_count = 0
    while RocksDBFFI.iterator_valid(iterator) do
        local key = RocksDBFFI.iterator_key(iterator)
        local value = RocksDBFFI.iterator_value(iterator)
        
        if key and value then
            local config_value = json.decode(value)
            if config_value then
                self.config_cache[key] = config_value
                loaded_count = loaded_count + 1
            end
        end
        
        RocksDBFFI.iterator_next(iterator)
    end
    
    -- 如果数据库为空，初始化默认配置
    if loaded_count == 0 then
        print("[ConfigManager] 数据库为空，正在初始化默认配置...")
        self:initialize_default_configs()
        loaded_count = self:get_config_count()
    end
    
    print("[ConfigManager] 配置加载完成，共加载 " .. loaded_count .. " 个配置项")
    return true
end

function ConfigManager:initialize_default_configs()
    -- 业务配置
    local business_configs = {
        stock_quotes = {
            name = "股票行情数据",
            description = "股票实时行情数据存储",
            block_size = 60,
            retention_days = 30,
            fields = {
                {name = "timestamp", type = "int", description = "时间戳"},
                {name = "stock_code", type = "string", description = "股票代码"},
                {name = "price", type = "float", description = "价格"},
                {name = "volume", type = "int", description = "成交量"}
            },
            compression = "lz4",
            index_fields = {"timestamp", "stock_code"}
        },
        iot_data = {
            name = "物联网数据",
            description = "物联网设备传感器数据",
            block_size = 300,
            retention_days = 90,
            fields = {
                {name = "timestamp", type = "int", description = "时间戳"},
                {name = "device_id", type = "string", description = "设备ID"},
                {name = "sensor_type", type = "string", description = "传感器类型"},
                {name = "value", type = "float", description = "传感器值"}
            },
            compression = "snappy",
            index_fields = {"timestamp", "device_id"}
        },
        order_data = {
            name = "订单数据",
            description = "电商订单交易数据",
            block_size = 3600,
            retention_days = 180,
            fields = {
                {name = "timestamp", type = "int", description = "时间戳"},
                {name = "order_id", type = "string", description = "订单ID"},
                {name = "user_id", type = "string", description = "用户ID"},
                {name = "amount", type = "float", description = "订单金额"},
                {name = "status", type = "string", description = "订单状态"}
            },
            compression = "lz4",
            index_fields = {"timestamp", "order_id"}
        },
        payment_data = {
            name = "支付数据",
            description = "支付交易流水数据",
            block_size = 3600,
            retention_days = 365,
            fields = {
                {name = "timestamp", type = "int", description = "时间戳"},
                {name = "payment_id", type = "string", description = "支付ID"},
                {name = "user_id", type = "string", description = "用户ID"},
                {name = "amount", type = "float", description = "支付金额"},
                {name = "channel", type = "string", description = "支付渠道"}
            },
            compression = "lz4",
            index_fields = {"timestamp", "payment_id"}
        }
    }
    
    -- 将业务配置保存到缓存和数据库
    for biz_type, config in pairs(business_configs) do
        local key = CONFIG_PREFIXES.BUSINESS_CONFIG .. biz_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
    
    -- 系统配置
    local system_config = {
        server = {
            port = 6379,
            bind = "0.0.0.0",
            max_connections = 10000,
            timeout = 300,
            log_level = "info"
        },
        storage = {
            data_dir = "./data",
            write_buffer_size = 64 * 1024 * 1024,  -- 64MB
            max_write_buffer_number = 4,
            target_file_size_base = 64 * 1024 * 1024,  -- 64MB
            max_bytes_for_level_base = 256 * 1024 * 1024,  -- 256MB
            compression = 4  -- lz4
        }
    }
    self.config_cache[CONFIG_PREFIXES.SYSTEM_CONFIG .. "main"] = system_config
    self:save_to_db(CONFIG_PREFIXES.SYSTEM_CONFIG .. "main", system_config)
    
    -- 实例配置
    local instance_configs = {
        stock_quotes_instance = {
            port = 6380,
            data_dir = "./data/stock_quotes",
            max_memory = "1GB",
            persistence = "aof"
        },
        iot_data_instance = {
            port = 6381,
            data_dir = "./data/iot_data",
            max_memory = "512MB",
            persistence = "rdb"
        },
        order_data_instance = {
            port = 6382,
            data_dir = "./data/order_data",
            max_memory = "2GB",
            persistence = "aof"
        },
        payment_data_instance = {
            port = 6383,
            data_dir = "./data/payment_data",
            max_memory = "1GB",
            persistence = "aof"
        }
    }
    
    for instance_type, config in pairs(instance_configs) do
        local key = CONFIG_PREFIXES.INSTANCE_CONFIG .. instance_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
    
    -- 路由配置
    local routing_config = {
        stock = "stock_quotes",
        iot = "iot_data",
        order = "order_data",
        payment = "payment_data"
    }
    self.config_cache[CONFIG_PREFIXES.ROUTING_CONFIG .. "main"] = routing_config
    self:save_to_db(CONFIG_PREFIXES.ROUTING_CONFIG .. "main", routing_config)
    
    -- 元数据配置
    local metadata_config = {
        version = "1.0.0",
        last_updated = os.time(),
        config_count = self:get_config_count()
    }
    self.config_cache[CONFIG_PREFIXES.METADATA_CONFIG .. "main"] = metadata_config
    self:save_to_db(CONFIG_PREFIXES.METADATA_CONFIG .. "main", metadata_config)
end

-- 加载业务配置
function ConfigManager:load_business_configs()
    local business_configs = {
        ["sms"] = {
            name = "短信下发",
            description = "短信发送记录、状态等",
            block_size = 60,
            retention_days = 30,
            fields = {
                {name = "sms_id", type = "string", description = "短信ID"},
                {name = "phone", type = "string", description = "手机号"},
                {name = "content", type = "string", description = "短信内容"},
                {name = "status", type = "string", description = "发送状态"},
                {name = "provider", type = "string", description = "服务商"},
                {name = "cost", type = "double", description = "费用"},
            },
            compression = "lz4",
            indexes = {"timestamp", "sms_id", "phone"},
        },
        ["orders"] = {
            name = "订单数据",
            description = "电商订单、交易订单等",
            block_size = 300,
            retention_days = 180,
            fields = {
                {name = "order_id", type = "string", description = "订单ID"},
                {name = "user_id", type = "string", description = "用户ID"},
                {name = "amount", type = "double", description = "订单金额"},
                {name = "status", type = "string", description = "订单状态"},
                {name = "product_count", type = "int32", description = "商品数量"},
            },
            compression = "zstd",
            indexes = {"timestamp", "order_id", "user_id"},
        },
        ["stock_quotes"] = {
            name = "金融行情",
            description = "股票、期货、外汇等金融行情数据",
            block_size = 30,
            retention_days = 90,
            fields = {
                {name = "open", type = "double", description = "开盘价"},
                {name = "high", type = "double", description = "最高价"},
                {name = "low", type = "double", description = "最低价"},
                {name = "close", type = "double", description = "收盘价"},
                {name = "volume", type = "int64", description = "成交量"},
                {name = "amount", type = "double", description = "成交额"},
            },
            compression = "lz4",
            indexes = {"timestamp", "symbol"},
        },
        -- 其他业务配置...
    }
    
    for biz_type, config in pairs(business_configs) do
        local key = CONFIG_PREFIXES.BUSINESS_CONFIG .. biz_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
end

-- 加载系统配置
function ConfigManager:load_system_configs()
    local system_configs = {
        ["server"] = {
            port = 6379,
            bind = "127.0.0.1",
            max_connections = 1000,
            use_event_driver = true,
        },
        ["storage"] = {
            data_dir = "./data",
            log_dir = "./logs",
            block_size = 30,
            compression_level = 6,
            enable_compression = true,
        },
        ["performance"] = {
            batch_size = 1000,
            query_cache_size = 10000,
            write_rate_limit = 0,
            query_concurrency = 8,
            enable_prefetch = true,
        },
        ["monitoring"] = {
            enable_monitoring = true,
            monitor_port = 8080,
            monitor_retention = 24,
            write_qps_threshold = 50000,
            query_latency_threshold = 100,
            error_rate_threshold = 0.01,
        },
    }
    
    for config_type, config in pairs(system_configs) do
        local key = CONFIG_PREFIXES.SYSTEM_CONFIG .. config_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
end

-- 加载实例配置
function ConfigManager:load_instance_configs()
    local instance_configs = {
        ["stock_quotes"] = {
            port = 6380,
            data_dir = "./data/stock",
            compression = "lz4",
            block_size = 30,
            retention_days = 90,
        },
        ["iot_data"] = {
            port = 6381,
            data_dir = "./data/iot",
            compression = "lz4",
            block_size = 60,
            retention_days = 30,
        },
        ["financial_quotes"] = {
            port = 6382,
            data_dir = "./data/finance",
            compression = "zstd",
            block_size = 30,
            retention_days = 180,
        },
        ["order_data"] = {
            port = 6383,
            data_dir = "./data/orders",
            compression = "zstd",
            block_size = 300,
            retention_days = 365,
        },
        ["payment_data"] = {
            port = 6384,
            data_dir = "./data/payments",
            compression = "zstd",
            block_size = 600,
            retention_days = 365,
        },
        ["inventory_data"] = {
            port = 6385,
            data_dir = "./data/inventory",
            compression = "lz4",
            block_size = 60,
            retention_days = 60,
        },
        ["sms_data"] = {
            port = 6386,
            data_dir = "./data/sms",
            compression = "lz4",
            block_size = 60,
            retention_days = 30,
        },
    }
    
    for instance_type, config in pairs(instance_configs) do
        local key = CONFIG_PREFIXES.INSTANCE_CONFIG .. instance_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
end

-- 加载路由配置
function ConfigManager:load_routing_configs()
    local routing_configs = {
        ["business_patterns"] = {
            ["stock:"] = "stock_quotes",
            ["iot:"] = "iot_data",
            ["finance:"] = "financial_quotes",
            ["order:"] = "order_data",
            ["payment:"] = "payment_data",
            ["inventory:"] = "inventory_data",
            ["sms:"] = "sms_data",
        },
        ["port_mapping"] = {
            stock_quotes = 6380,
            iot_data = 6381,
            financial_quotes = 6382,
            order_data = 6383,
            payment_data = 6384,
            inventory_data = 6385,
            sms_data = 6386,
        },
    }
    
    for routing_type, config in pairs(routing_configs) do
        local key = CONFIG_PREFIXES.ROUTING_CONFIG .. routing_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
end

-- 加载元数据配置
function ConfigManager:load_metadata_configs()
    local metadata_configs = {
        ["version"] = {
            config_schema_version = "1.0",
            last_updated = os.date("%Y-%m-%d %H:%M:%S"),
            created_by = "ConfigManager",
        },
        ["statistics"] = {
            total_business_types = 7,
            total_instances = 7,
            config_items_count = 0, -- 动态计算
        },
    }
    
    for meta_type, config in pairs(metadata_configs) do
        local key = CONFIG_PREFIXES.METADATA_CONFIG .. meta_type
        self.config_cache[key] = config
        self:save_to_db(key, config)
    end
end

-- 保存配置到RocksDB
function ConfigManager:save_to_db(key, config)
    if not self.is_initialized then
        return false, "配置管理器未初始化"
    end
    
    local config_json = json.encode(config)
    local success, err = RocksDBFFI.put(self.db, self.write_options, key, config_json)
    
    if not success then
        return false, "配置保存失败: " .. err
    end
    
    return true
end

-- 从RocksDB加载配置
function ConfigManager:load_from_db(key)
    if not self.is_initialized then
        return nil, "配置管理器未初始化"
    end
    
    local value, err = RocksDBFFI.get(self.db, self.read_options, key)
    
    if err then
        return nil, "配置加载失败: " .. err
    end
    
    if value == nil then
        return nil, "配置不存在: " .. key
    end
    
    return json.decode(value)
end

-- 获取配置（优先从内存缓存）
function ConfigManager:get_config(config_type, config_key)
    -- 映射配置类型到前缀键
    local prefix_map = {
        business = CONFIG_PREFIXES.BUSINESS_CONFIG,
        system = CONFIG_PREFIXES.SYSTEM_CONFIG,
        instance = CONFIG_PREFIXES.INSTANCE_CONFIG,
        routing = CONFIG_PREFIXES.ROUTING_CONFIG,
        metadata = CONFIG_PREFIXES.METADATA_CONFIG
    }
    
    local prefix = prefix_map[config_type]
    if not prefix then
        return nil, "不支持的配置类型: " .. config_type
    end
    
    local full_key = prefix .. config_key
    
    -- 优先从内存缓存获取
    if self.config_cache[full_key] then
        return self.config_cache[full_key]
    end
    
    -- 如果内存缓存中没有，尝试从RocksDB加载
    local config, err = self:load_from_db(full_key)
    if config then
        self.config_cache[full_key] = config
    end
    
    return config, err
end

-- 更新配置
function ConfigManager:update_config(config_type, config_key, new_config)
    -- 映射配置类型到前缀键
    local prefix_map = {
        business = CONFIG_PREFIXES.BUSINESS_CONFIG,
        system = CONFIG_PREFIXES.SYSTEM_CONFIG,
        instance = CONFIG_PREFIXES.INSTANCE_CONFIG,
        routing = CONFIG_PREFIXES.ROUTING_CONFIG,
        metadata = CONFIG_PREFIXES.METADATA_CONFIG
    }
    
    local prefix = prefix_map[config_type]
    if not prefix then
        return false, "不支持的配置类型: " .. config_type
    end
    
    local full_key = prefix .. config_key
    
    -- 保存到数据库
    local success, err = self:save_to_db(full_key, new_config)
    if not success then
        return false, err
    end
    
    -- 更新内存缓存
    self.config_cache[full_key] = new_config
    
    -- 记录配置版本
    self.config_versions[full_key] = self.config_versions[full_key] or {}
    table.insert(self.config_versions[full_key], {
        timestamp = os.time(),
        value = new_config
    })
    
    return true
end

-- 获取所有业务配置
function ConfigManager:get_all_business_configs()
    local business_configs = {}
    
    for key, config in pairs(self.config_cache) do
        if key:startswith(CONFIG_PREFIXES.BUSINESS_CONFIG) then
            local biz_type = key:sub(#CONFIG_PREFIXES.BUSINESS_CONFIG + 1)
            business_configs[biz_type] = config
        end
    end
    
    return business_configs
end

-- 获取所有实例配置
function ConfigManager:get_all_instance_configs()
    local instance_configs = {}
    
    for key, config in pairs(self.config_cache) do
        if key:startswith(CONFIG_PREFIXES.INSTANCE_CONFIG) then
            local instance_type = key:sub(#CONFIG_PREFIXES.INSTANCE_CONFIG + 1)
            instance_configs[instance_type] = config
        end
    end
    
    return instance_configs
end

-- 获取路由配置
function ConfigManager:get_routing_config()
    return self:get_config("routing", "business_patterns")
end

-- 获取端口映射
function ConfigManager:get_port_mapping()
    return self:get_config("routing", "port_mapping")
end

-- 获取配置统计信息
function ConfigManager:get_config_count()
    local count = 0
    for _ in pairs(self.config_cache) do
        count = count + 1
    end
    return count
end

-- 设置配置（Web界面使用）
function ConfigManager:set_config(key, value)
    if not self.is_initialized then
        return false, "配置管理器未初始化"
    end
    
    -- 如果value为nil，表示删除配置
    if value == nil then
        -- 从数据库删除
        local success, err = RocksDBFFI.delete(self.db, self.write_options, key)
        if not success then
            return false, "配置删除失败: " .. err
        end
        
        -- 从内存缓存删除
        self.config_cache[key] = nil
        
        return true
    end
    
    -- 保存配置到数据库
    local config_json = json.encode(value)
    local success, err = RocksDBFFI.put(self.db, self.write_options, key, config_json)
    
    if not success then
        return false, "配置保存失败: " .. err
    end
    
    -- 更新内存缓存
    self.config_cache[key] = value
    
    -- 记录配置版本
    self.config_versions[key] = self.config_versions[key] or {}
    table.insert(self.config_versions[key], {
        timestamp = os.time(),
        value = value
    })
    
    return true
end

-- 获取所有配置（Web界面使用）
function ConfigManager:get_all_configs()
    return self.config_cache
end

-- 获取业务类型列表（Web界面使用）
function ConfigManager:get_business_types()
    local business_types = {}
    
    for key, config in pairs(self.config_cache) do
        if key:startswith(CONFIG_PREFIXES.BUSINESS_CONFIG) then
            local biz_type = key:sub(#CONFIG_PREFIXES.BUSINESS_CONFIG + 1)
            table.insert(business_types, {
                type = biz_type,
                name = config.name or biz_type,
                description = config.description or ""
            })
        end
    end
    
    return business_types
end

-- 字符串startswith辅助函数
function string.startswith(str, start)
    return str:sub(1, #start) == start
end

-- 关闭配置管理器
function ConfigManager:close()
    if self.db then
        RocksDBFFI.close_database(self.db)
        self.db = nil
    end
    self.is_initialized = false
    print("[ConfigManager] 配置管理器已关闭")
end

return ConfigManager