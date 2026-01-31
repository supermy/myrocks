#!/bin/bash

# Stock-TSDB 生产环境维护脚本
# 提供系统维护、性能优化和故障排除功能

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
DATA_DIR="${DATA_DIR:-/var/lib/stock-tsdb}"
CONFIG_DIR="${CONFIG_DIR:-/etc/stock-tsdb}"
LOG_DIR="${LOG_DIR:-/var/log/stock-tsdb}"
BACKUP_DIR="${BACKUP_DIR:-/var/backup/stock-tsdb}"

# 维护配置
MAINTENANCE_LOG_RETENTION_DAYS="${MAINTENANCE_LOG_RETENTION_DAYS:-90}"
MAX_LOG_SIZE_MB="${MAX_LOG_SIZE_MB:-100}"
COMPACTION_THRESHOLD_PERCENT="${COMPACTION_THRESHOLD_PERCENT:-80}"
DISK_CLEANUP_THRESHOLD_PERCENT="${DISK_CLEANUP_THRESHOLD_PERCENT:-85}"

# 性能调优配置
OPTIMIZE_MEMORY_PERCENT="${OPTIMIZE_MEMORY_PERCENT:-70}"
OPTIMIZE_CPU_CORES="${OPTIMIZE_CPU_CORES:-auto}"
OPTIMIZE_DISK_TYPE="${OPTIMIZE_DISK_TYPE:-ssd}"

# 日志文件
MAINTENANCE_LOG="$LOG_DIR/maintenance.log"
HEALTH_CHECK_LOG="$LOG_DIR/health_check.log"
PERFORMANCE_LOG="$LOG_DIR/performance.log"

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$MAINTENANCE_LOG"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1" | tee -a "$MAINTENANCE_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$MAINTENANCE_LOG"
}

log_debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG]${NC} $1" | tee -a "$MAINTENANCE_LOG"
}

# 检查系统依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查必需的工具
    local required_tools=("find" "du" "df" "tar" "gzip" "systemctl" "journalctl")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # 检查可选工具
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必需的工具: ${missing_deps[*]}"
        return 1
    fi
    
    log_debug "所有依赖检查通过"
    return 0
}

# 检查服务状态
check_service_status() {
    local service_name="stock-tsdb"
    
    if systemctl is-active --quiet "$service_name"; then
        local service_status=$(systemctl is-active "$service_name")
        local service_uptime=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value)
        
        log_info "服务状态: $service_status (启动时间: $service_uptime)"
        return 0
    else
        log_error "服务未运行"
        return 1
    fi
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # CPU 使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    log_info "CPU 使用率: ${cpu_usage}%"
    
    # 内存使用率
    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local used_mem=$(free -m | grep Mem | awk '{print $3}')
    local mem_usage=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc -l)
    log_info "内存使用率: ${mem_usage}% (${used_mem}MB / ${total_mem}MB)"
    
    # 磁盘使用率
    local data_disk_usage=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    local log_disk_usage=$(df -h "$LOG_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log_info "数据磁盘使用率: ${data_disk_usage}%"
    log_info "日志磁盘使用率: ${log_disk_usage}%"
    
    # 检查是否超过阈值
    if [[ $data_disk_usage -gt $DISK_CLEANUP_THRESHOLD_PERCENT ]]; then
        log_warn "数据磁盘使用率超过阈值: ${data_disk_usage}% > ${DISK_CLEANUP_THRESHOLD_PERCENT}%"
        return 1
    fi
    
    if [[ $log_disk_usage -gt $DISK_CLEANUP_THRESHOLD_PERCENT ]]; then
        log_warn "日志磁盘使用率超过阈值: ${log_disk_usage}% > ${DISK_CLEANUP_THRESHOLD_PERCENT}%"
        return 1
    fi
    
    return 0
}

