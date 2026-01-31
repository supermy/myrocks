--[[
    LRU缓存实现 - 重构版
    
    设计目标:
    1. O(1) 时间复杂度的读写操作
    2. 支持TTL过期机制
    3. 自动LRU淘汰
    4. 线程安全(单线程环境)
    5. 代码清晰易维护
    
    数据结构:
    - 双向链表: 维护访问顺序，头部最新，尾部最旧
    - 哈希表: 快速查找节点
]]

local LRUCache = {}
LRUCache.__index = LRUCache

-- ============================================================================
-- 常量
-- ============================================================================

local DEFAULT_MAX_SIZE = 1000
local DEFAULT_TTL = 300  -- 5分钟
local CLEANUP_INTERVAL = 100  -- 每100次访问清理一次过期节点

-- ============================================================================
-- 构造函数
-- ============================================================================

--- 创建新的LRU缓存实例
-- @param options 配置选项
--   @field max_size 最大条目数 (默认1000)
--   @field default_ttl 默认过期时间秒数 (默认300)
-- @return LRUCache实例
function LRUCache:new(options)
    options = options or {}
    
    local obj = setmetatable({}, self)
    obj.max_size = options.max_size or DEFAULT_MAX_SIZE
    obj.default_ttl = options.default_ttl or DEFAULT_TTL
    
    -- 双向链表
    obj._head = nil  -- 最新访问
    obj._tail = nil  -- 最旧访问
    
    -- 哈希表: key -> node
    obj._nodes = {}
    obj._size = 0
    
    -- 统计信息
    obj._stats = {
        hits = 0,
        misses = 0,
        evictions = 0,
        expired = 0,
        total_requests = 0,
    }
    
    return obj
end

-- ============================================================================
-- 链表操作 (私有方法)
-- ============================================================================

-- 创建链表节点
local function create_node(key, value, ttl)
    return {
        key = key,
        value = value,
        prev = nil,
        next = nil,
        expires_at = ttl and (os.time() + ttl) or nil,
    }
end

-- 将节点移到头部 (标记为最新访问)
function LRUCache:_move_to_head(node)
    if node == self._head then
        return
    end
    
    -- 从当前位置移除
    self:_remove_from_list(node)
    
    -- 插入头部
    node.prev = nil
    node.next = self._head
    
    if self._head then
        self._head.prev = node
    end
    
    self._head = node
    
    if not self._tail then
        self._tail = node
    end
end

-- 从链表中移除节点
function LRUCache:_remove_from_list(node)
    if node.prev then
        node.prev.next = node.next
    end
    if node.next then
        node.next.prev = node.prev
    end
    
    if node == self._head then
        self._head = node.next
    end
    if node == self._tail then
        self._tail = node.prev
    end
end

-- 移除尾部节点 (LRU淘汰)
function LRUCache:_evict_lru()
    if not self._tail then
        return nil
    end
    
    local node = self._tail
    self:_remove_from_list(node)
    self._nodes[node.key] = nil
    self._size = self._size - 1
    
    return node
end

-- 插入节点到头部
function LRUCache:_insert_to_head(node)
    node.prev = nil
    node.next = self._head
    
    if self._head then
        self._head.prev = node
    end
    
    self._head = node
    
    if not self._tail then
        self._tail = node
    end
    
    self._nodes[node.key] = node
    self._size = self._size + 1
end

-- ============================================================================
-- 过期处理
-- ============================================================================

-- 检查节点是否过期
function LRUCache:_is_expired(node)
    if not node.expires_at then
        return false
    end
    return os.time() > node.expires_at
end

-- 删除指定节点
function LRUCache:_delete_node(node)
    self:_remove_from_list(node)
    self._nodes[node.key] = nil
    self._size = self._size - 1
end

-- 清理过期节点
function LRUCache:_cleanup_expired()
    local current = self._tail
    local now = os.time()
    
    while current do
        local prev = current.prev
        
        if current.expires_at and now > current.expires_at then
            self:_delete_node(current)
            self._stats.expired = self._stats.expired + 1
        end
        
        current = prev
    end
end

-- ============================================================================
-- 公共API
-- ============================================================================

--- 获取缓存值
-- @param key 键
-- @return value 值，不存在或过期返回nil
function LRUCache:get(key)
    -- 定期清理过期节点
    self._stats.total_requests = self._stats.total_requests + 1
    if self._stats.total_requests % CLEANUP_INTERVAL == 0 then
        self:_cleanup_expired()
    end
    
    local node = self._nodes[key]
    
    if not node then
        self._stats.misses = self._stats.misses + 1
        return nil
    end
    
    -- 检查过期
    if self:_is_expired(node) then
        self:_delete_node(node)
        self._stats.expired = self._stats.expired + 1
        self._stats.misses = self._stats.misses + 1
        return nil
    end
    
    -- 移到头部 (LRU更新)
    self:_move_to_head(node)
    self._stats.hits = self._stats.hits + 1
    
    return node.value
end

--- 设置缓存值
-- @param key 键
-- @param value 值
-- @param ttl 过期时间(秒)，nil表示使用默认值
-- @return boolean 是否成功
function LRUCache:set(key, value, ttl)
    ttl = ttl or self.default_ttl
    local node = self._nodes[key]
    
    if node then
        -- 更新现有节点
        node.value = value
        node.expires_at = ttl and (os.time() + ttl) or nil
        self:_move_to_head(node)
    else
        -- 创建新节点
        node = create_node(key, value, ttl)
        self:_insert_to_head(node)
        
        -- LRU淘汰
        while self._size > self.max_size do
            local evicted = self:_evict_lru()
            if evicted then
                self._stats.evictions = self._stats.evictions + 1
            end
        end
    end
    
    return true
end

--- 删除缓存值
-- @param key 键
-- @return boolean 是否删除成功
function LRUCache:delete(key)
    local node = self._nodes[key]
    
    if not node then
        return false
    end
    
    self:_delete_node(node)
    return true
end

--- 清空缓存
function LRUCache:clear()
    self._head = nil
    self._tail = nil
    self._nodes = {}
    self._size = 0
    
    -- 重置统计
    self._stats = {
        hits = 0,
        misses = 0,
        evictions = 0,
        expired = 0,
        total_requests = 0,
    }
end

--- 获取缓存统计信息
-- @return table 统计信息
function LRUCache:get_stats()
    local total = self._stats.hits + self._stats.misses
    
    return {
        size = self._size,
        max_size = self.max_size,
        hits = self._stats.hits,
        misses = self._stats.misses,
        hit_rate = total > 0 and (self._stats.hits / total * 100) or 0,
        evictions = self._stats.evictions,
        expired = self._stats.expired,
        total_requests = self._stats.total_requests,
    }
end

--- 获取所有键 (用于调试)
-- @return table 键列表(按访问顺序，最新的在前)
function LRUCache:keys()
    local keys = {}
    local current = self._head
    
    while current do
        table.insert(keys, current.key)
        current = current.next
    end
    
    return keys
end

--- 获取缓存大小
-- @return number 当前条目数
function LRUCache:count()
    return self._size
end

--- 检查键是否存在
-- @param key 键
-- @return boolean 是否存在(不过期检查)
function LRUCache:has(key)
    return self._nodes[key] ~= nil
end

return LRUCache
