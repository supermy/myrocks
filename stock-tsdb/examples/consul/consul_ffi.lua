#!/usr/bin/env luajit

-- Consul FFI客户端模块
-- 基于libcurl和Consul HTTP API实现

local ffi = require "ffi"
local bit = require "bit"

-- 定义C标准库和libcurl的FFI接口
ffi.cdef[[
    // 标准C库函数
    char* getenv(const char* name);
    int sprintf(char* str, const char* format, ...);
    int snprintf(char* str, size_t size, const char* format, ...);
    size_t strlen(const char* s);
    char* strdup(const char* s);
    void free(void* ptr);
    void* malloc(size_t size);
    void* memset(void* s, int c, size_t n);
    
    // libcurl相关定义
    typedef void CURL;
    typedef void CURLM;
    typedef int CURLcode;
    typedef int CURLMcode;
    
    struct curl_slist {
        char* data;
        struct curl_slist* next;
    };
    
    CURL* curl_easy_init(void);
    CURLcode curl_easy_setopt(CURL* curl, int option, ...);
    CURLcode curl_easy_perform(CURL* curl);
    void curl_easy_cleanup(CURL* curl);
    char* curl_easy_strerror(CURLcode);
    
    struct curl_slist* curl_slist_append(struct curl_slist* list, const char* string);
    void curl_slist_free_all(struct curl_slist* list);
    
    // 内存写入回调相关
    typedef size_t (*curl_write_callback)(char* ptr, size_t size, size_t nmemb, void* userdata);
    
    // 全局初始化
    CURLcode curl_global_init(long flags);
    void curl_global_cleanup(void);
]]

-- 尝试加载libcurl
local curl_lib = nil
local curl_available = false

for _, lib_name in ipairs({"curl", "libcurl", "libcurl.so.4", "libcurl.dylib"}) do
    local ok, lib = pcall(ffi.load, lib_name)
    if ok then
        curl_lib = lib
        curl_available = true
        print("[Consul FFI] 成功加载libcurl: " .. lib_name)
        break
    end
end

if not curl_available then
    print("[Consul FFI] 警告: libcurl不可用，将使用简化模拟模式")
end

-- Consul客户端实现
local ConsulClient = {}
ConsulClient.__index = ConsulClient

function ConsulClient:new(config)
    local obj = setmetatable({}, ConsulClient)
    obj.config = config or {}
    obj.consul_url = config.consul_url or config.endpoint or "http://127.0.0.1:8500"
    obj.timeout = config.timeout or 5000  -- 5秒超时
    obj.simulate = config.simulate or false
    obj.curl_handle = nil
    obj.initialized = false
    
    -- 初始化libcurl
    if curl_available then
        local ret = curl_lib.curl_global_init(0)  -- CURL_GLOBAL_DEFAULT
        if ret == 0 then
            obj.curl_handle = curl_lib.curl_easy_init()
            if obj.curl_handle ~= nil then
                obj.initialized = true
                print("[Consul FFI] Consul客户端初始化成功")
            else
                print("[Consul FFI] 错误: 无法创建CURL句柄")
            end
        else
            print("[Consul FFI] 错误: libcurl全局初始化失败")
        end
    else
        print("[Consul FFI] 使用模拟模式")
        obj.initialized = true
    end
    
    return obj
end

function ConsulClient:destroy()
    if self.curl_handle and curl_available then
        curl_lib.curl_easy_cleanup(self.curl_handle)
        self.curl_handle = nil
    end
    
    if curl_available then
        curl_lib.curl_global_cleanup()
    end
    
    self.initialized = false
    print("[Consul FFI] Consul客户端已销毁")
end

-- HTTP响应写入回调
local function write_callback(ptr, size, nmemb, userdata)
    local total_size = size * nmemb
    local data = ffi.string(ptr, total_size)
    
    -- 将数据追加到userdata字符串中
    local existing_data = ffi.cast("char**", userdata)[0]
    if existing_data == nil then
        ffi.cast("char**", userdata)[0] = ffi.C.strdup(data)
    else
        local existing_len = ffi.C.strlen(existing_data)
        local new_len = existing_len + total_size
        local new_data = ffi.C.malloc(new_len + 1)
        
        if new_data ~= nil then
            ffi.C.memset(new_data, 0, new_len + 1)
            ffi.copy(new_data, existing_data, existing_len)
            ffi.copy(new_data + existing_len, data, total_size)
            
            ffi.C.free(existing_data)
            ffi.cast("char**", userdata)[0] = new_data
        end
    end
    
    return total_size
end

-- 执行HTTP请求（简化实现）
function ConsulClient:http_request(method, path, data, params)
    if not self.initialized then
        return false, "Consul客户端未初始化"
    end
    
    -- 模拟模式下的简化实现
    if not curl_available or self.simulate then
        return self:simulate_consul_request(method, path, data, params)
    end
    
    -- 构建完整的URL
    local full_url = self.consul_url .. path
    if params then
        local param_parts = {}
        for k, v in pairs(params) do
            table.insert(param_parts, k .. "=" .. tostring(v))
        end
        if #param_parts > 0 then
            full_url = full_url .. "?" .. table.concat(param_parts, "&")
        end
    end
    
    -- 响应数据缓冲区
    local response_data = ffi.new("char*[1]")
    response_data[0] = nil
    
    -- 设置CURL选项（简化版本，实际实现会更复杂）
    local ret = curl_lib.curl_easy_setopt(self.curl_handle, 10002, full_url)  -- CURLOPT_URL
    if ret ~= 0 then
        return false, "设置URL失败"
    end
    
    -- 设置写入回调
    local callback_ptr = ffi.cast("curl_write_callback", write_callback)
    ret = curl_lib.curl_easy_setopt(self.curl_handle, 20011, callback_ptr)  -- CURLOPT_WRITEFUNCTION
    ret = curl_lib.curl_easy_setopt(self.curl_handle, 10001, response_data)  -- CURLOPT_WRITEDATA
    
    -- 执行请求
    ret = curl_lib.curl_easy_perform(self.curl_handle)
    
    if ret == 0 then
        local response = ""
        if response_data[0] ~= nil then
            response = ffi.string(response_data[0])
            ffi.C.free(response_data[0])
        end
        return true, response
    else
        local error_msg = "HTTP请求失败: " .. tostring(ret)
        if response_data[0] ~= nil then
            ffi.C.free(response_data[0])
        end
        return false, error_msg
    end
