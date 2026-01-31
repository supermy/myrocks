#!/bin/bash

# Stock-TSDB 单机版快速启动脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="单机极致性能版启动脚本"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
${SCRIPT_NAME}

快速启动单机极致性能版TSDB服务。

用法: $0 [选项]

选项:
    -c, --config FILE         配置文件路径 [默认: config/standalone_high_performance.lua]
    -p, --port PORT           服务端口 [默认: 6379]
    -d, --data-dir DIR        数据目录 [默认: ./data/standalone]
    -l, --log-level LEVEL     日志级别 [默认: info]
    --memory SIZE             内存池大小 [默认: 2GB]
    --daemon                  以守护进程方式运行
    --check-deps             检查依赖但不启动
    -h, --help               显示此帮助信息

示例:
    # 使用默认配置启动
    $0
    
    # 自定义端口和数据目录
    $0 --port 6380 --data-dir /data/tsdb
    
    # 以守护进程方式运行
    $0 --daemon
    
    # 检查依赖
    $0 --check-deps

EOF
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查LuaJIT
    if ! command -v luajit &> /dev/null; then
        log_error "LuaJIT未安装，请先安装LuaJIT"
        exit 1
    fi
    
    # 检查Lua版本
    LUA_VERSION=$(luajit -v 2>&1 | grep -o 'LuaJIT [0-9.]*' | cut -d' ' -f2)
    log_info "LuaJIT版本: $LUA_VERSION"
    
    # 检查必要目录
    for dir in "lua" "config"; do
        if [[ ! -d "$dir" ]]; then
            log_error "目录 '$dir' 不存在，请确保在项目根目录运行"
            exit 1
        fi
    done
    
    # 检查配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "配置文件 '$CONFIG_FILE' 不存在，将使用默认配置"
        # 尝试生成默认配置
        if [[ -f "config/standalone_high_performance.lua" ]]; then
            CONFIG_FILE="config/standalone_high_performance.lua"
        else
            log_error "未找到默认配置文件"
            exit 1
        fi
    fi
    
    log_success "依赖检查通过"
}

# 检查端口占用
check_port() {
    if command -v nc &> /dev/null; then
        if nc -z localhost "$PORT" 2>/dev/null; then
            log_warning "端口 $PORT 已被占用"
            return 1
        fi
    fi
    return 0
}

# 准备运行环境
prepare_environment() {
    log_info "准备运行环境..."
    
    # 创建必要目录
    mkdir -p "$DATA_DIR" "logs"
    
    # 设置Lua路径
    export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"
    export LUA_CPATH="./?.so;$LUA_CPATH"
    
    # 设置性能参数
    if [[ -n "$MEMORY_SIZE" ]]; then
        export TSDB_MEMORY_POOL="$MEMORY_SIZE"
    fi
}

# 生成启动配置
generate_startup_config() {
    log_info "生成启动配置..."
    
    # 创建启动脚本
    cat > "scripts/run-standalone.lua" << EOF
-- 单机版启动配置
local config = require("$(basename "$CONFIG_FILE" .lua)")

-- 覆盖配置参数
config.network.port = $PORT
config.storage.data_dir = "$DATA_DIR"
config.logging.level = "$LOG_LEVEL"

if "$MEMORY_SIZE" ~= "" then
    config.storage.performance.memory_pool_size = "$MEMORY_SIZE"
end

return config
EOF
    
    log_info "启动配置已生成: scripts/run-standalone.lua"
}

# 启动服务
start_service() {
    log_info "启动TSDB服务..."
    
    local start_cmd="luajit lua/main.lua --config scripts/run-standalone.lua"
    
    if [[ "$DAEMON_MODE" == "true" ]]; then
        log_info "以守护进程方式启动..."
        nohup $start_cmd > "logs/standalone.out" 2>&1 &
        local pid=$!
        echo $pid > "/tmp/stock-tsdb-standalone.pid"
        
        # 等待服务启动
        sleep 3
        
        if kill -0 "$pid" 2>/dev/null; then
            log_success "服务已启动 (PID: $pid)"
        else
            log_error "服务启动失败，请检查日志: logs/standalone.out"
            exit 1
        fi
    else
        log_info "以前台方式启动..."
        log_info "服务地址: http://localhost:$PORT"
        log_info "监控地址: http://localhost:9090/metrics"
        echo ""
        echo "按 Ctrl+C 停止服务"
        echo ""
        
        # 前台运行
        exec $start_cmd
    fi
}

