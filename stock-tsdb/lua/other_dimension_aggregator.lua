-- 其他维度汇总计算模块
-- 实现股票代码、市场、行业、地区等维度的汇总计算

local OtherDimensionAggregator = {}
OtherDimensionAggregator.__index = OtherDimensionAggregator

local string = require "string"
local table = require "table"

-- 前缀分隔符压缩工具
local PrefixCompressor = {}

-- 构建前缀分隔符键
function PrefixCompressor:build_key(prefix, dimensions, separator)
    local key_parts = {prefix}
    
    for _, field in ipairs(dimensions.fields) do
        local value = dimensions.values[field]
        if value then
            table.insert(key_parts, tostring(value))
        end
    end
    
    return table.concat(key_parts, separator)
end

-- 解析前缀分隔符键
function PrefixCompressor:parse_key(key, separator)
    local parts = {}
    for part in string.gmatch(key, "([^" .. separator .. "]+)") do
        table.insert(parts, part)
    end
    
    if #parts < 2 then
        return nil
    end
    
    return {
        prefix = parts[1],
        values = {table.unpack(parts, 2)}
    }
end

-- 压缩维度值
function PrefixCompressor:compress_dimensions(dimensions, config)
    local compressed = {}
    
    for field, value in pairs(dimensions) do
        if type(value) == "string" and string.len(value) > config.min_prefix_length then
            -- 提取前缀
            local prefix = string.sub(value, 1, config.max_prefix_length)
            compressed[field] = {
                original = value,
                compressed = prefix,
                is_compressed = true
            }
        else
            compressed[field] = {
                original = value,
                compressed = value,
                is_compressed = false
            }
        end
    end
    
    return compressed
end

-- 解压缩维度值
function PrefixCompressor:decompress_dimensions(compressed_dimensions)
    local dimensions = {}
    
    for field, comp_data in pairs(compressed_dimensions) do
        dimensions[field] = comp_data.original
    end
    
    return dimensions
end

-- 创建其他维度聚合器
function OtherDimensionAggregator:new(config)
    local obj = setmetatable({}, OtherDimensionAggregator)
    
    -- 直接使用传入的配置对象（可能是LightAggregationConfig或普通配置表）
    obj.config = config or {}
    
    obj.buffers = {}  -- 其他维度缓冲区
    obj.compressor = PrefixCompressor
    obj.last_flush_time = os.time()
    
    -- 初始化缓冲区
    obj:init_buffers()
    
    return obj
end

-- 初始化缓冲区
function OtherDimensionAggregator:init_buffers()
    self.buffers = {}
    
    -- 为每个启用的其他维度创建缓冲区
    local other_dimensions = self.config.other_dimensions or {}
    for dimension_name, dimension_config in pairs(other_dimensions) do
        if dimension_config.enabled then
            self.buffers[dimension_name] = {
                data = {},
                count = 0,
                last_update = os.time(),
                compression_stats = {
                    total_compressed = 0,
                    total_saved = 0,
                    compression_ratio = 0
                }
            }
        end
    end
end

-- 处理单个数据点
function OtherDimensionAggregator:process_data_point(data_point)
    local timestamp = data_point.timestamp or os.time()
    local value = data_point.value
    local dimensions = data_point.dimensions or {}
    
    -- 为每个启用的其他维度更新聚合数据
    local other_dimensions = self.config.other_dimensions or {}
    for dimension_name, dimension_config in pairs(other_dimensions) do
        if dimension_config.enabled then
            self:update_dimension_buffer(dimension_name, dimension_config, timestamp, value, dimensions)
        end
    end
    
    -- 检查是否需要刷新缓冲区
    self:check_flush_buffers()
end

-- 更新维度缓冲区
function OtherDimensionAggregator:update_dimension_buffer(dimension_name, dimension_config, timestamp, value, dimensions)
    local buffer = self.buffers[dimension_name]
    
    -- 提取该维度相关的字段值
    local dimension_values = {}
    for _, field in ipairs(dimension_config.fields) do
        dimension_values[field] = dimensions[field]
    end
    
    -- 构建维度键
    local key = self.compressor:build_key(dimension_config.prefix, {
        fields = dimension_config.fields,
        values = dimension_values
    }, dimension_config.separator)
    
    if not buffer.data[key] then
        buffer.data[key] = {
            values = {},
            dimensions = dimension_values,
            timestamp = timestamp,
            count = 0,
            aggregates = {},
            compression_data = {}
        }
    end
    
    local entry = buffer.data[key]
    table.insert(entry.values, value)
    entry.count = entry.count + 1
    entry.timestamp = timestamp
    
    -- 更新聚合统计
    self:update_aggregates(entry, value)
    
    -- 应用压缩（如果启用）
    local compression_strategies = self.config.compression_strategies or {}
    if compression_strategies.PREFIX and compression_strategies.PREFIX.enabled then
        self:apply_compression(entry, dimension_values, dimension_name)
    end
    
    buffer.count = buffer.count + 1
    buffer.last_update = os.time()
    
    -- 检查缓冲区大小
    local batch_size = (self.config.aggregation and self.config.aggregation.batch_size) or 1000
    if buffer.count >= batch_size then
        self:flush_dimension_buffer(dimension_name)
    end
