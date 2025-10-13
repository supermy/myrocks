# 方案A实现详解

## 1. 概述

方案A是Stock-TSDB的第二种存储实现，基于定长RowKey + 大端字节序 + 30秒分块策略设计。该方案旨在提高存储效率和查询性能，特别适用于大规模股票行情数据的存储和检索。

## 2. 设计理念

方案A的核心设计理念包括：

1. **定长键结构**：通过固定长度的键结构减少存储空间和提高查询效率
2. **大端字节序**：统一使用大端字节序保证数据的一致性和可读性
3. **时间分块策略**：将数据按30秒时间窗口分块，优化范围查询性能
4. **紧凑数据结构**：通过精心设计的数据结构最大化存储效率

## 3. 数据结构设计

### 3.1 RowKey 结构（共 18 字节）
| 字段 | 长度 | 类型 | 字节序 | 说明 |
|------|------|------|--------|------|
| market | 1 字节 | uint8 | - | 市场标识：'S'=沪深 'H'=港股 'U'=美股 |
| code | 9 字节 | ASCII | - | 股票代码，右对齐补0 |
| chunk_base_ms | 8 字节 | uint64 | 大端 | 30秒对齐的毫秒时间戳 |

### 3.2 Qualifier 结构（共 6 字节）
| 字段 | 长度 | 类型 | 字节序 | 计算方式 |
|------|------|------|--------|----------|
| micro_offset | 4 字节 | uint32 | 大端 | `ts_us - chunk_base_ms*1000` |
| seq | 2 字节 | uint16 | 大端 | 同一微秒内的序号 |

### 3.3 Value 结构（固定 50 字节）
| 字段 | 长度 | 类型 | 精度/格式 | 说明 |
|------|------|------|-----------|------|
| price | 4 字节 | int32 | 1/10000元 | 价格，精度到小数点后4位 |
| qty | 4 字节 | uint32 | 股 | 成交量 |
| channel | 1 字节 | uint8 | - | 通道号 |
| side | 1 字节 | uint8 | - | 买卖方向：'B'/'S'/'N' 存为 0/1/2 |
| order_no | 8 字节 | uint64 | 大端 | 订单号 |
| tick_no | 8 字节 | uint64 | 大端 | 成交序号 |
| reserved | 24 字节 | raw | - | 预留字段 |

## 4. 核心实现

### 4.1 FFI定义

方案A通过LuaJIT FFI直接调用RocksDB C API：

```lua
ffi.cdef[[
    // RocksDB基本类型和函数定义
    typedef struct rocksdb_t rocksdb_t;
    typedef struct rocksdb_options_t rocksdb_options_t;
    // ... 其他类型定义
    
    // RocksDB核心函数
    rocksdb_options_t* rocksdb_options_create();
    void rocksdb_options_destroy(rocksdb_options_t*);
    void rocksdb_options_set_create_if_missing(rocksdb_options_t*, unsigned char);
    void rocksdb_options_set_compression(rocksdb_options_t*, int);
    // ... 其他函数定义
]]
```

### 4.2 键打包函数

```lua
-- RowKey打包函数
local function pack_key(market, code, chunk_base_ms)
    local buf = {}
    table.insert(buf, string.char(string.byte(market)))
    local code_str = string.format("%09d", tonumber(code))
    table.insert(buf, code_str)
    table.insert(buf, pack_uint64(chunk_base_ms))
    return table.concat(buf)
end

-- Qualifier打包函数
local function pack_qual(micro_offset, seq)
    local buf = {}
    table.insert(buf, pack_uint32(micro_offset))
    table.insert(buf, pack_uint16(seq))
    return table.concat(buf)
end
```

### 4.3 时间分块计算

```lua
-- 计算30秒对齐的时间戳
local function get_chunk_base_ms(ts_us)
    return math.floor(ts_us / 1000000 / 30) * 30 * 1000
end

-- 计算微秒偏移
local function get_micro_offset(ts_us, chunk_base_ms)
    return ts_us - chunk_base_ms * 1000
end
```

### 4.4 数据写入实现

