-- TSDB存储引擎插件适配器
-- 将插件框架集成到TSDB存储引擎中

local plugin_manager = require "lua.rowkey_value_plugin"

local PluginAdapter = {}
PluginAdapter.__index = PluginAdapter

function PluginAdapter:new(storage_engine)
    local obj = setmetatable({}, PluginAdapter)
    obj.storage_engine = storage_engine
    obj.plugin_manager = plugin_manager.default_manager
    obj.current_plugin = nil
    obj.plugin_stats = {}
    return obj
end

function PluginAdapter:set_plugin(plugin_name)
    local plugin = self.plugin_manager:get_plugin(plugin_name)
    if plugin then
        self.current_plugin = plugin
        self.plugin_stats[plugin_name] = self.plugin_stats[plugin_name] or {
            encode_count = 0,
            decode_count = 0,
            total_encode_time = 0,
            total_decode_time = 0
        }
        return true
    end
    return false, "插件不存在: " .. plugin_name
end

function PluginAdapter:get_current_plugin()
    if not self.current_plugin then
        self.current_plugin = self.plugin_manager:get_default_plugin()
    end
    return self.current_plugin
end

-- 包装写入操作
function PluginAdapter:write_data(table_name, rowkey, value, timestamp, plugin_name)
    local plugin = plugin_name and self.plugin_manager:get_plugin(plugin_name) or self:get_current_plugin()
    if not plugin then
        return false, "没有可用的插件"
    end
    
    local start_time = os.clock()
    
    -- 使用插件编码RowKey和Value
    local encoded_rowkey, qualifier = plugin:encode_rowkey(rowkey, timestamp)
    local encoded_value = plugin:encode_value(value)
    
    local encode_time = os.clock() - start_time
    
    -- 更新统计信息
    local stats = self.plugin_stats[plugin:get_name()]
    if stats then
        stats.encode_count = stats.encode_count + 1
        stats.total_encode_time = stats.total_encode_time + encode_time
    end
    
    -- 调用存储引擎写入
    local success, error_msg = self.storage_engine:write(table_name, encoded_rowkey, encoded_value, timestamp, qualifier)
    
    return success, error_msg, {
        plugin = plugin:get_name(),
        encode_time = encode_time,
        key_size = #encoded_rowkey,
        value_size = #encoded_value
    }
end

-- 包装读取操作
function PluginAdapter:read_data(table_name, rowkey, timestamp, plugin_name)
    local plugin = plugin_name and self.plugin_manager:get_plugin(plugin_name) or self:get_current_plugin()
    if not plugin then
        return nil, "没有可用的插件"
    end
    
    local start_time = os.clock()
    
    -- 使用插件编码RowKey进行查询
    local encoded_rowkey = plugin:encode_rowkey(rowkey, timestamp)
    
    -- 调用存储引擎读取
    local encoded_value = self.storage_engine:read(table_name, encoded_rowkey, timestamp)
    if not encoded_value then
        return nil, "数据不存在"
    end
    
    -- 使用插件解码Value
    local decoded_value = plugin:decode_value(encoded_value)
    
    local decode_time = os.clock() - start_time
    
    -- 更新统计信息
    local stats = self.plugin_stats[plugin:get_name()]
    if stats then
        stats.decode_count = stats.decode_count + 1
        stats.total_decode_time = stats.total_decode_time + decode_time
    end
    
    return decoded_value, nil, {
        plugin = plugin:get_name(),
        decode_time = decode_time,
        value_size = #encoded_value
    }
end

-- 包装范围查询操作
function PluginAdapter:scan_data(table_name, start_rowkey, end_rowkey, plugin_name)
    local plugin = plugin_name and self.plugin_manager:get_plugin(plugin_name) or self:get_current_plugin()
    if not plugin then
        return {}, "没有可用的插件"
    end
    
    local start_time = os.clock()
    local results = {}
    
    -- 编码查询范围
    local encoded_start_key = plugin:encode_rowkey(start_rowkey)
    local encoded_end_key = plugin:encode_rowkey(end_rowkey)
    
    -- 调用存储引擎范围查询
    local encoded_results = self.storage_engine:scan_range(table_name, encoded_start_key, encoded_end_key)
    
    -- 解码结果
    for _, item in ipairs(encoded_results) do
        local decoded_key = plugin:decode_rowkey(item.rowkey)
        local decoded_value = plugin:decode_value(item.value)
        table.insert(results, {
            key = decoded_key,
            value = decoded_value,
            timestamp = item.timestamp
        })
    end
    
    local scan_time = os.clock() - start_time
    
    return results, nil, {
        plugin = plugin:get_name(),
        scan_time = scan_time,
        result_count = #results
    }
end

-- 获取插件统计信息
function PluginAdapter:get_plugin_stats(plugin_name)
    if plugin_name then
        return self.plugin_stats[plugin_name]
    end
    return self.plugin_stats
end

-- 重置插件统计信息
function PluginAdapter:reset_stats(plugin_name)
    if plugin_name then
        self.plugin_stats[plugin_name] = {
            encode_count = 0,
            decode_count = 0,
            total_encode_time = 0,
            total_decode_time = 0
        }
    else
        for name, _ in pairs(self.plugin_stats) do
            self.plugin_stats[name] = {
                encode_count = 0,
                decode_count = 0,
                total_encode_time = 0,
                total_decode_time = 0
            }
        end
    end
