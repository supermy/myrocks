#!/usr/bin/env luajit

-- 测试API服务器模块
package.path = package.path .. ";./lua/?.lua"

-- 加载API服务器模块
local api_server = require "api_server"

print("=== API服务器模块测试 ===")

-- 创建API服务器实例
local config = {
    host = "0.0.0.0",
    port = 8080,
    ssl_enabled = false
}

local server = api_server.create_server(config)

-- 检查对象类型
print("服务器对象类型:", type(server))
print("服务器对象:", server)

-- 检查是否有start方法
print("是否有start方法:", type(server.start) == "function")

-- 检查元表
local mt = getmetatable(server)
print("元表:", mt)
if mt then
    print("元表索引:", mt.__index)
    print("元表索引类型:", type(mt.__index))
    
    -- 检查元表索引中是否有start方法
    if type(mt.__index) == "table" then
        print("元表索引中是否有start方法:", type(mt.__index.start) == "function")
    end
end

-- 尝试调用start方法
print("\n=== 测试start方法 ===")
local success, result = pcall(function()
    return server:start()
end)

if success then
    print("start方法调用成功:", result)
else
    print("start方法调用失败:", result)
end