#!/bin/bash

# Stock-TSDB Ubuntu/Debian 安装脚本
# 专门为Ubuntu和Debian系统优化的安装脚本

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 检测发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        CODENAME=$VERSION_CODENAME
        VERSION_ID=$VERSION_ID
        log_info "检测到发行版: $DISTRO $VERSION ($CODENAME)"
    else
        log_error "无法检测发行版"
        exit 1
    fi
}

# 检查系统架构
check_architecture() {
    ARCH=$(dpkg --print-architecture)
    log_info "系统架构: $ARCH"

    case $ARCH in
        amd64|x86_64)
            log_info "支持的架构: $ARCH"
            ;;
        arm64|aarch64)
            log_info "支持的架构: $ARCH"
            ;;
        *)
            log_error "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
}

# 更新系统包
update_system() {
    log_info "更新系统包..."

    # 更新包列表
    sudo apt-get update

    # 升级已安装的包
    sudo apt-get upgrade -y

    log_info "系统包更新完成"
}

# 安装系统依赖
install_system_dependencies() {
    log_info "安装系统依赖..."

    # 根据发行版安装不同的依赖
    case $DISTRO in
        ubuntu)
            # Ubuntu特定依赖
            sudo apt-get install -y \
                software-properties-common \
                apt-transport-https \
                ca-certificates \
                gnupg \
                lsb-release
            ;;
        debian)
            # Debian特定依赖
            sudo apt-get install -y \
                apt-transport-https \
                ca-certificates \
                gnupg \
                lsb-release
            ;;
    esac

    # 安装基础依赖
    sudo apt-get install -y \
        build-essential \
        git \
        wget \
        curl \
        unzip \
        htop \
        tmux \
        vim \
        nano \
        supervisor \
        systemd \
        logrotate \
        cron

    log_info "系统依赖安装完成"
}

# 安装LuaJIT
install_luajit() {
    log_info "安装LuaJIT..."

    # 检查是否已安装
    if command -v luajit &> /dev/null; then
        LUAV=$(luajit -v)
        log_info "LuaJIT 已安装: $LUAV"
        return
    fi

    # 根据发行版安装LuaJIT
    case $DISTRO in
        ubuntu)
            # Ubuntu 20.04+ 使用官方仓库
            if [ "$VERSION_ID" -ge "2004" ]; then
                sudo apt-get install -y luajit luajit-5.1-dev
            else
                # 旧版本使用PPA
                sudo add-apt-repository -y ppa:openresty/luajit2
                sudo apt-get update
                sudo apt-get install -y luajit luajit-5.1-dev
            fi
            ;;
        debian)
            # Debian 11+ 使用官方仓库
            if [ "$VERSION_ID" -ge "11" ]; then
                sudo apt-get install -y luajit luajit-5.1-dev
            else
                # 旧版本从源码编译
                compile_luajit
            fi
            ;;
    esac

    # 验证安装
    if command -v luajit &> /dev/null; then
        LUAV=$(luajit -v)
        log_info "LuaJIT 安装成功: $LUAV"
    else
        log_error "LuaJIT 安装失败"
        exit 1
    fi
}

# 从源码编译LuaJIT
compile_luajit() {
    log_info "从源码编译LuaJIT..."

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # 下载LuaJIT源码
    cd "$TEMP_DIR"
    wget http://luajit.org/download/LuaJIT-2.1.0-beta3.tar.gz
    tar xzf LuaJIT-2.1.0-beta3.tar.gz
    cd LuaJIT-2.1.0-beta3

    # 编译和安装
    make && sudo make install

    # 创建符号链接
    sudo ln -sf /usr/local/bin/luajit /usr/bin/luajit

    # 更新动态链接库缓存
    sudo ldconfig

    cd - > /dev/null

    log_info "LuaJIT 编译安装完成"
}

