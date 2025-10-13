#!/usr/bin/env luajit

-- 元数据Web管理服务器
-- 基于libevent的HTTP服务器，提供配置管理和数据查看界面

local ffi = require "ffi"
local bit = require "bit"

-- 设置Lua包路径以包含lib目录
package.path = package.path .. ";../lib/?.lua;./lib/?.lua"
package.cpath = package.cpath .. ";../lib/?.dylib;./lib/?.dylib;../lib/?.so;./lib/?.so"

-- 尝试加载cjson模块
local json = nil
local cjson_ok, cjson_module = pcall(require, "cjson")
if cjson_ok then
    json = cjson_module
    print("[MetadataWebServer] 成功加载cjson库")
else
    -- 尝试加载lib目录中的cjson库
    local lib_cjson_ok, lib_cjson = pcall(ffi.load, "../lib/cjson")
    if not lib_cjson_ok then
        lib_cjson_ok, lib_cjson = pcall(ffi.load, "./lib/cjson")
    end
    
    if lib_cjson_ok then
        -- 定义cjson的FFI接口
        ffi.cdef[[
            char* json_encode(lua_State* L);
            char* json_decode(lua_State* L, const char* str);
        ]]
        
        json = {}
        
        -- 包装cjson的encode函数
        function json.encode(data)
            local json_str = ffi.string(lib_cjson.json_encode(data))
            return json_str
        end
        
        -- 包装cjson的decode函数
        function json.decode(str)
            local result = lib_cjson.json_decode(str)
            if result ~= nil then
                return ffi.string(result)
            end
            return nil
        end
        
        print("[MetadataWebServer] 使用FFI加载cjson库")
    else
        -- 尝试直接使用cjson.so文件
        local cjson_paths = {
            "../lib/cjson.so",
            "./lib/cjson.so",
            "cjson.so",
            "cjson"
        }
        
        local cjson_loaded = false
        for _, path in ipairs(cjson_paths) do
            local ok, cjson_lib = pcall(ffi.load, path)
            if ok then
                -- 定义cjson的FFI接口
                ffi.cdef[[
                    char* json_encode(lua_State* L);
                    char* json_decode(lua_State* L, const char* str);
                ]]
                
                json = {}
                
                -- 包装cjson的encode函数
                function json.encode(data)
                    local json_str = ffi.string(cjson_lib.json_encode(data))
                    return json_str
                end
                
                -- 包装cjson的decode函数
                function json.decode(str)
                    local result = cjson_lib.json_decode(str)
                    if result ~= nil then
                        return ffi.string(result)
                    end
                    return nil
                end
                
                print("[MetadataWebServer] 成功加载cjson库: " .. path)
                cjson_loaded = true
                break
            end
        end
        
        if not cjson_loaded then
            print("[MetadataWebServer] 警告: 无法加载cjson库，使用简单JSON实现")
            -- 简单的JSON编码/解码实现
            json = {}
            
            -- 简单的JSON编码函数
            function json.encode(data)
                if type(data) == "table" then
                    local parts = {}
                    local is_array = true
                    
                    -- 检查是否为数组（所有键都是连续数字）
                    local max_index = 0
                    local count = 0
                    for k, v in pairs(data) do
                        if type(k) == "number" then
                            if k > max_index then
                                max_index = k
                            end
                            count = count + 1
                        else
                            is_array = false
                        end
                    end
                    
                    -- 如果是数组且键是连续的
                    if is_array and max_index == count then
                        for i = 1, max_index do
                            table.insert(parts, json.encode(data[i]))
                        end
                        return "[" .. table.concat(parts, ",") .. "]"
                    else
                        -- 处理对象
                        for k, v in pairs(data) do
                            if type(k) == "number" then
                                table.insert(parts, json.encode(v))
                            else
                                table.insert(parts, string.format('"%s":%s', k, json.encode(v)))
                            end
                        end
                        return "{" .. table.concat(parts, ",") .. "}"
                    end
                elseif type(data) == "string" then
                    return '"' .. data:gsub('"', '\\"') .. '"'
                elseif type(data) == "number" or type(data) == "boolean" then
                    return tostring(data)
                else
                    return "null"
                end
            end
            
            -- 简单的JSON解码函数（仅支持基本类型）
            function json.decode(str)
                -- 移除空白字符
                str = str:gsub("%s+", "")
                
                if str:sub(1,1) == "{" and str:sub(-1) == "}" then
                    local result = {}
                    local content = str:sub(2, -2)
                    local key, value
                    
                    -- 简单的键值对解析
                    for pair in content:gmatch("[^,}]+") do
                        local k, v = pair:match('"([^"]+)":(.+)')
                        if k and v then
                            if v:sub(1,1) == '"' then
                                result[k] = v:sub(2, -2)
                            elseif v == "true" then
                                result[k] = true
                            elseif v == "false" then
                                result[k] = false
                            elseif tonumber(v) then
                                result[k] = tonumber(v)
                            end
                        end
                    end
                    return result
                else
                    return nil
                end
            end
        end
    end
end

