--
-- 日志模块
-- 提供多级别日志输出功能
--

local logger = {}

-- 日志级别
logger.DEBUG = 0
logger.INFO = 1
logger.WARN = 2
logger.ERROR = 3
logger.FATAL = 4

-- 日志级别名称
local level_names = {
    [logger.DEBUG] = "DEBUG",
    [logger.INFO] = "INFO",
    [logger.WARN] = "WARN",
    [logger.ERROR] = "ERROR",
    [logger.FATAL] = "FATAL"
}

-- 日志类
local Logger = {}
Logger.__index = Logger

function Logger:new(name, level)
    local obj = setmetatable({}, Logger)
    obj.name = name or "unknown"
    obj.level = level or logger.INFO
    obj.file_handle = nil
    obj.file_name = nil
    obj.max_size = 100 * 1024 * 1024  -- 100MB
    obj.max_files = 10
    obj.enable_console = true
    obj.enable_file = false
    return obj
end

function Logger:set_level(level)
    self.level = level
end

function Logger:set_console(enable)
    self.enable_console = enable
end

function Logger:enable_file(enable, file_name)
    self.enable_file = enable
    if enable and file_name then
        self.file_name = file_name
        self:open_file()
    end
end

function Logger:open_file()
    if self.file_handle then
        self.file_handle:close()
    end
    
    if self.file_name then
        local dir = self.file_name:match("(.*/)")
        if dir then
            os.execute("mkdir -p " .. dir)
        end
        self.file_handle = io.open(self.file_name, "a")
    end
end

function Logger:rotate_file()
    if not self.file_name then
        return
    end
    
    -- 检查文件大小
    local file = io.open(self.file_name, "r")
    if file then
        local size = file:seek("end")
        file:close()
        
        if size > self.max_size then
            -- 轮转日志文件
            for i = self.max_files - 1, 1, -1 do
                local old_name = self.file_name .. "." .. i
                local new_name = self.file_name .. "." .. (i + 1)
                os.rename(old_name, new_name)
            end
            
            os.rename(self.file_name, self.file_name .. ".1")
            self:open_file()
        end
    end
end

function Logger:log(level, message, ...)
    if level < self.level then
        return
    end
    
    local level_name = level_names[level] or "UNKNOWN"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local thread_id = 0  -- Lua中没有线程ID，用0代替
    
    -- 格式化消息
    local formatted_message
    if select('#', ...) > 0 then
        formatted_message = string.format(message, ...)
    else
        formatted_message = message
    end
    
    local log_line = string.format("[%s] [%s] [%s] [%d] %s: %s\n",
        timestamp, level_name, self.name, thread_id, debug.getinfo(2, "n").name or "unknown", formatted_message)
    
    -- 输出到控制台
    if self.enable_console then
        io.write(log_line)
        io.flush()
    end
    
    -- 输出到文件
    if self.enable_file and self.file_handle then
        self.file_handle:write(log_line)
        self.file_handle:flush()
        self:rotate_file()
    end
end

function Logger:debug(message, ...)
    self:log(logger.DEBUG, message, ...)
end

function Logger:info(message, ...)
    self:log(logger.INFO, message, ...)
end

function Logger:warn(message, ...)
    self:log(logger.WARN, message, ...)
end

function Logger:error(message, ...)
    self:log(logger.ERROR, message, ...)
end

function Logger:fatal(message, ...)
    self:log(logger.FATAL, message, ...)
end

function Logger:close()
    if self.file_handle then
        self.file_handle:close()
        self.file_handle = nil
    end
end

-- 日志管理器
local LoggerManager = {}
LoggerManager.__index = LoggerManager

function LoggerManager:new()
    local obj = setmetatable({}, LoggerManager)
    obj.loggers = {}
    obj.default_level = logger.INFO
    obj.enable_console = true
    obj.enable_file = false
    obj.log_dir = nil
    return obj
end

function LoggerManager:create_logger(name, level)
    local logger_obj = Logger:new(name, level or self.default_level)
    logger_obj:set_console(self.enable_console)
    
    if self.enable_file and self.log_dir then
        local file_name = self.log_dir .. "/" .. name .. ".log"
        logger_obj:enable_file(true, file_name)
    end
    
    self.loggers[name] = logger_obj
    return logger_obj
end

function LoggerManager:get_logger(name)
    if not self.loggers[name] then
        return self:create_logger(name)
    end
    return self.loggers[name]
end

function LoggerManager:set_default_level(level)
    self.default_level = level
    for _, logger_obj in pairs(self.loggers) do
        logger_obj:set_level(level)
    end
end

function LoggerManager:enable_console(enable)
    self.enable_console = enable
    for _, logger_obj in pairs(self.loggers) do
        logger_obj:enable_console(enable)
    end
end

function LoggerManager:enable_file(enable, log_dir)
    self.enable_file = enable
    self.log_dir = log_dir
    
    if enable and log_dir then
        os.execute("mkdir -p " .. log_dir)
        for name, logger_obj in pairs(self.loggers) do
            local file_name = log_dir .. "/" .. name .. ".log"
            logger_obj:enable_file(true, file_name)
        end
    end
end

function LoggerManager:close_all()
    for _, logger_obj in pairs(self.loggers) do
        logger_obj:close()
    end
    self.loggers = {}
end

-- 全局日志管理器实例
local global_logger_manager = LoggerManager:new()

-- 便捷函数
function logger.create(name, level)
    return global_logger_manager:create_logger(name, level)
end

function logger.get(name)
    return global_logger_manager:get_logger(name)
end

function logger.set_default_level(level)
    global_logger_manager:set_default_level(level)
end

function logger.enable_console(enable)
    global_logger_manager:enable_console(enable)
end

function logger.enable_file(enable, log_dir)
    global_logger_manager:enable_file(enable, log_dir)
end

function logger.close_all()
    global_logger_manager:close_all()
end

-- 全局日志记录器
local global_logger = logger.create("global")

-- 全局日志函数
function logger.debug(message, ...)
    global_logger:debug(message, ...)
end

function logger.info(message, ...)
    global_logger:info(message, ...)
end

function logger.warn(message, ...)
    global_logger:warn(message, ...)
end

function logger.error(message, ...)
    global_logger:error(message, ...)
end

function logger.fatal(message, ...)
    global_logger:fatal(message, ...)
end

-- 导出函数和类
logger.Logger = Logger
logger.LoggerManager = LoggerManager
logger.global_manager = global_logger_manager

return logger