-- 测试RocksDB库加载
local ffi = require "ffi"

print("测试RocksDB库加载...")

-- 尝试不同的加载方式
local test_paths = {
    "/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.dylib",
    "/usr/local/Cellar/rocksdb/10.5.1/lib/librocksdb.10.5.1.dylib",
    "rocksdb",
    "librocksdb.dylib"
}

for _, path in ipairs(test_paths) do
    print("尝试加载: " .. path)
    local success, result = pcall(function()
        return ffi.load(path)
    end)
    
    if success then
        print("✅ 成功加载: " .. path)
        print("库对象类型: " .. type(result))
        break
    else
        print("❌ 加载失败: " .. tostring(result))
    end
end

-- 检查系统库路径
print("\n检查系统库路径...")
local handle = io.popen("ls -la /usr/local/lib/librocksdb* 2>/dev/null || echo '文件不存在'")
local result = handle:read("*a")
handle:close()
print("/usr/local/lib/librocksdb*: " .. result)

-- 检查环境变量
print("\n检查环境变量...")
print("LD_LIBRARY_PATH: " .. (os.getenv("LD_LIBRARY_PATH") or "未设置"))
print("DYLD_LIBRARY_PATH: " .. (os.getenv("DYLD_LIBRARY_PATH") or "未设置"))