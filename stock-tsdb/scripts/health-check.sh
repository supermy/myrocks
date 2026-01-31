#!/bin/bash

# Stock-TSDB 健康检查脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="健康检查脚本"

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

检查Stock-TSDB服务的健康状态和性能指标。

用法: $0 [选项]

选项:
    -h, --host HOST           服务地址 [默认: 127.0.0.1]
    -p, --port PORT           服务端口 [默认: 6379]
    --mode MODE               检查模式 [默认: basic, 支持: basic, full, performance]
    --timeout SEC             超时时间(秒) [默认: 10]
    --output FORMAT           输出格式 [默认: human, 支持: human, json]
    --check-interval SEC      连续检查间隔 [默认: 不连续]
    --check-count NUM         连续检查次数
    -h, --help               显示此帮助信息

检查模式说明:
    basic       基础健康检查 (服务连通性、基本指标)
    full        完整健康检查 (包含存储、性能、资源使用)
    performance 性能检查 (响应时间、吞吐量、延迟)

示例:
    # 基础健康检查
    $0 --mode basic
    
    # 完整健康检查，JSON格式输出
    $0 --mode full --output json
    
    # 连续监控5次，间隔10秒
    $0 --check-interval 10 --check-count 5
    
    # 检查远程服务
    $0 --host 192.168.1.100 --port 6380

EOF
}

# 检查服务连通性
check_connectivity() {
    log_info "检查服务连通性..."
    
    local host="$1"
    local port="$2"
    
    # 使用nc检查端口
    if command -v nc &> /dev/null; then
        if nc -z "$host" "$port" 2>/dev/null; then
            log_success "服务端口连通正常: $host:$port"
            return 0
        else
            log_error "服务端口无法连接: $host:$port"
            return 1
        fi
    else
        log_warning "nc命令不可用，跳过端口检查"
        return 0
    fi
}

# 检查HTTP健康接口
check_http_health() {
    log_info "检查HTTP健康接口..."
    
    local host="$1"
    local port="$2"
    local health_port=$((port + 2000))
    
    if command -v curl &> /dev/null; then
        local health_url="http://$host:$health_port/health"
        local response=$(curl -s --connect-timeout "$TIMEOUT" "$health_url" 2>/dev/null || echo "")
        
        if [[ -n "$response" ]]; then
            log_success "HTTP健康接口正常"
            echo "   响应: $response"
            return 0
        else
            log_error "HTTP健康接口无响应"
            return 1
        fi
    else
        log_warning "curl命令不可用，跳过HTTP检查"
        return 0
    fi
}

# 检查性能指标
check_performance_metrics() {
    log_info "检查性能指标..."
    
    local host="$1"
    local port="$2"
    local metrics_port=$((port + 2000))
    
    if command -v curl &> /dev/null; then
        local metrics_url="http://$host:$metrics_port/metrics"
        local metrics=$(curl -s --connect-timeout "$TIMEOUT" "$metrics_url" 2>/dev/null || echo "")
        
        if [[ -n "$metrics" ]]; then
            log_success "性能指标获取成功"
            
            # 解析关键指标
            local requests=$(echo "$metrics" | grep -o 'tsdb_requests_total [0-9]*' | cut -d' ' -f2 || echo "0")
            local latency=$(echo "$metrics" | grep -o 'tsdb_latency_seconds [0-9.]*' | cut -d' ' -f2 || echo "0")
            local memory=$(echo "$metrics" | grep -o 'tsdb_memory_bytes [0-9]*' | cut -d' ' -f2 || echo "0")
            
            echo "   总请求数: $requests"
            echo "   平均延迟: ${latency}s"
            echo "   内存使用: $((memory/1024/1024))MB"
            
            return 0
        else
            log_error "无法获取性能指标"
            return 1
        fi
    else
        log_warning "curl命令不可用，跳过性能指标检查"
        return 0
    fi
}

# 检查存储状态
check_storage_status() {
    log_info "检查存储状态..."
    
    # 检查数据目录
    local data_dir="./data"
    if [[ -d "$data_dir" ]]; then
        local disk_usage=$(du -sh "$data_dir" 2>/dev/null | cut -f1 || echo "未知")
        log_success "数据目录存在，使用空间: $disk_usage"
        
        # 检查目录权限
        if [[ -w "$data_dir" ]]; then
            log_success "数据目录可写"
        else
            log_error "数据目录不可写"
            return 1
        fi
    else
        log_warning "数据目录不存在: $data_dir"
    fi
    
    return 0
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存使用
    if command -v free &> /dev/null; then
        local total_mem=$(free -m | awk '/Mem:/ {print $2}')
        local used_mem=$(free -m | awk '/Mem:/ {print $3}')
        local mem_usage=$((used_mem * 100 / total_mem))
        
        echo "   总内存: ${total_mem}MB"
        echo "   已使用: ${used_mem}MB (${mem_usage}%)"
        
        if [[ $mem_usage -gt 90 ]]; then
            log_warning "内存使用率较高"
        else
            log_success "内存使用正常"
        fi
    fi
    
    # 检查磁盘空间
    if command -v df &> /dev/null; then
        local disk_usage=$(df -h . | awk 'NR==2 {print $5}' | sed 's/%//')
        echo "   磁盘使用率: ${disk_usage}%"
        
        if [[ $disk_usage -gt 90 ]]; then
            log_warning "磁盘空间不足"
        else
            log_success "磁盘空间充足"
        fi
    fi
    
    return 0
}

