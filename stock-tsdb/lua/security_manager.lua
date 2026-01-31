--[[
    安全管理器
    优化方案5: 实现身份认证、权限控制和数据加密
]]

local SecurityManager = {}
SecurityManager.__index = SecurityManager

-- 权限级别枚举
local PERMISSIONS = {
    READ = "read",
    WRITE = "write",
    DELETE = "delete",
    ADMIN = "admin"
}

-- 角色定义
local ROLES = {
    GUEST = {PERMISSIONS.READ},
    USER = {PERMISSIONS.READ, PERMISSIONS.WRITE},
    OPERATOR = {PERMISSIONS.READ, PERMISSIONS.WRITE, PERMISSIONS.DELETE},
    ADMIN = {PERMISSIONS.READ, PERMISSIONS.WRITE, PERMISSIONS.DELETE, PERMISSIONS.ADMIN}
}

function SecurityManager:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.enabled = obj.config.enabled ~= false
    obj.token_expiry = obj.config.token_expiry or 3600  -- 1小时
    obj.max_login_attempts = obj.config.max_login_attempts or 5
    obj.lockout_duration = obj.config.lockout_duration or 300  -- 5分钟
    
    -- 用户存储
    obj.users = {}              -- 用户信息
    obj.sessions = {}           -- 活跃会话
    obj.tokens = {}             -- 令牌存储
    obj.failed_attempts = {}    -- 登录失败记录
    obj.locked_accounts = {}    -- 锁定账户
    
    -- 审计日志
    obj.audit_logs = {}
    obj.max_audit_logs = obj.config.max_audit_logs or 10000
    
    -- API密钥
    obj.api_keys = {}
    
    -- 统计信息
    obj.stats = {
        total_logins = 0,
        failed_logins = 0,
        total_sessions = 0,
        active_sessions = 0,
        audit_events = 0
    }
    
    return obj
end

-- 注册用户
function SecurityManager:register_user(username, password, role, metadata)
    if not self.enabled then
        return true
    end
    
    if self.users[username] then
        return false, "用户已存在"
    end
    
    -- 验证密码强度
    local valid, err = self:_validate_password_strength(password)
    if not valid then
        return false, err
    end
    
    -- 创建用户
    self.users[username] = {
        username = username,
        password_hash = self:_hash_password(password),
        role = role or "USER",
        metadata = metadata or {},
        created_at = os.time(),
        last_login = 0,
        login_count = 0,
        is_active = true
    }
    
    self:_log_audit("USER_REGISTERED", username, "用户注册成功")
    print(string.format("[安全管理] 用户注册成功: %s", username))
    
    return true
end

-- 用户登录
function SecurityManager:login(username, password, client_info)
    if not self.enabled then
        return true, "security_disabled"
    end
    
    -- 检查账户是否被锁定
    if self:_is_account_locked(username) then
        self:_log_audit("LOGIN_FAILED", username, "账户被锁定", client_info)
        return false, "账户被锁定，请稍后重试"
    end
    
    local user = self.users[username]
    if not user then
        self:_record_failed_attempt(username)
        self:_log_audit("LOGIN_FAILED", username, "用户不存在", client_info)
        return false, "用户名或密码错误"
    end
    
    if not user.is_active then
        self:_log_audit("LOGIN_FAILED", username, "账户已禁用", client_info)
        return false, "账户已禁用"
    end
    
    -- 验证密码
    if not self:_verify_password(password, user.password_hash) then
        self:_record_failed_attempt(username)
        self.stats.failed_logins = self.stats.failed_logins + 1
        self:_log_audit("LOGIN_FAILED", username, "密码错误", client_info)
        return false, "用户名或密码错误"
    end
    
    -- 清除失败记录
    self.failed_attempts[username] = nil
    
    -- 更新用户信息
    user.last_login = os.time()
    user.login_count = user.login_count + 1
    
    -- 创建会话
    local session = self:_create_session(username, client_info)
    
    self.stats.total_logins = self.stats.total_logins + 1
    self.stats.active_sessions = self.stats.active_sessions + 1
    
    self:_log_audit("LOGIN_SUCCESS", username, "登录成功", client_info)
    print(string.format("[安全管理] 用户登录成功: %s", username))
    
    return true, session.token, session
