--
-- 系统启动测试脚本
-- 测试股票行情数据TSDB系统的基本启动流程
--

print("=== 股票行情数据TSDB系统启动测试 ===")

-- 加载主程序模块
local success, tsdb = pcall(require, "lua.main")
if not success then
    print("❌ 主程序模块加载失败: " .. tostring(tsdb))
    os.exit(1)
end
print("✅ 主程序模块加载成功")

-- 创建系统实例
local system = tsdb.create_system("config/app.conf")

-- 测试系统初始化
print("\n=== 测试系统初始化 ===")
local init_success, init_error = system:initialize()
if init_success then
    print("✅ 系统初始化成功")
    
    -- 测试系统启动
    print("\n=== 测试系统启动 ===")
    local start_success, start_error = system:start()
    if start_success then
        print("✅ 系统启动成功")
        
        -- 模拟运行几秒钟
        print("\n=== 模拟系统运行 ===")
        print("系统正在运行中...")
        
        -- 获取系统状态
        local status = system:get_status()
        print("系统状态: " .. tostring(status))
        
        -- 测试系统停止
        print("\n=== 测试系统停止 ===")
        local stop_success, stop_error = system:stop()
        if stop_success then
            print("✅ 系统停止成功")
        else
            print("❌ 系统停止失败: " .. tostring(stop_error))
        end
    else
        print("❌ 系统启动失败: " .. tostring(start_error))
    end
else
    print("❌ 系统初始化失败: " .. tostring(init_error))
end

print("\n=== 测试完成 ===")
print("系统启动测试流程执行完毕")