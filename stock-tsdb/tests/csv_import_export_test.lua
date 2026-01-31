-- CSV导入导出功能测试脚本
-- 测试v3版本存储引擎的CSV格式业务数据导入导出功能

local V3StorageEngine = require "lua.tsdb_storage_engine_v3_rocksdb"
local TSDBStorageEngineIntegrated = require "lua.tsdb_storage_engine_integrated"

-- 测试配置
local test_config = {
    data_dir = "./test_data",
    cold_data_threshold_days = 7
}

-- 创建测试数据目录
os.execute("mkdir -p ./test_data")

-- 测试函数
local function test_csv_import_export()
    print("=== CSV导入导出功能测试 ===")
    
    -- 1. 测试V3存储引擎
    print("\n1. 测试V3存储引擎CSV功能")
    local v3_engine = V3StorageEngine:new(test_config)
    local success = v3_engine:initialize()
    
    if not success then
        print("V3存储引擎初始化失败")
        return false
    end
    
    -- 获取支持的CSV格式
    local formats = v3_engine:get_csv_formats()
    if formats then
        print("支持的CSV格式:")
        for business_type, format_info in pairs(formats) do
            print(string.format("  %s: %s", business_type, format_info.description))
            print("    列: " .. table.concat(format_info.columns, ", "))
        end
    else
        print("获取CSV格式失败")
        return false
    end
    
    -- 创建测试CSV文件
    local test_csv_content = [[timestamp,stock_code,market,open,high,low,close,volume,amount
1609459200,000001,SZ,10.5,11.2,10.3,10.8,1000000,10800000
1609545600,000001,SZ,10.8,11.5,10.6,11.2,1200000,13440000
1609632000,000001,SZ,11.2,11.8,11.0,11.5,1500000,17250000
1609718400,000002,SH,25.0,26.5,24.8,25.8,800000,20640000
1609804800,000002,SH,25.8,26.8,25.5,26.2,900000,23580000
]]
    
    local test_file = io.open("./test_data/test_stock_data.csv", "w")
    if test_file then
        test_file:write(test_csv_content)
        test_file:close()
        print("创建测试CSV文件成功")
    else
        print("创建测试CSV文件失败")
        return false
    end
    
    -- 验证CSV格式
    local valid, validation_result = v3_engine:validate_csv_format("./test_data/test_stock_data.csv", "stock_quotes")
    if valid then
        print("CSV格式验证成功")
    else
        print("CSV格式验证失败: " .. tostring(validation_result))
        return false
    end
    
    -- 导入CSV数据
    print("开始导入CSV数据...")
    local import_success, import_result = v3_engine:import_csv_data("./test_data/test_stock_data.csv", "stock_quotes", {
        batch_size = 100
    })
    
    if import_success then
        print("CSV数据导入成功:")
        print("  导入数量: " .. import_result.imported_count)
        print("  错误数量: " .. import_result.error_count)
        print("  成功率: " .. string.format("%.2f%%", import_result.success_rate))
    else
        print("CSV数据导入失败: " .. tostring(import_result))
        return false
    end
    
    -- 导出CSV数据
    print("开始导出CSV数据...")
    local export_success, export_result = v3_engine:export_csv_data(
        "./test_data/exported_stock_data.csv", 
        "stock_quotes", 
        1609459200,  -- 开始时间
        1609804800,  -- 结束时间
        {}
    )
    
    if export_success then
        print("CSV数据导出成功:")
        print("  导出数量: " .. export_result.exported_count)
        print("  文件路径: " .. export_result.file_path)
        
        -- 验证导出的文件
        local export_file = io.open("./test_data/exported_stock_data.csv", "r")
        if export_file then
            local content = export_file:read("*all")
            export_file:close()
            print("导出文件内容预览:")
            print(string.sub(content, 1, 200) .. "...")
        end
    else
        print("CSV数据导出失败: " .. tostring(export_result))
        return false
    end
    
    -- 2. 测试集成版本存储引擎
    print("\n2. 测试集成版本存储引擎CSV功能")
    local integrated_config = {
        data_dir = "./test_data_integrated",
        node_id = "test-node-1",
        cluster_name = "test-cluster"
    }
    
    local integrated_engine = TSDBStorageEngineIntegrated:new(integrated_config)
    local init_success = integrated_engine:init()
    
    if init_success then
        -- 测试集成版本的CSV导入
    local integrated_import_success, integrated_import_result = integrated_engine:import_csv_data(
        "./test_data/test_stock_data.csv", 
        "stock_quotes", 
        {batch_size = 50}
    )
        
        if integrated_import_success then
            print("集成版本CSV导入成功:")
            print("  导入数量: " .. integrated_import_result.imported_count)
        else
            print("集成版本CSV导入失败: " .. tostring(integrated_import_result))
        end
        
        -- 测试集成版本的CSV导出
        local integrated_export_success, integrated_export_result = integrated_engine:export_csv_data(
            "./test_data/exported_integrated_data.csv",
            "stock_quotes",
            1609459200,
            1609804800,
            {}
        )
        
        if integrated_export_success then
            print("集成版本CSV导出成功:")
            print("  导出数量: " .. integrated_export_result.exported_count)
        else
            print("集成版本CSV导出失败: " .. tostring(integrated_export_result))
        end
    else
        print("集成版本存储引擎初始化失败")
    end
    
    -- 3. 测试其他业务类型
    print("\n3. 测试其他业务类型CSV功能")
    
    -- 创建IOT测试数据
    local iot_csv_content = [[timestamp,device_id,sensor_type,value,unit,location,status
1609459200,device-001,temperature,25.5,C,room-101,normal
1609545600,device-001,temperature,26.2,C,room-101,normal
1609632000,device-002,humidity,65.0,%,room-102,normal
1609718400,device-002,humidity,63.5,%,room-102,normal
]]
    
    local iot_file = io.open("./test_data/test_iot_data.csv", "w")
    if iot_file then
        iot_file:write(iot_csv_content)
        iot_file:close()
        print("创建IOT测试CSV文件成功")
    end
    
    -- 导入IOT数据
    local iot_success, iot_result = v3_engine:import_csv_data("./test_data/test_iot_data.csv", "iot_data", {})
    if iot_success then
        print("IOT数据导入成功: " .. iot_result.imported_count .. " 条记录")
    else
        print("IOT数据导入失败: " .. tostring(iot_result))
    end
    
    -- 清理测试文件
    -- os.execute("rm -f ./test_stock_data.csv ./test_iot_data.csv ./exported_stock_data.csv ./exported_integrated_data.csv")
    -- os.execute("rm -rf ./test_data ./test_data_integrated")
    
    print("\n=== CSV导入导出功能测试完成 ===")
    return true
end

-- 运行测试
local success = test_csv_import_export()

if success then
    print("\n✅ 所有CSV功能测试通过！")
else
    print("\n❌ CSV功能测试失败！")
end

return success