end

-- 用户登出
function SecurityManager:logout(token)
    if not self.enabled then
        return true
    end
    
    local session = self.sessions[token]
    if session then
        self.sessions[token] = nil
        self.stats.active_sessions = self.stats.active_sessions - 1
        
        self:_log_audit("LOGOUT", session.username, "用户登出")
        print(string.format("[安全管理] 用户登出: %s", session.username))
    end
    
    return true
end

-- 验证令牌
function SecurityManager:validate_token(token)
    if not self.enabled then
        return true, {username = "anonymous", role = "ADMIN"}
    end
    
    local session = self.sessions[token]
    if not session then
        return false, "无效的令牌"
    end
    
    -- 检查令牌是否过期
    if os.time() > session.expires_at then
        self.sessions[token] = nil
        self.stats.active_sessions = self.stats.active_sessions - 1
        return false, "令牌已过期"
    end
    
    -- 刷新令牌过期时间
    session.expires_at = os.time() + self.token_expiry
    
    local user = self.users[session.username]
    return true, {
        username = session.username,
        role = user and user.role or "GUEST",
        permissions = ROLES[user and user.role or "GUEST"]
    }
end

-- 检查权限
function SecurityManager:check_permission(token, permission, resource)
    if not self.enabled then
        return true
    end
    
    local valid, session_info = self:validate_token(token)
    if not valid then
        return false, session_info
    end
    
    local user_permissions = session_info.permissions
    
    -- 检查是否具有ADMIN权限
    for _, p in ipairs(user_permissions) do
        if p == PERMISSIONS.ADMIN then
            return true
        end
    end
    
    -- 检查特定权限
    for _, p in ipairs(user_permissions) do
        if p == permission then
            return true
        end
    end
    
    return false, "权限不足"
end

-- 生成API密钥
function SecurityManager:generate_api_key(username, permissions, expiry_days)
    if not self.enabled then
        return "disabled"
    end
    
    local api_key = self:_generate_random_token(32)
    local expires_at = expiry_days and (os.time() + expiry_days * 86400) or nil
    
    self.api_keys[api_key] = {
        username = username,
        permissions = permissions or {PERMISSIONS.READ},
        created_at = os.time(),
        expires_at = expires_at,
        is_active = true,
        usage_count = 0
    }
    
    self:_log_audit("API_KEY_GENERATED", username, "生成API密钥")
    print(string.format("[安全管理] API密钥生成: %s", username))
    
    return api_key
end

-- 验证API密钥
function SecurityManager:validate_api_key(api_key)
    if not self.enabled then
        return true, {username = "anonymous", permissions = ROLES.ADMIN}
    end
    
    local key_info = self.api_keys[api_key]
    if not key_info then
        return false, "无效的API密钥"
    end
    
    if not key_info.is_active then
        return false, "API密钥已禁用"
    end
    
    if key_info.expires_at and os.time() > key_info.expires_at then
        return false, "API密钥已过期"
    end
    
    key_info.usage_count = key_info.usage_count + 1
    
    return true, {
        username = key_info.username,
        permissions = key_info.permissions
    }
end