# 检查数据目录一致性
check_data_consistency() {
    log_info "检查数据目录一致性..."
    
    if [[ ! -d "$DATA_DIR" ]]; then
        log_error "数据目录不存在: $DATA_DIR"
        return 1
    fi
    
    # 检查 RocksDB 文件
    local rocksdb_files=$(find "$DATA_DIR" -name "*.sst" -o -name "*.log" -o -name "CURRENT" -o -name "MANIFEST-*" 2>/dev/null | wc -l)
    
    if [[ $rocksdb_files -eq 0 ]]; then
        log_warn "未找到 RocksDB 数据文件"
        return 1
    fi
    
    log_info "找到 $rocksdb_files 个 RocksDB 数据文件"
    
    # 检查文件权限
    local wrong_permissions=$(find "$DATA_DIR" -type f ! -perm 644 2>/dev/null | wc -l)
    if [[ $wrong_permissions -gt 0 ]]; then
        log_warn "发现 $wrong_permissions 个文件权限异常"
    fi
    
    # 检查目录权限
    local wrong_dir_permissions=$(find "$DATA_DIR" -type d ! -perm 755 2>/dev/null | wc -l)
    if [[ $wrong_dir_permissions -gt 0 ]]; then
        log_warn "发现 $wrong_dir_permissions 个目录权限异常"
    fi
    
    return 0
}

# 检查日志文件
check_log_files() {
    log_info "检查日志文件..."
    
    if [[ ! -d "$LOG_DIR" ]]; then
        log_error "日志目录不存在: $LOG_DIR"
        return 1
    fi
    
    # 检查日志文件大小
    local large_logs=$(find "$LOG_DIR" -name "*.log" -type f -size +${MAX_LOG_SIZE_MB}M 2>/dev/null)
    
    if [[ -n "$large_logs" ]]; then
        log_warn "发现大日志文件:"
        echo "$large_logs" | while read -r logfile; do
            local size=$(du -h "$logfile" | cut -f1)
            log_warn "  $logfile ($size)"
        done
    fi
    
    # 检查日志轮转
    local log_files=$(find "$LOG_DIR" -name "*.log" -type f | wc -l)
    log_info "日志文件数量: $log_files"
    
    # 检查最近的错误
    local recent_errors=$(journalctl -u stock-tsdb --since "1 hour ago" --no-pager -q | grep -i error | wc -l)
    if [[ $recent_errors -gt 0 ]]; then
        log_warn "最近1小时发现 $recent_errors 个错误日志"
    fi
    
    return 0
}

# 清理过期日志
cleanup_old_logs() {
    log_info "清理过期日志文件..."
    
    local deleted_count=0
    
    # 删除过期日志文件
    while IFS= read -r -d '' logfile; do
        if rm -f "$logfile" 2>/dev/null; then
            deleted_count=$((deleted_count + 1))
            log_debug "删除日志文件: $(basename "$logfile")"
        fi
    done < <(find "$LOG_DIR" -name "*.log" -type f -mtime +$MAINTENANCE_LOG_RETENTION_DAYS -print0 2>/dev/null)
    
    # 清理压缩的旧日志
    while IFS= read -r -d '' logfile; do
        if rm -f "$logfile" 2>/dev/null; then
            deleted_count=$((deleted_count + 1))
            log_debug "删除压缩日志文件: $(basename "$logfile")"
        fi
    done < <(find "$LOG_DIR" -name "*.gz" -type f -mtime +$MAINTENANCE_LOG_RETENTION_DAYS -print0 2>/dev/null)
    
    # 清理空的日志目录
    find "$LOG_DIR" -type d -empty -delete 2>/dev/null || true
    
    log_info "清理完成，删除 $deleted_count 个过期日志文件"
    return 0
}

# 压缩大日志文件
compress_large_logs() {
    log_info "压缩大日志文件..."
    
    local compressed_count=0
    
    # 压缩大日志文件
    while IFS= read -r -d '' logfile; do
        if gzip "$logfile" 2>/dev/null; then
            compressed_count=$((compressed_count + 1))
            log_debug "压缩日志文件: $(basename "$logfile")"
        fi
    done < <(find "$LOG_DIR" -name "*.log" -type f -size +${MAX_LOG_SIZE_MB}M -mtime +1 -print0 2>/dev/null)
    
    log_info "压缩完成，处理 $compressed_count 个大日志文件"
    return 0
}

