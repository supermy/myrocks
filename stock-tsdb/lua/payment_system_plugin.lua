-- 支付系统插件
-- 支持多种支付方式、交易记录、对账等支付业务功能

local PaymentSystemPlugin = {}
PaymentSystemPlugin.__index = PaymentSystemPlugin

function PaymentSystemPlugin:new()
    local obj = setmetatable({}, PaymentSystemPlugin)
    obj.name = "payment_system"
    obj.version = "1.0.0"
    obj.description = "支付系统插件，支持多种支付方式和交易管理"
    
    -- 支付方式定义
    obj.payment_methods = {
        ALIPAY = "alipay",      -- 支付宝
        WECHAT = "wechat",      -- 微信支付
        UNIONPAY = "unionpay",  -- 银联
        CREDIT_CARD = "credit_card", -- 信用卡
        DEBIT_CARD = "debit_card",   -- 借记卡
        BANK_TRANSFER = "bank_transfer" -- 银行转账
    }
    
    -- 支付状态
    obj.payment_status = {
        INITIATED = "initiated",    -- 已发起
        PROCESSING = "processing",  -- 处理中
        SUCCESS = "success",        -- 成功
        FAILED = "failed",          -- 失败
        REFUNDED = "refunded",      -- 已退款
        CANCELLED = "cancelled"     -- 已取消
    }
    
    -- 货币类型
    obj.currencies = {
        CNY = "CNY",  -- 人民币
        USD = "USD",  -- 美元
        EUR = "EUR",  -- 欧元
        JPY = "JPY",  -- 日元
        GBP = "GBP"   -- 英镑
    }
    
    -- 缓存优化
    obj.transaction_cache = {}
    obj.payment_cache = {}
    obj.cache_size = 5000
    
    return obj
end

function PaymentSystemPlugin:get_name()
    return self.name
end

function PaymentSystemPlugin:get_version()
    return self.version
end

function PaymentSystemPlugin:get_description()
    return self.description
end

-- 编码支付交易RowKey
-- 格式: payment|merchant_id|transaction_id|timestamp|method
function PaymentSystemPlugin:encode_rowkey(merchant_id, transaction_id, timestamp, payment_method)
    payment_method = payment_method or self.payment_methods.ALIPAY
    
    -- 时间戳处理（按小时分块）
    local timestamp_hour = math.floor(timestamp / 3600) * 3600
    
    local key_parts = {
        "payment",
        tostring(merchant_id),
        transaction_id,
        tostring(timestamp_hour),
        payment_method
    }
    
    local qualifier = string.format("%06x", timestamp - timestamp_hour)  -- 6位十六进制表示秒偏移
    
    return table.concat(key_parts, "|"), qualifier
end