# 停止服务
stop_service() {
    log_info "停止TSDB服务..."
    
    if [[ -f "/tmp/stock-tsdb-standalone.pid" ]]; then
        local pid=$(cat "/tmp/stock-tsdb-standalone.pid")
        
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "/tmp/stock-tsdb-standalone.pid"
            log_success "服务已停止"
        else
            log_warning "服务未运行"
            rm -f "/tmp/stock-tsdb-standalone.pid"
        fi
    else
        log_warning "未找到PID文件，服务可能未运行"
    fi
}

# 检查服务状态
check_service_status() {
    log_info "检查服务状态..."
    
    if [[ -f "/tmp/stock-tsdb-standalone.pid" ]]; then
        local pid=$(cat "/tmp/stock-tsdb-standalone.pid")
        
        if kill -0 "$pid" 2>/dev/null; then
            log_success "服务运行中 (PID: $pid)"
            
            # 检查端口监听
            if command -v lsof &> /dev/null; then
                if lsof -i :"$PORT" > /dev/null 2>&1; then
                    log_info "端口 $PORT 监听正常"
                else
                    log_warning "端口 $PORT 未监听"
                fi
            fi
            
            # 检查健康接口
            if command -v curl &> /dev/null; then
                if curl -s "http://localhost:9090/health" > /dev/null 2>&1; then
                    log_success "健康检查通过"
                else
                    log_warning "健康检查失败"
                fi
            fi
            
            return 0
        else
            log_error "服务进程不存在"
            rm -f "/tmp/stock-tsdb-standalone.pid"
            return 1
        fi
    else
        log_warning "服务未运行"
        return 1
    fi
}

# 显示服务信息
show_service_info() {
    echo ""
    echo "=== Stock-TSDB 单机版服务信息 ==="
    echo "服务模式: 单机极致性能版"
    echo "服务端口: $PORT"
    echo "数据目录: $DATA_DIR"
    echo "配置文件: $CONFIG_FILE"
    echo "日志级别: $LOG_LEVEL"
    
    if [[ -n "$MEMORY_SIZE" ]]; then
        echo "内存配置: $MEMORY_SIZE"
    fi
    
    echo ""
    echo "=== 访问地址 ==="
    echo "服务地址: http://localhost:$PORT"
    echo "监控地址: http://localhost:9090/metrics"
    echo "健康检查: http://localhost:9090/health"
    echo ""
    
    if [[ "$DAEMON_MODE" == "true" ]]; then
        echo "=== 管理命令 ==="
        echo "停止服务: $0 stop"
        echo "重启服务: $0 restart"
        echo "查看状态: $0 status"
        echo "查看日志: tail -f logs/standalone.log"
    else
        echo "服务以前台方式运行，按 Ctrl+C 停止"
    fi
    echo ""
}

# 主函数
main() {
    # 默认配置
    CONFIG_FILE="config/standalone_high_performance.lua"
    PORT=6379
    DATA_DIR="./data/standalone"
    LOG_LEVEL="info"
    MEMORY_SIZE=""
    DAEMON_MODE="false"
    CHECK_DEPS_ONLY="false"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -d|--data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            -l|--log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --memory)
                MEMORY_SIZE="$2"
                shift 2
                ;;
            --daemon)
                DAEMON_MODE="true"
                shift
                ;;
            --check-deps)
                CHECK_DEPS_ONLY="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            start)
                # 直接启动
                shift
                ;;
            stop)
                stop_service
                exit 0
                ;;
            restart)
                stop_service
                sleep 2
                # 继续执行启动流程
                shift
                ;;
            status)
                check_service_status
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查依赖
    check_dependencies
    
    if [[ "$CHECK_DEPS_ONLY" == "true" ]]; then
        log_success "依赖检查完成"
        exit 0
    fi
    
    # 检查端口
    if ! check_port; then
        log_error "端口 $PORT 不可用"
        exit 1
    fi
    
    # 准备环境
    prepare_environment
    
    # 生成配置
    generate_startup_config
    
    # 启动服务
    start_service
    
    # 显示信息
    show_service_info
}

# 运行主函数
main "$@"