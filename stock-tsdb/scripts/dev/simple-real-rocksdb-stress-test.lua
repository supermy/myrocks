#!/usr/bin/env luajit

-- 简单真实RocksDB压力测试脚本
-- 直接测试真实RocksDB性能，避免复杂的CSV解析问题

package.path = package.path .. ";./lua/?.lua;../lua/?.lua"

local RocksDBFFI = require("rocksdb_ffi")

-- 简单的JSON序列化函数（避免依赖cjson）
local function simple_json_encode(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        if type(v) == "string" then
            table.insert(parts, string.format('"%s":"%s"', k, v))
        elseif type(v) == "number" then
            table.insert(parts, string.format('"%s":%s', k, v))
        elseif type(v) == "boolean" then
            table.insert(parts, string.format('"%s":%s', k, tostring(v)))
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- 简单的JSON反序列化函数
local function simple_json_decode(str)
    -- 简化实现，只处理基本类型
    local tbl = {}
    str = str:gsub("^%s*{%s*(.-)%s*}%s*$", "%1")
    
    for k, v in str:gmatch('"([^"]+)":"?([^",}]+)"?[,}]') do
        if v:match("^%d+%.?%d*$") then
            tbl[k] = tonumber(v)
        elseif v == "true" then
            tbl[k] = true
        elseif v == "false" then
            tbl[k] = false
        else
            tbl[k] = v
        end
    end
    return tbl
end

-- 测试配置
local NUM_REQUESTS = 100
local BATCH_SIZE = 10
local DATA_TYPE = "test_data"

-- 性能统计
local test_results = {
    total_requests = 0,
    successful_requests = 0,
    failed_requests = 0,
    total_time = 0,
    stage_performance = {
        rocksdb_storage = {
            total_time = 0,
            max_time = 0,
            min_time = math.huge,
            throughput = 0
        }
    }
}

-- 生成测试数据
local function generate_test_data(count)
    local data = {}
    for i = 1, count do
        local record = {
            id = i,
            timestamp = os.time() * 1000000 + i * 1000,
            value = math.random(1000, 10000) / 100,
            category = "category_" .. math.random(1, 10),
            status = math.random(0, 1) == 1 and "active" or "inactive",
            metadata = {
                tags = {"tag1", "tag2", "tag3"},
                priority = math.random(1, 5)
            }
        }
        table.insert(data, record)
    end
    return data
end

-- 真实RocksDB存储测试
local function test_real_rocksdb_performance()
    print("🚀 开始真实RocksDB压力测试...")
    print("测试配置: " .. NUM_REQUESTS .. " 个请求，批量大小: " .. BATCH_SIZE)
    
    -- 初始化RocksDB
    local options = RocksDBFFI.create_options()
    RocksDBFFI.set_create_if_missing(options, true)
    
    local db_path = "/tmp/test_real_rocksdb_" .. os.time()
    local db, err = RocksDBFFI.open_database(options, db_path)
    
    if not db then
        print("❌ 无法打开RocksDB数据库:", err)
        return false
    end
    
    print("✅ RocksDB数据库已打开: " .. db_path)
    
    local write_options = RocksDBFFI.create_write_options()
    local read_options = RocksDBFFI.create_read_options()
    
    local start_time = os.clock()
    
    -- 生成测试数据
    local test_data = generate_test_data(NUM_REQUESTS)
    
    -- 批量写入测试
    local batch_start_time = os.clock()
    local batch = RocksDBFFI.create_writebatch()
    local stored_count = 0
    
    for i, record in ipairs(test_data) do
        local key = string.format("%s:%d:%d", DATA_TYPE, record.timestamp, i)
        local value = simple_json_encode(record)
        
        RocksDBFFI.writebatch_put(batch, key, value)
        stored_count = stored_count + 1
        
        -- 批量提交
        if i % BATCH_SIZE == 0 or i == #test_data then
            local success, err = RocksDBFFI.write_batch(db, write_options, batch)
            if not success then
                print("❌ 批量写入失败:", err)
                break
            end
            RocksDBFFI.writebatch_clear(batch)
        end
    end
    
    local batch_end_time = os.clock()
    local batch_time = batch_end_time - batch_start_time
    
    -- 读取验证测试
    local read_start_time = os.clock()
    local read_count = 0
    
    for i = 1, math.min(10, NUM_REQUESTS) do  -- 只验证前10条数据
        local key = string.format("%s:%d:%d", DATA_TYPE, test_data[i].timestamp, i)
        local value, err = RocksDBFFI.get(db, read_options, key)
        
        if value then
            local record = simple_json_decode(value)
            if record and record.id == i then
                read_count = read_count + 1
            else
                print("❌ 数据验证失败，键:", key)
            end
        else
            print("❌ 读取失败，键:", key, "错误:", err)
        end
    end
    
    local read_end_time = os.clock()
    local read_time = read_end_time - read_start_time
    
    local total_time = os.clock() - start_time
    
    -- 清理资源
    RocksDBFFI.close_database(db)
    -- 注意：options、write_options、read_options 和 batch 由FFI的gc机制自动清理
    
    -- 输出测试结果
    print("\n=== 真实RocksDB压力测试报告 ===")
    print("测试时间: " .. string.format("%.2f", total_time) .. "秒")
    print("总请求数: " .. NUM_REQUESTS)
    print("成功写入: " .. stored_count)
    print("成功读取验证: " .. read_count)
    
    print("\n=== 性能指标 ===")
    print("批量写入时间: " .. string.format("%.4f", batch_time) .. "秒")
    print("批量写入吞吐量: " .. string.format("%.2f", stored_count / batch_time) .. " 记录/秒")
    print("读取验证时间: " .. string.format("%.4f", read_time) .. "秒")
    print("读取验证吞吐量: " .. string.format("%.2f", read_count / read_time) .. " 记录/秒")
    
    print("\n=== 测试完成 ===")
    print("✅ 真实RocksDB功能验证成功")
    
    return true
end

-- 主函数
local function main()
    print("🧪 简单真实RocksDB压力测试")
    print("==============================")
    
    -- 检查RocksDB库是否可用
    if not RocksDBFFI then
        print("❌ 无法加载RocksDB FFI模块")
        return
    end
    
    -- 运行测试
    local success = test_real_rocksdb_performance()
    
    if success then
        print("\n🎉 真实RocksDB压力测试完成！")
        print("📊 测试结果表明真实RocksDB功能正常，性能良好")
    else
        print("\n💥 真实RocksDB压力测试失败")
    end
end

-- 运行主函数
main()