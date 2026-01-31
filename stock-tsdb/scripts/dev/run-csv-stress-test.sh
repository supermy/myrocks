#!/bin/bash

# CSV导入导出压力测试启动脚本
# 用于运行Stock-TSDB系统的CSV数据导入导出压力测试

# 设置脚本选项
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 默认配置
TEST_TYPE="mixed"
CONCURRENT_THREADS=5
REQUESTS_PER_THREAD=100
TEST_DURATION=300

# 显示帮助信息
show_help() {
    echo "Stock-TSDB CSV导入导出压力测试"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -t, --type TYPE         测试类型: import|export|mixed (默认: mixed)"
    echo "  -c, --threads NUM        并发线程数 (默认: 5)"
    echo "  -r, --requests NUM       每个线程请求数 (默认: 100)"
    echo "  -d, --duration SEC      测试持续时间 (秒) (默认: 300)"
    echo "  -h, --help              显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -t import -c 10 -r 200     # 测试CSV导入，10线程，每个200请求"
    echo "  $0 --type export --duration 600  # 测试CSV导出，持续10分钟"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -c|--threads)
            CONCURRENT_THREADS="$2"
            shift 2
            ;;
        -r|--requests)
            REQUESTS_PER_THREAD="$2"
            shift 2
            ;;
        -d|--duration)
            TEST_DURATION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
    esac
done

# 验证参数
if [[ ! "$TEST_TYPE" =~ ^(import|export|mixed)$ ]]; then
    echo "错误: 测试类型必须是 import、export 或 mixed"
    exit 1
fi

if [[ ! "$CONCURRENT_THREADS" =~ ^[0-9]+$ ]] || [[ "$CONCURRENT_THREADS" -lt 1 ]]; then
    echo "错误: 并发线程数必须是正整数"
    exit 1
fi

if [[ ! "$REQUESTS_PER_THREAD" =~ ^[0-9]+$ ]] || [[ "$REQUESTS_PER_THREAD" -lt 1 ]]; then
    echo "错误: 每个线程请求数必须是正整数"
    exit 1
fi

if [[ ! "$TEST_DURATION" =~ ^[0-9]+$ ]] || [[ "$TEST_DURATION" -lt 10 ]]; then
    echo "错误: 测试持续时间必须至少10秒"
    exit 1
fi

# 检查依赖
check_dependencies() {
    echo "检查依赖..."
    
    # 检查luajit
    if ! command -v luajit &> /dev/null; then
        echo "错误: 未找到 luajit，请先安装"
        exit 1
    fi
    
    # 检查LuaSocket
    if ! luajit -e "require('socket')" &> /dev/null; then
        echo "错误: 未找到 LuaSocket 库，请先安装"
        echo "安装命令: luarocks install luasocket"
        exit 1
    fi
    
    # 检查cjson
    if ! luajit -e "require('cjson')" &> /dev/null; then
        echo "错误: 未找到 cjson 库，请先安装"
        echo "安装命令: luarocks install lua-cjson"
        exit 1
    fi
    
    echo "✅ 所有依赖检查通过"
}

# 检查Stock-TSDB服务状态
check_service() {
    echo "检查Stock-TSDB服务状态..."
    
    # 尝试连接服务
    if curl -s "http://localhost:8081/health" > /dev/null; then
        echo "✅ Stock-TSDB服务运行正常"
    else
        echo "⚠️  Stock-TSDB服务未运行或无法连接"
        echo "请确保服务在 http://localhost:8081 上运行"
        read -p "是否继续测试？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 准备测试环境
prepare_test() {
    echo "准备测试环境..."
    
    # 创建临时目录
    mkdir -p "/tmp/stock_tsdb_csv_test"
    
    # 备份当前配置
    cp "$SCRIPT_DIR/csv-stress-test.lua" "/tmp/stock_tsdb_csv_test/csv-stress-test.lua.backup" 2>/dev/null || true
    
    echo "✅ 测试环境准备完成"
}

# 运行压力测试
run_stress_test() {
    echo ""
    echo "=== 开始CSV导入导出压力测试 ==="
    echo "测试类型: $TEST_TYPE"
    echo "并发线程数: $CONCURRENT_THREADS"
    echo "每个线程请求数: $REQUESTS_PER_THREAD"
    echo "测试持续时间: $TEST_DURATION 秒"
    echo ""
    
    # 修改测试配置
    sed -i.bak "s/concurrent_threads = .*/concurrent_threads = $CONCURRENT_THREADS,/" "$SCRIPT_DIR/csv-stress-test.lua"
    sed -i.bak "s/requests_per_thread = .*/requests_per_thread = $REQUESTS_PER_THREAD,/" "$SCRIPT_DIR/csv-stress-test.lua"
    sed -i.bak "s/test_duration = .*/test_duration = $TEST_DURATION,/" "$SCRIPT_DIR/csv-stress-test.lua"
    
    # 运行测试
    cd "$PROJECT_ROOT"
    luajit "$SCRIPT_DIR/csv-stress-test.lua" "$TEST_TYPE"
    
    local exit_code=$?
    
    # 恢复原始配置
    mv "$SCRIPT_DIR/csv-stress-test.lua.bak" "$SCRIPT_DIR/csv-stress-test.lua" 2>/dev/null || true
    
    return $exit_code
}

# 清理测试环境
cleanup() {
    echo ""
    echo "清理测试环境..."
    
    # 删除临时文件
    rm -rf "/tmp/stock_tsdb_csv_test"
    rm -f "/tmp/csv_stress_test_*.csv"
    rm -f "/tmp/csv_export_*.csv"
    
    echo "✅ 环境清理完成"
}

# 主函数
main() {
    echo "Stock-TSDB CSV导入导出压力测试"
    echo "================================"
    
    # 检查依赖
    check_dependencies
    
    # 检查服务状态
    check_service
    
    # 准备测试环境
    prepare_test
    
    # 设置退出时清理
    trap cleanup EXIT
    
    # 运行压力测试
    run_stress_test
    
    local test_result=$?
    
    echo ""
    echo "测试完成，退出码: $test_result"
    
    if [[ $test_result -eq 0 ]]; then
        echo "🎉 压力测试通过！"
    else
        echo "❌ 压力测试失败！"
    fi
    
    exit $test_result
}

# 运行主函数
main "$@"