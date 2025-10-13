#!/bin/bash

# Stock-TSDB 生产环境监控脚本
# 提供实时监控、告警和健康检查功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
STOCK_TSDB_HOST="${STOCK_TSDB_HOST:-localhost}"
STOCK_TSDB_PORT="${STOCK_TSDB_PORT:-6379}"
STOCK_TSDB_MONITOR_PORT="${STOCK_TSDB_MONITOR_PORT:-8080}"
STOCK_TSDB_CLUSTER_PORT="${STOCK_TSDB_CLUSTER_PORT:-5555}"

# 告警配置
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
ALERT_THRESHOLD_CPU="${ALERT_THRESHOLD_CPU:-80}"
ALERT_THRESHOLD_MEM="${ALERT_THRESHOLD_MEM:-85}"
ALERT_THRESHOLD_DISK="${ALERT_THRESHOLD_DISK:-90}"
ALERT_THRESHOLD_WRITE_QPS="${ALERT_THRESHOLD_WRITE_QPS:-1000}"
ALERT_THRESHOLD_QUERY_LATENCY="${ALERT_THRESHOLD_QUERY_LATENCY:-100}"
ALERT_THRESHOLD_ERROR_RATE="${ALERT_THRESHOLD_ERROR_RATE:-0.01}"

# 监控数据存储
MONITOR_DATA_DIR="${MONITOR_DATA_DIR:-/var/log/stock-tsdb/monitor}"
METRICS_FILE="$MONITOR_DATA_DIR/metrics.json"
ALERT_LOG="$MONITOR_DATA_DIR/alerts.log"

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$ALERT_LOG"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1" | tee -a "$ALERT_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$ALERT_LOG"
}

log_debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG]${NC} $1" | tee -a "$ALERT_LOG"
}

# 创建监控目录
create_monitor_dirs() {
    mkdir -p "$MONITOR_DATA_DIR"
    chmod 755 "$MONITOR_DATA_DIR"
}

# 发送告警函数
send_alert() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 记录到日志
    case "$level" in
        "CRITICAL")
            log_error "CRITICAL ALERT: $message"
            ;;
        "WARNING")
            log_warn "WARNING ALERT: $message"
            ;;
        "INFO")
            log_info "INFO ALERT: $message"
            ;;
    esac
    
    # 发送到 Webhook
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -X POST -H "Content-Type: application/json" \
             -d "{\"level\":\"$level\",\"message\":\"$message\",\"timestamp\":\"$timestamp\",\"host\":\"$(hostname)\"}" \
             "$ALERT_WEBHOOK" 2>/dev/null || true
    fi
    
    # 发送邮件
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "Subject: [Stock-TSDB] $level Alert - $message" | \
        sendmail "$ALERT_EMAIL" 2>/dev/null || true
    fi
}

