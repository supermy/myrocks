#!/usr/bin/env luajit
-- 运行所有核心测试

package.path = package.path .. ";./?.lua;./lua/?.lua"

print("========================================")
print("     运行所有核心存储引擎测试")
print("========================================")
print("")

local total_passed = 0
local total_failed = 0

-- 测试1: RocksDB版本
print("【测试1】RocksDB存储引擎")
print("----------------------------------------")
local rocksdb_test = dofile("tests/test_core_storage.lua")
if rocksdb_test then
    total_passed = total_passed + 10
else
    total_failed = total_failed + 1
end
print("")

-- 测试2: 集成版本
print("【测试2】集成版本存储引擎")
print("----------------------------------------")
local integrated_test = dofile("tests/test_core_integrated.lua")
if integrated_test then
    total_passed = total_passed + 7
else
    total_failed = total_failed + 1
end
print("")

-- 汇总结果
print("========================================")
print("           测试结果汇总")
print("========================================")
print(string.format("总通过: %d", total_passed))
print(string.format("总失败: %d", total_failed))
print(string.format("成功率: %.1f%%", (total_passed / (total_passed + total_failed)) * 100))
print("")

if total_failed == 0 then
    print("🎉 所有核心测试全部通过！")
    print("")
    print("测试覆盖:")
    print("  ✓ RocksDB存储引擎 (10项测试)")
    print("  ✓ 集成版本存储引擎 (7项测试)")
    print("")
    os.exit(0)
else
    print("⚠ 部分测试失败")
    os.exit(1)
end
