-- CSV数据导入导出管理器
-- 支持v3版本的股票行情、IOT、金融行情、订单、支付、库存、短信下发等业务数据的CSV格式导入导出

local json = require "cjson"

-- 简单的CSV解析器（替代外部csv模块）
local SimpleCSVParser = {}
SimpleCSVParser.__index = SimpleCSVParser

function SimpleCSVParser:new(file)
    local obj = setmetatable({}, SimpleCSVParser)
    obj.file = file
    obj.buffer = ""
    return obj
end

-- 读取一行CSV数据
function SimpleCSVParser:read()
    if not self.file then
        return nil
    end
    
    local line = self.file:read()
    if not line then
        return nil
    end
    
    -- 简单的CSV解析：按逗号分割，处理引号内的逗号
    local fields = {}
    local current_field = ""
    local in_quotes = false
    
    for i = 1, #line do
        local char = line:sub(i, i)
        
        if char == '"' then
            in_quotes = not in_quotes
        elseif char == ',' and not in_quotes then
            table.insert(fields, current_field)
            current_field = ""
        else
            current_field = current_field .. char
        end
    end
    
    table.insert(fields, current_field)
    
    -- 去除字段两端的空格和引号
    for i, field in ipairs(fields) do
        fields[i] = field:gsub('^%s*(.-)%s*$', '%1'):gsub('^"(.*)"$', '%1')
    end
    
    return fields
end

-- 获取所有行
function SimpleCSVParser:lines()
    return function()
        return self:read()
    end
end

local CSVDataManager = {}
CSVDataManager.__index = CSVDataManager

function CSVDataManager:new(storage_engine)
    local obj = setmetatable({}, CSVDataManager)
    obj.storage_engine = storage_engine
    obj.business_schemas = {
        -- 股票行情数据schema
        stock_quotes = {
            columns = {"timestamp", "stock_code", "market", "open", "high", "low", "close", "volume", "amount"},
            required = {"timestamp", "stock_code", "market", "close"},
            metric_name = "stock_quotes",
            timestamp_format = "unix"
        },
        
        -- IOT设备数据schema
        iot_data = {
            columns = {"timestamp", "device_id", "sensor_type", "value", "unit", "location", "status"},
            required = {"timestamp", "device_id", "sensor_type", "value"},
            metric_name = "iot_data",
            timestamp_format = "unix"
        },
        
        -- 金融行情数据schema
        financial_quotes = {
            columns = {"timestamp", "symbol", "exchange", "bid", "ask", "last_price", "volume", "change", "change_percent"},
            required = {"timestamp", "symbol", "exchange", "last_price"},
            metric_name = "financial_quotes",
            timestamp_format = "unix"
        },
        
        -- 订单数据schema
        orders = {
            columns = {"timestamp", "order_id", "user_id", "product_id", "quantity", "price", "status", "payment_method"},
            required = {"timestamp", "order_id", "user_id", "product_id", "quantity", "price"},
            metric_name = "orders",
            timestamp_format = "unix"
        },
        
        -- 支付数据schema
        payments = {
            columns = {"timestamp", "payment_id", "order_id", "amount", "currency", "status", "payment_gateway", "user_id"},
            required = {"timestamp", "payment_id", "order_id", "amount", "currency"},
            metric_name = "payments",
            timestamp_format = "unix"
        },
        
        -- 库存数据schema
        inventory = {
            columns = {"timestamp", "product_id", "warehouse_id", "quantity", "location", "status", "last_updated_by"},
            required = {"timestamp", "product_id", "warehouse_id", "quantity"},
            metric_name = "inventory",
            timestamp_format = "unix"
        },
        
        -- 短信下发数据schema
        sms = {
            columns = {"timestamp", "sms_id", "phone_number", "content", "status", "template_id", "send_time", "delivery_time"},
            required = {"timestamp", "sms_id", "phone_number", "content"},
            metric_name = "sms",
            timestamp_format = "unix"
        }
    }
    
    return obj
end

