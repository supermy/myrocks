--[[
    TSDB存储引擎集成版 - 整合V3存储引擎与集群功能
    P2优化: 使用流式合并优化集群查询
    支持：
    - 一致性哈希分片
    - 30秒定长块 + 微秒列偏移
    - 按自然日分ColumnFamily
    - 冷热数据分离
    - ZeroMQ集群通信
    - Consul高可用
    - 流式数据合并
]]

local ffi = require "ffi"

-- 导入我们新开发的模块
local ConsistentHashCluster = require "../examples/cluster/consistent_hash_cluster"
-- 导入RocksDB版本的V3存储引擎
local TSDBStorageEngineV3 = require "lua.tsdb_storage_engine_v3_rocksdb"
-- P2优化: 导入流式合并器
local StreamingMerger = require "streaming_merger"

-- 获取正确的集群管理器类
local HighAvailabilityCluster = ConsistentHashCluster.HighAvailabilityCluster

-- 集成版TSDB存储引擎
local TSDBStorageEngineIntegrated = {}
TSDBStorageEngineIntegrated.__index = TSDBStorageEngineIntegrated

function TSDBStorageEngineIntegrated:new(config)
    local obj = setmetatable({}, TSDBStorageEngineIntegrated)
    
    -- 基础配置
    obj.config = config or {}
    obj.data_dir = config.data_dir or "./data"
    obj.node_id = config.node_id or "node-1"
    obj.cluster_name = config.cluster_name or "tsdb-cluster"
    
    -- 存储引擎配置
    obj.storage_config = {
        data_dir = obj.data_dir,
        write_buffer_size = config.write_buffer_size or 64 * 1024 * 1024,
        max_write_buffer_number = config.max_write_buffer_number or 4,
        target_file_size_base = config.target_file_size_base or 64 * 1024 * 1024,
        max_bytes_for_level_base = config.max_bytes_for_level_base or 256 * 1024 * 1024,
        compression = config.compression or "lz4",
        block_size = config.block_size or 30,  -- 30秒块
        enable_cold_data_separation = config.enable_cold_data_separation or true,
        cold_data_threshold_days = config.cold_data_threshold_days or 30
    }
    
    -- 集群配置
    obj.cluster_config = {
        node_id = obj.node_id,
        cluster_name = obj.cluster_name,
        seed_nodes = config.seed_nodes or {},
        gossip_port = config.gossip_port or 9090,
        data_port = config.data_port or 9091,
        consul_endpoints = config.consul_endpoints or {"http://127.0.0.1:8500"},
        replication_factor = config.replication_factor or 3,
        virtual_nodes_per_physical = config.virtual_nodes_per_physical or 100
    }
    
    -- 组件实例
    obj.storage_engine = nil
    obj.cluster_manager = nil
    obj.is_initialized = false
    obj.is_running = false
    
    return obj
end

function TSDBStorageEngineIntegrated:init()
    if self.is_initialized then
        return true
    end
    
    print("[TSDB集成引擎] 开始初始化...")
    
    -- 1. 初始化存储引擎
    local success, result = pcall(function()
        self.storage_engine = TSDBStorageEngineV3:new(self.storage_config)
        return self.storage_engine:initialize()
    end)
    
    if not success then
        print("[TSDB集成引擎] 存储引擎初始化失败: " .. tostring(result))
        return false
    end
    
    -- 2. 初始化集群管理器
    success, result = pcall(function()
        self.cluster_manager = HighAvailabilityCluster:new(self.cluster_config)
        return self.cluster_manager:initialize()
    end)
    
    if not success then
        print("[TSDB集成引擎] 集群管理器初始化失败: " .. tostring(result))
        -- 集群管理器不是必需的，继续运行
    end
    
    self.is_initialized = true
    print("[TSDB集成引擎] 初始化完成")
    
    return true
end

