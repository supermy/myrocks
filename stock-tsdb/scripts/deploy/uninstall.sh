#!/bin/bash

# Stock-TSDB 卸载脚本
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

# 停止服务
stop_service() {
    log_info "停止 Stock-TSDB 服务..."

    if [[ "$OS" == "Linux" ]]; then
        # 检查 systemd 服务是否存在
        if systemctl list-unit-files | grep -q "stock-tsdb.service"; then
            log_info "停止 systemd 服务..."
            sudo systemctl stop stock-tsdb 2>/dev/null || true
            sudo systemctl disable stock-tsdb 2>/dev/null || true
        else
            log_info "未找到 systemd 服务"
        fi
    else
        # macOS - 尝试杀死进程
        if pgrep -f "stock-tsdb-server" > /dev/null; then
            log_info "终止 stock-tsdb-server 进程..."
            pkill -f "stock-tsdb-server" || true
        else
            log_info "未找到运行中的 stock-tsdb-server 进程"
        fi
    fi
}

# 卸载系统文件
uninstall_system_files() {
    log_info "卸载系统文件..."

    # 卸载二进制文件
    if [[ -f "/usr/local/bin/stock-tsdb-server" ]]; then
        log_info "删除二进制文件..."
        sudo rm -f /usr/local/bin/stock-tsdb-server
    else
        log_info "未找到二进制文件"
    fi

    # 卸载 Lua 文件
    if [[ -d "/usr/local/share/stock-tsdb" ]]; then
        log_info "删除 Lua 文件..."
        sudo rm -rf /usr/local/share/stock-tsdb
    else
        log_info "未找到 Lua 文件"
    fi

    # 卸载配置文件
    if [[ -f "/usr/local/etc/stock-tsdb.conf" ]]; then
        read -p "是否删除配置文件? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除配置文件..."
            sudo rm -f /usr/local/etc/stock-tsdb.conf
        else
            log_info "保留配置文件"
        fi
    else
        log_info "未找到配置文件"
    fi

    # 卸载 systemd 服务文件 (仅 Linux)
    if [[ "$OS" == "Linux" ]]; then
        if [[ -f "/etc/systemd/system/stock-tsdb.service" ]]; then
            log_info "删除 systemd 服务文件..."
            sudo rm -f /etc/systemd/system/stock-tsdb.service
            sudo systemctl daemon-reload 2>/dev/null || true
        else
            log_info "未找到 systemd 服务文件"
        fi
    fi
}

# 删除用户数据
remove_user_data() {
    echo
    log_warn "==========================================="
    log_warn "注意: 以下操作将删除用户数据!"
    log_warn "==========================================="
    echo

    if [[ "$OS" == "Linux" ]]; then
        # 删除日志目录
        if [[ -d "/var/log/stock-tsdb" ]]; then
            read -p "是否删除日志数据? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除日志数据..."
                sudo rm -rf /var/log/stock-tsdb
            else
                log_info "保留日志数据"
            fi
        else
            log_info "未找到日志数据"
        fi

        # 删除数据目录
        if [[ -d "/var/lib/stock-tsdb" ]]; then
            read -p "是否删除数据库数据? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除数据库数据..."
                sudo rm -rf /var/lib/stock-tsdb
            else
                log_info "保留数据库数据"
            fi
        else
            log_info "未找到数据库数据"
        fi

        # 删除用户和组
        if id "stock-tsdb" &>/dev/null; then
            read -p "是否删除 stock-tsdb 用户和组? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除 stock-tsdb 用户和组..."
                sudo userdel stock-tsdb 2>/dev/null || true
                # 注意: 不删除 home 目录，因为它可能包含重要数据
            else
                log_info "保留 stock-tsdb 用户和组"
            fi
        else
            log_info "未找到 stock-tsdb 用户"
        fi
    else
        # macOS
        # 删除日志目录
        if [[ -d "/var/log/stock-tsdb" ]]; then
            read -p "是否删除日志数据? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除日志数据..."
                sudo rm -rf /var/log/stock-tsdb
            else
                log_info "保留日志数据"
            fi
        else
            log_info "未找到日志数据"
        fi

        # 删除数据目录
        if [[ -d "/var/lib/stock-tsdb" ]]; then
            read -p "是否删除数据库数据? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "删除数据库数据..."
                sudo rm -rf /var/lib/stock-tsdb
            else
                log_info "保留数据库数据"
            fi
        else
            log_info "未找到数据库数据"
        fi
    fi
}

# 清理 LuaRocks 安装的包
cleanup_luarocks() {
    echo
    log_info "清理 LuaRocks 安装的包..."

    # 列出已安装的包
    log_info "已安装的 Lua 包:"
    luarocks list | grep -E "(cjson|luasocket|llthreads2|lzmq)" || true

    read -p "是否卸载 Stock-TSDB 相关的 Lua 包? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "卸载 Lua 包..."
        
        # 卸载 lua-cjson
        if luarocks list | grep -q "lua-cjson"; then
            log_info "卸载 lua-cjson..."
            luarocks remove lua-cjson --local 2>/dev/null || sudo luarocks remove lua-cjson 2>/dev/null || true
        fi

        # 卸载 luasocket
        if luarocks list | grep -q "luasocket"; then
            log_info "卸载 luasocket..."
            luarocks remove luasocket --local 2>/dev/null || sudo luarocks remove luasocket 2>/dev/null || true
        fi

        # 卸载 lua-llthreads2
        if luarocks list | grep -q "llthreads2"; then
            log_info "卸载 lua-llthreads2..."
            luarocks remove lua-llthreads2 --local 2>/dev/null || sudo luarocks remove lua-llthreads2 2>/dev/null || true
        fi

        # 卸载 lzmq
        if luarocks list | grep -q "lzmq"; then
            log_info "卸载 lzmq..."
            luarocks remove lzmq --local 2>/dev/null || sudo luarocks remove lzmq 2>/dev/null || true
        fi
    else
        log_info "保留 Lua 包"
    fi
}

# 显示卸载完成信息
show_completion_info() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB 卸载完成!"
    log_info "==========================================="
    echo

    log_info "已执行的操作:"
    log_info "1. 停止运行中的服务"
    log_info "2. 删除系统文件和二进制程序"
    log_info "3. 删除 systemd 服务文件 (Linux)"
    log_info "4. 根据用户选择删除用户数据和配置文件"
    log_info "5. 根据用户选择清理 Lua 包"

    echo
    log_warn "注意: 以下项目需要手动清理:"
    log_warn "- 防火墙规则"
    log_warn "- 自定义的系统配置"
    log_warn "- 备份的数据文件"
}

# 主函数
main() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB 卸载脚本"
    log_info "==========================================="
    echo

    # 检查是否以 root 权限运行
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 用户运行此脚本"
        exit 1
    fi

    # 检查操作系统
    check_os

    # 确认卸载操作
    log_warn "此操作将卸载 Stock-TSDB 系统!"
    read -p "确认继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "取消卸载操作"
        exit 0
    fi

    # 停止服务
    stop_service

    # 卸载系统文件
    uninstall_system_files

    # 删除用户数据
    remove_user_data

    # 清理 LuaRocks 包
    cleanup_luarocks

    # 显示完成信息
    show_completion_info

    log_info "卸载脚本执行完成!"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB 卸载脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo
    echo "注意: 此脚本将删除 Stock-TSDB 安装的所有组件"
    echo "请在执行前备份重要数据"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
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