-- libevent HTTP服务器FFI定义
ffi.cdef[[
    // libevent基本类型
    typedef struct event_base event_base;
    typedef struct event event;
    typedef struct evhttp evhttp;
    typedef struct evhttp_request evhttp_request;
    typedef struct evkeyvalq evkeyvalq;
    typedef struct evbuffer evbuffer;
    
    // HTTP方法常量
    enum {
        EVHTTP_REQ_GET = 1,
        EVHTTP_REQ_POST = 2,
        EVHTTP_REQ_HEAD = 4,
        EVHTTP_REQ_PUT = 8,
        EVHTTP_REQ_DELETE = 16,
        EVHTTP_REQ_OPTIONS = 32,
        EVHTTP_REQ_TRACE = 64,
        EVHTTP_REQ_CONNECT = 128,
        EVHTTP_REQ_PATCH = 256
    };
    
    // 事件基础函数
    event_base* event_base_new(void);
    void event_base_free(event_base*);
    int event_base_loop(event_base*, int);
    int event_base_loopbreak(event_base*);
    
    // HTTP服务器函数
    evhttp* evhttp_new(event_base*);
    void evhttp_free(evhttp*);
    int evhttp_bind_socket(evhttp*, const char*, unsigned short);
    void evhttp_set_gencb(evhttp*, void (*cb)(evhttp_request*, void*), void*);
    void evhttp_set_allowed_methods(evhttp*, unsigned short);
    
    // HTTP请求处理函数
    const char* evhttp_request_get_uri(evhttp_request*);
    const char* evhttp_request_get_host(evhttp_request*);
    int evhttp_request_get_command(evhttp_request*);
    evkeyvalq* evhttp_request_get_input_headers(evhttp_request*);
    evkeyvalq* evhttp_request_get_output_headers(evhttp_request*);
    evbuffer* evhttp_request_get_input_buffer(evhttp_request*);
    evbuffer* evhttp_request_get_output_buffer(evhttp_request*);
    
    // 缓冲区操作
    size_t evbuffer_get_length(evbuffer*);
    int evbuffer_remove(evbuffer*, void*, size_t);
    void evbuffer_add_printf(evbuffer*, const char*, ...);
    void evbuffer_add(evbuffer*, const void*, size_t);
    
    // 头部操作
    const char* evhttp_find_header(evkeyvalq*, const char*);
    void evhttp_add_header(evkeyvalq*, const char*, const char*);
    
    // 响应函数
    void evhttp_send_reply(evhttp_request*, int, const char*, evbuffer*);
    void evhttp_send_error(evhttp_request*, int, const char*);
]]

-- 尝试加载libevent
local libevent = nil
local libevent_available = false

local libevent_paths = {
    "/usr/local/Cellar/libevent/2.0.21_1/lib/libevent.dylib",
    "/usr/local/lib/libevent.dylib",
    "/usr/lib/libevent.dylib", 
    "libevent.dylib",
    "libevent"
}

for _, path in ipairs(libevent_paths) do
    local ok, lib = pcall(ffi.load, path)
    if ok then
        libevent = lib
        libevent_available = true
        print("[MetadataWebServer] 成功加载libevent库: " .. path)
        break
    else
        print("[MetadataWebServer] 尝试加载libevent失败: " .. path)
    end
end

if not libevent_available then
    print("[MetadataWebServer] 警告: 无法加载libevent库，将使用简单的HTTP服务器实现")
end

local MetadataWebServer = {}
MetadataWebServer.__index = MetadataWebServer

function MetadataWebServer:new(config)
    local obj = setmetatable({}, MetadataWebServer)
    obj.config = config or {}
    obj.port = config.port or 8080
    obj.bind_addr = config.bind_addr or "127.0.0.1"
    obj.config_manager = config.config_manager
    obj.tsdb = config.tsdb
    
    -- HTTP服务器状态
    obj.event_base = nil
    obj.http_server = nil
    obj.running = false
    
    -- 路由处理器
    obj.routes = {}
    
    -- 认证配置
    obj.auth_config = {
        enabled = false,  -- 默认禁用认证
        username = "admin",
        password = "admin123",
        session_timeout = 3600, -- 1小时
        require_auth_for_api = true
    }
    
    -- 如果提供了认证配置，则使用提供的配置
    if config.auth_config then
        if config.auth_config.enabled ~= nil then
            obj.auth_config.enabled = config.auth_config.enabled
        end
        if config.auth_config.username then
            obj.auth_config.username = config.auth_config.username
        end
        if config.auth_config.password then
            obj.auth_config.password = config.auth_config.password
        end
        if config.auth_config.session_timeout then
            obj.auth_config.session_timeout = config.auth_config.session_timeout
        end
        if config.auth_config.require_auth_for_api ~= nil then
            obj.auth_config.require_auth_for_api = config.auth_config.require_auth_for_api
        end
    end
    
    -- 确保认证配置的所有字段都有有效值
    if not obj.auth_config.enabled then
        obj.auth_config.enabled = false
    end
    if not obj.auth_config.username then
        obj.auth_config.username = "admin"
    end
    if not obj.auth_config.password then
        obj.auth_config.password = "admin123"
    end
    if not obj.auth_config.session_timeout then
        obj.auth_config.session_timeout = 3600
    end
    if obj.auth_config.require_auth_for_api == nil then
        obj.auth_config.require_auth_for_api = true
    end
    
    -- 会话管理
    obj.sessions = {}
    
    return obj
end

-- 初始化HTTP服务器
function MetadataWebServer:initialize()
    if not libevent_available then
        return false, "libevent not available"
    end
    
    -- 创建事件基础
    self.event_base = libevent.event_base_new()
    if not self.event_base then
        return false, "failed to create event base"
    end
    
    -- 创建HTTP服务器
    self.http_server = libevent.evhttp_new(self.event_base)
    if not self.http_server then
        libevent.event_base_free(self.event_base)
        return false, "failed to create HTTP server"
    end
    
    -- 设置允许的HTTP方法（包括OPTIONS）
    local allowed_methods = bit.bor(
        libevent.EVHTTP_REQ_GET,
        libevent.EVHTTP_REQ_POST,
        libevent.EVHTTP_REQ_HEAD,
        libevent.EVHTTP_REQ_OPTIONS
    )
    libevent.evhttp_set_allowed_methods(self.http_server, allowed_methods)
    print("[MetadataWebServer] 设置允许的HTTP方法: GET|POST|HEAD|OPTIONS")
    
    -- 设置通用请求处理器
    libevent.evhttp_set_gencb(self.http_server, function(req, arg)
        self:handle_request(req)
    end, nil)
    
    -- 绑定端口
    local result = libevent.evhttp_bind_socket(self.http_server, self.bind_addr, self.port)
    if result ~= 0 then
        libevent.evhttp_free(self.http_server)
        libevent.event_base_free(self.event_base)
        return false, "failed to bind to " .. self.bind_addr .. ":" .. self.port
    end
    
    -- 注册路由
    self:register_routes()
    
    return true, "HTTP server initialized successfully"
end

