#!/bin/bash

# Stock-TSDB 数据查询脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="数据查询脚本"

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

支持多种查询方式的数据查询功能。

用法: $0 [选项]

查询模式:
    --metric METRIC          指标名称查询
    --tag TAG=VALUE          标签查询
    --time-range START END   时间范围查询
    --aggregation FUNC       聚合函数查询

选项:
    -h, --host HOST           服务地址 [默认: 127.0.0.1]
    -p, --port PORT           服务端口 [默认: 6379]
    -o, --output FORMAT       输出格式 [默认: table, 支持: table, json, csv]
    -l, --limit NUM           限制返回数量 [默认: 100]
    --start START_TIME        开始时间 [格式: YYYY-MM-DD HH:MM:SS 或 时间戳]
    --end END_TIME            结束时间
    --step INTERVAL           时间间隔 [用于聚合查询]
    --batch                  批量查询模式
    --config FILE            查询配置文件
    -h, --help               显示此帮助信息

查询示例:
    # 查询股票价格指标
    $0 --metric stock.price --start "2024-01-01" --end "2024-01-31"
    
    # 按标签查询IOT数据
    $0 --tag device_id=temp_sensor_001 --start "2024-01-01 00:00:00" --end "2024-01-01 23:59:59"
    
    # 聚合查询（每小时平均值）
    $0 --metric iot.temperature --aggregation avg --step 1h --start "2024-01-01" --end "2024-01-02"
    
    # JSON格式输出
    $0 --metric stock.volume --output json --limit 10
    
    # 批量查询
    $0 --config query_config.json --batch

支持的聚合函数:
    avg     平均值
    sum     求和
    min     最小值
    max     最大值
    count   计数
    first   第一个值
    last    最后一个值

EOF
}