end

-- 更新聚合统计
function OtherDimensionAggregator:update_aggregates(entry, value)
    local num_value = tonumber(value)
    
    -- 初始化聚合统计
    if not entry.aggregates then
        entry.aggregates = {}
    end
    
    if not entry.aggregates.count then
        entry.aggregates.count = 0
        entry.aggregates.sum = 0
        entry.aggregates.min = math.huge
        entry.aggregates.max = -math.huge
        entry.aggregates.first = value
        entry.aggregates.last = value
        entry.aggregates.distinct_values = {}
    end
    
    -- 更新统计值
    entry.aggregates.count = entry.aggregates.count + 1
    
    if num_value then
        entry.aggregates.sum = entry.aggregates.sum + num_value
        entry.aggregates.min = math.min(entry.aggregates.min, num_value)
        entry.aggregates.max = math.max(entry.aggregates.max, num_value)
    end
    
    entry.aggregates.last = value
    
    -- 更新唯一值统计
    if not entry.aggregates.distinct_values then
        entry.aggregates.distinct_values = {}
    end
    
    -- 确保value不为nil
    if value == nil then
        value = "nil_value"
    end
    
    if not entry.aggregates.distinct_values[value] then
        entry.aggregates.distinct_values[value] = 0
    end
    
    -- 确保当前值不为nil
    local current_count = entry.aggregates.distinct_values[value] or 0
    entry.aggregates.distinct_values[value] = current_count + 1
end

-- 应用压缩
function OtherDimensionAggregator:apply_compression(entry, dimensions, dimension_name)
    local compression_strategies = self.config.compression_strategies or {}
    local compression_config = compression_strategies.PREFIX and compression_strategies.PREFIX.config or {}
    
    entry.compression_data = self.compressor:compress_dimensions(dimensions, compression_config)
    
    -- 更新压缩统计
    local buffer = self.buffers[dimension_name]
    if not buffer then
        -- 如果缓冲区不存在，创建一个新的缓冲区
        self.buffers[dimension_name] = {
            data = {},
            count = 0,
            last_update = os.time(),
            compression_stats = {
                total_compressed = 0,
                total_saved = 0,
                compression_ratio = 0
            }
        }
        buffer = self.buffers[dimension_name]
    end
    
    for field, comp_data in pairs(entry.compression_data) do
        if comp_data.is_compressed then
            local original_size = string.len(comp_data.original)
            local compressed_size = string.len(comp_data.compressed)
            local saved = original_size - compressed_size
            
            buffer.compression_stats.total_compressed = buffer.compression_stats.total_compressed + 1
            buffer.compression_stats.total_saved = buffer.compression_stats.total_saved + saved
        end
    end
    
    if buffer.compression_stats.total_compressed > 0 then
        buffer.compression_stats.compression_ratio = 
            buffer.compression_stats.total_saved / (buffer.compression_stats.total_compressed * 10)  -- 估算
    end
end

-- 检查是否需要刷新缓冲区
function OtherDimensionAggregator:check_flush_buffers()
    local current_time = os.time()
    local flush_interval = (self.config.aggregation and self.config.aggregation.flush_interval) or 60
    
    if current_time - self.last_flush_time >= flush_interval then
        self:flush_all_buffers()
        self.last_flush_time = current_time
    end
end

-- 刷新指定维度缓冲区
function OtherDimensionAggregator:flush_dimension_buffer(dimension_name)
    local buffer = self.buffers[dimension_name]
    
    if buffer.count == 0 then
        return nil
    end
    
    -- 生成聚合结果
    local aggregated_results = {}
    
    for key, entry in pairs(buffer.data) do
        local result = {
            dimension = dimension_name,
            key = key,
            timestamp = entry.timestamp,
            count = entry.count,
            aggregates = {},
            dimensions = entry.dimensions,
            compression_data = entry.compression_data
        }
        
        -- 计算聚合值
        local aggregation_functions = self.config.aggregation_functions or {}
        
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
        
        -- 计算唯一值统计
        if entry.aggregates.distinct_values then
            result.aggregates.distinct_count = 0
            for _ in pairs(entry.aggregates.distinct_values) do
                result.aggregates.distinct_count = result.aggregates.distinct_count + 1
            end
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
function OtherDimensionAggregator:flush_all_buffers()
    local all_results = {}
    
    for dimension_name, _ in pairs(self.buffers) do
        local results = self:flush_dimension_buffer(dimension_name)
        if results and #results > 0 then
            for _, result in ipairs(results) do
                table.insert(all_results, result)
            end
        end
    end
    
    return all_results
