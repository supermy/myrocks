#!/bin/bash

# Stock-TSDB CSV数据导入脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="CSV数据导入脚本"

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

支持多种业务数据的CSV导入功能。

用法: $0 [选项]

选项:
    -f, --file FILE           CSV文件路径 (必需)
    -t, --type TYPE           数据类型 [必需，支持: stock_quote, iot_metric, financial_tick, order_book, trade_record, sensor_data, custom]
    -h, --host HOST           服务地址 [默认: 127.0.0.1]
    -p, --port PORT           服务端口 [默认: 6379]
    -b, --batch-size SIZE     批量大小 [默认: 1000]
    --delimiter CHAR          分隔符 [默认: ,]
    --skip-header             跳过CSV头部
    --validate                启用数据验证
    --dry-run                 试运行，不实际导入
    -h, --help               显示此帮助信息

支持的数据类型:
    stock_quote     股票行情数据
    iot_metric      IOT指标数据
    financial_tick  金融tick数据
    order_book      订单簿数据
    trade_record    交易记录数据
    sensor_data     传感器数据
    custom          自定义数据

示例:
    # 导入股票数据
    $0 --file stock_data.csv --type stock_quote
    
    # 导入IOT数据，自定义批量大小
    $0 --file iot_data.csv --type iot_metric --batch-size 500
    
    # 试运行验证数据
    $0 --file data.csv --type financial_tick --dry-run --validate

EOF
}

# 验证数据类型
validate_data_type() {
    local valid_types=("stock_quote" "iot_metric" "financial_tick" "order_book" "trade_record" "sensor_data" "custom")
    
    for valid_type in "${valid_types[@]}"; do
        if [[ "$DATA_TYPE" == "$valid_type" ]]; then
            return 0
        fi
    done
    
    log_error "不支持的数据类型: $DATA_TYPE"
    echo "支持的数据类型: ${valid_types[*]}"
    exit 1
}

# 检查CSV文件
check_csv_file() {
    if [[ ! -f "$CSV_FILE" ]]; then
        log_error "CSV文件不存在: $CSV_FILE"
        exit 1
    fi
    
    if [[ ! -r "$CSV_FILE" ]]; then
        log_error "CSV文件不可读: $CSV_FILE"
        exit 1
    fi
    
    # 检查文件大小
    local file_size=$(wc -c < "$CSV_FILE")
    if [[ $file_size -eq 0 ]]; then
        log_error "CSV文件为空: $CSV_FILE"
        exit 1
    fi
    
    log_info "CSV文件检查通过: $CSV_FILE (大小: $((file_size/1024))KB)"
}

# 检查服务连接
check_service_connection() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "试运行模式，跳过服务连接检查"
        return 0
    fi
    
    log_info "检查服务连接..."
    
    if command -v nc &> /dev/null; then
        if ! nc -z "$HOST" "$PORT" 2>/dev/null; then
            log_error "无法连接到服务: $HOST:$PORT"
            exit 1
        fi
    fi
    
    # 尝试HTTP健康检查
    if command -v curl &> /dev/null; then
        local health_url="http://$HOST:$((PORT + 2000))/health"
        if curl -s "$health_url" > /dev/null 2>&1; then
            log_success "服务健康检查通过"
        else
            log_warning "服务健康检查失败，但继续导入"
        fi
    fi
}

# 生成导入配置
generate_import_config() {
    log_info "生成导入配置..."
    
    local config_file="/tmp/tsdb_import_$$.lua"
    
    cat > "$config_file" << EOF
-- CSV导入配置
return {
    csv_import = {
        file_path = "$CSV_FILE",
        data_type = "$DATA_TYPE",
        
        -- 解析配置
        parsing = {
            delimiter = "$DELIMITER",
            skip_header = $SKIP_HEADER,
            encoding = "utf8"
        },
        
        -- 处理配置
        processing = {
            batch_size = $BATCH_SIZE,
            enable_validation = $VALIDATE,
            dry_run = $DRY_RUN
        },
        
        -- 连接配置
        connection = {
            host = "$HOST",
            port = $PORT,
            timeout = 300
        }
    }
}
EOF
    
    echo "$config_file"
}

# 执行导入
perform_import() {
    local config_file="$1"
    
    log_info "开始导入数据..."
    
    # 设置Lua路径
    export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"
    
    local import_cmd="luajit lua/csv_import.lua --config $config_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "试运行模式，不实际导入数据"
        echo "导入命令: $import_cmd"
        return 0
    fi
    
    # 执行导入
    if eval "$import_cmd"; then
        log_success "数据导入完成"
    else
        log_error "数据导入失败"
        exit 1
    fi
}

# 显示导入统计
show_import_stats() {
    log_info "导入统计信息:"
    
    # 获取文件行数
    local total_lines=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    if [[ $SKIP_HEADER == "true" ]]; then
        total_lines=$((total_lines - 1))
    fi
    
    echo "  - 数据文件: $CSV_FILE"
    echo "  - 数据类型: $DATA_TYPE"
    echo "  - 总数据行: $total_lines"
    echo "  - 批量大小: $BATCH_SIZE"
    echo "  - 分隔符: $DELIMITER"
    
    if [[ "$VALIDATE" == "true" ]]; then
        echo "  - 数据验证: 启用"
    else
        echo "  - 数据验证: 禁用"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  - 运行模式: 试运行"
    else
        echo "  - 运行模式: 实际导入"
        echo "  - 服务地址: $HOST:$PORT"
    fi
    
    echo ""
}

# 清理临时文件
cleanup() {
    if [[ -n "$TEMP_CONFIG" && -f "$TEMP_CONFIG" ]]; then
        rm -f "$TEMP_CONFIG"
    fi
}

# 主函数
main() {
    # 默认配置
    CSV_FILE=""
    DATA_TYPE=""
    HOST="127.0.0.1"
    PORT=6379
    BATCH_SIZE=1000
    DELIMITER=","
    SKIP_HEADER="false"
    VALIDATE="false"
    DRY_RUN="false"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                CSV_FILE="$2"
                shift 2
                ;;
            -t|--type)
                DATA_TYPE="$2"
                shift 2
                ;;
            -h|--host)
                HOST="$2"
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                shift 2
                ;;
            -b|--batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --delimiter)
                DELIMITER="$2"
                shift 2
                ;;
            --skip-header)
                SKIP_HEADER="true"
                shift
                ;;
            --validate)
                VALIDATE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
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
    
    # 验证必需参数
    if [[ -z "$CSV_FILE" ]]; then
        log_error "必须指定CSV文件路径 (-f/--file)"
        show_help
        exit 1
    fi
    
    if [[ -z "$DATA_TYPE" ]]; then
        log_error "必须指定数据类型 (-t/--type)"
        show_help
        exit 1
    fi
    
    # 验证数据类型
    validate_data_type
    
    # 检查CSV文件
    check_csv_file
    
    # 检查服务连接
    check_service_connection
    
    # 显示导入统计
    show_import_stats
    
    # 生成导入配置
    TEMP_CONFIG=$(generate_import_config)
    
    # 设置清理钩子
    trap cleanup EXIT
    
    # 执行导入
    perform_import "$TEMP_CONFIG"
    
    log_success "CSV导入流程完成"
}

# 运行主函数
main "$@"