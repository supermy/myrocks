#!/bin/bash

# Stock-TSDB 生产环境安装脚本
# 支持 macOS 和 Linux 系统

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

# 检查必要工具
check_dependencies() {
    log_info "检查必要工具..."

    # 检查 LuaJIT
    if ! command -v luajit &> /dev/null; then
        log_error "未找到 luajit，请先安装 LuaJIT"
        if [[ "$OS" == "macOS" ]]; then
            log_info "在 macOS 上可以使用 Homebrew 安装: brew install luajit"
        else
            log_info "在 Ubuntu/Debian 上可以使用: sudo apt-get install luajit"
            log_info "在 CentOS/RHEL 上可以使用: sudo yum install luajit"
        fi
        exit 1
    else
        LUAV=$(luajit -v)
        log_info "LuaJIT 版本: $LUAV"
    fi

    # 检查 luarocks
    if ! command -v luarocks &> /dev/null; then
        log_error "未找到 luarocks，请先安装 LuaRocks"
        if [[ "$OS" == "macOS" ]]; then
            log_info "在 macOS 上可以使用 Homebrew 安装: brew install luarocks"
        else
            log_info "在 Ubuntu/Debian 上可以使用: sudo apt-get install luarocks"
            log_info "在 CentOS/RHEL 上可以使用: sudo yum install luarocks"
        fi
        exit 1
    else
        LRVER=$(luarocks --version | head -n1)
        log_info "LuaRocks 版本: $LRVER"
    fi

    # 检查 make
    if ! command -v make &> /dev/null; then
        log_error "未找到 make 工具"
        if [[ "$OS" == "macOS" ]]; then
            log_info "请安装 Xcode Command Line Tools: xcode-select --install"
        else
            log_info "在 Ubuntu/Debian 上可以使用: sudo apt-get install build-essential"
            log_info "在 CentOS/RHEL 上可以使用: sudo yum groupinstall 'Development Tools'"
        fi
        exit 1
    fi

    # 检查 git
    if ! command -v git &> /dev/null; then
        log_warn "未找到 git，某些功能可能受限"
    fi
}

