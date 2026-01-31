-- 配置管理器
-- 用于管理RocksDB的配置参数，支持从文件加载、保存到文件等功能

local ConfigManager = {}
ConfigManager.__index = ConfigManager

function ConfigManager:new()
    local obj = setmetatable({}, ConfigManager)
    obj.config = {}
    return obj
end

-- 从文件加载配置
function ConfigManager:load_from_file(file_path)
    -- 检查文件是否存在
    local file = io.open(file_path, "r")
    if not file then
        return false, "配置文件不存在: " .. file_path
    end
    
    local content = file:read("*all")
    file:close()
    
    -- 使用pcall安全执行配置加载
    local success, result = pcall(function()
        -- 加载配置代码
        local chunk = load(content)
        if chunk then
            local loaded_config = chunk()
            if type(loaded_config) == "table" then
                return loaded_config
            else
                -- 如果没有返回表，尝试直接解析内容
                -- 创建一个环境表来存储变量
                local env = {}
                -- 修改加载字符串，使其将变量存储在env表中
                local modified_content = "local config = {}\n" .. content .. "\nreturn config"
                local modified_chunk = load(modified_content, nil, "t", {})
                if modified_chunk then
                    return modified_chunk()
                end
            end
        end
        return nil
    end)
    
    if not success then
        return false, "加载配置失败: " .. result
    end
    
    if result then
        self.config = result
        return true, "配置加载成功"
    else
        return false, "无法解析配置内容"
    end
end

-- 保存配置到文件
function ConfigManager:save_to_file(file_path)
    local file = io.open(file_path, "w")
    if not file then
        return false, "无法创建配置文件: " .. file_path
    end
    
    -- 写入配置头部注释
    file:write("-- RocksDB 配置文件\n")
    file:write("-- 自动生成，请勿手动修改\n\n")
    
    -- 写入配置参数
    local lines = {}
    for key, value in pairs(self.config) do
        local line
        if type(value) == "string" then
            line = string.format("%s = '%s',", key, value)
        elseif type(value) == "boolean" then
            line = string.format("%s = %s,", key, tostring(value))
        elseif type(value) == "number" then
            line = string.format("%s = %s,", key, tostring(value))
        elseif type(value) == "table" then
            -- 简单的表序列化
            line = string.format("%s = {}, -- 表配置", key)
        else
            line = string.format("%s = nil, -- 未知类型", key)
        end
        table.insert(lines, line)
    end
    
    -- 按字母顺序排序配置项
    table.sort(lines)
    
    -- 写入排序后的配置
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    
    file:close()
    return true, "配置已保存到: " .. file_path
end

-- 设置配置参数
function ConfigManager:set(key, value)
    self.config[key] = value
end

-- 获取配置参数
function ConfigManager:get(key, default)
    return self.config[key] or default
end

-- 合并配置
function ConfigManager:merge(other_config)
    if type(other_config) ~= "table" then
        return false, "参数必须是表类型"
    end
    
    for key, value in pairs(other_config) do
        self.config[key] = value
    end
    
    return true, "配置合并成功"
end

-- 获取所有配置
function ConfigManager:get_all()
    -- 返回配置的副本，避免外部直接修改
    local config_copy = {}
    for key, value in pairs(self.config) do
        if type(value) == "table" then
            -- 对表进行深拷贝
            config_copy[key] = {}
            for k, v in pairs(value) do
                config_copy[key][k] = v
            end
        else
            config_copy[key] = value
        end
    end
    return config_copy
end

-- 重置配置
function ConfigManager:reset()
    self.config = {}
    return true, "配置已重置"
end

-- 加载硬件检测模块
function ConfigManager:load_hardware_detector()
    -- 使用pcall安全加载硬件检测器
    local success, err = pcall(function()
        local HardwareDetector = require("hardware_detector")
        return HardwareDetector
    end)
    
    if not success then
        -- 尝试使用简化版硬件检测器
        local fallback_success, HardwareDetector = pcall(function()
            return require("hardware_detector_simple")
        end)
        
        if fallback_success then
            return true, HardwareDetector
        else
            return false, "无法加载硬件检测器: " .. err
        end
    end
    
    return true, err  -- err此时是HardwareDetector
end

-- 生成优化配置
function ConfigManager:generate_optimized_config(data_dir)
    local success, detector_or_err = self:load_hardware_detector()
    
    if not success then
        return false, detector_or_err
    end
    
    -- 创建硬件检测器实例
    local detector = detector_or_err:new()
    
    -- 获取优化参数
    local optimized_params = detector:get_optimized_rocksdb_params(data_dir)
    
    -- 合并到当前配置
    return self:merge(optimized_params)
end

-- 打印配置摘要
function ConfigManager:print_summary()
    print("\n=== 配置摘要 ===")
    
    -- 按类别分组打印
    local categories = {
        basic = {"create_if_missing", "enable_statistics", "stats_dump_period_sec"},
        memory = {"write_buffer_size", "max_write_buffer_number", "block_cache_size"},
        io = {"target_file_size_base", "max_file_size", "bytes_per_sync"},
        performance = {"max_background_compactions", "max_background_flushes"}
    }
    
    for category, keys in pairs(categories) do
        print(string.format("\n[%s]", category:upper()))
        for _, key in ipairs(keys) do
            if self.config[key] ~= nil then
                local value = self.config[key]
                if type(value) == "number" and value > 1024*1024*1024 then
                    -- 转换为GB
                    print(string.format("%s: %.2f GB", key, value/(1024*1024*1024)))
                elseif type(value) == "number" and value > 1024*1024 then
                    -- 转换为MB
                    print(string.format("%s: %.2f MB", key, value/(1024*1024)))
                elseif type(value) == "number" and value > 1024 then
                    -- 转换为KB
                    print(string.format("%s: %.2f KB", key, value/1024))
                else
                    print(string.format("%s: %s", key, tostring(value)))
                end
            end
        end
    end
    
    -- 打印其他配置项
    print("\n[OTHER]")
    local printed = {}
    for _, keys in pairs(categories) do
        for _, key in ipairs(keys) do
            printed[key] = true
        end
    end
    
    for key, value in pairs(self.config) do
        if not printed[key] then
            print(string.format("%s: %s", key, tostring(value)))
        end
    end
    
    print("================\n")
end

return ConfigManager