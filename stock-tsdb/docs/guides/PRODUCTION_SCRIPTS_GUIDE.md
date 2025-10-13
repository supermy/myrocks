# Stock-TSDB 生产环境脚本使用指南

## 概述

本指南详细介绍了 Stock-TSDB 生产环境相关脚本的使用方法，包括部署、监控、备份和维护等功能。这些脚本为生产环境的稳定运行提供了完整的解决方案。

## 脚本列表

### 1. 部署脚本
- **`production_deploy.sh`** - 生产环境部署脚本
- **`install.sh`** - 基础安装脚本
- **`stock-tsdb.sh`** - 服务管理脚本

### 2. 监控脚本
- **`monitor_production.sh`** - 生产环境监控脚本

### 3. 备份脚本
- **`backup_production.sh`** - 生产环境备份脚本

### 4. 维护脚本
- **`maintain_production.sh`** - 生产环境维护脚本

## 详细使用说明

### 部署脚本使用

#### production_deploy.sh

功能：完整的生产环境部署，支持基础版和集成版部署

```bash
# 基础部署
./production_deploy.sh deploy

# 集成版部署（含监控）
./production_deploy.sh deploy integrated

# 升级部署
./production_deploy.sh upgrade

# 回滚到上一版本
./production_deploy.sh rollback

# 备份当前版本
./production_deploy.sh backup

# 恢复指定版本
./production_deploy.sh restore 20231201-120000
```

参数说明：
- `deploy` - 部署新版本
- `upgrade` - 升级现有版本
- `rollback` - 回滚到上一版本
- `backup` - 创建当前版本备份
- `restore` - 恢复指定版本

#### install.sh

功能：基础安装和环境配置

```bash
# 基础安装
./install.sh

# 指定安装目录
./install.sh --prefix=/opt/stock-tsdb

# 开发模式安装
./install.sh --dev
```

#### stock-tsdb.sh

功能：服务管理和控制

```bash
# 启动服务
./stock-tsdb.sh start

# 停止服务
./stock-tsdb.sh stop

# 重启服务
./stock-tsdb.sh restart

# 查看状态
./stock-tsdb.sh status

# 查看日志
./stock-tsdb.sh logs

# 服务信息
./stock-tsdb.sh info
```

### 监控脚本使用

#### monitor_production.sh

功能：实时监控、告警和健康检查

```bash
# 执行完整健康检查
./monitor_production.sh check

# 启动实时监控模式
./monitor_production.sh realtime

# 获取性能指标
./monitor_production.sh metrics

# 执行告警检查
./monitor_production.sh alert

# 运行性能基准测试
./monitor_production.sh performance

# 生成监控报告
./monitor_production.sh report
```

高级用法：
```bash
# 指定主机和端口
./monitor_production.sh -h 192.168.1.100 -p 6379 realtime

# 配置告警
./monitor_production.sh -w https://hooks.slack.com/services/xxx -e admin@example.com realtime

# 设置自定义阈值
export ALERT_THRESHOLD_CPU=90
export ALERT_THRESHOLD_MEM=95
./monitor_production.sh realtime
```

监控指标：
- CPU 使用率
- 内存使用率
- 磁盘使用率
- 写入 QPS
- 查询延迟 P99
- 错误率
- 活跃连接数

### 备份脚本使用

#### backup_production.sh

功能：数据备份、恢复和管理

```bash
# 执行全量备份
./backup_production.sh full

# 执行增量备份
./backup_production.sh incremental

# 列出所有备份
./backup_production.sh list all

# 列出全量备份
./backup_production.sh list full

# 验证备份文件
./backup_production.sh verify /var/backup/stock-tsdb/full/backup-file.tar.gz

# 恢复备份
./backup_production.sh restore /var/backup/stock-tsdb/full/backup-file.tar.gz

# 清理过期备份
./backup_production.sh cleanup
```

高级配置：
```bash
# 设置备份目录和保留时间
./backup_production.sh -d /backup/stock-tsdb -r 60 full

# 启用加密备份
export BACKUP_ENCRYPTION_KEY="your-secret-key"
./backup_production.sh full

# 配置远程备份
export BACKUP_REMOTE_HOST="backup.example.com"
export BACKUP_REMOTE_PATH="/backups/stock-tsdb"
export BACKUP_REMOTE_USER="backup"
./backup_production.sh full

# 配置通知
export BACKUP_NOTIFICATION_EMAIL="admin@example.com"
export BACKUP_NOTIFICATION_WEBHOOK="https://hooks.slack.com/services/xxx"
./backup_production.sh full
```

备份策略建议：
- 全量备份：每天凌晨执行
- 增量备份：每4小时执行
- 备份保留：30天（可配置）
- 远程备份：建议配置异地备份

