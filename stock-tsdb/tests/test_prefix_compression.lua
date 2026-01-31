#!/usr/bin/env luajit

-- 前缀压缩功能测试
-- 测试RocksDB前缀压缩策略是否正常工作

print("前缀压缩功能测试")
print("==================")

-- 添加当前目录到Lua包路径
package.path = package.path .. ";./lua/?.lua"
package.cpath = package.cpath .. ";./lib/?.so"

-- 加载必要的模块
local DailyCFStorageEngine = require "daily_cf_storage_engine"
local PrefixCompressionConfig = require "prefix_compression_config"

-- 测试1: 前缀压缩配置模块测试
print("\n--- 测试1: 前缀压缩配置模块 ---")

local function test_prefix_compression_config()
    print("测试前缀压缩配置模块...")
    
    -- 获取所有策略
    local all_strategies = PrefixCompressionConfig.get_all_strategies()
    print("✓ 获取所有策略成功，数量: " .. #all_strategies)
    
    -- 获取策略摘要
    local summary = PrefixCompressionConfig.generate_summary()
    print("✓ 生成策略摘要成功")
    print("  - 股票策略数量: " .. #summary.stock_strategies)
    print("  - 时间序列策略数量: " .. #summary.timeseries_strategies)
    print("  - CF映射数量: " .. #summary.cf_mapping)
    
    -- 测试特定CF的策略获取
    local stock_strategy = PrefixCompressionConfig.get_strategy_for_cf("cf_20250101", true)
    if stock_strategy then
        print("✓ 获取股票CF策略成功: " .. stock_strategy.name)
    else
        print("✗ 获取股票CF策略失败")
        return false
    end
    
    local cold_strategy = PrefixCompressionConfig.get_strategy_for_cf("cold_20240101", false)
    if cold_strategy then
        print("✓ 获取冷数据CF策略成功: " .. cold_strategy.name)
    else
        print("✗ 获取冷数据CF策略失败")
        return false
    end
    
    return true
end

-- 测试2: 存储引擎前缀压缩配置测试
print("\n--- 测试2: 存储引擎前缀压缩配置 ---")

local function test_storage_engine_prefix_config()
    print("测试存储引擎前缀压缩配置...")
    
    -- 创建存储引擎配置
    local config = {
        enable_prefix_compression = true,
        default_prefix_length = 6,
        enable_cold_data_separation = true,
        cold_data_threshold_days = 30,
        daily_cf_enabled = true,
        retention_days = 30
    }
    
    -- 创建存储引擎实例
    local storage = DailyCFStorageEngine:new(config)
    if storage then
        print("✓ 存储引擎实例创建成功")
    else
        print("✗ 存储引擎实例创建失败")
        return false
    end
    
    -- 初始化存储引擎
    local init_result = storage:initialize()
    if init_result then
        print("✓ 存储引擎初始化成功")
    else
        print("✗ 存储引擎初始化失败")
        return false
    end
    
    -- 测试前缀压缩配置获取
    local prefix_config = storage:get_prefix_compression_config("cf_20250101", true)
    if prefix_config then
        print("✓ 获取前缀压缩配置成功")
        print("  - 启用状态: " .. tostring(prefix_config.enabled))
        print("  - 策略名称: " .. prefix_config.strategy_name)
        print("  - 前缀长度: " .. prefix_config.prefix_length)
    else
        print("✗ 获取前缀压缩配置失败")
        return false
    end
    
    -- 测试禁用前缀压缩的情况
    storage.enable_prefix_compression = false
    local disabled_config = storage:get_prefix_compression_config("cf_20250101", true)
    if disabled_config and not disabled_config.enabled then
        print("✓ 禁用前缀压缩配置正确")
    else
        print("✗ 禁用前缀压缩配置失败")
        return false
    end
    
    -- 恢复启用状态
    storage.enable_prefix_compression = true
    
    return true
end

-- 测试3: CF创建时的前缀压缩配置测试
print("\n--- 测试3: CF创建时的前缀压缩配置 ---")

local function test_cf_creation_with_prefix()
    print("测试CF创建时的前缀压缩配置...")
    
    -- 创建存储引擎实例
    local config = {
        enable_prefix_compression = true,
        default_prefix_length = 6,
        enable_cold_data_separation = true,
        cold_data_threshold_days = 30
    }
    
    local storage = DailyCFStorageEngine:new(config)
    storage:initialize()
    
    -- 测试热数据CF创建
    local hot_cf_name = storage:get_cf_name_for_timestamp(os.time())
    if storage.column_families[hot_cf_name] then
        local hot_cf = storage.column_families[hot_cf_name]
        print("✓ 热数据CF创建成功: " .. hot_cf.name)
        if hot_cf.prefix_compression then
            print("  - 前缀压缩配置: " .. hot_cf.prefix_compression.strategy_name)
            print("  - 前缀长度: " .. hot_cf.prefix_compression.prefix_length)
        else
            print("✗ 热数据CF缺少前缀压缩配置")
            return false
        end
    else
        print("✗ 热数据CF创建失败")
        return false
    end
    
    -- 测试冷数据CF创建（使用过去的时间戳）
    local old_timestamp = os.time() - (35 * 24 * 60 * 60)  -- 35天前
    local cold_cf_name = storage:get_cf_name_for_timestamp(old_timestamp)
    if storage.column_families[cold_cf_name] then
        local cold_cf = storage.column_families[cold_cf_name]
        print("✓ 冷数据CF创建成功: " .. cold_cf.name)
        if cold_cf.prefix_compression then
            print("  - 前缀压缩配置: " .. cold_cf.prefix_compression.strategy_name)
            print("  - 前缀长度: " .. cold_cf.prefix_compression.prefix_length)
        else
            print("✗ 冷数据CF缺少前缀压缩配置")
            return false
        end
    else
        print("✗ 冷数据CF创建失败")
        return false
    end
    
    return true
end

-- 测试4: 数据写入和前缀压缩统计测试
print("\n--- 测试4: 数据写入和前缀压缩统计 ---")

local function test_data_write_and_stats()
    print("测试数据写入和前缀压缩统计...")
    
    -- 创建存储引擎实例
    local config = {
        enable_prefix_compression = true,
        default_prefix_length = 6,
        enable_cold_data_separation = true,
        cold_data_threshold_days = 30
    }
    
    local storage = DailyCFStorageEngine:new(config)
    storage:initialize()
    
    -- 写入热数据
    local current_time = os.time()
    local write_result = storage:write_point("stock.SH000001", current_time, 100.50, {market="SH"})
    if write_result then
        print("✓ 热数据写入成功")
    else
        print("✗ 热数据写入失败")
        return false
    end
    
    -- 写入冷数据
    local old_time = current_time - (35 * 24 * 60 * 60)
    local cold_write_result = storage:write_point("stock.SH000001", old_time, 95.30, {market="SH"})
    if cold_write_result then
        print("✓ 冷数据写入成功")
    else
        print("✗ 冷数据写入失败")
        return false
    end
    
    -- 获取统计信息
    local stats = storage:get_stats()
    if stats then
        print("✓ 获取统计信息成功")
        print("  - 前缀压缩启用: " .. tostring(stats.prefix_compression_enabled))
        print("  - 策略数量: " .. stats.prefix_strategies_count)
        print("  - 默认前缀长度: " .. stats.default_prefix_length)
        
        -- 检查CF详情中的前缀压缩配置
        if stats.cf_details and #stats.cf_details > 0 then
            for _, cf_detail in ipairs(stats.cf_details) do
                if cf_detail.prefix_compression then
                    print("  - CF " .. cf_detail.name .. " 前缀压缩: " .. cf_detail.prefix_compression.strategy_name)
                end
            end
        end
    else
        print("✗ 获取统计信息失败")
        return false
    end
    
    return true
end

-- 测试5: 自动优化脚本的前缀压缩配置测试
print("\n--- 测试5: 自动优化脚本的前缀压缩配置 ---")

local function test_auto_optimization_prefix()
    print("测试自动优化脚本的前缀压缩配置...")
    
    -- 加载硬件检测器
    local HardwareDetector = require "hardware_detector_simple"
    
    -- 创建硬件检测器实例
    local detector = HardwareDetector:new()
    if detector then
        print("✓ 硬件检测器创建成功")
    else
        print("✗ 硬件检测器创建失败")
        return false
    end
    
    -- 获取优化的RocksDB参数
    local optimized_params = detector:get_optimized_rocksdb_params()
    if optimized_params then
        print("✓ 获取优化参数成功")
        
        -- 检查是否包含前缀压缩配置
        if optimized_params.enable_prefix_compression then
            print("  - 前缀压缩启用: " .. tostring(optimized_params.enable_prefix_compression))
        else
            print("✗ 优化参数缺少前缀压缩配置")
            return false
        end
        
        if optimized_params.prefix_extractor_length then
            print("  - 前缀提取器长度: " .. optimized_params.prefix_extractor_length)
        else
            print("✗ 优化参数缺少前缀提取器长度")
            return false
        end
        
        if optimized_params.memtable_prefix_bloom_size_ratio then
            print("  - Memtable前缀布隆过滤器比例: " .. optimized_params.memtable_prefix_bloom_size_ratio)
        else
            print("✗ 优化参数缺少Memtable前缀布隆过滤器比例")
            return false
        end
    else
        print("✗ 获取优化参数失败")
        return false
    end
    
    return true
end

-- 执行所有测试
print("\n=== 执行所有前缀压缩测试 ===")

local test_results = {}

-- 执行测试1
test_results[1] = test_prefix_compression_config()

-- 执行测试2
if test_results[1] then
    test_results[2] = test_storage_engine_prefix_config()
else
    test_results[2] = false
    print("跳过测试2，因为测试1失败")
end

-- 执行测试3
if test_results[2] then
    test_results[3] = test_cf_creation_with_prefix()
else
    test_results[3] = false
    print("跳过测试3，因为测试2失败")
end

-- 执行测试4
if test_results[3] then
    test_results[4] = test_data_write_and_stats()
else
    test_results[4] = false
    print("跳过测试4，因为测试3失败")
end

-- 执行测试5
if test_results[4] then
    test_results[5] = test_auto_optimization_prefix()
else
    test_results[5] = false
    print("跳过测试5，因为测试4失败")
end

-- 统计测试结果
print("\n=== 测试结果汇总 ===")
local passed = 0
local total = #test_results

for i, result in ipairs(test_results) do
    if result then
        passed = passed + 1
        print(string.format("测试%d: ✓ 通过", i))
    else
        print(string.format("测试%d: ✗ 失败", i))
    end
end

print(string.format("\n总测试数: %d, 通过: %d, 失败: %d", total, passed, total - passed))

if passed == total then
    print("\n🎉 所有前缀压缩测试通过！前缀压缩功能正常工作")
    print("✅ 前缀压缩配置模块功能正常")
    print("✅ 存储引擎前缀压缩配置正确")
    print("✅ CF创建时前缀压缩配置正确")
    print("✅ 数据写入和统计功能正常")
    print("✅ 自动优化脚本包含前缀压缩配置")
else
    print("\n❌ 部分前缀压缩测试失败，请检查相关配置和代码")
end

print("\n测试完成")