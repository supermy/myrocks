--[[
    高级配置管理器
    优化方案5: 实现统一配置管理、动态更新和版本控制
]]

local ConfigManagerAdvanced = {}
ConfigManagerAdvanced.__index = ConfigManagerAdvanced

function ConfigManagerAdvanced:new(config)
    local obj = setmetatable({}, self)
    
    obj.configs = {}           -- 配置存储
    obj.validators = {}        -- 配置验证器
    obj.watchers = {}          -- 配置变更监听器
    obj.history = {}           -- 配置历史版本
    obj.schemas = {}           -- 配置模式定义
    
    obj.config_file = config and config.config_file or "config/app.json"
    obj.auto_save = config and config.auto_save ~= false
    obj.max_history = config and config.max_history or 50
    
    -- 统计信息
    obj.stats = {
        total_updates = 0,
        total_validations = 0,
        failed_validations = 0,
        watcher_calls = 0
    }
    
    return obj
end

-- 加载配置
function ConfigManagerAdvanced:load(filepath)
    filepath = filepath or self.config_file
    
    local file = io.open(filepath, "r")
    if not file then
        print(string.format("[配置管理] 配置文件不存在: %s", filepath))
        return false
    end
    
    local content = file:read("*a")
    file:close()
    
    -- 解析JSON（简化实现）
    local success, configs = pcall(function()
        -- 这里应该使用JSON解析库
        -- 简化实现：假设配置是Lua表格式
        return loadstring("return " .. content)()
    end)
    
    if success and configs then
        self.configs = configs
        print(string.format("[配置管理] 成功加载配置: %s", filepath))
        return true
    else
        print(string.format("[配置管理-错误] 配置解析失败: %s", filepath))
        return false
    end
end

-- 保存配置
function ConfigManagerAdvanced:save(filepath)
    filepath = filepath or self.config_file
    
    -- 序列化配置（简化实现）
    local content = self:_serialize_config(self.configs)
    
    local file = io.open(filepath, "w")
    if not file then
        return false, "无法打开文件写入"
    end
    
    file:write(content)
    file:close()
    
    print(string.format("[配置管理] 配置已保存: %s", filepath))
    return true
end

-- 获取配置
function ConfigManagerAdvanced:get(key, default_value)
    local keys = self:_split_key(key)
    local value = self.configs
    
    for _, k in ipairs(keys) do
        if type(value) ~= "table" then
            return default_value
        end
        value = value[k]
        if value == nil then
            return default_value
        end
    end
    
    return value
end