### 维护脚本使用

#### maintain_production.sh

功能：系统维护、性能优化和故障排除

```bash
# 执行健康检查
./maintain_production.sh health-check

# 清理过期日志
./maintain_production.sh cleanup-logs

# 压缩大日志文件
./maintain_production.sh compress-logs

# 检查系统资源
./maintain_production.sh check-resources

# 检查磁盘空间
./maintain_production.sh check-disk

# 清理临时文件
./maintain_production.sh cleanup-temp

# 性能优化建议
./maintain_production.sh performance

# 收集系统信息
./maintain_production.sh system-info

# 故障排除模式
./maintain_production.sh troubleshoot

# 执行完整维护
./maintain_production.sh full-maintenance
```

维护配置：
```bash
# 设置日志保留时间和大小限制
./maintain_production.sh -r 60 -s 200 cleanup-logs

# 设置磁盘清理阈值
./maintain_production.sh -t 90 check-disk

# 自定义目录路径
./maintain_production.sh -d /data/stock-tsdb -l /logs/stock-tsdb full-maintenance
```

## 环境变量配置

### 通用环境变量
```bash
# 基础路径配置
export STOCK_TSDB_HOME=/opt/stock-tsdb
export DATA_DIR=/var/lib/stock-tsdb
export CONFIG_DIR=/etc/stock-tsdb
export LOG_DIR=/var/log/stock-tsdb
export BACKUP_DIR=/var/backup/stock-tsdb

# 服务配置
export STOCK_TSDB_HOST=localhost
export STOCK_TSDB_PORT=6379
export STOCK_TSDB_MONITOR_PORT=8080
export STOCK_TSDB_CLUSTER_PORT=5555
```

### 监控相关环境变量
```bash
# 告警配置
export ALERT_WEBHOOK="https://hooks.slack.com/services/xxx"
export ALERT_EMAIL="admin@example.com"

# 告警阈值
export ALERT_THRESHOLD_CPU=80
export ALERT_THRESHOLD_MEM=85
export ALERT_THRESHOLD_DISK=90
export ALERT_THRESHOLD_WRITE_QPS=1000
export ALERT_THRESHOLD_QUERY_LATENCY=100
export ALERT_THRESHOLD_ERROR_RATE=0.01
```

### 备份相关环境变量
```bash
# 备份配置
export BACKUP_RETENTION_DAYS=30
export BACKUP_COMPRESSION_LEVEL=6
export BACKUP_ENCRYPTION_KEY="your-secret-key"

# 远程备份
export BACKUP_REMOTE_HOST="backup.example.com"
export BACKUP_REMOTE_PATH="/backups/stock-tsdb"
export BACKUP_REMOTE_USER="backup"

# 通知配置
export BACKUP_NOTIFICATION_EMAIL="admin@example.com"
export BACKUP_NOTIFICATION_WEBHOOK="https://hooks.slack.com/services/xxx"
```

## 自动化配置

### Crontab 配置示例
```bash
# Stock-TSDB 定时任务
# 每分钟健康检查
* * * * * /opt/stock-tsdb/monitor_production.sh check >/dev/null 2>&1

# 每天凌晨2点全量备份
0 2 * * * /opt/stock-tsdb/backup_production.sh full >/dev/null 2>&1

# 每天凌晨4点增量备份
0 4 * * * /opt/stock-tsdb/backup_production.sh incremental >/dev/null 2>&1

# 每天凌晨6点清理过期备份
0 6 * * * /opt/stock-tsdb/backup_production.sh cleanup >/dev/null 2>&1

# 每天凌晨3点执行完整维护
0 3 * * * /opt/stock-tsdb/maintain_production.sh full-maintenance >/dev/null 2>&1

# 每周日凌晨1点清理过期日志
0 1 * * 0 /opt/stock-tsdb/maintain_production.sh cleanup-logs >/dev/null 2>&1

# 每周三凌晨1点压缩大日志文件
0 1 * * 3 /opt/stock-tsdb/maintain_production.sh compress-logs >/dev/null 2>&1
```

### Systemd 定时器配置
创建 `/etc/systemd/system/stock-tsdb-backup.service`：
```ini
[Unit]
Description=Stock-TSDB Backup Service
After=network.target

[Service]
Type=oneshot
User=stock-tsdb
Group=stock-tsdb
ExecStart=/opt/stock-tsdb/backup_production.sh full
StandardOutput=journal
StandardError=journal
```

