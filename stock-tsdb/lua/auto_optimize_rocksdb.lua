#!/usr/bin/env luajit
-- auto_optimize_rocksdb.lua
-- 自动检测系统硬件并优化RocksDB参数的脚本

local HardwareDetector = require "hardware_detector"
local json = require "json"

-- 命令行参数解析
local function parse_args()
    local args = {}
    local data_dir = nil
    local output_file = nil
    local format = "lua"  -- 默认输出格式
    local silent = false
    
    for i = 1, #arg do
        if arg[i] == "--data-dir" and i + 1 <= #arg then
            data_dir = arg[i + 1]
            i = i + 1
        elseif arg[i] == "--output" and i + 1 <= #arg then
            output_file = arg[i + 1]
            i = i + 1
        elseif arg[i] == "--format" and i + 1 <= #arg then
            format = arg[i + 1]
            i = i + 1
        elseif arg[i] == "--silent" then
            silent = true
        elseif arg[i] == "--help" or arg[i] == "-h" then
            return nil, true
        end
    end
    
    return {data_dir = data_dir, output_file = output_file, format = format, silent = silent}
end

-- 显示帮助信息
local function show_help()
    print([[
Usage: luajit auto_optimize_rocksdb.lua [options]
Options:
  --data-dir <path>     指定数据目录路径，用于检测该目录所在磁盘的信息（默认为当前目录）
  --output <file>       将优化参数保存到指定文件
  --format <format>     指定输出格式（lua或json，默认为lua）
  --silent              静默模式，不输出硬件摘要信息
  --help, -h            显示此帮助信息
]])
end

-- 主函数
local function main()
    -- 解析命令行参数
    local args, show_help_flag = parse_args()
    
    if show_help_flag then
        show_help()
        return 0
    end
    
    if not args then
        print("参数解析错误")
        show_help()
        return 1
    end
    
    -- 创建硬件检测器实例
    local detector = HardwareDetector:new()
    
    -- 非静默模式下显示硬件摘要
    if not args.silent then
        detector:print_summary()
    end
    
    -- 生成优化参数
    local params = detector:get_optimized_rocksdb_params(args.data_dir)
    
    -- 格式化输出
    local output
    if args.format == "json" then
        output = json.encode(params, {indent = true})
    else
        -- Lua格式
        output = detector:generate_config_string(params)
    end
    
    -- 输出结果
    if args.output_file then
        local success, message = detector:save_config_to_file(params, args.output_file)
        if success then
            if not args.silent then
                print(message)
            end
        else
            print("错误: " .. message)
            return 1
        end
    else
        -- 直接输出到控制台
        print("\n=== 优化后的RocksDB参数 ===")
        print(output)
        print("==========================\n")
    end
    
    return 0
end

-- 执行主函数
os.exit(main())