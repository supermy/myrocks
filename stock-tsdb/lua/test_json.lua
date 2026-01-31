-- 测试json.lua是否成功使用cjson.so库
local json = require("json")

print("Testing JSON functionality...")

-- 测试encode功能
local test_table = {
    name = "测试",
    age = 30,
    active = true,
    skills = {"Lua", "C", "JSON"},
    address = {city = "北京", district = "朝阳区"}
}

local json_str = json.encode(test_table)
print("Encoded JSON:")
print(json_str)

-- 测试decode功能
local decoded_table = json.decode(json_str)
print("\nDecoded table:")
for k, v in pairs(decoded_table) do
    if type(v) == "table" then
        print(k .. ": table")
    else
        print(k .. ": " .. tostring(v))
    end
end

print("\nTest completed successfully!")