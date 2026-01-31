-- ZeroMQ异步计算集成模块
-- 实现明细数据写入时的异步汇总计算机制

local ZMQAsyncAggregation = {}
ZMQAsyncAggregation.__index = ZMQAsyncAggregation

-- 导入依赖
local zmq = nil
local json = nil

-- 检查依赖是否可用
local function check_dependencies()
    local ok, zmq_module = pcall(require, "lzmq")
    if ok then
        zmq = zmq_module
    else
        print("警告: lzmq模块不可用，ZeroMQ功能将被禁用")
    end
    
    local ok, json_module = pcall(require, "cjson")
    if ok then
        json = json_module
    else
        -- 使用简单的JSON编码作为备选
        json = {
            encode = function(t)
                return "{data: " .. tostring(t) .. "}"
            end,
            decode = function(s)
                return {data = s}
            end
        }
    end
end

-- 初始化时检查依赖
check_dependencies()

-- 消息类型定义
local MESSAGE_TYPES = {
    DATA_POINT = "DATA_POINT",
    BATCH_DATA = "BATCH_DATA", 
    AGGREGATION_RESULT = "AGGREGATION_RESULT",
    FLUSH_REQUEST = "FLUSH_REQUEST",
    STATS_REQUEST = "STATS_REQUEST",
    SHUTDOWN = "SHUTDOWN"
}

-- 消息格式
local MessageFormat = {}

-- 创建数据点消息
function MessageFormat:create_data_point_message(data_point)
    return {
        type = MESSAGE_TYPES.DATA_POINT,
        timestamp = os.time(),
        data = data_point,
        message_id = self:generate_message_id()
    }
end

-- 创建批量数据消息
function MessageFormat:create_batch_message(data_points)
    return {
        type = MESSAGE_TYPES.BATCH_DATA,
        timestamp = os.time(),
        data = data_points,
        batch_size = #data_points,
        message_id = self:generate_message_id()
    }
end

-- 创建聚合结果消息
function MessageFormat:create_aggregation_result_message(results)
    return {
        type = MESSAGE_TYPES.AGGREGATION_RESULT,
        timestamp = os.time(),
        data = results,
        result_count = #results,
        message_id = self:generate_message_id()
    }
end

-- 创建刷新请求消息
function MessageFormat:create_flush_message()
    return {
        type = MESSAGE_TYPES.FLUSH_REQUEST,
        timestamp = os.time(),
        message_id = self:generate_message_id()
    }
end

-- 创建统计请求消息
function MessageFormat:create_stats_message()
    return {
        type = MESSAGE_TYPES.STATS_REQUEST,
        timestamp = os.time(),
        message_id = self:generate_message_id()
    }
end

-- 生成消息ID
function MessageFormat:generate_message_id()
    return tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
end

-- 创建ZeroMQ异步聚合器
function ZMQAsyncAggregation:new(config)
    local obj = setmetatable({}, ZMQAsyncAggregation)
    
    -- 处理LightAggregationConfig对象或直接配置
    obj.config = config or {}
    
    obj.context = nil
    obj.socket = nil
    obj.is_connected = false
    obj.message_queue = {}
    obj.stats = {
        messages_sent = 0,
        messages_received = 0,
        bytes_sent = 0,
        bytes_received = 0,
        errors = 0,
        last_error = nil
    }
    
    return obj
end

