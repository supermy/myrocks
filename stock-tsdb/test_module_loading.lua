-- 测试模块加载路径
print("=== 模块加载测试 ===")

-- 测试1: 直接加载rocksdb_ffi
print("\n测试1: 直接加载rocksdb_ffi")
local ok1, err1 = pcall(require, "rocksdb_ffi")
print("结果:", ok1, "错误:", err1)

-- 测试2: 使用相对路径加载
print("\n测试2: 使用相对路径加载rocksdb_ffi")
local ok2, err2 = pcall(require, "lua.rocksdb_ffi")
print("结果:", ok2, "错误:", err2)

-- 测试3: 检查当前工作目录
print("\n测试3: 当前工作目录")
local handle = io.popen("pwd")
local pwd = handle:read("*a")
handle:close()
print("当前目录:", pwd)

-- 测试4: 检查文件是否存在
print("\n测试4: 检查文件是否存在")
local handle2 = io.popen("ls -la lua/rocksdb_ffi.lua")
local file_info = handle2:read("*a")
handle2:close()
print("文件信息:", file_info)

-- 测试5: 修改package.path后加载
print("\n测试5: 修改package.path后加载")
package.path = package.path .. ";./lua/?.lua"
local ok5, err5 = pcall(require, "rocksdb_ffi")
print("结果:", ok5, "错误:", err5)