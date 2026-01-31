# CSV业务数据写入时的RowKey编码机制

## 概述
本文档详细描述了Stock-TSDB系统中CSV业务数据写入时的RowKey编码机制，包括多种编码方案、前缀压缩策略、性能优化和实际应用场景。

## RowKey编码架构图

```mermaid
graph TB
    A[CSV数据输入] --> B[业务类型识别]
    B --> C[数据解析]
    C --> D[RowKey编码器]
    D --> E[前缀压缩]
    E --> F[存储引擎]
    
    D --> G[文本格式编码]
    D --> H[二进制格式编码]
    D --> I[紧凑格式编码]
    
    E --> J[股票前缀策略]
    E --> K[时间序列前缀策略]
    E --> L[自定义前缀策略]
    
    F --> M[RocksDB存储]
    F --> N[内存缓存]
    F --> O[批量写入]
    
    style D fill:#e1f5fe
    style E fill:#f3e5f5
```

## 核心编码方案

### 1. 文本格式编码（默认方案）

```mermaid
sequenceDiagram
    participant CSV as CSV数据
    participant Parser as 解析器
    participant Encoder as RowKey编码器
    participant Storage as 存储引擎
    
    CSV->>Parser: 解析业务数据
    Parser->>Encoder: 传递字段数据
    Encoder->>Encoder: 构建文本格式RowKey
    Encoder->>Storage: 存储编码结果
    
    Note over Encoder: 格式: metric|tag1=value1|tag2=value2|timestamp
```

**编码规则：**
- **格式**: `metric|tag1=value1|tag2=value2|timestamp`
- **分隔符**: 使用 `|` 分隔不同字段
- **标签格式**: `key=value` 键值对
- **时间戳**: Unix时间戳（秒级精度）

**示例：**
```lua
-- 股票数据RowKey
"stock|SH|000001|1633046400"

-- IOT设备数据RowKey  
"iot_data|device_id=sensor001|sensor_type=temperature|1633046400"
```

### 2. 二进制格式编码（高性能方案）

```mermaid
sequenceDiagram
    participant CSV as CSV数据
    participant Parser as 解析器
    participant Encoder as 二进制编码器
    participant Storage as 存储引擎
    
    CSV->>Parser: 解析业务数据
    Parser->>Encoder: 传递字段数据
    Encoder->>Encoder: 二进制编码
    Encoder->>Storage: 存储紧凑格式
    
    Note over Encoder: 格式: market(1B) + stock_code(6B) + timestamp(8B) = 15B
```

**编码规则：**
- **固定长度**: 15字节固定长度RowKey
- **市场代码**: 1字节（SH=0x01, SZ=0x02等）
- **股票代码**: 6字节（固定长度，不足补空格）
- **时间戳**: 8字节（Unix时间戳，秒级精度）

**示例：**
```lua
-- 股票数据二进制RowKey（15字节）
-- 市场: SH(0x01) + 代码: 000001 + 时间戳: 1633046400
"\x01000001\x00\x00\x00\x00\x61\x5E\xE8\x80"
```

### 3. 紧凑格式编码（micro_ts插件）

```mermaid
sequenceDiagram
    participant CSV as CSV数据
    participant Parser as 解析器
    participant FFI as FFI调用
    participant C_Lib as C库函数
    participant Storage as 存储引擎
    
    CSV->>Parser: 解析业务数据
    Parser->>FFI: 调用C函数
    FFI->>C_Lib: pack_key_qual()
    C_Lib->>FFI: 返回编码结果
    FFI->>Storage: 存储18字节RowKey
    
    Note over C_Lib: 格式: market(1B) + stock_code(9B) + timestamp(8B) = 18B
```

**编码规则：**
- **固定长度**: 18字节固定长度RowKey
- **市场代码**: 1字节
- **股票代码**: 9字节（支持更长的代码）
- **时间戳**: 8字节（毫秒级精度）
- **Qualifier**: 6字节（微秒偏移和序列号）

## 前缀压缩机制

### 前缀压缩策略配置

```mermaid
graph LR
    A[数据分类] --> B[前缀策略选择]
    B --> C[前缀长度计算]
    C --> D[压缩存储]
    
    B --> E[股票数据策略]
    B --> F[时间序列策略]
    B --> G[自定义策略]
    
    E --> E1[默认:6字节]
    E --> E2[热门:8字节]
    E --> E3[指数:4字节]
    
    F --> F1[默认:8字节]
    F --> F2[高频:12字节]
    F --> F3[低频:4字节]
```

