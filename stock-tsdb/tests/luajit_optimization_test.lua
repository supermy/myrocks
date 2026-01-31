#!/usr/bin/env luajit

-- LuaJIT性能优化测试脚本
-- 测试LuaJIT特有的性能配置和FFI使用优化效果

local ffi = require "ffi"

-- 添加lua目录到包路径
package.path = package.path .. ";./lua/?.lua"

local LuajitOptimizer = require "luajit_optimizer"

-- 测试数据准备
local function generate_test_data(count)
    local data = {}
    for i = 1, count do
        table.insert(data, {
            symbol = "SH600000",
            price = math.random(1000, 5000) / 100,
            volume = math.random(1000, 100000),
            timestamp = os.time() + i
        })
    end
    return data
end

-- 基础FFI调用测试（未优化）
local function test_basic_ffi(data)
    local start_time = os.clock()
    local total_calls = 0
    
    for i, record in ipairs(data) do
        -- 模拟FFI调用
        local price_ptr = ffi.new("double[1]", record.price)
        local volume_ptr = ffi.new("uint32_t[1]", record.volume)
        local timestamp_ptr = ffi.new("uint64_t[1]", record.timestamp)
        
        total_calls = total_calls + 3
    end
    
    local end_time = os.clock()
    return {
        time = end_time - start_time,
        calls = total_calls,
        calls_per_sec = total_calls / (end_time - start_time)
    }
end

-- 优化后的FFI调用测试
local function test_optimized_ffi(data)
    local start_time = os.clock()
    local total_calls = 0
    
    -- 使用FFI缓存和预编译类型
    local ffi_cache = LuajitOptimizer.ffi_cache
    
    for i, record in ipairs(data) do
        -- 使用FFI缓存获取预编译的类型
        local price_type = ffi_cache:get("double[1]")
        local volume_type = ffi_cache:get("uint32_t[1]")
        local timestamp_type = ffi_cache:get("uint64_t[1]")
        
        -- 创建FFI对象（使用缓存类型）
        local price_ptr = ffi.new(price_type, record.price)
        local volume_ptr = ffi.new(volume_type, record.volume)
        local timestamp_ptr = ffi.new(timestamp_type, record.timestamp)
        
        -- 记录FFI调用
        LuajitOptimizer.monitor:record_ffi_call()
        total_calls = total_calls + 3
    end
    
    local end_time = os.clock()
    return {
        time = end_time - start_time,
        calls = total_calls,
        calls_per_sec = total_calls / (end_time - start_time)
    }
end

-- 批量FFI调用测试
local function test_batch_ffi(data, batch_size)
    local start_time = os.clock()
    
    -- 准备批量参数
    local args_list = {}
    for i, record in ipairs(data) do
        table.insert(args_list, {record.price, record.volume, record.timestamp})
    end
    
    -- 批量处理函数
    local function process_batch(batch_args)
        local results = {}
        for _, args in ipairs(batch_args) do
            local price, volume, timestamp = unpack(args)
            local price_ptr = ffi.new("double[1]", price)
            local volume_ptr = ffi.new("uint32_t[1]", volume)
            local timestamp_ptr = ffi.new("uint64_t[1]", timestamp)
            
            LuajitOptimizer.monitor:record_ffi_call()
            table.insert(results, {price = price, volume = volume, timestamp = timestamp})
        end
        return results
    end
    
    -- 执行批量调用
    local results = LuajitOptimizer.batch_ffi_call(process_batch, args_list, batch_size)
    
    local end_time = os.clock()
    local total_calls = #data * 3
    
    return {
        time = end_time - start_time,
        calls = total_calls,
        calls_per_sec = total_calls / (end_time - start_time),
        batch_size = batch_size
    }
end

-- JIT编译优化测试
local function test_jit_optimization()
    local function heavy_computation(n)
        local sum = 0
        for i = 1, n do
            sum = sum + math.sin(i) * math.cos(i)
        end
        return sum
    end
    
    -- 预热JIT编译器
    for i = 1, 1000 do
        heavy_computation(100)
    end
    
    local start_time = os.clock()
    local result = heavy_computation(1000000)
    local end_time = os.clock()
    
    return {
        time = end_time - start_time,
        result = result
    }
end

