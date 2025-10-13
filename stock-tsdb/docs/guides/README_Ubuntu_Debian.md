# Stock-TSDB Ubuntu/Debian 打包与安装指南

本指南介绍如何在 Ubuntu 和 Debian 系统上打包和安装 Stock-TSDB 项目。

## 概述

我们提供了两个专门的脚本，用于在 Ubuntu 和 Debian 系统上进行打包和安装：

1. `package_ubuntu_debian.sh` - 打包脚本，支持多种包格式
2. `install_ubuntu_debian.sh` - 安装脚本，提供完整的系统安装

## 打包脚本使用方法

### 基本用法

```bash
# 创建 Debian 包
./package_ubuntu_debian.sh --deb

# 创建 AppImage 包
./package_ubuntu_debian.sh --appimage

# 创建 RPM 包
./package_ubuntu_debian.sh --rpm

# 创建 Docker 镜像
./package_ubuntu_debian.sh --docker

# 创建 Snap 包
./package_ubuntu_debian.sh --snap

# 创建所有格式的包
./package_ubuntu_debian.sh --all
```

### 高级选项

```bash
# 仅安装打包依赖
./package_ubuntu_debian.sh --install-deps

# 指定版本
./package_ubuntu_debian.sh --version 1.0.0

# 指定输出目录
./package_ubuntu_debian.sh --output-dir /tmp/packages

# 详细输出
./package_ubuntu_debian.sh --verbose

# 清理构建文件
./package_ubuntu_debian.sh --clean
```

### 使用 Makefile

```bash
# 打包 Ubuntu/Debian 系统
make package-ubuntu-debian

# 创建 Debian 包
make package-deb

# 创建 AppImage 包
make package-appimage

# 创建 RPM 包
make package-rpm

# 创建 Docker 镜像
make package-docker

# 创建 Snap 包
make package-snap

# 创建所有格式的包
make package-all

# 安装打包依赖
make install-packaging-deps
```

## 安装脚本使用方法

### 基本用法

```bash
# 基本安装
./install_ubuntu_debian.sh

# 指定安装目录
./install_ubuntu_debian.sh --prefix /opt/stock-tsdb

# 指定用户
./install_ubuntu_debian.sh --user stocktsdb

# 开发模式安装
./install_ubuntu_debian.sh --dev-mode

# 仅安装依赖
./install_ubuntu_debian.sh --deps-only

# 详细输出
./install_ubuntu_debian.sh --verbose
```

### 使用 Makefile

```bash
# 安装到 Ubuntu/Debian 系统
make install-ubuntu-debian
```

## 系统要求

### Ubuntu
- Ubuntu 18.04 LTS 或更高版本
- 至少 2GB 内存
- 至少 5GB 可用磁盘空间

### Debian
- Debian 10 或更高版本
- 至少 2GB 内存
- 至少 5GB 可用磁盘空间

### 依赖项
脚本会自动安装以下依赖项：
- 构建工具 (build-essential)
- LuaJIT
- LuaRocks
- RocksDB
- Redis
- 系统库 (zlib, ssl, crypto 等)

## 包格式说明

### Debian 包 (.deb)
- 适用于 Debian 和 Ubuntu 系统
- 使用 `dpkg -i package.deb` 安装
- 支持依赖管理

### AppImage 包
- 便携式应用程序格式
- 无需安装，直接运行
- 适用于大多数 Linux 发行版

### RPM 包
- 适用于 Red Hat、CentOS、Fedora 等系统
- 使用 `rpm -i package.rpm` 安装

### Docker 镜像
- 容器化部署
- 隔离环境
- 易于扩展和管理

### Snap 包
- 通用 Linux 包格式
- 自动更新
- 沙箱安全

## 安装后配置

### 服务管理

```bash
# 启动服务
sudo systemctl start stock-tsdb
sudo systemctl enable stock-tsdb

# 查看状态
sudo systemctl status stock-tsdb

# 查看日志
sudo journalctl -u stock-tsdb -f
```

### 配置文件

主配置文件位于: `/etc/stock-tsdb/stock-tsdb.conf`

### 日志轮转

日志轮转配置位于: `/etc/logrotate.d/stock-tsdb`

### 防火墙配置

如果启用了防火墙，需要开放以下端口：
- 6379: Redis 协议端口
- 5555: ZeroMQ 集群通信端口

```bash
# UFW (Ubuntu)
sudo ufw allow 6379
sudo ufw allow 5555

# firewalld (CentOS/RHEL)
sudo firewall-cmd --permanent --add-port=6379/tcp
sudo firewall-cmd --permanent --add-port=5555/tcp
sudo firewall-cmd --reload
```

## 故障排除

### 常见问题

1. **权限错误**
   ```bash
   sudo chown -R stocktsdb:stocktsdb /var/lib/stock-tsdb
   ```

2. **依赖安装失败**
   ```bash
   # 更新包列表
   sudo apt update
   
   # 修复损坏的依赖
   sudo apt -f install
   ```

3. **服务启动失败**
   ```bash
   # 检查配置文件
   sudo stock-tsdb -t /etc/stock-tsdb/stock-tsdb.conf
   
   # 查看详细错误
   sudo journalctl -u stock-tsdb -n 50
   ```

### 日志位置

- 应用日志: `/var/log/stock-tsdb/`
- 系统日志: `journalctl -u stock-tsdb`
- 安装日志: `/tmp/stock-tsdb-install.log`

## 卸载

### 使用包管理器

```bash
# Debian/Ubuntu
sudo dpkg -r stock-tsdb

# RPM
sudo rpm -e stock-tsdb

# Snap
sudo snap remove stock-tsdb
```

### 手动卸载

```bash
# 停止服务
sudo systemctl stop stock-tsdb
sudo systemctl disable stock-tsdb

# 删除文件
sudo rm -rf /etc/stock-tsdb
sudo rm -rf /var/lib/stock-tsdb
sudo rm -rf /var/log/stock-tsdb
sudo rm -rf /usr/local/bin/stock-tsdb*
sudo rm -f /etc/systemd/system/stock-tsdb.service
sudo rm -f /etc/logrotate.d/stock-tsdb

# 重新加载 systemd
sudo systemctl daemon-reload
```

## 开发者指南

### 本地开发环境

```bash
# 开发模式安装
./install_ubuntu_debian.sh --dev-mode --prefix $HOME/stock-tsdb-dev

# 设置环境变量
export PATH=$HOME/stock-tsdb-dev/bin:$PATH
export STOCK_TSDB_CONFIG=$HOME/stock-tsdb-dev/etc/stock-tsdb.conf
```

### 构建自定义包

```bash
# 修改版本
export VERSION="1.0.0-custom"

# 构建包
./package_ubuntu_debian.sh --version $VERSION --output-dir ./custom-packages
```

## 贡献

如果您发现问题或有改进建议，请提交 Issue 或 Pull Request。

## 许可证

本项目采用 MIT 许可证。详见 LICENSE 文件。