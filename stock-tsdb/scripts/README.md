# Stock-TSDB 脚本目录

本目录包含 Stock-TSDB 项目的各种管理和运维脚本，按照功能分类组织。

## 目录结构

```
scripts/
├── README.md                    # 本文件
├── bin/                        # 可执行脚本（添加到PATH）
│   ├── stock-tsdb              # 主启动脚本
│   ├── stock-tsdb-server       # 服务器启动脚本
│   └── stock-tsdb-cli          # 命令行工具
├── deploy/                     # 部署相关脚本
│   ├── install.sh              # 安装脚本
│   ├── deploy-production.sh    # 生产环境部署
│   ├── backup.sh               # 备份脚本
│   └── uninstall.sh           # 卸载脚本
├── dev/                        # 开发环境脚本
│   ├── setup.sh                # 开发环境设置
│   ├── start-dev.sh            # 启动开发环境
│   ├── stop-dev.sh             # 停止开发环境
│   └── test.sh                 # 测试脚本
├── monitor/                    # 监控和维护脚本
│   ├── health-check.sh         # 健康检查
│   ├── status.sh               # 状态检查
│   ├── logs.sh                 # 日志查看
│   └── metrics.sh              # 指标收集
├── utils/                      # 工具脚本
│   ├── validate.sh             # 项目验证
│   ├── config.sh               # 配置管理
│   └── release.sh              # 发布脚本
└── templates/                  # 模板文件
    ├── systemd.service         # systemd服务模板
    └── nginx.conf              # nginx配置模板
```

## 使用说明

### 开发环境

```bash
# 设置开发环境
./scripts/dev/setup.sh

# 启动开发环境
./scripts/dev/start-dev.sh

# 运行测试
./scripts/dev/test.sh
```

### 生产环境

```bash
# 安装到系统
./scripts/deploy/install.sh

# 部署到生产环境
./scripts/deploy/deploy-production.sh

# 健康检查
./scripts/monitor/health-check.sh
```

### 快速启动

```bash
# 使用主启动脚本（推荐）
./scripts/bin/stock-tsdb start
./scripts/bin/stock-tsdb stop
./scripts/bin/stock-tsdb status
```

## 脚本说明

### bin/ 目录

- **stock-tsdb**: 主控制脚本，提供统一的命令接口
- **stock-tsdb-server**: 服务器启动脚本
- **stock-tsdb-cli**: 命令行工具，用于数据操作

### deploy/ 目录

- **install.sh**: 完整的系统安装脚本
- **deploy-production.sh**: 生产环境部署脚本
- **backup.sh**: 数据备份和恢复脚本
- **uninstall.sh**: 系统卸载脚本

### dev/ 目录

- **setup.sh**: 开发环境设置脚本
- **start-dev.sh**: 开发环境启动脚本
- **stop-dev.sh**: 开发环境停止脚本
- **test.sh**: 测试运行脚本

### monitor/ 目录

- **health-check.sh**: 系统健康检查
- **status.sh**: 服务状态检查
- **logs.sh**: 日志查看和管理
- **metrics.sh**: 性能指标收集

### utils/ 目录

- **validate.sh**: 项目完整性验证
- **config.sh**: 配置管理工具
- **release.sh**: 版本发布脚本

## 最佳实践

1. **权限设置**: 所有脚本都应设置为可执行：`chmod +x scripts/**/*.sh`
2. **环境变量**: 使用环境变量进行配置，避免硬编码
3. **错误处理**: 所有脚本都应包含适当的错误处理
4. **日志记录**: 重要的操作应该记录日志
5. **安全性**: 生产环境脚本应考虑安全性

## 扩展开发

如需添加新脚本，请遵循以下规范：

1. 根据功能放入相应的目录
2. 提供完整的帮助信息
3. 包含错误处理和日志记录
4. 添加适当的权限设置
5. 更新本README文档