### 前缀压缩配置表

| 数据类型 | 策略名称 | 前缀长度 | 描述 |
|---------|---------|----------|------|
| 股票数据 | default | 6字节 | 默认股票前缀策略 |
| 股票数据 | hot_stock | 8字节 | 热门股票前缀策略 |
| 股票数据 | index_stock | 4字节 | 指数股票前缀策略 |
| 时间序列 | default | 8字节 | 默认时间序列前缀策略 |
| 时间序列 | high_frequency | 12字节 | 高频数据前缀策略 |
| 时间序列 | low_frequency | 4字节 | 低频数据前缀策略 |

### ColumnFamily前缀映射

```mermaid
graph TB
    A[CF名称] --> B[前缀策略映射]
    
    B --> C[cf_ → hot_stock]
    B --> D[cold_ → default]  
    B --> E[default → default]
    
    C --> F[热数据CF]
    D --> G[冷数据CF]
    E --> H[默认CF]
```

## 业务数据编码详细流程

### CSV导入时的RowKey编码流程

```mermaid
flowchart TD
    A[开始CSV导入] --> B{业务类型识别}
    B -->|股票数据| C[股票编码器]
    B -->|IOT数据| D[IOT编码器]
    B -->|金融数据| E[金融编码器]
    B -->|其他数据| F[通用编码器]
    
    C --> G[选择编码方案]
    D --> G
    E --> G
    F --> G
    
    G --> H{性能要求}
    H -->|高| I[二进制编码]
    H -->|中| J[紧凑编码]
    H -->|低| K[文本编码]
    
    I --> L[前缀压缩]
    J --> L
    K --> L
    
    L --> M[存储引擎写入]
    M --> N[完成导入]
```

### 股票数据编码详细过程

```mermaid
sequenceDiagram
    participant CSV as CSV文件
    participant Manager as CSV管理器
    participant Plugin as 编码插件
    participant Prefix as 前缀压缩
    participant Engine as 存储引擎
    
    CSV->>Manager: 读取股票数据行
    Manager->>Plugin: 调用encode_rowkey()
    
    alt 文本编码方案
        Plugin->>Plugin: 构建文本格式
        Plugin->>Plugin: stock|SH|000001|timestamp
    else 二进制编码方案
        Plugin->>Plugin: 市场代码转换
        Plugin->>Plugin: 股票代码填充
        Plugin->>Plugin: 时间戳编码
        Plugin->>Plugin: 生成15字节RowKey
    else 紧凑编码方案
        Plugin->>Plugin: FFI调用C函数
        Plugin->>Plugin: 生成18字节RowKey
        Plugin->>Plugin: 生成6字节Qualifier
    end
    
    Plugin->>Prefix: 应用前缀压缩
    Prefix->>Prefix: 根据CF选择策略
    Prefix->>Prefix: 计算前缀长度
    Prefix->>Engine: 传递压缩后RowKey
    Engine->>Engine: 批量写入存储
    Engine->>Manager: 返回写入结果
```

## 性能优化机制

### 缓存策略

```mermaid
graph LR
    A[RowKey编码请求] --> B{缓存检查}
    B -->|命中| C[返回缓存结果]
    B -->|未命中| D[执行编码]
    D --> E[更新缓存]
    E --> F[返回编码结果]
    
    G[LRU淘汰策略] --> H[缓存大小限制]
    H --> I[性能监控]
    I --> J[动态调整]
```

### 批量处理优化

```mermaid
graph TB
    A[单条数据] --> B[批量缓冲区]
    B --> C{缓冲区满?}
    C -->|是| D[批量编码]
    C -->|否| E[继续收集]
    D --> F[批量写入]
    F --> G[性能提升]
    
    H[WriteBatch] --> I[减少I/O操作]
    I --> J[提升吞吐量]
```

## 实际编码示例

### 股票数据编码示例

