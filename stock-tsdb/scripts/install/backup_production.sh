#!/bin/bash

# Stock-TSDB 生产环境备份脚本
# 提供数据备份、恢复和管理功能

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
BACKUP_DIR="${BACKUP_DIR:-/var/backup/stock-tsdb}"
DATA_DIR="${DATA_DIR:-/var/lib/stock-tsdb}"
CONFIG_DIR="${CONFIG_DIR:-/etc/stock-tsdb}"
LOG_DIR="${LOG_DIR:-/var/log/stock-tsdb}"

# 备份配置
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION_LEVEL="${BACKUP_COMPRESSION_LEVEL:-6}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-}"
BACKUP_REMOTE_PATH="${BACKUP_REMOTE_PATH:-}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-}"

# 数据库配置
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-6379}"
DB_PASSWORD="${DB_PASSWORD:-}"

# 通知配置
BACKUP_NOTIFICATION_EMAIL="${BACKUP_NOTIFICATION_EMAIL:-}"
BACKUP_NOTIFICATION_WEBHOOK="${BACKUP_NOTIFICATION_WEBHOOK:-}"

# 日志文件
BACKUP_LOG="$BACKUP_DIR/backup.log"
RESTORE_LOG="$BACKUP_DIR/restore.log"

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $1" | tee -a "$BACKUP_LOG"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $1" | tee -a "$BACKUP_LOG"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" | tee -a "$BACKUP_LOG"
}

log_debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG]${NC} $1" | tee -a "$BACKUP_LOG"
}

# 创建备份目录
create_backup_dirs() {
    mkdir -p "$BACKUP_DIR"/{full,incremental,config,logs,metadata}
    chmod 750 "$BACKUP_DIR"
    
    # 创建备份日志文件
    touch "$BACKUP_LOG" "$RESTORE_LOG"
    chmod 640 "$BACKUP_LOG" "$RESTORE_LOG"
}

# 检查系统依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查必需的工具
    local required_tools=("tar" "gzip" "date" "find" "du" "stat")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_deps+=("$tool")
        fi
    done
    
    # 检查可选工具
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        if ! command -v "openssl" >/dev/null 2>&1; then
            missing_deps+=("openssl")
        fi
    fi
    
    if [[ -n "$BACKUP_REMOTE_HOST" ]]; then
        if ! command -v "rsync" >/dev/null 2>&1; then
            missing_deps+=("rsync")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必需的工具: ${missing_deps[*]}"
        return 1
    fi
    
    log_debug "所有依赖检查通过"
    return 0
}

# 检查磁盘空间
check_disk_space() {
    local required_space_mb="$1"
    local backup_partition=$(df -m "$BACKUP_DIR" | tail -1 | awk '{print $4}')
    
    if [[ $backup_partition -lt $required_space_mb ]]; then
        log_error "备份分区空间不足: 需要 ${required_space_mb}MB，可用 ${backup_partition}MB"
        return 1
    fi
    
    log_debug "磁盘空间检查通过: 可用 ${backup_partition}MB"
    return 0
}

