#!/usr/bin/env luajit

-- 检查RocksDB库中可用的函数

local ffi = require "ffi"

-- 尝试加载RocksDB库
local rocksdb, rocksdb_loaded
local success, result = pcall(function()
    -- 首先尝试使用完整路径加载
    return ffi.load("/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib")
end)

if not success then
    -- 如果完整路径失败，尝试使用系统路径
    success, result = pcall(function()
        return ffi.load("rocksdb")
    end)
end

if success then
    rocksdb = result
    rocksdb_loaded = true
    print("✅ RocksDB库加载成功")
else
    rocksdb_loaded = false
    print("❌ RocksDB库加载失败: " .. tostring(result))
    return
end

-- 测试基本函数
local function test_function(func_name)
    -- 在macOS上，C函数符号通常带有下划线前缀
    local func_name_with_underscore = "_" .. func_name
    
    local success, result = pcall(function()
        return rocksdb[func_name]
    end)
    
    if success and result ~= nil then
        print("✅ " .. func_name .. " 函数可用")
        return true
    else
        -- 尝试带下划线的版本
        local success2, result2 = pcall(function()
            return rocksdb[func_name_with_underscore]
        end)
        
        if success2 and result2 ~= nil then
            print("✅ " .. func_name .. " 函数可用 (带下划线)")
            return true
        else
            print("❌ " .. func_name .. " 函数不可用 (尝试了 " .. func_name .. " 和 " .. func_name_with_underscore .. ")")
            return false
        end
    end
end

print("\n=== 测试基本函数 ===")
test_function("rocksdb_open")
test_function("rocksdb_close")
test_function("rocksdb_put")
test_function("rocksdb_get")

print("\n=== 测试多CF函数 ===")
test_function("rocksdb_open_column_families")
test_function("rocksdb_create_column_family")
test_function("rocksdb_drop_column_family")
test_function("rocksdb_column_family_handle_destroy")

print("\n=== 测试WriteBatch CF函数 ===")
test_function("rocksdb_writebatch_put_cf")
test_function("rocksdb_writebatch_delete_cf")

print("\n=== 测试其他可能的多CF函数名称 ===")
-- 尝试不同的函数名称变体
local cf_function_variants = {
    "rocksdb_open_column_families",
    "rocksdb_open_for_column_families",
    "rocksdb_open_with_cf",
    "rocksdb_open_column_family",
    "rocksdb_open_with_cf_list"
}

for _, func_name in ipairs(cf_function_variants) do
    test_function(func_name)
end