#!/usr/bin/env luajit

--
-- Redis TCP服务器启动脚本
-- 启动基于libevent的Redis协议接口服务器
--

-- 设置包路径以包含lib目录
package.cpath = package.cpath .. ";./lib/?.so"

-- 导入必要的模块
local RedisTCPServer = require "lua.redis_tcp_server".RedisTCPServer
local BusinessInstanceManager = require "lua.business_instance_manager"

-- 配置参数
local config = {
    port = 6379,  -- Redis标准端口
    bind_addr = "127.0.0.1",
    max_connections = 10000,
    node_id = "redis_tcp_server_" .. os.date("%Y%m%d_%H%M%S"),
    cluster_nodes = {
        {host = "127.0.0.1", port = 5555},
        {host = "127.0.0.1", port = 5556},
        {host = "127.0.0.1", port = 5557}
    }
}

-- 信号处理函数
local function setup_signal_handlers(server)
    -- 处理Ctrl+C信号
    local function signal_handler(signal)
        print("\n接收到信号 " .. signal .. ", 正在停止服务器...")
        server:stop()
        os.exit(0)
    end
    
    -- 设置信号处理（简化实现）
    print("按Ctrl+C停止服务器")
end

-- 健康检查函数
local function health_check(server)
    local stats = server:get_stats()
    print(string.format("[%s] 服务器运行状态: %s, 连接数: %d, 命令数: %d", 
        os.date("%Y-%m-%d %H:%M:%S"),
        stats.running and "运行中" or "已停止",
        stats.current_connections,
        stats.total_commands
    ))
end

-- 主函数
local function main()
    print("=== Redis TCP服务器启动 ===")
    print("启动时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
    print("版本: 1.0.0")
    print("")
    
    -- 创建Redis TCP服务器实例
    local server = RedisTCPServer:new(config)
    
    -- 启动服务器
    local success, err = server:start()
    if not success then
        print("错误: 无法启动服务器 - " .. (err or "unknown error"))
        os.exit(1)
    end
    
    -- 设置信号处理
    setup_signal_handlers(server)
    
    -- 启动健康检查定时器（每30秒检查一次）
    local health_check_timer = 0
    
    -- 主循环
    print("服务器已启动，开始处理请求...")
    print("")
    
    while server.running do
        -- 运行服务器主循环
        local success, err = server:run()
        if not success then
            print("服务器运行错误: " .. (err or "unknown error"))
            break
        end
        
        -- 定期健康检查
        health_check_timer = health_check_timer + 1
        if health_check_timer >= 30 then  -- 每30秒检查一次
            health_check(server)
            health_check_timer = 0
        end
        
        -- 短暂休眠，避免CPU占用过高
        os.execute("sleep 0.1")
    end
    
    print("服务器已停止")
end

-- 运行主函数
if pcall(main) then
    print("服务器正常退出")
else
    print("服务器异常退出")
    os.exit(1)
end