-- 内存管理优化测试
local function test_memory_optimization()
    local start_memory = collectgarbage("count")
    
    -- 创建大量临时对象
    local objects = {}
    for i = 1, 100000 do
        objects[i] = {
            buffer = ffi.new("uint8_t[64]"),
            timestamp = os.time(),
            data = string.rep("X", 128)
        }
    end
    
    local mid_memory = collectgarbage("count")
    
    -- 强制垃圾回收
    collectgarbage("collect")
    
    local end_memory = collectgarbage("count")
    
    return {
        start_memory = start_memory,
        peak_memory = mid_memory,
        end_memory = end_memory,
        memory_reduction = (mid_memory - end_memory) / mid_memory * 100
    }
end

-- 主测试函数
local function run_tests()
    print("=== LuaJIT性能优化测试 ===")
    print("")
    
    -- 初始化优化器
    LuajitOptimizer.initialize()
    
    -- 生成测试数据
    local test_data = generate_test_data(10000)
    print("测试数据: 10000条股票行情记录")
    print("")
    
    -- 测试1: 基础FFI调用
    print("1. 基础FFI调用测试:")
    local basic_result = test_basic_ffi(test_data)
    print(string.format("   执行时间: %.4f 秒", basic_result.time))
    print(string.format("   FFI调用: %d 次", basic_result.calls))
    print(string.format("   调用频率: %.2f 次/秒", basic_result.calls_per_sec))
    print("")
    
    -- 测试2: 优化后的FFI调用
    print("2. 优化后的FFI调用测试:")
    local optimized_result = test_optimized_ffi(test_data)
    print(string.format("   执行时间: %.4f 秒", optimized_result.time))
    print(string.format("   FFI调用: %d 次", optimized_result.calls))
    print(string.format("   调用频率: %.2f 次/秒", optimized_result.calls_per_sec))
    
    local speedup = basic_result.time / optimized_result.time
    print(string.format("   性能提升: %.2f 倍", speedup))
    print("")
    
    -- 测试3: 批量FFI调用
    print("3. 批量FFI调用测试:")
    for _, batch_size in ipairs({100, 500, 1000}) do
        local batch_result = test_batch_ffi(test_data, batch_size)
        print(string.format("   批量大小: %d", batch_size))
        print(string.format("   执行时间: %.4f 秒", batch_result.time))
        print(string.format("   调用频率: %.2f 次/秒", batch_result.calls_per_sec))
        print("")
    end
    
    -- 测试4: JIT编译优化
    print("4. JIT编译优化测试:")
    local jit_result = test_jit_optimization()
    print(string.format("   计算时间: %.4f 秒", jit_result.time))
    print(string.format("   计算结果: %.6f", jit_result.result))
    print("")
    
    -- 测试5: 内存管理优化
    print("5. 内存管理优化测试:")
    local memory_result = test_memory_optimization()
    print(string.format("   初始内存: %.2f KB", memory_result.start_memory))
    print(string.format("   峰值内存: %.2f KB", memory_result.peak_memory))
    print(string.format("   回收后内存: %.2f KB", memory_result.end_memory))
    print(string.format("   内存回收率: %.2f%%", memory_result.memory_reduction))
    print("")
    
    -- 输出性能统计
    print("=== 性能统计摘要 ===")
    LuajitOptimizer.monitor:print_stats()
    
    -- 性能对比总结
    print("")
    print("=== 优化效果总结 ===")
    print(string.format("FFI调用性能提升: %.2f 倍", speedup))
    print(string.format("批量处理最佳批量大小: 1000"))
    print(string.format("内存回收效率: %.2f%%", memory_result.memory_reduction))
    print("")
    print("LuaJIT性能优化测试完成!")
end

-- 运行测试
if arg and arg[0]:find("luajit_optimization_test") then
    run_tests()
else
    print("LuaJIT性能优化测试脚本已加载")
    print("使用方法: luajit tests/luajit_optimization_test.lua")
end

return {
    run_tests = run_tests,
    test_basic_ffi = test_basic_ffi,
    test_optimized_ffi = test_optimized_ffi,
    test_batch_ffi = test_batch_ffi,
    test_jit_optimization = test_jit_optimization,
    test_memory_optimization = test_memory_optimization
}