-- 设置配置
function ConfigManagerAdvanced:set(key, value, options)
    options = options or {}
    
    -- 验证配置
    if not options.skip_validation then
        local valid, err = self:validate(key, value)
        if not valid then
            print(string.format("[配置管理-错误] 配置验证失败: %s", err))
            return false, err
        end
    end
    
    -- 保存历史版本
    self:_save_history(key)
    
    -- 设置新值
    local keys = self:_split_key(key)
    local target = self.configs
    
    for i = 1, #keys - 1 do
        local k = keys[i]
        if type(target[k]) ~= "table" then
            target[k] = {}
        end
        target = target[k]
    end
    
    local old_value = target[keys[#keys]]
    target[keys[#keys]] = value
    
    self.stats.total_updates = self.stats.total_updates + 1
    
    -- 通知监听器
    self:_notify_watchers(key, old_value, value)
    
    -- 自动保存
    if self.auto_save and not options.skip_save then
        self:save()
    end
    
    print(string.format("[配置管理] 配置已更新: %s", key))
    return true
end

-- 批量设置配置
function ConfigManagerAdvanced:set_batch(updates, options)
    options = options or {}
    local success_count = 0
    
    for key, value in pairs(updates) do
        local success = self:set(key, value, {skip_save = true, skip_validation = options.skip_validation})
        if success then
            success_count = success_count + 1
        end
    end
    
    -- 批量保存
    if self.auto_save and not options.skip_save then
        self:save()
    end
    
    print(string.format("[配置管理] 批量更新完成: %d/%d", success_count, #updates))
    return success_count
end

-- 注册配置验证器
function ConfigManagerAdvanced:register_validator(key, validator)
    self.validators[key] = validator
    print(string.format("[配置管理] 注册验证器: %s", key))
    return true
end

-- 验证配置
function ConfigManagerAdvanced:validate(key, value)
    self.stats.total_validations = self.stats.total_validations + 1
    
    -- 查找适用的验证器
    local validator = self.validators[key]
    
    -- 如果没有特定验证器，尝试通配符验证器
    if not validator then
        for pattern, v in pairs(self.validators) do
            if string.match(key, pattern) then
                validator = v
                break
            end
        end
    end
    
    if validator then
        local valid, err = validator(value)
        if not valid then
            self.stats.failed_validations = self.stats.failed_validations + 1
            return false, err
        end
    end
    
    return true
end

-- 注册配置变更监听器
function ConfigManagerAdvanced:register_watcher(key_pattern, callback)
    if not self.watchers[key_pattern] then
        self.watchers[key_pattern] = {}
    end
    
    table.insert(self.watchers[key_pattern], callback)
    print(string.format("[配置管理] 注册监听器: %s", key_pattern))
    return true
end

-- 通知监听器
function ConfigManagerAdvanced:_notify_watchers(key, old_value, new_value)
    for pattern, callbacks in pairs(self.watchers) do
        if string.match(key, pattern) then
            for _, callback in ipairs(callbacks) do
                local success, err = pcall(callback, key, old_value, new_value)
                if not success then
                    print(string.format("[配置管理-警告] 监听器执行失败: %s", err))
                end
                self.stats.watcher_calls = self.stats.watcher_calls + 1
            end
        end
    end
end

-- 保存历史版本
function ConfigManagerAdvanced:_save_history(key)
    local history_entry = {
        timestamp = os.time(),
        key = key,
        value = self:get(key),
        configs_snapshot = self:_deep_copy(self.configs)
    }
    
    table.insert(self.history, 1, history_entry)
    
    -- 限制历史记录数量
    while #self.history > self.max_history do
        table.remove(self.history)
    end
end

-- 回滚配置
function ConfigManagerAdvanced:rollback(steps)
    steps = steps or 1
    
    if #self.history < steps then
        return false, "历史记录不足"
    end
    
    local target_history = self.history[steps]
    self.configs = self:_deep_copy(target_history.configs_snapshot)
    
    -- 移除已回滚的历史记录
    for i = 1, steps do
        table.remove(self.history, 1)
    end
    
    -- 保存回滚后的配置
    if self.auto_save then
        self:save()
    end
    
    print(string.format("[配置管理] 配置已回滚 %d 步", steps))
    return true
end

-- 获取配置历史
function ConfigManagerAdvanced:get_history(key, limit)
    limit = limit or 10
    local result = {}
    
    for _, entry in ipairs(self.history) do
        if not key or entry.key == key then
            table.insert(result, entry)
            if #result >= limit then
                break
            end
        end
    end
    
    return result
end

-- 导出配置
function ConfigManagerAdvanced:export(format)
    format = format or "json"
    
    if format == "json" then
        return self:_serialize_config(self.configs)
    elseif format == "lua" then
        return self:_serialize_lua(self.configs)
    else
        return nil, "不支持的格式"
    end
end

-- 导入配置
function ConfigManagerAdvanced:import(data, format, options)
    format = format or "json"
    options = options or {}
    
    local configs
    if format == "json" then
        -- 简化实现
        configs = loadstring("return " .. data)()
    elseif format == "lua" then
        configs = loadstring(data)()
    else
        return false, "不支持的格式"
    end
    
    if not options.merge then
        self.configs = {}
    end
    
    -- 合并配置
    for key, value in pairs(configs) do
        self:set(key, value, {skip_validation = options.skip_validation})
    end
    
    print(string.format("[配置管理] 配置导入完成"))
    return true
end

-- 获取统计信息
function ConfigManagerAdvanced:get_stats()
    return {
        stats = self.stats,
        config_count = self:_count_configs(self.configs),
        validator_count = self:_count_table(self.validators),
        watcher_count = self:_count_table(self.watchers),
        history_count = #self.history
    }
end

-- ==================== 私有方法 ====================

-- 分割配置键
function ConfigManagerAdvanced:_split_key(key)
    local keys = {}
    for k in string.gmatch(key, "[^.]+") do
        table.insert(keys, k)
    end
    return keys
end

-- 深拷贝表
function ConfigManagerAdvanced:_deep_copy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in next, orig, nil do
            copy[self:_deep_copy(k)] = self:_deep_copy(v)
        end
        setmetatable(copy, self:_deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- 序列化配置
function ConfigManagerAdvanced:_serialize_config(config, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local parts = {}
    
    if type(config) ~= "table" then
        return tostring(config)
    end
    
    table.insert(parts, "{")
    
    for k, v in pairs(config) do
        local key_str = type(k) == "string" and k or "[" .. tostring(k) .. "]"
        local value_str
        
        if type(v) == "table" then
            value_str = self:_serialize_config(v, indent + 1)
        elseif type(v) == "string" then
            value_str = string.format("%q", v)
        else
            value_str = tostring(v)
        end
        
        table.insert(parts, indent_str .. "  " .. key_str .. " = " .. value_str .. ",")
    end
    
    table.insert(parts, indent_str .. "}")
    
    return table.concat(parts, "\n")
end

-- 序列化为Lua格式
function ConfigManagerAdvanced:_serialize_lua(config)
    return "return " .. self:_serialize_config(config)
end

-- 统计配置数量
function ConfigManagerAdvanced:_count_configs(config, count)
    count = count or 0
    
    if type(config) ~= "table" then
        return count + 1
    end
    
    for _, v in pairs(config) do
        if type(v) == "table" then
            count = self:_count_configs(v, count)
        else
            count = count + 1
        end
    end
    
    return count
end

-- 统计表元素数量
function ConfigManagerAdvanced:_count_table(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

return ConfigManagerAdvanced