# 检查磁盘空间
check_disk_space() {
    log_info "检查磁盘空间..."
    
    local data_disk_usage=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    local log_disk_usage=$(df -h "$LOG_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log_info "数据磁盘使用率: ${data_disk_usage}%"
    log_info "日志磁盘使用率: ${log_disk_usage}%"
    
    if [[ $data_disk_usage -gt $DISK_CLEANUP_THRESHOLD_PERCENT ]]; then
        log_error "数据磁盘使用率过高: ${data_disk_usage}% > ${DISK_CLEANUP_THRESHOLD_PERCENT}%"
        return 1
    fi
    
    if [[ $log_disk_usage -gt $DISK_CLEANUP_THRESHOLD_PERCENT ]]; then
        log_error "日志磁盘使用率过高: ${log_disk_usage}% > ${DISK_CLEANUP_THRESHOLD_PERCENT}%"
        return 1
    fi
    
    return 0
}

# 清理临时文件
cleanup_temp_files() {
    log_info "清理临时文件..."
    
    local temp_dirs=(
        "/tmp/stock-tsdb-*"
        "/var/tmp/stock-tsdb-*"
        "$DATA_DIR/tmp"
        "$LOG_DIR/tmp"
    )
    
    local deleted_count=0
    
    for temp_pattern in "${temp_dirs[@]}"; do
        while IFS= read -r -d '' temp_file; do
            if rm -rf "$temp_file" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                log_debug "删除临时文件/目录: $(basename "$temp_file")"
            fi
        done < <(find "$(dirname "$temp_pattern")" -name "$(basename "$temp_pattern")" -type f -mtime +1 -print0 2>/dev/null)
    done
    
    log_info "清理完成，删除 $deleted_count 个临时文件"
    return 0
}

# 检查系统健康状态
perform_health_check() {
    log_info "执行系统健康检查..."
    
    local health_score=100
    local issues=()
    
    # 检查服务状态
    if ! check_service_status; then
        health_score=$((health_score - 20))
        issues+=("服务未运行")
    fi
    
    # 检查系统资源
    if ! check_system_resources; then
        health_score=$((health_score - 15))
        issues+=("系统资源不足")
    fi
    
    # 检查数据一致性
    if ! check_data_consistency; then
        health_score=$((health_score - 15))
        issues+=("数据一致性问题")
    fi
    
    # 检查日志文件
    if ! check_log_files; then
        health_score=$((health_score - 10))
        issues+=("日志文件异常")
    fi
    
    # 检查磁盘空间
    if ! check_disk_space; then
        health_score=$((health_score - 20))
        issues+=("磁盘空间不足")
    fi
    
    # 输出健康报告
    echo "=========================================="
    echo "系统健康检查报告"
    echo "=========================================="
    echo "检查时间: $(date)"
    echo "健康评分: $health_score/100"
    echo
    
    if [[ $health_score -ge 90 ]]; then
        echo -e "整体状态: ${GREEN}优秀${NC}"
    elif [[ $health_score -ge 70 ]]; then
        echo -e "整体状态: ${YELLOW}良好${NC}"
    elif [[ $health_score -ge 50 ]]; then
        echo -e "整体状态: ${YELLOW}警告${NC}"
    else
        echo -e "整体状态: ${RED}严重${NC}"
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        echo
        echo "发现的问题:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
    fi
    
    echo "=========================================="
    
    # 记录到健康检查日志
    {
        echo "$(date '+%Y-%m-%d %H:%M:%S') Health Check Score: $health_score/100"
        if [[ ${#issues[@]} -gt 0 ]]; then
            for issue in "${issues[@]}"; do
                echo "  Issue: $issue"
            done
        fi
    } >> "$HEALTH_CHECK_LOG"
    
    return 0
}

# 性能优化建议
performance_optimization() {
    log_info "分析性能优化建议..."
    
    local recommendations=()
    
    # 内存优化建议
    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local available_mem=$(free -m | grep Mem | awk '{print $7}')
    local mem_usage_percent=$(echo "scale=1; ($total_mem - $available_mem) * 100 / $total_mem" | bc -l)
    
    if (( $(echo "$mem_usage_percent > $OPTIMIZE_MEMORY_PERCENT" | bc -l) )); then
        recommendations+=("内存使用率过高 (${mem_usage_percent}%)，建议增加内存或优化内存使用")
    fi
    
    # CPU 优化建议
    local cpu_cores=$(nproc)
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    if (( $(echo "$load_avg > $cpu_cores" | bc -l) )); then
        recommendations+=("系统负载过高 (${load_avg} > ${cpu_cores})，建议优化 CPU 使用")
    fi
    
    # 磁盘优化建议
    local disk_type="$OPTIMIZE_DISK_TYPE"
    local data_disk_usage=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [[ $disk_type == "hdd" ]]; then
        recommendations+=("当前使用机械硬盘，建议升级到 SSD 以提高性能")
    fi
    
    if [[ $data_disk_usage -gt 80 ]]; then
        recommendations+=("数据磁盘使用率较高 (${data_disk_usage}%)，建议清理旧数据或扩容")
    fi
    
    # 配置优化建议
    local config_file="$CONFIG_DIR/stock-tsdb.conf"
    if [[ -f "$config_file" ]]; then
        # 检查配置参数
        local max_connections=$(grep "^max_connections" "$config_file" 2>/dev/null | awk '{print $3}' || echo "1000")
        local write_buffer_size=$(grep "^write_buffer_size" "$config_file" 2>/dev/null | awk '{print $3}' || echo "64MB")
        
        if [[ $max_connections -lt 100 ]]; then
            recommendations+=("最大连接数设置较低 ($max_connections)，建议根据实际需求调整")
        fi
    fi
    
    # 输出优化建议
    echo "=========================================="
    echo "性能优化建议"
    echo "=========================================="
    echo "分析时间: $(date)"
    echo
    
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo "优化建议:"
        for i in "${!recommendations[@]}"; do
            echo "$((i+1)). ${recommendations[$i]}"
        done
    else
        echo "当前系统性能良好，暂无优化建议"
    fi
    
    echo "=========================================="
    
    # 记录到性能日志
    {
        echo "$(date '+%Y-%m-%d %H:%M:%S') Performance Analysis:"
        if [[ ${#recommendations[@]} -gt 0 ]]; then
            for recommendation in "${recommendations[@]}"; do
                echo "  Recommendation: $recommendation"
            done
        else
            echo "  No optimization recommendations"
        fi
    } >> "$PERFORMANCE_LOG"
    
    return 0
}

# 系统信息收集
collect_system_info() {
    log_info "收集系统信息..."
    
    local info_file="$LOG_DIR/system_info_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Stock-TSDB 系统信息报告"
        echo "生成时间: $(date)"
        echo "=========================================="
        echo
        
        echo "系统信息:"
        echo "  主机名: $(hostname)"
        echo "  操作系统: $(uname -s)"
        echo "  内核版本: $(uname -r)"
        echo "  架构: $(uname -m)"
        echo "  运行时间: $(uptime -p)"
        echo
        
        echo "硬件信息:"
        echo "  CPU 核心数: $(nproc)"
        echo "  CPU 型号: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
        echo "  总内存: $(free -h | grep Mem | awk '{print $2}')"
        echo "  可用内存: $(free -h | grep Mem | awk '{print $7}')"
        echo "  交换空间: $(free -h | grep Swap | awk '{print $2}')"
        echo
        
        echo "磁盘信息:"
        df -h | grep -E "(Filesystem|$DATA_DIR|$LOG_DIR)" | while read -r line; do
            echo "  $line"
        done
        echo
        
        echo "服务信息:"
        if systemctl is-active --quiet stock-tsdb; then
            echo "  服务状态: 运行中"
            echo "  服务版本: $(stock-tsdb-server --version 2>/dev/null || echo 'unknown')"
            echo "  启动时间: $(systemctl show stock-tsdb --property=ActiveEnterTimestamp --value)"
            echo "  进程ID: $(pgrep -f stock-tsdb-server || echo 'unknown')"
        else
            echo "  服务状态: 停止"
        fi
        echo
        
        echo "数据目录信息:"
        if [[ -d "$DATA_DIR" ]]; then
            echo "  数据目录: $DATA_DIR"
            echo "  目录大小: $(du -sh "$DATA_DIR" | cut -f1)"
            echo "  文件数量: $(find "$DATA_DIR" -type f | wc -l)"
            echo "  RocksDB文件: $(find "$DATA_DIR" -name '*.sst' -o -name '*.log' | wc -l)"
        else
            echo "  数据目录: 不存在"
        fi
        echo
        
        echo "配置信息:"
        if [[ -f "$CONFIG_DIR/stock-tsdb.conf" ]]; then
            echo "  配置文件: $CONFIG_DIR/stock-tsdb.conf"
            echo "  配置大小: $(stat -c%s "$CONFIG_DIR/stock-tsdb.conf") bytes"
            echo "  最近修改: $(stat -c%y "$CONFIG_DIR/stock-tsdb.conf")"
        else
            echo "  配置文件: 不存在"
        fi
        echo
        
        echo "日志信息:"
        if [[ -d "$LOG_DIR" ]]; then
            echo "  日志目录: $LOG_DIR"
            echo "  目录大小: $(du -sh "$LOG_DIR" | cut -f1)"
            echo "  日志文件: $(find "$LOG_DIR" -name '*.log' | wc -l)"
            echo "  压缩日志: $(find "$LOG_DIR" -name '*.gz' | wc -l)"
        else
            echo "  日志目录: 不存在"
        fi
        echo
        
        echo "网络信息:"
        echo "  监听端口:"
        netstat -tuln | grep -E ":6379|:8080|:5555" | while read -r line; do
            echo "    $line"
        done
        echo
        
        echo "系统负载:"
        echo "  负载平均值: $(uptime | awk -F'load average:' '{print $2}')"
        echo "  CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
        echo "  内存使用率: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
        echo
        
        echo "进程信息:"
        ps aux | grep -E "(stock-tsdb|rocksdb)" | grep -v grep | while read -r line; do
            echo "  $line"
        done
        
    } > "$info_file"
    
    log_info "系统信息已收集到: $info_file"
    echo "系统信息报告已生成: $info_file"
    return 0
}

# 故障排除模式
troubleshooting_mode() {
    log_info "启动故障排除模式..."
    
    echo "=========================================="
    echo "Stock-TSDB 故障排除"
    echo "=========================================="
    
    # 检查基本服务状态
    echo "1. 检查服务状态:"
    if systemctl is-active --quiet stock-tsdb; then
        echo -e "   ${GREEN}✓${NC} 服务正在运行"
    else
        echo -e "   ${RED}✗${NC} 服务未运行"
        echo "   尝试启动服务: systemctl start stock-tsdb"
    fi
    echo
    
    # 检查端口监听
    echo "2. 检查端口监听:"
    local ports=("6379" "8080" "5555")
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            echo -e "   ${GREEN}✓${NC} 端口 $port 正在监听"
        else
            echo -e "   ${RED}✗${NC} 端口 $port 未监听"
        fi
    done
    echo
    
    # 检查磁盘空间
    echo "3. 检查磁盘空间:"
    local data_usage=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}')
    local log_usage=$(df -h "$LOG_DIR" | tail -1 | awk '{print $5}')
    
    echo "   数据磁盘使用率: $data_usage"
    echo "   日志磁盘使用率: $log_usage"
    echo
    
    # 检查内存使用
    echo "4. 检查内存使用:"
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
    echo "   内存使用率: $mem_usage"
    echo
    
    # 检查最近的错误
    echo "5. 检查最近的错误:"
    local recent_errors=$(journalctl -u stock-tsdb --since "1 hour ago" --no-pager -q | grep -i error | tail -5)
    if [[ -n "$recent_errors" ]]; then
        echo "$recent_errors" | while read -r line; do
            echo "   $line"
        done
    else
        echo "   最近1小时未发现错误"
    fi
    echo
    
    # 检查配置文件
    echo "6. 检查配置文件:"
    if [[ -f "$CONFIG_DIR/stock-tsdb.conf" ]]; then
        if stock-tsdb-server --check-config "$CONFIG_DIR/stock-tsdb.conf" 2>/dev/null; then
            echo -e "   ${GREEN}✓${NC} 配置文件语法正确"
        else
            echo -e "   ${RED}✗${NC} 配置文件存在语法错误"
        fi
    else
        echo -e "   ${RED}✗${NC} 配置文件不存在"
    fi
    echo
    
    # 检查数据目录
    echo "7. 检查数据目录:"
    if [[ -d "$DATA_DIR" ]]; then
        local data_files=$(find "$DATA_DIR" -name "*.sst" -o -name "*.log" -o -name "CURRENT" | wc -l)
        echo "   数据文件数量: $data_files"
        
        if [[ $data_files -gt 0 ]]; then
            echo -e "   ${GREEN}✓${NC} 数据目录正常"
        else
            echo -e "   ${YELLOW}!${NC} 数据目录为空或损坏"
        fi
    else
        echo -e "   ${RED}✗${NC} 数据目录不存在"
    fi
    echo
    
    # 提供解决方案
    echo "建议的解决方案:"
    echo "=========================================="
    
    if ! systemctl is-active --quiet stock-tsdb; then
        echo "• 服务未运行，尝试:"
        echo "  systemctl start stock-tsdb"
        echo "  systemctl status stock-tsdb"
        echo
    fi
    
    local data_usage_num=$(df -h "$DATA_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $data_usage_num -gt 90 ]]; then
        echo "• 磁盘空间不足，尝试:"
        echo "  清理旧数据: find $DATA_DIR -name '*.old' -delete"
        echo "  扩容磁盘或迁移数据"
        echo
    fi
    
    local mem_usage_num=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $mem_usage_num -gt 90 ]]; then
        echo "• 内存使用率过高，尝试:"
        echo "  重启服务: systemctl restart stock-tsdb"
        echo "  增加物理内存"
        echo
    fi
    
    echo "• 查看详细日志:"
    echo "  journalctl -u stock-tsdb -f"
    echo "  tail -f $LOG_DIR/stock-tsdb.log"
    echo
    
    echo "• 检查配置文件:"
    echo "  stock-tsdb-server --check-config $CONFIG_DIR/stock-tsdb.conf"
    echo
    
    echo "• 验证数据完整性:"
    echo "  $0 check-data"
    echo
    
    echo "• 重启服务:"
    echo "  systemctl restart stock-tsdb"
    echo
    
    return 0
}

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 生产环境维护脚本

用法: $0 [选项] [命令]

命令:
    health-check        执行健康检查
    cleanup-logs        清理过期日志
    compress-logs       压缩大日志文件
    check-resources     检查系统资源
    check-disk          检查磁盘空间
    cleanup-temp        清理临时文件
    performance         性能优化建议
    system-info         收集系统信息
    troubleshoot        故障排除模式
    full-maintenance    执行完整维护
    help                显示帮助信息

选项:
    -d DIR              数据目录 [默认: /var/lib/stock-tsdb]
    -c DIR              配置目录 [默认: /etc/stock-tsdb]
    -l DIR              日志目录 [默认: /var/log/stock-tsdb]
    -r DAYS             日志保留天数 [默认: 90]
    -s MB               最大日志文件大小(MB) [默认: 100]
    -t PERCENT          磁盘清理阈值 [默认: 85]

环境变量:
    DATA_DIR                    数据目录
    CONFIG_DIR                  配置目录
    LOG_DIR                     日志目录
    MAINTENANCE_LOG_RETENTION_DAYS 日志保留天数
    MAX_LOG_SIZE_MB             最大日志文件大小
    DISK_CLEANUP_THRESHOLD_PERCENT 磁盘清理阈值

示例:
    # 执行健康检查
    $0 health-check

    # 清理过期日志
    $0 cleanup-logs

    # 执行完整维护
    $0 full-maintenance

    # 故障排除模式
    $0 troubleshoot

    # 性能优化建议
    $0 performance

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d)
                DATA_DIR="$2"
                shift 2
                ;;
            -c)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -l)
                LOG_DIR="$2"
                shift 2
                ;;
            -r)
                MAINTENANCE_LOG_RETENTION_DAYS="$2"
                shift 2
                ;;
            -s)
                MAX_LOG_SIZE_MB="$2"
                shift 2
                ;;
            -t)
                DISK_CLEANUP_THRESHOLD_PERCENT="$2"
                shift 2
                ;;
            health-check|cleanup-logs|compress-logs|check-resources|check-disk|cleanup-temp|performance|system-info|troubleshoot|full-maintenance|help)
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