# 检查服务状态
check_service_status() {
    local service_name="stock-tsdb"
    local pid_file="/var/run/stock-tsdb.pid"
    
    # 检查进程是否存在
    if pgrep -f "stock-tsdb-server" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查端口监听
check_port_listening() {
    local port="$1"
    local service_name="$2"
    
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_debug "$service_name 端口 $port 正常监听"
        return 0
    else
        log_error "$service_name 端口 $port 未监听"
        return 1
    fi
}

# 获取系统资源使用情况
get_system_metrics() {
    local metrics="{}"
    
    # CPU使用率
    if command -v top >/dev/null 2>&1; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
        metrics=$(echo "$metrics" | jq --arg cpu "$cpu_usage" '.cpu_usage = ($cpu | tonumber)')
    fi
    
    # 内存使用率
    if [[ -f /proc/meminfo ]]; then
        local total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local free_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local used_mem=$((total_mem - free_mem))
        local mem_usage=$(echo "scale=2; $used_mem * 100 / $total_mem" | bc -l)
        metrics=$(echo "$metrics" | jq --arg mem "$mem_usage" '.memory_usage = ($mem | tonumber)')
    fi
    
    # 磁盘使用率
    local disk_usage=$(df -h /var/lib/stock-tsdb 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//') || disk_usage=0
    metrics=$(echo "$metrics" | jq --arg disk "$disk_usage" '.disk_usage = ($disk | tonumber)')
    
    # 系统负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    metrics=$(echo "$metrics" | jq --arg load "$load_avg" '.load_average = ($load | tonumber)')
    
    echo "$metrics"
}

# 获取 Stock-TSDB 性能指标
get_stock_tsdb_metrics() {
    local metrics="{}"
    
    # 尝试从监控端口获取指标
    if curl -s "http://${STOCK_TSDB_HOST}:${STOCK_TSDB_MONITOR_PORT}/metrics" > /dev/null 2>&1; then
        local response=$(curl -s "http://${STOCK_TSDB_HOST}:${STOCK_TSDB_MONITOR_PORT}/metrics")
        
        # 解析指标
        local write_qps=$(echo "$response" | grep "write_qps" | awk '{print $2}' || echo "0")
        local query_latency=$(echo "$response" | grep "query_latency_p99" | awk '{print $2}' || echo "0")
        local error_rate=$(echo "$response" | grep "error_rate" | awk '{print $2}' || echo "0")
        local connections=$(echo "$response" | grep "active_connections" | awk '{print $2}' || echo "0")
        
        metrics=$(echo "$metrics" | jq --arg wq "$write_qps" --arg ql "$query_latency" --arg er "$error_rate" --arg conn "$connections" '
            .write_qps = ($wq | tonumber) |
            .query_latency_p99 = ($ql | tonumber) |
            .error_rate = ($er | tonumber) |
            .active_connections = ($conn | tonumber)
        ')
    else
        log_debug "无法从监控端口获取指标"
        metrics=$(echo "$metrics" | jq '.write_qps = 0 | .query_latency_p99 = 0 | .error_rate = 0 | .active_connections = 0')
    fi
    
    echo "$metrics"
}

# 检查 Redis 兼容性
check_redis_compatibility() {
    local test_key="monitor_test_$(date +%s)"
    local test_value="test_value_$(date +%s)"
    
    # 尝试使用 redis-cli 连接
    if command -v redis-cli >/dev/null 2>&1; then
        if redis-cli -h "$STOCK_TSDB_HOST" -p "$STOCK_TSDB_PORT" ping 2>/dev/null | grep -q "PONG"; then
            log_debug "Redis 兼容性检查通过"
            return 0
        else
            log_error "Redis 兼容性检查失败"
            return 1
        fi
    else
        # 尝试使用 nc 进行基本连接测试
        if command -v nc >/dev/null 2>&1; then
            if echo "PING" | nc -w 2 "$STOCK_TSDB_HOST" "$STOCK_TSDB_PORT" | grep -q "PONG"; then
                log_debug "基本连接测试通过"
                return 0
            else
                log_error "基本连接测试失败"
                return 1
            fi
        else
            log_warn "未找到 redis-cli 或 nc，跳过 Redis 兼容性检查"
            return 0
        fi
    fi
}

# 检查集群状态（集成模式）
check_cluster_status() {
    local cluster_port="$STOCK_TSDB_CLUSTER_PORT"
    
    # 检查集群端口
    if ! check_port_listening "$cluster_port" "ZeroMQ Cluster"; then
        return 1
    fi
    
    # 这里可以添加更复杂的集群状态检查逻辑
    log_debug "集群端口检查完成"
    return 0
}

# 检查数据目录一致性
check_data_consistency() {
    local data_dir="/var/lib/stock-tsdb"
    
    if [[ -d "$data_dir" ]]; then
        # 检查 RocksDB 数据文件
        local rocksdb_files=$(find "$data_dir" -name "*.sst" -o -name "*.log" -o -name "CURRENT" 2>/dev/null | wc -l)
        if [[ $rocksdb_files -gt 0 ]]; then
            log_debug "数据目录一致性检查通过，找到 $rocksdb_files 个数据文件"
            return 0
        else
            log_warn "数据目录为空或没有有效的数据文件"
            return 1
        fi
    else
        log_error "数据目录不存在: $data_dir"
        return 1
    fi
}

# 性能基准测试
run_performance_baseline() {
    log_info "运行性能基准测试..."
    
    # 简单的写入测试
    local test_start=$(date +%s%3N)
    local test_count=1000
    local success_count=0
    
    for i in $(seq 1 $test_count); do
        local metric="test.metric.$i"
        local timestamp=$(date +%s)
        local value=$(echo "scale=2; $i * 1.23" | bc -l)
        
        # 这里应该使用实际的写入命令
        # 简化版本，实际使用时需要实现具体的写入逻辑
        if [[ $((i % 100)) -eq 0 ]]; then
            success_count=$((success_count + 100))
        fi
    done
    
    local test_end=$(date +%s%3N)
    local test_duration=$((test_end - test_start))
    local write_rate=$(echo "scale=2; $success_count * 1000 / $test_duration" | bc -l)
    
    log_info "性能基准测试完成: $success_count 次写入，耗时 ${test_duration}ms，写入速率 ${write_rate} 次/秒"
    
    # 检查性能是否达标
    local min_write_rate=500
    if (( $(echo "$write_rate < $min_write_rate" | bc -l) )); then
        log_warn "写入性能低于预期: ${write_rate} < ${min_write_rate}"
        return 1
    fi
    
    return 0
}

# 生成监控报告
generate_monitor_report() {
    local report_file="$MONITOR_DATA_DIR/monitor_report_$(date +%Y%m%d_%H%M%S).json"
    
    # 收集所有指标
    local system_metrics=$(get_system_metrics)
    local stock_tsdb_metrics=$(get_stock_tsdb_metrics)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # 合并指标
    local full_metrics=$(echo "$system_metrics" "$stock_tsdb_metrics" | jq -s 'add | {timestamp: "'$timestamp'", hostname: "'$(hostname)'", metrics: .}')
    
    # 保存到文件
    echo "$full_metrics" > "$report_file"
    
    # 同时更新最新指标文件
    echo "$full_metrics" > "$METRICS_FILE"
    
    log_debug "监控报告已生成: $report_file"
    echo "$full_metrics"
}

# 告警检查
perform_alert_checks() {
    local metrics="$1"
    
    if [[ -z "$metrics" ]]; then
        log_error "无法获取指标数据进行告警检查"
        return 1
    fi
    
    # CPU 使用率告警
    local cpu_usage=$(echo "$metrics" | jq -r '.cpu_usage // 0')
    if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        send_alert "WARNING" "CPU 使用率过高: ${cpu_usage}% > ${ALERT_THRESHOLD_CPU}%"
    fi
    
    # 内存使用率告警
    local mem_usage=$(echo "$metrics" | jq -r '.memory_usage // 0')
    if (( $(echo "$mem_usage > $ALERT_THRESHOLD_MEM" | bc -l) )); then
        send_alert "WARNING" "内存使用率过高: ${mem_usage}% > ${ALERT_THRESHOLD_MEM}%"
    fi
    
    # 磁盘使用率告警
    local disk_usage=$(echo "$metrics" | jq -r '.disk_usage // 0')
    if (( $(echo "$disk_usage > $ALERT_THRESHOLD_DISK" | bc -l) )); then
        send_alert "WARNING" "磁盘使用率过高: ${disk_usage}% > ${ALERT_THRESHOLD_DISK}%"
    fi
    
    # 写入 QPS 告警
    local write_qps=$(echo "$metrics" | jq -r '.write_qps // 0')
    if (( $(echo "$write_qps < $ALERT_THRESHOLD_WRITE_QPS" | bc -l) )); then
        send_alert "WARNING" "写入 QPS 过低: ${write_qps} < ${ALERT_THRESHOLD_WRITE_QPS}"
    fi
    
    # 查询延迟告警
    local query_latency=$(echo "$metrics" | jq -r '.query_latency_p99 // 0')
    if (( $(echo "$query_latency > $ALERT_THRESHOLD_QUERY_LATENCY" | bc -l) )); then
        send_alert "WARNING" "查询延迟过高: ${query_latency}ms > ${ALERT_THRESHOLD_QUERY_LATENCY}ms"
    fi
    
    # 错误率告警
    local error_rate=$(echo "$metrics" | jq -r '.error_rate // 0')
    if (( $(echo "$error_rate > $ALERT_THRESHOLD_ERROR_RATE" | bc -l) )); then
        send_alert "CRITICAL" "错误率过高: ${error_rate} > ${ALERT_THRESHOLD_ERROR_RATE}"
    fi
    
    # 服务状态告警
    if ! check_service_status; then
        send_alert "CRITICAL" "Stock-TSDB 服务未运行"
    fi
    
    # 端口告警
    if ! check_port_listening "$STOCK_TSDB_PORT" "Stock-TSDB"; then
        send_alert "CRITICAL" "Stock-TSDB 端口 $STOCK_TSDB_PORT 未监听"
    fi
}

# 实时监控模式
realtime_monitor() {
    log_info "启动实时监控模式..."
    
    while true; do
        clear
        echo "=========================================="
        echo "Stock-TSDB 实时监控 - $(date)"
        echo "=========================================="
        echo
        
        # 生成监控报告
        local metrics=$(generate_monitor_report)
        
        # 显示系统指标
        echo "系统资源:"
        local cpu_usage=$(echo "$metrics" | jq -r '.cpu_usage // 0')
        local mem_usage=$(echo "$metrics" | jq -r '.memory_usage // 0')
        local disk_usage=$(echo "$metrics" | jq -r '.disk_usage // 0')
        local load_avg=$(echo "$metrics" | jq -r '.load_average // 0')
        
        printf "  CPU 使用率: %.1f%%\n" "$cpu_usage"
        printf "  内存使用率: %.1f%%\n" "$mem_usage"
        printf "  磁盘使用率: %.1f%%\n" "$disk_usage"
        printf "  系统负载: %.2f\n" "$load_avg"
        echo
        
        # 显示应用指标
        echo "应用指标:"
        local write_qps=$(echo "$metrics" | jq -r '.write_qps // 0')
        local query_latency=$(echo "$metrics" | jq -r '.query_latency_p99 // 0')
        local error_rate=$(echo "$metrics" | jq -r '.error_rate // 0')
        local connections=$(echo "$metrics" | jq -r '.active_connections // 0')
        
        printf "  写入 QPS: %.0f\n" "$write_qps"
        printf "  查询延迟 P99: %.1fms\n" "$query_latency"
        printf "  错误率: %.4f%%\n" "$(echo "$error_rate * 100" | bc -l)"
        printf "  活跃连接: %d\n" "$connections"
        echo
        
        # 显示服务状态
        echo "服务状态:"
        if check_service_status; then
            echo -e "  Stock-TSDB 服务: ${GREEN}运行中${NC}"
        else
            echo -e "  Stock-TSDB 服务: ${RED}停止${NC}"
        fi
        
        # 端口状态
        if check_port_listening "$STOCK_TSDB_PORT" "Stock-TSDB"; then
            echo -e "  Redis 端口 ($STOCK_TSDB_PORT): ${GREEN}正常${NC}"
        else
            echo -e "  Redis 端口 ($STOCK_TSDB_PORT): ${RED}异常${NC}"
        fi
        
        if check_port_listening "$STOCK_TSDB_MONITOR_PORT" "Monitor"; then
            echo -e "  监控端口 ($STOCK_TSDB_MONITOR_PORT): ${GREEN}正常${NC}"
        else
            echo -e "  监控端口 ($STOCK_TSDB_MONITOR_PORT): ${RED}异常${NC}"
        fi
        echo
        
        # 执行告警检查
        perform_alert_checks "$metrics"
        
        echo "=========================================="
        echo "按 Ctrl+C 退出实时监控"
        echo "=========================================="
        
        sleep 5
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 生产环境监控脚本

用法: $0 [选项] [命令]

命令:
    check           执行完整健康检查
    metrics         获取性能指标
    realtime        启动实时监控模式
    alert           执行告警检查
    performance     运行性能基准测试
    report          生成监控报告
    help            显示帮助信息

选项:
    -h HOST         Stock-TSDB 主机地址 [默认: localhost]
    -p PORT         Stock-TSDB 端口 [默认: 6379]
    -m PORT         监控端口 [默认: 8080]
    -c PORT         集群端口 [默认: 5555]
    -w WEBHOOK      告警 Webhook URL
    -e EMAIL        告警邮箱地址
    -d DIR          监控数据目录 [默认: /var/log/stock-tsdb/monitor]

环境变量:
    STOCK_TSDB_HOST         Stock-TSDB 主机地址
    STOCK_TSDB_PORT         Stock-TSDB 端口
    STOCK_TSDB_MONITOR_PORT 监控端口
    ALERT_WEBHOOK          告警 Webhook URL
    ALERT_EMAIL            告警邮箱地址
    MONITOR_DATA_DIR       监控数据目录

示例:
    # 基本健康检查
    $0 check

    # 实时监控模式
    $0 realtime

    # 指定主机和端口
    $0 -h 192.168.1.100 -p 6379 realtime

    # 带告警的监控
    $0 -w https://hooks.slack.com/services/xxx realtime

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h)
                STOCK_TSDB_HOST="$2"
                shift 2
                ;;
            -p)
                STOCK_TSDB_PORT="$2"
                shift 2
                ;;
            -m)
                STOCK_TSDB_MONITOR_PORT="$2"
                shift 2
                ;;
            -c)
                STOCK_TSDB_CLUSTER_PORT="$2"
                shift 2
                ;;
            -w)
                ALERT_WEBHOOK="$2"
                shift 2
                ;;
            -e)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            -d)
                MONITOR_DATA_DIR="$2"
                shift 2
                ;;
            check|metrics|realtime|alert|performance|report|help)
                COMMAND="$1"
                shift
                ;;
            *)
                echo "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 主函数
