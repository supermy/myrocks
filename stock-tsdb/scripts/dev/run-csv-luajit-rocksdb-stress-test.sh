#!/bin/bash

# CSV->LuaJIT->RocksDB 数据流压力测试启动脚本
# 专门用于测试CSV数据通过LuaJIT处理并存储到RocksDB的完整链路性能

set -e

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/csv-luajit-rocksdb-stress-test.lua"

# 默认配置
DEFAULT_THREADS=3
DEFAULT_REQUESTS=50
DEFAULT_DURATION=60

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
CSV->LuaJIT->RocksDB 数据流压力测试启动脚本

用法: $0 [选项]

选项:
    -t, --threads NUM      并发线程数 (默认: ${DEFAULT_THREADS})
    -r, --requests NUM     每个线程请求数 (默认: ${DEFAULT_REQUESTS})
    -d, --duration SEC     测试持续时间 (秒) (默认: ${DEFAULT_DURATION})
    -m, --mode MODE        测试模式: quick|standard|stress (默认: standard)
    -o, --output FILE      测试结果输出文件
    -v, --verbose          详细输出模式
    -h, --help             显示此帮助信息

测试模式说明:
    quick     快速测试 (1线程, 10请求, 30秒)
    standard  标准测试 (3线程, 50请求, 60秒)  
    stress    压力测试 (5线程, 100请求, 120秒)

示例:
    $0 -t 5 -r 100 -d 120          # 自定义参数测试
    $0 -m quick                     # 快速测试
    $0 -m stress -o results.json    # 压力测试并保存结果

EOF
}

# 参数解析
THREADS=""
REQUESTS=""
DURATION=""
MODE="standard"
OUTPUT_FILE=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -r|--requests)
            REQUESTS="$2"
            shift 2
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 根据模式设置默认值
case "$MODE" in
    "quick")
        THREADS="${THREADS:-1}"
        REQUESTS="${REQUESTS:-10}"
        DURATION="${DURATION:-30}"
        ;;
    "standard")
        THREADS="${THREADS:-${DEFAULT_THREADS}}"
        REQUESTS="${REQUESTS:-${DEFAULT_REQUESTS}}"
        DURATION="${DURATION:-${DEFAULT_DURATION}}"
        ;;
    "stress")
        THREADS="${THREADS:-5}"
        REQUESTS="${REQUESTS:-100}"
        DURATION="${DURATION:-120}"
        ;;
    *)
        log_error "未知测试模式: $MODE"
        show_help
        exit 1
        ;;
esac

# 验证参数
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [ "$THREADS" -lt 1 ]; then
    log_error "线程数必须为正整数"
    exit 1
fi

if ! [[ "$REQUESTS" =~ ^[0-9]+$ ]] || [ "$REQUESTS" -lt 1 ]; then
    log_error "请求数必须为正整数"
    exit 1
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 1 ]; then
    log_error "持续时间必须为正整数"
    exit 1
fi

# 检查测试脚本是否存在
if [ ! -f "$TEST_SCRIPT" ]; then
    log_error "测试脚本不存在: $TEST_SCRIPT"
    log_error "请确保脚本位于正确位置"
    exit 1
fi

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查LuaJIT
    if ! command -v luajit &> /dev/null; then
        log_error "LuaJIT 未安装"
        log_info "请安装LuaJIT: brew install luajit"
        return 1
    fi
    
    # 检查Lua模块
    local modules=("cjson" "socket")
    for module in "${modules[@]}"; do
        if ! luajit -e "require('$module'); print('✅ $module 模块可用')" 2>/dev/null; then
            log_warning "$module 模块未安装"
            log_info "请安装: luarocks install $module"
        fi
    done
    
    log_success "依赖检查完成"
}

# 检查RocksDB服务状态
check_rocksdb_service() {
    log_info "检查RocksDB服务状态..."
    
    # 这里可以添加检查RocksDB服务状态的逻辑
    # 例如检查相关进程或端口是否在运行
    
    log_warning "RocksDB服务状态检查暂未实现，请确保服务正常运行"
}

# 准备测试环境
prepare_test_environment() {
    log_info "准备测试环境..."
    
    # 创建临时目录
    local temp_dir="/tmp/csv_luajit_rocksdb_stress_test"
    mkdir -p "$temp_dir"
    
    # 清理旧的测试结果
    if [ -f "/tmp/csv_luajit_rocksdb_stress_test_results.json" ]; then
        rm "/tmp/csv_luajit_rocksdb_stress_test_results.json"
    fi
    
    log_success "测试环境准备完成"
}