# 获取数据目录大小
get_data_size() {
    if [[ -d "$DATA_DIR" ]]; then
        local size_bytes=$(du -sb "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
        local size_mb=$((size_bytes / 1024 / 1024))
        echo "$size_mb"
    else
        echo "0"
    fi
}

# 停止服务（如果需要）
stop_service_if_needed() {
    local backup_type="$1"
    
    # 对于全量备份，建议停止服务以确保数据一致性
    if [[ "$backup_type" == "full" ]]; then
        log_info "正在停止 Stock-TSDB 服务以进行一致性备份..."
        
        if systemctl is-active --quiet stock-tsdb; then
            systemctl stop stock-tsdb
            
            # 等待服务完全停止
            local max_wait=30
            local waited=0
            while systemctl is-active --quiet stock-tsdb && [[ $waited -lt $max_wait ]]; do
                sleep 1
                waited=$((waited + 1))
            done
            
            if systemctl is-active --quiet stock-tsdb; then
                log_error "服务停止超时"
                return 1
            fi
            
            log_info "服务已停止"
            return 0
        else
            log_info "服务当前未运行"
            return 0
        fi
    else
        log_info "增量备份，无需停止服务"
        return 0
    fi
}

# 启动服务
start_service() {
    log_info "正在启动 Stock-TSDB 服务..."
    
    if systemctl is-active --quiet stock-tsdb; then
        log_info "服务已在运行"
        return 0
    fi
    
    systemctl start stock-tsdb
    
    # 等待服务启动
    local max_wait=60
    local waited=0
    while ! systemctl is-active --quiet stock-tsdb && [[ $waited -lt $max_wait ]]; do
        sleep 1
        waited=$((waited + 1))
    done
    
    if systemctl is-active --quiet stock-tsdb; then
        log_info "服务已启动"
        return 0
    else
        log_error "服务启动失败"
        return 1
    fi
}

# 创建备份元数据
create_backup_metadata() {
    local backup_name="$1"
    local backup_type="$2"
    local backup_size="$3"
    local start_time="$4"
    local end_time="$5"
    
    local metadata_file="$BACKUP_DIR/metadata/${backup_name}.json"
    local hostname=$(hostname)
    local stock_tsdb_version=$(stock-tsdb-server --version 2>/dev/null || echo "unknown")
    
    cat > "$metadata_file" << EOF
{
    "backup_name": "$backup_name",
    "backup_type": "$backup_type",
    "hostname": "$hostname",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "start_time": "$start_time",
    "end_time": "$end_time",
    "duration_seconds": $(($(date -d "$end_time" +%s) - $(date -d "$start_time" +%s))),
    "backup_size_bytes": $backup_size,
    "backup_size_human": "$(numfmt --to=iec-i --suffix=B "$backup_size" 2>/dev/null || echo "${backup_size}B")",
    "data_directory": "$DATA_DIR",
    "config_directory": "$CONFIG_DIR",
    "backup_directory": "$BACKUP_DIR",
    "stock_tsdb_version": "$stock_tsdb_version",
    "compression_level": $BACKUP_COMPRESSION_LEVEL,
    "encryption_enabled": $([[ -n "$BACKUP_ENCRYPTION_KEY" ]] && echo "true" || echo "false"),
    "remote_backup_enabled": $([[ -n "$BACKUP_REMOTE_HOST" ]] && echo "true" || echo "false"),
    "system_info": {
        "os": "$(uname -s)",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "total_memory": "$(free -h | grep Mem | awk '{print $2}')",
        "cpu_cores": "$(nproc)"
    }
}
EOF
    
    chmod 640 "$metadata_file"
    log_debug "备份元数据已创建: $metadata_file"
}

# 压缩备份文件
compress_backup() {
    local source_file="$1"
    local target_file="$2"
    
    log_info "正在压缩备份文件..."
    
    if gzip -"$BACKUP_COMPRESSION_LEVEL" -c "$source_file" > "$target_file"; then
        local original_size=$(stat -c%s "$source_file")
        local compressed_size=$(stat -c%s "$target_file")
        local compression_ratio=$(echo "scale=2; ($original_size - $compressed_size) * 100 / $original_size" | bc -l)
        
        log_info "压缩完成: 原始大小 $(numfmt --to=iec-i --suffix=B "$original_size")，压缩大小 $(numfmt --to=iec-i --suffix=B "$compressed_size")，压缩率 ${compression_ratio}%"
        
        # 删除原始文件
        rm -f "$source_file"
        
        return 0
    else
        log_error "压缩失败"
        return 1
    fi
}

# 加密备份文件
encrypt_backup() {
    local source_file="$1"
    local target_file="$2"
    
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        log_info "正在加密备份文件..."
        
        if openssl enc -aes-256-cbc -salt -in "$source_file" -out "$target_file" -pass pass:"$BACKUP_ENCRYPTION_KEY"; then
            log_info "加密完成"
            
            # 删除未加密的文件
            rm -f "$source_file"
            
            return 0
        else
            log_error "加密失败"
            return 1
        fi
    else
        log_debug "未启用加密"
        return 0
    fi
}

# 上传远程备份
upload_remote_backup() {
    local local_file="$1"
    local remote_file="$2"
    
    if [[ -n "$BACKUP_REMOTE_HOST" && -n "$BACKUP_REMOTE_PATH" ]]; then
        log_info "正在上传备份到远程服务器..."
        
        local remote_target="$BACKUP_REMOTE_USER@$BACKUP_REMOTE_HOST:$BACKUP_REMOTE_PATH/$(basename "$remote_file")"
        
        if rsync -avz --progress "$local_file" "$remote_target"; then
            log_info "远程备份上传完成: $remote_target"
            return 0
        else
            log_error "远程备份上传失败"
            return 1
        fi
    else
        log_debug "未配置远程备份"
        return 0
    fi
}

# 发送备份通知
send_backup_notification() {
    local backup_name="$1"
    local backup_type="$2"
    local status="$3"
    local message="$4"
    local metadata_file="$5"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    
    # 邮件通知
    if [[ -n "$BACKUP_NOTIFICATION_EMAIL" ]]; then
        {
            echo "Subject: [Stock-TSDB] 备份 $status - $backup_name"
            echo "From: stock-tsdb@$hostname"
            echo "To: $BACKUP_NOTIFICATION_EMAIL"
            echo
            echo "备份信息:"
            echo "  备份名称: $backup_name"
            echo "  备份类型: $backup_type"
            echo "  状态: $status"
            echo "  时间: $timestamp"
            echo "  主机: $hostname"
            echo "  消息: $message"
            echo
            if [[ -f "$metadata_file" ]]; then
                echo "详细元数据:"
                cat "$metadata_file"
            fi
        } | sendmail "$BACKUP_NOTIFICATION_EMAIL" 2>/dev/null || log_warn "邮件发送失败"
    fi
    
    # Webhook 通知
    if [[ -n "$BACKUP_NOTIFICATION_WEBHOOK" ]]; then
        local payload=$(cat << EOF
{
    "event": "backup_$status",
    "backup_name": "$backup_name",
    "backup_type": "$backup_type",
    "timestamp": "$timestamp",
    "hostname": "$hostname",
    "message": "$message",
    "metadata_file": "$metadata_file"
}
EOF
        )
        
        if curl -X POST -H "Content-Type: application/json" -d "$payload" "$BACKUP_NOTIFICATION_WEBHOOK" 2>/dev/null; then
            log_debug "Webhook 通知发送成功"
        else
            log_warn "Webhook 通知发送失败"
        fi
    fi
}

# 清理过期备份
cleanup_old_backups() {
    log_info "清理过期备份文件 (保留 $BACKUP_RETENTION_DAYS 天)..."
    
    local deleted_count=0
    
    # 清理全量备份
    find "$BACKUP_DIR/full" -name "*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null && deleted_count=$((deleted_count + 1)) || true
    
    # 清理增量备份
    find "$BACKUP_DIR/incremental" -name "*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null && deleted_count=$((deleted_count + 1)) || true
    
    # 清理配置备份
    find "$BACKUP_DIR/config" -name "*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null && deleted_count=$((deleted_count + 1)) || true
    
    # 清理日志备份
    find "$BACKUP_DIR/logs" -name "*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null && deleted_count=$((deleted_count + 1)) || true
    
    # 清理元数据
    find "$BACKUP_DIR/metadata" -name "*.json" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null && deleted_count=$((deleted_count + 1)) || true
    
    log_info "清理完成，删除 $deleted_count 个过期文件"
}

# 全量备份
perform_full_backup() {
    local backup_name="stock-tsdb-full-$(date +%Y%m%d-%H%M%S)"
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local temp_backup_file="$BACKUP_DIR/${backup_name}.tar"
    local final_backup_file="$BACKUP_DIR/full/${backup_name}.tar.gz"
    
    log_info "开始全量备份: $backup_name"
    
    # 检查依赖
    if ! check_dependencies; then
        send_backup_notification "$backup_name" "full" "failed" "依赖检查失败" ""
        return 1
    fi
    
    # 检查磁盘空间
    local data_size_mb=$(get_data_size)
    local required_space_mb=$((data_size_mb * 2))  # 预留2倍空间用于压缩和临时文件
    
    if ! check_disk_space "$required_space_mb"; then
        send_backup_notification "$backup_name" "full" "failed" "磁盘空间不足" ""
        return 1
    fi
    
    # 停止服务
    if ! stop_service_if_needed "full"; then
        send_backup_notification "$backup_name" "full" "failed" "服务停止失败" ""
        return 1
    fi
    
    # 创建临时备份文件
    log_info "正在创建数据备份..."
    
    if tar -cf "$temp_backup_file" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>/dev/null; then
        log_info "数据备份创建完成"
    else
        log_error "数据备份创建失败"
        send_backup_notification "$backup_name" "full" "failed" "数据备份创建失败" ""
        start_service
        return 1
    fi
    
    # 备份配置文件
    local config_backup_file="$BACKUP_DIR/config/${backup_name}-config.tar.gz"
    if [[ -d "$CONFIG_DIR" ]]; then
        log_info "正在备份配置文件..."
        if tar -czf "$config_backup_file" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>/dev/null; then
            log_info "配置文件备份完成"
        else
            log_warn "配置文件备份失败"
        fi
    fi
    
    # 启动服务
    start_service
    
    # 压缩备份文件
    if ! compress_backup "$temp_backup_file" "$final_backup_file"; then
        send_backup_notification "$backup_name" "full" "failed" "备份文件压缩失败" ""
        return 1
    fi
    
    # 加密备份文件（如果启用）
    if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
        local encrypted_file="${final_backup_file}.enc"
        if ! encrypt_backup "$final_backup_file" "$encrypted_file"; then
            send_backup_notification "$backup_name" "full" "failed" "备份文件加密失败" ""
            return 1
        fi
        final_backup_file="$encrypted_file"
    fi
    
    # 获取最终文件大小
    local backup_size=$(stat -c%s "$final_backup_file")
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 创建备份元数据
    create_backup_metadata "$backup_name" "full" "$backup_size" "$start_time" "$end_time"
    local metadata_file="$BACKUP_DIR/metadata/${backup_name}.json"
    
    # 上传到远程服务器（如果配置）
    if ! upload_remote_backup "$final_backup_file" "$final_backup_file"; then
        log_warn "远程备份上传失败，但本地备份已完成"
    fi
    
    # 发送成功通知
    send_backup_notification "$backup_name" "full" "success" "全量备份完成" "$metadata_file"
    
    # 清理过期备份
    cleanup_old_backups
    
    log_info "全量备份完成: $backup_name ($(numfmt --to=iec-i --suffix=B "$backup_size"))"
    return 0
}

# 增量备份
perform_incremental_backup() {
    local backup_name="stock-tsdb-incremental-$(date +%Y%m%d-%H%M%S)"
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local final_backup_file="$BACKUP_DIR/incremental/${backup_name}.tar.gz"
    
    log_info "开始增量备份: $backup_name"
    
    # 检查依赖
    if ! check_dependencies; then
        send_backup_notification "$backup_name" "incremental" "failed" "依赖检查失败" ""
        return 1
    fi
    
    # 查找最近的全量备份
    local last_full_backup=$(find "$BACKUP_DIR/full" -name "stock-tsdb-full-*.tar.gz*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$last_full_backup" ]]; then
        log_warn "未找到全量备份，执行全量备份"
        perform_full_backup
        return $?
    fi
    
    local last_full_backup_time=$(stat -c %Y "$last_full_backup")
    log_info "基于全量备份进行增量备份: $(basename "$last_full_backup")"
    
    # 创建临时目录用于增量文件
    local temp_dir="/tmp/stock-tsdb-incremental-$$"
    mkdir -p "$temp_dir"
    
    # 查找修改的文件
    log_info "正在查找修改的文件..."
    find "$DATA_DIR" -type f -newer "$last_full_backup" -print0 > "$temp_dir/modified_files.txt" 2>/dev/null || true
    
    local modified_count=$(tr -cd '\0' < "$temp_dir/modified_files.txt" | wc -c)
    
    if [[ $modified_count -eq 0 ]]; then
        log_info "没有文件修改，跳过增量备份"
        rm -rf "$temp_dir"
        return 0
    fi
    
    log_info "找到 $modified_count 个修改的文件"
    
    # 创建增量备份
    if tar -czf "$final_backup_file" --null -T "$temp_dir/modified_files.txt" 2>/dev/null; then
        log_info "增量备份创建完成"
    else
        log_error "增量备份创建失败"
        rm -rf "$temp_dir"
        send_backup_notification "$backup_name" "incremental" "failed" "增量备份创建失败" ""
        return 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    # 获取文件大小
    local backup_size=$(stat -c%s "$final_backup_file")
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 创建备份元数据
    create_backup_metadata "$backup_name" "incremental" "$backup_size" "$start_time" "$end_time"
    local metadata_file="$BACKUP_DIR/metadata/${backup_name}.json"
    
    # 上传到远程服务器
    if ! upload_remote_backup "$final_backup_file" "$final_backup_file"; then
        log_warn "远程备份上传失败，但本地备份已完成"
    fi
    
    # 发送成功通知
    send_backup_notification "$backup_name" "incremental" "success" "增量备份完成 ($modified_count 个文件)" "$metadata_file"
    
    log_info "增量备份完成: $backup_name ($(numfmt --to=iec-i --suffix=B "$backup_size"))"
    return 0
}

