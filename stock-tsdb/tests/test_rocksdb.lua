#!/usr/bin/env lua

-- 测试RocksDB Lua模块

-- 添加当前目录到Lua包路径
package.cpath = package.cpath .. ";./lib/?.so"

-- 加载模块
local rocksdb = require("rocksdb")

print("RocksDB Lua模块测试")
print("==================")

-- 创建存储引擎实例
local storage = rocksdb.create()
if storage then
    print("✓ 成功创建存储引擎实例")
    
    -- 初始化存储引擎
    local success = storage:init()
    if success then
        print("✓ 存储引擎初始化成功")
    else
        print("✗ 存储引擎初始化失败")
    end
    
    -- 关闭存储引擎
    storage:shutdown()
    print("✓ 存储引擎已关闭")
else
    print("✗ 创建存储引擎实例失败")
end

print("测试完成")