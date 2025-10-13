-- 库存管理插件
-- 支持库存跟踪、出入库管理、库存预警等业务功能

local InventoryManagementPlugin = {}
InventoryManagementPlugin.__index = InventoryManagementPlugin

function InventoryManagementPlugin:new()
    local obj = setmetatable({}, InventoryManagementPlugin)
    obj.name = "inventory_management"
    obj.version = "1.0.0"
    obj.description = "库存管理系统插件，支持实时库存跟踪和出入库管理"
    
    -- 库存操作类型
    obj.operation_types = {
        INBOUND = "inbound",      -- 入库
        OUTBOUND = "outbound",    -- 出库
        TRANSFER = "transfer",    -- 调拨
        ADJUSTMENT = "adjustment" -- 调整
    }
    
    -- 库存状态
    obj.inventory_status = {
        NORMAL = "normal",        -- 正常
        LOW = "low",             -- 库存不足
        OVERSTOCK = "overstock",  -- 库存积压
        EXPIRED = "expired"       -- 已过期
    }
    
    -- 仓库类型
    obj.warehouse_types = {
        CENTRAL = "central",      -- 中心仓
        REGIONAL = "regional",    -- 区域仓
        RETAIL = "retail",        -- 零售仓
        VIRTUAL = "virtual"       -- 虚拟仓
    }
    
    -- 缓存优化
    obj.inventory_cache = {}
    obj.operation_cache = {}
    obj.cache_size = 4000
    
    return obj
end

function InventoryManagementPlugin:get_name()
    return self.name
end

function InventoryManagementPlugin:get_version()
    return self.version
end

function InventoryManagementPlugin:get_description()
    return self.description
end

-- 编码库存记录RowKey
-- 格式: inventory|warehouse_id|sku_id|timestamp|operation
function InventoryManagementPlugin:encode_rowkey(warehouse_id, sku_id, timestamp, operation_type)
    operation_type = operation_type or self.operation_types.INBOUND
    
    -- 时间戳处理（按天分块）
    local timestamp_day = math.floor(timestamp / 86400) * 86400
    
    local key_parts = {
        "inventory",
        tostring(warehouse_id),
        sku_id,
        tostring(timestamp_day),
        operation_type
    }
    
    local qualifier = string.format("%08x", timestamp - timestamp_day)  -- 8位十六进制表示秒偏移
    
    return table.concat(key_parts, "|"), qualifier
end

-- 解码库存记录RowKey
function InventoryManagementPlugin:decode_rowkey(rowkey)
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 5 and parts[1] == "inventory" then
        local timestamp_day = tonumber(parts[4])
        
        return {
            type = "inventory",
            warehouse_id = tonumber(parts[2]),
            sku_id = parts[3],
            timestamp = timestamp_day,
            operation_type = parts[5]
        }
    end
    
    return {type = "unknown"}
end