```lua
-- CSV数据: timestamp,stock_code,market,open,high,low,close,volume,amount
-- 输入: 1633046400,000001,SH,10.5,11.2,10.3,10.8,1000000,10800000

-- 文本编码结果
rowkey = "stock|SH|000001|1633046400"
qualifier = "00000000"

-- 二进制编码结果（15字节）
rowkey = "\x01000001\x00\x00\x00\x00\x61\x5E\xE8\x80"  -- SH市场 + 000001 + 时间戳
qualifier = "00000000"

-- 紧凑编码结果（18字节 + 6字节qualifier）
rowkey = "\x010000001  \x00\x00\x00\x00\x17\x6F\x35\x80"  -- 扩展的9字节代码
qualifier = "\x00\x00\x00\x00\x00\x00"  -- 微秒偏移和序列号
```

### IOT数据编码示例

```lua
-- CSV数据: timestamp,device_id,sensor_type,value,unit,location,status
-- 输入: 1633046400,sensor001,temperature,25.5,C,room1,normal

-- 文本编码结果
rowkey = "iot_data|device_id=sensor001|sensor_type=temperature|1633046400"
qualifier = "00000000"

-- 二进制编码结果
rowkey = "iot\x00sensor001temp\x00\x00\x00\x00\x61\x5E\xE8\x80"
qualifier = "00000000"
```

## 编码性能对比

### 不同编码方案性能指标

| 编码方案 | RowKey大小 | 编码速度 | 存储效率 | 适用场景 |
|---------|------------|----------|----------|----------|
| 文本编码 | 可变长度 | 中等 | 低 | 调试、兼容性 |
| 二进制编码 | 15字节固定 | 高 | 高 | 高性能存储 |
| 紧凑编码 | 18字节固定 | 最高 | 最高 | 极致性能 |

### 前缀压缩效果

```mermaid
xychart-beta
    title "前缀压缩存储效率对比"
    x-axis ["无压缩", "默认策略", "热门策略", "高频策略"]
    y-axis "存储效率" 0 --> 100
    bar [30, 65, 75, 85]
```

## 配置和调优

### 编码方案选择配置

```lua
-- 在存储引擎配置中设置编码方案
local config = {
    rowkey_encoding = {
        -- 默认编码方案
        default_scheme = "text",  -- text, binary, compact
        
        -- 业务特定编码方案
        business_specific = {
            stock_quotes = "compact",      -- 股票使用紧凑编码
            iot_data = "binary",           -- IOT使用二进制编码
            financial_quotes = "binary",   -- 金融数据使用二进制编码
            orders = "text",               -- 订单数据使用文本编码（便于调试）
            payments = "text"              -- 支付数据使用文本编码
        },
        
        -- 性能优化配置
        performance = {
            enable_cache = true,           -- 启用编码缓存
            cache_size = 1000,             -- 缓存大小
            batch_encoding = true,         -- 批量编码
            prefetch_strategy = "adaptive" -- 自适应预取策略
        }
    }
}
```

### 前缀压缩配置

```lua
-- 前缀压缩配置示例
local prefix_config = {
    -- 股票数据前缀策略
    stock_strategies = {
        default = { prefix_length = 6, description = "默认股票前缀" },
        hot_stock = { prefix_length = 8, description = "热门股票前缀" },
        index_stock = { prefix_length = 4, description = "指数股票前缀" }
    },
    
    -- CF映射关系
    cf_mapping = {
        ["cf_"] = "hot_stock",      -- 热数据CF
        ["cold_"] = "default",       -- 冷数据CF  
        ["default"] = "default"     -- 默认CF
    },
    
    -- 动态调整配置
    adaptive = {
        enable_dynamic_adjustment = true,  -- 启用动态调整
        adjustment_interval = 3600,       -- 调整间隔（秒）
        performance_threshold = 0.8       -- 性能阈值
    }
}
```

## 总结

CSV业务数据写入时的RowKey编码机制提供了多种灵活的编码方案：

1. **多编码方案支持** - 文本、二进制、紧凑三种编码方案
2. **智能前缀压缩** - 根据数据类型和CF动态选择压缩策略
3. **性能优化机制** - 缓存、批量处理、预取等多重优化
4. **业务适配性** - 不同业务数据使用最优编码方案
5. **可配置性** - 灵活的配置选项满足不同场景需求

这套编码机制确保了CSV数据导入的高效性和存储的空间效率，是Stock-TSDB系统高性能的重要保障。