# Stock-TSDB 项目结构说明

## 重构后的项目组织

本项目经过重构，采用了清晰的功能模块化目录结构，便于维护和扩展。

## 根目录结构

```
stock-tsdb/
├── README.md                    # 项目主说明文档
├── LICENSE                      # 开源许可证
├── Makefile                    # 构建和测试脚本
├── Dockerfile                  # Docker容器化配置
├── docker-compose.yml          # Docker Compose配置
├── stock-tsdb                  # 主可执行文件
├── stock-tsdb.sh               # 服务管理脚本
├── server.log                  # 服务日志文件
├── .gitignore                  # Git忽略文件配置
├── bin/                        # 二进制文件目录
├── conf/                       # 配置文件目录
├── config/                     # 应用配置目录
│   ├── business/               # 业务配置
│   └── performance/            # 性能配置
├── data/                       # 数据文件目录
├── docs/                       # 文档目录
├── examples/                   # 示例代码目录
├── lib/                        # 库文件目录
├── logs/                       # 日志文件目录
├── lua/                        # Lua核心代码目录
├── scripts/                    # 脚本目录
├── src/                        # C++源代码目录
└── tests/                      # 测试文件目录
```

## 详细目录说明

### docs/ - 文档目录
```
docs/
├── architecture/               # 架构设计文档
│   ├── BUSINESS_SEPARATION_ARCHITECTURE.md
│   ├── CONSUL_INTEGRATION_SUMMARY.md
│   ├── CONSUL_PRODUCTION_DEPLOYMENT.md
│   ├── MIGRATION_ETCD_TO_CONSUL.md
│   ├── REDIS_TCP_SERVER_IMPLEMENTATION.md
│   ├── SYSTEM_ARCHITECTURE_DIAGRAM.md
│   ├── TECHNICAL_DESIGN_COMPREHENSIVE.md
│   ├── TSDB_CLUSTER_OPTIMIZATION_GUIDE.md
│   └── TSDB_REDIS_SYSTEM_ARCHITECTURE.md
├── chinese/                    # 中文文档
│   ├── architecture/           # 中文架构文档
│   ├── design/                # 中文设计文档
│   └── requirements/          # 中文需求文档
├── guides/                     # 使用指南和教程
│   ├── MAKEFILE_IMPROVEMENTS.md
│   ├── PRODUCTION_SCRIPTS_GUIDE.md
│   ├── PROJECT_DOCUMENTATION_SUMMARY.md
│   ├── README_Ubuntu_Debian.md
│   ├── V3_INTEGRATED_SUMMARY.md
│   ├── V3_PERFORMANCE_OPTIMIZATION_SUMMARY.md
│   ├── V3_REFACTOR_COMPLETION_SUMMARY.md
│   ├── V3_STORAGE_ENGINE_COMPLETE_GUIDE.md
│   ├── V3_VERSION_COMPARISON_REPORT.md
│   ├── micro_ts_analysis_guide.md
│   ├── micro_ts_final_fix_report.md
│   ├── micro_ts_optimization_summary.md
│   └── micro_ts_test_analysis_comparison.md
├── reports/                    # 性能报告和分析
│   ├── micro_ts_performance_charts.html
│   ├── plugin_comparison_final.txt
│   ├── plugin_comparison_output.txt
│   ├── plugin_comparison_output_fixed.txt
│   ├── plugin_comparison_with_micro_ts_final.txt
│   └── rowkey_value_plugin_performance_report.json
├── CHANGELOG.md               # 变更日志
└── DOCUMENTATION_INDEX.md    # 文档索引
```

### examples/ - 示例代码目录
```
examples/
├── business/                  # 业务相关示例
│   ├── business_data_cluster_test.lua
│   ├── demo_business_separation.lua
│   ├── start_business_instances.lua
│   ├── test_business_cluster.lua
│   └── test_business_instances.lua
├── cluster/                   # 集群相关示例
│   ├── consistent_hash_cluster.lua
│   ├── test_cold_hot_cluster.lua
│   └── test_optimized_cluster.lua
├── consul/                    # Consul集成示例
│   ├── consul_ffi.lua
│   ├── consul_ha_cluster.lua
│   ├── consul_production_config.lua
│   ├── consul_production_example.lua
│   ├── consul_simulation_demo.lua
│   └── test_consul_integration.lua
├── performance/               # 性能分析示例
│   ├── v3_detailed_performance_comparison.lua
│   ├── v3_performance_analysis_final.lua
│   ├── v3_performance_optimization_analysis.lua
│   └── v3_performance_optimization_fix.lua
├── plugins/                  # 插件示例
│   └── rowkey_value_plugin_performance_comparison.lua
├── redis/                    # Redis相关示例
│   ├── integrate_redis_tcp_server.lua
│   ├── simple_redis_tcp_verification.lua
│   ├── start_redis_tcp_server.lua
│   ├── test_redis_tcp_server.lua
│   └── verify_redis_tcp_integration.lua
├── storage/                  # 存储引擎示例
│   ├── integrate_daily_cf_example.lua
│   └── test_daily_cf_engine.lua
├── testing/                  # 测试示例
│   ├── test_cjson_paths.lua
│   ├── test_commons_refactor.lua
│   └── test_config_manager.lua
└── v3/                       # V3版本示例
    ├── test_v3_basic.lua
    ├── test_v3_comparison.lua
    ├── test_v3_final_comparison.lua
    ├── test_v3_integrated.lua
    ├── test_v3_simple_comparison.lua
    └── test_v3_validation.lua
```

### scripts/ - 脚本目录
```
scripts/
├── deployment/                # 部署脚本
│   └── production_deploy.sh
├── install/                  # 安装脚本
│   ├── install.sh
│   ├── install_ubuntu_debian.sh
│   ├── package_ubuntu_debian.sh
│   └── uninstall.sh
└── maintenance/              # 维护脚本
    ├── backup_production.sh
    ├── maintain_production.sh
    └── monitor_production.sh
```

### lua/ - Lua核心代码目录
```
lua/
├── commons/                  # 公共模块
│   ├── init.lua             # 公共模块初始化
│   ├── config_utils.lua     # 配置工具
│   ├── logger.lua           # 日志模块
│   ├── utils.lua            # 工具函数
│   ├── redis_protocol.lua   # Redis协议
│   └── error_handler.lua    # 错误处理
├── main.lua                 # 程序主入口
├── tsdb_storage_engine_v3.lua # V3存储引擎
└── ... (其他核心模块文件)
```

## 重构优势

1. **模块化组织**: 按功能模块分类，便于查找和维护
2. **清晰的层次结构**: 文档、示例、脚本、代码分离
3. **易于扩展**: 新增功能可以按模块添加到相应目录
4. **维护友好**: 相关文件集中管理，减少文件查找时间
5. **标准化结构**: 符合现代软件开发的最佳实践

## 使用说明

- **开发人员**: 主要关注 `lua/` 目录和 `examples/` 目录
- **运维人员**: 主要关注 `scripts/` 目录和 `docs/guides/` 目录
- **架构师**: 主要关注 `docs/architecture/` 目录
- **测试人员**: 主要关注 `examples/testing/` 和 `tests/` 目录

## 注意事项

- 所有路径引用已更新为新的目录结构
- Makefile 中的测试目标已适配新的文件位置
- 模块导入路径已正确配置，确保功能正常