创建 `/etc/systemd/system/stock-tsdb-backup.timer`：
```ini
[Unit]
Description=Stock-TSDB Backup Timer
Requires=stock-tsdb-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

启用定时器：
```bash
systemctl enable stock-tsdb-backup.timer
systemctl start stock-tsdb-backup.timer
```

## 最佳实践

### 1. 部署最佳实践
- 在生产环境部署前，先在测试环境验证
- 使用版本控制管理配置文件
- 记录每次部署的变更内容
- 保持部署脚本的可重复性

### 2. 监控最佳实践
- 配置合理的告警阈值，避免告警风暴
- 建立告警升级机制
- 定期审查监控指标的有效性
- 保存历史监控数据用于趋势分析

### 3. 备份最佳实践
- 定期测试备份恢复流程
- 实施3-2-1备份策略（3份副本，2种介质，1份异地）
- 加密敏感数据备份
- 监控备份任务执行情况

### 4. 维护最佳实践
- 在低峰期执行维护操作
- 维护前创建系统快照或备份
- 记录维护操作日志
- 建立维护窗口和通知机制

## 故障排除

### 常见问题

1. **服务无法启动**
   ```bash
   # 检查服务状态
   systemctl status stock-tsdb
   
   # 查看详细日志
   journalctl -u stock-tsdb -f
   
   # 检查配置文件
   stock-tsdb-server --check-config /etc/stock-tsdb/stock-tsdb.conf
   ```

2. **备份失败**
   ```bash
   # 检查磁盘空间
   df -h /var/backup
   
   # 验证备份文件
   ./backup_production.sh verify /path/to/backup.tar.gz
   
   # 查看备份日志
   tail -f /var/backup/stock-tsdb/backup.log
   ```

3. **监控告警**
   ```bash
   # 手动执行健康检查
   ./monitor_production.sh check
   
   # 查看监控指标
   ./monitor_production.sh metrics
   
   # 进入故障排除模式
   ./maintain_production.sh troubleshoot
   ```

### 故障排除工具
```bash
# 系统信息收集
./maintain_production.sh system-info

# 性能分析
./monitor_production.sh performance

# 详细诊断
./maintain_production.sh troubleshoot
```

## 安全考虑

### 1. 权限管理
- 脚本文件权限设置为 755
- 配置文件权限设置为 640
- 日志文件权限设置为 640
- 备份文件权限设置为 600（加密）

### 2. 敏感信息保护
- 使用环境变量存储敏感信息
- 加密备份文件
- 安全传输备份数据
- 定期轮换访问密钥

### 3. 审计日志
- 记录所有管理操作
- 保存命令执行历史
- 监控异常访问模式
- 定期审查安全日志

## 性能优化

### 1. 监控性能优化
- 调整监控频率避免资源消耗
- 使用批量操作减少系统调用
- 缓存频繁查询的数据
- 优化日志轮转策略

### 2. 备份性能优化
- 使用增量备份减少数据传输
- 并行压缩大文件
- 优化网络传输参数
- 选择合适的备份时间窗口

### 3. 维护性能优化
- 分批处理大文件操作
- 使用高效的数据结构
- 优化磁盘 I/O 操作
- 合理配置系统参数

## 更新和升级

### 脚本更新
```bash
# 备份当前脚本
./backup_production.sh backup

# 下载新版本脚本
curl -O https://example.com/stock-tsdb-scripts.tar.gz

# 验证新版本
./production_deploy.sh check

# 部署新版本
./production_deploy.sh upgrade
```

### 配置更新
```bash
# 备份当前配置
cp /etc/stock-tsdb/stock-tsdb.conf /etc/stock-tsdb/stock-tsdb.conf.backup

# 应用新配置
systemctl reload stock-tsdb

# 验证配置生效
./monitor_production.sh check
```

## 支持和文档

### 获取帮助
```bash
# 查看脚本帮助
./script_name.sh help

# 查看详细文档
cat PRODUCTION_SCRIPTS_GUIDE.md

# 查看版本信息
./script_name.sh --version
```

### 文档资源
- [Stock-TSDB 完整指南](V3_STORAGE_ENGINE_COMPLETE_GUIDE.md)
- [生产环境部署文档](CONSUL_PRODUCTION_DEPLOYMENT.md)
- [系统配置文档](conf/stock-tsdb.conf)
- [故障排除指南](README.md)

### 社区支持
- GitHub Issues: 报告问题和功能请求
- 文档 Wiki: 查找使用技巧和最佳实践
- 社区论坛: 与其他用户交流经验

## 总结

Stock-TSDB 生产环境脚本提供了完整的运维解决方案，涵盖部署、监控、备份和维护等各个方面。通过合理使用这些脚本，可以确保生产环境的稳定运行，提高运维效率，降低故障风险。

建议根据实际业务需求和环境特点，适当调整脚本参数和配置，建立适合自身环境的运维流程。同时，定期审查和更新运维策略，确保系统的持续稳定运行。