# 安装LuaRocks
install_luarocks() {
    log_info "安装LuaRocks..."

    # 检查是否已安装
    if command -v luarocks &> /dev/null; then
        LRVER=$(luarocks --version | head -n1)
        log_info "LuaRocks 已安装: $LRVER"
        return
    fi

    # 根据发行版安装LuaRocks
    case $DISTRO in
        ubuntu)
            # Ubuntu 20.04+ 使用官方仓库
            if [ "$VERSION_ID" -ge "2004" ]; then
                sudo apt-get install -y luarocks
            else
                # 旧版本从源码编译
                compile_luarocks
            fi
            ;;
        debian)
            # Debian 11+ 使用官方仓库
            if [ "$VERSION_ID" -ge "11" ]; then
                sudo apt-get install -y luarocks
            else
                # 旧版本从源码编译
                compile_luarocks
            fi
            ;;
    esac

    # 验证安装
    if command -v luarocks &> /dev/null; then
        LRVER=$(luarocks --version | head -n1)
        log_info "LuaRocks 安装成功: $LRVER"
    else
        log_error "LuaRocks 安装失败"
        exit 1
    fi
}

# 从源码编译LuaRocks
compile_luarocks() {
    log_info "从源码编译LuaRocks..."

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # 下载LuaRocks源码
    cd "$TEMP_DIR"
    wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz
    tar xzf luarocks-3.9.2.tar.gz
    cd luarocks-3.9.2

    # 配置和编译
    ./configure --with-lua=/usr/local --with-lua-include=/usr/local/include/luajit-2.1
    make && sudo make install

    cd - > /dev/null

    log_info "LuaRocks 编译安装完成"
}

# 安装Lua依赖
install_lua_dependencies() {
    log_info "安装Lua依赖包..."

    # 安装lua-cjson
    if ! luarocks list | grep -q "lua-cjson"; then
        log_info "安装 lua-cjson..."
        sudo luarocks install lua-cjson || {
            log_error "lua-cjson 安装失败"
            exit 1
        }
    else
        log_info "lua-cjson 已安装"
    fi

    # 安装luasocket
    if ! luarocks list | grep -q "luasocket"; then
        log_info "安装 luasocket..."
        sudo luarocks install luasocket || {
            log_error "luasocket 安装失败"
            exit 1
        }
    else
        log_info "luasocket 已安装"
    fi

    # 安装lua-llthreads2
    if ! luarocks list | grep -q "llthreads2"; then
        log_info "安装 lua-llthreads2..."
        sudo luarocks install llthreads2 || {
            log_error "lua-llthreads2 安装失败"
            exit 1
        }
    else
        log_info "lua-llthreads2 已安装"
    fi

    # 安装lzmq (ZeroMQ Lua 绑定)
    if ! luarocks list | grep -q "lzmq"; then
        log_info "安装 lzmq..."
        # 先安装ZeroMQ开发库
        sudo apt-get install -y libzmq3-dev
        sudo luarocks install lzmq || {
            log_error "lzmq 安装失败"
            exit 1
        }
    else
        log_info "lzmq 已安装"
    fi

    log_info "Lua依赖包安装完成"
}

# 安装RocksDB
install_rocksdb() {
    log_info "安装RocksDB..."

    # 检查是否已安装
    if pkg-config --exists rocksdb; then
        RBVER=$(pkg-config --modversion rocksdb)
        log_info "RocksDB 已安装: $RBVER"
        return
    fi

    # 根据发行版安装RocksDB
    case $DISTRO in
        ubuntu)
            # Ubuntu 20.04+ 使用官方仓库
            if [ "$VERSION_ID" -ge "2004" ]; then
                sudo apt-get install -y librocksdb-dev
            else
                # 旧版本从源码编译
                compile_rocksdb
            fi
            ;;
        debian)
            # Debian 11+ 使用官方仓库
            if [ "$VERSION_ID" -ge "11" ]; then
                sudo apt-get install -y librocksdb-dev
            else
                # 旧版本从源码编译
                compile_rocksdb
            fi
            ;;
    esac

    # 验证安装
    if pkg-config --exists rocksdb; then
        RBVER=$(pkg-config --modversion rocksdb)
        log_info "RocksDB 安装成功: $RBVER"
    else
        log_error "RocksDB 安装失败"
        exit 1
    fi
}

