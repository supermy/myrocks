#!/bin/bash

# Stock-TSDB 业务数据Web服务器启动脚本
# 快速启动业务数据Web服务器，支持开发和生产环境

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

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 业务数据Web服务器启动脚本

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -p, --port PORT     指定端口号（默认: 8081）
    -e, --env ENV       环境类型：dev（开发）或 prod（生产）
    -d, --daemon        后台模式运行
    -l, --log FILE      指定日志文件
    -c, --config FILE   指定配置文件

示例:
    # 开发环境启动
    $0 -e dev
    
    # 生产环境后台启动
    $0 -e prod -d -l /var/log/stock-tsdb/business-web.log
    
    # 指定端口启动
    $0 -p 9090 -e dev

EOF
}

# 默认配置
PORT="8081"
ENV="dev"
DAEMON=false
LOG_FILE=""
CONFIG_FILE=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -e|--env)
            ENV="$2"
            shift 2
            ;;
        -d|--daemon)
            DAEMON=true
            shift
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查LuaJIT
check_luajit() {
    if ! command -v luajit &> /dev/null; then
        log_error "未找到 LuaJIT，请先安装 LuaJIT"
        exit 1
    fi
    log_info "LuaJIT 版本: $(luajit -v)"
}

# 检查项目结构
check_project_structure() {
    if [[ ! -f "web/start_business_web.lua" ]]; then
        log_error "业务数据Web服务器启动文件不存在: web/start_business_web.lua"
        exit 1
    fi
    
    if [[ ! -d "lua" ]]; then
        log_error "Lua模块目录不存在: lua"
        exit 1
    fi
    
    log_info "项目结构检查通过"
}

# 设置环境变量
setup_environment() {
    export LUA_PATH="$(pwd)/lua/?.lua;$(pwd)/?.lua;;"
    export LUA_CPATH="$(pwd)/lib/?.so;;"
    
    if [[ "$ENV" == "prod" ]]; then
        export STOCK_TSDB_ENV="production"
        log_info "生产环境配置"
    else
        export STOCK_TSDB_ENV="development"
        log_info "开发环境配置"
    fi
    
    if [[ -n "$CONFIG_FILE" ]]; then
        export STOCK_TSDB_CONFIG="$CONFIG_FILE"
        log_info "使用自定义配置文件: $CONFIG_FILE"
    fi
}

# 启动服务器
start_server() {
    local cmd="cd web && luajit start_business_web.lua"
    
    if [[ "$DAEMON" == true ]]; then
        log_info "后台模式启动业务数据Web服务器..."
        if [[ -n "$LOG_FILE" ]]; then
            nohup $cmd > "$LOG_FILE" 2>&1 &
        else
            nohup $cmd > /dev/null 2>&1 &
        fi
        local pid=$!
        echo $pid > /tmp/stock-tsdb-business-web.pid
        log_info "业务数据Web服务器已启动，PID: $pid"
        log_info "访问地址: http://localhost:$PORT"
    else
        log_info "前台模式启动业务数据Web服务器..."
        log_info "访问地址: http://localhost:$PORT"
        log_info "按 Ctrl+C 停止服务器"
        cd web && luajit start_business_web.lua
    fi
}

# 检查端口占用
check_port() {
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        log_warn "端口 $PORT 已被占用"
        if [[ "$DAEMON" == false ]]; then
            read -p "是否继续启动? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "用户取消启动"
                exit 0
            fi
        fi
    fi
}

# 主函数
main() {
    log_info "Stock-TSDB 业务数据Web服务器启动脚本"
    log_info "环境: $ENV, 端口: $PORT, 后台模式: $DAEMON"
    
    # 执行检查
    check_luajit
    check_project_structure
    check_port
    setup_environment
    
    # 启动服务器
    start_server
}

# 信号处理
trap 'log_info "服务器停止"; exit 0' INT TERM

# 运行主函数
main "$@"