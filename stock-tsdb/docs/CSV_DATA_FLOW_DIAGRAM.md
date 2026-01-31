# CSV数据流程图

## 概述
本文档详细描述了Stock-TSDB系统中CSV数据的导入导出流程，涵盖从文件读取到存储引擎写入的完整数据流。

## 整体架构图

```mermaid
graph TB
    A[CSV文件] --> B[CSV数据管理器]
    B --> C[格式验证]
    C --> D[数据解析]
    D --> E[批量处理]
    E --> F[存储引擎]
    F --> G[RocksDB存储]
    
    H[查询请求] --> I[存储引擎]
    I --> J[数据查询]
    J --> K[CSV格式化]
    K --> L[导出文件]
    
    B --> M[错误处理]
    C --> N[格式错误]
    D --> O[解析错误]
    E --> P[写入错误]
    
    style A fill:#e1f5fe
    style L fill:#e1f5fe
    style G fill:#f3e5f5
```

## 详细数据流程图

### 1. CSV导入流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant CSVManager as CSV数据管理器
    participant Parser as CSV解析器
    participant Storage as 存储引擎
    participant RocksDB as RocksDB
    
    User->>CSVManager: import_csv(file_path, business_type)
    CSVManager->>CSVManager: 验证业务类型
    CSVManager->>Parser: 打开CSV文件
    Parser->>Parser: 读取表头
    Parser->>CSVManager: 返回表头
    CSVManager->>CSVManager: 验证必需字段
    
    loop 逐行处理
        Parser->>Parser: 解析CSV行
        Parser->>CSVManager: 返回解析数据
        CSVManager->>CSVManager: 数据转换和验证
        CSVManager->>Storage: 批量写入数据
        Storage->>RocksDB: 写入RocksDB
        RocksDB->>Storage: 写入确认
    end
    
    CSVManager->>User: 返回导入结果
```

### 2. CSV导出流程

```mermaid
sequenceDiagram
    participant User as 用户
    participant CSVManager as CSV数据管理器
    participant Storage as 存储引擎
    participant RocksDB as RocksDB
    participant File as 导出文件
    
    User->>CSVManager: export_csv(file_path, business_type, time_range)
    CSVManager->>CSVManager: 验证业务类型
    CSVManager->>Storage: 查询数据
    Storage->>RocksDB: 读取数据
    RocksDB->>Storage: 返回查询结果
    Storage->>CSVManager: 返回数据点
    
    CSVManager->>File: 创建CSV文件
    CSVManager->>File: 写入表头
    
    loop 逐行写入
        CSVManager->>CSVManager: 格式化数据行
        CSVManager->>File: 写入CSV行
    end
    
    CSVManager->>User: 返回导出结果
```

## 核心组件交互图

### CSV数据管理器架构

```mermaid
graph LR
    A[CSV文件输入] --> B[SimpleCSVParser]
    B --> C[CSVDataManager]
    C --> D[业务Schema验证]
    D --> E[数据转换]
    E --> F[批量写入]
    F --> G[存储引擎接口]
    
    H[查询请求] --> I[数据查询]
    I --> J[CSV格式化]
    J --> K[文件输出]
    
    subgraph "业务类型支持"
        L[股票行情]
        M[IOT数据]
        N[金融行情]
        O[订单数据]
        P[支付数据]
        Q[库存数据]
        R[短信数据]
    end
    
    D --> L
    D --> M
    D --> N
    D --> O
    D --> P
    D --> Q
    D --> R
```

## 数据处理状态图

### CSV导入状态流转

```mermaid
stateDiagram-v2
    [*] --> 文件验证
    文件验证 --> 格式正确: 文件存在且可读
    文件验证 --> 错误处理: 文件不存在或不可读
    
    格式正确 --> 表头解析
    表头解析 --> 必需字段验证
    必需字段验证 --> 字段完整: 必需字段存在
    必需字段验证 --> 错误处理: 缺少必需字段
    
    字段完整 --> 数据解析
    数据解析 --> 数据转换
    数据转换 --> 批量写入
    批量写入 --> 写入成功: 批量写入完成
    批量写入 --> 写入失败: 写入错误
    
    写入成功 --> [*]
    写入失败 --> 错误处理
    错误处理 --> [*]
```

### CSV导出状态流转

```mermaid
stateDiagram-v2
    [*] --> 参数验证
    参数验证 --> 查询准备: 参数有效
    参数验证 --> 错误处理: 参数无效
    
    查询准备 --> 数据查询
    数据查询 --> 查询成功: 数据获取成功
    数据查询 --> 查询失败: 数据获取失败
    
    查询成功 --> 文件创建
    文件创建 --> 表头写入
    表头写入 --> 数据格式化
    数据格式化 --> 数据写入
    数据写入 --> 导出完成
    
    导出完成 --> [*]
    查询失败 --> 错误处理
    错误处理 --> [*]
