-- 业务数据聚合引擎
-- 支持SQL查询和聚合函数

local BusinessAggregation = {}
BusinessAggregation.__index = BusinessAggregation

-- 导入依赖
local cjson = require "cjson"
local UnifiedDataAccess = require "unified_data_access"

-- 支持的聚合函数
local AGGREGATION_FUNCTIONS = {
    COUNT = function(values) return #values end,
    SUM = function(values) 
        local sum = 0
        for _, v in ipairs(values) do
            sum = sum + (tonumber(v) or 0)
        end
        return sum
    end,
    AVG = function(values)
        if #values == 0 then return 0 end
        local sum = 0
        for _, v in ipairs(values) do
            sum = sum + (tonumber(v) or 0)
        end
        return sum / #values
    end,
    MAX = function(values)
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
    MIN = function(values)
        if #values == 0 then return nil end
        local min = tonumber(values[1]) or math.huge
        for _, v in ipairs(values) do
            local num = tonumber(v)
            if num and num < min then
                min = num
            end
        end
        return min
    end
}

-- SQL解析器
local SQLParser = {}
SQLParser.__index = SQLParser

function SQLParser:new()
    local obj = setmetatable({}, SQLParser)
    return obj
end

function SQLParser:parse(sql)
    local query = {
        select = {},
        from = "",
        where = {},
        group_by = {},
        order_by = {},
        limit = nil,
        offset = 0
    }
    
    -- 保存原始SQL用于字段名提取
    local original_sql = sql
    
    -- 简单的SQL解析（实际项目中应该使用更复杂的解析器）
    sql = sql:upper():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- 解析SELECT子句
    local select_start, select_end = sql:find("SELECT%s+")
    local from_start = sql:find("FROM%s+")
    
    if select_start and from_start then
        -- 使用原始SQL提取字段名，保留大小写
        -- 直接使用原始SQL的位置来提取字段名
        local select_clause = original_sql:sub(select_start + 6, from_start - 1)
        for field in select_clause:gmatch("[^,]+") do
            field = field:gsub("^%s+", ""):gsub("%s+$", "")
            table.insert(query.select, field)
        end
        
        -- 调试：打印解析的SELECT字段
        print("[DEBUG] Parsed SELECT fields:", require("cjson").encode(query.select))
    end
    
    -- 解析FROM子句
    local where_start = sql:find("WHERE%s+") or sql:find("GROUP%s+BY%s+") or 
                       sql:find("ORDER%s+BY%s+") or sql:find("LIMIT%s+") or #sql + 1
    
    if from_start then
        query.from = sql:sub(from_start + 5, where_start - 1):gsub("^%s+", ""):gsub("%s+$", "")
    end
    
    -- 解析WHERE子句
    local where_clause_start = sql:find("WHERE%s+")
    if where_clause_start then
        local group_start = sql:find("GROUP%s+BY%s+") or sql:find("ORDER%s+BY%s+") or 
                           sql:find("LIMIT%s+") or #sql + 1
        local where_clause = sql:sub(where_clause_start + 6, group_start - 1)
        
        -- 简单的条件解析
        for condition in where_clause:gmatch("[^AND]+") do
            condition = condition:gsub("^%s+", ""):gsub("%s+$", "")
            table.insert(query.where, condition)
        end
    end
    
    -- 解析GROUP BY子句
    local group_start = sql:find("GROUP%s+BY%s+")
    if group_start then
        local order_start = sql:find("ORDER%s+BY%s+") or sql:find("LIMIT%s+") or #sql + 1
        
        -- 使用原始SQL提取字段名，保留大小写
        -- 直接使用原始SQL的位置来提取字段名
        -- 修正偏移量计算：找到"GROUP BY"后面的第一个非空格字符位置
        local group_by_end = group_start + 8  -- "GROUP BY"的长度是8
        local field_start = group_by_end
        
        -- 跳过空格
        while field_start <= #original_sql and original_sql:sub(field_start, field_start):match("%s") do
            field_start = field_start + 1
        end
        
        local group_clause = original_sql:sub(field_start, order_start - 1)
        
        for field in group_clause:gmatch("[^,]+") do
            field = field:gsub("^%s+", ""):gsub("%s+$", "")
            table.insert(query.group_by, field)
        end
    end
    
    -- 解析ORDER BY子句
    local order_start = sql:find("ORDER%s+BY%s+")
    if order_start then
        local limit_start = sql:find("LIMIT%s+") or #sql + 1
        local order_clause = sql:sub(order_start + 9, limit_start - 1)
        
        for field in order_clause:gmatch("[^,]+") do
            field = field:gsub("^%s+", ""):gsub("%s+$", "")
            table.insert(query.order_by, field)
        end
    end
    
    -- 解析LIMIT子句
    local limit_start = sql:find("LIMIT%s+")
    if limit_start then
        local limit_clause = sql:sub(limit_start + 6)
        local limit_parts = {}
        for part in limit_clause:gmatch("%S+") do
            table.insert(limit_parts, tonumber(part))
        end
        
        if #limit_parts >= 1 then
            query.limit = limit_parts[1]
        end
        if #limit_parts >= 2 then
            query.offset = limit_parts[2]
        end
    end
    
    return query
