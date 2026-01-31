#!/usr/bin/env luajit

-- 元数据Web管理服务器启动脚本

-- 设置包路径
package.path = package.path .. ";./lua/?.lua;./?.lua;../lua/?.lua;../?.lua"
package.cpath = package.cpath .. ";./lib/?.so;../lib/?.so"

-- 导入必要的模块
local MetadataWebServer = require "metadata_web_server"
local ConfigManager = require "config_manager"

-- 创建配置管理器实例
local config_manager = ConfigManager:new("./data/config_db")

-- 初始化配置管理器
print("正在初始化配置管理器...")
local success, err = config_manager:initialize()
if not success then
    print("配置管理器初始化失败: " .. tostring(err))
    os.exit(1)
end
print("配置管理器初始化成功")

-- 创建Web服务器配置
local web_config = {
    port = 8080,
    bind_addr = "0.0.0.0",
    config_manager = config_manager,
    auth_config = {
        enabled = true,  -- 启用认证
        username = "admin",  -- 默认用户名
        password = "admin123",  -- 默认密码
        session_timeout = 3600,  -- 会话超时时间（秒）
        require_auth_for_api = true  -- API接口需要认证
    }
}

-- 创建Web服务器实例
local web_server = MetadataWebServer:new(web_config)

-- 启动Web服务器
print("正在启动元数据Web服务器...")
success, err = web_server:start()
if not success then
    print("Web服务器启动失败: " .. tostring(err))
    os.exit(1)
end

print("元数据Web服务器已启动")
print("管理界面: http://localhost:8080")

-- 处理信号，优雅关闭
local function shutdown(signal)
    print("\n收到信号 " .. signal .. ", 正在关闭服务器...")
    web_server:stop()
    print("服务器已关闭")
    os.exit(0)
end

-- 注册信号处理
local signals = {"SIGINT", "SIGTERM"}
for _, sig in ipairs(signals) do
    if pcall(function() os.setenv("LUA_SIGNAL_HANDLERS", "1") end) then
        -- 使用Lua信号处理
        local signal = require "signal"
        if signal then
            signal.signal(sig, function() shutdown(sig) end)
        end
    end
end

-- 保持主线程运行
while true do
    os.execute("sleep 1")
end