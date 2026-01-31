#!/usr/bin/env luajit

-- 启动所有业务实例的脚本
-- 为股票行情、IOT、金融行情、订单、支付、库存、短信下发等业务启动独立的数据库实例

-- 设置包路径以包含lib目录
local base_path = "/Users/moyong/project/ai/myrocks/stock-tsdb"
package.cpath = package.cpath .. ";" .. base_path .. "/lib/?.so"

-- 设置Lua模块路径以包含lua目录
package.path = package.path .. ";" .. base_path .. "/lua/?.lua"

-- 确保cjson模块可以正确加载
package.cpath = package.cpath .. ";" .. base_path .. "/lib/cjson.so"

-- 导入必要的模块
local BusinessInstanceManager = require "lua.business_instance_manager"

-- 主函数
local function main()
    print("=== 业务实例启动脚本 ===")
    print("开始启动所有业务数据库实例...")
    print("")
    
    -- 创建业务实例管理器
    local instance_manager = BusinessInstanceManager:new("business_instance_config.json")
    
    -- 启动所有业务实例
    local success = instance_manager:start_all_instances()
    
    if success then
        print("")
        print("✅ 所有业务实例启动成功!")
        print("")
        
        -- 显示实例状态
        local statuses = instance_manager:get_all_instances_status()
        print("=== 业务实例状态 ===")
        
        for business_type, status in pairs(statuses) do
            if status.status == "running" then
                print(string.format("✅ %s: 端口 %d, 运行时间 %d 秒", 
                    business_type, status.port, status.uptime))
            else
                print(string.format("❌ %s: 未运行", business_type))
            end
        end
        
        print("")
        print("=== 业务实例端口映射 ===")
        print("股票行情 (stock_quotes): 端口 6380")
        print("物联网数据 (iot_data): 端口 6381") 
        print("金融行情 (financial_quotes): 端口 6382")
        print("订单数据 (orders): 端口 6383")
        print("支付数据 (payments): 端口 6384")
        print("库存数据 (inventory): 端口 6385")
        print("短信下发 (sms): 端口 6386")
        print("")
        print("💡 提示: 每个业务实例都有独立的数据库文件、配置和端口，互不干扰")
        print("")
        
        -- 健康检查
        local health = instance_manager:health_check()
        if health.healthy then
            print("✅ 所有业务实例健康状态正常")
        else
            print("⚠️  部分业务实例健康状态异常")
            for business_type, detail in pairs(health.details) do
                print(string.format("   %s: %s", business_type, detail))
            end
        end
        
        print("")
        print("🚀 业务实例启动完成，可以开始使用!")
        
        -- 保持脚本运行，等待用户中断
        print("")
        print("按 Ctrl+C 停止所有业务实例...")
        
        -- 设置信号处理
        local interrupted = false
        local function signal_handler()
            interrupted = true
        end
        
        -- 注册信号处理（简化版本）
        local function setup_signal_handler()
            -- 在Lua中处理信号比较复杂，这里使用简单的循环检查
        end
        
        -- 主循环
        while not interrupted do
            os.execute("sleep 1")
            
            -- 定期健康检查
            local current_health = instance_manager:health_check()
            if not current_health.healthy then
                print("⚠️  检测到不健康的实例，尝试重启...")
                instance_manager:reload_config()
            end
        end
        
    else
        print("")
        print("❌ 业务实例启动失败!")
        print("请检查配置文件和日志输出")
        os.exit(1)
    end
    
    -- 清理资源
    print("")
    print("正在停止所有业务实例...")
    instance_manager:stop_all_instances()
    print("✅ 所有业务实例已停止")
end

-- 错误处理
local function protected_main()
    local success, err = pcall(main)
    if not success then
        print("❌ 脚本执行错误: " .. tostring(err))
        print("")
        print("💡 可能的原因:")
        print("1. 配置文件格式错误")
        print("2. 端口被占用")
        print("3. 权限不足")
        print("4. 依赖模块缺失")
        os.exit(1)
    end
end

-- 运行脚本
protected_main()