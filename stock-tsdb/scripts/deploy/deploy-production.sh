#!/bin/bash

# Stock-TSDB 生产环境部署脚本
# 支持 V3 存储引擎基础版本和集成版本部署
# 包含完整的部署、监控、备份和回滚功能

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 版本信息
SCRIPT_VERSION="1.0.0"
DEPLOY_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "deploy_${DEPLOY_TIMESTAMP}.log"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1" | tee -a "deploy_${DEPLOY_TIMESTAMP}.log"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "deploy_${DEPLOY_TIMESTAMP}.log"
}

log_debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG]${NC} $1" | tee -a "deploy_${DEPLOY_TIMESTAMP}.log"
}

log_success() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1" | tee -a "deploy_${DEPLOY_TIMESTAMP}.log"
}

# 全局变量
DEPLOY_MODE=""                    # 部署模式: basic, integrated
BACKUP_DIR="/opt/stock-tsdb/backups"
INSTALL_DIR="/opt/stock-tsdb"
CONFIG_DIR="/etc/stock-tsdb"
LOG_DIR="/var/log/stock-tsdb"
DATA_DIR="/var/lib/stock-tsdb"
SERVICE_USER="stock-tsdb"
CONSUL_SERVERS=""               # Consul服务器列表（集成模式）
CLUSTER_NODES=""                # 集群节点列表（集成模式）

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 生产环境部署脚本 v${SCRIPT_VERSION}

用法: $0 [选项] [命令]

命令:
    deploy          部署 Stock-TSDB
    upgrade         升级现有部署
    rollback        回滚到上一个版本
    backup          创建数据备份
    restore         恢复数据备份
    status          查看部署状态
    health          健康检查
    monitor         启动监控
    stop            停止服务
    start           启动服务
    restart         重启服务
    uninstall       卸载服务

选项:
    -m, --mode MODE         部署模式: basic(基础版), integrated(集成版) [默认: basic]
    -c, --consul-servers   Consul服务器地址(集成模式), 格式: host1:port1,host2:port2
    -n, --cluster-nodes    集群节点地址(集成模式), 格式: host1,host2,host3
    -d, --data-dir DIR     数据目录 [默认: /var/lib/stock-tsdb]
    -l, --log-dir DIR      日志目录 [默认: /var/log/stock-tsdb]
    -i, --install-dir DIR  安装目录 [默认: /opt/stock-tsdb]
    -u, --user USER        服务用户 [默认: stock-tsdb]
    -b, --backup-dir DIR   备份目录 [默认: /opt/stock-tsdb/backups]
    -f, --config-file FILE 自定义配置文件
    -v, --version VERSION  部署版本（用于升级）
    --force                强制操作，跳过确认
    --dry-run              模拟运行，不执行实际操作
    -h, --help             显示帮助信息

示例:
    # 基础版本部署
    $0 deploy -m basic

    # 集成版本部署（3节点集群）
    $0 deploy -m integrated -c consul1:8500,consul2:8500,consul3:8500 -n node1,node2,node3

    # 升级到新版本
    $0 upgrade -v v2.0.0

    # 创建备份
    $0 backup

    # 回滚到上一个版本
    $0 rollback

    # 健康检查
    $0 health

EOF
}

# 检查运行权限
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检查操作系统
check_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macOS"
        log_info "检测到操作系统: macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="Linux"
        log_info "检测到操作系统: Linux"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存
    if [[ "$OS" == "Linux" ]]; then
        TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
        AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
    else
        TOTAL_MEM=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
        AVAILABLE_MEM=$TOTAL_MEM
    fi
    
    log_info "总内存: ${TOTAL_MEM}GB, 可用内存: ${AVAILABLE_MEM}GB"
    
    if [[ $TOTAL_MEM -lt 4 ]]; then
        log_warn "内存不足4GB，可能影响性能"
    fi
    
    # 检查磁盘空间
    DISK_AVAIL=$(df -BG "$DATA_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//') || DISK_AVAIL=0
    log_info "磁盘可用空间: ${DISK_AVAIL}GB"
    
    if [[ $DISK_AVAIL -lt 10 ]]; then
        log_warn "磁盘空间不足10GB，可能影响数据存储"
    fi
}

