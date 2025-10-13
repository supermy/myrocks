#!/usr/bin/env luajit

-- 测试cjson模块路径配置
print("=== 测试cjson模块路径配置 ===")

-- 首先设置Lua路径以找到commons.utils模块
package.path = package.path .. ";./lua/?.lua;./?.lua"

-- 方法1：直接使用require（可能失败）
print("\n1. 直接使用require 'cjson':")
local ok1, cjson1 = pcall(require, "cjson")
if ok1 then
    print("✓ 直接require成功")
    local test_data = {name = "test", value = 123}
    local json_str = cjson1.encode(test_data)
    print("JSON编码结果:", json_str)
else
    print("✗ 直接require失败:", cjson1)
end

-- 方法2：使用utils.setup_module_paths
print("\n2. 使用utils.setup_module_paths:")
local utils = require "commons.utils"
utils.setup_module_paths()

local ok2, cjson2 = pcall(require, "cjson")
if ok2 then
    print("✓ 使用setup_module_paths后require成功")
    local test_data = {name = "test", value = 123}
    local json_str = cjson2.encode(test_data)
    print("JSON编码结果:", json_str)
else
    print("✗ 使用setup_module_paths后require失败:", cjson2)
end

-- 方法3：使用utils.safe_require_cjson
print("\n3. 使用utils.safe_require_cjson:")
local cjson3 = utils.safe_require_cjson()
if cjson3 then
    print("✓ safe_require_cjson成功")
    local test_data = {name = "test", value = 123}
    local json_str = cjson3.encode(test_data)
    print("JSON编码结果:", json_str)
else
    print("✗ safe_require_cjson失败")
end

-- 检查当前路径配置
print("\n4. 当前路径配置:")
print("package.cpath:", package.cpath)
print("package.path:", package.path)

print("\n=== 测试完成 ===")