end

function BusinessAggregation:new()
    local obj = setmetatable({}, BusinessAggregation)
    obj.name = "business_aggregation"
    obj.version = "1.0.0"
    obj.description = "业务数据聚合引擎，支持SQL查询和聚合函数"
    
    -- 初始化数据访问层
    obj.data_access = UnifiedDataAccess:new()
    
    -- SQL解析器
    obj.sql_parser = SQLParser:new()
    
    -- 业务数据模式定义
    obj.schemas = {
        stock_quotes = {
            fields = {
                "stock_code", "market", "timestamp", "price", "volume", 
                "amount", "open", "high", "low", "close"
            },
            key_pattern = "stock:%s:%d",
            business_type = "stock_quotes"
        },
        iot_data = {
            fields = {
                "device_id", "metric_type", "timestamp", "value", "unit", "location"
            },
            key_pattern = "iot:%s:%s:%d",
            business_type = "iot_data"
        },
        financial_quotes = {
            fields = {
                "symbol", "exchange", "timestamp", "price", "volume", "change"
            },
            key_pattern = "financial:%s:%d",
            business_type = "financial_quotes"
        },
        order_data = {
            fields = {
                "order_id", "user_id", "timestamp", "amount", "status", "product_id"
            },
            key_pattern = "order:%s:%d",
            business_type = "order_data"
        },
        payment_data = {
            fields = {
                "payment_id", "order_id", "timestamp", "amount", "status", "method"
            },
            key_pattern = "payment:%s:%d",
            business_type = "payment_data"
        },
        inventory_data = {
            fields = {
                "product_id", "warehouse", "timestamp", "quantity", "status", "location"
            },
            key_pattern = "inventory:%s:%d",
            business_type = "inventory_data"
        },
        sms_delivery = {
            fields = {
                "sms_id", "phone", "timestamp", "content", "status", "provider"
            },
            key_pattern = "sms:%s:%d",
            business_type = "sms_delivery"
        }
    }
    
    return obj
end

-- 执行SQL查询
function BusinessAggregation:execute_sql(sql)
    local query = self.sql_parser:parse(sql)
    
    if not query.from or query.from == "" then
        return nil, "缺少FROM子句"
    end
    
    -- 将表名转换为小写以匹配模式定义
    local table_name = query.from:lower()
    local schema = self.schemas[table_name]
    if not schema then
        return nil, "未知的数据表: " .. query.from
    end
    
    -- 获取数据
    local data = self:fetch_data(schema, query.where)
    
    -- 应用聚合函数
    if #query.group_by > 0 then
        return self:apply_group_by(data, query.select, query.group_by)
    else
        return self:apply_aggregation(data, query.select)
    end
end