-- 导入CSV数据到存储引擎
function CSVDataManager:import_csv(file_path, business_type, options)
    options = options or {}
    local schema = self.business_schemas[business_type]
    
    if not schema then
        return false, "不支持的业务类型: " .. tostring(business_type)
    end
    
    -- 打开CSV文件
    local file, err = io.open(file_path, "r")
    if not file then
        return false, "无法打开CSV文件: " .. tostring(err)
    end
    
    -- 解析CSV文件
    local csv_parser = SimpleCSVParser:new(file)
    local header = csv_parser:read()
    
    if not header then
        file:close()
        return false, "CSV文件格式错误：缺少表头"
    end
    
    -- 验证表头
    local column_mapping = {}
    for i, col_name in ipairs(header) do
        column_mapping[col_name:lower()] = i
    end
    
    -- 检查必需字段
    for _, required_col in ipairs(schema.required) do
        if not column_mapping[required_col:lower()] then
            file:close()
            return false, "缺少必需字段: " .. required_col
        end
    end
    
    -- 导入数据
    local imported_count = 0
    local error_count = 0
    local batch_size = options.batch_size or 1000
    local batch_data = {}
    
    for row in csv_parser:lines() do
        if #row > 0 then
            local data_point = self:parse_csv_row(row, header, schema, business_type)
            
            if data_point then
                table.insert(batch_data, data_point)
                imported_count = imported_count + 1
                
                -- 批量写入
                if #batch_data >= batch_size then
                    local success = self:batch_write_data(batch_data, business_type)
                    if not success then
                        error_count = error_count + #batch_data
                    end
                    batch_data = {}
                end
            else
                error_count = error_count + 1
            end
        end
    end
    
    -- 写入剩余数据
    if #batch_data > 0 then
        local success = self:batch_write_data(batch_data, business_type)
        if not success then
            error_count = error_count + #batch_data
        end
    end
    
    file:close()
    
    return true, {
        imported_count = imported_count,
        error_count = error_count,
        success_rate = (imported_count - error_count) / imported_count * 100
    }
end

-- 解析CSV行数据
function CSVDataManager:parse_csv_row(row, header, schema, business_type)
    local data = {}
    
    -- 解析每个字段
    for i, col_name in ipairs(header) do
        local value = row[i]
        if value and value ~= "" then
            -- 根据字段类型进行转换
            if col_name:lower() == "timestamp" then
                data.timestamp = tonumber(value) or os.time()
            elseif col_name:lower() == "price" or col_name:lower() == "amount" or 
                   col_name:lower() == "value" or col_name:lower() == "quantity" then
                data[col_name:lower()] = tonumber(value)
            else
                data[col_name:lower()] = value
            end
        end
    end
    
    -- 验证必需字段
    for _, required_col in ipairs(schema.required) do
        if not data[required_col] then
            return nil
        end
    end
    
    -- 构建存储引擎需要的数据结构
    local metric_name = schema.metric_name
    local timestamp = data.timestamp
    local value = data.close or data.last_price or data.amount or data.value or data.quantity or 0
    local tags = {}
    
    -- 提取标签字段
    for col_name, col_value in pairs(data) do
        if col_name ~= "timestamp" and col_name ~= "value" then
            tags[col_name] = col_value
        end
    end
    
    return {
        metric = metric_name,
        timestamp = timestamp,
        value = value,
        tags = tags,
        business_type = business_type,
        raw_data = data
    }
end

-- 批量写入数据
function CSVDataManager:batch_write_data(batch_data, business_type)
    if not self.storage_engine then
        return false
    end
    
    local success_count = 0
    
    for _, data_point in ipairs(batch_data) do
        local success = self.storage_engine:write_point(
            data_point.metric,
            data_point.timestamp,
            data_point.value,
            data_point.tags
        )
        
        if success then
            success_count = success_count + 1
        end
    end
    
    return success_count == #batch_data
end