-- 加密数据
function SecurityManager:encrypt(data, key)
    -- 简化实现：使用简单的异或加密
    -- 实际生产环境应该使用AES等标准加密算法
    
    if not key then
        key = self.config.encryption_key or "default_key"
    end
    
    local encrypted = {}
    local key_bytes = {string.byte(key, 1, -1)}
    local data_bytes = {string.byte(data, 1, -1)}
    
    for i, byte in ipairs(data_bytes) do
        local key_byte = key_bytes[(i - 1) % #key_bytes + 1]
        table.insert(encrypted, string.char(bit.bxor(byte, key_byte)))
    end
    
    return table.concat(encrypted)
end

-- 解密数据
function SecurityManager:decrypt(encrypted_data, key)
    -- 异或加密是对称的，加密和解密使用相同操作
    return self:encrypt(encrypted_data, key)
end

-- 获取审计日志
function SecurityManager:get_audit_logs(options)
    options = options or {}
    local logs = {}
    
    for _, log in ipairs(self.audit_logs) do
        local include = true
        
        if options.username and log.username ~= options.username then
            include = false
        end
        
        if options.event_type and log.event_type ~= options.event_type then
            include = false
        end
        
        if options.start_time and log.timestamp < options.start_time then
            include = false
        end
        
        if options.end_time and log.timestamp > options.end_time then
            include = false
        end
        
        if include then
            table.insert(logs, log)
        end
        
        if options.limit and #logs >= options.limit then
            break
        end
    end
    
    return logs
end

-- 获取统计信息
function SecurityManager:get_stats()
    return {
        stats = self.stats,
        total_users = self:_count_table(self.users),
        total_api_keys = self:_count_table(self.api_keys),
        locked_accounts = self:_count_table(self.locked_accounts),
        enabled = self.enabled
    }
end

-- ==================== 私有方法 ====================

-- 验证密码强度
function SecurityManager:_validate_password_strength(password)
    if #password < 8 then
        return false, "密码长度至少8位"
    end
    
    -- 检查是否包含数字
    if not string.match(password, "%d") then
        return false, "密码必须包含数字"
    end
    
    -- 检查是否包含字母
    if not string.match(password, "%a") then
        return false, "密码必须包含字母"
    end
    
    return true
end

-- 哈希密码
function SecurityManager:_hash_password(password)
    -- 简化实现：实际应该使用bcrypt等标准算法
    local hash = password  -- 占位实现
    return hash
end

-- 验证密码
function SecurityManager:_verify_password(password, hash)
    return self:_hash_password(password) == hash
end

-- 创建会话
function SecurityManager:_create_session(username, client_info)
    local token = self:_generate_random_token(32)
    local now = os.time()
    
    local session = {
        token = token,
        username = username,
        created_at = now,
        expires_at = now + self.token_expiry,
        client_info = client_info or {},
        last_activity = now
    }
    
    self.sessions[token] = session
    self.stats.total_sessions = self.stats.total_sessions + 1
    
    return session
end

-- 生成随机令牌
function SecurityManager:_generate_random_token(length)
    length = length or 32
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local token = {}
    
    for i = 1, length do
        local idx = math.random(1, #chars)
        table.insert(token, string.sub(chars, idx, idx))
    end
    
    return table.concat(token)
end

-- 检查账户是否被锁定
function SecurityManager:_is_account_locked(username)
    local lock_info = self.locked_accounts[username]
    if not lock_info then
        return false
    end
    
    -- 检查锁定是否已过期
    if os.time() > lock_info.locked_until then
        self.locked_accounts[username] = nil
        return false
    end
    
    return true
end

-- 记录失败尝试
function SecurityManager:_record_failed_attempt(username)
    self.failed_attempts[username] = (self.failed_attempts[username] or 0) + 1
    
    -- 检查是否需要锁定账户
    if self.failed_attempts[username] >= self.max_login_attempts then
        self.locked_accounts[username] = {
            locked_at = os.time(),
            locked_until = os.time() + self.lockout_duration,
            failed_attempts = self.failed_attempts[username]
        }
        
        print(string.format("[安全管理] 账户锁定: %s", username))
        self:_log_audit("ACCOUNT_LOCKED", username, "多次登录失败，账户已锁定")
    end
end

-- 记录审计日志
function SecurityManager:_log_audit(event_type, username, description, client_info)
    local log_entry = {
        timestamp = os.time(),
        event_type = event_type,
        username = username,
        description = description,
        client_info = client_info or {},
        id = tostring(os.time()) .. "_" .. tostring(math.random(10000))
    }
    
    table.insert(self.audit_logs, 1, log_entry)
    self.stats.audit_events = self.stats.audit_events + 1
    
    -- 限制日志数量
    while #self.audit_logs > self.max_audit_logs do
        table.remove(self.audit_logs)
    end
end

-- 统计表元素数量
function SecurityManager:_count_table(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

return SecurityManager