-- 获取数据
function BusinessAggregation:fetch_data(schema, conditions)
    local data = {}
    
    -- 这里应该实现实际的数据获取逻辑
    -- 简化版本：模拟数据
    if schema.business_type == "stock_quotes" then
        data = {
            {stock_code = "000001", market = "SH", timestamp = os.time() - 3600, price = 10.5, volume = 1000000, amount = 10500000, open = 10.4, high = 10.8, low = 10.3, close = 10.5},
            {stock_code = "000002", market = "SZ", timestamp = os.time() - 1800, price = 15.2, volume = 500000, amount = 7600000, open = 15.1, high = 15.5, low = 15.0, close = 15.2},
            {stock_code = "000001", market = "SH", timestamp = os.time() - 7200, price = 10.3, volume = 800000, amount = 8240000, open = 10.2, high = 10.6, low = 10.1, close = 10.3},
            {stock_code = "000003", market = "SH", timestamp = os.time() - 5400, price = 8.7, volume = 300000, amount = 2610000, open = 8.6, high = 8.9, low = 8.5, close = 8.7}
        }
    elseif schema.business_type == "iot_data" then
        data = {
            {device_id = "sensor_001", metric_type = "temperature", timestamp = os.time() - 3600, value = 25.6, unit = "°C", location = "room_101"},
            {device_id = "sensor_002", metric_type = "humidity", timestamp = os.time() - 1800, value = 65.2, unit = "%", location = "room_102"},
            {device_id = "sensor_001", metric_type = "temperature", timestamp = os.time() - 7200, value = 24.8, unit = "°C", location = "room_101"},
            {device_id = "sensor_003", metric_type = "pressure", timestamp = os.time() - 5400, value = 1013.2, unit = "hPa", location = "room_103"}
        }
    end
    
    -- 应用WHERE条件过滤
    if #conditions > 0 then
        data = self:apply_where_conditions(data, conditions)
    end
    
    return data
end

-- 应用WHERE条件
function BusinessAggregation:apply_where_conditions(data, conditions)
    local filtered_data = {}
    
    -- 调试：打印解析的条件
    print("[DEBUG] WHERE conditions:", require("cjson").encode(conditions))
    
    for _, record in ipairs(data) do
        local match = true
        
        for _, condition in ipairs(conditions) do
            -- 先去除条件字符串前后的空格
            condition = condition:gsub("^%s+", ""):gsub("%s+$", "")
            
            -- 调试：打印原始条件
            print("[DEBUG] Raw condition:", condition)
            
            -- 使用更简单的方法解析条件
            local field, operator, value = self:parse_condition(condition)
            
            -- 调试：打印解析结果
            print("[DEBUG] Parsed - field:", field, "operator:", operator, "value:", value)
            
            if field and operator and value then
                -- 将字段名转换为小写以匹配数据记录中的键
                local field_lower = field:lower()
                local record_value = record[field_lower]
                
                -- 调试：打印记录值和比较
                print("[DEBUG] Record value for", field_lower, ":", record_value)
                
                if operator == "=" then
                    match = match and (tostring(record_value) == value)
                elseif operator == "!=" then
                    match = match and (tostring(record_value) ~= value)
                elseif operator == "<" then
                    match = match and (tonumber(record_value) or 0) < tonumber(value)
                elseif operator == ">" then
                    match = match and (tonumber(record_value) or 0) > tonumber(value)
                elseif operator == "<=" then
                    match = match and (tonumber(record_value) or 0) <= tonumber(value)
                elseif operator == ">=" then
                    match = match and (tonumber(record_value) or 0) >= tonumber(value)
                elseif operator == "LIKE" then
                    local pattern = value:gsub("%*", ".*"):gsub("%?", ".")
                    match = match and (tostring(record_value):match(pattern) ~= nil)
                end
                
                -- 调试：打印匹配结果
                print("[DEBUG] Match result for condition:", match)
            else
                print("[DEBUG] Failed to parse condition")
            end
        end
        
        if match then
            table.insert(filtered_data, record)
        end
    end
    
    return filtered_data
end

