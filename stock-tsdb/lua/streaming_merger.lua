--[[
    流式数据合并器
    P2优化: 使用最小堆实现多路归并
    用于集群查询时合并多个节点的有序数据
]]

local StreamingMerger = {}
StreamingMerger.__index = StreamingMerger

-- 最小堆实现
local MinHeap = {}
MinHeap.__index = MinHeap

-- 导出MinHeap供外部使用
StreamingMerger.MinHeap = MinHeap

function MinHeap:new(compare_func)
    local obj = setmetatable({}, self)
    obj.data = {}
    obj.size = 0
    obj.compare = compare_func or function(a, b) return a < b end
    return obj
end

function MinHeap:push(value)
    self.size = self.size + 1
    self.data[self.size] = value
    self:_sift_up(self.size)
end

function MinHeap:pop()
    if self.size == 0 then
        return nil
    end
    
    local min = self.data[1]
    self.data[1] = self.data[self.size]
    self.data[self.size] = nil
    self.size = self.size - 1
    
    if self.size > 0 then
        self:_sift_down(1)
    end
    
    return min
end

function MinHeap:peek()
    if self.size == 0 then
        return nil
    end
    return self.data[1]
end

function MinHeap:empty()
    return self.size == 0
end

function MinHeap:_sift_up(index)
    local parent = math.floor(index / 2)
    while index > 1 and self.compare(self.data[index], self.data[parent]) do
        self.data[index], self.data[parent] = self.data[parent], self.data[index]
        index = parent
        parent = math.floor(index / 2)
    end
end

function MinHeap:_sift_down(index)
    local size = self.size
    while true do
        local smallest = index
        local left = index * 2
        local right = index * 2 + 1
        
        if left <= size and self.compare(self.data[left], self.data[smallest]) then
            smallest = left
        end
        
        if right <= size and self.compare(self.data[right], self.data[smallest]) then
            smallest = right
        end
        
        if smallest == index then
            break
        end
        
        self.data[index], self.data[smallest] = self.data[smallest], self.data[index]
        index = smallest
    end
end

-- 流式合并器
function StreamingMerger:new(compare_func)
    local obj = setmetatable({}, self)
    obj.compare = compare_func or function(a, b)
        -- 默认按timestamp排序
        if type(a) == "table" and type(b) == "table" then
            return (a.timestamp or 0) < (b.timestamp or 0)
        else
            return a < b
        end
    end
    obj.heap = MinHeap:new(function(a, b)
        return obj.compare(a.value, b.value)
    end)
    return obj
end

-- 添加数据源
function StreamingMerger:add_source(source_id, data_iterator)
    -- data_iterator 是一个函数，每次调用返回下一个数据项
    local first_item = data_iterator()
    if first_item then
        self.heap:push({
            source_id = source_id,
            value = first_item,
            iterator = data_iterator
        })
    end
end

-- 获取下一个合并后的数据
function StreamingMerger:next()
    if self.heap:empty() then
        return nil
    end
    
    local min = self.heap:pop()
    local result = min.value
    
    -- 从同一数据源获取下一个数据
    local next_item = min.iterator()
    if next_item then
        self.heap:push({
            source_id = min.source_id,
            value = next_item,
            iterator = min.iterator
        })
    end
    
    return result
end

-- 流式处理所有数据
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

-- 批量获取数据
function StreamingMerger:next_batch(batch_size)
    batch_size = batch_size or 100
    local batch = {}
    
    for i = 1, batch_size do
        local item = self:next()
        if not item then
            break
        end
        table.insert(batch, item)
    end
    
    return batch
end

-- 创建数组迭代器
function StreamingMerger:create_array_iterator(array)
    local index = 0
    return function()
        index = index + 1
        return array[index]
    end
end

-- 创建函数迭代器
function StreamingMerger:create_function_iterator(func)
    return func
end

-- 静态方法：合并多个有序数组
function StreamingMerger.merge_sorted_arrays(arrays, compare_func)
    local merger = StreamingMerger:new(compare_func)
    
    for i, array in ipairs(arrays) do
        if #array > 0 then
            merger:add_source(i, merger:create_array_iterator(array))
        end
    end
    
    local result = {}
    while true do
        local item = merger:next()
        if not item then
            break
        end
        table.insert(result, item)
    end
    
    return result
end

-- 静态方法：合并多个数据源（通用接口）
function StreamingMerger.merge_sources(sources, compare_func)
    -- sources: { {id = "source1", iterator = func}, ... }
    local merger = StreamingMerger:new(compare_func)
    
    for _, source in ipairs(sources) do
        merger:add_source(source.id, source.iterator)
    end
    
    return merger
end

-- 性能测试
function StreamingMerger:benchmark(arrays, iterations)
    iterations = iterations or 100
    
    local start_time = os.clock()
    for i = 1, iterations do
        local result = StreamingMerger.merge_sorted_arrays(arrays)
    end
    local merge_time = os.clock() - start_time
    
    -- 对比简单合并+排序
    start_time = os.clock()
    for i = 1, iterations do
        local all_data = {}
        for _, array in ipairs(arrays) do
            for _, item in ipairs(array) do
                table.insert(all_data, item)
            end
        end
        table.sort(all_data, self.compare)
    end
    local sort_time = os.clock() - start_time
    
    return {
        merge_time_ms = merge_time * 1000,
        sort_time_ms = sort_time * 1000,
        speedup = sort_time / merge_time,
        total_items = #StreamingMerger.merge_sorted_arrays(arrays)
    }
end

return StreamingMerger