function TSDBStorageEngineIntegrated:put_stock_data(stock_code, timestamp, data, market)
    -- 写入股票数据
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- 1. 确定数据应该路由到哪个节点
    local target_node_id = self:get_target_node(stock_code, timestamp)
    
    -- 2. 如果是本地节点，直接写入
    if target_node_id == self.node_id then
        -- V3存储引擎使用write_point方法
        return self.storage_engine:write_point(stock_code, timestamp, data.close or data, data)
    else
        -- 3. 如果是远程节点，通过集群转发
        if self.cluster_manager then
            return self.cluster_manager:forward_data(target_node_id, {
                type = "stock_data",
                stock_code = stock_code,
                timestamp = timestamp,
                data = data,
                market = market
            })
        else
            return false, "集群管理器未初始化，无法转发数据"
        end
    end
end

function TSDBStorageEngineIntegrated:get_stock_data(stock_code, start_time, end_time, market)
    -- 读取股票数据
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- 1. 确定数据可能分布在哪些节点
    local target_nodes = self:get_target_nodes_for_range(stock_code, start_time, end_time)
    
    -- 2. 从本地节点读取数据
    local local_data = {}
    if self.storage_engine then
        local success, result = self.storage_engine:read_point(stock_code, start_time, end_time, {})
        if success then
            for _, data_point in ipairs(result) do
                -- 转换数据结构以匹配测试期望
                local converted_data = {
                    stock_code = stock_code,
                    market = market,
                    timestamp = data_point.timestamp,
                    value = data_point.value
                }
                table.insert(local_data, converted_data)
            end
        end
    end
    
    -- 3. 从远程节点读取数据（如果集群管理器可用）
    if self.cluster_manager and #target_nodes > 0 then
        for _, node_id in ipairs(target_nodes) do
            if node_id ~= self.node_id then
                local success, remote_data = self.cluster_manager:fetch_data(node_id, {
                    type = "stock_query",
                    stock_code = stock_code,
                    start_time = start_time,
                    end_time = end_time,
                    market = market
                })
                
                if success and remote_data then
                    for _, data_point in ipairs(remote_data) do
                        table.insert(local_data, data_point)
                    end
                end
            end
        end
    end
    
    -- 4. 按时间排序数据
    table.sort(local_data, function(a, b)
        return a.timestamp < b.timestamp
    end)
    
    return true, local_data
end

function TSDBStorageEngineIntegrated:put_metric_data(metric_name, timestamp, value, tags)
    -- 写入度量数据
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- 1. 确定数据应该路由到哪个节点
    local target_node_id = self:get_target_node(metric_name, timestamp)
    
    -- 2. 如果是本地节点，直接写入
    if target_node_id == self.node_id then
        return self.storage_engine:write_point(metric_name, timestamp, value, tags)
    else
        -- 3. 如果是远程节点，通过集群转发
        if self.cluster_manager then
            return self.cluster_manager:forward_data(target_node_id, {
                type = "metric_data",
                metric_name = metric_name,
                timestamp = timestamp,
                value = value,
                tags = tags
            })
        else
            return false, "集群管理器未初始化，无法转发数据"
        end
    end
end

-- CSV数据导入接口
function TSDBStorageEngineIntegrated:import_csv_data(file_path, business_type, options)
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- CSV导入只在本地节点处理
    if self.storage_engine then
        return self.storage_engine:import_csv_data(file_path, business_type, options)
    else
        return false, "存储引擎不可用"
    end
end

-- CSV数据导出接口
function TSDBStorageEngineIntegrated:export_csv_data(file_path, business_type, start_time, end_time, options)
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- CSV导出只在本地节点处理
    if self.storage_engine then
        return self.storage_engine:export_csv_data(file_path, business_type, start_time, end_time, options)
    else
        return false, "存储引擎不可用"
    end
end

-- 获取支持的CSV格式列表
function TSDBStorageEngineIntegrated:get_csv_formats()
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    if self.storage_engine then
        return self.storage_engine:get_csv_formats()
    else
        return false, "存储引擎不可用"
    end
end

-- 验证CSV文件格式
function TSDBStorageEngineIntegrated:validate_csv_format(file_path, business_type)
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    if self.storage_engine then
        return self.storage_engine:validate_csv_format(file_path, business_type)
    else
        return false, "存储引擎不可用"
    end
end

