-- 时间维度汇总计算模块
-- 实现小时、天、周、月维度的汇总计算

local TimeDimensionAggregator = {}
TimeDimensionAggregator.__index = TimeDimensionAggregator

local os = require "os"
local math = require "math"

-- 时间工具函数
local TimeUtils = {}

-- 获取时间戳对应的整点小时时间戳
function TimeUtils:get_hour_timestamp(timestamp)
    -- 验证时间戳类型
    if type(timestamp) ~= "number" then
        -- 尝试转换为数字
        local num_timestamp = tonumber(timestamp)
        if not num_timestamp then
            -- 如果无法转换，使用当前时间戳
            return math.floor(os.time() / 3600) * 3600
        end
        timestamp = num_timestamp
    end
    return math.floor(timestamp / 3600) * 3600
end

-- 获取时间戳对应的整天时间戳
function TimeUtils:get_day_timestamp(timestamp)
    -- 验证时间戳类型
    if type(timestamp) ~= "number" then
        -- 尝试转换为数字
        local num_timestamp = tonumber(timestamp)
        if not num_timestamp then
            -- 如果无法转换，使用当前时间戳
            return math.floor(os.time() / 86400) * 86400
        end
        timestamp = num_timestamp
    end
    return math.floor(timestamp / 86400) * 86400
end

-- 获取时间戳对应的整周时间戳
function TimeUtils:get_week_timestamp(timestamp)
    -- 验证时间戳类型
    if type(timestamp) ~= "number" then
        -- 尝试转换为数字
        local num_timestamp = tonumber(timestamp)
        if not num_timestamp then
            -- 如果无法转换，使用当前时间戳
            timestamp = os.time()
        else
            timestamp = num_timestamp
        end
    end
    local day_timestamp = self:get_day_timestamp(timestamp)
    -- 计算周偏移（假设周一为周开始）
    local weekday = os.date("%w", day_timestamp)
    local offset = (tonumber(weekday) + 6) % 7  -- 转换为周一为0
    return day_timestamp - offset * 86400
end

-- 获取时间戳对应的整月时间戳
function TimeUtils:get_month_timestamp(timestamp)
    -- 验证时间戳类型
    if type(timestamp) ~= "number" then
        -- 尝试转换为数字
        local num_timestamp = tonumber(timestamp)
        if not num_timestamp then
            -- 如果无法转换，使用当前时间戳
            timestamp = os.time()
        else
            timestamp = num_timestamp
        end
    end
    local time_table = os.date("*t", timestamp)
    time_table.day = 1
    time_table.hour = 0
    time_table.min = 0
    time_table.sec = 0
    return os.time(time_table)
end

-- 格式化时间戳
function TimeUtils:format_timestamp(timestamp, format)
    return os.date(format, timestamp)
end

-- 计算时间维度键
function TimeDimensionAggregator:calculate_dimension_keys(timestamp, config)
    local keys = {}
    
    -- 获取时间维度配置（支持LightAggregationConfig对象和普通配置表）
    local time_dimensions = config.time_dimensions or config
    
    -- 小时维度
    if time_dimensions.HOUR and time_dimensions.HOUR.enabled then
        local hour_timestamp = TimeUtils:get_hour_timestamp(timestamp)
        local hour_key = time_dimensions.HOUR.prefix .. 
                        time_dimensions.HOUR.separator ..
                        TimeUtils:format_timestamp(hour_timestamp, time_dimensions.HOUR.format)
        keys.HOUR = hour_key
    end
    
    -- 天维度
    if time_dimensions.DAY and time_dimensions.DAY.enabled then
        local day_timestamp = TimeUtils:get_day_timestamp(timestamp)
        local day_key = time_dimensions.DAY.prefix .. 
                       time_dimensions.DAY.separator ..
                       TimeUtils:format_timestamp(day_timestamp, time_dimensions.DAY.format)
        keys.DAY = day_key
    end
    
    -- 周维度
    if time_dimensions.WEEK and time_dimensions.WEEK.enabled then
        local week_timestamp = TimeUtils:get_week_timestamp(timestamp)
        local week_key = time_dimensions.WEEK.prefix .. 
                        time_dimensions.WEEK.separator ..
                        TimeUtils:format_timestamp(week_timestamp, time_dimensions.WEEK.format)
        keys.WEEK = week_key
    end
    
    -- 月维度
    if time_dimensions.MONTH and time_dimensions.MONTH.enabled then
        local month_timestamp = TimeUtils:get_month_timestamp(timestamp)
        local month_key = time_dimensions.MONTH.prefix .. 
                         time_dimensions.MONTH.separator ..
                         TimeUtils:format_timestamp(month_timestamp, time_dimensions.MONTH.format)
        keys.MONTH = month_key
    end
    
    return keys