-- 导出数据到CSV文件
function CSVDataManager:export_csv(file_path, business_type, start_time, end_time, options)
    options = options or {}
    local schema = self.business_schemas[business_type]
    
    if not schema then
        return false, "不支持的业务类型: " .. tostring(business_type)
    end
    
    if not self.storage_engine then
        return false, "存储引擎未初始化"
    end
    
    -- 查询数据
    local success, results = self.storage_engine:read_point(
        schema.metric_name,
        start_time or 0,
        end_time or os.time(),
        {}
    )
    
    if not success then
        return false, "数据查询失败"
    end
    
    -- 创建CSV文件
    local file, err = io.open(file_path, "w")
    if not file then
        return false, "无法创建CSV文件: " .. tostring(err)
    end
    
    -- 写入表头
    local header = {}
    for _, col_name in ipairs(schema.columns) do
        table.insert(header, col_name)
    end
    
    file:write(table.concat(header, ",") .. "\n")
    
    -- 写入数据行
    local exported_count = 0
    for _, data_point in ipairs(results) do
        local row = {}
        
        for _, col_name in ipairs(schema.columns) do
            local value = ""
            
            if col_name == "timestamp" then
                value = tostring(data_point.timestamp)
            elseif col_name == "value" then
                value = tostring(data_point.value)
            elseif data_point.tags and data_point.tags[col_name] then
                value = tostring(data_point.tags[col_name])
            end
            
            table.insert(row, value)
        end
        
        file:write(table.concat(row, ",") .. "\n")
        exported_count = exported_count + 1
    end
    
    file:close()
    
    return true, {
        exported_count = exported_count,
        file_path = file_path,
        business_type = business_type,
        time_range = {start_time = start_time, end_time = end_time}
    }
end

-- 获取支持的CSV格式列表
function CSVDataManager:get_supported_formats()
    local formats = {}
    
    for business_type, schema in pairs(self.business_schemas) do
        formats[business_type] = {
            columns = schema.columns,
            required = schema.required,
            description = self:get_business_description(business_type)
        }
    end
    
    return formats
end

-- 获取业务描述
function CSVDataManager:get_business_description(business_type)
    local descriptions = {
        stock_quotes = "股票行情数据：包含股票代码、市场、开盘价、最高价、最低价、收盘价、成交量等",
        iot_data = "IOT设备数据：包含设备ID、传感器类型、数值、单位、位置、状态等",
        financial_quotes = "金融行情数据：包含金融符号、交易所、买入价、卖出价、最新价、成交量等",
        orders = "订单数据：包含订单ID、用户ID、产品ID、数量、价格、状态等",
        payments = "支付数据：包含支付ID、订单ID、金额、货币、状态、支付网关等",
        inventory = "库存数据：包含产品ID、仓库ID、数量、位置、状态等",
        sms = "短信下发数据：包含短信ID、手机号、内容、状态、模板ID、发送时间等"
    }
    
    return descriptions[business_type] or "未知业务类型"
end

-- 验证CSV文件格式
function CSVDataManager:validate_csv_format(file_path, business_type)
    local schema = self.business_schemas[business_type]
    
    if not schema then
        return false, "不支持的业务类型: " .. tostring(business_type)
    end
    
    local file, err = io.open(file_path, "r")
    if not file then
        return false, "无法打开CSV文件: " .. tostring(err)
    end
    
    local csv_parser = SimpleCSVParser:new(file)
    local header = csv_parser:read()
    
    if not header then
        file:close()
        return false, "CSV文件格式错误：缺少表头"
    end
    
    -- 验证表头
    local column_mapping = {}
    for i, col_name in ipairs(header) do
        column_mapping[col_name:lower()] = i
    end
    
    -- 检查必需字段
    local missing_columns = {}
    for _, required_col in ipairs(schema.required) do
        if not column_mapping[required_col:lower()] then
            table.insert(missing_columns, required_col)
        end
    end
    
    file:close()
    
    if #missing_columns > 0 then
        return false, "缺少必需字段: " .. table.concat(missing_columns, ", ")
    end
    
    return true, {
        valid = true,
        columns_found = header,
        columns_expected = schema.columns,
        missing_columns = missing_columns
    }
end

return CSVDataManager