# 列出备份
list_backups() {
    local backup_type="$1"
    
    echo "备份列表:"
    echo "=========================================="
    
    case "$backup_type" in
        full)
            echo "全量备份:"
            find "$BACKUP_DIR/full" -name "stock-tsdb-full-*.tar.gz*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | while read -r timestamp filepath; do
                local filename=$(basename "$filepath")
                local filesize=$(stat -c%s "$filepath")
                local filedate=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')
                local metadata_file="$BACKUP_DIR/metadata/${filename%.tar.gz*}.json"
                
                if [[ -f "$metadata_file" ]]; then
                    local duration=$(jq -r '.duration_seconds // "unknown"' "$metadata_file" 2>/dev/null)
                    echo "  $filename"
                    echo "    时间: $filedate"
                    echo "    大小: $(numfmt --to=iec-i --suffix=B "$filesize")"
                    echo "    耗时: ${duration}s"
                    echo
                else
                    echo "  $filename"
                    echo "    时间: $filedate"
                    echo "    大小: $(numfmt --to=iec-i --suffix=B "$filesize")"
                    echo
                fi
            done
            ;;
            
        incremental)
            echo "增量备份:"
            find "$BACKUP_DIR/incremental" -name "stock-tsdb-incremental-*.tar.gz*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | while read -r timestamp filepath; do
                local filename=$(basename "$filepath")
                local filesize=$(stat -c%s "$filepath")
                local filedate=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')
                local metadata_file="$BACKUP_DIR/metadata/${filename%.tar.gz*}.json"
                
                if [[ -f "$metadata_file" ]]; then
                    local duration=$(jq -r '.duration_seconds // "unknown"' "$metadata_file" 2>/dev/null)
                    echo "  $filename"
                    echo "    时间: $filedate"
                    echo "    大小: $(numfmt --to=iec-i --suffix=B "$filesize")"
                    echo "    耗时: ${duration}s"
                    echo
                else
                    echo "  $filename"
                    echo "    时间: $filedate"
                    echo "    大小: $(numfmt --to=iec-i --suffix=B "$filesize")"
                    echo
                fi
            done
            ;;
            
        all)
            echo "所有备份:"
            find "$BACKUP_DIR" -name "stock-tsdb-*.tar.gz*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | while read -r timestamp filepath; do
                local filename=$(basename "$filepath")
                local filesize=$(stat -c%s "$filepath")
                local filedate=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')
                local backup_type=$(echo "$filename" | grep -q "full" && echo "全量" || echo "增量")
                
                echo "  [$backup_type] $filename"
                echo "    时间: $filedate"
                echo "    大小: $(numfmt --to=iec-i --suffix=B "$filesize")"
                echo
            done
            ;;
            
        *)
            echo "未知备份类型: $backup_type"
            return 1
            ;;
    esac
}

