# Lua存储引擎

这是一个使用LuaJIT FFI封装RocksDB C API实现的高性能时序数据库存储引擎。

## 特性

- 高性能键值存储，基于RocksDB
- 时序数据优化存储格式
- 支持数据压缩和批量操作
- 列族管理功能
- 完整的CRUD操作支持

## 安装要求

- LuaJIT
- RocksDB库

在macOS上安装RocksDB：
```bash
brew install rocksdb
```

## 使用方法

### 初始化存储引擎

```lua
local storage = require "storage"

-- 配置存储引擎
local config = {
    data_dir = "./data",
    write_buffer_size = 64 * 1024 * 1024,  -- 64MB
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,  -- 64MB
    max_bytes_for_level_base = 256 * 1024 * 1024,  -- 256MB
    compression = 4  -- lz4
}

-- 创建存储引擎实例
local engine = storage.create_engine(config)

-- 初始化存储引擎
local success, err = engine:init()
if not success then
    error("初始化失败: " .. err)
end
```

### 写入数据

```lua
-- 写入单个数据点
local point = {
    timestamp = 1234567890,
    value = 100.5,
    quality = 100
}

local success, err = engine:write_point("SH000001", point, 0)
if not success then
    print("写入失败:", err)
end

-- 批量写入数据点
local points = {
    {timestamp = 1234567891, value = 101.0, quality = 95},
    {timestamp = 1234567892, value = 102.5, quality = 90}
}

local success, err = engine:write_points("SH000001", points, 0)
if not success then
    print("批量写入失败:", err)
end
```

### 读取数据

```lua
-- 读取单个数据点
local success, result = engine:read_point("SH000001", 1234567890, 0)
if success then
    print("数据:", result.value, result.timestamp, result.quality)
end

-- 范围读取数据
local success, results = engine:read_range("SH000001", 1234567890, 1234567892, 0)
if success then
    for i, point in ipairs(results) do
        print(i, point.timestamp, point.value, point.quality)
    end
end

-- 获取最新数据点
local success, result = engine:get_latest_point("SH000001", 0)
if success then
    print("最新数据:", result.timestamp, result.value, result.quality)
end
```

### 管理操作

```lua
-- 创建列族
local success, err = engine:create_column_family("new_cf")
if not success then
    print("创建列族失败:", err)
end

-- 获取统计信息
local success, stats = engine:get_statistics()
if success then
    print("统计信息:", stats)
end

-- 数据压缩
local success, err = engine:compact_data("SH000001")
if not success then
    print("数据压缩失败:", err)
end

-- 删除数据
local success, count = engine:delete_data("SH000001", 1234567890, 1234567891, 0)
if success then
    print("删除了", count, "个数据点")
end
```

### 关闭存储引擎

```lua
-- 关闭存储引擎
engine:shutdown()
```

## API参考

### StorageEngine类

#### `engine:init()`
初始化存储引擎

#### `engine:shutdown()`
关闭存储引擎

#### `engine:write_point(symbol, point, data_type)`
写入单个数据点

#### `engine:write_points(symbol, points, data_type)`
批量写入数据点

#### `engine:read_point(symbol, timestamp, data_type)`
读取单个数据点

#### `engine:read_range(symbol, start_time, end_time, data_type)`
范围读取数据

#### `engine:delete_data(symbol, start_time, end_time, data_type)`
删除指定范围的数据

#### `engine:get_latest_point(symbol, data_type)`
获取指定symbol的最新数据点

#### `engine:get_statistics()`
获取存储引擎统计信息

#### `engine:compact_data(symbol)`
压缩数据

#### `engine:create_column_family(cf_name)`
创建列族

#### `engine:drop_column_family(cf_name)`
删除列族

#### `engine:get_column_families()`
获取所有列族列表

## 数据结构

### 数据点 (DataPoint)
- `timestamp`: 时间戳 (uint64_t)
- `value`: 数值 (double)
- `quality`: 质量 (uint8_t)

### 行键 (RowKey)
格式: `{symbol}:{timestamp}:{data_type}`
- `symbol`: 股票代码，如"SH000001"
- `timestamp`: 时间戳，16位十六进制格式
- `data_type`: 数据类型，2位十六进制格式

## 数据类型常量

- `0`: 价格 (PRICE)
- `1`: 成交量 (VOLUME)
- `2`: 买一价 (BID)
- `3`: 卖一价 (ASK)
- `4`: 买一量 (BID_VOLUME)
- `5`: 卖一量 (ASK_VOLUME)