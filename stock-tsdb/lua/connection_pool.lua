--[[
    连接池管理器
    优化方案4: 实现高效的连接复用和管理
]]

local ConnectionPool = {}
ConnectionPool.__index = ConnectionPool

function ConnectionPool:new(config)
    local obj = setmetatable({}, self)
    
    obj.config = config or {}
    obj.max_pool_size = obj.config.max_pool_size or 20
    obj.min_pool_size = obj.config.min_pool_size or 5
    obj.connection_timeout = obj.config.connection_timeout or 5000      -- 5秒
    obj.idle_timeout = obj.config.idle_timeout or 300000               -- 5分钟
    obj.max_lifetime = obj.config.max_lifetime or 3600000              -- 1小时
    
    -- 连接池
    obj.pools = {}          -- 按目标分组的连接池
    obj.active_connections = {}  -- 活跃连接
    
    -- 统计信息
    obj.stats = {
        total_created = 0,
        total_destroyed = 0,
        total_borrowed = 0,
        total_returned = 0,
        total_timeout = 0,
        current_active = 0,
        current_idle = 0
    }
    
    -- 启动清理线程
    obj:_start_cleanup_timer()
    
    return obj
end

-- 获取连接
function ConnectionPool:borrow_connection(target_id, connection_factory)
    target_id = target_id or "default"
    
    -- 初始化目标连接池
    if not self.pools[target_id] then
        self.pools[target_id] = {
            idle = {},
            active = 0,
            total = 0
        }
    end
    
    local pool = self.pools[target_id]
    
    -- 尝试从空闲池获取连接
    while #pool.idle > 0 do
        local conn = table.remove(pool.idle, 1)
        
        -- 检查连接是否有效
        if self:_is_connection_valid(conn) then
            conn.last_borrowed = os.time() * 1000
            conn.borrow_count = conn.borrow_count + 1
            
            self.active_connections[conn.id] = conn
            pool.active = pool.active + 1
            
            self.stats.total_borrowed = self.stats.total_borrowed + 1
            self.stats.current_active = self.stats.current_active + 1
            self.stats.current_idle = self.stats.current_idle - 1
            
            return conn
        else
            -- 连接无效，销毁
            self:_destroy_connection(conn)
            pool.total = pool.total - 1
        end
    end
    
    -- 空闲池为空，创建新连接
    if pool.total < self.max_pool_size then
        local conn, err = self:_create_connection(target_id, connection_factory)
        if conn then
            self.active_connections[conn.id] = conn
            pool.active = pool.active + 1
            pool.total = pool.total + 1
            
            self.stats.total_created = self.stats.total_created + 1
            self.stats.total_borrowed = self.stats.total_borrowed + 1
            self.stats.current_active = self.stats.current_active + 1
            
            return conn
        else
            return nil, err
        end
    end
    
    -- 连接池已满
    return nil, "Connection pool exhausted for target: " .. target_id
end

-- 归还连接
function ConnectionPool:return_connection(conn)
    if not conn or not conn.id then
        return false
    end
    
    -- 从活跃连接中移除
    self.active_connections[conn.id] = nil
    
    local pool = self.pools[conn.target_id]
    if pool then
        pool.active = pool.active - 1
    end
    
    -- 检查连接是否仍然有效
    if not self:_is_connection_valid(conn) then
        self:_destroy_connection(conn)
        if pool then
            pool.total = pool.total - 1
        end
        self.stats.current_active = self.stats.current_active - 1
        return true
    end
    
    -- 重置连接状态
    conn.last_returned = os.time() * 1000
    conn.in_use = false
    
    -- 归还到空闲池
    if pool then
        table.insert(pool.idle, conn)
        self.stats.total_returned = self.stats.total_returned + 1
        self.stats.current_active = self.stats.current_active - 1
        self.stats.current_idle = self.stats.current_idle + 1
    end
    
    return true
end

-- 创建连接
function ConnectionPool:_create_connection(target_id, connection_factory)
    if not connection_factory then
        -- 默认连接工厂（模拟）
        connection_factory = function()
            return {
                id = tostring(os.time()) .. "_" .. tostring(math.random(10000)),
                target_id = target_id,
                created_at = os.time() * 1000,
                last_used = os.time() * 1000,
                last_borrowed = 0,
                last_returned = 0,
                borrow_count = 0,
                in_use = true,
                is_valid = true
            }
        end
    end
    
    local conn, err = connection_factory()
    if not conn then
        return nil, err or "Failed to create connection"
    end
    
    conn.target_id = target_id
    
    return conn
end

-- 销毁连接
function ConnectionPool:_destroy_connection(conn)
    if conn and conn.close then
        pcall(function() conn:close() end)
    end
    
    self.stats.total_destroyed = self.stats.total_destroyed + 1
end

-- 检查连接是否有效
function ConnectionPool:_is_connection_valid(conn)
    if not conn then
        return false
    end
    
    -- 检查连接是否被标记为无效
    if conn.is_valid == false then
        return false
    end
    
    -- 检查连接是否超时
    local current_time = os.time() * 1000
    if conn.last_borrowed > 0 and (current_time - conn.last_borrowed) > self.connection_timeout then
        conn.is_valid = false
        self.stats.total_timeout = self.stats.total_timeout + 1
        return false
    end
    
    -- 检查连接生命周期
    if (current_time - conn.created_at) > self.max_lifetime then
        conn.is_valid = false
        return false
    end
    
    return true
end

-- 关闭连接池
function ConnectionPool:close()
    -- 关闭所有活跃连接
    for _, conn in pairs(self.active_connections) do
        self:_destroy_connection(conn)
    end
    self.active_connections = {}
    
    -- 关闭所有空闲连接
    for target_id, pool in pairs(self.pools) do
        for _, conn in ipairs(pool.idle) do
            self:_destroy_connection(conn)
        end
        pool.idle = {}
        pool.active = 0
        pool.total = 0
    end
    
    print("[连接池] 连接池已关闭")
    return true
end

-- 获取连接池统计
function ConnectionPool:get_stats()
    local pool_stats = {}
    
    for target_id, pool in pairs(self.pools) do
        pool_stats[target_id] = {
            idle_count = #pool.idle,
            active_count = pool.active,
            total_count = pool.total
        }
    end
    
    return {
        global_stats = self.stats,
        pool_stats = pool_stats,
        config = {
            max_pool_size = self.max_pool_size,
            min_pool_size = self.min_pool_size,
            connection_timeout = self.connection_timeout,
            idle_timeout = self.idle_timeout
        }
    }
end

-- 启动清理定时器
function ConnectionPool:_start_cleanup_timer()
    -- 在实际实现中，这里应该启动一个定时器线程
    -- 简化实现：记录启动时间
    self.cleanup_started = os.time()
end

-- 清理过期连接
function ConnectionPool:cleanup_expired_connections()
    local current_time = os.time() * 1000
    local cleaned_count = 0
    
    for target_id, pool in pairs(self.pools) do
        local i = 1
        while i <= #pool.idle do
            local conn = pool.idle[i]
            
            -- 检查空闲超时
            if conn.last_returned > 0 and (current_time - conn.last_returned) > self.idle_timeout then
                self:_destroy_connection(conn)
                table.remove(pool.idle, i)
                pool.total = pool.total - 1
                cleaned_count = cleaned_count + 1
                self.stats.current_idle = self.stats.current_idle - 1
            else
                i = i + 1
            end
        end
    end
    
    return cleaned_count
end

return ConnectionPool