function TSDBStorageEngineIntegrated:get_metric_data(metric_name, start_time, end_time, tags)
    -- 读取度量数据
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    -- 1. 确定数据可能分布在哪些节点
    local target_nodes = self:get_target_nodes_for_range(metric_name, start_time, end_time)
    
    -- 2. 收集所有数据源
    local data_sources = {}
    
    -- 本地数据源
    if self.storage_engine then
        local success, result = self.storage_engine:read_point(metric_name, start_time, end_time, tags)
        if success and #result > 0 then
            table.insert(data_sources, {
                id = "local",
                data = result
            })
        end
    end
    
    -- 远程数据源
    if self.cluster_manager and #target_nodes > 0 then
        for _, node_id in ipairs(target_nodes) do
            if node_id ~= self.node_id then
                local success, remote_data = self.cluster_manager:fetch_data(node_id, {
                    type = "metric_query",
                    metric_name = metric_name,
                    start_time = start_time,
                    end_time = end_time,
                    tags = tags
                })
                
                if success and remote_data and #remote_data > 0 then
                    table.insert(data_sources, {
                        id = node_id,
                        data = remote_data
                    })
                end
            end
        end
    end
    
    -- 3. P2优化: 使用流式合并器合并多个有序数据源
    if #data_sources == 0 then
        return true, {}
    elseif #data_sources == 1 then
        -- 只有一个数据源，直接返回
        return true, data_sources[1].data
    else
        -- 多个数据源，使用流式合并
        local merger = StreamingMerger:new(function(a, b)
            return a.timestamp < b.timestamp
        end)
        
        -- 添加所有数据源
        for _, source in ipairs(data_sources) do
            merger:add_source(source.id, StreamingMerger.create_array_iterator(source.data))
        end
        
        -- 收集合并后的结果
        local merged_data = {}
        while true do
            local item = merger:next()
            if not item then
                break
            end
            table.insert(merged_data, item)
        end
        
        return true, merged_data
    end
end

function TSDBStorageEngineIntegrated:get_target_node(key, timestamp)
    -- 根据一致性哈希确定目标节点
    if self.cluster_manager then
        return self.cluster_manager:get_target_node(key, timestamp)
    else
        -- 如果没有集群管理器，默认返回本地节点
        return self.node_id
    end
end

function TSDBStorageEngineIntegrated:get_target_nodes_for_range(key, start_time, end_time)
    -- 获取时间范围内可能涉及的所有节点
    local nodes = {}
    
    if self.cluster_manager then
        -- 基于时间范围计算可能涉及的分片
        local time_step = 30  -- 30秒块
        local current_time = start_time
        
        while current_time <= end_time do
            local node_id = self.cluster_manager:get_target_node(key, current_time)
            if not table.contains(nodes, node_id) then
                table.insert(nodes, node_id)
            end
            current_time = current_time + time_step
        end
    else
        -- 如果没有集群管理器，只返回本地节点
        table.insert(nodes, self.node_id)
    end
    
    return nodes
end

function TSDBStorageEngineIntegrated:compact_range(cf_name, start_key, end_key)
    -- 压缩指定范围的数据
    if not self.is_initialized then
        return false, "存储引擎未初始化"
    end
    
    return self.storage_engine:compact_range(cf_name, start_key, end_key)
end

function TSDBStorageEngineIntegrated:get_stats()
    -- 获取统计信息
    local stats = {
        is_initialized = self.is_initialized,
        is_running = self.is_running,
        node_id = self.node_id,
        cluster_enabled = self.cluster_manager ~= nil
    }
    
    if self.storage_engine and self.storage_engine.get_stats then
        stats.storage_stats = self.storage_engine:get_stats()
    end
    
    if self.cluster_manager and self.cluster_manager.get_stats then
        stats.cluster_stats = self.cluster_manager:get_stats()
    end
    
    return stats
end

function TSDBStorageEngineIntegrated:close()
    -- 关闭存储引擎
    if self.storage_engine then
        -- 检查存储引擎是否有close方法
        if self.storage_engine.close then
            self.storage_engine:close()
        end
    end
    
    if self.cluster_manager then
        -- 检查集群管理器是否有close方法
        if self.cluster_manager.close then
            self.cluster_manager:close()
        end
    end
    
    self.is_initialized = false
    self.is_running = false
    
    print("[TSDB集成引擎] 已关闭")
    return true
end

-- 辅助函数
table.contains = function(t, value)
    for _, v in ipairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

return TSDBStorageEngineIntegrated