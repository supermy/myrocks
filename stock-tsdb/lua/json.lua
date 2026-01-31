-- 使用CJSON库进行JSON解析和序列化
local json = nil
local json_path = "../lib/cjson.so"

-- 尝试加载CJSON库
local success, cjson = pcall(require, "cjson")
if not success then
    -- 如果直接require失败，尝试使用package.loadlib加载
    local cjson_lib = package.loadlib(json_path, "luaopen_cjson")
    if cjson_lib then
        success, cjson = pcall(cjson_lib)
    end
end

if not success then
    -- 如果CJSON库加载失败，输出错误信息并创建一个简单的回退实现
    print("Warning: Failed to load cjson.so, using fallback implementation")
    
    -- 简单的回退实现
    json = {
        encode = function(obj)
            if type(obj) == "nil" then return "null"
            elseif type(obj) == "boolean" then return obj and "true" or "false"
            elseif type(obj) == "number" then return tostring(obj)
            elseif type(obj) == "string" then
                return '"' .. obj:gsub('"', '\\"'):gsub('\\', '\\\\') .. '"'
            elseif type(obj) == "table" then
                local items = {}
                for k, v in pairs(obj) do
                    if type(k) == "number" then
                        table.insert(items, json.encode(v))
                    else
                        table.insert(items, json.encode(tostring(k)) .. ":" .. json.encode(v))
                    end
                end
                if #items > 0 and items[1] ~= nil then
                    -- 尝试判断是否为数组
                    local is_array = true
                    for i, _ in pairs(obj) do
                        if type(i) ~= "number" or i < 1 or math.floor(i) ~= i then
                            is_array = false
                            break
                        end
                    end
                    return is_array and "[" .. table.concat(items, ",") .. "]" or "{" .. table.concat(items, ",") .. "}"
                else
                    return "[]"
                end
            else
                return "null"
            end
        end,
        
        decode = function(str)
            -- 简单的JSON解析回退实现
            -- 注意：这只是一个非常基础的实现，仅支持简单的数据结构
            local env = setmetatable({}, {__index = _G})
            local func, err = loadstring("return " .. str:gsub('true', 'true'):gsub('false', 'false'):gsub('null', 'nil'), "json_decode")
            if func then
                setfenv(func, env)
                return func()
            else
                return nil, err
            end
        end
    }
else
    -- 成功加载CJSON库
    json = cjson
    
    -- 确保接口一致性
    if not json.encode then
        json.encode = json.encode
    end
    if not json.decode then
        json.decode = json.decode
    end
end

return json