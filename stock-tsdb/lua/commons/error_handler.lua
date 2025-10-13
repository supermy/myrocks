--
-- 错误处理工具类
-- 提供统一的错误处理、异常捕获和错误信息管理功能
--

local error_handler = {}

-- 错误代码定义
error_handler.ERROR_CODES = {
    -- 通用错误
    SUCCESS = 0,
    UNKNOWN_ERROR = 1000,
    INVALID_PARAMETER = 1001,
    OPERATION_FAILED = 1002,
    TIMEOUT = 1003,
    
    -- 配置相关错误
    CONFIG_LOAD_FAILED = 2001,
    CONFIG_VALIDATION_FAILED = 2002,
    CONFIG_NOT_FOUND = 2003,
    
    -- 网络相关错误
    NETWORK_ERROR = 3001,
    CONNECTION_FAILED = 3002,
    PROTOCOL_ERROR = 3003,
    
    -- 存储相关错误
    STORAGE_ERROR = 4001,
    DATA_NOT_FOUND = 4002,
    DATA_VALIDATION_FAILED = 4003,
    
    -- 业务相关错误
    BUSINESS_ERROR = 5001,
    PERMISSION_DENIED = 5002,
    RESOURCE_BUSY = 5003
}

-- 错误代码描述映射
error_handler.ERROR_MESSAGES = {
    [0] = "操作成功",
    [1000] = "未知错误",
    [1001] = "参数无效",
    [1002] = "操作失败",
    [1003] = "操作超时",
    [2001] = "配置加载失败",
    [2002] = "配置验证失败",
    [2003] = "配置不存在",
    [3001] = "网络错误",
    [3002] = "连接失败",
    [3003] = "协议错误",
    [4001] = "存储错误",
    [4002] = "数据不存在",
    [4003] = "数据验证失败",
    [5001] = "业务错误",
    [5002] = "权限不足",
    [5003] = "资源繁忙"
}

-- 错误类
local Error = {}
Error.__index = Error

function Error:new(code, message, details)
    local obj = setmetatable({}, Error)
    obj.code = code or error_handler.ERROR_CODES.UNKNOWN_ERROR
    obj.message = message or error_handler.ERROR_MESSAGES[obj.code] or "未知错误"
    obj.details = details
    obj.timestamp = os.time()
    obj.stack_trace = debug.traceback()
    return obj
end

-- 获取错误信息
function Error:get_message()
    return self.message
end

-- 获取错误代码
function Error:get_code()
    return self.code
end

-- 获取详细信息
function Error:get_details()
    return self.details
end

-- 获取堆栈跟踪
function Error:get_stack_trace()
    return self.stack_trace
end

-- 转换为字符串
function Error:to_string()
    local str = string.format("[%d] %s", self.code, self.message)
    
    if self.details then
        str = str .. " (" .. tostring(self.details) .. ")"
    end
    
    return str
end

-- 转换为表格式
function Error:to_table()
    return {
        code = self.code,
        message = self.message,
        details = self.details,
        timestamp = self.timestamp,
        stack_trace = self.stack_trace
    }
end

-- 错误处理器类
local ErrorHandler = {}
ErrorHandler.__index = ErrorHandler

function ErrorHandler:new(config)
    local obj = setmetatable({}, ErrorHandler)
    obj.config = config or {}
    obj.error_callbacks = {}
    obj.error_stats = {
        total_errors = 0,
        error_counts = {},
        last_error_time = 0
    }
    return obj
end

-- 注册错误回调
function ErrorHandler:register_callback(error_code, callback)
    if not self.error_callbacks[error_code] then
        self.error_callbacks[error_code] = {}
    end
    
    table.insert(self.error_callbacks[error_code], callback)
    return true
end

-- 处理错误
function ErrorHandler:handle_error(error_code, message, details)
    local error_obj = Error:new(error_code, message, details)
    
    -- 更新错误统计
    self.error_stats.total_errors = self.error_stats.total_errors + 1
    self.error_stats.error_counts[error_code] = (self.error_stats.error_counts[error_code] or 0) + 1
    self.error_stats.last_error_time = os.time()
    
    -- 调用错误回调
    local callbacks = self.error_callbacks[error_code] or {}
    for _, callback in ipairs(callbacks) do
        local success, result = pcall(callback, error_obj)
        if not success then
            print("错误回调执行失败: " .. tostring(result))
        end
    end
    
    -- 调用通用错误回调
    local general_callbacks = self.error_callbacks["*"] or {}
    for _, callback in ipairs(general_callbacks) do
        local success, result = pcall(callback, error_obj)
        if not success then
            print("通用错误回调执行失败: " .. tostring(result))
        end
    end
    
    return error_obj
