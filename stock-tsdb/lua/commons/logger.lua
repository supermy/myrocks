--
-- 日志记录工具类
-- 提供统一的日志记录功能，支持不同日志级别和输出格式
--

local logger = {}

-- 日志级别定义
logger.LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5
}

-- 日志级别名称映射
logger.LEVEL_NAMES = {
    [1] = "DEBUG",
    [2] = "INFO", 
    [3] = "WARN",
    [4] = "ERROR",
    [5] = "FATAL"
}

-- 日志记录器类
local Logger = {}
Logger.__index = Logger

function Logger:new(name, config)
    local obj = setmetatable({}, Logger)
    obj.name = name or "default"
    obj.config = config or {}
    obj.level = obj.config.level or logger.LEVELS.INFO
    obj.output_file = obj.config.output_file
    obj.max_file_size = obj.config.max_file_size or 10 * 1024 * 1024  -- 10MB
    obj.file_handle = nil
    
    -- 初始化文件句柄
    if obj.output_file then
        obj.file_handle = io.open(obj.output_file, "a")
        if not obj.file_handle then
            print(string.format("WARN: 无法打开日志文件: %s", obj.output_file))
        end
    end
    
    return obj
end

-- 设置日志级别
function Logger:set_level(level)
    if type(level) == "string" then
        level = logger.LEVELS[level:upper()]
    end
    
    if level and level >= logger.LEVELS.DEBUG and level <= logger.LEVELS.FATAL then
        self.level = level
    else
        self:error("无效的日志级别: " .. tostring(level))
    end
end

-- 检查是否应该记录指定级别的日志
function Logger:should_log(level)
    return level >= self.level
end

-- 格式化日志消息
function Logger:format_message(level, message, ...)
    local level_name = logger.LEVEL_NAMES[level] or "UNKNOWN"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    
    -- 格式化消息
    if select('#', ...) > 0 then
        message = string.format(message, ...)
    end
    
    return string.format("[%s] [%s] [%s] %s", timestamp, level_name, self.name, message)
end

-- 输出日志消息
function Logger:output_message(formatted_message)
    -- 输出到控制台
    print(formatted_message)
    
    -- 输出到文件
    if self.file_handle then
        self.file_handle:write(formatted_message .. "\n")
        self.file_handle:flush()
        
        -- 检查文件大小，如果超过限制则轮转
        local current_pos = self.file_handle:seek("cur")
        if current_pos > self.max_file_size then
            self:rotate_log_file()
        end
    end
end

-- 轮转日志文件
function Logger:rotate_log_file()
    if not self.file_handle then
        return
    end
    
    self.file_handle:close()
    
    -- 备份当前日志文件
    local backup_file = self.output_file .. "." .. os.date("%Y%m%d_%H%M%S")
    os.rename(self.output_file, backup_file)
    
    -- 重新打开日志文件
    self.file_handle = io.open(self.output_file, "a")
    if not self.file_handle then
        print(string.format("ERROR: 无法重新打开日志文件: %s", self.output_file))
    end
end

-- 记录调试日志
function Logger:debug(message, ...)
    if self:should_log(logger.LEVELS.DEBUG) then
        local formatted = self:format_message(logger.LEVELS.DEBUG, message, ...)
        self:output_message(formatted)
    end
end

-- 记录信息日志
function Logger:info(message, ...)
    if self:should_log(logger.LEVELS.INFO) then
        local formatted = self:format_message(logger.LEVELS.INFO, message, ...)
        self:output_message(formatted)
    end
end

-- 记录警告日志
function Logger:warn(message, ...)
    if self:should_log(logger.LEVELS.WARN) then
        local formatted = self:format_message(logger.LEVELS.WARN, message, ...)
        self:output_message(formatted)
    end
end

-- 记录错误日志
function Logger:error(message, ...)
    if self:should_log(logger.LEVELS.ERROR) then
        local formatted = self:format_message(logger.LEVELS.ERROR, message, ...)
        self:output_message(formatted)
    end
end

-- 记录致命错误日志
function Logger:fatal(message, ...)
    if self:should_log(logger.LEVELS.FATAL) then
        local formatted = self:format_message(logger.LEVELS.FATAL, message, ...)
        self:output_message(formatted)
        self:output_message(formatted)
    end
end

-- 记录异常信息
function Logger:exception(err, message, ...)
    local err_msg = tostring(err)
    local traceback = debug.traceback()
    
    if message then
        if select('#', ...) > 0 then
            message = string.format(message, ...)
        end
        err_msg = message .. ": " .. err_msg
    end
    
    self:error("%s\n%s", err_msg, traceback)
end

-- 性能监控日志
function Logger:performance(operation, start_time, end_time, ...)
    local duration = end_time - start_time
    local message = string.format("操作 %s 耗时: %.3f 秒", operation, duration)
    
    if select('#', ...) > 0 then
        message = message .. " " .. string.format(...)
    end
    
    self:info(message)
    return duration
end

-- 关闭日志记录器
function Logger:close()
    if self.file_handle then
        self.file_handle:close()
        self.file_handle = nil
    end
end

-- 全局日志管理器
local LogManager = {}
LogManager.__index = LogManager

function LogManager:new()
    local obj = setmetatable({}, LogManager)
    obj.loggers = {}
    obj.default_config = {
        level = logger.LEVELS.INFO,
        output_file = nil
    }
    return obj
end

-- 获取或创建日志记录器
function LogManager:get_logger(name, config)
    if not name then
        name = "default"
    end
    
    if not self.loggers[name] then
        local merged_config = {}
        for k, v in pairs(self.default_config) do
            merged_config[k] = v
        end
        if config then
            for k, v in pairs(config) do
                merged_config[k] = v
            end
        end
        
        self.loggers[name] = Logger:new(name, merged_config)
    end
    
    return self.loggers[name]
end

-- 设置默认配置
function LogManager:set_default_config(config)
    if config.level then
        self.default_config.level = config.level
    end
    if config.output_file then
        self.default_config.output_file = config.output_file
    end
    if config.max_file_size then
        self.default_config.max_file_size = config.max_file_size
    end
end

-- 关闭所有日志记录器
function LogManager:close_all()
    for name, logger_instance in pairs(self.loggers) do
        logger_instance:close()
    end
    self.loggers = {}
end

-- 全局日志管理器实例
local global_log_manager = LogManager:new()

-- 便捷全局函数
function logger.debug(message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:debug(message, ...)
end

function logger.info(message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:info(message, ...)
end

function logger.warn(message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:warn(message, ...)
end

function logger.error(message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:error(message, ...)
end

function logger.fatal(message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:fatal(message, ...)
end

function logger.exception(err, message, ...)
    local default_logger = global_log_manager:get_logger("default")
    default_logger:exception(err, message, ...)
end

-- 导出
logger.Logger = Logger
logger.LogManager = LogManager
global_log_manager = global_log_manager

return logger