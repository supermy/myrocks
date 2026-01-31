--
-- 简单logger模块测试脚本
-- 单独测试logger模块的功能
--

print("=== Logger模块简单测试 ===")

-- 加载logger模块
local success, logger = pcall(require, "logger")
if not success then
    print("❌ Logger模块加载失败: " .. tostring(logger))
    os.exit(1)
end
print("✅ Logger模块加载成功")

-- 测试创建logger
print("\n=== 测试创建logger ===")
local test_logger = logger.create("test-logger", "INFO")
if test_logger then
    print("✅ Logger创建成功")
    
    -- 测试日志输出
    print("\n=== 测试日志输出 ===")
    test_logger:info("这是一条测试信息")
    test_logger:debug("这是一条调试信息")
    
    print("✅ 日志输出测试完成")
else
    print("❌ Logger创建失败")
end

-- 测试enable_file函数
print("\n=== 测试enable_file函数 ===")
local enable_file_func = logger.enable_file
if type(enable_file_func) == "function" then
    print("✅ enable_file是一个函数")
    
    -- 测试调用enable_file
    local success, result = pcall(function()
        return logger.enable_file(true, "logs")
    end)
    
    if success then
        print("✅ enable_file调用成功")
    else
        print("❌ enable_file调用失败: " .. tostring(result))
    end
else
    print("❌ enable_file不是函数，实际类型: " .. type(enable_file_func))
    print("enable_file的值: " .. tostring(enable_file_func))
end

print("\n=== 测试完成 ===")