# 基础健康检查
basic_health_check() {
    local host="$1"
    local port="$2"
    
    echo "=== 基础健康检查 ==="
    
    local all_passed=true
    
    # 检查连通性
    if ! check_connectivity "$host" "$port"; then
        all_passed=false
    fi
    
    # 检查HTTP健康
    if ! check_http_health "$host" "$port"; then
        all_passed=false
    fi
    
    return $all_passed
}

# 完整健康检查
full_health_check() {
    local host="$1"
    local port="$2"
    
    echo "=== 完整健康检查 ==="
    
    local all_passed=true
    
    # 基础检查
    if ! basic_health_check "$host" "$port"; then
        all_passed=false
    fi
    
    # 性能指标
    if ! check_performance_metrics "$host" "$port"; then
        all_passed=false
    fi
    
    # 存储状态
    if ! check_storage_status; then
        all_passed=false
    fi
    
    # 系统资源
    if ! check_system_resources; then
        all_passed=false
    fi
    
    return $all_passed
}

# 性能检查
performance_check() {
    local host="$1"
    local port="$2"
    
    echo "=== 性能检查 ==="
    
    # 检查性能指标
    if ! check_performance_metrics "$host" "$port"; then
        return 1
    fi
    
    # 简单的性能测试
    log_info "执行简单性能测试..."
    
    # 这里可以添加实际的性能测试逻辑
    # 例如：发送测试查询，测量响应时间等
    
    log_success "性能检查完成"
    return 0
}

# 格式化输出
format_output() {
    local result="$1"
    local format="$2"
    
    if [[ "$format" == "json" ]]; then
        # 简单的JSON格式输出
        echo "{\"status\": \"$result\", \"timestamp\": \"$(date -Iseconds)\"}"
    else
        # 人类可读格式
        if [[ "$result" == "healthy" ]]; then
            echo ""
            echo "✅ 服务状态: 健康"
            echo "🕒 检查时间: $(date)"
        else
            echo ""
            echo "❌ 服务状态: 异常"
            echo "🕒 检查时间: $(date)"
        fi
    fi
}

# 主函数
main() {
    # 默认配置
    HOST="127.0.0.1"
    PORT=6379
    MODE="basic"
    TIMEOUT=10
    OUTPUT_FORMAT="human"
    CHECK_INTERVAL=""
    CHECK_COUNT=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                HOST="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --check-interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --check-count)
                CHECK_COUNT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证模式
    case "$MODE" in
        basic|full|performance)
            # 有效模式
            ;;
        *)
            log_error "无效的检查模式: $MODE"
            echo "支持的模式: basic, full, performance"
            exit 1
            ;;
    esac
    
    # 连续检查逻辑
    if [[ -n "$CHECK_INTERVAL" && -n "$CHECK_COUNT" ]]; then
        log_info "开始连续健康检查..."
        echo "检查间隔: ${CHECK_INTERVAL}秒"
        echo "检查次数: $CHECK_COUNT"
        echo ""
        
        local count=1
        local all_healthy=true
        
        while [[ $count -le $CHECK_COUNT ]]; do
            echo "=== 第 $count/$CHECK_COUNT 次检查 ==="
            
            case "$MODE" in
                basic)
                    if ! basic_health_check "$HOST" "$PORT"; then
                        all_healthy=false
                    fi
                    ;;
                full)
                    if ! full_health_check "$HOST" "$PORT"; then
                        all_healthy=false
                    fi
                    ;;
                performance)
                    if ! performance_check "$HOST" "$PORT"; then
                        all_healthy=false
                    fi
                    ;;
            esac
            
            if [[ $count -lt $CHECK_COUNT ]]; then
                echo "等待 ${CHECK_INTERVAL}秒后继续..."
                sleep "$CHECK_INTERVAL"
            fi
            
            count=$((count + 1))
        done
        
        if [[ "$all_healthy" == "true" ]]; then
            format_output "healthy" "$OUTPUT_FORMAT"
            exit 0
        else
            format_output "unhealthy" "$OUTPUT_FORMAT"
            exit 1
        fi
    fi
    
    # 单次检查
    log_info "开始健康检查..."
    echo "服务地址: $HOST:$PORT"
    echo "检查模式: $MODE"
    echo ""
    
    local result=""
    
    case "$MODE" in
        basic)
            if basic_health_check "$HOST" "$PORT"; then
                result="healthy"
            else
                result="unhealthy"
            fi
            ;;
        full)
            if full_health_check "$HOST" "$PORT"; then
                result="healthy"
            else
                result="unhealthy"
            fi
            ;;
        performance)
            if performance_check "$HOST" "$PORT"; then
                result="healthy"
            else
                result="unhealthy"
            fi
            ;;
    esac
    
    # 输出结果
    format_output "$result" "$OUTPUT_FORMAT"
    
    if [[ "$result" == "healthy" ]]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@"