-- 轻度汇总数据库配置模块
-- 定义时间维度、其他维度、压缩策略等配置

local LightAggregationConfig = {}
LightAggregationConfig.__index = LightAggregationConfig

-- 时间维度汇总配置
local TIME_DIMENSIONS = {
    HOUR = {
        name = "hour",
        interval = 3600,      -- 秒
        format = "%Y%m%d%H",  -- 时间格式
        prefix = "H",         -- 键前缀
        separator = "|",      -- 分隔符
        enabled = true
    },
    DAY = {
        name = "day", 
        interval = 86400,     -- 秒
        format = "%Y%m%d",
        prefix = "D",
        separator = "|",
        enabled = true
    },
    WEEK = {
        name = "week",
        interval = 604800,     -- 秒
        format = "%Y%W",
        prefix = "W",
        separator = "|",
        enabled = true
    },
    MONTH = {
        name = "month",
        interval = 2592000,    -- 秒
        format = "%Y%m",
        prefix = "M",
        separator = "|",
        enabled = true
    }
}

-- 其他维度汇总配置
local OTHER_DIMENSIONS = {
    STOCK_CODE = {
        name = "stock_code",
        prefix = "S",
        separator = "|",
        enabled = true,
        fields = {"code"}
    },
    MARKET = {
        name = "market", 
        prefix = "M",
        separator = "|",
        enabled = true,
        fields = {"market"}
    },
    INDUSTRY = {
        name = "industry",
        prefix = "I", 
        separator = "|",
        enabled = true,
        fields = {"industry"}
    },
    REGION = {
        name = "region",
        prefix = "R",
        separator = "|",
        enabled = true,
        fields = {"region"}
    }
}