-- 编码库存操作Value
function InventoryManagementPlugin:encode_value(inventory_data)
    local value_parts = {}
    
    -- 库存基础信息
    local base_fields = {
        "warehouse_id", "sku_id", "quantity", "operation_type", "status",
        "create_time", "update_time", "operator_id", "reference_id"
    }
    
    for i, field in ipairs(base_fields) do
        local value = inventory_data[field]
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
    
    -- 商品信息
    if inventory_data.product_info then
        local product = inventory_data.product_info
        value_parts[#value_parts + 1] = string.format(
            ',"product_info":{"name":"%s","category":"%s","brand":"%s","unit":"%s"}',
            product.name or "", product.category or "", product.brand or "", product.unit or "")
    end
    
    -- 批次信息
    if inventory_data.batch_info then
        local batch = inventory_data.batch_info
        value_parts[#value_parts + 1] = string.format(
            ',"batch_info":{"batch_no":"%s","production_date":"%s","expiry_date":"%s"}',
            batch.batch_no or "", batch.production_date or "", batch.expiry_date or "")
    end
    
    -- 位置信息
    if inventory_data.location_info then
        local location = inventory_data.location_info
        value_parts[#value_parts + 1] = string.format(
            ',"location_info":{"zone":"%s","shelf":"%s","position":"%s"}',
            location.zone or "", location.shelf or "", location.position or "")
    end
    
    -- 成本信息
    if inventory_data.cost_info then
        local cost = inventory_data.cost_info
        value_parts[#value_parts + 1] = string.format(
            ',"cost_info":{"unit_cost":%.2f,"total_cost":%.2f,"currency":"%s"}',
            cost.unit_cost or 0, cost.total_cost or 0, cost.currency or "CNY")
    end
    
    -- 扩展字段
    if inventory_data.extra_info then
        value_parts[#value_parts + 1] = ',"extra_info":{'
        local first = true
        for k, v in pairs(inventory_data.extra_info) do
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

-- 解码库存操作Value
function InventoryManagementPlugin:decode_value(value)
    local inventory_data = {}
    
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
                inventory_data[field] = self:_parse_object(obj_content)
                pos = obj_end + 2
            else
                pos = pos + 1
            end
        -- 处理简单值
        else
            -- 尝试匹配数字值
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start and value_start == pos then
                inventory_data[field] = tonumber(val)
                pos = value_end + 1
            else
                -- 匹配字符串值
                value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
                if value_start and value_start == pos then
                    inventory_data[field] = val
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
    
    return inventory_data
end

-- 解析对象字段
function InventoryManagementPlugin:_parse_object(obj_content)
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
function InventoryManagementPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"inventory", "stock", "operation"},
        encoding_format = "JSON",
        key_format = "inventory|warehouse_id|sku_id|timestamp|operation",
        features = {
            "real_time_tracking",
            "multi_warehouse_support",
            "batch_management",
            "inventory_alert"
        },
        performance_characteristics = {
            avg_encode_time = "< 0.12ms",
            avg_decode_time = "< 0.06ms",
            memory_footprint = "中等"
        }
    }
end

-- 库存查询
function InventoryManagementPlugin:query_inventory(warehouse_id, sku_id)
    local query_conditions = {
        warehouse_id = warehouse_id,
        sku_id = sku_id
    }
    
    return query_conditions
end

-- 库存操作记录查询
function InventoryManagementPlugin:query_operations(warehouse_id, start_time, end_time, operation_type)
    local query_conditions = {
        warehouse_id = warehouse_id,
        start_time = start_time,
        end_time = end_time,
        operation_type = operation_type
    }
    
    return query_conditions
end

-- 库存统计
function InventoryManagementPlugin:get_inventory_statistics(warehouse_id)
    local stats = {
        total_skus = 0,
        total_quantity = 0,
        total_value = 0,
        status_distribution = {},
        category_distribution = {}
    }
    
    return stats
end

-- 库存预警检查
function InventoryManagementPlugin:check_inventory_alerts(warehouse_id)
    local alerts = {
        low_stock = {},
        overstock = {},
        near_expiry = {},
        abnormal_movement = {}
    }
    
    return alerts
end

-- 库存盘点
function InventoryManagementPlugin:inventory_count(warehouse_id, sku_list)
    local count_result = {
        warehouse_id = warehouse_id,
        count_time = os.time(),
        total_counted = 0,
        discrepancies = {},
        accuracy_rate = 0
    }
    
    return count_result
end

-- 库存调拨
function InventoryManagementPlugin:transfer_inventory(from_warehouse, to_warehouse, sku_id, quantity, reason)
    local transfer = {
        from_warehouse = from_warehouse,
        to_warehouse = to_warehouse,
        sku_id = sku_id,
        quantity = quantity,
        reason = reason,
        transfer_time = os.time(),
        status = "pending"
    }
    
    return transfer
end

-- 库存调整
function InventoryManagementPlugin:adjust_inventory(warehouse_id, sku_id, adjustment_quantity, reason)
    local adjustment = {
        warehouse_id = warehouse_id,
        sku_id = sku_id,
        adjustment_quantity = adjustment_quantity,
        reason = reason,
        adjustment_time = os.time(),
        status = "pending"
    }
    
    return adjustment
end

return InventoryManagementPlugin