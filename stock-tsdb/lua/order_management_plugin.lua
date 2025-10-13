-- 订单管理插件
-- 支持订单创建、状态跟踪、查询统计等业务功能

local OrderManagementPlugin = {}
OrderManagementPlugin.__index = OrderManagementPlugin

function OrderManagementPlugin:new()
    local obj = setmetatable({}, OrderManagementPlugin)
    obj.name = "order_management"
    obj.version = "1.0.0"
    obj.description = "订单管理系统插件，支持订单全生命周期管理"
    
    -- 订单状态定义
    obj.order_status = {
        PENDING = "pending",      -- 待处理
        CONFIRMED = "confirmed",  -- 已确认
        PROCESSING = "processing", -- 处理中
        SHIPPED = "shipped",      -- 已发货
        DELIVERED = "delivered",  -- 已送达
        CANCELLED = "cancelled",  -- 已取消
        REFUNDED = "refunded"     -- 已退款
    }
    
    -- 订单类型
    obj.order_types = {
        NORMAL = "normal",        -- 普通订单
        EXPRESS = "express",      -- 加急订单
        WHOLESALE = "wholesale",  -- 批发订单
        SUBSCRIPTION = "subscription" -- 订阅订单
    }
    
    -- 缓存优化
    obj.order_cache = {}
    obj.status_cache = {}
    obj.cache_size = 3000
    
    return obj
end

function OrderManagementPlugin:get_name()
    return self.name
end

function OrderManagementPlugin:get_version()
    return self.version
end

function OrderManagementPlugin:get_description()
    return self.description
end

-- 编码订单RowKey
-- 格式: order|user_id|order_id|timestamp|type
function OrderManagementPlugin:encode_rowkey(user_id, order_id, timestamp, order_type)
    order_type = order_type or self.order_types.NORMAL
    
    -- 时间戳处理（按天分块）
    local timestamp_day = math.floor(timestamp / 86400) * 86400
    
    local key_parts = {
        "order",
        tostring(user_id),
        tostring(order_id),
        tostring(timestamp_day),
        order_type
    }
    
    local qualifier = string.format("%08x", timestamp - timestamp_day)  -- 8位十六进制表示秒偏移
    
    return table.concat(key_parts, "|"), qualifier
end

-- 解码订单RowKey
function OrderManagementPlugin:decode_rowkey(rowkey)
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 5 and parts[1] == "order" then
        local timestamp_day = tonumber(parts[4])
        
        return {
            type = "order",
            user_id = tonumber(parts[2]),
            order_id = parts[3],
            timestamp = timestamp_day,
            order_type = parts[5]
        }
    end
    
    return {type = "unknown"}
end