-- 新的条件解析方法
function BusinessAggregation:parse_condition(condition)
    -- 定义支持的运算符
    local operators = {">=", "<=", "!=", ">", "<", "=", "LIKE"}
    
    -- 按运算符分割条件
    for _, op in ipairs(operators) do
        local pattern = "(.-)" .. op .. "(.+)"
        local field_part, value_part = condition:match(pattern)
        
        if field_part and value_part then
            -- 去除字段和值两端的空格
            field_part = field_part:gsub("^%s+", ""):gsub("%s+$", "")
            value_part = value_part:gsub("^%s+", ""):gsub("%s+$", "")
            
            -- 如果值被引号包围，去除引号
            if value_part:match("^['\"](.*)['\"]$") then
                value_part = value_part:match("^['\"](.*)['\"]$")
            end
            
            return field_part, op, value_part
        end
    end
    
    -- 如果上面的方法失败，尝试简单的空格分割
    local parts = {}
    for part in condition:gmatch("%S+") do
        table.insert(parts, part)
    end
    
    if #parts >= 3 then
        local field = parts[1]
        local operator = parts[2]
        local value = parts[3]
        
        -- 检查运算符是否支持
        for _, op in ipairs(operators) do
            if operator == op then
                return field, operator, value
            end
        end
    end
    
    return nil, nil, nil
end

-- 应用聚合函数
function BusinessAggregation:apply_aggregation(data, select_fields)
    -- 检查是否包含聚合函数
    local has_aggregation = false
    for _, field in ipairs(select_fields) do
        for func_name, _ in pairs(AGGREGATION_FUNCTIONS) do
            if field:upper():find(func_name .. "%(") then
                has_aggregation = true
                break
            end
        end
        if has_aggregation then break end
    end
    
    if has_aggregation then
        -- 有聚合函数，返回聚合结果
        local result = {}
        
        for _, field in ipairs(select_fields) do
            local field_name = field
            local aggregation_func = nil
            
            -- 检查是否包含聚合函数
            for func_name, _ in pairs(AGGREGATION_FUNCTIONS) do
                if field:upper():find(func_name .. "%(") then
                    local column = field:match(func_name .. "%(([^)]+)%)")
                    if column then
                        field_name = func_name .. "(" .. column .. ")"
                        aggregation_func = AGGREGATION_FUNCTIONS[func_name]
                        break
                    end
                end
            end
            
            if aggregation_func then
                local values = {}
                
                -- 处理COUNT(*)的情况
                if field:upper():find("COUNT%(%*%)") then
                    -- COUNT(*) 统计所有记录
                    result[field_name] = #data
                else
                    -- 处理其他聚合函数
                    for _, record in ipairs(data) do
                        local column_name = field:match("%(([^)]+)%)")
                        if column_name then
                            -- 尝试不同大小写的字段名匹配
                            local value = record[column_name] or record[column_name:lower()] or record[column_name:upper()]
                            if value then
                                table.insert(values, value)
                            end
                        end
                    end
                    
                    result[field_name] = aggregation_func(values)
                end
            else
                -- 非聚合字段，取第一条记录的值
                if #data > 0 then
                    result[field_name] = data[1][field_name]
                else
                    result[field_name] = nil
                end
            end
        end
        
        return {result}
    else
        -- 没有聚合函数，返回所有记录
        local results = {}
        
        for _, record in ipairs(data) do
            local result_record = {}
            
            -- 处理SELECT *的情况
            if #select_fields == 1 and select_fields[1] == "*" then
                -- 如果是SELECT *，返回所有字段
                for field_name, field_value in pairs(record) do
                    result_record[field_name] = field_value
                end
            else
                -- 正常处理指定字段
        for _, field in ipairs(select_fields) do
            -- 将字段名转换为小写以匹配数据记录中的键
            local field_lower = field:lower()
            result_record[field] = record[field_lower]
        end
            end
            
            table.insert(results, result_record)
        end
        
        return results
    end
end

