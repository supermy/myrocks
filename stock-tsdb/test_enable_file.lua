-- 测试enable_file函数
print("=== 测试enable_file函数 ===")

-- 加载logger模块
local logger = require("logger")

-- 检查enable_file的类型
print("enable_file类型:", type(logger.enable_file))
print("enable_file值:", tostring(logger.enable_file))

-- 如果是函数，测试调用
if type(logger.enable_file) == "function" then
    print("✅ enable_file是一个函数")
    
    -- 测试调用enable_file
    local success, result = pcall(function()
        return logger.enable_file(true, "logs")
    end)
    
    if success then
        print("✅ enable_file调用成功")
    else
        print("❌ enable_file调用失败:", result)
    end
else
    print("❌ enable_file不是函数")
end