```lua
function StorageEngine:write_point(symbol, point, data_type)
    -- 解析symbol
    local market, code = parse_symbol(symbol)
    
    -- 计算时间分块
    local timestamp_us = point.timestamp * 1000000
    local chunk_base_ms = get_chunk_base_ms(timestamp_us)
    local micro_offset = get_micro_offset(timestamp_us, chunk_base_ms)
    local seq = point.seq or 0
    
    -- 创建RowKey和Qualifier
    local key = pack_key(market, code, chunk_base_ms)
    local qual = pack_qual(micro_offset, seq)
    
    -- 创建Value
    local value = self:pack_value(point)
    
    -- 拼接完整键并写入
    local full_key = key .. qual
    rocksdb_lib.rocksdb_put(self.db, self.write_options, 
                           full_key, #full_key, value, #value, errptr)
end
```

## 5. 性能优化措施

### 5.1 批量写入优化

方案A支持批量写入操作，通过RocksDB的WriteBatch机制提高写入性能：

```lua
function StorageEngine:write_points(symbol, points, data_type)
    -- 创建批量写入批次
    local batch = ffi.gc(rocksdb_lib.rocksdb_writebatch_create(), 
                        rocksdb_lib.rocksdb_writebatch_destroy)
    
    -- 批量添加数据点
    for _, point in ipairs(points) do
        -- 处理数据点...
        rocksdb_lib.rocksdb_writebatch_put(batch, full_key, #full_key, value, #value)
    end
    
    -- 执行批量写入
    rocksdb_lib.rocksdb_write(self.db, self.write_options, batch, errptr)
end
```

### 5.2 范围查询优化

方案A的键结构设计有利于范围查询：

```lua
function StorageEngine:read_range(symbol, start_time, end_time, data_type)
    -- 创建迭代器
    local iter = ffi.gc(rocksdb_lib.rocksdb_create_iterator(self.db, self.read_options), 
                       rocksdb_lib.rocksdb_iter_destroy)
    
    -- 构造起始键
    local start_chunk_base_ms = get_chunk_base_ms(start_time * 1000000)
    local start_key = pack_key(market, code, start_chunk_base_ms)
    
    -- 定位到起始位置并遍历
    rocksdb_lib.rocksdb_iter_seek(iter, start_key, #start_key)
    while rocksdb_lib.rocksdb_iter_valid(iter) ~= 0 do
        -- 处理数据...
        rocksdb_lib.rocksdb_iter_next(iter)
    end
end
```

## 6. 压缩策略

方案A支持多种压缩算法：

```lua
-- 获取压缩类型值的函数
local function get_compression_type(name)
    local compression_types = {
        no_compression = 0,
        snappy_compression = 1,
        zlib_compression = 2,
        bz2_compression = 3,
        lz4_compression = 4,
        lz4hc_compression = 5,
        xpress_compression = 6,
        zstd_compression = 7
    }
    return compression_types[name] or 4  -- 默认使用LZ4
end

-- 设置压缩选项
local compression_type = self.config.compression_type or "lz4_compression"
rocksdb_lib.rocksdb_options_set_compression(self.options, get_compression_type(compression_type))
```

## 7. 错误处理

方案A具有完善的错误处理机制：

```lua
local errptr = ffi.new("char*[1]")
rocksdb_lib.rocksdb_put(self.db, self.write_options, 
                       full_key, #full_key, value, #value, errptr)

if errptr[0] ~= nil then
    local error_msg = ffi.string(errptr[0])
    rocksdb_lib.rocksdb_free(errptr[0])
    return false, error_msg
end
```

## 8. 内存管理

方案A使用LuaJIT的垃圾回收机制管理RocksDB资源：

```lua
self.options = ffi.gc(rocksdb_lib.rocksdb_options_create(), 
                     rocksdb_lib.rocksdb_options_destroy)
self.write_options = ffi.gc(rocksdb_lib.rocksdb_writeoptions_create(), 
                           rocksdb_lib.rocksdb_writeoptions_destroy)
self.read_options = ffi.gc(rocksdb_lib.rocksdb_readoptions_create(), 
                          rocksdb_lib.rocksdb_readoptions_destroy)
```

## 9. 性能测试结果

根据性能测试结果，方案A在存储效率方面表现优异，但在写入和查询性能上较现有实现有所下降：

- 写入性能：160,855 QPS (-71.7%)
- 查询性能：153,419 QPS (-56.3%)

## 10. 使用场景建议

方案A适用于以下场景：

1. **存储效率优先**：对存储空间有严格要求的环境
2. **范围查询频繁**：需要频繁进行时间范围查询的应用
3. **大数据量存储**：需要存储海量历史数据的系统
4. **成本敏感**：存储成本是主要考虑因素的项目

对于对性能要求较高的实时交易系统，建议使用现有实现(V1)。