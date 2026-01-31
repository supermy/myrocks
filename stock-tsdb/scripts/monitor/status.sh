#!/bin/bash

# Stock-TSDB 项目状态检查脚本
# 检查项目完整性、依赖状态和功能可用性

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
Stock-TSDB 项目状态检查脚本

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -c, --check TYPE    检查类型：all（全部）、deps（依赖）、docs（文档）、scripts（脚本）、services（服务）
    -v, --verbose       详细输出
    -f, --fix           尝试自动修复问题

示例:
    # 完整检查
    $0 -c all
    
    # 只检查依赖
    $0 -c deps
    
    # 详细输出并尝试修复
    $0 -c all -v -f

EOF
}

# 默认配置
CHECK_TYPE="all"
VERBOSE=false
FIX_ISSUES=false

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
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查工具依赖
check_tool_dependencies() {
    log_info "检查工具依赖..."
    
    local tools=("luajit" "luarocks" "make" "curl" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool 已安装 ($($tool --version 2>/dev/null | head -1 || echo "版本未知"))"
        else
            log_error "$tool 未安装"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warn "缺失工具: ${missing_tools[*]}"
        if [[ "$FIX_ISSUES" == true ]]; then
            log_info "尝试安装缺失工具..."
            # 这里可以添加自动安装逻辑
            log_warn "自动安装功能暂未实现，请手动安装缺失工具"
        fi
        return 1
    else
        log_success "所有工具依赖检查通过"
        return 0
    fi
}

# 检查Lua依赖
check_lua_dependencies() {
    log_info "检查Lua依赖..."
    
    local lua_deps=("lua-cjson" "luasocket" "lua-llthreads2" "lzmq")
    local missing_deps=()
    
    for dep in "${lua_deps[@]}"; do
        if luarocks list | grep -q "$dep"; then
            log_success "$dep 已安装"
        else
            log_error "$dep 未安装"
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warn "缺失Lua依赖: ${missing_deps[*]}"
        if [[ "$FIX_ISSUES" == true ]]; then
            log_info "尝试安装缺失Lua依赖..."
            for dep in "${missing_deps[@]}"; do
                log_info "安装 $dep..."
                luarocks install "$dep" --local || {
                    log_warn "$dep 安装失败，尝试使用sudo"
                    sudo luarocks install "$dep" || {
                        log_error "$dep 安装失败"
                    }
                }
            done
        fi
        return 1
    else
        log_success "所有Lua依赖检查通过"
        return 0
    fi
}

# 检查项目文档
check_documentation() {
    log_info "检查项目文档..."
    
    local docs=("README.md" "CHANGELOG.md" "DOCUMENTATION_INDEX.md" "PROJECT_STRUCTURE.md")
    local missing_docs=()
    
    for doc in "${docs[@]}"; do
        if [[ -f "$doc" ]]; then
            log_success "$doc 存在"
            if [[ "$VERBOSE" == true ]]; then
                log_debug "  - 文件大小: $(wc -c < "$doc") 字节"
                log_debug "  - 最后修改: $(stat -f "%Sm" "$doc" 2>/dev/null || date -r "$doc")"
            fi
        else
            log_error "$doc 缺失"
            missing_docs+=("$doc")
        fi
    done
    
    # 检查docs目录
    if [[ -d "docs" ]]; then
        local doc_count=$(find docs -name "*.md" | wc -l)
        log_success "docs目录存在，包含 $doc_count 个文档文件"
    else
        log_error "docs目录缺失"
        missing_docs+=("docs目录")
    fi
    
    if [[ ${#missing_docs[@]} -gt 0 ]]; then
        log_warn "缺失文档: ${missing_docs[*]}"
        return 1
    else
        log_success "项目文档检查通过"
        return 0
    fi
}

# 检查脚本文件
check_scripts() {
    log_info "检查脚本文件..."
    
    local scripts=(
        "scripts/install/install.sh"
        "scripts/install/production_deploy.sh"
        "scripts/install/monitor_production.sh"
        "scripts/install/backup_production.sh"
        "scripts/install/maintain_production.sh"
        "scripts/start_business_web.sh"
        "scripts/check_project_status.sh"
    )
    local missing_scripts=()
    local invalid_scripts=()
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # 检查脚本是否可执行
            if [[ -x "$script" ]]; then
                log_success "$script 存在且可执行"
            else
                log_warn "$script 存在但不可执行"
                invalid_scripts+=("$script")
                if [[ "$FIX_ISSUES" == true ]]; then
                    log_info "设置执行权限: $script"
                    chmod +x "$script"
                fi
            fi
        else
            log_error "$script 缺失"
            missing_scripts+=("$script")
        fi
    done
    
    if [[ ${#missing_scripts[@]} -gt 0 ]] || [[ ${#invalid_scripts[@]} -gt 0 ]]; then
        if [[ ${#missing_scripts[@]} -gt 0 ]]; then
            log_warn "缺失脚本: ${missing_scripts[*]}"
        fi
        if [[ ${#invalid_scripts[@]} -gt 0 ]]; then
            log_warn "无效脚本: ${invalid_scripts[*]}"
        fi
        return 1
    else
        log_success "脚本文件检查通过"
        return 0
    fi
}

# 检查服务状态
check_services() {
    log_info "检查服务状态..."
    
    local services=(
        "Redis集群服务器:6379"
        "元数据Web服务器:8080"
        "业务数据Web服务器:8081"
    )
    local running_services=()
    local stopped_services=()
    
    for service_info in "${services[@]}"; do
        local service_name="${service_info%:*}"
        local service_port="${service_info#*:}"
        
        if netstat -tuln 2>/dev/null | grep -q ":$service_port "; then
            log_success "$service_name 运行中 (端口: $service_port)"
            running_services+=("$service_name")
        else
            log_warn "$service_name 未运行 (端口: $service_port)"
            stopped_services+=("$service_name")
        fi
    done
    
    if [[ ${#stopped_services[@]} -gt 0 ]]; then
        log_warn "未运行的服务: ${stopped_services[*]}"
        if [[ "$FIX_ISSUES" == true ]]; then
            log_info "尝试启动服务..."
            # 这里可以添加自动启动服务的逻辑
            log_warn "自动启动服务功能暂未实现"
        fi
        return 1
    else
        log_success "所有服务运行正常"
        return 0
    fi
}

# 检查Makefile功能
check_makefile() {
    log_info "检查Makefile功能..."
    
    if [[ -f "Makefile" ]]; then
        log_success "Makefile 存在"
        
        # 测试基本Makefile目标
        local targets=("build" "test-quick" "health-check")
        
        for target in "${targets[@]}"; do
            if make -n "$target" &> /dev/null; then
                log_success "Makefile目标 '$target' 有效"
            else
                log_error "Makefile目标 '$target' 无效"
                return 1
            fi
        done
        
        log_success "Makefile功能检查通过"
        return 0
    else
        log_error "Makefile 缺失"
        return 1
    fi
}

# 生成检查报告
generate_report() {
    local check_results=("$@")
    local total_checks=${#check_results[@]}
    local passed_checks=0
    local failed_checks=0
    
    echo ""
    echo "=== 项目状态检查报告 ==="
    echo "检查时间: $(date)"
    echo "检查类型: $CHECK_TYPE"
    echo ""
    
    for result in "${check_results[@]}"; do
        local check_name="${result%:*}"
        local status="${result#*:}"
        
        if [[ "$status" == "0" ]]; then
            echo "✓ $check_name: 通过"
            ((passed_checks++))
        else
            echo "✗ $check_name: 失败"
            ((failed_checks++))
        fi
    done
    
    echo ""
    echo "=== 检查结果汇总 ==="
    echo "总检查项: $total_checks"
    echo "通过项: $passed_checks"
    echo "失败项: $failed_checks"
    
    if [[ $failed_checks -eq 0 ]]; then
        log_success "项目状态检查全部通过！"
        return 0
    else
        log_error "项目状态检查发现 $failed_checks 个问题"
        return 1
    fi
}

# 主函数
main() {
    log_info "Stock-TSDB 项目状态检查开始"
    log_info "检查类型: $CHECK_TYPE, 详细输出: $VERBOSE, 自动修复: $FIX_ISSUES"
    
    local check_results=()
    
    # 根据检查类型执行相应的检查
    case "$CHECK_TYPE" in
        "all")
            check_tool_dependencies && check_results+=("工具依赖:0") || check_results+=("工具依赖:1")
            check_lua_dependencies && check_results+=("Lua依赖:0") || check_results+=("Lua依赖:1")
            check_documentation && check_results+=("项目文档:0") || check_results+=("项目文档:1")
            check_scripts && check_results+=("脚本文件:0") || check_results+=("脚本文件:1")
            check_services && check_results+=("服务状态:0") || check_results+=("服务状态:1")
            check_makefile && check_results+=("Makefile功能:0") || check_results+=("Makefile功能:1")
            ;;
        "deps")
            check_tool_dependencies && check_results+=("工具依赖:0") || check_results+=("工具依赖:1")
            check_lua_dependencies && check_results+=("Lua依赖:0") || check_results+=("Lua依赖:1")
            ;;
        "docs")
            check_documentation && check_results+=("项目文档:0") || check_results+=("项目文档:1")
            ;;
        "scripts")
            check_scripts && check_results+=("脚本文件:0") || check_results+=("脚本文件:1")
            ;;
        "services")
            check_services && check_results+=("服务状态:0") || check_results+=("服务状态:1")
            ;;
        *)
            log_error "未知的检查类型: $CHECK_TYPE"
            show_help
            exit 1
            ;;
    esac
    
    # 生成检查报告
    generate_report "${check_results[@]}"
}

# 运行主函数
main "$@"