end

-- 创建时间维度聚合器
function TimeDimensionAggregator:new(config)
    local obj = setmetatable({}, TimeDimensionAggregator)
    
    -- 直接使用传入的配置对象（可能是LightAggregationConfig或普通配置表）
    obj.config = config or {}
    
    obj.buffers = {}  -- 时间维度缓冲区
    obj.last_flush_time = os.time()
    
    -- 初始化缓冲区
    obj:init_buffers()
    
    return obj
end

-- 初始化缓冲区
function TimeDimensionAggregator:init_buffers()
    self.buffers = {
        HOUR = {},
        DAY = {},
        WEEK = {},
        MONTH = {}
    }
    
    -- 获取时间维度配置（支持LightAggregationConfig对象和普通配置表）
    local time_dimensions = self.config.time_dimensions or self.config
    
    -- 为每个时间维度创建空的聚合缓冲区
    for dimension, config in pairs(time_dimensions) do
        if config.enabled then
            self.buffers[dimension] = {
                data = {},
                count = 0,
                last_update = os.time()
            }
        end
    end
end

-- 处理单个数据点
function TimeDimensionAggregator:process_data_point(data_point)
    local timestamp = data_point.timestamp or os.time()
    local value = data_point.value
    local dimensions = data_point.dimensions or {}
    
    -- 计算时间维度键
    local time_keys = self:calculate_dimension_keys(timestamp, self.config)
    
    -- 为每个时间维度更新聚合数据
    for dimension, key in pairs(time_keys) do
        -- 获取时间维度配置（支持LightAggregationConfig对象和普通配置表）
        local time_dimensions = self.config.time_dimensions or self.config
        if time_dimensions[dimension] and time_dimensions[dimension].enabled then
            self:update_dimension_buffer(dimension, key, value, dimensions)
        end
    end
    
    -- 检查是否需要刷新缓冲区
    self:check_flush_buffers()
end

-- 更新维度缓冲区
function TimeDimensionAggregator:update_dimension_buffer(dimension, key, value, dimensions)
    local buffer = self.buffers[dimension]
    
    if not buffer.data[key] then
        buffer.data[key] = {
            values = {},
            dimensions = dimensions,
            timestamp = os.time(),
            count = 0,
            aggregates = {}
        }
    end
    
    local entry = buffer.data[key]
    table.insert(entry.values, value)
    entry.count = entry.count + 1
    entry.timestamp = os.time()
    
    -- 更新聚合统计
    self:update_aggregates(entry, value)
    
    buffer.count = buffer.count + 1
    buffer.last_update = os.time()
    
    -- 检查缓冲区大小
    local batch_size = (self.config.aggregation and self.config.aggregation.batch_size) or 1000
    if buffer.count >= batch_size then
        self:flush_dimension_buffer(dimension)
    end
end

-- 更新聚合统计
function TimeDimensionAggregator:update_aggregates(entry, value)
    local num_value = tonumber(value)
    
    -- 初始化聚合统计
    if not entry.aggregates.count then
        entry.aggregates.count = 0
        entry.aggregates.sum = 0
        entry.aggregates.min = math.huge
        entry.aggregates.max = -math.huge
        entry.aggregates.first = value
        entry.aggregates.last = value
    end
    
    -- 更新统计值
    entry.aggregates.count = entry.aggregates.count + 1
    
    if num_value then
        entry.aggregates.sum = entry.aggregates.sum + num_value
        entry.aggregates.min = math.min(entry.aggregates.min, num_value)
        entry.aggregates.max = math.max(entry.aggregates.max, num_value)
    end
    
    entry.aggregates.last = value
end

-- 检查是否需要刷新缓冲区
function TimeDimensionAggregator:check_flush_buffers()
    local current_time = os.time()
    local flush_interval = (self.config.aggregation and self.config.aggregation.flush_interval) or 60
    
    if current_time - self.last_flush_time >= flush_interval then
        self:flush_all_buffers()
        self.last_flush_time = current_time
    end
end

