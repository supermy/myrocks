-- 测试API服务器修复
print("=== 测试API服务器修复 ===")

-- 设置Lua路径
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
package.cpath = package.cpath .. ";/Users/moyong/.luarocks/lib/lua/5.2/?.so"

-- 加载API服务器模块
local api_server = require("api_server")

-- 创建API服务器实例
print("创建API服务器实例...")
local server = api_server.create_server({
    host = "0.0.0.0",
    port = 8080,
    tsdb_core = {} -- 模拟TSDB核心
})

print("API服务器对象:", server)
print("API服务器类型:", type(server))

-- 检查对象结构
if type(server) == "table" then
    print("对象字段数量:", #server)
    print("对象是否有host字段:", server.host ~= nil)
    print("对象是否有port字段:", server.port ~= nil)
    print("对象是否有start方法:", server.start ~= nil)
    
    if server.host then
        print("host字段值:", server.host)
    end
    if server.port then
        print("port字段值:", server.port)
    end
end

-- 测试启动方法
print("\n测试启动方法...")
local success, error = server:start()
if success then
    print("✅ API服务器启动成功")
else
    print("❌ API服务器启动失败:", error)
end

print("\n=== 测试完成 ===")