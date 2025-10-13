#!/bin/bash

# Stock-TSDB 管理脚本
# 提供启动、停止、重启等常用操作

set -e

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

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 默认配置
CONFIG_FILE="./conf/stock-tsdb.conf"
DATA_DIR="./data"
LOGS_DIR="./logs"
BINARY="./stock-tsdb-server"

# 检查二进制文件是否存在
check_binary() {
    if [[ ! -f "$BINARY" ]]; then
        log_error "未找到二进制文件: $BINARY"
        log_info "请先运行 'make' 命令编译项目"
        exit 1
    fi
}

# 检查配置文件是否存在
check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "未找到配置文件: $CONFIG_FILE"
        log_info "请检查配置文件路径"
        exit 1
    fi
}

# 创建必要的目录
create_directories() {
    mkdir -p "$DATA_DIR" "$LOGS_DIR"
    log_debug "创建目录: $DATA_DIR, $LOGS_DIR"
}

# 启动服务
start_service() {
    log_info "启动 Stock-TSDB 服务..."
    
    check_binary
    check_config
    create_directories
    
    # 检查是否已经在运行
    if pgrep -f "$BINARY" > /dev/null; then
        log_warn "Stock-TSDB 服务已在运行"
        exit 1
    fi
    
    # 启动服务
    "$BINARY" -c "$CONFIG_FILE" &
    
    # 等待几秒钟检查是否启动成功
    sleep 3
    
    if pgrep -f "$BINARY" > /dev/null; then
        log_info "Stock-TSDB 服务启动成功"
        echo "PID: $(pgrep -f "$BINARY")"
    else
        log_error "Stock-TSDB 服务启动失败"
        exit 1
    fi
}

# 停止服务
stop_service() {
    log_info "停止 Stock-TSDB 服务..."
    
    if pgrep -f "$BINARY" > /dev/null; then
        pkill -f "$BINARY"
        sleep 2
        
        if pgrep -f "$BINARY" > /dev/null; then
            log_warn "服务未完全停止，强制终止..."
            pkill -9 -f "$BINARY"
        fi
        
        log_info "Stock-TSDB 服务已停止"
    else
        log_warn "Stock-TSDB 服务未运行"
    fi
}

# 重启服务
restart_service() {
    log_info "重启 Stock-TSDB 服务..."
    stop_service
    sleep 2
    start_service
}

# 查看服务状态
status_service() {
    if pgrep -f "$BINARY" > /dev/null; then
        log_info "Stock-TSDB 服务正在运行"
        echo "PID: $(pgrep -f "$BINARY")"
    else
        log_info "Stock-TSDB 服务未运行"
    fi
}

# 查看日志
view_logs() {
    if [[ -f "$LOGS_DIR/stock-tsdb.log" ]]; then
        log_info "显示最新日志 (按 Ctrl+C 退出)..."
        tail -f "$LOGS_DIR/stock-tsdb.log"
    else
        log_warn "日志文件不存在: $LOGS_DIR/stock-tsdb.log"
    fi
}

# 显示服务信息
show_info() {
    echo
    log_info "==========================================="
    log_info "Stock-TSDB 服务信息"
    log_info "==========================================="
    echo
    
    echo "项目目录: $SCRIPT_DIR"
    echo "配置文件: $CONFIG_FILE"
    echo "数据目录: $DATA_DIR"
    echo "日志目录: $LOGS_DIR"
    echo "二进制文件: $BINARY"
    
    echo
    status_service
    
    echo
    log_info "可用命令:"
    echo "  start   - 启动服务"
    echo "  stop    - 停止服务"
    echo "  restart - 重启服务"
    echo "  status  - 查看状态"
    echo "  logs    - 查看日志"
    echo "  info    - 显示信息"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB 管理脚本"
    echo
    echo "用法: $0 {start|stop|restart|status|logs|info|help}"
    echo
    echo "命令:"
    echo "  start   - 启动 Stock-TSDB 服务"
    echo "  stop    - 停止 Stock-TSDB 服务"
    echo "  restart - 重启 Stock-TSDB 服务"
    echo "  status  - 查看服务状态"
    echo "  logs    - 实时查看日志"
    echo "  info    - 显示服务信息"
    echo "  help    - 显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 start     # 启动服务"
    echo "  $0 stop      # 停止服务"
    echo "  $0 restart   # 重启服务"
}

# 主函数
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    case "$1" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            status_service
            ;;
        logs)
            view_logs
            ;;
        info)
            show_info
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"