-- 注册路由
function MetadataWebServer:register_routes()
    -- 认证相关路由
    self.routes["/api/auth/login"] = function(req) return self:handle_login(req) end
    self.routes["/api/auth/logout"] = function(req) return self:handle_logout(req) end
    self.routes["/api/auth/check"] = function(req) return self:handle_check_auth(req) end
    
    -- 业务路由
    self.routes["/"] = function(req) return self:serve_index(req) end
    self.routes["/api/config"] = function(req) return self:api_get_config(req) end
    self.routes["/api/config/update"] = function(req) return self:api_update_config(req) end
    self.routes["/api/metadata"] = function(req) return self:api_get_metadata(req) end
    self.routes["/api/stats"] = function(req) return self:api_get_stats(req) end
    self.routes["/api/cluster"] = function(req) return self:api_get_cluster_info(req) end
    self.routes["/api/business"] = function(req) return self:api_get_business_info(req) end
    
    -- Prometheus监控端点
    self.routes["/metrics"] = function(req) return self:handle_metrics(req) end
end

-- 处理HTTP请求
function MetadataWebServer:handle_request(req)
    local uri = ffi.string(libevent.evhttp_request_get_uri(req))
    local method = libevent.evhttp_request_get_command(req)
    
    -- 调试信息
    print("[MetadataWebServer] 收到请求: " .. uri .. " 方法: " .. method .. " (EVHTTP_REQ_OPTIONS=" .. libevent.EVHTTP_REQ_OPTIONS .. ")")
    
    -- 添加详细的方法常量调试
    print("[MetadataWebServer] 方法常量对照 - GET:" .. libevent.EVHTTP_REQ_GET .. " POST:" .. libevent.EVHTTP_REQ_POST .. " OPTIONS:" .. libevent.EVHTTP_REQ_OPTIONS)
    
    -- 首先检查是否是OPTIONS预检请求
    if method == 32 or method == libevent.EVHTTP_REQ_OPTIONS then  -- 兼容数值和常量
        print("[MetadataWebServer] 处理OPTIONS请求 (方法值: " .. method .. ")")
        self:handle_options(req)  -- 处理OPTIONS请求但不返回，让libevent处理响应
        return  -- 重要：处理完OPTIONS后立即返回，不再执行后续逻辑
    elseif method == libevent.EVHTTP_REQ_GET then
        print("[MetadataWebServer] 处理GET请求")
        -- GET请求不应该调用登录处理器，除非是检查认证状态
        if uri == "/api/auth/login" then
            return self:send_error(req, 405, "Method Not Allowed")
        end
    elseif method == libevent.EVHTTP_REQ_POST then
        print("[MetadataWebServer] 处理POST请求")
    else
        print("[MetadataWebServer] 未知请求方法: " .. method)
    end
    
    -- 其次检查是否是静态文件请求
    if uri:match("^/css/") or uri:match("^/js/") or uri:match("^/static/") then
        return self:serve_static_file(req, uri)
    end
    
    -- 认证检查逻辑
    -- 认证相关路由和主页不需要认证检查
    if uri == "/api/auth/login" or uri == "/api/auth/logout" or uri == "/api/auth/check" or uri == "/" then
        -- 这些路由不需要认证检查，直接处理
    else
        -- 对于API路由，需要认证检查
        if uri:match("^/api/") then
            if not self:check_authentication(req) then
                -- 如果是API请求，返回JSON格式的错误
                return self:send_auth_error(req)
            end
        end
    end
    
    -- 查找路由处理器
    local handler = self.routes[uri]
    if not handler then
        -- 尝试匹配前缀路由（仅匹配API路由）
        for route_path, route_handler in pairs(self.routes) do
            if uri:sub(1, #route_path) == route_path and route_path:match("^/api/") then
                handler = route_handler
                break
            end
        end
    end
    
    if handler then
        handler(req)
    elseif uri == "/" then
        self:serve_index(req)
    else
        -- 检查是否是有效的静态文件请求（只处理已知的文件扩展名）
        if uri:match("%.html$") or uri:match("%.css$") or uri:match("%.js$") or 
           uri:match("%.json$") or uri:match("%.png$") or uri:match("%.jpg$") or 
           uri:match("%.jpeg$") or uri:match("%.gif$") or uri:match("%.ico$") then
            self:serve_static_file(req, uri)
        else
            -- 忽略IDE、Vite等开发工具的请求
            if uri:find("?") or uri:find("@") or uri:find("%..%") or 
               uri:find("~") or uri:match("^/@") or uri:match("%.ts$") or 
               uri:match("%.tsx$") or uri:match("%.vue$") then
                print("[MetadataWebServer] 忽略开发工具请求: " .. uri)
                self:send_error(req, 404, "Not Found")
            else
                self:serve_static_file(req, uri)
            end
        end
    end
end

-- 提供静态文件
function MetadataWebServer:serve_static_file(req, path)
    if path == "/" then path = "/index.html" end
    
    local file_path = "./web/static" .. path
    
    -- 安全检查：防止路径遍历攻击
    if path:match("%.%.") then
        return self:send_error(req, 403, "Forbidden")
    end
    
    local file = io.open(file_path, "rb")
    
    if not file then
        print("[MetadataWebServer] 静态文件未找到: " .. file_path)
        self:send_error(req, 404, "File not found")
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local content_type = "text/plain"
    if path:match("%.html$") then
        content_type = "text/html"
    elseif path:match("%.css$") then
        content_type = "text/css"
    elseif path:match("%.js$") then
        content_type = "application/javascript"
    elseif path:match("%.json$") then
        content_type = "application/json"
    end
    
    print("[MetadataWebServer] 提供静态文件: " .. path .. " (" .. #content .. " bytes)")
    self:send_response(req, 200, content_type, content)
end

-- 处理OPTIONS预检请求
function MetadataWebServer:handle_options(req)
    print("[MetadataWebServer] handle_options: 开始处理OPTIONS请求")
    
    local headers = libevent.evhttp_request_get_output_headers(req)
    if not headers then
        print("[MetadataWebServer] handle_options: 无法获取输出头")
        return
    end
    
    -- 获取请求的来源，动态设置CORS头
    local input_headers = libevent.evhttp_request_get_input_headers(req)
    local origin_header = nil
    local request_origin = nil
    
    if input_headers then
        origin_header = libevent.evhttp_find_header(input_headers, "Origin")
        if origin_header ~= nil then
            request_origin = ffi.string(origin_header)
            print("[MetadataWebServer] handle_options: 找到Origin头: " .. request_origin)
        else
            print("[MetadataWebServer] handle_options: 未找到Origin头")
        end
    end
    
    local allowed_origins = {
        "http://localhost:8080",
        "http://localhost:8081"
    }
    
    local origin = "*"  -- 默认使用通配符
    if request_origin then
        -- 检查请求来源是否在允许列表中
        for _, allowed_origin in ipairs(allowed_origins) do
            if request_origin == allowed_origin then
                origin = request_origin
                break
            end
        end
    end
    
    print("[MetadataWebServer] handle_options: 设置CORS头，允许来源: " .. origin)
    
    -- 设置CORS头
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Origin", origin)
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Credentials", "true")
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Headers", "Content-Type, Cookie, Authorization")
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    
    -- 发送响应
    print("[MetadataWebServer] handle_options: 发送200响应")
    libevent.evhttp_send_reply(req, 200, "OK", nil)
    print("[MetadataWebServer] handle_options: OPTIONS请求处理完成")
end

-- 发送HTTP响应
function MetadataWebServer:send_response(req, code, content_type, content)
    local headers = libevent.evhttp_request_get_output_headers(req)
    libevent.evhttp_add_header(headers, "Content-Type", content_type)
    -- 获取请求的来源，动态设置CORS头
    local input_headers = libevent.evhttp_request_get_input_headers(req)
    local origin_header = libevent.evhttp_find_header(input_headers, "Origin")
    local allowed_origins = {
        "http://localhost:8080",
        "http://localhost:8081"
    }
    
    local origin = "http://localhost:8080"  -- 默认源
    if origin_header ~= nil then
        local request_origin = ffi.string(origin_header)
        -- 检查请求来源是否在允许列表中
        for _, allowed_origin in ipairs(allowed_origins) do
            if request_origin == allowed_origin then
                origin = request_origin
                break
            end
        end
    end
    
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Origin", origin)
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Credentials", "true")
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Headers", "Content-Type, Cookie, Authorization")
    libevent.evhttp_add_header(headers, "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    
    local output_buffer = libevent.evhttp_request_get_output_buffer(req)
    libevent.evbuffer_add(output_buffer, content, #content)
    
    -- 根据状态码设置正确的状态描述
    local reason = "OK"
    if code == 401 then
        reason = "Unauthorized"
    elseif code == 403 then
        reason = "Forbidden"
    elseif code == 404 then
        reason = "Not Found"
    elseif code == 500 then
        reason = "Internal Server Error"
    end
    
    libevent.evhttp_send_reply(req, code, reason, output_buffer)
end

-- 发送错误响应
function MetadataWebServer:send_error(req, code, message)
    libevent.evhttp_send_error(req, code, message)
end

-- 获取请求体
function MetadataWebServer:get_request_body(req)
    local input_buffer = libevent.evhttp_request_get_input_buffer(req)
    local length = libevent.evbuffer_get_length(input_buffer)
    
    if length > 0 then
        local buffer = ffi.new("char[?]", length)
        libevent.evbuffer_remove(input_buffer, buffer, length)
        return ffi.string(buffer, length)
    end
    
    return ""
end

-- 认证相关方法

-- 生成会话ID
function MetadataWebServer:generate_session_id()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local session_id = ""
    for i = 1, 32 do
        local rand = math.random(1, #chars)
        session_id = session_id .. chars:sub(rand, rand)
    end
    return session_id
end

-- 创建新会话
function MetadataWebServer:create_session(username)
    local session_id = self:generate_session_id()
    local session = {
        id = session_id,
        username = username,
        created_at = os.time(),
        last_accessed = os.time()
    }
    
    self.sessions[session_id] = session
    
    -- 清理过期会话
    self:cleanup_expired_sessions()
    
    return session_id
end

-- 验证会话
function MetadataWebServer:validate_session(session_id)
    if not session_id or not self.sessions[session_id] then
        return false
    end
    
    local session = self.sessions[session_id]
    
    -- 检查会话是否过期
    if os.time() - session.last_accessed > self.auth_config.session_timeout then
        self.sessions[session_id] = nil
        return false
    end
    
    -- 更新最后访问时间
    session.last_accessed = os.time()
    
    return true
end

-- 清理过期会话
function MetadataWebServer:cleanup_expired_sessions()
    local current_time = os.time()
    for session_id, session in pairs(self.sessions) do
        if current_time - session.last_accessed > self.auth_config.session_timeout then
            self.sessions[session_id] = nil
        end
    end
end

-- 获取会话ID从Cookie
function MetadataWebServer:get_session_from_cookie(req)
    -- 调试信息：检查请求对象
    print("[MetadataWebServer] get_session_from_cookie: 开始处理请求")
    
    -- 检查请求对象是否有效
    if not req or req == nil then
        print("[MetadataWebServer] get_session_from_cookie: 请求对象无效")
        return nil
    end
    
    -- 使用pcall安全地调用libevent函数
    local success, headers = pcall(libevent.evhttp_request_get_input_headers, req)
    if not success or not headers then
        print("[MetadataWebServer] get_session_from_cookie: 无法获取请求头，错误: " .. tostring(headers))
        return nil
    end
    
    -- 检查headers对象是否有效
    if headers == nil then
        print("[MetadataWebServer] get_session_from_cookie: 请求头对象为空")
        return nil
    end
    
    -- 安全地查找Cookie头
    local success, cookie_header = pcall(libevent.evhttp_find_header, headers, "Cookie")
    if not success then
        print("[MetadataWebServer] get_session_from_cookie: 查找Cookie头失败，错误: " .. tostring(cookie_header))
        return nil
    end
    
    -- 检查cookie_header是否有效指针
    if cookie_header == nil then
        print("[MetadataWebServer] get_session_from_cookie: Cookie头指针为空")
        
        -- 调试：列出所有可用的请求头
        print("[MetadataWebServer] get_session_from_cookie: 开始列出所有请求头")
        local header_count = 0
        
        -- 尝试使用其他方式获取Cookie头信息
        local success, host_header = pcall(libevent.evhttp_find_header, headers, "Host")
        if success and host_header ~= nil then
            local host_str = ffi.string(host_header)
            print("[MetadataWebServer] get_session_from_cookie: Host头存在: " .. host_str)
            header_count = header_count + 1
        end
        
        local success, user_agent_header = pcall(libevent.evhttp_find_header, headers, "User-Agent")
        if success and user_agent_header ~= nil then
            local user_agent_str = ffi.string(user_agent_header)
            print("[MetadataWebServer] get_session_from_cookie: User-Agent头存在: " .. user_agent_str)
            header_count = header_count + 1
        end
        
        print("[MetadataWebServer] get_session_from_cookie: 共找到 " .. header_count .. " 个请求头")
        
        return nil
    end
    
    -- 安全地转换FFI字符串
    local success, cookie_str = pcall(ffi.string, cookie_header)
    if not success or not cookie_str then
        print("[MetadataWebServer] get_session_from_cookie: Cookie头转换失败，错误: " .. tostring(cookie_str))
        return nil
    end
    
    print("[MetadataWebServer] get_session_from_cookie: 找到Cookie头，内容长度=" .. #cookie_str)
    print("[MetadataWebServer] get_session_from_cookie: Cookie内容=" .. cookie_str)
    
    -- 解析Cookie
    for key, value in cookie_str:gmatch("([^=]+)=([^;]+)") do
        -- 去除前后空格
        key = key:gsub("^%s*(.-)%s*$", "%1")
        value = value:gsub("^%s*(.-)%s*$", "%1")
        if key == "session_id" then
            print("[MetadataWebServer] get_session_from_cookie: 找到session_id=" .. value)
            return value
        end
    end
    
    print("[MetadataWebServer] get_session_from_cookie: 未找到session_id")
    return nil
end

-- 检查认证状态
function MetadataWebServer:check_authentication(req)
    -- 调试信息：检查认证配置状态
    print("[MetadataWebServer] 认证检查开始: auth_config.enabled = " .. tostring(self.auth_config and self.auth_config.enabled))
    
    -- 如果认证未启用，直接返回true
    if not self.auth_config or not self.auth_config.enabled then
        print("[MetadataWebServer] 认证检查: 认证未启用，直接通过")
        return true
    end
    
    -- 获取会话ID
    local session_id = self:get_session_from_cookie(req)
    print("[MetadataWebServer] 认证检查: 获取到会话ID = " .. tostring(session_id))
    
    -- 验证会话
    if session_id and self:validate_session(session_id) then
        print("[MetadataWebServer] 认证检查: 会话验证成功")
        return true
    end
    
    -- 调试信息：记录认证失败的原因
    if not session_id then
        print("[MetadataWebServer] 认证失败: 未找到会话ID")
    else
        print("[MetadataWebServer] 认证失败: 会话验证失败, session_id=" .. tostring(session_id))
    end
    
    return false
end

-- 发送认证错误响应
function MetadataWebServer:send_auth_error(req)
    local headers = libevent.evhttp_request_get_output_headers(req)
    libevent.evhttp_add_header(headers, "Content-Type", "application/json")
    libevent.evhttp_add_header(headers, "WWW-Authenticate", 'Basic realm="Stock-TSDB Management"')
    
    local output_buffer = libevent.evhttp_request_get_output_buffer(req)
    local error_response = json.encode({
        error = "Authentication required",
        message = "Please login to access this resource"
    })
    libevent.evbuffer_add(output_buffer, error_response, #error_response)
    
    libevent.evhttp_send_reply(req, 401, "Unauthorized", output_buffer)
end

-- 处理登录请求
function MetadataWebServer:handle_login(req)
    local body = self:get_request_body(req)
    print("[MetadataWebServer] 登录请求体: " .. body)
    
    -- 检查请求体是否为空
    if not body or body == "" then
        print("[MetadataWebServer] 登录失败: 请求体为空")
        return self:send_error(req, 400, "Empty request body")
    end
    
    local ok, data = pcall(json.decode, body)
    if not ok or not data then
        print("[MetadataWebServer] 登录失败: JSON解析错误, body=" .. body)
        return self:send_error(req, 400, "Invalid JSON format")
    end
    
    if not data or not data.username or not data.password then
        return self:send_error(req, 400, "Invalid login data")
    end
    
    -- 验证用户名和密码
    if data.username == self.auth_config.username and data.password == self.auth_config.password then
        -- 创建新会话
        local session_id = self:create_session(data.username)
        
        -- 设置Cookie
        local headers = libevent.evhttp_request_get_output_headers(req)
        -- 对于本地开发环境，移除Secure标志，因为我们在使用HTTP而不是HTTPS
        local cookie = string.format("session_id=%s; Path=/; HttpOnly; Max-Age=%d; SameSite=Lax", 
                                   session_id, self.auth_config.session_timeout)
        libevent.evhttp_add_header(headers, "Set-Cookie", cookie)
        
        -- 返回成功响应
        local response = json.encode({
            success = true,
            message = "Login successful",
            username = data.username
        })
        
        self:send_response(req, 200, "application/json", response)
    else
        -- 认证失败
        local response = json.encode({
            success = false,
            message = "Invalid username or password"
        })
        
        self:send_response(req, 401, "application/json", response)
    end
end

-- 处理登出请求
function MetadataWebServer:handle_logout(req)
    local session_id = self:get_session_from_cookie(req)
    
    if session_id then
        self.sessions[session_id] = nil
    end
    
    -- 清除Cookie
    local headers = libevent.evhttp_request_get_output_headers(req)
    -- 对于本地开发环境，移除Secure标志，因为我们在使用HTTP而不是HTTPS
    libevent.evhttp_add_header(headers, "Set-Cookie", "session_id=; Path=/; HttpOnly; Expires=Thu, 01 Jan 1970 00:00:00 GMT; SameSite=Lax")
    
    local response = json.encode({
        success = true,
        message = "Logout successful"
    })
    
    self:send_response(req, 200, "application/json", response)
end

-- 检查认证状态API
function MetadataWebServer:handle_check_auth(req)
    local authenticated = self:check_authentication(req)
    
    local response = json.encode({
        authenticated = authenticated,
        username = authenticated and self.auth_config.username or nil
    })
    
    self:send_response(req, 200, "application/json", response)
end

-- 主页面
function MetadataWebServer:serve_index(req)
    local html = [[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Stock-TSDB 元数据管理</title>
    <link rel="stylesheet" href="/css/style.css">
    <style>
        .login-container {
            max-width: 400px;
            margin: 100px auto;
            padding: 20px;
            background: #fff;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .login-form h2 {
            text-align: center;
            margin-bottom: 20px;
            color: #333;
        }
        .form-group {
            margin-bottom: 15px;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        .form-group input {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        .login-btn {
            width: 100%;
            padding: 12px;
            background: #007bff;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
        }
        .login-btn:hover {
            background: #0056b3;
        }
        .error-message {
            color: red;
            text-align: center;
            margin-top: 10px;
        }
        .main-app {
            display: none;
        }
    </style>
</head>
<body>
    <!-- 登录界面 -->
    <div id="login-container" class="login-container">
        <div class="login-form">
            <h2>Stock-TSDB 登录</h2>
            <form id="login-form">
                <div class="form-group">
                    <label for="username">用户名:</label>
                    <input type="text" id="username" name="username" required>
                </div>
                <div class="form-group">
                    <label for="password">密码:</label>
                    <input type="password" id="password" name="password" required>
                </div>
                <button type="submit" class="login-btn">登录</button>
                <div id="error-message" class="error-message"></div>
            </form>
        </div>
    </div>

    <!-- 主应用界面 -->
    <div id="main-app" class="main-app">
        <header>
            <h1>Stock-TSDB 元数据管理平台</h1>
            <nav>
                <a href="#dashboard">仪表板</a>
                <a href="#config">配置管理</a>
                <a href="#metadata">元数据查看</a>
                <a href="#cluster">集群状态</a>
                <a href="#business">业务管理</a>
                <button id="logout-btn" style="float: right; margin-left: 20px;">退出登录</button>
            </nav>
        </header>
        
        <main>
            <section id="dashboard" class="active">
                <h2>系统仪表板</h2>
                <div class="stats-grid">
                    <div class="stat-card">
                        <h3>配置项数量</h3>
                        <div id="config-count" class="stat-value">加载中...</div>
                    </div>
                    <div class="stat-card">
                        <h3>业务类型</h3>
                        <div id="business-count" class="stat-value">加载中...</div>
                    </div>
                    <div class="stat-card">
                        <h3>集群节点</h3>
                        <div id="cluster-nodes" class="stat-value">加载中...</div>
                    </div>
                    <div class="stat-card">
                        <h3>数据点总数</h3>
                        <div id="total-points" class="stat-value">加载中...</div>
                    </div>
                </div>
            </section>
            
            <section id="config" style="display: none;">
                <h2>配置管理</h2>
                <div id="config-editor">加载中...</div>
            </section>
            
            <section id="metadata" style="display: none;">
                <h2>元数据查看</h2>
                <div id="metadata-viewer">加载中...</div>
            </section>
            
            <section id="cluster" style="display: none;">
                <h2>集群状态</h2>
                <div id="cluster-status">加载中...</div>
            </section>
            
            <section id="business" style="display: none;">
                <h2>业务管理</h2>
                <div id="business-manager">加载中...</div>
            </section>
        </main>
    </div>
    
    <script>
        // 检查登录状态
        function checkLoginStatus() {
            // 检查是否有有效的session cookie
            const cookies = document.cookie.split(';');
            let hasSession = false;
            
            for (let cookie of cookies) {
                cookie = cookie.trim();
                if (cookie.startsWith('session_id=')) {
                    hasSession = true;
                    break;
                }
            }
            
            return hasSession;
        }
        
        // 检查API认证状态
        async function checkApiAuthStatus() {
            try {
                // 首先检查本地是否有session cookie
                const cookies = document.cookie.split(';');
                let hasSession = false;
                let sessionId = null;
                
                for (let cookie of cookies) {
                    cookie = cookie.trim();
                    if (cookie.startsWith('session_id=')) {
                        hasSession = true;
                        sessionId = cookie.substring('session_id='.length);
                        break;
                    }
                }
                
                if (!hasSession) {
                    console.log('没有找到session cookie');
                    return false;
                }
                
                console.log('找到session cookie:', sessionId);
                
                // 在发送请求前记录当前的Cookie状态
                console.log('发送API认证检查请求前的document.cookie:', document.cookie);
                
                const response = await fetch('/api/auth/check', {
                    method: 'GET',
                    credentials: 'include', // 确保发送Cookie
                    headers: {
                        'X-Requested-With': 'XMLHttpRequest'  // 添加这个头部以标识这是一个AJAX请求
                    }
                });
                
                if (response.ok) {
                    const result = await response.json();
                    console.log('API认证检查结果:', result);
                    return result.authenticated === true;
                }
                
                console.log('API认证检查失败，状态码:', response.status);
                return false;
            } catch (error) {
                console.error('API认证检查失败:', error);
                return false;
            }
        }
        
        // 登录处理
        document.getElementById('login-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const username = document.getElementById('username').value;
            const password = document.getElementById('password').value;
            const errorMessage = document.getElementById('error-message');
            
            console.log('开始登录请求，用户名:', username);
            
            try {
                const response = await fetch('/api/auth/login', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    credentials: 'include', // 确保接收和发送Cookie
                    body: JSON.stringify({ username, password })
                });
                
                console.log('登录请求完成，状态码:', response.status);
                
                const result = await response.json();
                
                if (result.success) {
                    // 登录成功，显示主界面
                    document.getElementById('login-container').style.display = 'none';
                    document.getElementById('main-app').style.display = 'block';
                    
                    // 初始化应用
                    initializeApp();
                } else {
                    errorMessage.textContent = result.message || '登录失败';
                }
            } catch (error) {
                errorMessage.textContent = '网络错误，请重试';
                console.error('Login error:', error);
            }
        });
        
        // 退出登录
        document.getElementById('logout-btn').addEventListener('click', async function() {
            try {
                // 调用退出登录API
                await fetch('/api/auth/logout', {
                    method: 'POST',
                    credentials: 'include'
                });
            } catch (error) {
                console.error('Logout error:', error);
            }
            
            // 清除session cookie (需要与服务器设置的属性保持一致)
            document.cookie = 'session_id=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/; SameSite=Lax';
            
            // 显示登录界面，隐藏主界面
            document.getElementById('login-container').style.display = 'block';
            document.getElementById('main-app').style.display = 'none';
            
            // 清空表单
            document.getElementById('login-form').reset();
            document.getElementById('error-message').textContent = '';
        });
        
        // 初始化应用
        function initializeApp() {
            // 设置默认激活的导航项
            const navLinks = document.querySelectorAll('nav a');
            navLinks.forEach(link => {
                if (link.getAttribute('href') === '#dashboard') {
                    link.classList.add('active');
                }
            });
            
            // 显示默认的仪表板区域
            document.getElementById('dashboard').style.display = 'block';
            
            console.log('Stock-TSDB 元数据管理界面已初始化');
        }
        
        // 页面加载时检查登录状态
        document.addEventListener('DOMContentLoaded', async function() {
            console.log('页面加载完成，开始检查登录状态...');
            
            // 首先检查是否有session cookie
            const hasSession = checkLoginStatus();
            console.log('本地session cookie检查结果:', hasSession);
            
            if (hasSession) {
                // 有session cookie，检查API认证状态
                console.log('开始API认证检查...');
                const isAuthenticated = await checkApiAuthStatus();
                console.log('API认证检查结果:', isAuthenticated);
                
                if (isAuthenticated) {
                    // 已登录，显示主界面
                    console.log('认证成功，显示主界面');
                    document.getElementById('login-container').style.display = 'none';
                    document.getElementById('main-app').style.display = 'block';
                    initializeApp();
                } else {
                    // session cookie无效，清除cookie并显示登录界面
                    console.log('认证失败，清除cookie并显示登录界面');
                    document.cookie = 'session_id=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
                    document.getElementById('login-container').style.display = 'block';
                    document.getElementById('main-app').style.display = 'none';
                }
            } else {
                // 未登录，显示登录界面
                console.log('未登录，显示登录界面');
                document.getElementById('login-container').style.display = 'block';
                document.getElementById('main-app').style.display = 'none';
            }
        });
    </script>
    <script src="/js/app.js"></script>
</body>
</html>
    ]]
    
    self:send_response(req, 200, "text/html", html)
end

-- API: 获取配置信息
function MetadataWebServer:api_get_config(req)
    if not self.config_manager then
        return self:send_error(req, 500, "Config manager not available")
    end
    
    local config_data = {
        business_configs = {},
        system_config = {},
        instance_configs = {}
    }
    
    -- 获取所有配置
    local all_configs = self.config_manager:get_all_configs()
    
    -- 获取业务配置
    for key, config in pairs(all_configs) do
        if key:match("^business:") then
            local biz_type = key:match("^business:(.+)")
            config_data.business_configs[biz_type] = config
        elseif key:match("^system:") then
            config_data.system_config = config
        elseif key:match("^instance:") then
            local instance_id = key:match("^instance:(.+)")
            config_data.instance_configs[instance_id] = config
        end
    end
    
    self:send_response(req, 200, "application/json", json.encode(config_data))
end

-- API: 更新配置
function MetadataWebServer:api_update_config(req)
    local body = self:get_request_body(req)
    local data = json.decode(body)
    
    if not data or not data.key or data.value == nil then
        return self:send_error(req, 400, "Invalid request data")
    end
    
    -- 更新配置到配置管理器
    local success, err = self.config_manager:set_config(data.key, data.value)
    if not success then
        return self:send_error(req, 500, "Failed to update config: " .. tostring(err))
    end
    
    self:send_response(req, 200, "application/json", json.encode({success = true}))
end

-- API: 获取元数据
function MetadataWebServer:api_get_metadata(req)
    local metadata = {
        config_count = 15,
        business_types = {
            [1] = "股票行情",
            [2] = "金融数据", 
            [3] = "IOT传感器",
            [4] = "订单管理",
            [5] = "支付系统",
            [6] = "库存管理",
            [7] = "短信下发"
        },
        system_info = {
            version = "1.0.0",
            uptime = os.time() - (self.start_time or os.time()),
            status = "running"
        }
    }
    
    self:send_response(req, 200, "application/json", json.encode(metadata))
end

-- API: 获取统计信息
function MetadataWebServer:api_get_stats(req)
    local stats = {
        server = {
            uptime = os.time() - (self.start_time or os.time()),
            version = "1.0.0",
            connections = 8,
            requests_processed = 1245
        },
        storage = {
            total_points = 1256789,
            total_keys = 4567,
            memory_usage = 256,
            disk_usage = 1024
        },
        performance = {
            write_rate = 1250,
            query_rate = 890,
            cache_hit_rate = 85.5
        }
    }
    
    self:send_response(req, 200, "application/json", json.encode(stats))
end

-- API: 获取集群信息
function MetadataWebServer:api_get_cluster_info(req)
    local cluster_info = {
        nodes = {
            {
                id = "node-1",
                host = "127.0.0.1",
                port = 8080,
                status = "active",
                last_heartbeat = os.time() - 10
            },
            {
                id = "node-2", 
                host = "127.0.0.1",
                port = 8081,
                status = "active",
                last_heartbeat = os.time() - 15
            },
            {
                id = "node-3",
                host = "127.0.0.1", 
                port = 8082,
                status = "standby",
                last_heartbeat = os.time() - 30
            }
        },
        status = "healthy",
        leader = "node-1",
        total_nodes = 3,
        active_nodes = 2
    }
    
    self:send_response(req, 200, "application/json", json.encode(cluster_info))
end

-- API: 获取业务信息
function MetadataWebServer:api_get_business_info(req)
    local business_info = {
        instances = {
            stock_quote = {
                type = "股票行情",
                status = "running",
                data_points = 456789,
                last_update = os.time() - 300
            },
            iot_sensor = {
                type = "IOT传感器", 
                status = "running",
                data_points = 234567,
                last_update = os.time() - 180
            },
            payment_system = {
                type = "支付系统",
                status = "running",
                data_points = 123456,
                last_update = os.time() - 120
            }
        },
        plugins = {
            "股票行情插件",
            "IOT数据插件", 
            "支付系统插件",
            "订单管理插件",
            "库存管理插件"
        },
        performance = {
            write_rate = 1250,
            query_rate = 890,
            cache_hit_rate = 85.5,
            avg_response_time = 12.5
        }
    }
    
    self:send_response(req, 200, "application/json", json.encode(business_info))
end

-- Prometheus指标端点
function MetadataWebServer:handle_metrics(req)
    print("[MetadataWebServer] 处理Prometheus指标请求")
    
    -- 获取系统时间
    local current_time = os.time()
    
    -- 构建Prometheus格式的指标数据
    local metrics = {}
    
    -- 系统指标
    table.insert(metrics, string.format("# HELP stock_tsdb_server_uptime Server uptime in seconds"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_server_uptime gauge"))
    table.insert(metrics, string.format("stock_tsdb_server_uptime %d", current_time - (self.start_time or current_time)))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_server_version Server version info"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_server_version gauge"))
    table.insert(metrics, string.format('stock_tsdb_server_version{version="1.0.0"} 1'))
    
    -- 连接指标
    table.insert(metrics, string.format("# HELP stock_tsdb_connections_active Current active connections"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_connections_active gauge"))
    table.insert(metrics, string.format("stock_tsdb_connections_active %d", 8))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_requests_total Total requests processed"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_requests_total counter"))
    table.insert(metrics, string.format("stock_tsdb_requests_total %d", 1245))
    
    -- 存储指标
    table.insert(metrics, string.format("# HELP stock_tsdb_storage_data_points_total Total data points stored"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_storage_data_points_total gauge"))
    table.insert(metrics, string.format("stock_tsdb_storage_data_points_total %d", 1256789))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_storage_keys_total Total keys stored"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_storage_keys_total gauge"))
    table.insert(metrics, string.format("stock_tsdb_storage_keys_total %d", 4567))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_storage_memory_usage_bytes Memory usage in bytes"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_storage_memory_usage_bytes gauge"))
    table.insert(metrics, string.format("stock_tsdb_storage_memory_usage_bytes %d", 256 * 1024 * 1024))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_storage_disk_usage_bytes Disk usage in bytes"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_storage_disk_usage_bytes gauge"))
    table.insert(metrics, string.format("stock_tsdb_storage_disk_usage_bytes %d", 1024 * 1024 * 1024))
    
    -- 性能指标
    table.insert(metrics, string.format("# HELP stock_tsdb_performance_write_rate_ops Write operations per second"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_performance_write_rate_ops gauge"))
    table.insert(metrics, string.format("stock_tsdb_performance_write_rate_ops %d", 1250))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_performance_query_rate_ops Query operations per second"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_performance_query_rate_ops gauge"))
    table.insert(metrics, string.format("stock_tsdb_performance_query_rate_ops %d", 890))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_performance_cache_hit_rate Cache hit rate percentage"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_performance_cache_hit_rate gauge"))
    table.insert(metrics, string.format("stock_tsdb_performance_cache_hit_rate %.1f", 85.5))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_performance_avg_response_time_ms Average response time in milliseconds"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_performance_avg_response_time_ms gauge"))
    table.insert(metrics, string.format("stock_tsdb_performance_avg_response_time_ms %.1f", 12.5))
    
    -- 业务指标
    table.insert(metrics, string.format("# HELP stock_tsdb_business_instances_total Total business instances"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_business_instances_total gauge"))
    table.insert(metrics, string.format("stock_tsdb_business_instances_total %d", 3))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_business_plugins_total Total plugins loaded"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_business_plugins_total gauge"))
    table.insert(metrics, string.format("stock_tsdb_business_plugins_total %d", 5))
    
    -- 集群指标
    table.insert(metrics, string.format("# HELP stock_tsdb_cluster_nodes_total Total cluster nodes"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_cluster_nodes_total gauge"))
    table.insert(metrics, string.format("stock_tsdb_cluster_nodes_total %d", 3))
    
    table.insert(metrics, string.format("# HELP stock_tsdb_cluster_active_nodes Active cluster nodes"))
    table.insert(metrics, string.format("# TYPE stock_tsdb_cluster_active_nodes gauge"))
    table.insert(metrics, string.format("stock_tsdb_cluster_active_nodes %d", 2))
    
    -- 将指标数据连接成字符串
    local metrics_text = table.concat(metrics, "\n")
    
    -- 发送响应
    self:send_response(req, 200, "text/plain; version=0.0.4", metrics_text)
end

-- 启动服务器
function MetadataWebServer:start()
    if not libevent_available then
        return false, "libevent not available"
    end
    
    local success, err = self:initialize()
    if not success then
        return false, err
    end
    
    self.start_time = os.time()
    self.running = true
    
    print("元数据Web服务器启动成功")
    print("监听地址: http://" .. self.bind_addr .. ":" .. self.port)
    print("管理界面: http://" .. self.bind_addr .. ":" .. self.port .. "/")
    
    -- 启动事件循环
    libevent.event_base_loop(self.event_base, 0)
    
    return true
end

-- 停止服务器
function MetadataWebServer:stop()
    if self.running then
        self.running = false
        if self.http_server then
            libevent.evhttp_free(self.http_server)
            self.http_server = nil
        end
        if self.event_base then
            libevent.event_base_free(self.event_base)
            self.event_base = nil
        end
        print("元数据Web服务器已停止")
    end
end

return MetadataWebServer