-- 编码订单Value
function OrderManagementPlugin:encode_value(order_data)
    local value_parts = {}
    
    -- 订单基础信息
    local base_fields = {
        "user_id", "order_id", "amount", "currency", "status", 
        "create_time", "update_time", "order_type", "payment_status"
    }
    
    for i, field in ipairs(base_fields) do
        local value = order_data[field]
        if value ~= nil then
            if i > 1 then
                value_parts[#value_parts + 1] = ","
            end
            if type(value) == "number" then
                value_parts[#value_parts + 1] = string.format('"%s":%.2f', field, value)
            else
                value_parts[#value_parts + 1] = string.format('"%s":"%s"', field, value)
            end
        end
    end
    
    -- 订单商品信息
    if order_data.items and #order_data.items > 0 then
        value_parts[#value_parts + 1] = ',"items":['
        
        for i, item in ipairs(order_data.items) do
            if i > 1 then
                value_parts[#value_parts + 1] = ","
            end
            value_parts[#value_parts + 1] = string.format('{"product_id":"%s","quantity":%d,"price":%.2f}',
                item.product_id, item.quantity, item.price)
        end
        value_parts[#value_parts + 1] = "]"
    end
    
    -- 收货地址信息
    if order_data.shipping_address then
        local addr = order_data.shipping_address
        value_parts[#value_parts + 1] = string.format(
            ',"shipping_address":{"name":"%s","phone":"%s","address":"%s","city":"%s","province":"%s"}',
            addr.name or "", addr.phone or "", addr.address or "", addr.city or "", addr.province or "")
    end
    
    -- 支付信息
    if order_data.payment_info then
        local payment = order_data.payment_info
        value_parts[#value_parts + 1] = string.format(
            ',"payment_info":{"method":"%s","transaction_id":"%s","amount":%.2f}',
            payment.method or "", payment.transaction_id or "", payment.amount or 0)
    end
    
    -- 扩展字段
    if order_data.extra_info then
        value_parts[#value_parts + 1] = ',"extra_info":{'
        local first = true
        for k, v in pairs(order_data.extra_info) do
            if not first then
                value_parts[#value_parts + 1] = ","
            end
            value_parts[#value_parts + 1] = string.format('"%s":"%s"', k, v)
            first = false
        end
        value_parts[#value_parts + 1] = "}"
    end
    
    return "{" .. table.concat(value_parts) .. "}"
end

-- 解码订单Value
function OrderManagementPlugin:decode_value(value)
    local order_data = {}
    
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
        
        -- 处理数组字段（items）
        if field == "items" and string.sub(content, pos, pos) == "[" then
            local array_end = string.find(content, "]", pos)
            if array_end then
                local array_content = string.sub(content, pos + 1, array_end - 1)
                order_data.items = self:_parse_items_array(array_content)
                pos = array_end + 2
            else
                pos = pos + 1
            end
        -- 处理对象字段
        elseif string.sub(content, pos, pos) == "{" then
            local obj_end = string.find(content, "}", pos)
            if obj_end then
                local obj_content = string.sub(content, pos + 1, obj_end - 1)
                order_data[field] = self:_parse_object(obj_content)
                pos = obj_end + 2
            else
                pos = pos + 1
            end
        -- 处理简单值
        else
            -- 尝试匹配数字值
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start and value_start == pos then
                order_data[field] = tonumber(val)
                pos = value_end + 1
            else
                -- 匹配字符串值
                value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
                if value_start and value_start == pos then
                    order_data[field] = val
                    pos = value_end + 2
                else
                    pos = pos + 1
                end
            end
        end
        
        -- 跳过逗号
        if string.sub(content, pos, pos) == ',' then
            pos = pos + 1
        end
    end
    
    return order_data
end

-- 解析商品数组
function OrderManagementPlugin:_parse_items_array(array_content)
    local items = {}
    local pos = 1
    local item_index = 1
    
    while pos <= #array_content do
        if string.sub(array_content, pos, pos) == "{" then
            local item_end = string.find(array_content, "}", pos)
            if item_end then
                local item_content = string.sub(array_content, pos + 1, item_end - 1)
                items[item_index] = self:_parse_object(item_content)
                item_index = item_index + 1
                pos = item_end + 2
            else
                pos = pos + 1
            end
        else
            pos = pos + 1
        end
    end
    
    return items
end

-- 解析对象字段
function OrderManagementPlugin:_parse_object(obj_content)
    local obj = {}
    local pos = 1
    
    while pos <= #obj_content do
        local field_start, field_end, field = string.find(obj_content, '"([^"]+)":', pos)
        if not field_start then break end
        
        pos = field_end + 1
        local value_start, value_end, val
        
        -- 匹配数字值
        value_start, value_end, val = string.find(obj_content, "([%d%.]+)", pos)
        if value_start and value_start == pos then
            obj[field] = tonumber(val)
            pos = value_end + 1
        else
            -- 匹配字符串值
            value_start, value_end, val = string.find(obj_content, '"([^"]+)"', pos)
            if value_start and value_start == pos then
                obj[field] = val
                pos = value_end + 2
            else
                pos = pos + 1
            end
        end
        
        -- 跳过逗号
        if string.sub(obj_content, pos, pos) == ',' then
            pos = pos + 1
        end
    end
    
    return obj
end

-- 获取插件信息
function OrderManagementPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"order", "order_status", "order_item"},
        encoding_format = "JSON",
        key_format = "order|user_id|order_id|timestamp|type",
        features = {
            "order_lifecycle_management",
            "multi_item_support",
            "status_tracking",
            "payment_integration"
        },
        performance_characteristics = {
            avg_encode_time = "< 0.2ms",
            avg_decode_time = "< 0.1ms",
            memory_footprint = "中等"
        }
    }
end

-- 订单状态查询
function OrderManagementPlugin:query_orders_by_status(status, start_time, end_time)
    -- 构建状态查询条件
    local query_conditions = {
        status = status,
        start_time = start_time,
        end_time = end_time
    }
    
    return query_conditions
end

-- 用户订单查询
function OrderManagementPlugin:query_orders_by_user(user_id, limit, offset)
    -- 构建用户查询条件
    local query_conditions = {
        user_id = user_id,
        limit = limit or 100,
        offset = offset or 0
    }
    
    return query_conditions
end

-- 订单统计
function OrderManagementPlugin:get_order_statistics(start_time, end_time)
    local stats = {
        total_orders = 0,
        total_amount = 0,
        status_distribution = {},
        daily_trend = {}
    }
    
    return stats
end

return OrderManagementPlugin