-- 初始化ZeroMQ连接
function ZMQAsyncAggregation:initialize()
    if not self.config.zmq or not self.config.zmq.enabled then
        return true, "ZeroMQ已禁用"
    end
    
    -- 检查ZeroMQ是否可用
    if not zmq then
        self.is_connected = true
        return true, "ZeroMQ不可用，客户端以禁用模式初始化"
    end
    
    local ok, err = pcall(function()
        -- 创建ZeroMQ上下文
        self.context = zmq.context()
        
        -- 创建DEALER套接字（用于异步通信）
        self.socket = self.context:socket(zmq.DEALER, {
            connect = "tcp://localhost:" .. tostring(self.config.zmq.port),
            sndtimeo = self.config.zmq.send_timeout,
            rcvtimoe = self.config.zmq.recv_timeout,
            linger = 0
        })
        
        self.is_connected = true
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "ZeroMQ初始化失败: " .. tostring(err)
    end
    
    return true, "ZeroMQ初始化成功"
end

-- 发送单个数据点
function ZMQAsyncAggregation:send_data_point(data_point)
    if not self.config.zmq or not self.config.zmq.enabled or not self.is_connected then
        return false, "ZeroMQ未启用或未连接"
    end
    
    local message = MessageFormat:create_data_point_message(data_point)
    return self:send_message(message)
end

-- 发送批量数据点
function ZMQAsyncAggregation:send_batch_data(data_points)
    if not self.config.zmq or not self.config.zmq.enabled or not self.is_connected then
        return false, "ZeroMQ未启用或未连接"
    end
    
    local message = MessageFormat:create_batch_message(data_points)
    return self:send_message(message)
end

-- 发送消息
function ZMQAsyncAggregation:send_message(message)
    local ok, err = pcall(function()
        local message_json = json.encode(message)
        local bytes_sent = self.socket:send(message_json)
        
        if bytes_sent > 0 then
            self.stats.messages_sent = self.stats.messages_sent + 1
            self.stats.bytes_sent = self.stats.bytes_sent + bytes_sent
            
            -- 添加到消息队列用于跟踪
            table.insert(self.message_queue, {
                message_id = message.message_id,
                type = message.type,
                timestamp = message.timestamp,
                status = "sent"
            })
        else
            error("消息发送失败")
        end
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "消息发送失败: " .. tostring(err)
    end
    
    return true, "消息发送成功"
end

-- 接收消息
function ZMQAsyncAggregation:receive_message(timeout)
    if not self.config.zmq or not self.config.zmq.enabled or not self.is_connected then
        return nil, "ZeroMQ未启用或未连接"
    end
    
    local original_timeout = self.socket:get_rcvtimeo()
    if timeout then
        self.socket:set_rcvtimeo(timeout)
    end
    
    local ok, message_json, err = pcall(function()
        return self.socket:recv()
    end)
    
    -- 恢复原始超时设置
    if timeout then
        self.socket:set_rcvtimeo(original_timeout)
    end
    
    if not ok or not message_json then
        if err and err ~= "Resource temporarily unavailable" then
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
        end
        return nil, err
    end
    
    -- 解析JSON消息
    local ok, message = pcall(function()
        return json.decode(message_json)
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = "JSON解析失败"
        return nil, "JSON解析失败"
    end
    
    self.stats.messages_received = self.stats.messages_received + 1
    self.stats.bytes_received = self.stats.bytes_received + #message_json
    
    -- 更新消息队列状态
    self:update_message_status(message)
    
    return message, nil
end

-- 更新消息状态
function ZMQAsyncAggregation:update_message_status(message)
    for i, queued_message in ipairs(self.message_queue) do
        if queued_message.message_id == message.message_id then
            queued_message.status = "received"
            queued_message.response_timestamp = os.time()
            queued_message.response_data = message
            break
        end
    end
end

-- 发送刷新请求
function ZMQAsyncAggregation:send_flush_request()
    if not self.config.zmq or not self.config.zmq.enabled or not self.is_connected then
        return false, "ZeroMQ未启用或未连接"
    end
    
    local message = MessageFormat:create_flush_message()
    return self:send_message(message)
end

-- 发送统计请求
function ZMQAsyncAggregation:send_stats_request()
    if not self.config.zmq or not self.config.zmq.enabled or not self.is_connected then
        return false, "ZeroMQ未启用或未连接"
    end
    
    local message = MessageFormat:create_stats_message()
    return self:send_message(message)
end

-- 获取统计信息
function ZMQAsyncAggregation:get_stats()
    local zmq_config = self.config.zmq or {}
    local stats = {
        connection = {
            enabled = zmq_config.enabled or false,
            connected = self.is_connected,
            port = zmq_config.port or 0
        },
        messages = {
            sent = self.stats.messages_sent,
            received = self.stats.messages_received,
            bytes_sent = self.stats.bytes_sent,
            bytes_received = self.stats.bytes_received,
            queue_size = #self.message_queue
        },
        errors = {
            total = self.stats.errors,
            last_error = self.stats.last_error
        },
        performance = {
            send_rate = self:calculate_send_rate(),
            receive_rate = self:calculate_receive_rate()
        }
    }
    
    return stats
end

-- 计算发送速率
function ZMQAsyncAggregation:calculate_send_rate()
    if #self.message_queue == 0 then
        return 0
    end
    
    local oldest_message = self.message_queue[1]
    local time_span = os.time() - oldest_message.timestamp
    
    if time_span == 0 then
        return self.stats.messages_sent
    end
    
    return self.stats.messages_sent / time_span
end

-- 计算接收速率
function ZMQAsyncAggregation:calculate_receive_rate()
    if #self.message_queue == 0 then
        return 0
    end
    
    local received_count = 0
    for _, message in ipairs(self.message_queue) do
        if message.status == "received" then
            received_count = received_count + 1
        end
    end
    
    local oldest_message = self.message_queue[1]
    local time_span = os.time() - oldest_message.timestamp
    
    if time_span == 0 then
        return received_count
    end
    
    return received_count / time_span
end

-- 清理过期的消息队列
function ZMQAsyncAggregation:cleanup_message_queue(retention_hours)
    local cutoff_time = os.time() - (retention_hours * 3600)
    local cleaned_count = 0
    
    for i = #self.message_queue, 1, -1 do
        if self.message_queue[i].timestamp < cutoff_time then
            table.remove(self.message_queue, i)
            cleaned_count = cleaned_count + 1
        end
    end
    
    return cleaned_count
end

-- 关闭连接
function ZMQAsyncAggregation:close()
    if self.socket then
        self.socket:close()
        self.socket = nil
    end
    
    if self.context then
        self.context:destroy()
        self.context = nil
    end
    
    self.is_connected = false
end

-- 重新连接
function ZMQAsyncAggregation:reconnect()
    self:close()
    return self:initialize()
end

-- 检查连接状态
function ZMQAsyncAggregation:check_connection()
    if not self.config.zmq or not self.config.zmq.enabled then
        return true, "ZeroMQ已禁用"
    end
    
    if not self.is_connected then
        return false, "未连接"
    end
    
    -- 发送测试消息检查连接
    local test_message = {
        type = "TEST",
        timestamp = os.time(),
        message_id = "test_" .. tostring(os.time())
    }
    
    local ok, err = self:send_message(test_message)
    if not ok then
        self.is_connected = false
        return false, "连接测试失败: " .. tostring(err)
    end
    
    return true, "连接正常"
end

-- 异步聚合处理器（服务端）
local AsyncAggregationProcessor = {}
AsyncAggregationProcessor.__index = AsyncAggregationProcessor

-- 创建异步聚合处理器
function AsyncAggregationProcessor:new(config, time_aggregator, other_aggregator, storage_engine)
    local obj = setmetatable({}, AsyncAggregationProcessor)
    obj.config = config
    obj.time_aggregator = time_aggregator
    obj.other_aggregator = other_aggregator
    obj.storage_engine = storage_engine
    obj.context = nil
    obj.socket = nil
    obj.is_running = false
    obj.stats = {
        messages_processed = 0,
        data_points_processed = 0,
        aggregation_results = 0,
        errors = 0
    }
    
    return obj
end

-- 启动处理器
function AsyncAggregationProcessor:start()
    if not self.config.zmq.enabled then
        return true, "ZeroMQ已禁用"
    end
    
    local ok, err = pcall(function()
        -- 创建ZeroMQ上下文
        self.context = zmq.context()
        
        -- 创建ROUTER套接字（用于接收消息）
        self.socket = self.context:socket(zmq.ROUTER, {
            bind = "tcp://*:" .. tostring(self.config.zmq.port),
            sndtimeo = self.config.zmq.send_timeout,
            rcvtimoe = self.config.zmq.recv_timeout
        })
        
        self.is_running = true
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        return false, "处理器启动失败: " .. tostring(err)
    end
    
    return true, "处理器启动成功"
end

-- 处理消息循环
function AsyncAggregationProcessor:process_loop()
    while self.is_running do
        local message, err = self:receive_message(1000)  -- 1秒超时
        
        if message then
            self:handle_message(message)
        elseif err and err ~= "Resource temporarily unavailable" then
            self.stats.errors = self.stats.errors + 1
        end
    end
end

-- 处理单个消息
function AsyncAggregationProcessor:handle_message(message)
    self.stats.messages_processed = self.stats.messages_processed + 1
    
    if message.type == MESSAGE_TYPES.DATA_POINT then
        self:handle_data_point(message)
    elseif message.type == MESSAGE_TYPES.BATCH_DATA then
        self:handle_batch_data(message)
    elseif message.type == MESSAGE_TYPES.FLUSH_REQUEST then
        self:handle_flush_request(message)
    elseif message.type == MESSAGE_TYPES.STATS_REQUEST then
        self:handle_stats_request(message)
    elseif message.type == MESSAGE_TYPES.SHUTDOWN then
        self:handle_shutdown(message)
    else
        self:send_error_response(message, "未知消息类型: " .. tostring(message.type))
    end
end

-- 处理数据点消息
function AsyncAggregationProcessor:handle_data_point(message)
    local data_point = message.data
    
    -- 处理时间维度聚合
    if self.time_aggregator then
        self.time_aggregator:process_data_point(data_point)
    end
    
    -- 处理其他维度聚合
    if self.other_aggregator then
        self.other_aggregator:process_data_point(data_point)
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + 1
    
    -- 发送确认响应
    self:send_success_response(message, "数据点处理成功")
end

-- 处理批量数据消息
function AsyncAggregationProcessor:handle_batch_data(message)
    local data_points = message.data
    local results = {}
    
    -- 处理时间维度聚合
    if self.time_aggregator then
        local time_results = self.time_aggregator:process_batch(data_points)
        for _, result in ipairs(time_results) do
            table.insert(results, result)
        end
    end
    
    -- 处理其他维度聚合
    if self.other_aggregator then
        local other_results = self.other_aggregator:process_batch(data_points)
        for _, result in ipairs(other_results) do
            table.insert(results, result)
        end
    end
    
    self.stats.data_points_processed = self.stats.data_points_processed + #data_points
    
    -- 存储聚合结果
    if self.storage_engine and #results > 0 then
        self.storage_engine:store_aggregation_results(results)
        self.stats.aggregation_results = self.stats.aggregation_results + #results
    end
    
    -- 发送聚合结果响应
    local response = MessageFormat:create_aggregation_result_message(results)
    self:send_response(message, response)
end

-- 处理刷新请求
function AsyncAggregationProcessor:handle_flush_request(message)
    local results = {}
    
    -- 刷新时间维度缓冲区
    if self.time_aggregator then
        local time_results = self.time_aggregator:flush_all_buffers()
        for _, result in ipairs(time_results) do
            table.insert(results, result)
        end
    end
    
    -- 刷新其他维度缓冲区
    if self.other_aggregator then
        local other_results = self.other_aggregator:flush_all_buffers()
        for _, result in ipairs(other_results) do
            table.insert(results, result)
        end
    end
    
    -- 存储聚合结果
    if self.storage_engine and #results > 0 then
        self.storage_engine:store_aggregation_results(results)
        self.stats.aggregation_results = self.stats.aggregation_results + #results
    end
    
    -- 发送刷新完成响应
    local response = {
        type = "FLUSH_COMPLETE",
        timestamp = os.time(),
        results_count = #results,
        message_id = message.message_id
    }
    
    self:send_response(message, response)
end

-- 处理统计请求
function AsyncAggregationProcessor:handle_stats_request(message)
    local stats = {
        processor_stats = self.stats,
        time_aggregator_stats = self.time_aggregator and self.time_aggregator:get_all_stats() or {},
        other_aggregator_stats = self.other_aggregator and self.other_aggregator:get_all_stats() or {},
        storage_stats = self.storage_engine and self.storage_engine:get_stats() or {}
    }
    
    local response = {
        type = "STATS_RESPONSE",
        timestamp = os.time(),
        data = stats,
        message_id = message.message_id
    }
    
    self:send_response(message, response)
end

-- 处理关闭请求
function AsyncAggregationProcessor:handle_shutdown(message)
    self.is_running = false
    
    local response = {
        type = "SHUTDOWN_ACK",
        timestamp = os.time(),
        message_id = message.message_id
    }
    
    self:send_response(message, response)
end

-- 发送成功响应
function AsyncAggregationProcessor:send_success_response(original_message, message_text)
    local response = {
        type = "SUCCESS",
        timestamp = os.time(),
        message = message_text,
        message_id = original_message.message_id
    }
    
    self:send_response(original_message, response)
end

-- 发送错误响应
function AsyncAggregationProcessor:send_error_response(original_message, error_text)
    local response = {
        type = "ERROR",
        timestamp = os.time(),
        error = error_text,
        message_id = original_message.message_id
    }
    
    self:send_response(original_message, response)
end

-- 发送响应
function AsyncAggregationProcessor:send_response(original_message, response)
    local ok, err = pcall(function()
        local response_json = cjson.encode(response)
        self.socket:send(original_message.sender_id, zmq.SNDMORE)
        self.socket:send("", zmq.SNDMORE)
        self.socket:send(response_json)
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
    end
end

-- 接收消息（带发送者ID）
function AsyncAggregationProcessor:receive_message(timeout)
    local original_timeout = self.socket:get_rcvtimeo()
    if timeout then
        self.socket:set_rcvtimeo(timeout)
    end
    
    local ok, sender_id, empty, message_json, err = pcall(function()
        local sid = self.socket:recv()
        local emp = self.socket:recv()
        local msg = self.socket:recv()
        return sid, emp, msg
    end)
    
    -- 恢复原始超时设置
    if timeout then
        self.socket:set_rcvtimeo(original_timeout)
    end
    
    if not ok or not message_json then
        return nil, err
    end
    
    -- 解析JSON消息
    local ok, message = pcall(function()
        local msg = cjson.decode(message_json)
        msg.sender_id = sender_id
        return msg
    end)
    
    if not ok then
        return nil, "JSON解析失败"
    end
    
    return message, nil
end

-- 停止处理器
function AsyncAggregationProcessor:stop()
    self.is_running = false
    
    if self.socket then
        self.socket:close()
        self.socket = nil
    end
    
    if self.context then
        self.context:destroy()
        self.context = nil
    end
end

return {
    ZMQAsyncAggregation = ZMQAsyncAggregation,
    AsyncAggregationProcessor = AsyncAggregationProcessor,
    MESSAGE_TYPES = MESSAGE_TYPES,
    MessageFormat = MessageFormat
}