# 验证备份文件
verify_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_info "正在验证备份文件: $(basename "$backup_file")"
    
    # 检查文件完整性
    if [[ "$backup_file" == *.gz ]]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            log_info "压缩文件完整性检查通过"
        else
            log_error "压缩文件损坏"
            return 1
        fi
    fi
    
    # 检查加密文件
    if [[ "$backup_file" == *.enc ]]; then
        if [[ -n "$BACKUP_ENCRYPTION_KEY" ]]; then
            if openssl enc -aes-256-cbc -d -in "$backup_file" -pass pass:"$BACKUP_ENCRYPTION_KEY" >/dev/null 2>&1; then
                log_info "加密文件验证通过"
            else
                log_error "加密文件验证失败"
                return 1
            fi
        else
            log_warn "未提供解密密钥，跳过加密验证"
        fi
    fi
    
    # 检查 tar 文件内容
    if [[ "$backup_file" == *.tar.gz ]]; then
        if tar -tzf "$backup_file" >/dev/null 2>&1; then
            log_info "tar 文件内容检查通过"
        else
            log_error "tar 文件损坏"
            return 1
        fi
    fi
    
    log_info "备份文件验证通过"
    return 0
}

# 恢复备份
restore_backup() {
    local backup_file="$1"
    local target_dir="$2"
    local restore_type="$3"
    
    if [[ -z "$target_dir" ]]; then
        target_dir="$DATA_DIR"
    fi
    
    if [[ -z "$restore_type" ]]; then
        restore_type="full"
    fi
    
    local backup_name=$(basename "$backup_file")
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "开始恢复备份: $backup_name"
    
    # 验证备份文件
    if ! verify_backup "$backup_file"; then
        log_error "备份文件验证失败，无法恢复"
        return 1
    fi
    
    # 检查目标目录
    if [[ -d "$target_dir" ]]; then
        log_warn "目标目录已存在: $target_dir"
        read -p "是否覆盖现有数据? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "恢复操作已取消"
            return 0
        fi
        
        # 备份现有数据
        local existing_backup="/tmp/stock-tsdb-existing-$(date +%Y%m%d-%H%M%S).tar.gz"
        log_info "正在备份现有数据..."
        if tar -czf "$existing_backup" -C "$(dirname "$target_dir")" "$(basename "$target_dir")" 2>/dev/null; then
            log_info "现有数据已备份到: $existing_backup"
        else
            log_warn "现有数据备份失败"
        fi
    fi
    
    # 创建临时恢复目录
    local temp_dir="/tmp/stock-tsdb-restore-$$"
    mkdir -p "$temp_dir"
    
    # 解密文件（如果需要）
    local decrypted_file="$backup_file"
    if [[ "$backup_file" == *.enc ]]; then
        decrypted_file="$temp_dir/$(basename "$backup_file" .enc)"
        log_info "正在解密备份文件..."
        
        if openssl enc -aes-256-cbc -d -in "$backup_file" -out "$decrypted_file" -pass pass:"$BACKUP_ENCRYPTION_KEY"; then
            log_info "解密完成"
        else
            log_error "解密失败"
            rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # 解压缩文件
    local extracted_dir="$temp_dir/extracted"
    mkdir -p "$extracted_dir"
    
    log_info "正在解压缩备份文件..."
    if tar -xzf "$decrypted_file" -C "$extracted_dir"; then
        log_info "解压缩完成"
    else
        log_error "解压缩失败"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 移动数据到目标目录
    log_info "正在恢复数据到目标目录..."
    
    # 停止服务
    stop_service_if_needed "full"
    
    # 删除现有目录
    rm -rf "$target_dir"
    
    # 移动新数据
    if mv "$extracted_dir/$(basename "$DATA_DIR")" "$target_dir" 2>/dev/null; then
        log_info "数据恢复完成"
    else
        log_error "数据恢复失败"
        start_service
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 设置正确的权限
    chown -R stock-tsdb:stock-tsdb "$target_dir" 2>/dev/null || true
    chmod -R 750 "$target_dir" 2>/dev/null || true
    
    # 启动服务
    start_service
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "备份恢复完成: $backup_name"
    log_info "恢复时间: $start_time -> $end_time"
    
    return 0
}

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 生产环境备份脚本