# 从源码编译RocksDB
compile_rocksdb() {
    log_info "从源码编译RocksDB..."

    # 安装编译依赖
    sudo apt-get install -y \
        g++ \
        cmake \
        libgflags-dev \
        libsnappy-dev \
        libzstd-dev \
        liblz4-dev \
        libbz2-dev \
        libjemalloc-dev

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # 下载RocksDB源码
    cd "$TEMP_DIR"
    git clone https://github.com/facebook/rocksdb.git
    cd rocksdb
    git checkout v8.3.2

    # 编译和安装
    mkdir build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_GFLAGS=OFF -DWITH_TESTS=OFF
    make -j$(nproc)
    sudo make install

    # 更新动态链接库缓存
    sudo ldconfig

    cd - > /dev/null

    log_info "RocksDB 编译安装完成"
}

# 安装Redis
install_redis() {
    log_info "安装Redis..."

    # 检查是否已安装
    if command -v redis-server &> /dev/null; then
        RVER=$(redis-server --version | cut -d' ' -f3 | cut -d'=' -f2)
        log_info "Redis 已安装: $RVER"
        return
    fi

    # 安装Redis
    sudo apt-get install -y redis-server

    # 配置Redis
    sudo sed -i 's/supervised no/supervised systemd/' /etc/redis/redis.conf
    sudo mkdir -p /var/run/redis
    sudo chown redis:redis /var/run/redis

    # 启动Redis服务
    sudo systemctl enable redis-server
    sudo systemctl start redis-server

    # 验证安装
    if command -v redis-server &> /dev/null; then
        RVER=$(redis-server --version | cut -d' ' -f3 | cut -d'=' -f2)
        log_info "Redis 安装成功: $RVER"
    else
        log_error "Redis 安装失败"
        exit 1
    fi
}

# 配置系统优化
configure_system_optimization() {
    log_info "配置系统优化..."

    # 配置文件描述符限制
    sudo tee -a /etc/security/limits.conf > /dev/null << EOF
# Stock-TSDB 优化
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

    # 配置内核参数
    sudo tee -a /etc/sysctl.conf > /dev/null << EOF
# Stock-TSDB 优化
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 5000
vm.swappiness = 1
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

    # 应用内核参数
    sudo sysctl -p

    log_info "系统优化配置完成"
}

# 创建系统用户
create_user() {
    log_info "创建系统用户..."

    # 检查用户是否存在
    if ! id "stock-tsdb" &>/dev/null; then
        sudo useradd -r -s /bin/false -d /var/lib/stock-tsdb -m stock-tsdb
        log_info "用户 stock-tsdb 创建完成"
    else
        log_info "用户 stock-tsdb 已存在"
    fi
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."

    # 创建应用目录
    sudo mkdir -p /opt/stock-tsdb/{bin,lib,etc,logs,data}
    sudo mkdir -p /var/log/stock-tsdb
    sudo mkdir -p /var/lib/stock-tsdb

    # 设置权限
    sudo chown -R stock-tsdb:stock-tsdb /opt/stock-tsdb
    sudo chown -R stock-tsdb:stock-tsdb /var/log/stock-tsdb
    sudo chown -R stock-tsdb:stock-tsdb /var/lib/stock-tsdb

    log_info "目录结构创建完成"
}

# 构建项目
build_project() {
    log_info "构建 Stock-TSDB 项目..."

    # 运行 make 命令
    make || {
        log_error "项目构建失败"
        exit 1
    }

    log_info "项目构建完成"
}

