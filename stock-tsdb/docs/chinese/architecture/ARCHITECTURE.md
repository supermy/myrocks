# Stock-TSDB 架构文档

## 1. 概述

Stock-TSDB 是一个专为股票行情数据设计的高性能时序数据库，基于 RocksDB 和 LuaJIT 实现。系统支持两种存储方案，以满足不同的性能和功能需求。

### 1.1 核心特性
- **高性能存储**：基于 RocksDB 的高效键值存储
- **时序优化**：针对股票行情数据的时序特性优化
- **LuaJIT FFI**：使用 LuaJIT FFI 直接调用 RocksDB C API
- **双方案支持**：提供两种不同的存储方案以满足不同需求
- **高可靠性**：支持数据压缩、备份和恢复

## 2. 系统架构

### 2.1 整体架构
```
┌─────────────────┐    ┌─────────────────┐
│   Lua 应用层     │    │   批量API接口    │
└─────────┬───────┘    └─────────┬───────┘
          │                      │
          └──────────────────────┘
                    │
          ┌─────────┴─────────┐
          │   LuaJIT 引擎     │
          │  (业务逻辑)       │
          └─────────┬─────────┘
                    │
          ┌─────────┴─────────┐
          │   存储引擎层       │
          │  - 方案A (V2)     │
          │  - 现有实现 (V1)  │
          └─────────┬─────────┘
                    │
          ┌─────────┴─────────┐
          │   RocksDB 存储层   │
          │  - 高性能KV存储    │
          │  - LZ4压缩        │
          │  - 智能Compaction │
          └───────────────────┘
```

### 2.2 目录结构
```
stock-tsdb/
├── lua/                    # Lua 核心模块
│   └── tsdb_storage_engine_integrated.lua # 集成存储引擎(V3集群版)
│   ├── tsdb.lua           # TSDB 核心逻辑
│   ├── cluster.lua        # 集群管理
│   ├── config.lua         # 配置管理
│   ├── logger.lua         # 日志系统
│   ├── api.lua            # API 接口
│   ├── monitor.lua        # 监控系统
│   ├── event_server.lua   # 事件服务器
│   └── main.lua           # 主程序入口
├── tests/                  # 测试脚本
│   ├── performance_comparison_test.lua # 性能对比测试
│   ├── simple_test.lua    # 基础功能测试
│   └── comprehensive_test.lua # 综合测试
├── docs/                   # 文档
├── data/                   # 数据目录
├── conf/                   # 配置文件
└── bin/                    # 可执行文件
```

## 3. 存储方案对比

### 3.1 方案概述

Stock-TSDB 提供两种存储方案：

1. **现有实现 (V1)**：基于传统的键值对存储方式，使用字符串作为键和值。
2. **方案A (V2)**：基于优化的键结构设计，使用定长RowKey + 大端字节序 + 30秒分块策略。

### 3.2 性能对比

根据性能测试结果，在相同硬件环境下两种方案的性能对比如下：

| 指标 | 现有实现 (V1) | 方案A (V2) | 差异 |
|------|---------------|------------|------|
| 写入性能 | 567,395 QPS | 160,855 QPS | -71.7% |
| 查询性能 | 350,680 QPS | 153,419 QPS | -56.3% |

注：负值表示方案A性能较现有实现下降的百分比。

### 3.3 方案特点

#### 现有实现 (V1)
- **优点**：
  - 实现简单，易于理解和维护
  - 性能较高，适合大多数应用场景
  - 兼容性好，与现有系统集成容易

- **缺点**：
  - 键结构不够紧凑，存储效率相对较低
  - 查询优化空间有限

#### 方案A (V2)
- **优点**：
  - 键结构紧凑，存储效率高
  - 支持更高效的范围查询
  - 数据分块策略有利于压缩和查询优化

- **缺点**：
  - 实现复杂度较高
  - 性能测试显示写入和查询性能均低于现有实现
  - 需要更多的计算资源来处理键的打包和解包

## 4. 方案切换指南

### 4.1 配置文件切换

通过修改配置文件来切换存储方案：

```lua
-- conf/stock-tsdb.conf
{
  -- 存储引擎配置
  storage_engine = {
    -- 选择存储引擎版本: "v1" 或 "v2"
    version = "v1",  -- 或 "v2" 切换到方案A
    
    -- 通用配置
    data_dir = "./data",
    write_buffer_size = 64 * 1024 * 1024,
    max_write_buffer_number = 4,
    target_file_size_base = 64 * 1024 * 1024,
    max_bytes_for_level_base = 256 * 1024 * 1024,
    
    -- 方案A特有配置 (仅在version="v2"时生效)
    compression_type = "lz4_compression"  -- 可选: no_compression, snappy_compression, zlib_compression, bz2_compression, lz4_compression, lz4hc_compression, xpress_compression, zstd_compression
  }
}
```

### 4.2 代码层面切换

在代码中通过导入不同的存储引擎模块来切换方案：

```lua
-- 使用现有实现 (V1)
local StorageEngine = require "storage_engine"

-- 使用方案A (V2)
local StorageEngine = require "storage_engine_v2"

-- 初始化存储引擎
local config = {
  data_dir = "./data",
  -- 其他配置...
}

local engine = StorageEngine:new(config)
engine:init()
```

### 4.3 运行时切换

系统支持在运行时通过配置参数切换存储方案：

```bash
# 使用现有实现 (V1)
./stock-tsdb --storage-engine=v1

# 使用方案A (V2)
./stock-tsdb --storage-engine=v2
```

## 5. 使用建议

### 5.1 选择现有实现 (V1) 的场景
- 对写入和查询性能要求较高
- 系统对实现复杂度敏感
- 需要快速集成和部署
- 数据量适中，存储效率不是主要瓶颈

### 5.2 选择方案A (V2) 的场景
- 对存储效率有较高要求
- 需要频繁进行范围查询
- 数据量巨大，存储成本是主要考虑因素
- 可以接受一定的性能损失以换取存储效率

## 6. 未来优化方向

1. **方案A性能优化**：
   - 优化键打包和解包算法
   - 减少不必要的内存分配
   - 使用更高效的数据结构

2. **混合方案**：
   - 根据数据访问模式动态选择存储方案
   - 热数据使用现有实现，冷数据使用方案A

3. **并行处理**：
   - 引入多线程处理机制
   - 利用 RocksDB 的多线程特性

4. **缓存优化**：
   - 引入多级缓存机制
   - 优化热点数据访问