-- 刷新指定维度缓冲区
function TimeDimensionAggregator:flush_dimension_buffer(dimension)
    local buffer = self.buffers[dimension]
    
    if buffer.count == 0 then
        return
    end
    
    -- 生成聚合结果
    local aggregated_results = {}
    
    for key, entry in pairs(buffer.data) do
        local result = {
            dimension = dimension,
            key = key,
            timestamp = entry.timestamp,
            count = entry.count,
            aggregates = {}
        }
        
        -- 获取聚合函数配置（支持LightAggregationConfig对象和普通配置表）
        local aggregation_functions = self.config.aggregation_functions or {}
        
        -- 计算聚合值
        if aggregation_functions.COUNT and aggregation_functions.COUNT.enabled then
            result.aggregates.count = entry.aggregates.count
        end
        
        if aggregation_functions.SUM and aggregation_functions.SUM.enabled and entry.aggregates.sum then
            result.aggregates.sum = entry.aggregates.sum
        end
        
        if aggregation_functions.AVG and aggregation_functions.AVG.enabled and entry.aggregates.sum then
            result.aggregates.avg = entry.aggregates.sum / entry.aggregates.count
        end
        
        if aggregation_functions.MIN and aggregation_functions.MIN.enabled and entry.aggregates.min ~= math.huge then
            result.aggregates.min = entry.aggregates.min
        end
        
        if aggregation_functions.MAX and aggregation_functions.MAX.enabled and entry.aggregates.max ~= -math.huge then
            result.aggregates.max = entry.aggregates.max
        end
        
        if aggregation_functions.FIRST and aggregation_functions.FIRST.enabled then
            result.aggregates.first = entry.aggregates.first
        end
        
        if aggregation_functions.LAST and aggregation_functions.LAST.enabled then
            result.aggregates.last = entry.aggregates.last
        end
        
        table.insert(aggregated_results, result)
    end
    
    -- 清空缓冲区
    buffer.data = {}
    buffer.count = 0
    
    -- 返回聚合结果（将由调用者处理存储）
    return aggregated_results
end

-- 刷新所有缓冲区
function TimeDimensionAggregator:flush_all_buffers()
    local all_results = {}
    
    for dimension, _ in pairs(self.buffers) do
        local results = self:flush_dimension_buffer(dimension)
        if results and #results > 0 then
            for _, result in ipairs(results) do
                table.insert(all_results, result)
            end
        end
    end
    
    return all_results
end

-- 批量处理数据点
function TimeDimensionAggregator:process_batch(data_points)
    local results = {}
    
    for _, data_point in ipairs(data_points) do
        self:process_data_point(data_point)
    end
    
    -- 强制刷新所有缓冲区
    local aggregated_results = self:flush_all_buffers()
    
    if #aggregated_results > 0 then
        for _, result in ipairs(aggregated_results) do
            table.insert(results, result)
        end
    end
    
    return results
end

-- 查询时间维度聚合数据
function TimeDimensionAggregator:query_aggregated_data(dimension, start_time, end_time, filters)
    -- 这里需要与存储引擎交互来查询数据
    -- 返回格式化的查询结果
    
    local query_result = {
        dimension = dimension,
        start_time = start_time,
        end_time = end_time,
        data = {}
    }
    
    -- 实现查询逻辑（需要与存储引擎集成）
    -- 这里返回模拟数据
    
    return query_result
end

-- 获取维度统计信息
function TimeDimensionAggregator:get_dimension_stats(dimension)
    local buffer = self.buffers[dimension]
    
    if not buffer then
        return nil
    end
    
    return {
        dimension = dimension,
        buffer_size = buffer.count,
        last_update = buffer.last_update,
        active_keys = #buffer.data
    }
end

-- 获取所有维度统计信息
function TimeDimensionAggregator:get_all_stats()
    local stats = {}
    
    for dimension, buffer in pairs(self.buffers) do
        stats[dimension] = {
            buffer_size = buffer.count,
            last_update = buffer.last_update,
            active_keys = #buffer.data
        }
    end
    
    return stats
end

-- 清理过期数据
function TimeDimensionAggregator:cleanup_expired_data(retention_days)
    local current_time = os.time()
    local cutoff_time = current_time - (retention_days * 86400)
    
    local cleaned_count = 0
    
    for dimension, buffer in pairs(self.buffers) do
        for key, entry in pairs(buffer.data) do
            if entry.timestamp < cutoff_time then
                buffer.data[key] = nil
                buffer.count = buffer.count - 1
                cleaned_count = cleaned_count + 1
            end
        end
    end
    
    return cleaned_count
end

-- 导出缓冲区状态
function TimeDimensionAggregator:export_buffer_state()
    local state = {
        last_flush_time = self.last_flush_time,
        buffers = {}
    }
    
    for dimension, buffer in pairs(self.buffers) do
        state.buffers[dimension] = {
            count = buffer.count,
            last_update = buffer.last_update,
            data_size = 0
        }
        
        -- 计算数据大小（估算）
        for _, entry in pairs(buffer.data) do
            state.buffers[dimension].data_size = state.buffers[dimension].data_size + 
                                               entry.count * 100  -- 估算每个值100字节
        end
    end
    
    return state
end

-- 导入缓冲区状态
function TimeDimensionAggregator:import_buffer_state(state)
    if state.last_flush_time then
        self.last_flush_time = state.last_flush_time
    end
    
    -- 注意：这里只恢复元数据，不恢复实际数据
    -- 实际数据应该在存储引擎中持久化
end

return TimeDimensionAggregator