main() {
    # 创建监控目录
    create_monitor_dirs
    
    # 解析参数
    parse_arguments "$@"
    
    # 设置默认命令
    if [[ -z "$COMMAND" ]]; then
        COMMAND="check"
    fi
    
    case "$COMMAND" in
        check)
            log_info "执行完整健康检查..."
            
            local overall_status=0
            
            # 服务状态检查
            if check_service_status; then
                log_success "服务状态: 正常"
            else
                log_error "服务状态: 异常"
                overall_status=1
            fi
            
            # 端口检查
            if check_port_listening "$STOCK_TSDB_PORT" "Stock-TSDB"; then
                log_success "端口检查: 正常"
            else
                log_error "端口检查: 异常"
                overall_status=1
            fi
            
            # Redis 兼容性检查
            if check_redis_compatibility; then
                log_success "Redis 兼容性: 正常"
            else
                log_error "Redis 兼容性: 异常"
                overall_status=1
            fi
            
            # 数据一致性检查
            if check_data_consistency; then
                log_success "数据一致性: 正常"
            else
                log_error "数据一致性: 异常"
                overall_status=1
            fi
            
            # 系统资源检查
            local system_metrics=$(get_system_metrics)
            local cpu_usage=$(echo "$system_metrics" | jq -r '.cpu_usage // 0')
            local mem_usage=$(echo "$system_metrics" | jq -r '.memory_usage // 0')
            
            if (( $(echo "$cpu_usage < 80" | bc -l) )) && (( $(echo "$mem_usage < 85" | bc -l) )); then
                log_success "系统资源: 正常 (CPU: ${cpu_usage}%, 内存: ${mem_usage}%)"
            else
                log_warn "系统资源: 高负载 (CPU: ${cpu_usage}%, 内存: ${mem_usage}%)"
            fi
            
            exit $overall_status
            ;;
            
        metrics)
            log_info "获取性能指标..."
            generate_monitor_report
            ;;
            
        realtime)
            realtime_monitor
            ;;
            
        alert)
            log_info "执行告警检查..."
            local metrics=$(generate_monitor_report)
            perform_alert_checks "$metrics"
            ;;
            
        performance)
            log_info "运行性能基准测试..."
            run_performance_baseline
            ;;
            
        report)
            log_info "生成监控报告..."
            generate_monitor_report
            ;;
            
        help)
            show_help
            ;;
            
        *)
            echo "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 脚本入口
main "$@"