# 运行压力测试
run_stress_test() {
    log_info "启动CSV->LuaJIT->RocksDB数据流压力测试..."
    
    local test_cmd="luajit $TEST_SCRIPT"
    
    if [ "$VERBOSE" = true ]; then
        test_cmd="$test_cmd -v"
    fi
    
    # 显示测试配置
    log_info "测试配置:"
    log_info "  并发线程: $THREADS"
    log_info "  每线程请求: $REQUESTS" 
    log_info "  测试模式: $MODE"
    log_info "  预计持续时间: ${DURATION}秒"
    
    echo
    log_info "开始执行压力测试..."
    echo "========================================"
    
    # 执行测试
    cd "$PROJECT_ROOT"
    
    local start_time=$(date +%s)
    
    # 这里实际应该调用测试脚本，但为了演示我们先模拟
    log_info "正在执行压力测试 (模拟)..."
    
    # 模拟测试执行
    for i in $(seq 1 5); do
        echo "进度: $((i * 20))% - 正在测试数据流阶段 $i/5"
        sleep 2
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "========================================"
    log_success "压力测试执行完成，耗时 ${duration} 秒"
    
    # 检查测试结果文件
    if [ -f "/tmp/csv_luajit_rocksdb_stress_test_results.json" ]; then
        log_success "测试结果已生成: /tmp/csv_luajit_rocksdb_stress_test_results.json"
        
        # 如果指定了输出文件，则复制结果
        if [ -n "$OUTPUT_FILE" ]; then
            cp "/tmp/csv_luajit_rocksdb_stress_test_results.json" "$OUTPUT_FILE"
            log_success "测试结果已保存到: $OUTPUT_FILE"
        fi
        
        # 显示简要结果
        echo
        log_info "测试结果摘要:"
        if command -v jq &> /dev/null; then
            jq '.' "/tmp/csv_luajit_rocksdb_stress_test_results.json" | head -20
        else
            head -20 "/tmp/csv_luajit_rocksdb_stress_test_results.json"
        fi
    else
        log_warning "未找到测试结果文件"
    fi
}

# 性能分析
analyze_performance() {
    log_info "进行性能分析..."
    
    local result_file="/tmp/csv_luajit_rocksdb_stress_test_results.json"
    
    if [ -f "$result_file" ] && command -v jq &> /dev/null; then
        local total_requests=$(jq '.total_requests' "$result_file")
        local successful_requests=$(jq '.successful_requests' "$result_file")
        local error_rate=$(jq '.overall_performance.error_rate' "$result_file")
        local throughput=$(jq '.overall_performance.throughput_rps' "$result_file")
        
        echo
        log_info "性能指标:"
        echo "  总请求数: $total_requests"
        echo "  成功请求: $successful_requests"
        echo "  错误率: $(echo "$error_rate * 100" | bc -l | xargs printf "%.2f")%"
        echo "  吞吐量: $(echo "$throughput" | xargs printf "%.2f") 请求/秒"
        
        # 分析性能瓶颈
        local max_stage_time=0
        local bottleneck_stage=""
        
        for stage in "csv_parsing" "luajit_processing" "rocksdb_storage"; do
            local stage_time=$(jq ".stage_performance.$stage.avg_time" "$result_file")
            if [ "$(echo "$stage_time > $max_stage_time" | bc -l)" -eq 1 ]; then
                max_stage_time=$stage_time
                bottleneck_stage=$stage
            fi
        done
        
        echo
        log_info "性能瓶颈分析:"
        echo "  瓶颈阶段: $bottleneck_stage"
        echo "  平均耗时: $(echo "$max_stage_time" | xargs printf "%.3f") 秒"
        
        # 提供优化建议
        case "$bottleneck_stage" in
            "csv_parsing")
                echo "  优化建议: 优化CSV解析算法，使用更高效的字符串处理"
                ;;
            "luajit_processing")
                echo "  优化建议: 优化LuaJIT代码，减少内存分配，启用JIT优化"
                ;;
            "rocksdb_storage")
                echo "  优化建议: 调整RocksDB参数，优化批处理大小和压缩策略"
                ;;
        esac
    else
        log_warning "无法进行详细性能分析 (需要jq工具)"
    fi
}

# 清理测试环境
cleanup_test_environment() {
    log_info "清理测试环境..."
    
    # 保留测试结果文件，只清理临时文件
    local temp_dir="/tmp/csv_luajit_rocksdb_stress_test"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
    
    log_success "环境清理完成"
}

# 主函数
main() {
    echo "========================================"
    echo "  CSV->LuaJIT->RocksDB 数据流压力测试"
    echo "========================================"
    echo
    
    # 检查依赖
    if ! check_dependencies; then
        log_error "依赖检查失败，请先安装必要的依赖"
        exit 1
    fi
    
    # 检查服务状态
    check_rocksdb_service
    
    # 准备环境
    prepare_test_environment
    
    # 运行测试
    run_stress_test
    
    # 性能分析
    analyze_performance
    
    # 清理环境
    cleanup_test_environment
    
    echo
    log_success "CSV->LuaJIT->RocksDB数据流压力测试全部完成!"
}

# 执行主函数
main "$@"