# 安装文件
install_files() {
    log_info "安装文件..."

    # 安装二进制文件
    sudo cp bin/stock-tsdb-server /opt/stock-tsdb/bin/
    sudo chmod +x /opt/stock-tsdb/bin/stock-tsdb-server

    # 安装库文件
    sudo cp lib/*.so /opt/stock-tsdb/lib/

    # 安装配置文件
    sudo cp -r conf/* /opt/stock-tsdb/etc/

    # 安装Lua脚本
    sudo cp -r lua /opt/stock-tsdb/

    # 创建符号链接
    sudo ln -sf /opt/stock-tsdb/bin/stock-tsdb-server /usr/local/bin/stock-tsdb-server

    log_info "文件安装完成"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."

    # 创建服务文件
    sudo tee /etc/systemd/system/stock-tsdb.service > /dev/null << EOF
[Unit]
Description=Stock Time Series Database
After=network.target redis.service

[Service]
Type=simple
User=stock-tsdb
Group=stock-tsdb
ExecStart=/opt/stock-tsdb/bin/stock-tsdb-server -c /opt/stock-tsdb/etc/stock-tsdb.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=stock-tsdb

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/stock-tsdb /var/log/stock-tsdb /opt/stock-tsdb

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd
    sudo systemctl daemon-reload

    log_info "systemd服务创建完成"
}

# 配置logrotate
configure_logrotate() {
    log_info "配置logrotate..."

    # 创建logrotate配置
    sudo tee /etc/logrotate.d/stock-tsdb > /dev/null << EOF
/var/log/stock-tsdb/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 stock-tsdb stock-tsdb
    postrotate
        systemctl reload stock-tsdb >/dev/null 2>&1 || true
    endscript
}
EOF

    log_info "logrotate配置完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."

    # 检查UFW是否可用
    if command -v ufw &> /dev/null; then
        # 检查UFW状态
        if ufw status | grep -q "active"; then
            log_info "配置UFW规则..."
            sudo ufw allow 6379/tcp comment "Stock-TSDB Redis"
            sudo ufw allow 5555/tcp comment "Stock-TSDB API"
            sudo ufw allow 8080/tcp comment "Stock-TSDB Web"
        else
            log_warn "UFW未启用，跳过防火墙配置"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        # 检查firewalld状态
        if systemctl is-active --quiet firewalld; then
            log_info "配置firewalld规则..."
            sudo firewall-cmd --permanent --add-port=6379/tcp
            sudo firewall-cmd --permanent --add-port=5555/tcp
            sudo firewall-cmd --permanent --add-port=8080/tcp
            sudo firewall-cmd --reload
        else
            log_warn "firewalld未启用，跳过防火墙配置"
        fi
    else
        log_warn "未找到支持的防火墙工具，跳过防火墙配置"
    fi

    log_info "防火墙配置完成"
}

# 创建启动脚本
create_startup_script() {
    log_info "创建启动脚本..."

    # 创建启动脚本
    sudo tee /opt/stock-tsdb/bin/start-stock-tsdb.sh > /dev/null << 'EOF'
#!/bin/bash

# Stock-TSDB 启动脚本

# 设置环境变量
export PATH=/opt/stock-tsdb/bin:$PATH
export LD_LIBRARY_PATH=/opt/stock-tsdb/lib:$LD_LIBRARY_PATH

# 检查配置文件
if [ ! -f /opt/stock-tsdb/etc/stock-tsdb.conf ]; then
    echo "错误: 配置文件不存在 /opt/stock-tsdb/etc/stock-tsdb.conf"
    exit 1
fi

# 启动服务
exec /opt/stock-tsdb/bin/stock-tsdb-server -c /opt/stock-tsdb/etc/stock-tsdb.conf "$@"
EOF

    # 创建停止脚本
    sudo tee /opt/stock-tsdb/bin/stop-stock-tsdb.sh > /dev/null << 'EOF'
#!/bin/bash

# Stock-TSDB 停止脚本

# 查找进程ID
PID=$(pgrep -f "stock-tsdb-server")

if [ -z "$PID" ]; then
    echo "Stock-TSDB 服务未运行"
    exit 0
fi

# 停止服务
echo "停止 Stock-TSDB 服务 (PID: $PID)..."
kill -TERM $PID

# 等待进程结束
for i in {1..10}; do
    if ! kill -0 $PID 2>/dev/null; then
        echo "Stock-TSDB 服务已停止"
        exit 0
    fi
    sleep 1
done

# 强制杀死进程
echo "强制停止 Stock-TSDB 服务..."
kill -KILL $PID 2>/dev/null || true
echo "Stock-TSDB 服务已停止"
EOF

    # 设置执行权限
    sudo chmod +x /opt/stock-tsdb/bin/start-stock-tsdb.sh
    sudo chmod +x /opt/stock-tsdb/bin/stop-stock-tsdb.sh

    log_info "启动脚本创建完成"
}

# 显示安装后信息
show_post_install_info() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB Ubuntu/Debian 安装完成!"
    log_info "==========================================="
    echo

    log_info "服务管理:"
    log_info "1. 启动服务: sudo systemctl start stock-tsdb"
    log_info "2. 设置开机自启: sudo systemctl enable stock-tsdb"
    log_info "3. 查看状态: sudo systemctl status stock-tsdb"
    log_info "4. 停止服务: sudo systemctl stop stock-tsdb"
    log_info "5. 重启服务: sudo systemctl restart stock-tsdb"

    echo
    log_info "配置文件位置: /opt/stock-tsdb/etc/stock-tsdb.conf"
    log_info "日志文件位置: /var/log/stock-tsdb/"
    log_info "数据文件位置: /var/lib/stock-tsdb/"
    log_info "安装目录: /opt/stock-tsdb/"

    echo
    log_info "手动启动/停止:"
    log_info "1. 启动: /opt/stock-tsdb/bin/start-stock-tsdb.sh"
    log_info "2. 停止: /opt/stock-tsdb/bin/stop-stock-tsdb.sh"

    echo
    log_info "测试安装:"
    log_info "stock-tsdb-server --help"

    echo
    log_info "配置文件编辑:"
    log_info "sudo nano /opt/stock-tsdb/etc/stock-tsdb.conf"

    echo
    log_info "查看日志:"
    log_info "sudo journalctl -u stock-tsdb -f"
    log_info "sudo tail -f /var/log/stock-tsdb/stock-tsdb.log"

    echo
    log_info "更多信息请参考文档:"
    log_info "https://github.com/stock-tsdb/stock-tsdb/wiki"
}

# 主函数
main() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB Ubuntu/Debian 安装脚本"
    log_info "==========================================="
    echo

    # 检查是否以 root 权限运行
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 用户运行此脚本"
        exit 1
    fi

    # 检测发行版
    detect_distro

    # 检查系统架构
    check_architecture

    # 更新系统
    update_system

    # 安装系统依赖
    install_system_dependencies

    # 安装LuaJIT
    install_luajit

    # 安装LuaRocks
    install_luarocks

    # 安装Lua依赖
    install_lua_dependencies

    # 安装RocksDB
    install_rocksdb

    # 安装Redis
    install_redis

    # 配置系统优化
    configure_system_optimization

    # 创建系统用户
    create_user

    # 创建目录结构
    create_directories

    # 构建项目
    build_project

    # 安装文件
    install_files

    # 创建systemd服务
    create_systemd_service

    # 配置logrotate
    configure_logrotate

    # 配置防火墙
    configure_firewall

    # 创建启动脚本
    create_startup_script

    # 显示安装后信息
    show_post_install_info

    log_info "安装脚本执行完成!"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB Ubuntu/Debian 安装脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --no-service   不创建系统服务"
    echo "  --no-redis     不安装Redis"
    echo "  --no-firewall  不配置防火墙"
    echo
    echo "示例:"
    echo "  $0             执行完整安装"
    echo "  $0 --no-service  安装但不创建系统服务"
}

# 解析命令行参数
NO_SERVICE=false
NO_REDIS=false
NO_FIREWALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-service)
            NO_SERVICE=true
            shift
            ;;
        --no-redis)
            NO_REDIS=true
            shift
            ;;
        --no-firewall)
            NO_FIREWALL=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 运行主函数
main