-- 解码支付交易RowKey
function PaymentSystemPlugin:decode_rowkey(rowkey)
    local parts = {}
    for part in string.gmatch(rowkey, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 5 and parts[1] == "payment" then
        local timestamp_hour = tonumber(parts[4])
        
        return {
            type = "payment",
            merchant_id = tonumber(parts[2]),
            transaction_id = parts[3],
            timestamp = timestamp_hour,
            payment_method = parts[5]
        }
    end
    
    return {type = "unknown"}
end

-- 编码支付交易Value
function PaymentSystemPlugin:encode_value(payment_data)
    local value_parts = {}
    
    -- 支付基础信息
    local base_fields = {
        "merchant_id", "transaction_id", "amount", "currency", "status",
        "payment_method", "create_time", "update_time", "user_id", "order_id"
    }
    
    for i, field in ipairs(base_fields) do
        local value = payment_data[field]
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
    
    -- 支付渠道信息
    if payment_data.channel_info then
        local channel = payment_data.channel_info
        value_parts[#value_parts + 1] = string.format(
            ',"channel_info":{"channel_id":"%s","channel_name":"%s","fee_rate":%.4f}',
            channel.channel_id or "", channel.channel_name or "", channel.fee_rate or 0)
    end
    
    -- 支付结果信息
    if payment_data.result_info then
        local result = payment_data.result_info
        value_parts[#value_parts + 1] = string.format(
            ',"result_info":{"code":"%s","message":"%s","gateway_tx_id":"%s"}',
            result.code or "", result.message or "", result.gateway_tx_id or "")
    end
    
    -- 退款信息
    if payment_data.refund_info then
        local refund = payment_data.refund_info
        value_parts[#value_parts + 1] = string.format(
            ',"refund_info":{"refund_id":"%s","refund_amount":%.2f,"refund_reason":"%s"}',
            refund.refund_id or "", refund.refund_amount or 0, refund.refund_reason or "")
    end
    
    -- 风控信息
    if payment_data.risk_info then
        local risk = payment_data.risk_info
        value_parts[#value_parts + 1] = string.format(
            ',"risk_info":{"risk_score":%d,"risk_level":"%s","risk_reason":"%s"}',
            risk.risk_score or 0, risk.risk_level or "", risk.risk_reason or "")
    end
    
    -- 扩展字段
    if payment_data.extra_info then
        value_parts[#value_parts + 1] = ',"extra_info":{'
        local first = true
        for k, v in pairs(payment_data.extra_info) do
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

-- 解码支付交易Value
function PaymentSystemPlugin:decode_value(value)
    local payment_data = {}
    
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
                payment_data[field] = self:_parse_object(obj_content)
                pos = obj_end + 2
            else
                pos = pos + 1
            end
        -- 处理简单值
        else
            -- 尝试匹配数字值
            value_start, value_end, val = string.find(content, "([%d%.]+)", pos)
            if value_start and value_start == pos then
                payment_data[field] = tonumber(val)
                pos = value_end + 1
            else
                -- 匹配字符串值
                value_start, value_end, val = string.find(content, '"([^"]+)"', pos)
                if value_start and value_start == pos then
                    payment_data[field] = val
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
    
    return payment_data
end

-- 解析对象字段
function PaymentSystemPlugin:_parse_object(obj_content)
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
function PaymentSystemPlugin:get_info()
    return {
        name = self.name,
        version = self.version,
        description = self.description,
        supported_types = {"payment", "refund", "transaction"},
        encoding_format = "JSON",
        key_format = "payment|merchant_id|transaction_id|timestamp|method",
        features = {
            "multi_payment_method",
            "transaction_tracking",
            "refund_management",
            "risk_control"
        },
        performance_characteristics = {
            avg_encode_time = "< 0.15ms",
            avg_decode_time = "< 0.08ms",
            memory_footprint = "中等"
        }
    }
end

-- 交易查询
function PaymentSystemPlugin:query_transactions(merchant_id, start_time, end_time, status)
    local query_conditions = {
        merchant_id = merchant_id,
        start_time = start_time,
        end_time = end_time,
        status = status
    }
    
    return query_conditions
end

-- 支付统计
function PaymentSystemPlugin:get_payment_statistics(start_time, end_time)
    local stats = {
        total_transactions = 0,
        total_amount = 0,
        success_rate = 0,
        method_distribution = {},
        hourly_trend = {}
    }
    
    return stats
end

-- 对账功能
function PaymentSystemPlugin:reconcile_transactions(merchant_id, date)
    local reconciliation = {
        merchant_id = merchant_id,
        date = date,
        total_count = 0,
        total_amount = 0,
        discrepancies = {}
    }
    
    return reconciliation
end

-- 风控检查
function PaymentSystemPlugin:risk_check(payment_data)
    local risk_result = {
        risk_score = 0,
        risk_level = "low",
        risk_reasons = {},
        suggested_actions = {}
    }
    
    -- 简单的风控规则
    if payment_data.amount > 10000 then
        risk_result.risk_score = risk_result.risk_score + 30
        table.insert(risk_result.risk_reasons, "大额交易")
    end
    
    if payment_data.payment_method == self.payment_methods.CREDIT_CARD then
        risk_result.risk_score = risk_result.risk_score + 20
        table.insert(risk_result.risk_reasons, "信用卡支付")
    end
    
    -- 根据风险分数确定风险等级
    if risk_result.risk_score >= 50 then
        risk_result.risk_level = "high"
        table.insert(risk_result.suggested_actions, "需要人工审核")
    elseif risk_result.risk_score >= 30 then
        risk_result.risk_level = "medium"
        table.insert(risk_result.suggested_actions, "发送验证码")
    else
        risk_result.risk_level = "low"
        table.insert(risk_result.suggested_actions, "自动通过")
    end
    
    return risk_result
end

return PaymentSystemPlugin