# 检查端口占用
check_ports() {
    log_info "检查端口占用..."
    
    local ports=("6379" "5555" "8080" "8500")
    local occupied_ports=()
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            occupied_ports+=("$port")
        fi
    done
    
    if [[ ${#occupied_ports[@]} -gt 0 ]]; then
        log_warn "以下端口已被占用: ${occupied_ports[*]}"
        if [[ "$FORCE" != "true" ]]; then
            read -p "是否继续部署? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "用户取消部署"
                exit 1
            fi
        fi
    fi
}

# 创建系统用户
create_service_user() {
    log_info "创建服务用户: $SERVICE_USER"
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
        log_success "用户 $SERVICE_USER 创建成功"
    else
        log_info "用户 $SERVICE_USER 已存在"
    fi
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    # 创建主要目录
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$DATA_DIR" "$BACKUP_DIR"
    
    # 创建子目录
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/scripts"
    mkdir -p "$DATA_DIR/sh" "$DATA_DIR/sz" "$DATA_DIR/hk" "$DATA_DIR/us"
    mkdir -p "$LOG_DIR/archive"
    
    # 设置权限
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$LOG_DIR" "$DATA_DIR" "$BACKUP_DIR"
    chmod 755 "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$DATA_DIR"
    chmod 750 "$BACKUP_DIR"
    
    log_success "目录结构创建完成"
}

# 安装系统依赖
install_system_dependencies() {
    log_info "安装系统依赖..."
    
    if [[ "$OS" == "Linux" ]]; then
        # 检测发行版
        if [[ -f /etc/redhat-release ]]; then
            # RHEL/CentOS
            yum update -y
            yum install -y gcc gcc-c++ make cmake git wget curl
            yum install -y snappy snappy-devel zlib zlib-devel bzip2 bzip2-devel
            yum install -y lz4 lz4-devel zstd zstd-devel gflags gflags-devel
            yum install -y zeromq zeromq-devel
        elif [[ -f /etc/debian_version ]]; then
            # Ubuntu/Debian
            apt-get update
            apt-get install -y build-essential cmake git wget curl
            apt-get install -y libsnappy-dev zlib1g-dev libbz2-dev
            apt-get install -y liblz4-dev libzstd-dev libgflags-dev
            apt-get install -y libzeromq3-dev
        else
            log_error "不支持的操作系统发行版"
            exit 1
        fi
    else
        # macOS
        if ! command -v brew &> /dev/null; then
            log_error "请先安装 Homebrew"
            exit 1
        fi
        
        brew install cmake wget curl snappy lz4 zstd gflags zeromq
    fi
    
    log_success "系统依赖安装完成"
}

# 安装 LuaJIT 和 LuaRocks
install_luajit_luarocks() {
    log_info "安装 LuaJIT 和 LuaRocks..."
    
    # 检查是否已安装
    if command -v luajit &> /dev/null && command -v luarocks &> /dev/null; then
        log_info "LuaJIT 和 LuaRocks 已安装"
        return
    fi
    
    # 安装 LuaJIT
    if ! command -v luajit &> /dev/null; then
        log_info "安装 LuaJIT..."
        cd /tmp
        wget -O luajit.tar.gz https://github.com/LuaJIT/LuaJIT/archive/v2.1.0-beta3.tar.gz
        tar xzf luajit.tar.gz
        cd LuaJIT-2.1.0-beta3
        make && make install
        ldconfig
        cd /
        rm -rf /tmp/LuaJIT-2.1.0-beta3 /tmp/luajit.tar.gz
    fi
    
    # 安装 LuaRocks
    if ! command -v luarocks &> /dev/null; then
        log_info "安装 LuaRocks..."
        cd /tmp
        wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz
        tar xzf luarocks-3.9.2.tar.gz
        cd luarocks-3.9.2
        ./configure --with-lua-include=/usr/local/include/luajit-2.1
        make && make install
        cd /
        rm -rf /tmp/luarocks-3.9.2 /tmp/luarocks-3.9.2.tar.gz
    fi
    
    log_success "LuaJIT 和 LuaRocks 安装完成"
}

# 安装 Lua 依赖
install_lua_dependencies() {
    log_info "安装 Lua 依赖包..."
    
    local deps=("lua-cjson" "luasocket" "lua-llthreads2" "lzmq")
    
    for dep in "${deps[@]}"; do
        if ! luarocks list | grep -q "$dep"; then
            log_info "安装 $dep..."
            luarocks install "$dep" || {
                log_error "$dep 安装失败"
                exit 1
            }
        else
            log_info "$dep 已安装"
        fi
    done
    
    log_success "Lua 依赖安装完成"
}

# 构建项目
build_project() {
    log_info "构建 Stock-TSDB 项目..."
    
    # 清理之前的构建
    make clean 2>/dev/null || true
    
    # 构建项目
    make || {
        log_error "项目构建失败"
        exit 1
    }
    
    log_success "项目构建完成"
}

# 安装二进制文件
install_binaries() {
    log_info "安装二进制文件..."
    
    # 复制二进制文件
    cp stock-tsdb-server "$INSTALL_DIR/bin/"
    cp stock-tsdb.sh "$INSTALL_DIR/scripts/"
    
    # 创建符号链接
    ln -sf "$INSTALL_DIR/bin/stock-tsdb-server" /usr/local/bin/stock-tsdb-server
    ln -sf "$INSTALL_DIR/scripts/stock-tsdb.sh" /usr/local/bin/stock-tsdb
    
    # 设置权限
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/bin/stock-tsdb-server"
    chmod 755 "$INSTALL_DIR/bin/stock-tsdb-server"
    chmod 755 "$INSTALL_DIR/scripts/stock-tsdb.sh"
    
    log_success "二进制文件安装完成"
}

# 配置系统服务
configure_system_service() {
    log_info "配置系统服务..."
    
    if [[ "$OS" == "Linux" ]]; then
        # 创建 systemd 服务文件
        cat > /etc/systemd/system/stock-tsdb.service << EOF
[Unit]
Description=Stock Time Series Database - V3 Storage Engine
Documentation=https://github.com/your-repo/stock-tsdb
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=$INSTALL_DIR/bin/stock-tsdb-server -c $CONFIG_DIR/stock-tsdb.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# 环境变量
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=LD_LIBRARY_PATH=/usr/local/lib

# 资源限制
LimitNOFILE=65536
LimitNPROC=32768
LimitCORE=infinity

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR $LOG_DIR

# 日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=stock-tsdb

[Install]
WantedBy=multi-user.target
EOF
        
        # 重新加载 systemd
        systemctl daemon-reload
        
        # 启用服务
        systemctl enable stock-tsdb
        
        log_success "系统服务配置完成"
    else
        # macOS - 创建 LaunchDaemon
        cat > /Library/LaunchDaemons/com.stocktsdb.server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.stocktsdb.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/bin/stock-tsdb-server</string>
        <string>-c</string>
        <string>$CONFIG_DIR/stock-tsdb.conf</string>
    </array>
    <key>UserName</key>
    <string>$SERVICE_USER</string>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stock-tsdb.stdout</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stock-tsdb.stderr</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
        
        # 设置权限
        chown root:wheel /Library/LaunchDaemons/com.stocktsdb.server.plist
        chmod 644 /Library/LaunchDaemons/com.stocktsdb.server.plist
        
        log_success "macOS LaunchDaemon 配置完成"
    fi
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    local config_file="$CONFIG_DIR/stock-tsdb.conf"
    
    # 基础配置
    cat > "$config_file" << EOF
# Stock-TSDB 生产环境配置文件
# 生成时间: $(date)
# 部署模式: $DEPLOY_MODE

[server]
# Redis接口端口
port = 6379
# 绑定地址 (生产环境建议绑定内网地址)
bind = 0.0.0.0
# 最大连接数
max_connections = 10000
# 使用事件驱动服务器
use_event_driver = true

[storage]
# 数据存储目录
data_dir = $DATA_DIR
# 日志目录
log_dir = $LOG_DIR
# 数据块大小(秒)
block_size = 30
# 压缩级别(1-22, 数字越大压缩率越高)
compression_level = 6
# 是否启用压缩
enable_compression = true
# 内存映射文件大小(MB)
mmap_size = 4096
# 写缓冲区大小(MB)
write_buffer_size = 128
# 最大写缓冲区数
max_write_buffer_number = 6

[rocksdb]
# RocksDB配置
write_buffer_size = 128MB
max_file_size = 256MB
target_file_size_base = 128MB
target_file_size_multiplier = 2
max_background_compactions = 16
max_background_flushes = 8
block_cache_size = 1024MB
enable_statistics = true
stats_dump_period_sec = 300

[cluster]
# ZeroMQ集群配置
node_id = 0
cluster_mode = single
master_host = 127.0.0.1
master_port = 5555
heartbeat_interval = 30
replication_timeout = 60
max_retry = 3
EOF

    # 集成模式配置
    if [[ "$DEPLOY_MODE" == "integrated" ]]; then
        cat >> "$config_file" << EOF

[cluster_consul]
# Consul集群配置
consul_servers = $CONSUL_SERVERS
cluster_nodes = $CLUSTER_NODES
service_name = stock-tsdb
health_check_interval = 10
leader_election_timeout = 30
EOF
    fi
    
    # 通用配置
    cat >> "$config_file" << EOF

[data_retention]
# 数据保留策略
hot_data_days = 7
warm_data_days = 30
cold_data_days = 365
auto_cleanup = true
cleanup_interval = 24

[performance]
# 性能优化参数
batch_size = 2000
query_cache_size = 50000
write_rate_limit = 0
query_concurrency = 16
enable_prefetch = true

[monitoring]
# 监控配置
enable_monitoring = true
monitor_port = 8080
monitor_retention = 168
write_qps_threshold = 100000
query_latency_threshold = 50
error_rate_threshold = 0.005

[logging]
# 日志配置
log_level = info
max_log_size = 500
log_retention_days = 30
enable_console_log = false
enable_file_log = true

[market]
# 市场配置
markets = sh,sz,hk,us

[market.sh]
name = 上海证券交易所
data_dir = $DATA_DIR/sh
compression = lz4

[market.sz]
name = 深圳证券交易所
data_dir = $DATA_DIR/sz
compression = lz4

[market.hk]
name = 香港交易所
data_dir = $DATA_DIR/hk
compression = zstd

[market.us]
name = 美国交易所
data_dir = $DATA_DIR/us
compression = zstd
EOF
    
    # 设置权限
    chown "$SERVICE_USER:$SERVICE_USER" "$config_file"
    chmod 644 "$config_file"
    
    log_success "配置文件生成完成: $config_file"
}

# 配置监控
configure_monitoring() {
    log_info "配置监控..."
    
    # 创建监控脚本
    cat > "$INSTALL_DIR/scripts/monitor.sh" << 'EOF'
#!/bin/bash
# Stock-TSDB 监控脚本

STOCK_TSDB_HOST="${STOCK_TSDB_HOST:-localhost}"
STOCK_TSDB_PORT="${STOCK_TSDB_PORT:-8080}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"

# 检查服务状态
check_service() {
    if ! curl -s "http://${STOCK_TSDB_HOST}:${STOCK_TSDB_PORT}/health" > /dev/null; then
        echo "ERROR: Stock-TSDB 服务不可达"
        return 1
    fi
    return 0
}

# 检查性能指标
check_performance() {
    local metrics=$(curl -s "http://${STOCK_TSDB_HOST}:${STOCK_TSDB_PORT}/metrics" 2>/dev/null)
    
    if [[ -n "$metrics" ]]; then
        local write_qps=$(echo "$metrics" | grep "write_qps" | awk '{print $2}')
        local query_latency=$(echo "$metrics" | grep "query_latency_p99" | awk '{print $2}')
        local error_rate=$(echo "$metrics" | grep "error_rate" | awk '{print $2}')
        
        echo "Write QPS: $write_qps"
        echo "Query Latency P99: ${query_latency}ms"
        echo "Error Rate: $error_rate"
        
        # 简单告警逻辑
        if [[ $(echo "$write_qps < 1000" | bc -l) -eq 1 ]]; then
            echo "WARN: Write QPS 过低"
        fi
        
        if [[ $(echo "$query_latency > 100" | bc -l) -eq 1 ]]; then
            echo "WARN: 查询延迟过高"
        fi
        
        if [[ $(echo "$error_rate > 0.01" | bc -l) -eq 1 ]]; then
            echo "WARN: 错误率过高"
        fi
    else
        echo "ERROR: 无法获取性能指标"
        return 1
    fi
}

# 主函数
main() {
    echo "=== Stock-TSDB 监控检查 ==="
    echo "时间: $(date)"
    echo "服务地址: ${STOCK_TSDB_HOST}:${STOCK_TSDB_PORT}"
    echo
    
    if check_service; then
        check_performance
    else
        exit 1
    fi
    
    echo
    echo "=== 监控检查完成 ==="
}

main "$@"
EOF
    
    chmod 755 "$INSTALL_DIR/scripts/monitor.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts/monitor.sh"
    
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "*/5 * * * * $INSTALL_DIR/scripts/monitor.sh >> $LOG_DIR/monitor.log 2>&1") | crontab -
    
    log_success "监控配置完成"
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 检查服务状态
    if [[ "$OS" == "Linux" ]]; then
        if systemctl is-active --quiet stock-tsdb; then
            log_success "Stock-TSDB 服务运行正常"
        else
            log_error "Stock-TSDB 服务未运行"
            return 1
        fi
    fi
    
    # 检查端口
    if netstat -tuln | grep -q ":6379 "; then
        log_success "Redis 接口端口正常 (6379)"
    else
        log_error "Redis 接口端口未监听"
        return 1
    fi
    
    # 检查监控端口
    if netstat -tuln | grep -q ":8080 "; then
        log_success "监控端口正常 (8080)"
    else
        log_warn "监控端口未监听"
    fi
    
    # 检查数据目录
    if [[ -d "$DATA_DIR" && -r "$DATA_DIR" && -w "$DATA_DIR" ]]; then
        log_success "数据目录正常: $DATA_DIR"
    else
        log_error "数据目录异常: $DATA_DIR"
        return 1
    fi
    
    # 检查日志目录
    if [[ -d "$LOG_DIR" && -r "$LOG_DIR" && -w "$LOG_DIR" ]]; then
        log_success "日志目录正常: $LOG_DIR"
    else
        log_error "日志目录异常: $LOG_DIR"
        return 1
    fi
    
    log_success "健康检查通过"
    return 0
}

# 创建备份
create_backup() {
    log_info "创建数据备份..."
    
    local backup_name="stock-tsdb-backup-${DEPLOY_TIMESTAMP}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    # 创建备份目录
    mkdir -p "$backup_path"
    
    # 停止服务
    log_info "停止服务以创建一致性备份..."
    stop_service
    
    # 备份数据
    if [[ -d "$DATA_DIR" ]]; then
        cp -r "$DATA_DIR" "$backup_path/"
        log_info "数据备份完成"
    fi
    
    # 备份配置
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -r "$CONFIG_DIR" "$backup_path/"
        log_info "配置备份完成"
    fi
    
    # 创建备份信息
    cat > "$backup_path/backup.info" << EOF
备份时间: $(date)
备份版本: $(cd "$INSTALL_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
部署模式: $DEPLOY_MODE
数据目录: $DATA_DIR
配置目录: $CONFIG_DIR
主机名: $(hostname)
EOF
    
    # 压缩备份
    cd "$BACKUP_DIR"
    tar -czf "$backup_name.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    # 设置权限
    chown "$SERVICE_USER:$SERVICE_USER" "$backup_name.tar.gz"
    chmod 640 "$backup_name.tar.gz"
    
    # 启动服务
    start_service
    
    log_success "备份创建完成: $backup_name.tar.gz"
}

# 主部署函数
deploy() {
    log_info "开始部署 Stock-TSDB..."
    log_info "部署模式: $DEPLOY_MODE"
    log_info "安装目录: $INSTALL_DIR"
    log_info "数据目录: $DATA_DIR"
    log_info "日志目录: $LOG_DIR"
    
    # 预检查
    check_system_resources
    check_ports
    
    # 创建用户和目录
    create_service_user
    create_directories
    
    # 安装依赖
    install_system_dependencies
    install_luajit_luarocks
    install_lua_dependencies
    
    # 构建和安装
    build_project
    install_binaries
    
    # 配置
    generate_config
    configure_system_service
    configure_monitoring
    
    # 启动服务
    start_service
    
    # 健康检查
    sleep 5
    if health_check; then
        log_success "Stock-TSDB 部署成功!"
        log_info "服务状态: systemctl status stock-tsdb"
        log_info "查看日志: journalctl -u stock-tsdb -f"
        log_info "监控地址: http://localhost:8080"
    else
        log_error "部署失败，请检查日志"
        exit 1
    fi
}

# 启动服务
start_service() {
    log_info "启动 Stock-TSDB 服务..."
    
    if [[ "$OS" == "Linux" ]]; then
        systemctl start stock-tsdb
        systemctl enable stock-tsdb
    else
        launchctl load /Library/LaunchDaemons/com.stocktsdb.server.plist
    fi
    
    # 等待服务启动
    sleep 3
    
    if systemctl is-active --quiet stock-tsdb 2>/dev/null || pgrep -f stock-tsdb-server > /dev/null; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# 停止服务
stop_service() {
    log_info "停止 Stock-TSDB 服务..."
    
    if [[ "$OS" == "Linux" ]]; then
        systemctl stop stock-tsdb 2>/dev/null || true
    else
        launchctl unload /Library/LaunchDaemons/com.stocktsdb.server.plist 2>/dev/null || true
    fi
    
    # 等待服务停止
    sleep 2
    
    # 确保进程已停止
    pkill -f stock-tsdb-server 2>/dev/null || true
    
    log_success "服务停止完成"
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                DEPLOY_MODE="$2"
                shift 2
                ;;
            -c|--consul-servers)
                CONSUL_SERVERS="$2"
                shift 2
                ;;
            -n|--cluster-nodes)
                CLUSTER_NODES="$2"
                shift 2
                ;;
            -d|--data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            -i|--install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -u|--user)
                SERVICE_USER="$2"
                shift 2
                ;;
            -b|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            deploy|upgrade|rollback|backup|restore|status|health|monitor|stop|start|restart|uninstall)
                COMMAND="$1"
                shift
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证部署模式
    if [[ -n "$DEPLOY_MODE" && "$DEPLOY_MODE" != "basic" && "$DEPLOY_MODE" != "integrated" ]]; then
        log_error "无效的部署模式: $DEPLOY_MODE (应为 basic 或 integrated)"
        exit 1
    fi
    
    # 集成模式验证
    if [[ "$DEPLOY_MODE" == "integrated" ]]; then
        if [[ -z "$CONSUL_SERVERS" ]]; then
            log_error "集成模式需要指定 Consul 服务器地址 (-c 参数)"
            exit 1
        fi
        if [[ -z "$CLUSTER_NODES" ]]; then
            log_error "集成模式需要指定集群节点地址 (-n 参数)"
            exit 1
        fi
    fi
}

# 主函数
main() {
    # 解析参数
    parse_arguments "$@"
    
    # 检查权限
    check_permissions
    
    # 检查操作系统
    check_os
    
    # 执行命令
    case "$COMMAND" in
        deploy)
            deploy
            ;;
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        health)
            health_check
            ;;
        backup)
            create_backup
            ;;
        *)
            log_error "未实现的命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 脚本入口
main "$@"