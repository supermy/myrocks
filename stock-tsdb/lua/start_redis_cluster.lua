#!/usr/bin/env lua
--
-- Redis集群服务器启动脚本
-- 监听6379端口，集成ZeroMQ集群通信
--

-- 设置Lua路径以使用lib目录下的cjson.so和本地安装的包
package.cpath = package.cpath .. ";../lib/?.so;./lib/?.so;./?.so"

local redis_cluster_server = require "redis_cluster_server"
local tsdb = require "tsdb"

-- 配置参数
local config = {
    port = 6379,  -- Redis标准端口
    bind_addr = "127.0.0.1",
    node_id = "redis_node_1",
    cluster_port = 5555,
    cluster_nodes = {
        -- 可以添加其他集群节点地址
        -- "127.0.0.1:5556",
        -- "127.0.0.1:5557"
    }
}

-- 解析命令行参数
for i = 1, #arg do
    if arg[i] == "--port" and arg[i+1] then
        config.port = tonumber(arg[i+1])
    elseif arg[i] == "--bind" and arg[i+1] then
        config.bind_addr = arg[i+1]
    elseif arg[i] == "--node-id" and arg[i+1] then
        config.node_id = arg[i+1]
    elseif arg[i] == "--cluster-port" and arg[i+1] then
        config.cluster_port = tonumber(arg[i+1])
    elseif arg[i] == "--cluster-nodes" and arg[i+1] then
        -- 解析集群节点列表，格式: node1:port1,node2:port2
        local nodes = {}
        for node in arg[i+1]:gmatch("[^,]+") do
            table.insert(nodes, node)
        end
        config.cluster_nodes = nodes
    elseif arg[i] == "--help" then
        print("Usage: lua start_redis_cluster.lua [OPTIONS]")
        print("")
        print("Options:")
        print("  --port PORT           Redis服务端口 (default: 6379)")
        print("  --bind ADDR           绑定地址 (default: 127.0.0.1)")
        print("  --node-id ID          节点标识符 (default: redis_node_1)")
        print("  --cluster-port PORT   集群通信端口 (default: 5555)")
        print("  --cluster-nodes LIST   集群节点列表，逗号分隔 (default: none)")
        print("  --help                显示帮助信息")
        print("")
        print("Examples:")
        print("  lua start_redis_cluster.lua --port 6379 --bind 0.0.0.0")
        print("  lua start_redis_cluster.lua --cluster-nodes 127.0.0.1:5556,127.0.0.1:5557")
        os.exit(0)
    end
end

-- 直接使用TSDB模块（纯Lua实现，无需创建实例）
config.tsdb = tsdb

-- 创建并启动服务器
local server = redis_cluster_server.create_server(config)

-- 设置信号处理
local function signal_handler(signal)
    print("\nReceived signal " .. signal .. ", shutting down...")
    server:stop()
    os.exit(0)
end

-- 注册信号处理
pcall(function()
    -- 尝试注册信号处理（在某些平台上可能不可用）
    os.execute("trap '' INT TERM")
end)

-- 主函数
local function main()
    print("Starting Redis cluster server...")
    print("Redis port: " .. config.port)
    print("Cluster port: " .. config.cluster_port)
    print("Node ID: " .. config.node_id)
    print("Cluster nodes: " .. table.concat(config.cluster_nodes, ", "))
    print("")
    
    local success, err = server:start()
    if not success then
        print("Failed to start server: " .. tostring(err))
        os.exit(1)
    end
end

-- 运行主函数
local success, err = xpcall(main, debug.traceback)
if not success then
    print("Error: " .. tostring(err))
    server:stop()
    os.exit(1)
end