# 验证时间格式
validate_time_format() {
    local time_str="$1"
    
    # 检查时间戳格式
    if [[ "$time_str" =~ ^[0-9]+$ ]]; then
        return 0
    fi
    
    # 检查日期时间格式
    if [[ "$time_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || \
       [[ "$time_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        return 0
    fi
    
    return 1
}

# 验证聚合函数
validate_aggregation() {
    local valid_funcs=("avg" "sum" "min" "max" "count" "first" "last")
    
    for func in "${valid_funcs[@]}"; do
        if [[ "$AGGREGATION" == "$func" ]]; then
            return 0
        fi
    done
    
    log_error "不支持的聚合函数: $AGGREGATION"
    echo "支持的聚合函数: ${valid_funcs[*]}"
    exit 1
}

# 检查服务连接
check_service_connection() {
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
            log_warning "服务健康检查失败，但继续查询"
        fi
    fi
}

# 生成查询配置
generate_query_config() {
    log_info "生成查询配置..."
    
    local config_file="/tmp/tsdb_query_$$.lua"
    
    cat > "$config_file" << EOF
-- 数据查询配置
return {
    query = {
        -- 查询类型
        type = "$QUERY_TYPE",
        
        -- 查询条件
        conditions = {
EOF
    
    # 添加查询条件
    if [[ -n "$METRIC" ]]; then
        echo "            metric = \"$METRIC\"," >> "$config_file"
    fi
    
    if [[ -n "$TAG" ]]; then
        echo "            tag = \"$TAG\"," >> "$config_file"
    fi
    
    if [[ -n "$START_TIME" ]]; then
        echo "            start_time = \"$START_TIME\"," >> "$config_file"
    fi
    
    if [[ -n "$END_TIME" ]]; then
        echo "            end_time = \"$END_TIME\"," >> "$config_file"
    fi
    
    if [[ -n "$AGGREGATION" ]]; then
        echo "            aggregation = \"$AGGREGATION\"," >> "$config_file"
    fi
    
    if [[ -n "$STEP" ]]; then
        echo "            step = \"$STEP\"," >> "$config_file"
    fi
    
    cat >> "$config_file" << EOF
        },
        
        -- 输出配置
        output = {
            format = "$OUTPUT_FORMAT",
            limit = $LIMIT,
            batch_mode = $BATCH_MODE
        },
        
        -- 连接配置
        connection = {
            host = "$HOST",
            port = $PORT,
            timeout = 60
        }
    }
}
EOF
    
    echo "$config_file"
}

# 执行查询
perform_query() {
    local config_file="$1"
    
    log_info "执行数据查询..."
    
    # 设置Lua路径
    export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"
    
    local query_cmd="luajit lua/query_engine.lua --config $config_file"
    
    # 执行查询
    if eval "$query_cmd"; then
        log_success "查询完成"
    else
        log_error "查询执行失败"
        exit 1
    fi
}

# 显示查询信息
show_query_info() {
    log_info "查询信息:"
    
    echo "  - 服务地址: $HOST:$PORT"
    echo "  - 输出格式: $OUTPUT_FORMAT"
    echo "  - 返回限制: $LIMIT"
    
    if [[ -n "$METRIC" ]]; then
        echo "  - 指标名称: $METRIC"
    fi
    
    if [[ -n "$TAG" ]]; then
        echo "  - 标签条件: $TAG"
    fi
    
    if [[ -n "$START_TIME" ]]; then
        echo "  - 开始时间: $START_TIME"
    fi
    
    if [[ -n "$END_TIME" ]]; then
        echo "  - 结束时间: $END_TIME"
    fi
    
    if [[ -n "$AGGREGATION" ]]; then
        echo "  - 聚合函数: $AGGREGATION"
    fi
    
    if [[ -n "$STEP" ]]; then
        echo "  - 时间间隔: $STEP"
    fi
    
    if [[ "$BATCH_MODE" == "true" ]]; then
        echo "  - 查询模式: 批量"
    else
        echo "  - 查询模式: 单次"
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
    HOST="127.0.0.1"
    PORT=6379
    OUTPUT_FORMAT="table"
    LIMIT=100
    QUERY_TYPE="metric"
    METRIC=""
    TAG=""
    START_TIME=""
    END_TIME=""
    AGGREGATION=""
    STEP=""
    BATCH_MODE="false"
    CONFIG_FILE=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --metric)
                METRIC="$2"
                QUERY_TYPE="metric"
                shift 2
                ;;
            --tag)
                TAG="$2"
                QUERY_TYPE="tag"
                shift 2
                ;;
            --time-range)
                START_TIME="$2"
                END_TIME="$3"
                QUERY_TYPE="time_range"
                shift 3
                ;;
            --aggregation)
                AGGREGATION="$2"
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
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -l|--limit)
                LIMIT="$2"
                shift 2
                ;;
            --start)
                START_TIME="$2"
                shift 2
                ;;
            --end)
                END_TIME="$2"
                shift 2
                ;;
            --step)
                STEP="$2"
                shift 2
                ;;
            --batch)
                BATCH_MODE="true"
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
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
    
    # 如果指定了配置文件，直接使用
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "配置文件不存在: $CONFIG_FILE"
            exit 1
        fi
        
        log_info "使用配置文件: $CONFIG_FILE"
        TEMP_CONFIG="$CONFIG_FILE"
    else
        # 验证必需参数
        if [[ -z "$METRIC" && -z "$TAG" ]]; then
            log_error "必须指定查询条件 (--metric 或 --tag)"
            show_help
            exit 1
        fi
        
        # 验证时间格式
        if [[ -n "$START_TIME" ]] && ! validate_time_format "$START_TIME"; then
            log_error "无效的开始时间格式: $START_TIME"
            exit 1
        fi
        
        if [[ -n "$END_TIME" ]] && ! validate_time_format "$END_TIME"; then
            log_error "无效的结束时间格式: $END_TIME"
            exit 1
        fi
        
        # 验证聚合函数
        if [[ -n "$AGGREGATION" ]]; then
            validate_aggregation
        fi
        
        # 检查服务连接
        check_service_connection
        
        # 显示查询信息
        show_query_info
        
        # 生成查询配置
        TEMP_CONFIG=$(generate_query_config)
    fi
    
    # 设置清理钩子
    trap cleanup EXIT
    
    # 执行查询
    perform_query "$TEMP_CONFIG"
    
    log_success "数据查询流程完成"
}

# 运行主函数
main "$@"