-- 汇总统计函数配置
local AGGREGATION_FUNCTIONS = {
    COUNT = {
        name = "count",
        func = function(values) return #values end,
        enabled = true
    },
    SUM = {
        name = "sum",
        func = function(values) 
            local sum = 0
            for _, v in ipairs(values) do
                sum = sum + (tonumber(v) or 0)
            end
            return sum
        end,
        enabled = true
    },
    AVG = {
        name = "avg",
        func = function(values)
            if #values == 0 then return 0 end
            local sum = 0
            for _, v in ipairs(values) do
                sum = sum + (tonumber(v) or 0)
            end
            return sum / #values
        end,
        enabled = true
    },
    MAX = {
        name = "max",
        func = function(values)
            if #values == 0 then return nil end
            local max = tonumber(values[1]) or -math.huge
            for _, v in ipairs(values) do
                local num = tonumber(v)
                if num and num > max then
                    max = num
                end
            end
            return max
        end,
        enabled = true
    },
    MIN = {
        name = "min",
        func = function(values)
            if #values == 0 then return nil end
            local min = tonumber(values[1]) or math.huge
            for _, v in ipairs(values) do
                local num = tonumber(v)
                if num and num < min then
                    min = num
                end
            end
            return min
        end,
        enabled = true
    },
    FIRST = {
        name = "first",
        func = function(values)
            return values[1]
        end,
        enabled = true
    },
    LAST = {
        name = "last",
        func = function(values)
            return values[#values]
        end,
        enabled = true
    }
}

-- 压缩策略配置
local COMPRESSION_STRATEGIES = {
    SEPARATOR = {
        name = "separator",
        enabled = true,
        config = {
            separator = "|",
            max_length = 1000
        }
    },
    PREFIX = {
        name = "prefix",
        enabled = true,
        config = {
            min_prefix_length = 2,
            max_prefix_length = 10
        }
    },
    LZ4 = {
        name = "lz4",
        enabled = true,
        config = {
            compression_level = 6
        }
    }
}

-- 默认配置
local DEFAULT_CONFIG = {
    -- ZeroMQ异步配置
    zmq = {
        enabled = true,
        port = 5565,
        threads = 4,
        max_connections = 1000,
        send_timeout = 5000,
        recv_timeout = 5000
    },
    
    -- 汇总计算配置
    aggregation = {
        enabled = true,
        batch_size = 1000,
        flush_interval = 60,      -- 秒
        retention_days = 365,     -- 数据保留天数
        max_memory_usage = 1024 * 1024 * 100, -- 100MB
        enable_compression = true
    },
    
    -- RocksDB存储配置
    storage = {
        path = "./data/light_aggregation_db",
        write_buffer_size = 64 * 1024 * 1024,
        max_write_buffer_number = 4,
        block_cache_size = 256 * 1024 * 1024,
        compression = "lz4",
        enable_statistics = true,
        
        -- 分隔符压缩配置（关键优化）
        enable_separator_compression = true,  -- 启用分隔符压缩
        separator = "|",                       -- 分隔符字符
        separator_position = 3,               -- 在第3个分隔符处生效
        prefix_extractor_length = 2,           -- 提取前2个分隔符作为前缀
        memtable_prefix_bloom_ratio = 0.1      -- 10%内存用于布隆过滤器
    },
    
    -- 监控配置
    monitoring = {
        enabled = true,
        stats_interval = 300,     -- 秒
        enable_prometheus = false,
        prometheus_port = 9090
    }
}

function LightAggregationConfig:new(config)
    local obj = setmetatable({}, LightAggregationConfig)
    obj.config = config or DEFAULT_CONFIG
    obj.time_dimensions = TIME_DIMENSIONS
    obj.other_dimensions = OTHER_DIMENSIONS
    obj.aggregation_functions = AGGREGATION_FUNCTIONS
    obj.compression_strategies = COMPRESSION_STRATEGIES
    
    -- 合并用户配置
    if config then
        obj.config = self:merge_config(DEFAULT_CONFIG, config)
    end
    
    return obj
end

-- 合并配置
function LightAggregationConfig:merge_config(default, user)
    local merged = {}
    
    for key, value in pairs(default) do
        if user[key] ~= nil then
            if type(value) == "table" and type(user[key]) == "table" then
                merged[key] = self:merge_config(value, user[key])
            else
                merged[key] = user[key]
            end
        else
            merged[key] = value
        end
    end
    
    return merged
end

-- 获取时间维度配置
function LightAggregationConfig:get_time_dimension(name)
    for _, dim in pairs(self.time_dimensions) do
        if dim.name == name then
            return dim
        end
    end
    return nil
end

-- 获取其他维度配置
function LightAggregationConfig:get_other_dimension(name)
    for _, dim in pairs(self.other_dimensions) do
        if dim.name == name then
            return dim
        end
    end
    return nil
end

-- 获取启用的时间维度
function LightAggregationConfig:get_enabled_time_dimensions()
    local enabled = {}
    for _, dim in pairs(self.time_dimensions) do
        if dim.enabled then
            table.insert(enabled, dim)
        end
    end
    return enabled
end

-- 获取启用的其他维度
function LightAggregationConfig:get_enabled_other_dimensions()
    local enabled = {}
    for _, dim in pairs(self.other_dimensions) do
        if dim.enabled then
            table.insert(enabled, dim)
        end
    end
    return enabled
end

-- 获取汇总函数
function LightAggregationConfig:get_aggregation_function(name)
    for _, func in pairs(self.aggregation_functions) do
        if func.name == name then
            return func
        end
    end
    return nil
end

-- 获取压缩策略
function LightAggregationConfig:get_compression_strategy(name)
    for _, strategy in pairs(self.compression_strategies) do
        if strategy.name == name then
            return strategy
        end
    end
    return nil
end

-- 验证配置
function LightAggregationConfig:validate()
    local errors = {}
    
    -- 验证存储路径
    if not self.config.storage.path or self.config.storage.path == "" then
        table.insert(errors, "存储路径不能为空")
    end
    
    -- 验证端口范围
    if self.config.zmq.port < 1024 or self.config.zmq.port > 65535 then
        table.insert(errors, "ZeroMQ端口必须在1024-65535范围内")
    end
    
    -- 验证批处理大小
    if self.config.aggregation.batch_size <= 0 then
        table.insert(errors, "批处理大小必须大于0")
    end
    
    -- 验证至少启用一个维度
    local enabled_time_dims = self:get_enabled_time_dimensions()
    local enabled_other_dims = self:get_enabled_other_dimensions()
    
    if #enabled_time_dims == 0 and #enabled_other_dims == 0 then
        table.insert(errors, "至少需要启用一个汇总维度")
    end
    
    return #errors == 0, errors
end

-- 生成配置摘要
function LightAggregationConfig:get_summary()
    local summary = {
        time_dimensions = {},
        other_dimensions = {},
        aggregation_functions = {},
        compression_strategies = {}
    }
    
    -- 时间维度摘要
    for _, dim in pairs(self:get_enabled_time_dimensions()) do
        table.insert(summary.time_dimensions, {
            name = dim.name,
            interval = dim.interval,
            prefix = dim.prefix
        })
    end
    
    -- 其他维度摘要
    for _, dim in pairs(self:get_enabled_other_dimensions()) do
        table.insert(summary.other_dimensions, {
            name = dim.name,
            prefix = dim.prefix,
            fields = dim.fields
        })
    end
    
    -- 汇总函数摘要
    for name, func in pairs(self.aggregation_functions) do
        if func.enabled then
            table.insert(summary.aggregation_functions, func.name)
        end
    end
    
    -- 压缩策略摘要
    for name, strategy in pairs(self.compression_strategies) do
        if strategy.enabled then
            table.insert(summary.compression_strategies, strategy.name)
        end
    end
    
    return summary
end

-- 导出配置为JSON格式
function LightAggregationConfig:to_json()
    local cjson = require "cjson"
    return cjson.encode({
        config = self.config,
        time_dimensions = self.time_dimensions,
        other_dimensions = self.other_dimensions,
        aggregation_functions = self.aggregation_functions,
        compression_strategies = self.compression_strategies
    })
end

-- 从JSON导入配置
function LightAggregationConfig:from_json(json_str)
    local cjson = require "cjson"
    local data = cjson.decode(json_str)
    
    if data.config then
        self.config = self:merge_config(DEFAULT_CONFIG, data.config)
    end
    
    if data.time_dimensions then
        self.time_dimensions = data.time_dimensions
    end
    
    if data.other_dimensions then
        self.other_dimensions = data.other_dimensions
    end
    
    if data.aggregation_functions then
        self.aggregation_functions = data.aggregation_functions
    end
    
    if data.compression_strategies then
        self.compression_strategies = data.compression_strategies
    end
    
    return true
end

return LightAggregationConfig