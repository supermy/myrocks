--
-- 公共模块初始化文件
-- 提供统一的公共模块导入接口
--

local commons = {}

-- 导入所有公共模块
commons.config_utils = require "commons.config_utils"
commons.logger = require "commons.logger"
commons.utils = require "commons.utils"
commons.redis_protocol = require "commons.redis_protocol"
commons.error_handler = require "commons.error_handler"

-- 便捷访问函数
function commons.get_config_utils()
    return commons.config_utils
end

function commons.get_logger(name, config)
    return commons.logger.LogManager:get_logger(name, config)
end

function commons.get_utils()
    return commons.utils
end

function commons.get_redis_protocol()
    return commons.redis_protocol
end

function commons.get_error_handler()
    return commons.error_handler
end

-- 初始化函数
function commons.init(config)
    config = config or {}
    
    -- 初始化日志系统
    if config.logger then
        commons.logger.LogManager:set_default_config(config.logger)
    end
    
    -- 初始化错误处理器
    if config.error_handler then
        for error_code, callback in pairs(config.error_handler.callbacks or {}) do
            commons.error_handler.register_callback(error_code, callback)
        end
    end
    
    return true
end

-- 便捷全局函数
function commons.debug(message, ...)
    commons.logger.debug(message, ...)
end

function commons.info(message, ...)
    commons.logger.info(message, ...)
end

function commons.warn(message, ...)
    commons.logger.warn(message, ...)
end

function commons.error(message, ...)
    commons.logger.error(message, ...)
end

function commons.fatal(message, ...)
    commons.logger.fatal(message, ...)
end

function commons.exception(err, message, ...)
    commons.logger.exception(err, message, ...)
end

-- 兼容性函数（用于测试脚本）
function commons.log_info(message, ...)
    commons.logger.info(message, ...)
end

function commons.log_error(message, ...)
    commons.logger.error(message, ...)
end

-- 配置管理便捷函数
function commons.load_config(name, filename)
    return commons.config_utils.load_config(name, filename)
end

function commons.get_config(name)
    return commons.config_utils.get_config(name)
end

function commons.reload_config(name, filename)
    return commons.config_utils.reload_config(name, filename)
end

function commons.get_config()
    -- 返回默认配置或空配置
    return commons.config_utils.global_config_manager.configs or {}
end

-- 工具函数便捷访问
function commons.split(str, delimiter)
    return commons.utils.split(str, delimiter)
end

function commons.trim(str)
    return commons.utils.trim(str)
end

function commons.format_string(format_str, ...)
    return commons.utils.format_string(format_str, ...)
end

function commons.validate_symbol(symbol)
    return commons.utils.validate_symbol(symbol)
end

function commons.validate_data_type(data_type)
    return commons.utils.validate_data_type(data_type)
end

function commons.format_time(timestamp, format)
    return commons.utils.format_timestamp(timestamp, format)
end

-- 错误处理便捷函数
function commons.handle_error(code, message, details)
    return commons.error_handler.handle(code, message, details)
end

function commons.safe_execute(func, error_code, ...)
    return commons.error_handler.safe_execute(func, error_code, ...)
end

function commons.retry_execute(func, max_retries, delay_ms, error_code, ...)
    return commons.error_handler.retry_execute(func, max_retries, delay_ms, error_code, ...)
end

-- 版本信息
commons.VERSION = "1.0.0"
commons.DESCRIPTION = "Stock-TSDB 公共模块库"

-- 版本信息函数
function commons.get_version()
    return commons.VERSION
end

function commons.get_description()
    return commons.DESCRIPTION
end

return commons