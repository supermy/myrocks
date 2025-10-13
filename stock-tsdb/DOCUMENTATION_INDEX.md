# Stock-TSDB 文档索引

本文档提供 Stock-TSDB 项目所有文档的索引和导航。

## 📚 核心文档

### 项目说明
- [README.md](../README.md) - 项目主说明文档
- [PROJECT_STRUCTURE.md](../PROJECT_STRUCTURE.md) - 项目结构说明
- [CHANGELOG.md](../CHANGELOG.md) - 变更日志

### 架构设计
- [系统架构图](architecture/SYSTEM_ARCHITECTURE_DIAGRAM.md)
- [技术设计综合文档](architecture/TECHNICAL_DESIGN_COMPREHENSIVE.md)
- [业务分离架构](architecture/BUSINESS_SEPARATION_ARCHITECTURE.md)
- [TSDB集群优化指南](architecture/TSDB_CLUSTER_OPTIMIZATION_GUIDE.md)

### 存储引擎
- [V3存储引擎完整指南](guides/V3_STORAGE_ENGINE_COMPLETE_GUIDE.md)
- [V3版本对比报告](guides/V3_VERSION_COMPARISON_REPORT.md)
- [V3集成版本总结](guides/V3_INTEGRATED_SUMMARY.md)
- [V3性能优化总结](guides/V3_PERFORMANCE_OPTIMIZATION_SUMMARY.md)

### 集群和集成
- [Consul集成总结](architecture/CONSUL_INTEGRATION_SUMMARY.md)
- [Consul生产部署](architecture/CONSUL_PRODUCTION_DEPLOYMENT.md)
- [ETCD到Consul迁移指南](architecture/MIGRATION_ETCD_TO_CONSUL.md)
- [Redis TCP服务器实现](architecture/REDIS_TCP_SERVER_IMPLEMENTATION.md)

## 🛠️ 使用指南

### 安装和部署
- [Ubuntu/Debian安装指南](guides/README_Ubuntu_Debian.md)
- [Makefile改进文档](guides/MAKEFILE_IMPROVEMENTS.md)
- [生产环境脚本指南](guides/PRODUCTION_SCRIPTS_GUIDE.md)

### 开发和测试
- [项目文档总结](guides/PROJECT_DOCUMENTATION_SUMMARY.md)
- [V3重构完成总结](guides/V3_REFACTOR_COMPLETION_SUMMARY.md)
- [微秒级时序分析指南](guides/micro_ts_analysis_guide.md)
- [微秒级时序优化总结](guides/micro_ts_optimization_summary.md)

## 📊 性能报告

### 性能分析
- [微秒级时序性能图表](reports/micro_ts_performance_charts.html)
- [插件对比最终报告](reports/plugin_comparison_final.txt)
- [行键值插件性能报告](reports/rowkey_value_plugin_performance_report.json)

### 测试报告
- [微秒级时序最终修复报告](guides/micro_ts_final_fix_report.md)
- [微秒级时序测试分析对比](guides/micro_ts_test_analysis_comparison.md)

## 📁 目录结构

```
docs/
├── architecture/           # 架构设计文档
│   ├── BUSINESS_SEPARATION_ARCHITECTURE.md
│   ├── CONSUL_INTEGRATION_SUMMARY.md
│   ├── CONSUL_PRODUCTION_DEPLOYMENT.md
│   ├── MIGRATION_ETCD_TO_CONSUL.md
│   ├── REDIS_TCP_SERVER_IMPLEMENTATION.md
│   ├── SYSTEM_ARCHITECTURE_DIAGRAM.md
│   ├── TECHNICAL_DESIGN_COMPREHENSIVE.md
│   ├── TSDB_CLUSTER_OPTIMIZATION_GUIDE.md
│   └── TSDB_REDIS_SYSTEM_ARCHITECTURE.md
├── chinese/                # 中文文档
│   ├── architecture/       # 中文架构文档
│   ├── design/            # 中文设计文档
│   └── requirements/      # 中文需求文档
├── guides/                 # 使用指南和教程
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
├── reports/                # 性能报告和分析
│   ├── micro_ts_performance_charts.html
│   ├── plugin_comparison_final.txt
│   ├── plugin_comparison_output.txt
│   ├── plugin_comparison_output_fixed.txt
│   ├── plugin_comparison_with_micro_ts_final.txt
│   └── rowkey_value_plugin_performance_report.json
└── urban_management/       # 城市管理相关文档
```

## 🔧 脚本和工具

### 安装脚本
- [install.sh](../scripts/install/install.sh) - 基础安装脚本
- [install_ubuntu_debian.sh](../scripts/install/install_ubuntu_debian.sh) - Ubuntu/Debian专用安装
- [uninstall.sh](../scripts/install/uninstall.sh) - 卸载脚本

### 部署脚本
- [production_deploy.sh](../scripts/install/production_deploy.sh) - 生产环境部署
- [package_ubuntu_debian.sh](../scripts/install/package_ubuntu_debian.sh) - 打包脚本

### 维护脚本
- [monitor_production.sh](../scripts/install/monitor_production.sh) - 生产环境监控
- [backup_production.sh](../scripts/install/backup_production.sh) - 备份脚本
- [maintain_production.sh](../scripts/install/maintain_production.sh) - 维护脚本

### 开发脚本
- [start_business_web.sh](../scripts/start_business_web.sh) - 业务数据Web服务器启动脚本
- [check_project_status.sh](../scripts/check_project_status.sh) - 项目状态检查脚本
- [setup_dev_env.sh](../scripts/setup_dev_env.sh) - 开发环境设置脚本

## 🚀 快速开始

### 快速开始指南
- [快速开始指南](docs/guides/QUICK_START.md) - 快速上手Stock-TSDB
- [安装指南](docs/guides/INSTALLATION_GUIDE.md) - 详细安装说明
- [配置指南](docs/guides/CONFIGURATION_GUIDE.md) - 系统配置说明
- [开发环境设置](scripts/setup_dev_env.sh) - 开发环境快速搭建
- [项目状态检查](scripts/check_project_status.sh) - 验证项目完整性

### 开发环境
```bash
# 克隆项目
git clone <repository-url>
cd stock-tsdb

# 安装依赖
make install-deps

# 构建项目
make build

# 运行测试
make test-quick

# 启动开发环境
make dev-start
```

### 生产部署
```bash
# 使用部署脚本
./scripts/install/production_deploy.sh deploy -m basic

# 或者使用Makefile
make deploy-production
```

## 📞 支持

- **问题报告**: 请使用项目的 Issue 跟踪系统
- **文档问题**: 如果发现文档错误或缺失，请提交 Pull Request
- **功能请求**: 欢迎提出新功能建议

## 🤝 贡献

我们欢迎社区贡献！请参考：
- [贡献指南](guides/CONTRIBUTING.md)
- [代码风格指南](guides/CODING_STYLE.md)
- [测试指南](guides/TESTING_GUIDE.md)

---

*最后更新: 2024-12-01*