--
-- 配置管理工具类
-- 提供统一的配置加载、解析、验证功能
--

local config_utils = {}

-- 配置管理器类
local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager:new()
    local obj = setmetatable({}, ConfigManager)
    obj.configs = {}
    obj.config_files = {}
    obj.default_configs = {}
    return obj
end

-- 加载配置文件
function ConfigManager:load_config(name, filename)
    if not name or not filename then
        return false, "配置名称和文件名不能为空"
    end
    
    -- 检查文件是否存在
    local file = io.open(filename, "r")
    if not file then
        return false, "配置文件不存在: " .. filename
    end
    
    local content = file:read("*a")
    file:close()
    
    -- 解析配置内容（支持JSON格式）
    local ok, config = pcall(require("cjson").decode, content)
    if not ok then
        -- 尝试解析为Lua表格式
        local func, err = loadstring("return " .. content)
        if func then
            ok, config = pcall(func)
        end
    end
    
    if not ok or type(config) ~= "table" then
        return false, "配置文件格式错误: " .. filename
    end
    
    self.configs[name] = config
    self.config_files[name] = filename
    
    return true
end

-- 获取配置
function ConfigManager:get_config(name)
    return self.configs[name] or self.default_configs[name]
end

-- 重新加载配置
function ConfigManager:reload_config(name, filename)
    filename = filename or self.config_files[name]
    if not filename then
        return false, "未找到配置文件路径"
    end
    
    return self:load_config(name, filename)
end

-- 设置默认配置
function ConfigManager:set_default(name, default_config)
    if type(default_config) ~= "table" then
        return false, "默认配置必须是表类型"
    end
    
    self.default_configs[name] = default_config
    return true
end

-- 验证配置
function ConfigManager:validate_config(name, required_fields)
    local config = self:get_config(name)
    if not config then
        return false, "配置不存在: " .. name
    end
    
    if required_fields then
        for _, field in ipairs(required_fields) do
            if config[field] == nil then
                return false, "缺少必需字段: " .. field
            end
        end
    end
    
    return true
end

-- 配置合并工具函数
function config_utils.merge_configs(base_config, override_config)
    local result = {}
    
    -- 复制基础配置
    for k, v in pairs(base_config) do
        result[k] = v
    end
    
    -- 合并覆盖配置
    for k, v in pairs(override_config) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = config_utils.merge_configs(result[k], v)
        else
            result[k] = v
        end
    end
    
    return result
end

-- 配置验证工具函数
function config_utils.validate_config_structure(config, schema)
    if type(config) ~= "table" then
        return false, "配置必须是表类型"
    end
    
    if schema then
        for field, field_schema in pairs(schema) do
            local value = config[field]
            local required = field_schema.required or false
            local type_expected = field_schema.type
            
            if required and value == nil then
                return false, "缺少必需字段: " .. field
            end
            
            if value ~= nil and type_expected and type(value) ~= type_expected then
                return false, string.format("字段 %s 类型错误: 期望 %s, 实际 %s", 
                    field, type_expected, type(value))
            end
            
            -- 验证嵌套配置
            if type_expected == "table" and field_schema.schema then
                local ok, err = config_utils.validate_config_structure(value, field_schema.schema)
                if not ok then
                    return false, "字段 " .. field .. " 验证失败: " .. err
                end
            end
        end
    end
    
    return true
end

-- 便捷函数
function config_utils.load_config(name, filename)
    return global_config_manager:load_config(name, filename)
end

function config_utils.get_config(name)
    return global_config_manager:get_config(name)
end

function config_utils.reload_config(name, filename)
    return global_config_manager:reload_config(name, filename)
end

-- 全局配置管理器实例
local global_config_manager = ConfigManager:new()

-- 导出
config_utils.ConfigManager = ConfigManager
config_utils.global_config_manager = global_config_manager

return config_utils