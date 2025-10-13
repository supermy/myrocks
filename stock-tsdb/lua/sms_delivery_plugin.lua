-- 短信下发插件
-- 支持短信发送、状态跟踪、模板管理等短信业务功能

local SMSDeliveryPlugin = {}
SMSDeliveryPlugin.__index = SMSDeliveryPlugin

function SMSDeliveryPlugin:new()
    local obj = setmetatable({}, SMSDeliveryPlugin)
    obj.name = "sms_delivery"
    obj.version = "1.0.0"
    obj.description = "短信下发系统插件，支持短信发送和状态跟踪"
    
    -- 短信类型定义
    obj.sms_types = {
        VERIFICATION = "verification",    -- 验证码
        NOTIFICATION = "notification",    -- 通知
        PROMOTION = "promotion",          -- 营销
        ALERT = "alert"                   -- 告警
    }
    
    -- 短信状态
    obj.sms_status = {
        PENDING = "pending",      -- 待发送
        SENDING = "sending",      -- 发送中
        SENT = "sent",            -- 已发送
        DELIVERED = "delivered",  -- 已送达
        FAILED = "failed",        -- 发送失败
        EXPIRED = "expired"       -- 已过期
    }
    
    -- 短信渠道
    obj.sms_channels = {
        ALIYUN = "aliyun",        -- 阿里云
        TENCENT = "tencent",      -- 腾讯云
        CHUANGLAN = "chuanglan",  -- 创蓝
        YUNPIAN = "yunpian"       -- 云片
    }
    
    -- 模板类型
    obj.template_types = {
        TEXT = "text",            -- 文本
        VOICE = "voice",          -- 语音
        INTERNATIONAL = "international" -- 国际
    }
    
    -- 缓存优化
    obj.sms_cache = {}
    obj.template_cache = {}
    obj.cache_size = 3000
    
    return obj
end

function SMSDeliveryPlugin:get_name()
    return self.name
end

function SMSDeliveryPlugin:get_version()
    return self.version
end

function SMSDeliveryPlugin:get_description()
    return self.description
end

-- 编码短信记录RowKey
-- 格式: sms|channel|template_id|timestamp|type
function SMSDeliveryPlugin:encode_rowkey(channel, template_id, timestamp, sms_type)
    sms_type = sms_type or self.sms_types.VERIFICATION
    
    -- 时间戳处理（按小时分块）
    local timestamp_hour = math.floor(timestamp / 3600) * 3600
    
    local key_parts = {
        "sms",
        channel,
        template_id,
        tostring(timestamp_hour),
        sms_type
    }
    
    local qualifier = string.format("%06x", timestamp - timestamp_hour)  -- 6位十六进制表示秒偏移
    
    return table.concat(key_parts, "|"), qualifier
end

-- 解码短信记录RowKey
function SMSDeliveryPlugin:decode_rowkey(rowkey)
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 5 and parts[1] == "sms" then
        local timestamp_hour = tonumber(parts[4])
        
        return {
            type = "sms",
            channel = parts[2],
            template_id = parts[3],
            timestamp = timestamp_hour,
            sms_type = parts[5]
        }
    end
    
    return {type = "unknown"}
end

