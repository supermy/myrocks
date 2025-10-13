#!/usr/bin/env luajit

-- 综合测试运行器
-- 运行所有测试脚本并汇总结果

local tests = {
    {name = "简单测试", script = "simple_test.lua"},
    {name = "存储测试", script = "test_storage.lua"},
    {name = "方案A测试", script = "scheme_a_test.lua"},
    {name = "真实股票数据测试", script = "real_stock_data_test.lua"},
    {name = "性能对比测试", script = "performance_comparison_test.lua"},
    {name = "综合测试", script = "comprehensive_test.lua"},
    {name = "FFI测试", script = "test_ffi.lua"},
    {name = "RocksDB测试", script = "test_rocksdb.lua"},
    {name = "集群测试", script = "tsdb_cluster_test.lua"},
    {name = "集成测试", script = "integrated_tsdb_test.lua"}
}

local results = {}
local total_tests = 0
local passed_tests = 0
local failed_tests = 0

print("=== 运行所有测试 ===")
print("总共 " .. #tests .. " 个测试")
print("")

for i, test in ipairs(tests) do
    print(string.format("[%d/%d] 运行 %s...", i, #tests, test.name))
    
    local start_time = os.time()
    local success = false
    local error_msg = ""
    
    -- 运行测试脚本（设置正确的Lua路径）
    local command = "cd .. && LUA_PATH='./lua/?.lua;./?.lua;;' luajit tests/" .. test.script .. " 2>&1"
    local handle = io.popen(command)
    if handle then
        local output = handle:read("*a")
        local exit_code = handle:close()
        
        -- 检查是否成功（基于输出内容）
        if output and (string.find(output, "测试完成") or string.find(output, "完成") or 
                      string.find(output, "✓") or string.find(output, "成功")) then
            success = true
        end
        
        if not success then
            error_msg = output
        end
    else
        error_msg = "无法运行测试脚本"
    end
    
    local end_time = os.time()
    local duration = end_time - start_time
    
    total_tests = total_tests + 1
    
    if success then
        passed_tests = passed_tests + 1
        print(string.format("✓ %s - 通过 (耗时 %d 秒)", test.name, duration))
    else
        failed_tests = failed_tests + 1
        print(string.format("✗ %s - 失败 (耗时 %d 秒)", test.name, duration))
        if error_msg and error_msg ~= "" then
            print("  错误信息: " .. string.sub(error_msg, 1, 100) .. "...")
        end
    end
    
    table.insert(results, {
        name = test.name,
        success = success,
        duration = duration,
        error = error_msg
    })
    
    print("")
end

-- 汇总结果
print("=== 测试结果汇总 ===")
print(string.format("总测试数: %d", total_tests))
print(string.format("通过: %d", passed_tests))
print(string.format("失败: %d", failed_tests))
print(string.format("成功率: %.1f%%", (passed_tests / total_tests) * 100))

if failed_tests > 0 then
    print("\n失败的测试:")
    for _, result in ipairs(results) do
        if not result.success then
            print("- " .. result.name)
        end
    end
end

print("\n=== 测试运行完成 ===")

-- 返回适当的退出码
if failed_tests > 0 then
    os.exit(1)
else
    os.exit(0)
end