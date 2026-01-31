# 📚 V3存储引擎文档索引

## 🎯 快速入门
- [V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md) - 🌟 **推荐优先阅读**
- [快速开始指南](README.md) - 项目基本介绍

## 📖 核心文档

### 版本对比与选择
| 文档 | 描述 | 关键内容 |
|------|------|----------|
| [V3版本对比报告](V3_VERSION_COMPARISON_REPORT.md) | 详细性能对比 | 写入/查询性能基准测试 |
| [V3集成版本总结](V3_INTEGRATED_SUMMARY.md) | 集成版本特性 | 分布式架构、集群功能 |
| [V3重构完成总结](V3_REFACTOR_COMPLETION_SUMMARY.md) | 插件化重构成果 | 架构设计、接口统一 |

### 开发与测试
| 文档 | 描述 | 使用场景 |
|------|------|----------|
| [Makefile改进文档](MAKEFILE_IMPROVEMENTS.md) | 测试工具完善 | 新增测试目标、快速验证 |
| [V3基础版本测试报告](test_v3_basic_report.md) | 基础版本测试结果 | 单机性能测试 |
| [V3集成版本测试报告](test_v3_integrated_report.md) | 集成版本测试结果 | 分布式功能测试 |

### 架构与技术
| 文档 | 描述 | 技术要点 |
|------|------|----------|
| [V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md) | 完整技术指南 | 架构设计、部署指南 |
| [V3插件化架构设计](V3_PLUGIN_ARCHITECTURE.md) | 插件化设计 | 接口统一、扩展性 |

## 🚀 使用建议

### 新手用户
1. 首先阅读 [V3存储引擎完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md)
2. 运行 `make health-check` 检查环境
3. 运行 `make test-quick` 快速体验
4. 根据需求选择版本（基础版/集成版）

### 开发用户
1. 查看 [Makefile改进文档](MAKEFILE_IMPROVEMENTS.md) 了解测试工具
2. 运行 `make test-v3` 完整测试
3. 参考 [V3重构完成总结](V3_REFACTOR_COMPLETION_SUMMARY.md) 理解架构
4. 根据场景选择部署模式

### 运维用户
1. 重点阅读 [V3集成版本总结](V3_INTEGRATED_SUMMARY.md)
2. 参考 [V3版本对比报告](V3_VERSION_COMPARISON_REPORT.md) 做容量规划
3. 使用 `make clean-v3` 等工具进行维护

## 📊 版本选择决策树

```
需求分析
├── 数据规模 < 100万点/天？
│   ├── 是 → V3基础版本 ✅
│   └── 否 → 继续分析
└── 需要分布式部署？
    ├── 否 → V3基础版本 ✅
    └── 是 → V3集成版本 ✅
```

## 🎯 关键指标对比

| 指标 | V3基础版本 | V3集成版本 | 推荐场景 |
|------|------------|------------|----------|
| 写入性能 | 200-350万点/秒 | 30-55万点/秒 | 基础版适合高吞吐 |
| 查询性能 | 1000-1200万点/秒 | 10-57万点/秒 | 基础版适合快速查询 |
| 部署复杂度 | 简单 | 复杂 | 基础版适合快速部署 |
| 扩展性 | 单机 | 分布式 | 集成版适合大规模 |
| 高可用 | 单机 | 集群 | 集成版适合生产环境 |

## 📋 技术设计文档

### 综合技术方案
| 文档 | 描述 | 覆盖内容 |
|------|------|----------|
| [技术设计综合文档](TECHNICAL_DESIGN_COMPREHENSIVE.md) | 🌟 **研究阶段完整整合** | 技术复用、两套方案、实现细节、架构设计 |
| [Study文档合并总结](STUDY_DOCUMENTS_MERGED_SUMMARY.md) | 文档整理说明 | 合并过程、阅读建议、技术要点 |

### 运维与部署
| 文档 | 描述 | 主要内容 |
|------|------|----------|
| [生产环境脚本指南](PRODUCTION_SCRIPTS_GUIDE.md) | 完整运维指南 | 部署、监控、备份、维护脚本 |

## 🔧 常用命令速查

### 环境检查
```bash
make health-check      # 系统健康检查
make test-quick        # 快速验证测试
```

### 版本测试
```bash
make test-v3-basic        # 基础版本测试
make test-v3-integrated   # 集成版本测试
make test-v3-comparison   # 版本对比测试
make test-v3              # 完整测试套件
```

### 数据清理
```bash
make clean           # 清理构建文件
make clean-v3        # 清理V3测试数据
```

### 帮助信息
```bash
make help            # 显示所有可用目标
```

## 🆕 优化方案文档 (2026-01)

### 六大优化方案完整指南
| 文档 | 描述 | 覆盖内容 |
|------|------|----------|
| [优化方案完整指南](OPTIMIZATION_SCHEMES_COMPLETE_GUIDE.md) | 🌟 **六大优化方案详解** | 方案1-6完整实现、使用指南、测试验证 |

### 优化方案组件文档
| 方案 | 组件 | 文档 | 测试状态 |
|------|------|------|----------|
| 方案3 | 智能负载均衡 | lua/smart_load_balancer.lua | ✅ 25项测试通过 |
| 方案3 | 性能监控 | lua/performance_monitor.lua | ✅ 25项测试通过 |
| 方案4 | 连接池管理 | lua/connection_pool.lua | ✅ 25项测试通过 |
| 方案4 | 容错管理 | lua/fault_tolerance_manager.lua | ✅ 25项测试通过 |
| 方案5 | 配置管理 | lua/config_manager_advanced.lua | ✅ 36项测试通过 |
| 方案5 | 安全管理 | lua/security_manager.lua | ✅ 36项测试通过 |
| 方案6 | 部署管理 | lua/deployment_manager.lua | ✅ 36项测试通过 |
| 方案6 | 性能基准 | lua/performance_benchmark.lua | ✅ 36项测试通过 |

### 优化方案测试
```bash
# 运行方案3和4测试
luajit tests/test_optimization_3_4.lua

# 运行方案5和6测试
luajit tests/test_optimization_5_6.lua
```

## 📈 文档更新记录

| 日期 | 更新内容 | 相关文档 |
|------|----------|----------|
| 2026-01 | 六大优化方案实现完成 | OPTIMIZATION_SCHEMES_COMPLETE_GUIDE.md |
| 2026-01 | 新增8个核心组件 | lua/*_manager.lua |
| 2026-01 | 新增优化方案测试 | tests/test_optimization_*.lua |
| 2024-01 | Study目录文档合并整理 | TECHNICAL_DESIGN_COMPREHENSIVE.md |
| 2024-01 | 创建完整技术设计综合文档 | STUDY_DOCUMENTS_MERGED_SUMMARY.md |
| 2024-01 | 创建完整指南 | V3_STORAGE_ENGINE_COMPLETE_GUIDE.md |
| 2024-01 | Makefile测试工具完善 | MAKEFILE_IMPROVEMENTS.md |
| 2024-01 | V3插件化重构完成 | V3_REFACTOR_COMPLETION_SUMMARY.md |
| 2024-01 | 版本对比测试 | V3_VERSION_COMPARISON_REPORT.md |

## 🔗 相关链接

- [项目主页](README.md)
- [源代码目录](src/)
- [配置文件](conf/)
- [测试脚本](test/)

## 💡 反馈与建议

如果您在使用过程中遇到问题或有改进建议，欢迎：
1. 查看相关技术文档
2. 运行诊断命令
3. 参考故障排除指南
4. 提交问题反馈

---

**📌 提示**: 本文档索引会随项目发展持续更新，建议定期查看最新版本。