end

-- 获取错误统计
function ErrorHandler:get_error_stats()
    return {
        total_errors = self.error_stats.total_errors,
        error_counts = self.error_stats.error_counts,
        last_error_time = self.error_stats.last_error_time
    }
end

-- 重置错误统计
function ErrorHandler:reset_stats()
    self.error_stats = {
        total_errors = 0,
        error_counts = {},
        last_error_time = 0
    }
end

-- 错误处理工具函数

-- 创建错误对象
function error_handler.create_error(code, message, details)
    return Error:new(code, message, details)
end

-- 安全执行函数（带错误处理）
function error_handler.safe_execute(func, error_code, ...)
    local success, result = pcall(func, ...)
    
    if success then
        return true, result
    else
        local error_obj = Error:new(error_code or error_handler.ERROR_CODES.OPERATION_FAILED, result)
        return false, error_obj
    end
end

-- 重试执行函数（带错误处理）
function error_handler.retry_execute(func, max_retries, delay_ms, error_code, ...)
    max_retries = max_retries or 3
    delay_ms = delay_ms or 1000
    
    for attempt = 1, max_retries do
        local success, result = error_handler.safe_execute(func, error_code, ...)
        
        if success then
            return true, result
        end
        
        if attempt < max_retries then
            -- 等待一段时间后重试
            local timer = require("lzmq.timer")
            timer.sleep(delay_ms)
        end
    end
    
    local final_error = Error:new(error_code or error_handler.ERROR_CODES.OPERATION_FAILED, "达到最大重试次数")
    return false, final_error
end

-- 验证参数
function error_handler.validate_params(params, schema)
    if type(params) ~= "table" then
        return false, Error:new(error_handler.ERROR_CODES.INVALID_PARAMETER, "参数必须是表类型")
    end
    
    if schema then
        for field_name, field_schema in pairs(schema) do
            local value = params[field_name]
            local required = field_schema.required or false
            local type_expected = field_schema.type
            
            -- 检查必需字段
            if required and value == nil then
                return false, Error:new(
                    error_handler.ERROR_CODES.INVALID_PARAMETER,
                    string.format("缺少必需参数: %s", field_name)
                )
            end
            
            -- 检查字段类型
            if value ~= nil and type_expected and type(value) ~= type_expected then
                return false, Error:new(
                    error_handler.ERROR_CODES.INVALID_PARAMETER,
                    string.format("参数 %s 类型错误: 期望 %s, 实际 %s", 
                        field_name, type_expected, type(value))
                )
            end
            
            -- 验证嵌套参数
            if type_expected == "table" and field_schema.schema then
                local ok, err = error_handler.validate_params(value, field_schema.schema)
                if not ok then
                    return false, err
                end
            end
        end
    end
    
    return true
end

-- 错误信息格式化
function error_handler.format_error_message(error_obj, include_stack_trace)
    if not error_obj or type(error_obj) ~= "table" then
        return "未知错误"
    end
    
    local message = error_obj.to_string and error_obj:to_string() or tostring(error_obj)
    
    if include_stack_trace and error_obj.get_stack_trace then
        message = message .. "\n堆栈跟踪:\n" .. error_obj:get_stack_trace()
    end
    
    return message
end

-- 错误日志记录
function error_handler.log_error(error_obj, logger_name)
    local logger = require("commons.logger")
    local log = logger.get_logger(logger_name or "error")
    
    if error_obj and error_obj.to_string then
        log:error("%s", error_obj:to_string())
        
        if error_obj.get_stack_trace then
            log:debug("堆栈跟踪:\n%s", error_obj:get_stack_trace())
        end
    else
        log:error("未知错误: %s", tostring(error_obj))
    end
end

-- 全局错误处理器实例
local global_error_handler = ErrorHandler:new()

-- 便捷全局函数
function error_handler.handle(code, message, details)
    return global_error_handler:handle_error(code, message, details)
end

function error_handler.register_callback(code, callback)
    return global_error_handler:register_callback(code, callback)
end

function error_handler.get_stats()
    return global_error_handler:get_error_stats()
end

function error_handler.reset()
    return global_error_handler:reset_stats()
end

-- 导出
error_handler.Error = Error
error_handler.ErrorHandler = ErrorHandler
global_error_handler = global_error_handler

return error_handler