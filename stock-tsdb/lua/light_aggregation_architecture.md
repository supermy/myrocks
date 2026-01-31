# 轻度汇总数据库系统架构设计

## 系统概述

轻度汇总数据库系统是一个基于时间维度（小时、天、周、月）和其他维度的异步汇总计算系统，采用分隔符压缩和前缀压缩技术，使用ZeroMQ实现异步计算，汇总数据单独保存到RocksDB中。

## 核心特性

- **时间维度汇总**: 小时、天、周、月级别的数据汇总
- **多维度支持**: 支持任意维度的数据汇总
- **分隔符压缩**: 采用分隔符进行数据压缩
- **前缀压缩**: 使用前缀压缩技术优化存储
- **异步计算**: 基于ZeroMQ的异步汇总计算
- **独立存储**: 汇总数据单独保存到RocksDB

## 系统架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   明细数据写入   │───▶│   ZeroMQ异步    │───▶│   汇总计算引擎   │
│                 │    │    消息队列     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────┬───────┘
                                                       │
┌─────────────────┐    ┌─────────────────┐    ┌───────▼───────┐
│   汇总数据查询   │◀───│   汇总数据存储   │◀───│   汇总结果写入  │
│                 │    │    (RocksDB)    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 数据结构设计

### 1. 汇总维度定义

```lua
-- 时间维度汇总配置
local TIME_DIMENSIONS = {
    HOUR = {
        name = "hour",
        interval = 3600,  -- 秒
        format = "%Y%m%d%H",
        prefix = "H"
    },
    DAY = {
        name = "day", 
        interval = 86400, -- 秒
        format = "%Y%m%d",
        prefix = "D"
    },
    WEEK = {
        name = "week",
        interval = 604800, -- 秒
        format = "%Y%W",
        prefix = "W"
    },
    MONTH = {
        name = "month",
        interval = 2592000, -- 秒
        format = "%Y%m",
        prefix = "M"
    }
}

-- 其他维度汇总配置
local OTHER_DIMENSIONS = {
    STOCK_CODE = {
        name = "stock_code",
        prefix = "S",
        separator = "|"
    },
    MARKET = {
        name = "market", 
        prefix = "M",
        separator = "|"
    },
    INDUSTRY = {
        name = "industry",
        prefix = "I", 
        separator = "|"
    }
}
```

### 2. 汇总键设计

```lua
-- 时间维度汇总键格式: H|{timestamp}|{dimension_values}
-- 示例: H|2023101514|SH000001 -> 2023年10月15日14时的SH000001汇总

-- 其他维度汇总键格式: {prefix}|{dimension_values}|{timestamp}
-- 示例: S|SH000001|20231015 -> SH000001股票在2023年10月15日的汇总
```

### 3. 汇总值结构

```lua
-- 汇总统计数据
local AGGREGATION_STATS = {
    COUNT = "count",      -- 数据点数量
    SUM = "sum",          -- 总和
    AVG = "avg",          -- 平均值
    MAX = "max",          -- 最大值
    MIN = "min",          -- 最小值
    FIRST = "first",      -- 第一个值
    LAST = "last"         -- 最后一个值
}

-- 汇总值存储格式
local AGGREGATION_VALUE = {
    timestamp = 0,        -- 汇总时间戳
    count = 0,            -- 数据点数量
    sum = 0,             -- 总和
    avg = 0,             -- 平均值
    max = 0,             -- 最大值
    min = 0,             -- 最小值
    first = 0,           -- 第一个值
    last = 0             -- 最后一个值
}
```

### 4. 消息格式设计

```lua
-- ZeroMQ异步消息格式
local ASYNC_MESSAGE = {
    type = "aggregation",     -- 消息类型
    dimension = "hour",       -- 汇总维度
    timestamp = 0,           -- 时间戳
    data = {},               -- 原始数据
    metadata = {}            -- 元数据
}
```

## 存储设计

### 1. RocksDB存储结构

```
汇总数据库 (aggregation_db)
├── time_aggregations/          # 时间维度汇总
│   ├── hour/                  # 小时汇总
│   ├── day/                   # 天汇总
│   ├── week/                  # 周汇总
│   └── month/                 # 月汇总
├── dimension_aggregations/    # 其他维度汇总
│   ├── stock_code/           # 股票代码维度
│   ├── market/               # 市场维度
│   └── industry/             # 行业维度
└── metadata/                  # 元数据
    ├── config/               # 配置信息
    ├── statistics/           # 统计信息
    └── status/               # 系统状态
```

### 2. 键前缀设计

```lua
-- 时间维度键前缀
local KEY_PREFIXES = {
    TIME_HOUR = "TH",
    TIME_DAY = "TD", 
    TIME_WEEK = "TW",
    TIME_MONTH = "TM",
    DIM_STOCK = "DS",
    DIM_MARKET = "DM",
    DIM_INDUSTRY = "DI"
}
```

## 性能优化策略

### 1. 压缩优化
- 使用分隔符压缩减少存储空间
- 前缀压缩优化查询性能
- LZ4压缩算法

### 2. 异步处理优化
- ZeroMQ多线程处理
- 批量写入优化
- 内存缓存机制

### 3. 查询优化
- 时间范围索引
- 维度前缀索引
- 缓存热点数据

## 配置参数

```lua
local DEFAULT_CONFIG = {
    -- ZeroMQ配置
    zmq = {
        port = 5565,
        threads = 4,
        max_connections = 1000
    },
    
    -- 汇总配置
    aggregation = {
        enabled = true,
        batch_size = 1000,
        flush_interval = 60,  -- 秒
        retention_days = 365  -- 数据保留天数
    },
    
    -- RocksDB配置
    rocksdb = {
        path = "./data/aggregation_db",
        write_buffer_size = 64 * 1024 * 1024,
        max_write_buffer_number = 4,
        compression = "lz4"
    }
}
```

这个架构设计为轻度汇总数据库系统提供了完整的框架，接下来将实现具体的功能模块。