```

## 业务数据Schema图

### 支持的CSV格式类型

```mermaid
graph TB
    A[CSV数据格式] --> B[股票行情数据]
    A --> C[IOT设备数据]
    A --> D[金融行情数据]
    A --> E[订单数据]
    A --> F[支付数据]
    A --> G[库存数据]
    A --> H[短信下发数据]
    
    B --> B1[timestamp, stock_code, market, open, high, low, close, volume, amount]
    C --> C1[timestamp, device_id, sensor_type, value, unit, location, status]
    D --> D1[timestamp, symbol, exchange, bid, ask, last_price, volume, change, change_percent]
    E --> E1[timestamp, order_id, user_id, product_id, quantity, price, status, payment_method]
    F --> F1[timestamp, payment_id, order_id, amount, currency, status, payment_gateway, user_id]
    G --> G1[timestamp, product_id, warehouse_id, quantity, location, status, last_updated_by]
    H --> H1[timestamp, sms_id, phone_number, content, status, template_id, send_time, delivery_time]
    
    style B1 fill:#f3e5f5
    style C1 fill:#f3e5f5
    style D1 fill:#f3e5f5
    style E1 fill:#f3e5f5
    style F1 fill:#f3e5f5
    style G1 fill:#f3e5f5
    style H1 fill:#f3e5f5
```

## 错误处理流程图

### CSV导入错误处理

```mermaid
flowchart TD
    A[开始CSV导入] --> B{文件验证}
    B -->|成功| C{格式验证}
    B -->|失败| D[返回文件错误]
    
    C -->|成功| E{数据解析}
    C -->|失败| F[返回格式错误]
    
    E -->|成功| G{批量写入}
    E -->|失败| H[返回解析错误]
    
    G -->|成功| I[返回导入成功]
    G -->|失败| J[返回写入错误]
    
    D --> K[结束]
    F --> K
    H --> K
    J --> K
    I --> K
```

### CSV导出错误处理

```mermaid
flowchart TD
    A[开始CSV导出] --> B{参数验证}
    B -->|成功| C{数据查询}
    B -->|失败| D[返回参数错误]
    
    C -->|成功| E{文件创建}
    C -->|失败| F[返回查询错误]
    
    E -->|成功| G{数据写入}
    E -->|失败| H[返回文件错误]
    
    G -->|成功| I[返回导出成功]
    G -->|失败| J[返回写入错误]
    
    D --> K[结束]
    F --> K
    H --> K
    J --> K
    I --> K
```

## 性能优化流程图

### 批量处理优化

```mermaid
graph LR
    A[单条处理] --> B[性能瓶颈]
    B --> C[批量处理优化]
    C --> D[批量大小调优]
    D --> E[内存优化]
    E --> F[并发处理]
    F --> G[最优性能]
    
    style G fill:#c8e6c9
```

### 缓存策略

```mermaid
graph TB
    A[CSV解析] --> B[数据缓存]
    B --> C[批量写入缓存]
    C --> D[存储引擎缓存]
    D --> E[RocksDB写入]
    
    F[查询请求] --> G[存储引擎缓存]
    G --> H[CSV格式化缓存]
    H --> I[文件输出缓存]
    
    style B fill:#fff3e0
    style C fill:#fff3e0
    style D fill:#fff3e0
    style G fill:#fff3e0
    style H fill:#fff3e0
```

## 实际使用示例

### 股票数据导入流程

```mermaid
sequenceDiagram
    participant T as 测试脚本
    participant CM as CSV管理器
    participant SE as 存储引擎
    participant RDB as RocksDB
    
    T->>CM: import_csv('test_stock_data.csv', 'stock_quotes')
    CM->>CM: 验证stock_quotes schema
    CM->>CM: 打开CSV文件
    CM->>CM: 验证必需字段: timestamp, stock_code, market, close
    
    loop 处理5条股票数据
        CM->>CM: 解析行数据
        CM->>CM: 转换数据格式
        CM->>SE: write_point('stock_quotes', timestamp, close, tags)
        SE->>RDB: 写入RocksDB
        RDB->>SE: 确认写入
        SE->>CM: 返回成功
    end
    
    CM->>T: 返回导入结果: 5条成功，0条错误
```

### IOT数据导出流程

```mermaid
sequenceDiagram
    participant T as 测试脚本
    participant CM as CSV管理器
    participant SE as 存储引擎
    participant RDB as RocksDB
    participant F as 导出文件
    
    T->>CM: export_csv('exported_iot_data.csv', 'iot_data', start_time, end_time)
    CM->>CM: 验证iot_data schema
    CM->>SE: 查询数据: metric='iot_data', time_range
    SE->>RDB: 读取数据
    RDB->>SE: 返回数据点
    SE->>CM: 返回查询结果
    
    CM->>F: 创建导出文件
    CM->>F: 写入表头: timestamp, device_id, sensor_type, value, unit, location, status
    
    loop 格式化并写入数据
        CM->>CM: 格式化数据行
        CM->>F: 写入CSV行
    end
    
    CM->>T: 返回导出结果: 5条数据导出成功
```

## 总结

CSV数据流程图展示了Stock-TSDB系统中完整的数据导入导出机制，包括：

1. **多业务类型支持** - 7种不同的业务数据格式
2. **完整的验证流程** - 文件、格式、数据三层验证
3. **批量处理优化** - 提升导入导出性能
4. **错误处理机制** - 完善的错误检测和恢复
5. **缓存策略** - 多级缓存提升性能

该流程图为开发和运维人员提供了清晰的CSV数据处理参考，确保数据处理的可靠性和高效性。