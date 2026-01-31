--[[
    流式数据合并器 - 重构版
    
    设计目标:
    1. 使用最小堆实现多路归并排序
    2. 流式处理大数据集，避免内存爆炸
    3. 支持自定义比较函数
    4. 适用于集群查询结果合并
    
    使用场景:
    - 合并多个有序数据源
    - 集群查询结果归并
    - 大数据集排序
]]

local StreamingMerger = {}
StreamingMerger.__index = StreamingMerger

-- ============================================================================
-- 最小堆实现
-- ============================================================================

local MinHeap = {}
MinHeap.__index = MinHeap

--- 创建新的最小堆
-- @param compare_func 比较函数，默认使用 <
-- @return MinHeap实例
function MinHeap:new(compare_func)
    return setmetatable({
        _data = {},
        _size = 0,
        _compare = compare_func or function(a, b) return a < b end,
    }, self)
end

--- 插入元素
-- @param value 要插入的元素
function MinHeap:push(value)
    self._size = self._size + 1
    self._data[self._size] = value
    self:_sift_up(self._size)
end

--- 移除并返回最小元素
-- @return 最小元素，堆为空返回nil
function MinHeap:pop()
    if self._size == 0 then
        return nil
    end
    
    local min = self._data[1]
    self._data[1] = self._data[self._size]
    self._data[self._size] = nil
    self._size = self._size - 1
    
    if self._size > 0 then
        self:_sift_down(1)
    end
    
    return min
end

--- 查看最小元素(不移除)
-- @return 最小元素
function MinHeap:peek()
    return self._size > 0 and self._data[1] or nil
end

--- 检查堆是否为空
-- @return boolean
function MinHeap:empty()
    return self._size == 0
end

--- 获取堆大小
-- @return number
function MinHeap:size()
    return self._size
end

-- 上浮操作
function MinHeap:_sift_up(index)
    local data = self._data
    local compare = self._compare
    
    while index > 1 do
        local parent = math.floor(index / 2)
        if not compare(data[index], data[parent]) then
            break
        end
        data[index], data[parent] = data[parent], data[index]
        index = parent
    end
end

-- 下沉操作
function MinHeap:_sift_down(index)
    local data = self._data
    local compare = self._compare
    local size = self._size
    
    while true do
        local smallest = index
        local left = index * 2
        local right = left + 1
        
        if left <= size and compare(data[left], data[smallest]) then
            smallest = left
        end
        if right <= size and compare(data[right], data[smallest]) then
            smallest = right
        end
        
        if smallest == index then
            break
        end
        
        data[index], data[smallest] = data[smallest], data[index]
        index = smallest
    end
end

-- 导出MinHeap
StreamingMerger.MinHeap = MinHeap

-- ============================================================================
-- 流式合并器
-- ============================================================================

--- 创建新的流式合并器
-- @param compare_func 比较函数
-- @return StreamingMerger实例
function StreamingMerger:new(compare_func)
    local obj = setmetatable({}, self)
    
    -- 默认按timestamp排序
    obj._compare = compare_func or function(a, b)
        local ta = type(a) == "table" and (a.timestamp or 0) or a
        local tb = type(b) == "table" and (b.timestamp or 0) or b
        return ta < tb
    end
    
    -- 堆中存储的元素: {source_id=..., value=..., iterator=...}
    obj._heap = MinHeap:new(function(a, b)
        return obj._compare(a.value, b.value)
    end)
    
    obj._source_count = 0
    
    return obj
end

--- 添加数据源
-- @param source_id 数据源标识
-- @param iterator 迭代器函数，每次调用返回下一个元素
function StreamingMerger:add_source(source_id, iterator)
    local first_item = iterator()
    if first_item then
        self._heap:push({
            source_id = source_id,
            value = first_item,
            iterator = iterator,
        })
        self._source_count = self._source_count + 1
    end
end