end

-- 批量处理数据点
function OtherDimensionAggregator:process_batch(data_points)
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

-- 查询其他维度聚合数据
function OtherDimensionAggregator:query_aggregated_data(dimension_name, filters)
    -- 这里需要与存储引擎交互来查询数据
    -- 返回格式化的查询结果
    
    local query_result = {
        dimension = dimension_name,
        filters = filters,
        data = {}
    }
    
    -- 实现查询逻辑（需要与存储引擎集成）
    -- 这里返回模拟数据
    
    return query_result
end

-- 获取维度统计信息
function OtherDimensionAggregator:get_dimension_stats(dimension_name)
    local buffer = self.buffers[dimension_name]
    
    if not buffer then
        return nil
    end
    
    return {
        dimension = dimension_name,
        buffer_size = buffer.count,
        last_update = buffer.last_update,
        active_keys = #buffer.data,
        compression_stats = buffer.compression_stats
    }
end

-- 获取所有维度统计信息
function OtherDimensionAggregator:get_all_stats()
    local stats = {}
    
    for dimension_name, buffer in pairs(self.buffers) do
        stats[dimension_name] = {
            buffer_size = buffer.count,
            last_update = buffer.last_update,
            active_keys = #buffer.data,
            compression_stats = buffer.compression_stats
        }
    end
    
    return stats
end

-- 清理过期数据
function OtherDimensionAggregator:cleanup_expired_data(retention_days)
    local current_time = os.time()
    local cutoff_time = current_time - (retention_days * 86400)
    
    local cleaned_count = 0
    
    for dimension_name, buffer in pairs(self.buffers) do
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
function OtherDimensionAggregator:export_buffer_state()
    local state = {
        last_flush_time = self.last_flush_time,
        buffers = {}
    }
    
    for dimension_name, buffer in pairs(self.buffers) do
        state.buffers[dimension_name] = {
            count = buffer.count,
            last_update = buffer.last_update,
            data_size = 0,
            compression_stats = buffer.compression_stats
        }
        
        -- 计算数据大小（估算）
        for _, entry in pairs(buffer.data) do
            state.buffers[dimension_name].data_size = state.buffers[dimension_name].data_size + 
                                                   entry.count * 100  -- 估算每个值100字节
        end
    end
    
    return state
end

-- 导入缓冲区状态
function OtherDimensionAggregator:import_buffer_state(state)
    if state.last_flush_time then
        self.last_flush_time = state.last_flush_time
    end
    
    -- 注意：这里只恢复元数据，不恢复实际数据
    -- 实际数据应该在存储引擎中持久化
end

-- 测试压缩效果
function OtherDimensionAggregator:test_compression_effectiveness(sample_data)
    local results = {}
    
    local other_dimensions = self.config.other_dimensions or {}
    for dimension_name, dimension_config in pairs(other_dimensions) do
        if dimension_config.enabled then
            local test_result = {
                dimension = dimension_name,
                original_size = 0,
                compressed_size = 0,
                compression_ratio = 0,
                samples_tested = 0
            }
            
            for _, data_point in ipairs(sample_data) do
                local dimensions = data_point.dimensions or {}
                local dimension_values = {}
                
                for _, field in ipairs(dimension_config.fields) do
                    dimension_values[field] = dimensions[field]
                end
                
                local compressed = self.compressor:compress_dimensions(dimension_values, 
                    self.config.compression_strategies.PREFIX.config)
                
                for field, comp_data in pairs(compressed) do
                    test_result.original_size = test_result.original_size + string.len(comp_data.original)
                    test_result.compressed_size = test_result.compressed_size + string.len(comp_data.compressed)
                    test_result.samples_tested = test_result.samples_tested + 1
                end
            end
            
            if test_result.original_size > 0 then
                test_result.compression_ratio = (test_result.original_size - test_result.compressed_size) / test_result.original_size
            end
            
            results[dimension_name] = test_result
        end
    end
    
    return results
end

return OtherDimensionAggregator