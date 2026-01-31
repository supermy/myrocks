#!/bin/bash

# Stock-TSDB 项目完整性验证脚本
# 全面验证项目的文件结构、配置、依赖和功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
Stock-TSDB 项目完整性验证脚本

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -c, --check TYPE    检查类型：all（全部）、files（文件）、deps（依赖）、config（配置）、build（构建）、test（测试）
    -v, --verbose       详细输出
    -f, --fix           尝试自动修复问题
    -r, --report        生成详细报告

示例:
    # 完整验证
    $0 -c all
    
    # 仅验证文件结构
    $0 -c files
    
    # 生成详细报告
    $0 -c all -r

EOF
}

# 默认配置
CHECK_TYPE="all"
VERBOSE=false
FIX_ISSUES=false
GENERATE_REPORT=false
REPORT_FILE="project_validation_report_$(date +%Y%m%d_%H%M%S).txt"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--check)
            CHECK_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--fix)
            FIX_ISSUES=true
            shift
            ;;
        -r|--report)
            GENERATE_REPORT=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 报告函数
report() {
    if [[ "$GENERATE_REPORT" == true ]]; then
        echo "$1" >> "$REPORT_FILE"
    fi
    echo "$1"
}

# 检查文件结构
check_file_structure() {
    log_info "检查文件结构..."
    
    local required_files=(
        "README.md"
        "CHANGELOG.md"
        "DOCUMENTATION_INDEX.md"
        "PROJECT_STRUCTURE.md"
        "Makefile"
        "Dockerfile"
        "LICENSE"
        ".gitignore"
        "conf/config.lua"
        "conf/redis.conf"
        "src/main.lua"
        "src/core/"
        "src/storage/"
        "src/api/"
        "scripts/"
        "docs/"
        "tests/"
        "data/"
        "logs/"
    )
    
    local missing_files=()
    local invalid_files=()
    
    for file in "${required_files[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ -d "$file" && "$file" =~ /$ ]]; then
                # 检查目录
                if [[ -d "${file%/}" ]]; then
                    report "✓ 目录存在: $file"
                else
                    report "✗ 目录缺失: $file"
                    missing_files+=("$file")
                fi
            else
                # 检查文件
                if [[ -f "$file" ]]; then
                    local size=$(wc -c < "$file" 2>/dev/null || echo 0)
                    if [[ $size -gt 0 ]]; then
                        report "✓ 文件存在且非空: $file ($size 字节)"
                    else
                        report "✗ 文件为空: $file"
                        invalid_files+=("$file")
                    fi
                else
                    report "✗ 文件缺失: $file"
                    missing_files+=("$file")
                fi
            fi
        else
            report "✗ 文件/目录缺失: $file"
            missing_files+=("$file")
        fi
    done
    
    # 检查脚本文件
    local scripts=(
        "scripts/install/install.sh"
        "scripts/install/production_deploy.sh"
        "scripts/install/monitor_production.sh"
        "scripts/start_business_web.sh"
        "scripts/check_project_status.sh"
        "scripts/setup_dev_env.sh"
        "scripts/validate_project.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                report "✓ 脚本可执行: $script"
            else
                report "✗ 脚本不可执行: $script"
                invalid_files+=("$script")
                if [[ "$FIX_ISSUES" == true ]]; then
                    chmod +x "$script"
                    report "✓ 已修复执行权限: $script"
                fi
            fi
        else
            report "✗ 脚本缺失: $script"
            missing_files+=("$script")
        fi
    done
    
    # 检查文档文件
    local docs=(
        "docs/guides/QUICK_START.md"
        "docs/architecture/SYSTEM_ARCHITECTURE.md"
        "docs/API_REFERENCE.md"
    )
    
    for doc in "${docs[@]}"; do
        if [[ -f "$doc" ]]; then
            local size=$(wc -c < "$doc" 2>/dev/null || echo 0)
            if [[ $size -gt 100 ]]; then
                report "✓ 文档存在: $doc ($size 字节)"
            else
                report "✗ 文档过短: $doc"
                invalid_files+=("$doc")
            fi
        else
            report "✗ 文档缺失: $doc"
            missing_files+=("$doc")
        fi
    done
    
    # 汇总结果
    if [[ ${#missing_files[@]} -eq 0 && ${#invalid_files[@]} -eq 0 ]]; then
        report "✓ 文件结构检查通过"
        return 0
    else
        report "✗ 文件结构检查发现问题"
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            report "  缺失文件: ${missing_files[*]}"
        fi
        if [[ ${#invalid_files[@]} -gt 0 ]]; then
            report "  无效文件: ${invalid_files[*]}"
        fi
        return 1
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    local tools=("luajit" "luarocks" "make" "curl" "git")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            report "✓ 工具已安装: $tool"
        else
            report "✗ 工具未安装: $tool"
            missing_tools+=("$tool")
        fi
    done
    
    local lua_deps=("lua-cjson" "luasocket" "busted")
    local missing_deps=()
    
    for dep in "${lua_deps[@]}"; do
        if luarocks list | grep -q "$dep"; then
            report "✓ Lua依赖已安装: $dep"
        else
            report "✗ Lua依赖未安装: $dep"
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 && ${#missing_deps[@]} -eq 0 ]]; then
        report "✓ 依赖检查通过"
        return 0
    else
        report "✗ 依赖检查发现问题"
        if [[ ${#missing_tools[@]} -gt 0 ]]; then
            report "  缺失工具: ${missing_tools[*]}"
        fi
        if [[ ${#missing_deps[@]} -gt 0 ]]; then
            report "  缺失Lua依赖: ${missing_deps[*]}"
        fi
        return 1
    fi
}

# 检查配置
check_configuration() {
    log_info "检查配置..."
    
    local config_files=("conf/config.lua" "conf/redis.conf")
    local invalid_configs=()
    
    for config in "${config_files[@]}"; do
        if [[ -f "$config" ]]; then
            # 检查配置文件语法
            if [[ "$config" == *.lua ]]; then
                if luajit -e "dofile('$config')" &> /dev/null; then
                    report "✓ Lua配置语法正确: $config"
                else
                    report "✗ Lua配置语法错误: $config"
                    invalid_configs+=("$config")
                fi
            else
                # 简单检查非空
                if [[ -s "$config" ]]; then
                    report "✓ 配置文件非空: $config"
                else
                    report "✗ 配置文件为空: $config"
                    invalid_configs+=("$config")
                fi
            fi
        else
            report "✗ 配置文件缺失: $config"
            invalid_configs+=("$config")
        fi
    done
    
    # 检查环境变量配置
    if [[ -f "conf/dev.env" ]]; then
        report "✓ 开发环境配置存在: conf/dev.env"
    else
        report "✗ 开发环境配置缺失: conf/dev.env"
        invalid_configs+=("conf/dev.env")
    fi
    
    if [[ ${#invalid_configs[@]} -eq 0 ]]; then
        report "✓ 配置检查通过"
        return 0
    else
        report "✗ 配置检查发现问题"
        report "  无效配置: ${invalid_configs[*]}"
        return 1
    fi
}

# 检查构建
check_build() {
    log_info "检查构建..."
    
    # 检查Makefile目标
    local make_targets=("build" "clean" "test-quick" "health-check")
    local invalid_targets=()
    
    for target in "${make_targets[@]}"; do
        if make -n "$target" &> /dev/null; then
            report "✓ Makefile目标有效: $target"
        else
            report "✗ Makefile目标无效: $target"
            invalid_targets+=("$target")
        fi
    done
    
    # 尝试构建
    if make build &> /dev/null; then
        report "✓ 项目构建成功"
    else
        report "✗ 项目构建失败"
        invalid_targets+=("build")
    fi
    
    if [[ ${#invalid_targets[@]} -eq 0 ]]; then
        report "✓ 构建检查通过"
        return 0
    else
        report "✗ 构建检查发现问题"
        report "  构建问题: ${invalid_targets[*]}"
        return 1
    fi
}

# 检查测试
check_tests() {
    log_info "检查测试..."
    
    # 检查测试文件
    local test_files=("tests/test_core.lua" "tests/test_storage.lua" "tests/test_api.lua")
    local missing_tests=()
    
    for test in "${test_files[@]}"; do
        if [[ -f "$test" ]]; then
            report "✓ 测试文件存在: $test"
        else
            report "✗ 测试文件缺失: $test"
            missing_tests+=("$test")
        fi
    done
    
    # 运行快速测试
    if make test-quick &> /dev/null; then
        report "✓ 快速测试通过"
    else
        report "✗ 快速测试失败"
        missing_tests+=("test-quick")
    fi
    
    if [[ ${#missing_tests[@]} -eq 0 ]]; then
        report "✓ 测试检查通过"
        return 0
    else
        report "✗ 测试检查发现问题"
        report "  测试问题: ${missing_tests[*]}"
        return 1
    fi
}

# 检查服务
check_services() {
    log_info "检查服务..."
    
    local services=(
        "Redis集群服务器:6379"
        "元数据Web服务器:8080"
        "业务数据Web服务器:8081"
    )
    local stopped_services=()
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_port="${service_info#*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$service_port "; then
            report "✓ 服务运行中: $service_name (端口: $service_port)"
        else
            report "✗ 服务未运行: $service_name (端口: $service_port)"
            stopped_services+=("$service_name")
        fi
    done
    
    if [[ ${#stopped_services[@]} -eq 0 ]]; then
        report "✓ 服务检查通过"
        return 0
    else
        report "✗ 服务检查发现问题"
        report "  未运行服务: ${stopped_services[*]}"
        return 1
    fi
}

# 生成详细报告
generate_detailed_report() {
    local check_results=("$@")
    local total_checks=${#check_results[@]}
    local passed_checks=0
    local failed_checks=0
    
    echo "" >> "$REPORT_FILE"
    echo "=== Stock-TSDB 项目完整性验证报告 ===" >> "$REPORT_FILE"
    echo "验证时间: $(date)" >> "$REPORT_FILE"
    echo "验证类型: $CHECK_TYPE" >> "$REPORT_FILE"
    echo "项目路径: $(pwd)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for result in "${check_results[@]}"; do
        local check_name="${result%:*}"
        local status="${result#*:}"
        
        if [[ "$status" == "0" ]]; then
            echo "✓ $check_name: 通过" >> "$REPORT_FILE"
            ((passed_checks++))
        else
            echo "✗ $check_name: 失败" >> "$REPORT_FILE"
            ((failed_checks++))
        fi
    done
    
    echo "" >> "$REPORT_FILE"
    echo "=== 验证结果汇总 ===" >> "$REPORT_FILE"
    echo "总检查项: $total_checks" >> "$REPORT_FILE"
    echo "通过项: $passed_checks" >> "$REPORT_FILE"
    echo "失败项: $failed_checks" >> "$REPORT_FILE"
    echo "通过率: $((passed_checks * 100 / total_checks))%" >> "$REPORT_FILE"
    
    if [[ $failed_checks -eq 0 ]]; then
        echo "" >> "$REPORT_FILE"
        echo "🎉 项目完整性验证全部通过！" >> "$REPORT_FILE"
        echo "项目处于健康状态，可以正常使用。" >> "$REPORT_FILE"
    else
        echo "" >> "$REPORT_FILE"
        echo "⚠️ 项目完整性验证发现 $failed_checks 个问题" >> "$REPORT_FILE"
        echo "请根据报告中的问题描述进行修复。" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "=== 建议操作 ===" >> "$REPORT_FILE"
    if [[ $failed_checks -gt 0 ]]; then
        echo "1. 查看详细错误信息" >> "$REPORT_FILE"
        echo "2. 运行修复命令: $0 -c all -f" >> "$REPORT_FILE"
        echo "3. 重新验证项目" >> "$REPORT_FILE"
    fi
    echo "4. 查看文档: cat docs/guides/QUICK_START.md" >> "$REPORT_FILE"
    echo "5. 启动服务: make dev-start" >> "$REPORT_FILE"
}

# 主函数
main() {
    log_info "Stock-TSDB 项目完整性验证开始"
    log_info "检查类型: $CHECK_TYPE, 详细输出: $VERBOSE, 自动修复: $FIX_ISSUES, 生成报告: $GENERATE_REPORT"
    
    # 初始化报告文件
    if [[ "$GENERATE_REPORT" == true ]]; then
        echo "# Stock-TSDB 项目完整性验证报告" > "$REPORT_FILE"
        echo "生成时间: $(date)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
    
    local check_results=()
    
    # 根据检查类型执行相应的检查
    case "$CHECK_TYPE" in
        "all")
            check_file_structure && check_results+=("文件结构:0") || check_results+=("文件结构:1")
            check_dependencies && check_results+=("依赖:0") || check_results+=("依赖:1")
            check_configuration && check_results+=("配置:0") || check_results+=("配置:1")
            check_build && check_results+=("构建:0") || check_results+=("构建:1")
            check_tests && check_results+=("测试:0") || check_results+=("测试:1")
            check_services && check_results+=("服务:0") || check_results+=("服务:1")
            ;;
        "files")
            check_file_structure && check_results+=("文件结构:0") || check_results+=("文件结构:1")
            ;;
        "deps")
            check_dependencies && check_results+=("依赖:0") || check_results+=("依赖:1")
            ;;
        "config")
            check_configuration && check_results+=("配置:0") || check_results+=("配置:1")
            ;;
        "build")
            check_build && check_results+=("构建:0") || check_results+=("构建:1")
            ;;
        "test")
            check_tests && check_results+=("测试:0") || check_results+=("测试:1")
            ;;
        *)
            log_error "未知的检查类型: $CHECK_TYPE"
            show_help
            exit 1
            ;;
    esac
    
    # 生成详细报告
    if [[ "$GENERATE_REPORT" == true ]]; then
        generate_detailed_report "${check_results[@]}"
        log_success "详细报告已生成: $REPORT_FILE"
    fi
    
    # 汇总结果
    local total_checks=${#check_results[@]}
    local passed_checks=0
    local failed_checks=0
    
    for result in "${check_results[@]}"; do
        if [[ "${result#*:}" == "0" ]]; then
            ((passed_checks++))
        else
            ((failed_checks++))
        fi
    done
    
    echo ""
    echo "=== 验证结果汇总 ==="
    echo "总检查项: $total_checks"
    echo "通过项: $passed_checks"
    echo "失败项: $failed_checks"
    
    if [[ $failed_checks -eq 0 ]]; then
        log_success "🎉 项目完整性验证全部通过！"
        echo "项目处于健康状态，可以正常使用。"
    else
        log_error "⚠️ 项目完整性验证发现 $failed_checks 个问题"
        echo "请根据错误信息进行修复，或使用 -f 选项尝试自动修复。"
        exit 1
    fi
}

# 运行主函数
main "$@"