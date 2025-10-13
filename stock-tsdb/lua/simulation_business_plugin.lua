-- 模拟业务测试插件
-- 用于测试和对比各种业务场景的编码性能

local SimulationBusinessPlugin = {}
SimulationBusinessPlugin.__index = SimulationBusinessPlugin

function SimulationBusinessPlugin:new()
    local obj = setmetatable({}, SimulationBusinessPlugin)
    obj.name = "simulation_business"
    obj.version = "1.0.0"
    obj.description = "模拟业务测试插件，支持多种业务场景的编码测试"
    
    -- 业务场景定义
    obj.business_scenarios = {
        ECOMMERCE = "ecommerce",      -- 电商业务
        FINANCE = "finance",          -- 金融业务
        IOT = "iot",                  -- 物联网业务
        LOGISTICS = "logistics",      -- 物流业务
        SOCIAL = "social"             -- 社交业务
    }
    
    -- 数据复杂度级别
    obj.complexity_levels = {
        SIMPLE = "simple",           -- 简单数据
        MEDIUM = "medium",           -- 中等数据
        COMPLEX = "complex"          -- 复杂数据
    }
    
    -- 缓存优化
    obj.simulation_cache = {}
    obj.cache_size = 2000
    
    return obj
end

function SimulationBusinessPlugin:get_name()
    return self.name
end

function SimulationBusinessPlugin:get_version()
    return self.version
end

function SimulationBusinessPlugin:get_description()
    return self.description
end

-- 编码模拟业务RowKey
-- 格式: sim|scenario|entity_id|timestamp|complexity
function SimulationBusinessPlugin:encode_rowkey(scenario, entity_id, timestamp, complexity)
    scenario = scenario or self.business_scenarios.ECOMMERCE
    complexity = complexity or self.complexity_levels.MEDIUM
    
    -- 时间戳处理（按业务场景选择分块策略）
    local block_size = 3600  -- 默认按小时分块
    if scenario == self.business_scenarios.IOT then
        block_size = 300  -- IOT场景按5分钟分块
    elseif scenario == self.business_scenarios.FINANCE then
        block_size = 60   -- 金融场景按分钟分块
    end
    
    local timestamp_block = math.floor(timestamp / block_size) * block_size
    
    local key_parts = {
        "sim",
        scenario,
        tostring(entity_id),
        tostring(timestamp_block),
        complexity
    }
    
    local qualifier = string.format("%06x", timestamp - timestamp_block)
    
    return table.concat(key_parts, "|"), qualifier
end

-- 解码模拟业务RowKey
function SimulationBusinessPlugin:decode_rowkey(rowkey)
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 5 and parts[1] == "sim" then
        local timestamp_block = tonumber(parts[4])
        
        return {
            type = "simulation",
            scenario = parts[2],
            entity_id = parts[3],  -- 保持为字符串类型
            timestamp = timestamp_block,
            complexity = parts[5]
        }
    end
    
    return {type = "unknown"}
end