# 执行完整维护
perform_full_maintenance() {
    log_info "开始执行完整维护..."
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 1. 健康检查
    log_info "步骤 1/8: 健康检查"
    perform_health_check
    echo
    
    # 2. 系统资源检查
    log_info "步骤 2/8: 系统资源检查"
    check_system_resources
    echo
    
    # 3. 磁盘空间检查
    log_info "步骤 3/8: 磁盘空间检查"
    check_disk_space
    echo
    
    # 4. 数据一致性检查
    log_info "步骤 4/8: 数据一致性检查"
    check_data_consistency
    echo
    
    # 5. 日志文件检查
    log_info "步骤 5/8: 日志文件检查"
    check_log_files
    echo
    
    # 6. 清理过期日志
    log_info "步骤 6/8: 清理过期日志"
    cleanup_old_logs
    echo
    
    # 7. 压缩大日志文件
    log_info "步骤 7/8: 压缩大日志文件"
    compress_large_logs
    echo
    
    # 8. 清理临时文件
    log_info "步骤 8/8: 清理临时文件"
    cleanup_temp_files
    echo
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "完整维护完成"
    log_info "开始时间: $start_time"
    log_info "结束时间: $end_time"
    
    # 性能优化建议
    performance_optimization
    
    return 0
}

# 主函数
main() {
    # 检查依赖
    if ! check_dependencies; then
        exit 1
    fi
    
    # 创建必要的日志文件
    touch "$MAINTENANCE_LOG" "$HEALTH_CHECK_LOG" "$PERFORMANCE_LOG"
    chmod 640 "$MAINTENANCE_LOG" "$HEALTH_CHECK_LOG" "$PERFORMANCE_LOG"
    
    # 解析参数
    parse_arguments "$@"
    
    # 设置默认命令
    if [[ -z "$COMMAND" ]]; then
        COMMAND="health-check"
    fi
    
    case "$COMMAND" in
        health-check)
            perform_health_check
            ;;
            
        cleanup-logs)
            cleanup_old_logs
            ;;
            
        compress-logs)
            compress_large_logs
            ;;
            
        check-resources)
            check_system_resources
            ;;
            
        check-disk)
            check_disk_space
            ;;
            
        cleanup-temp)
            cleanup_temp_files
            ;;
            
        performance)
            performance_optimization
            ;;
            
        system-info)
            collect_system_info
            ;;
            
        troubleshoot)
            troubleshooting_mode
            ;;
            
        full-maintenance)
            perform_full_maintenance
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