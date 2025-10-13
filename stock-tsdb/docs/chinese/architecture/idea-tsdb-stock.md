用于股市行情数据TSDB 系统

方案 A：「分块 + 列偏移」——最像 OpenTSDB， **顺序写、顺序读** ，行情实盘首选

**可直接编译运行**的 LuaJIT + RocksDB 实现（方案 A：30 s 定长块 + 微秒列偏移）

1. 参考open tsdb 的RowKey+Qualifier 机制；
2. 借鉴 kvrocks 处理 meta 与data 数据 cf；
3. 技术 zeromq luajit  rdocksdb；使用事件驱动机制；
4. lzmq-ffi 实现事件驱动提供服务端口；**luarocks install --local lzmq-ffi**
5. luajit ffi 调用 rocksdb
6. 优化达到生产级别使用；
7. 提供redis-cli 接口；提供批量数据接口；
8. lua 脚本实现业务逻辑；可配置；热更新；
9. zeromq 实现分布式集群；
10. consul 高可用（已替换etcd）；
11. rocksdb性能优化
    11.1 按 自然日 分 ColumnFamily（CF）

    ```
    每天自动新建一个 CF
    冷数据 CF 可单独设置 ZSTD 压缩 + 关闭自动 Compaction
    想删 30 天前数据，直接 Drop 整个 CF，秒级完成，不产生 Compaction 抖动。
    ```
    11.2 按 市场 分 DB 实例