-- 应用GROUP BY分组
function BusinessAggregation:apply_group_by(data, select_fields, group_by_fields)
    local grouped_data = {}
    
    -- 分组数据
    for _, record in ipairs(data) do
        local group_key = ""
        for _, group_field in ipairs(group_by_fields) do
            -- 尝试不同大小写的字段名匹配
            local value = record[group_field] or record[group_field:lower()] or record[group_field:upper()]
            group_key = group_key .. tostring(value) .. "|"
        end
        
        if not grouped_data[group_key] then
            grouped_data[group_key] = {}
        end
        
        table.insert(grouped_data[group_key], record)
    end
    
    -- 对每个分组应用聚合
    local results = {}
    for group_key, group_records in pairs(grouped_data) do
        local group_result = {}
        
        -- 添加分组字段
        local group_parts = {}
        for part in group_key:gmatch("[^|]+") do
            table.insert(group_parts, part)
        end
        

        
        for i, group_field in ipairs(group_by_fields) do
            -- 使用原始字段名作为键
            group_result[group_field] = group_parts[i]
        end
        
        -- 应用聚合函数
        for _, field in ipairs(select_fields) do
            local field_name = field
            local aggregation_func = nil
            
            for func_name, _ in pairs(AGGREGATION_FUNCTIONS) do
                if field:upper():find(func_name .. "%(") then
                    local column = field:match(func_name .. "%(([^)]+)%)")
                    if column then
                        field_name = func_name .. "(" .. column .. ")"
                        aggregation_func = AGGREGATION_FUNCTIONS[func_name]
                        break
                    end
                end
            end
            
            if aggregation_func then
                local values = {}
                
                -- 处理COUNT(*)的情况
                if field:upper():find("COUNT%(%*%)") then
                    -- COUNT(*) 统计分组记录数
                    group_result[field_name] = #group_records
                else
                    -- 处理其他聚合函数
                    for _, record in ipairs(group_records) do
                        local column_name = field:match("%(([^)]+)%)")
                        if column_name then
                            -- 尝试不同大小写的字段名匹配
                            local value = record[column_name] or record[column_name:lower()] or record[column_name:upper()]
                            if value then
                                table.insert(values, value)
                            end
                        end
                    end
                    
                    group_result[field_name] = aggregation_func(values)
                end
            else
                -- 非聚合字段，检查是否在分组字段中
                local is_group_field = false
                for _, group_field in ipairs(group_by_fields) do
                    if field == group_field then
                        is_group_field = true
                        break
                    end
                end
                
                if is_group_field then
                    -- 如果是分组字段，应该已经在group_result中设置过了
                    -- 这里不需要额外处理
                else
                    -- 如果不是分组字段，取第一条记录的值
                    -- 将字段名转换为小写以匹配数据记录中的键
                    local field_lower = field_name:lower()
                    group_result[field_name] = group_records[1][field_lower]
                end
            end
        end
        
        -- 按照SELECT字段的顺序重新组织结果
        local ordered_result = {}
        for _, field in ipairs(select_fields) do
            local field_name = field
            
            -- 处理聚合函数字段名
            for func_name, _ in pairs(AGGREGATION_FUNCTIONS) do
                if field:upper():find(func_name .. "%(") then
                    local column = field:match(func_name .. "%(([^)]+)%)")
                    if column then
                        field_name = func_name .. "(" .. column .. ")"
                        break
                    end
                end
            end
            
            ordered_result[field_name] = group_result[field_name]
        end
        
        table.insert(results, ordered_result)
    end
    
    return results
end

-- 获取可用的数据表列表
function BusinessAggregation:get_available_tables()
    local tables = {}
    for table_name, schema in pairs(self.schemas) do
        table.insert(tables, {
            name = table_name,
            fields = schema.fields,
            description = schema.business_type
        })
    end
    return tables
end

-- 获取表结构信息
function BusinessAggregation:get_table_schema(table_name)
    local schema = self.schemas[table_name]
    if schema then
        return {
            name = table_name,
            fields = schema.fields,
            key_pattern = schema.key_pattern,
            business_type = schema.business_type
        }
    end
    return nil
end

return BusinessAggregation