-- 编码模拟业务Value（根据场景和复杂度生成不同结构的数据）
function SimulationBusinessPlugin:encode_value(simulation_data)
    local scenario = simulation_data.scenario or self.business_scenarios.ECOMMERCE
    local complexity = simulation_data.complexity or self.complexity_levels.MEDIUM
    
    local value_parts = {}
    
    -- 基础字段
    local base_fields = {
        "scenario", "entity_id", "timestamp", "complexity", "data_type"
    }
    
    for i, field in ipairs(base_fields) do
        local value = simulation_data[field]
        if value ~= nil then
            if i > 1 then
                value_parts[#value_parts + 1] = ","
            end
            if type(value) == "number" then
                value_parts[#value_parts + 1] = string.format('"%s":%d', field, value)
            else
                value_parts[#value_parts + 1] = string.format('"%s":"%s"', field, value)
            end
        end
    end
    
    -- 根据业务场景和复杂度生成不同的数据字段
    if scenario == self.business_scenarios.ECOMMERCE then
        value_parts[#value_parts + 1] = self:_generate_ecommerce_data(complexity, simulation_data)
    elseif scenario == self.business_scenarios.FINANCE then
        value_parts[#value_parts + 1] = self:_generate_finance_data(complexity, simulation_data)
    elseif scenario == self.business_scenarios.IOT then
        value_parts[#value_parts + 1] = self:_generate_iot_data(complexity, simulation_data)
    elseif scenario == self.business_scenarios.LOGISTICS then
        value_parts[#value_parts + 1] = self:_generate_logistics_data(complexity, simulation_data)
    elseif scenario == self.business_scenarios.SOCIAL then
        value_parts[#value_parts + 1] = self:_generate_social_data(complexity, simulation_data)
    end
    
    -- 性能指标（用于测试对比）
    value_parts[#value_parts + 1] = string.format(
        ',"performance_metrics":{"data_size":%d,"field_count":%d,"complexity_score":%.2f}',
        #table.concat(value_parts),
        self:_count_fields(value_parts),
        self:_calculate_complexity_score(complexity)
    )
    
    return "{" .. table.concat(value_parts) .. "}"
end

-- 解码模拟业务Value
function SimulationBusinessPlugin:decode_value(value)
    local simulation_data = {}
    
    -- 移除首尾花括号
    local content = string.sub(value, 2, -2)
    
    -- 解析JSON格式
    local pos = 1
    while pos <= #content do
        -- 查找字段名
        local field_start, field_end, field = string.find(content, '"([^"]+)":', pos)
        if not field_start then break end
        
        -- 查找值
        pos = field_end + 1
        local value_start, value_end, val
        
        -- 处理对象字段
        if string.sub(content, pos, pos) == "{" then
            local obj_end = string.find(content, "}", pos)
            if obj_end then
                local obj_content = string.sub(content, pos + 1, obj_end - 1)
                simulation_data[field] = self:_parse_object(obj_content)
                pos = obj_end + 2
            else
                pos = pos + 1
            end
        -- 处理数组字段
        elseif string.sub(content, pos, pos) == "[" then
            local array_end = string.find(content, "]", pos)
            if array_end then
                local array_content = string.sub(content, pos + 1, array_end - 1)
                simulation_data[field] = self:_parse_array(array_content)
                pos = array_end + 2
            else
                pos = pos + 1
            end
        -- 处理字符串值
        elseif string.sub(content, pos, pos) == '"' then
            value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
            if value_start then
                simulation_data[field] = val
                pos = value_end + 2
            else
                pos = pos + 1
            end
        -- 处理数字值
        else
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start then
                simulation_data[field] = tonumber(val)
                pos = value_end + 1
            else
                pos = pos + 1
            end
        end
        
        -- 跳过逗号
        if string.sub(content, pos, pos) == ',' then
            pos = pos + 1
        end
    end
    
    return simulation_data
end

-- 生成电商业务数据
function SimulationBusinessPlugin:_generate_ecommerce_data(complexity, data)
    local ecommerce_parts = {}
    
    if complexity == self.complexity_levels.SIMPLE then
        ecommerce_parts[#ecommerce_parts + 1] = ',"ecommerce_data":{"order_amount":%.2f,"product_count":%d}'
        return string.format(table.concat(ecommerce_parts), data.order_amount or 100.0, data.product_count or 1)
    elseif complexity == self.complexity_levels.MEDIUM then
        ecommerce_parts[#ecommerce_parts + 1] = ',"ecommerce_data":{"order_amount":%.2f,"product_count":%d,"user_level":"%s","payment_method":"%s"}'
        return string.format(table.concat(ecommerce_parts), 
            data.order_amount or 100.0, data.product_count or 1, 
            data.user_level or "normal", data.payment_method or "alipay")
    else
        ecommerce_parts[#ecommerce_parts + 1] = ',"ecommerce_data":{"order_amount":%.2f,"product_count":%d,"user_level":"%s","payment_method":"%s","shipping_address":"%s","discount_rate":%.2f}'
        return string.format(table.concat(ecommerce_parts), 
            data.order_amount or 100.0, data.product_count or 1, 
            data.user_level or "normal", data.payment_method or "alipay",
            data.shipping_address or "Beijing", data.discount_rate or 0.1)
    end
end

-- 生成金融业务数据
function SimulationBusinessPlugin:_generate_finance_data(complexity, data)
    local finance_parts = {}
    
    if complexity == self.complexity_levels.SIMPLE then
        finance_parts[#finance_parts + 1] = ',"finance_data":{"price":%.4f,"volume":%d}'
        return string.format(table.concat(finance_parts), data.price or 100.0, data.volume or 1000)
    elseif complexity == self.complexity_levels.MEDIUM then
        finance_parts[#finance_parts + 1] = ',"finance_data":{"price":%.4f,"volume":%d,"market":"%s","symbol":"%s"}'
        return string.format(table.concat(finance_parts), 
            data.price or 100.0, data.volume or 1000, 
            data.market or "SH", data.symbol or "000001")
    else
        finance_parts[#finance_parts + 1] = ',"finance_data":{"price":%.4f,"volume":%d,"market":"%s","symbol":"%s","open":%.4f,"high":%.4f,"low":%.4f,"amount":%.2f}'
        return string.format(table.concat(finance_parts), 
            data.price or 100.0, data.volume or 1000, 
            data.market or "SH", data.symbol or "000001",
            data.open or 99.5, data.high or 101.0, data.low or 99.0, data.amount or 1000000.0)
    end
end

-- 生成物联网业务数据
function SimulationBusinessPlugin:_generate_iot_data(complexity, data)
    local iot_parts = {}
    
    if complexity == self.complexity_levels.SIMPLE then
        iot_parts[#iot_parts + 1] = ',"iot_data":{"value":%.2f,"quality":%d}'
        return string.format(table.concat(iot_parts), data.value or 25.5, data.quality or 95)
    elseif complexity == self.complexity_levels.MEDIUM then
        iot_parts[#iot_parts + 1] = ',"iot_data":{"value":%.2f,"quality":%d,"sensor_type":"%s","battery_level":%.2f}'
        return string.format(table.concat(iot_parts), 
            data.value or 25.5, data.quality or 95, 
            data.sensor_type or "temperature", data.battery_level or 85.0)
    else
        iot_parts[#iot_parts + 1] = ',"iot_data":{"value":%.2f,"quality":%d,"sensor_type":"%s","battery_level":%.2f,"location":"%s","timestamp_offset":%d}'
        return string.format(table.concat(iot_parts), 
            data.value or 25.5, data.quality or 95, 
            data.sensor_type or "temperature", data.battery_level or 85.0,
            data.location or "room_101", data.timestamp_offset or 0)
    end
end

-- 生成物流业务数据
function SimulationBusinessPlugin:_generate_logistics_data(complexity, data)
    local logistics_parts = {}
    
    if complexity == self.complexity_levels.SIMPLE then
        logistics_parts[#logistics_parts + 1] = ',"logistics_data":{"package_status":"%s","location":"%s"}'
        return string.format(table.concat(logistics_parts), data.package_status or "in_transit", data.location or "warehouse")
    elseif complexity == self.complexity_levels.MEDIUM then
        logistics_parts[#logistics_parts + 1] = ',"logistics_data":{"package_status":"%s","location":"%s","estimated_delivery":"%s","weight":%.2f}'
        return string.format(table.concat(logistics_parts), 
            data.package_status or "in_transit", data.location or "warehouse", 
            data.estimated_delivery or "2024-01-01", data.weight or 2.5)
    else
        logistics_parts[#logistics_parts + 1] = ',"logistics_data":{"package_status":"%s","location":"%s","estimated_delivery":"%s","weight":%.2f,"recipient":"%s","shipping_cost":%.2f}'
        return string.format(table.concat(logistics_parts), 
            data.package_status or "in_transit", data.location or "warehouse", 
            data.estimated_delivery or "2024-01-01", data.weight or 2.5,
            data.recipient or "John Doe", data.shipping_cost or 15.0)
    end
end

-- 生成社交业务数据
function SimulationBusinessPlugin:_generate_social_data(complexity, data)
    local social_parts = {}
    
    if complexity == self.complexity_levels.SIMPLE then
        social_parts[#social_parts + 1] = ',"social_data":{"post_type":"%s","like_count":%d}'
        return string.format(table.concat(social_parts), data.post_type or "text", data.like_count or 10)
    elseif complexity == self.complexity_levels.MEDIUM then
        social_parts[#social_parts + 1] = ',"social_data":{"post_type":"%s","like_count":%d,"comment_count":%d,"share_count":%d}'
        return string.format(table.concat(social_parts), 
            data.post_type or "text", data.like_count or 10, 
            data.comment_count or 5, data.share_count or 2)
    else
        social_parts[#social_parts + 1] = ',"social_data":{"post_type":"%s","like_count":%d,"comment_count":%d,"share_count":%d,"author":"%s","tags":"%s"}'
        return string.format(table.concat(social_parts), 
            data.post_type or "text", data.like_count or 10, 
            data.comment_count or 5, data.share_count or 2,
            data.author or "user123", data.tags or "tech,programming")
    end
end

-- 辅助方法：解析对象
function SimulationBusinessPlugin:_parse_object(content)
    local obj = {}
    local pos = 1
    while pos <= #content do
        local field_start, field_end, field = string.find(content, '"([^"]+)":', pos)
        if not field_start then break end
        
        pos = field_end + 1
        local value_start, value_end, val
        
        if string.sub(content, pos, pos) == '"' then
            value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
            if value_start then
                obj[field] = val
                pos = value_end + 2
            end
        else
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start then
                obj[field] = tonumber(val)
                pos = value_end + 1
            end
        end
        
        if string.sub(content, pos, pos) == ',' then
            pos = pos + 1
        end
    end
    return obj
end

-- 辅助方法：解析数组
function SimulationBusinessPlugin:_parse_array(content)
    local array = {}
    local pos = 1
    local index = 1
    
    while pos <= #content do
        local value_start, value_end, val
        
        if string.sub(content, pos, pos) == '{' then
            local obj_end = string.find(content, "}", pos)
            if obj_end then
                local obj_content = string.sub(content, pos + 1, obj_end - 1)
                array[index] = self:_parse_object(obj_content)
                pos = obj_end + 2
                index = index + 1
            else
                pos = pos + 1
            end
        else
            pos = pos + 1
        end
        
        if string.sub(content, pos, pos) == ',' then
            pos = pos + 1
        end
    end
    
    return array
end

-- 辅助方法：计算字段数量
function SimulationBusinessPlugin:_count_fields(value_parts)
    local count = 0
    for _, part in ipairs(value_parts) do
        local field_count = select(2, string.gsub(part, '"[^"]+":', ""))
        count = count + field_count
    end
    return count
end

-- 辅助方法：计算复杂度分数
function SimulationBusinessPlugin:_calculate_complexity_score(complexity)
    if complexity == self.complexity_levels.SIMPLE then
        return 1.0
    elseif complexity == self.complexity_levels.MEDIUM then
        return 2.5
    else
        return 4.0
    end
end

function SimulationBusinessPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"simulation_data", "performance_test", "business_comparison"},
        encoding_format = "JSON",
        key_format = "sim|scenario|entity_id|timestamp|complexity",
        features = {
            "multi_scenario_support",
            "variable_complexity_levels",
            "performance_metrics_tracking",
            "business_data_simulation"
        }
    }
end

return SimulationBusinessPlugin