用法: $0 [选项] [命令]

命令:
    full                    执行全量备份
    incremental             执行增量备份
    list [type]             列出备份文件 [full|incremental|all]
    verify <backup_file>    验证备份文件
    restore <backup_file> [target_dir] [type] 恢复备份
    cleanup                 清理过期备份
    help                    显示帮助信息

选项:
    -d DIR                  备份目录 [默认: /var/backup/stock-tsdb]
    -D DIR                  数据目录 [默认: /var/lib/stock-tsdb]
    -C DIR                  配置目录 [默认: /etc/stock-tsdb]
    -r DAYS                 备份保留天数 [默认: 30]
    -c LEVEL                压缩级别 (1-9) [默认: 6]
    -k KEY                  加密密钥
    -H HOST                 远程备份主机
    -P PATH                 远程备份路径
    -U USER                 远程备份用户
    -e EMAIL                通知邮箱
    -w WEBHOOK              通知 Webhook

环境变量:
    BACKUP_DIR              备份目录
    DATA_DIR                数据目录
    CONFIG_DIR              配置目录
    BACKUP_RETENTION_DAYS   备份保留天数
    BACKUP_COMPRESSION_LEVEL 压缩级别
    BACKUP_ENCRYPTION_KEY   加密密钥
    BACKUP_REMOTE_HOST      远程备份主机
    BACKUP_REMOTE_PATH      远程备份路径
    BACKUP_REMOTE_USER      远程备份用户
    BACKUP_NOTIFICATION_EMAIL 通知邮箱
    BACKUP_NOTIFICATION_WEBHOOK 通知 Webhook

