-- auto_optimize_rocksdb_simple.lua
-- 使用简化版硬件检测器自动优化RocksDB参数

-- 加载简化版硬件检测器
local HardwareDetector = require("hardware_detector_simple")

-- 默认数据目录
local DEFAULT_DATA_DIR = "./data"

-- 主函数
local function main()
    print("=== RocksDB 参数自动优化工具 ===")
    print("正在检测系统硬件信息...")
    
    -- 创建硬件检测器实例
    local detector = HardwareDetector:new()
    
    -- 打印硬件信息摘要
    detector:print_summary()
    
    -- 获取优化的RocksDB参数
    print("正在生成优化的RocksDB参数...")
    local optimized_params = detector:get_optimized_rocksdb_params(DEFAULT_DATA_DIR)
    
    -- 打印优化后的参数
    print("\n=== 优化后的RocksDB参数 ===")
    print(detector:generate_config_string(optimized_params))
    
    -- 保存配置到文件
    local config_file = "./rocksdb_optimized_config.lua"
    local success, message = detector:save_config_to_file(optimized_params, config_file)
    
    if success then
        print("\n" .. message)
        print("\n优化完成！您可以将生成的配置文件导入到您的RocksDB应用程序中。")
    else
        print("\n错误: " .. message)
    end
    
    -- 输出集成建议
    print("\n=== 集成建议 ===")
    print("将以下代码添加到您的应用程序中以使用自动优化的参数:")
    print([[
-- 加载自动优化的配置
local optimized_config = dofile("./rocksdb_optimized_config.lua")

-- 应用配置到RocksDB选项
for key, value in pairs(optimized_config) do
    if key ~= "create_if_missing" and key ~= "is_ssd" then  -- 跳过不需要的键
        options[key] = value
    end
end

-- 应用前缀压缩配置（如果启用）
if optimized_config.enable_prefix_compression then
    -- 设置前缀提取器
    options:set_prefix_extractor(optimized_config.prefix_extractor_length)
    
    -- 设置memtable前缀布隆过滤器大小比例
    options:set_memtable_prefix_bloom_size_ratio(optimized_config.memtable_prefix_bloom_size_ratio)
end]])
end

-- 运行主函数
if arg and arg[0] == "auto_optimize_rocksdb_simple.lua" then
    main()
end

-- 导出主函数供其他脚本使用
return { main = main }