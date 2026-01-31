--[[
    LRU缓存实现
    P0优化: 替代简单table，实现O(1)淘汰和TTL过期
]]

local LRUCache = {}
LRUCache.__index = LRUCache

function LRUCache:new(options)
    local obj = setmetatable({}, self)
    
    options = options or {}
    obj.max_size = options.max_size or 1000
    obj.default_ttl = options.default_ttl or 300  -- 默认5分钟
    
    -- 双向链表节点
    obj.head = nil  -- 最新
    obj.tail = nil  -- 最旧
    
    -- 哈希表存储节点
    obj.nodes = {}
    obj.size = 0
    
    -- 统计信息
    obj.stats = {
        hits = 0,
        misses = 0,
        evictions = 0,
        expired = 0
    }
    
    return obj
end

-- 创建链表节点
local function create_node(key, value, ttl)
    return {
        key = key,
        value = value,
        prev = nil,
        next = nil,
        expires_at = ttl and (os.time() + ttl) or nil
    }
end

-- 将节点移到头部（最新）
function LRUCache:_move_to_head(node)
    if node == self.head then
        return
    end
    
    -- 从当前位置移除
    if node.prev then
        node.prev.next = node.next
    end
    if node.next then
        node.next.prev = node.prev
    end
    
    if node == self.tail then
        self.tail = node.prev
    end
    
    -- 插入头部
    node.prev = nil
    node.next = self.head
    
    if self.head then
        self.head.prev = node
    end
    
    self.head = node
    
    if not self.tail then
        self.tail = node
    end
end

-- 移除尾部节点（最旧）
function LRUCache:_remove_tail()
    if not self.tail then
        return nil
    end
    
    local node = self.tail
    
    if node.prev then
        node.prev.next = nil
        self.tail = node.prev
    else
        -- 只有一个节点
        self.head = nil
        self.tail = nil
    end
    
    self.nodes[node.key] = nil
    self.size = self.size - 1
    
    return node
end

-- 检查节点是否过期
function LRUCache:_is_expired(node)
    if not node.expires_at then
        return false
    end
    return os.time() > node.expires_at
end

-- 清理过期节点
function LRUCache:_cleanup_expired()
    local current = self.tail
    while current do
        local prev = current.prev
        if self:_is_expired(current) then
            -- 移除过期节点
            if current.prev then
                current.prev.next = current.next
            end
            if current.next then
                current.next.prev = current.prev
            end
            if current == self.tail then
                self.tail = current.prev
            end
            if current == self.head then
                self.head = current.next
            end
            
            self.nodes[current.key] = nil
            self.size = self.size - 1
            self.stats.expired = self.stats.expired + 1
        end
        current = prev
    end
end

-- 获取值
function LRUCache:get(key)
    -- 定期清理过期节点（每100次访问）
    if (self.stats.hits + self.stats.misses) % 100 == 0 then
        self:_cleanup_expired()
    end
    
    local node = self.nodes[key]
    
    if not node then
        self.stats.misses = self.stats.misses + 1
        return nil
    end
    
    -- 检查是否过期
    if self:_is_expired(node) then
        -- 移除过期节点
        if node.prev then
            node.prev.next = node.next
        end
        if node.next then
            node.next.prev = node.prev
        end
        if node == self.tail then
            self.tail = node.prev
        end
        if node == self.head then
            self.head = node.next
        end
        
        self.nodes[key] = nil
        self.size = self.size - 1
        self.stats.expired = self.stats.expired + 1
        self.stats.misses = self.stats.misses + 1
        return nil
    end
    
    -- 移到头部
    self:_move_to_head(node)
    self.stats.hits = self.stats.hits + 1
    
    return node.value
end

-- 设置值
function LRUCache:set(key, value, ttl)
    ttl = ttl or self.default_ttl
    
    local node = self.nodes[key]
    
    if node then
        -- 更新现有节点
        node.value = value
        node.expires_at = ttl and (os.time() + ttl) or nil
        self:_move_to_head(node)
    else
        -- 创建新节点
        node = create_node(key, value, ttl)
        
        -- 插入头部
        node.next = self.head
        if self.head then
            self.head.prev = node
        end
        self.head = node
        
        if not self.tail then
            self.tail = node
        end
        
        self.nodes[key] = node
        self.size = self.size + 1
        
        -- 检查是否需要淘汰
        while self.size > self.max_size do
            local removed = self:_remove_tail()
            if removed then
                self.stats.evictions = self.stats.evictions + 1
            end
        end
    end
    
    return true
end

-- 删除值
function LRUCache:delete(key)
    local node = self.nodes[key]
    
    if not node then
        return false
    end
    
    -- 从链表中移除
    if node.prev then
        node.prev.next = node.next
    end
    if node.next then
        node.next.prev = node.prev
    end
    if node == self.head then
        self.head = node.next
    end
    if node == self.tail then
        self.tail = node.prev
    end
    
    self.nodes[key] = nil
    self.size = self.size - 1
    
    return true
end

-- 清空缓存
function LRUCache:clear()
    self.head = nil
    self.tail = nil
    self.nodes = {}
    self.size = 0
end

-- 获取统计信息
function LRUCache:get_stats()
    local total_requests = self.stats.hits + self.stats.misses
    local hit_rate = total_requests > 0 and (self.stats.hits / total_requests * 100) or 0
    
    return {
        size = self.size,
        max_size = self.max_size,
        hits = self.stats.hits,
        misses = self.stats.misses,
        hit_rate = hit_rate,
        evictions = self.stats.evictions,
        expired = self.stats.expired
    }
end

-- 获取所有键（用于调试）
function LRUCache:keys()
    local keys = {}
    local current = self.head
    while current do
        table.insert(keys, current.key)
        current = current.next
    end
    return keys
end

return LRUCache
