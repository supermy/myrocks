-- 业务数据Web服务器启动脚本
-- 提供SQL查询和聚合函数支持的Web界面

-- 设置Lua模块路径
package.path = package.path .. ";./?.lua;./lua/?.lua;./web/?.lua;/Users/moyong/.luarocks/share/lua/5.2/?.lua;/Users/moyong/.luarocks/share/lua/5.2/?/init.lua"
package.cpath = package.cpath .. ";/Users/moyong/.luarocks/lib/lua/5.2/?.so"

-- 添加lua目录到模块路径
package.path = package.path .. ";../lua/?.lua"

local socket = require "socket"
local http = require "socket.http"
local ltn12 = require "ltn12"
local cjson = require "cjson"
local url = require "socket.url"

-- 导入业务数据Web模块
local BusinessDataWeb = require "business_data_web"

-- 配置
local PORT = 8081
local HOST = "0.0.0.0"

-- 初始化业务数据Web
local business_web = BusinessDataWeb:new()

-- HTTP请求处理函数
local function handle_request(method, path, headers, body)
    local response = {
        status = 200,
        headers = {},
        body = ""
    }
    
    -- 设置默认响应头
    response.headers["Content-Type"] = "text/html; charset=utf-8"
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    
    -- 处理OPTIONS请求（CORS预检）
    if method == "OPTIONS" then
        response.status = 200
        response.body = ""
        return response
    end
    
    -- 路由处理
    if path == "/" or path == "/index.html" then
        -- 主页面
        response.body = business_web:generate_html()
        
    elseif path == "/business/tables" and method == "GET" then
        -- 获取数据表列表
        response.headers["Content-Type"] = "application/json"
        local result = business_web:handle_get_tables()
        response.body = cjson.encode(result)
        
    elseif path == "/business/schema" and method == "GET" then
        -- 获取表结构
        response.headers["Content-Type"] = "application/json"
        local query_params = url.parse_query(path:match("%?(.*)") or "")
        local result = business_web:handle_get_schema(query_params)
        response.body = cjson.encode(result)
        
    elseif path == "/business/query" and method == "POST" then
        -- 执行SQL查询
        response.headers["Content-Type"] = "application/json"
        
        local request_data
        if body and body ~= "" then
            local ok, data = pcall(cjson.decode, body)
            if ok then
                request_data = data
            end
        end
        
        if not request_data then
            response.status = 400
            response.body = cjson.encode({
                success = false,
                error = "无效的请求数据"
            })
        else
            local result = business_web:handle_sql_query(request_data)
            response.body = cjson.encode(result)
        end
        
    elseif path == "/health" then
        -- 健康检查
        response.headers["Content-Type"] = "application/json"
        response.body = cjson.encode({
            status = "healthy",
            service = "business_data_web",
            port = PORT,
            timestamp = os.time()
        })
        
    else
        -- 404 页面
        response.status = 404
        response.body = [[
            <!DOCTYPE html>
            <html>
            <head><title>404 - 页面未找到</title></head>
            <body>
                <h1>404 - 页面未找到</h1>
                <p>请求的页面不存在: ]] .. path .. [[</p>
                <p><a href="/">返回首页</a></p>
            </body>
            </html>
        ]]
    end
    
    return response
end

-- 创建HTTP服务器
local server = socket.bind(HOST, PORT)
if not server then
    print("错误: 无法在端口 " .. PORT .. " 上启动服务器")
    os.exit(1)
end

print("🚀 业务数据Web服务器启动成功")
print("📍 服务地址: http://" .. HOST .. ":" .. PORT)
print("📊 功能: SQL查询、聚合函数、数据可视化")
print("⏰ 启动时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
print("-" .. string.rep("-", 50))

-- 主服务器循环
while true do
    local client = server:accept()
    
    if client then
        -- 在新协程中处理请求
        local co = coroutine.create(function()
            -- 读取请求
            local request_line = client:receive()
            if not request_line then
                client:close()
                return
            end
            
            -- 解析请求行
            local method, path, http_version = request_line:match("^(%u+)%s+(.-)%s+(HTTP/%d%.%d)$")
            if not method then
                client:close()
                return
            end
            
            -- 读取请求头
            local headers = {}
            while true do
                local line = client:receive()
                if not line or line == "" then
                    break
                end
                
                local key, value = line:match("^([^:]+):%s*(.+)$")
                if key and value then
                    headers[key:lower()] = value
                end
            end
            
            -- 读取请求体（如果有）
            local body = ""
            local content_length = tonumber(headers["content-length"])
            if content_length and content_length > 0 then
                body = client:receive(content_length)
            end
            
            -- 处理请求
            local response = handle_request(method, path, headers, body)
            
            -- 构建响应头
            local response_headers = ""
            for key, value in pairs(response.headers) do
                response_headers = response_headers .. key .. ": " .. value .. "\r\n"
            end
            
            -- 发送响应
            local status_line = "HTTP/1.1 " .. response.status .. " " .. 
                (response.status == 200 and "OK" or 
                 response.status == 404 and "Not Found" or 
                 response.status == 400 and "Bad Request" or 
                 "Unknown") .. "\r\n"
            
            client:send(status_line)
            client:send(response_headers)
            client:send("\r\n")
            client:send(response.body)
            
            client:close()
            
            -- 记录访问日志
            print(string.format("[%s] %s %s %d", 
                os.date("%Y-%m-%d %H:%M:%S"), 
                method, path, response.status))
        end)
        
        -- 运行协程
        local ok, err = coroutine.resume(co)
        if not ok then
            print("协程错误: " .. tostring(err))
        end
    end
    
    -- 短暂休眠以避免CPU过度使用
    socket.sleep(0.001)
end