--- 获取下一个合并后的元素
-- @return 下一个元素，无数据返回nil
function StreamingMerger:next()
    if self._heap:empty() then
        return nil
    end
    
    local min = self._heap:pop()
    local result = min.value
    
    -- 从同一数据源获取下一个元素
    local next_item = min.iterator()
    if next_item then
        self._heap:push({
            source_id = min.source_id,
            value = next_item,
            iterator = min.iterator,
        })
    end
    
    return result
end

--- 流式处理所有数据
-- @param callback 回调函数，返回false停止处理
function StreamingMerger:stream_all(callback)
    while true do
        local item = self:next()
        if not item then
            break
        end
        
        if callback then
            local should_continue = callback(item)
            if should_continue == false then
                break
            end
        end
    end
end

--- 批量获取数据
-- @param batch_size 批量大小，默认100
-- @return table 批量数据
function StreamingMerger:next_batch(batch_size)
    batch_size = batch_size or 100
    local batch = {}
    
    for i = 1, batch_size do
        local item = self:next()
        if not item then
            break
        end
        batch[i] = item
    end
    
    return batch
end

--- 获取所有数据(注意:大数据集会消耗大量内存)
-- @return table 所有数据
function StreamingMerger:collect_all()
    local result = {}
    while true do
        local item = self:next()
        if not item then
            break
        end
        result[#result + 1] = item
    end
    return result
end

-- ============================================================================
-- 迭代器工厂方法
-- ============================================================================

--- 从数组创建迭代器
-- @param array 数组
-- @return function 迭代器
function StreamingMerger.create_array_iterator(array)
    local index = 0
    local len = #array
    return function()
        index = index + 1
        if index <= len then
            return array[index]
        end
        return nil
    end
end

--- 从函数创建迭代器
-- @param func 生成函数
-- @return function 迭代器
function StreamingMerger.create_function_iterator(func)
    return func
end

-- ============================================================================
-- 静态方法
-- ============================================================================

--- 合并多个有序数组
-- @param arrays 数组列表
-- @param compare_func 比较函数
-- @return table 合并后的有序数组
function StreamingMerger.merge_sorted_arrays(arrays, compare_func)
    local merger = StreamingMerger:new(compare_func)
    
    for i, array in ipairs(arrays) do
        if #array > 0 then
            merger:add_source(i, StreamingMerger.create_array_iterator(array))
        end
    end
    
    return merger:collect_all()
end

--- 合并多个数据源
-- @param sources 数据源列表 {id=..., iterator=...}
-- @param compare_func 比较函数
-- @return StreamingMerger实例
function StreamingMerger.merge_sources(sources, compare_func)
    local merger = StreamingMerger:new(compare_func)
    
    for _, source in ipairs(sources) do
        merger:add_source(source.id, source.iterator)
    end
    
    return merger
end

-- ============================================================================
-- 性能测试
-- ============================================================================

--- 性能基准测试
-- @param arrays 测试数组
-- @param iterations 迭代次数
-- @return table 测试结果
function StreamingMerger:benchmark(arrays, iterations)
    iterations = iterations or 100
    
    -- 预热
    for i = 1, 10 do
        StreamingMerger.merge_sorted_arrays(arrays, self._compare)
    end
    
    -- 测试流式合并
    local start = os.clock()
    for i = 1, iterations do
        StreamingMerger.merge_sorted_arrays(arrays, self._compare)
    end
    local merge_time = os.clock() - start
    
    -- 测试简单合并+排序
    start = os.clock()
    for i = 1, iterations do
        local all = {}
        for _, arr in ipairs(arrays) do
            for _, item in ipairs(arr) do
                all[#all + 1] = item
            end
        end
        table.sort(all, self._compare)
    end
    local sort_time = os.clock() - start
    
    local result = StreamingMerger.merge_sorted_arrays(arrays, self._compare)
    
    return {
        merge_time_ms = merge_time * 1000,
        sort_time_ms = sort_time * 1000,
        speedup = sort_time / merge_time,
        total_items = #result,
        iterations = iterations,
    }
end

return StreamingMerger