# 安装 Lua 依赖
install_lua_dependencies() {
    log_info "安装 Lua 依赖包..."

    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    # 安装 lua-cjson
    if ! luarocks list | grep -q "lua-cjson"; then
        log_info "安装 lua-cjson..."
        luarocks install lua-cjson --local || {
            log_warn "lua-cjson 安装失败，尝试使用 sudo"
            sudo luarocks install lua-cjson || {
                log_error "lua-cjson 安装失败"
                exit 1
            }
        }
    else
        log_info "lua-cjson 已安装"
    fi

    # 安装 luasocket
    if ! luarocks list | grep -q "luasocket"; then
        log_info "安装 luasocket..."
        luarocks install luasocket --local || {
            log_warn "luasocket 安装失败，尝试使用 sudo"
            sudo luarocks install luasocket || {
                log_error "luasocket 安装失败"
                exit 1
            }
        }
    else
        log_info "luasocket 已安装"
    fi

    # 安装 lua-llthreads2
    if ! luarocks list | grep -q "llthreads2"; then
        log_info "安装 lua-llthreads2..."
        luarocks install lua-llthreads2 --local || {
            log_warn "lua-llthreads2 安装失败，尝试使用 sudo"
            sudo luarocks install lua-llthreads2 || {
                log_error "lua-llthreads2 安装失败"
                exit 1
            }
        }
    else
        log_info "lua-llthreads2 已安装"
    fi

    # 安装 lzmq (ZeroMQ Lua 绑定)
    if ! luarocks list | grep -q "lzmq"; then
        log_info "安装 lzmq..."
        luarocks install lzmq --local || {
            log_warn "lzmq 安装失败，尝试使用 sudo"
            sudo luarocks install lzmq || {
                log_error "lzmq 安装失败"
                exit 1
            }
        }
    else
        log_info "lzmq 已安装"
    fi
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

# 创建系统服务文件 (仅 Linux)
create_systemd_service() {
    if [[ "$OS" == "Linux" ]]; then
        log_info "创建 systemd 服务文件..."

        SERVICE_FILE="/etc/systemd/system/stock-tsdb.service"
        if [[ -f "$SERVICE_FILE" ]]; then
            log_warn "服务文件已存在: $SERVICE_FILE"
            read -p "是否覆盖? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "跳过服务文件创建"
                return
            fi
        fi

        # 创建服务文件
        sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Stock Time Series Database
After=network.target

[Service]
Type=simple
User=stock-tsdb
Group=stock-tsdb
ExecStart=/usr/local/bin/stock-tsdb-server -c /usr/local/etc/stock-tsdb.conf
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        log_info "systemd 服务文件创建完成: $SERVICE_FILE"
    fi
}

# 安装到系统
install_to_system() {
    log_info "安装 Stock-TSDB 到系统..."

    # 运行 make install
    sudo make install || {
        log_error "安装失败"
        exit 1
    }

    # 创建必要的目录和设置权限
    sudo mkdir -p /var/log/stock-tsdb /var/lib/stock-tsdb
    sudo chown -R $(whoami) /var/log/stock-tsdb /var/lib/stock-tsdb

    log_info "安装完成"
}

# 创建用户和组 (仅 Linux)
create_user_group() {
    if [[ "$OS" == "Linux" ]]; then
        log_info "创建 stock-tsdb 用户和组..."

        # 检查用户是否存在
        if ! id "stock-tsdb" &>/dev/null; then
            sudo useradd -r -s /bin/false -d /var/lib/stock-tsdb stock-tsdb
            log_info "用户 stock-tsdb 创建完成"
        else
            log_info "用户 stock-tsdb 已存在"
        fi
    fi
}

# 配置防火墙 (仅 Linux)
configure_firewall() {
    if [[ "$OS" == "Linux" ]]; then
        log_info "配置防火墙规则..."

        # 检查 firewalld 是否运行
        if systemctl is-active --quiet firewalld; then
            log_info "配置 firewalld 规则..."
            sudo firewall-cmd --permanent --add-port=6379/tcp 2>/dev/null || true
            sudo firewall-cmd --permanent --add-port=5555/tcp 2>/dev/null || true
            sudo firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
            sudo firewall-cmd --reload 2>/dev/null || true
        elif command -v ufw &> /dev/null && ufw status | grep -q "active"; then
            log_info "配置 UFW 规则..."
            sudo ufw allow 6379/tcp 2>/dev/null || true
            sudo ufw allow 5555/tcp 2>/dev/null || true
            sudo ufw allow 8080/tcp 2>/dev/null || true
        fi
    fi
}

# 显示安装后使用说明
show_post_install_info() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB 安装完成!"
    log_info "==========================================="
    echo

    if [[ "$OS" == "macOS" ]]; then
        log_info "使用说明:"
        log_info "1. 启动服务: stock-tsdb-server -c /usr/local/etc/stock-tsdb.conf"
        log_info "2. 后台运行: stock-tsdb-server -c /usr/local/etc/stock-tsdb.conf -d"
        log_info "3. 停止服务: killall stock-tsdb-server"
    else
        log_info "使用说明:"
        log_info "1. 启动服务: sudo systemctl start stock-tsdb"
        log_info "2. 设置开机自启: sudo systemctl enable stock-tsdb"
        log_info "3. 查看状态: sudo systemctl status stock-tsdb"
        log_info "4. 停止服务: sudo systemctl stop stock-tsdb"
    fi

    echo
    log_info "默认配置文件位置: /usr/local/etc/stock-tsdb.conf"
    log_info "日志文件位置: /var/log/stock-tsdb/"
    log_info "数据文件位置: /var/lib/stock-tsdb/"

    echo
    log_info "您可以编辑配置文件来调整设置:"
    log_info "sudo nano /usr/local/etc/stock-tsdb.conf"

    echo
    log_info "测试安装:"
    log_info "stock-tsdb-server --help"
}

# 主函数
main() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB 生产环境安装脚本"
    log_info "==========================================="
    echo

    # 检查是否以 root 权限运行
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 用户运行此脚本"
        exit 1
    fi

    # 检查操作系统
    check_os

    # 检查依赖
    check_dependencies

    # 安装 Lua 依赖
    install_lua_dependencies

    # 构建项目
    build_project

    # 创建用户组 (仅 Linux)
    create_user_group

    # 安装到系统
    install_to_system

    # 创建 systemd 服务 (仅 Linux)
    create_systemd_service

    # 配置防火墙 (仅 Linux)
    configure_firewall

    # 显示安装后信息
    show_post_install_info

    log_info "安装脚本执行完成!"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB 生产环境安装脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --no-service   不创建系统服务 (仅 Linux)"
    echo
    echo "示例:"
    echo "  $0             执行完整安装"
    echo "  $0 --no-service  安装但不创建系统服务"
}

# 解析命令行参数
NO_SERVICE=false

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
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 运行主函数
main