end

-- 性能基准测试
function PluginAdapter:benchmark_plugin(plugin_name, test_data)
    local plugin = self.plugin_manager:get_plugin(plugin_name)
    if not plugin then
        return nil, "插件不存在: " .. plugin_name
    end
    
    local benchmark_results = {
        plugin_name = plugin_name,
        encode_performance = {},
        decode_performance = {},
        memory_usage = {},
        test_timestamp = os.time()
    }
    
    -- 重置统计
    self:reset_stats(plugin_name)
    
    -- 编码性能测试
    local encode_start = os.clock()
    local encoded_data = {}
    
    for i, data in ipairs(test_data) do
        local key, value = data.key, data.value
        local encoded_key, _ = plugin:encode_rowkey(key.stock_code, key.timestamp, key.market)
        local encoded_val = plugin:encode_value(value)
        
        table.insert(encoded_data, {
            key = encoded_key,
            value = encoded_val,
            original_key = key,
            original_value = value
        })
    end
    
    local encode_total_time = os.clock() - encode_start
    benchmark_results.encode_performance = {
        total_time = encode_total_time,
        avg_time_per_record = encode_total_time / #test_data,
        records_per_second = #test_data / encode_total_time,
        total_data_size = 0
    }
    
    -- 计算总数据大小
    for _, item in ipairs(encoded_data) do
        benchmark_results.encode_performance.total_data_size = 
            benchmark_results.encode_performance.total_data_size + #item.key + #item.value
    end
    
    -- 解码性能测试
    local decode_start = os.clock()
    local decoded_count = 0
    
    for _, item in ipairs(encoded_data) do
        local decoded_key = plugin:decode_rowkey(item.key)
        local decoded_value = plugin:decode_value(item.value)
        decoded_count = decoded_count + 1
    end
    
    local decode_total_time = os.clock() - decode_start
    benchmark_results.decode_performance = {
        total_time = decode_total_time,
        avg_time_per_record = decode_total_time / decoded_count,
        records_per_second = decoded_count / decode_total_time
    }
    
    -- 内存使用统计（简化）
    benchmark_results.memory_usage = {
        estimated_encode_buffer = benchmark_results.encode_performance.total_data_size,
        estimated_decode_buffer = benchmark_results.encode_performance.total_data_size,
        efficiency_ratio = #test_data / (benchmark_results.encode_performance.total_data_size / 1024)  -- 记录数/KB
    }
    
    -- 获取插件统计
    benchmark_results.plugin_stats = self:get_plugin_stats(plugin_name)
    
    return benchmark_results
end

-- 对比多个插件的性能
function PluginAdapter:compare_plugins(plugin_names, test_data)
    local comparison_results = {
        timestamp = os.time(),
        test_data_size = #test_data,
        plugins = {},
        summary = {}
    }
    
    for _, plugin_name in ipairs(plugin_names) do
        local benchmark_result, error_msg = self:benchmark_plugin(plugin_name, test_data)
        if benchmark_result then
            comparison_results.plugins[plugin_name] = benchmark_result
        else
            comparison_results.plugins[plugin_name] = {error = error_msg}
        end
    end
    
    -- 生成对比摘要
    comparison_results.summary = self:generate_comparison_summary(comparison_results.plugins)
    
    return comparison_results
end

-- 生成对比摘要
function PluginAdapter:generate_comparison_summary(plugin_results)
    local summary = {
        best_encode_performance = nil,
        best_decode_performance = nil,
        most_efficient = nil,
        recommendations = {}
    }
    
    local best_encode_speed = 0
    local best_decode_speed = 0
    local best_efficiency = 0
    
    for plugin_name, results in pairs(plugin_results) do
        if not results.error then
            -- 最佳编码性能
            local encode_speed = results.encode_performance.records_per_second
            if encode_speed > best_encode_speed then
                best_encode_speed = encode_speed
                summary.best_encode_performance = plugin_name
            end
            
            -- 最佳解码性能
            local decode_speed = results.decode_performance.records_per_second
            if decode_speed > best_decode_speed then
                best_decode_speed = decode_speed
                summary.best_decode_performance = plugin_name
            end
            
            -- 最高效率
            local efficiency = results.memory_usage.efficiency_ratio
            if efficiency > best_efficiency then
                best_efficiency = efficiency
                summary.most_efficient = plugin_name
            end
        end
    end
    
    -- 生成建议
    if summary.best_encode_performance then
        table.insert(summary.recommendations, 
            string.format("编码性能最佳: %s (%.0f 记录/秒)", 
                summary.best_encode_performance, best_encode_speed))
    end
    
    if summary.best_decode_performance then
        table.insert(summary.recommendations,
            string.format("解码性能最佳: %s (%.0f 记录/秒)",
                summary.best_decode_performance, best_decode_speed))
    end
    
    if summary.most_efficient then
        table.insert(summary.recommendations,
            string.format("存储效率最高: %s (%.2f 记录/KB)",
                summary.most_efficient, best_efficiency))
    end
    
    return summary
end

return PluginAdapter