--
-- 配置模块
-- 提供INI格式配置文件解析功能
--

local config = {}

-- 配置类
local Config = {}
Config.__index = Config

function Config:new()
    local obj = setmetatable({}, Config)
    obj.data = {}
    obj.sections = {}
    return obj
end

function Config:load(filename)
    -- 加载配置文件
    local file = io.open(filename, "r")
    if not file then
        return false, "无法打开配置文件: " .. filename
    end
    
    local current_section = "default"
    self.data[current_section] = {}
    
    for line in file:lines() do
        -- 移除注释
        local comment_pos = line:find("#")
        if comment_pos then
            line = line:sub(1, comment_pos - 1)
        end
        
        -- 移除前后空格
        line = line:match("^%s*(.-)%s*$")
        
        -- 跳过空行
        if line ~= "" then
            -- 检查是否是节标题
            local section = line:match("^%[([^%]]+)%]$")
            if section then
                current_section = section
                self.data[current_section] = {}
                self.sections[section] = true
            else
                -- 解析键值对
                local key, value = line:match("^([^=]+)=(.*)$")
                if key and value then
                    key = key:match("^%s*(.-)%s*$")
                    value = value:match("^%s*(.-)%s*$")
                    self.data[current_section][key] = value
                end
            end
        end
    end
    
    file:close()
    return true
end

function Config:get_string(section, key, default)
    -- 获取字符串值
    if self.data[section] and self.data[section][key] then
        return self.data[section][key]
    end
    return default
end

function Config:get_int(section, key, default)
    -- 获取整数值
    local value = self:get_string(section, key, "")
    if value ~= "" then
        return tonumber(value) or default
    end
    return default
end

function Config:get_float(section, key, default)
    -- 获取浮点数值
    local value = self:get_string(section, key, "")
    if value ~= "" then
        return tonumber(value) or default
    end
    return default
end

function Config:get_bool(section, key, default)
    -- 获取布尔值
    local value = self:get_string(section, key, "")
    if value ~= "" then
        value = value:lower()
        return value == "true" or value == "yes" or value == "1" or value == "on"
    end
    return default
end

function Config:get_table(section, key, default)
    -- 获取表格值（逗号分隔）
    local value = self:get_string(section, key, "")
    if value ~= "" then
        local result = {}
        for item in value:gmatch("([^,]+)") do
            item = item:match("^%s*(.-)%s*$")
            if item ~= "" then
                table.insert(result, item)
            end
        end
        return result
    end
    return default or {}
end

function Config:reload(filename)
    -- 重新加载配置
    self.data = {}
    self.sections = {}
    return self:load(filename)
end

function Config:get_sections()
    -- 获取所有节
    local sections = {}
    for section, _ in pairs(self.sections) do
        table.insert(sections, section)
    end
    return sections
end

function Config:get_keys(section)
    -- 获取指定节的所有键
    local keys = {}
    if self.data[section] then
        for key, _ in pairs(self.data[section]) do
            table.insert(keys, key)
        end
    end
    return keys
end

-- 配置加载函数
function config.load_config(filename)
    local cfg = Config:new()
    local success, error = cfg:load(filename)
    if success then
        return cfg
    else
        return nil, error
    end
end

-- 配置管理器
local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager:new()
    local obj = setmetatable({}, ConfigManager)
    obj.configs = {}
    return obj
end

function ConfigManager:load_config(name, filename)
    -- 加载配置文件
    local cfg, error = config.load_config(filename)
    if cfg then
        self.configs[name] = cfg
        return cfg
    end
    return nil, error
end

function ConfigManager:get_config(name)
    -- 获取配置
    return self.configs[name]
end

function ConfigManager:reload_config(name, filename)
    -- 重新加载配置
    local cfg = self.configs[name]
    if cfg then
        return cfg:reload(filename)
    end
    return false, "配置不存在: " .. name
end

-- 全局配置管理器实例
local global_config_manager = ConfigManager:new()

-- 便捷函数
function config.load(name, filename)
    return global_config_manager:load_config(name, filename)
end

function config.get(name)
    return global_config_manager:get_config(name)
end

function config.reload(name, filename)
    return global_config_manager:reload_config(name, filename)
end

-- 导出函数和类
config.Config = Config
config.ConfigManager = ConfigManager
config.global_manager = global_config_manager

return config