示例:
    # 执行全量备份
    $0 full

    # 执行增量备份
    $0 incremental

    # 列出所有备份
    $0 list all

    # 验证备份文件
    $0 verify /var/backup/stock-tsdb/full/stock-tsdb-full-20231201-120000.tar.gz

    # 恢复备份
    $0 restore /var/backup/stock-tsdb/full/stock-tsdb-full-20231201-120000.tar.gz

    # 清理过期备份
    $0 cleanup

EOF
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -D)
                DATA_DIR="$2"
                shift 2
                ;;
            -C)
                CONFIG_DIR="$2"
                shift 2
                ;;
            -r)
                BACKUP_RETENTION_DAYS="$2"
                shift 2
                ;;
            -c)
                BACKUP_COMPRESSION_LEVEL="$2"
                shift 2
                ;;
            -k)
                BACKUP_ENCRYPTION_KEY="$2"
                shift 2
                ;;
            -H)
                BACKUP_REMOTE_HOST="$2"
                shift 2
                ;;
            -P)
                BACKUP_REMOTE_PATH="$2"
                shift 2
                ;;
            -U)
                BACKUP_REMOTE_USER="$2"
                shift 2
                ;;
            -e)
                BACKUP_NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            -w)
                BACKUP_NOTIFICATION_WEBHOOK="$2"
                shift 2
                ;;
            full|incremental|list|verify|restore|cleanup|help)
                COMMAND="$1"
                shift
                ;;
            *)
                # 处理命令参数
                if [[ -z "$BACKUP_FILE" ]]; then
                    BACKUP_FILE="$1"
                elif [[ -z "$TARGET_DIR" ]]; then
                    TARGET_DIR="$1"
                elif [[ -z "$RESTORE_TYPE" ]]; then
                    RESTORE_TYPE="$1"
                else
                    echo "未知参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# 主函数
main() {
    # 创建备份目录
    create_backup_dirs
    
    # 解析参数
    parse_arguments "$@"
    
    # 设置默认命令
    if [[ -z "$COMMAND" ]]; then
        COMMAND="full"
    fi
    
    case "$COMMAND" in
        full)
            perform_full_backup
            ;;
            
        incremental)
            perform_incremental_backup
            ;;
            
        list)
            list_backups "${BACKUP_FILE:-all}"
            ;;
            
        verify)
            if [[ -z "$BACKUP_FILE" ]]; then
                log_error "请指定备份文件"
                exit 1
            fi
            verify_backup "$BACKUP_FILE"
            ;;
            
        restore)
            if [[ -z "$BACKUP_FILE" ]]; then
                log_error "请指定备份文件"
                exit 1
            fi
            restore_backup "$BACKUP_FILE" "$TARGET_DIR" "$RESTORE_TYPE"
            ;;
            
        cleanup)
            cleanup_old_backups
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