-- 编码短信记录Value
function SMSDeliveryPlugin:encode_value(sms_data)
    local value_parts = {}
    
    -- 短信基础信息
    local base_fields = {
        "channel", "template_id", "phone_number", "content", "status",
        "create_time", "send_time", "delivery_time", "sms_type", "priority"
    }
    
    for i, field in ipairs(base_fields) do
        local value = sms_data[field]
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
    
    -- 发送结果信息
    if sms_data.send_result then
        local result = sms_data.send_result
        value_parts[#value_parts + 1] = string.format(
            ',"send_result":{"message_id":"%s","error_code":"%s","error_message":"%s"}',
            result.message_id or "", result.error_code or "", result.error_message or "")
    end
    
    -- 模板信息
    if sms_data.template_info then
        local template = sms_data.template_info
        value_parts[#value_parts + 1] = string.format(
            ',"template_info":{"name":"%s","content":"%s","params":"%s"}',
            template.name or "", template.content or "", template.params or "")
    end
    
    -- 费用信息
    if sms_data.cost_info then
        local cost = sms_data.cost_info
        value_parts[#value_parts + 1] = string.format(
            ',"cost_info":{"unit_cost":%.4f,"total_cost":%.4f,"currency":"%s"}',
            cost.unit_cost or 0, cost.total_cost or 0, cost.currency or "CNY")
    end
    
    -- 扩展字段
    if sms_data.extra_info then
        value_parts[#value_parts + 1] = ',"extra_info":{'
        local first = true
        for k, v in pairs(sms_data.extra_info) do
            if not first then
                value_parts[#value_parts + 1] = ","
            end
            value_parts[#value_parts + 1] = string.format('"%s":"%s"', k, v)
            first = false
        end
        value_parts[#value_parts + 1] = "}"
    end
    
    -- 用户信息
    if sms_data.user_info then
        local user = sms_data.user_info
        value_parts[#value_parts + 1] = string.format(
            ',"user_info":{"user_id":"%s","user_type":"%s","region":"%s"}',
            user.user_id or "", user.user_type or "", user.region or "")
    end
    
    return "{" .. table.concat(value_parts) .. "}"
end

-- 解码短信记录Value
function SMSDeliveryPlugin:decode_value(value)
    local sms_data = {}
    
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
                sms_data[field] = self:_parse_object(obj_content)
                pos = obj_end + 2
            else
                pos = pos + 1
            end
        -- 处理简单值
        else
            -- 尝试匹配数字值
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start and value_start == pos then
                sms_data[field] = tonumber(val)
                pos = value_end + 1
            else
                -- 匹配字符串值
                value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
                if value_start and value_start == pos then
                    sms_data[field] = val
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
    
    return sms_data
end

-- 解析对象字段
function SMSDeliveryPlugin:_parse_object(obj_content)
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
function SMSDeliveryPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"sms", "template", "delivery"},
        encoding_format = "JSON",
        key_format = "sms|channel|template_id|timestamp|type",
        features = {
            "multi_channel_support",
            "template_management",
            "delivery_tracking",
            "cost_control"
        },
        performance_characteristics = {
            avg_encode_time = "< 0.1ms",
            avg_decode_time = "< 0.05ms",
            memory_footprint = "低"
        }
    }
end

-- 短信发送
function SMSDeliveryPlugin:send_sms(phone_number, content, template_id, channel)
    local sms_request = {
        phone_number = phone_number,
        content = content,
        template_id = template_id,
        channel = channel or self.sms_channels.ALIYUN,
        create_time = os.time(),
        status = self.sms_status.PENDING,
        priority = 1
    }
    
    return sms_request
end

-- 批量短信发送
function SMSDeliveryPlugin:batch_send_sms(phone_numbers, content, template_id, channel)
    local batch_request = {
        phone_numbers = phone_numbers,
        content = content,
        template_id = template_id,
        channel = channel or self.sms_channels.ALIYUN,
        create_time = os.time(),
        status = self.sms_status.PENDING,
        batch_id = self:_generate_batch_id(),
        total_count = #phone_numbers
    }
    
    return batch_request
end

-- 短信状态查询
function SMSDeliveryPlugin:query_sms_status(message_id, phone_number)
    local query_conditions = {
        message_id = message_id,
        phone_number = phone_number,
        query_time = os.time()
    }
    
    return query_conditions
end

-- 短信统计
function SMSDeliveryPlugin:get_sms_statistics(start_time, end_time, channel)
    local stats = {
        total_sent = 0,
        total_delivered = 0,
        success_rate = 0,
        channel_distribution = {},
        hourly_trend = {}
    }
    
    return stats
end

-- 模板管理
function SMSDeliveryPlugin:create_template(template_name, content, template_type, params)
    local template = {
        template_id = self:_generate_template_id(),
        template_name = template_name,
        content = content,
        template_type = template_type or self.template_types.TEXT,
        params = params or {},
        create_time = os.time(),
        status = "active"
    }
    
    return template
end

-- 模板查询
function SMSDeliveryPlugin:query_templates(template_type, status)
    local query_conditions = {
        template_type = template_type,
        status = status,
        query_time = os.time()
    }
    
    return query_conditions
end

-- 费用统计
function SMSDeliveryPlugin:get_cost_statistics(start_time, end_time)
    local cost_stats = {
        total_cost = 0,
        avg_unit_cost = 0,
        channel_cost_distribution = {},
        daily_cost_trend = {}
    }
    
    return cost_stats
end

-- 生成批次ID
function SMSDeliveryPlugin:_generate_batch_id()
    local timestamp = os.time()
    local random = math.random(1000, 9999)
    return string.format("BATCH_%d_%d", timestamp, random)
end

-- 生成模板ID
function SMSDeliveryPlugin:_generate_template_id()
    local timestamp = os.time()
    local random = math.random(100, 999)
    return string.format("TMPL_%d_%d", timestamp, random)
end

-- 短信内容验证
function SMSDeliveryPlugin:validate_sms_content(content)
    local validation_result = {
        is_valid = true,
        length = #content,
        contains_sensitive_words = false,
        sensitive_words = {},
        suggestions = {}
    }
    
    -- 简单的验证规则
    if #content > 500 then
        validation_result.is_valid = false
        table.insert(validation_result.suggestions, "内容过长，建议分段发送")
    end
    
    if #content < 5 then
        validation_result.is_valid = false
        table.insert(validation_result.suggestions, "内容过短，请补充完整信息")
    end
    
    -- 敏感词检查（简化版）
    local sensitive_words = {"赌博", "诈骗", "色情"}
    for _, word in ipairs(sensitive_words) do
        if string.find(content, word) then
            validation_result.contains_sensitive_words = true
            table.insert(validation_result.sensitive_words, word)
        end
    end
    
    if validation_result.contains_sensitive_words then
        validation_result.is_valid = false
        table.insert(validation_result.suggestions, "内容包含敏感词，请修改后重试")
    end
    
    return validation_result
end

return SMSDeliveryPlugin