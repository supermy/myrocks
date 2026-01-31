--
-- 配置加载测试脚本
-- 单独测试配置文件的加载功能
--

print("=== 配置加载测试 ===")

-- 加载配置模块
local success, config = pcall(require, "config")
if not success then
    print("❌ 配置模块加载失败: " .. tostring(config))
    os.exit(1)
end
print("✅ 配置模块加载成功")

-- 测试配置文件加载
print("\n=== 测试配置文件加载 ===")
local cfg = config.load_config("config/app.conf")
if cfg then
    print("✅ 配置文件加载成功")
    
    -- 测试配置读取
    print("\n=== 测试配置读取 ===")
    local log_level = cfg:get_string("log", "level", "INFO")
    local log_file = cfg:get_string("log", "file", "logs/stock-tsdb.log")
    local api_port = cfg:get_int("api", "port", 8080)
    
    print("日志级别: " .. tostring(log_level))
    print("日志文件: " .. tostring(log_file))
    print("API端口: " .. tostring(api_port))
    
    -- 测试日志目录提取
    print("\n=== 测试日志目录提取 ===")
    if log_file then
        local log_dir = log_file:match("(.*)/")
        print("日志目录: " .. tostring(log_dir))
        
        if log_dir then
            print("创建日志目录...")
            os.execute("mkdir -p " .. log_dir)
            print("✅ 日志目录创建成功")
        else
            print("⚠️ 日志目录为空，使用当前目录")
        end
    else
        print("❌ 日志文件配置为空")
    end
else
    print("❌ 配置文件加载失败")
    
    -- 检查配置文件是否存在
    local file = io.open("config/app.conf", "r")
    if file then
        print("✅ 配置文件存在")
        file:close()
    else
        print("❌ 配置文件不存在")
    end
end

print("\n=== 测试完成 ===")