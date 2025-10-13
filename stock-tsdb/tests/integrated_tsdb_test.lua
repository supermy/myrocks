--
-- TSDB集群系统集成测试
-- 测试完整的数据写入、读取、分片路由和集群功能
--

package.path = package.path .. ";./?.lua;./lua/?.lua"

local function test_integrated_storage_engine()
    print("=== 测试集成存储引擎 ===")
    
    -- 模拟配置
    local config = {
        data_dir = "./test_data/integrated",
        node_id = "test-node-1",
        cluster_name = "test-cluster",
        write_buffer_size = 16 * 1024 * 1024,  -- 16MB
        max_write_buffer_number = 2,
        target_file_size_base = 16 * 1024 * 1024,
        max_bytes_for_level_base = 64 * 1024 * 1024,
        compression = "lz4",
        block_size = 30,  -- 30秒块
        enable_cold_data_separation = true,
        cold_data_threshold_days = 7,  -- 测试用7天
        seed_nodes = {"test-node-2", "test-node-3"},
        gossip_port = 19090,
        data_port = 19091,
        consul_endpoints = {"http://127.0.0.1:12379"},  -- 测试用端口
        replication_factor = 2,
        virtual_nodes_per_physical = 10  -- 测试用较少虚拟节点
    }
    
    -- 创建集成存储引擎
    local TSDBStorageEngineIntegrated = require "tsdb_storage_engine_integrated"
    local storage_engine = TSDBStorageEngineIntegrated:new(config)
    
    -- 初始化
    local success = storage_engine:init()
    assert(success, "集成存储引擎初始化失败")
    print("✓ 集成存储引擎初始化成功")
    
    -- 测试股票数据写入
    local stock_data = {
        open = 100.5,
        high = 102.3,
        low = 99.8,
        close = 101.2,
        volume = 1000000,
        amount = 101200000
    }
    
    local timestamp = os.time()
    success = storage_engine:put_stock_data("000001", timestamp, stock_data, "SH")
    assert(success, "股票数据写入失败")
    print("✓ 股票数据写入成功")
    
    -- 测试股票数据读取
    local read_success, read_data = storage_engine:get_stock_data("000001", timestamp - 60, timestamp + 60, "SH")
    assert(read_success, "股票数据读取失败")
    assert(#read_data > 0, "未读取到股票数据")
    
    local data_point = read_data[1]
    assert(data_point.stock_code == "000001", "股票代码不匹配")
    assert(data_point.market == "SH", "市场代码不匹配")
    assert(math.abs(data_point.timestamp - timestamp) < 1, "时间戳不匹配")
    
    print("✓ 股票数据读取成功")
    
    -- 测试度量数据写入
    local metric_data = 85.6  -- CPU使用率
    local tags = {
        host = "server-1",
        region = "us-east",
        service = "api"
    }
    
    success = storage_engine:put_metric_data("cpu.usage", timestamp, metric_data, tags)
    assert(success, "度量数据写入失败")
    print("✓ 度量数据写入成功")
    
    -- 测试度量数据读取
    local metric_success, metric_read_data = storage_engine:get_metric_data("cpu.usage", timestamp - 60, timestamp + 60, tags)
    assert(metric_success, "度量数据读取失败")
    assert(#metric_read_data > 0, "未读取到度量数据")
    
    local metric_point = metric_read_data[1]
    assert(metric_point.metric_name == "cpu.usage", "度量名称不匹配")
    assert(math.abs(metric_point.value - metric_data) < 0.001, "度量值不匹配")
    
    print("✓ 度量数据读取成功")
    
    -- 测试分片路由逻辑
    local target_node = storage_engine:get_target_node("000001", timestamp)
    assert(target_node == "test-node-1", "分片路由逻辑错误")
    print("✓ 分片路由逻辑测试通过")
    
    -- 测试时间范围节点查询
    local target_nodes = storage_engine:get_target_nodes_for_range("000001", timestamp - 300, timestamp + 300)
    assert(#target_nodes > 0, "时间范围节点查询失败")
    assert(table.contains(target_nodes, "test-node-1"), "本地节点不在目标节点列表中")
    print("✓ 时间范围节点查询测试通过")
    
    -- 测试统计信息获取
    local stats = storage_engine:get_stats()
    assert(stats.is_initialized, "统计信息显示未初始化")
    assert(stats.node_id == "test-node-1", "节点ID不匹配")
    print("✓ 统计信息获取测试通过")
    
    -- 关闭存储引擎
    storage_engine:close()
    print("✓ 存储引擎关闭成功")
    
    return true
end

local function test_rowkey_encoding_consistency()
    print("\n=== 测试RowKey编码一致性 ===")
    
    -- 测试相同的输入是否产生相同的RowKey
    local TSDBStorageEngineV3 = require "tsdb_storage_engine_v3"
    
    local config = {
        data_dir = "./test_data/encoding",
        block_size = 30
    }
    
    local engine = TSDBStorageEngineV3:new(config)
    
    -- 测试股票RowKey编码
    local stock_code = "000001"
    local timestamp = 1609459200  -- 固定时间戳
    local market = "SH"
    
    local rowkey1, qualifier1 = engine:encode_stock_key(stock_code, timestamp, market)
    local rowkey2, qualifier2 = engine:encode_stock_key(stock_code, timestamp, market)
    
    assert(rowkey1 == rowkey2, "股票RowKey编码不一致")
    assert(qualifier1 == qualifier2, "股票Qualifier编码不一致")
    print("✓ 股票RowKey编码一致性测试通过")
    
    -- 测试度量RowKey编码
    local metric_name = "cpu.usage"
    local tags = {host = "server1", region = "us-east"}
    
    local m_rowkey1, m_qualifier1 = engine:encode_metric_key(metric_name, timestamp, tags)
    local m_rowkey2, m_qualifier2 = engine:encode_metric_key(metric_name, timestamp, tags)
    
    assert(m_rowkey1 == m_rowkey2, "度量RowKey编码不一致")
    assert(m_qualifier1 == m_qualifier2, "度量Qualifier编码不一致")
    print("✓ 度量RowKey编码一致性测试通过")
    
    -- 测试时间块对齐
    local aligned_time = math.floor(timestamp / 30) * 30
    local test_rowkey, _ = engine:encode_stock_key(stock_code, aligned_time, market)
    
    assert(string.find(test_rowkey, tostring(aligned_time)) ~= nil, "时间块对齐错误")
    print("✓ 时间块对齐测试通过")
    
    return true
end

local function test_cold_hot_data_separation()
    print("\n=== 测试冷热数据分离 ===")
    
    local TSDBStorageEngineV3 = require "tsdb_storage_engine_v3"
    
    local config = {
        data_dir = "./test_data/cold_hot",
        enable_cold_data_separation = true,
        cold_data_threshold_days = 7  -- 测试用7天
    }
    
    local engine = TSDBStorageEngineV3:new(config)
    
    -- 测试热数据（今天）
    local today_timestamp = os.time()
    local today_cf = engine:get_cf_name_for_timestamp(today_timestamp)
    assert(string.find(today_cf, "cf_") ~= nil, "今天的数据应该使用热数据CF")
    print("✓ 热数据CF命名测试通过")
    
    -- 测试冷数据（8天前）
    local old_timestamp = os.time() - 8 * 24 * 60 * 60
    local cold_cf = engine:get_cf_name_for_timestamp(old_timestamp)
    assert(string.find(cold_cf, "cold_") ~= nil, "8天前的数据应该使用冷数据CF")
    print("✓ 冷数据CF命名测试通过")
    
    -- 测试边界情况（正好7天前）
    local boundary_timestamp = os.time() - 7 * 24 * 60 * 60
    local boundary_cf = engine:get_cf_name_for_timestamp(boundary_timestamp)
    assert(string.find(boundary_cf, "cf_") ~= nil, "7天前的数据应该使用热数据CF")
    print("✓ 边界条件测试通过")
    
    return true
end

local function test_cluster_aware_routing()
    print("\n=== 测试集群感知路由 ===")
    
    local ConsistentHashCluster = require "consistent_hash_cluster"
    
    -- 模拟集群配置
    local cluster_config = {
        node_id = "node-a",
        cluster_name = "test-cluster",
        seed_nodes = {"node-b", "node-c"},
        consul_endpoints = {"http://127.0.0.1:12379"},
        virtual_nodes_per_physical = 10
    }
    
    local cluster = ConsistentHashCluster:new(cluster_config)
    
    -- 测试节点加入
    cluster:add_node("node-a", "127.0.0.1", 9090)
    cluster:add_node("node-b", "127.0.0.2", 9090)
    cluster:add_node("node-c", "127.0.0.3", 9090)
    
    -- 测试一致性哈希路由
    local test_key = "test-metric"
    local timestamp = os.time()
    
    local target_node1 = cluster:get_target_node(test_key, timestamp)
    local target_node2 = cluster:get_target_node(test_key, timestamp)
    
    assert(target_node1 == target_node2, "相同键应该路由到相同节点")
    print("✓ 一致性哈希路由测试通过")
    
    -- 测试节点移除和重新路由
    cluster:remove_node("node-b")
    local target_node_after_remove = cluster:get_target_node(test_key, timestamp)
    
    assert(target_node_after_remove ~= "node-b", "已移除的节点不应该被路由到")
    print("✓ 节点移除和重新路由测试通过")
    
    -- 测试虚拟节点分布
    local node_distribution = {}
    for i = 1, 100 do
        local key = "metric-" .. i
        local node = cluster:get_target_node(key, timestamp)
        node_distribution[node] = (node_distribution[node] or 0) + 1
    end
    
    -- 验证每个节点都分配到了一些键
    local nodes_used = 0
    for node, count in pairs(node_distribution) do
        if count > 0 then
            nodes_used = nodes_used + 1
        end
    end
    
    assert(nodes_used >= 2, "键应该分布在多个节点上")
    print("✓ 虚拟节点分布测试通过")
    
    return true
end

local function test_performance_characteristics()
    print("\n=== 测试性能特性 ===")
    
    local TSDBStorageEngineV3 = require "tsdb_storage_engine_v3"
    
    local config = {
        data_dir = "./test_data/performance",
        write_buffer_size = 8 * 1024 * 1024,  -- 8MB for testing
        block_size = 30
    }
    
    local engine = TSDBStorageEngineV3:new(config)
    local success = engine:init()
    assert(success, "性能测试引擎初始化失败")
    
    -- 测试批量写入性能
    local start_time = os.clock()
    local write_count = 1000
    
    for i = 1, write_count do
        local stock_data = {
            open = 100 + i * 0.1,
            high = 102 + i * 0.1,
            low = 99 + i * 0.1,
            close = 101 + i * 0.1,
            volume = 1000000 + i * 100,
            amount = 101200000 + i * 1000
        }
        
        local timestamp = os.time() + i
        engine:put_stock_data("TEST" .. tostring(i % 100), timestamp, stock_data, "SH")
    end
    
    local write_time = os.clock() - start_time
    local writes_per_second = write_count / write_time
    
    print(string.format("批量写入性能: %.2f 写入/秒", writes_per_second))
    assert(writes_per_second > 100, "写入性能过低")
    print("✓ 批量写入性能测试通过")
    
    -- 测试批量读取性能
    start_time = os.clock()
    local read_count = 100
    
    for i = 1, read_count do
        local stock_code = "TEST" .. tostring(i % 100)
        local end_time = os.time() + 1000
        local start_time_range = end_time - 3600  -- 1小时范围
        
        engine:get_stock_data(stock_code, start_time_range, end_time, "SH")
    end
    
    local read_time = os.clock() - start_time
    local reads_per_second = read_count / read_time
    
    print(string.format("批量读取性能: %.2f 读取/秒", reads_per_second))
    assert(reads_per_second > 10, "读取性能过低")
    print("✓ 批量读取性能测试通过")
    
    engine:close()
    
    return true
end

local function run_all_integrated_tests()
    print("开始TSDB集群系统集成测试...")
    print("=" .. string.rep("=", 60))
    
    local results = {
        integrated_storage = test_integrated_storage_engine(),
        rowkey_consistency = test_rowkey_encoding_consistency(),
        cold_hot_separation = test_cold_hot_data_separation(),
        cluster_routing = test_cluster_aware_routing(),
        performance = test_performance_characteristics()
    }
    
    print("\n" .. "=" .. string.rep("=", 60))
    print("集成测试结果摘要:")
    
    local passed = 0
    local total = 0
    
    for test_name, success in pairs(results) do
        total = total + 1
        if success then
            passed = passed + 1
            print("✓ " .. test_name .. " - 通过")
        else
            print("✗ " .. test_name .. " - 失败")
        end
    end
    
    print(string.format("\n总计: %d/%d 集成测试通过", passed, total))
    
    if passed == total then
        print("🎉 TSDB集群系统集成测试全部通过！")
        print("\n系统特性验证完成:")
        print("  • 集成存储引擎功能")
        print("  • RowKey编码一致性")
        print("  • 冷热数据分离")
        print("  • 集群感知路由")
        print("  • 性能特性")
        return true
    else
        print("⚠ 部分集成测试失败，请检查具体实现")
        return false
    end
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

-- 运行集成测试
local success = run_all_integrated_tests()

if success then
    print("\n🚀 TSDB集群系统已准备就绪！")
    print("可以开始部署生产环境或进行进一步的压力测试。")
else
    print("\n❌ 集成测试发现问题，请修复后重新测试。")
end

return success