end

-- Consul模拟模式（用于测试和libcurl不可用的情况）
function ConsulClient:simulate_consul_request(method, path, data, params)
    -- 模拟Consul API响应
    local key = path:match("/v1/kv/(.+)$")
    
    if method == "GET" and key then
        -- 模拟获取键值
        local mock_data = {
            ["cluster/nodes/node1"] = '{"id":"node1","address":"127.0.0.1:8081","status":"alive","last_seen":' .. os.time() .. '}',
            ["cluster/nodes/node2"] = '{"id":"node2","address":"127.0.0.1:8082","status":"alive","last_seen":' .. os.time() .. '}',
            ["cluster/leader"] = 'node1',
            ["cluster/config"] = '{"replication_factor":2,"shard_count":16}'
        }
        
        if mock_data[key] then
            -- 模拟Consul的响应格式
            local response = '[{"Key":"' .. key .. '","Value":"' .. self:base64_encode(mock_data[key]) .. '","ModifyIndex":1}]'
            return true, response
        else
            return true, "[]"  -- 键不存在
        end
    elseif method == "PUT" and key then
        -- 模拟设置键值
        print("[Consul FFI 模拟] PUT " .. key .. " = " .. tostring(data))
        return true, "true"
    elseif method == "DELETE" and key then
        -- 模拟删除键值
        print("[Consul FFI 模拟] DELETE " .. key)
        return true, "true"
    else
        -- 其他API端点的模拟响应
        if path == "/v1/agent/self" then
            return true, '{"Config":{"Datacenter":"dc1","NodeName":"consul-node1"}}'
        elseif path == "/v1/status/leader" then
            return true, '"127.0.0.1:8300"'
        elseif path == "/v1/catalog/nodes" then
            return true, '[{"ID":"node1","Node":"consul-node1","Address":"127.0.0.1","Datacenter":"dc1"}]'
        else
            return true, "{}"  -- 默认空响应
        end
    end
end

-- 简单的base64编码（简化实现）
function ConsulClient:base64_encode(data)
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x) 
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6 - i) or 0) end
        return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- Consul KV操作
function ConsulClient:kv_get(key, recurse)
    local path = "/v1/kv/" .. key
    local params = {}
    if recurse then
        params.recurse = "true"
    end
    
    return self:http_request("GET", path, nil, params)
end

function ConsulClient:kv_put(key, value)
    local path = "/v1/kv/" .. key
    return self:http_request("PUT", path, value)
end

function ConsulClient:kv_delete(key, recurse)
    local path = "/v1/kv/" .. key
    local params = {}
    if recurse then
        params.recurse = "true"
    end
    
    return self:http_request("DELETE", path, nil, params)
end

-- 服务注册和发现
function ConsulClient:register_service(service_id, service_name, address, port, tags)
    local path = "/v1/agent/service/register"
    local service_data = {
        ID = service_id,
        Name = service_name,
        Address = address,
        Port = port,
        Tags = tags or {},
        Check = {
            HTTP = "http://" .. address .. ":" .. port .. "/health",
            Interval = "10s",
            Timeout = "5s"
        }
    }
    
    local json_str = self:table_to_json(service_data)
    return self:http_request("PUT", path, json_str)
end

function ConsulClient:deregister_service(service_id)
    local path = "/v1/agent/service/deregister/" .. service_id
    return self:http_request("PUT", path)
end

function ConsulClient:discover_services(service_name)
    local path = "/v1/health/service/" .. service_name
    return self:http_request("GET", path)
end

-- 会话管理（用于分布式锁）
function ConsulClient:create_session(name, ttl)
    local path = "/v1/session/create"
    local session_data = {
        Name = name,
        TTL = ttl or "30s",
        Behavior = "delete"
    }
    
    local json_str = self:table_to_json(session_data)
    return self:http_request("PUT", path, json_str)
end

function ConsulClient:destroy_session(session_id)
    local path = "/v1/session/destroy/" .. session_id
    return self:http_request("PUT", path)
end

-- 简单的JSON编码器
function ConsulClient:table_to_json(t)
    if type(t) ~= "table" then
        return tostring(t)
    end
    
    local parts = {}
    for k, v in pairs(t) do
        if type(v) == "string" then
            table.insert(parts, '"' .. k .. '":"' .. v .. '"')
        elseif type(v) == "number" then
            table.insert(parts, '"' .. k .. '":' .. v)
        elseif type(v) == "table" then
            table.insert(parts, '"' .. k .. '":' .. self:table_to_json(v))
        elseif type(v) == "boolean" then
            table.insert(parts, '"' .. k .. '":' .. tostring(v))
        end
    end
    
    return "{" .. table.concat(parts, ",") .. "}"
end

-- 创建Consul客户端实例
local function create_consul_client(config)
    return ConsulClient:new(config)
end

-- 模块导出
return {
    new = create_consul_client,
    ConsulClient = ConsulClient
}