# LuaJIT FFI 调用 RocksDB 总结

## 项目概述
本项目演示了如何使用 LuaJIT 的 FFI (Foreign Function Interface) 直接调用 RocksDB 的 C API，实现高性能的键值存储功能，特别适用于股票行情数据的存储和查询。

## 实现要点

### 1. FFI 定义
通过 `ffi.cdef` 函数定义了 RocksDB 的 C API 接口，包括：
- 基本数据类型（rocksdb_t, rocksdb_options_t 等）
- 核心函数（rocksdb_open, rocksdb_put, rocksdb_get 等）
- 迭代器相关函数（rocksdb_create_iterator, rocksdb_iter_seek 等）

### 2. 库加载
使用 `ffi.load("rocksdb")` 加载 RocksDB 共享库。

### 3. 存储引擎封装
创建了 StorageEngine 类，封装了以下功能：
- 数据库打开/关闭
- 数据读写（put/get）
- 迭代器功能（scan_prefix）

### 4. 股票行情数据示例
提供了两个示例脚本：
1. 基础示例 (`stock_example.lua`) - 演示基本的读写操作
2. 高级示例 (`advanced_stock_example.lua`) - 演示迭代器功能，可按前缀查询数据

## 核心优势

### 1. 高性能
- 直接调用 C API，避免了额外的绑定层开销
- 利用 LuaJIT 的 JIT 编译优化执行性能

### 2. 灵活性
- 可以直接使用 RocksDB 的所有功能
- 通过面向对象封装，提供更易用的接口

### 3. 内存安全
- 使用 `ffi.gc` 自动管理 C 对象的生命周期
- 正确处理内存释放，避免内存泄漏

## 使用方法

1. 确保系统已安装 RocksDB 共享库
2. 运行示例脚本：
   ```
   luajit stock_example.lua
   luajit advanced_stock_example.lua
   ```

## 键值设计

针对股票行情数据的特点，采用以下键值设计：
- 键格式：`股票代码:时间戳` (如 "SH000001:1625097600")
- 值格式：`价格:成交量` (如 "3580.23:123456789")

这种设计支持：
- 快速按股票代码和时间查询
- 高效的范围查询（通过迭代器）
- 紧凑的数据存储格式

## 总结

通过 LuaJIT FFI 调用 RocksDB，我们实现了：
1. 高性能的股票行情数据存储方案
2. 灵活的数据查询接口
3. 易于扩展的功能（可轻松添加更多 RocksDB 功能）

这种方法比传统的 Lua C 模块绑定更加简洁高效，特别适合需要高性能存储的金融数据应用场景。