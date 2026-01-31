#!/bin/bash

# Stock-TSDB 开发环境设置脚本
# 为开发者快速搭建完整的开发环境

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
Stock-TSDB 开发环境设置脚本

用法: $0 [选项]

选项:
    -h, --help          显示帮助信息
    -f, --full          完整设置（包括所有依赖和工具）
    -b, --basic         基础设置（仅必需依赖）
    -t, --tools         仅安装开发工具
    -d, --deps          仅安装依赖
    -c, --check         仅检查环境状态
    -v, --verbose       详细输出

示例:
    # 完整开发环境设置
    $0 -f
    
    # 仅检查环境状态
    $0 -c
    
    # 基础设置
    $0 -b

EOF
}

# 默认配置
SETUP_TYPE="basic"
VERBOSE=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--full)
            SETUP_TYPE="full"
            shift
            ;;
        -b|--basic)
            SETUP_TYPE="basic"
            shift
            ;;
        -t|--tools)
            SETUP_TYPE="tools"
            shift
            ;;
        -d|--deps)
            SETUP_TYPE="deps"
            shift
            ;;
        -c|--check)
            SETUP_TYPE="check"
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查操作系统
check_os() {
    log_info "检查操作系统..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_success "Linux 系统检测"
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log_success "macOS 系统检测"
        OS="macos"
    else
        log_error "不支持的操作系统: $OSTYPE"
        exit 1
    fi
    
    # 检测包管理器
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        log_success "检测到 apt 包管理器"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        log_success "检测到 yum 包管理器"
    elif command -v brew &> /dev/null; then
        PKG_MANAGER="brew"
        log_success "检测到 Homebrew 包管理器"
    else
        log_warn "未检测到包管理器，部分功能可能受限"
        PKG_MANAGER="unknown"
    fi
}

# 安装系统依赖
install_system_deps() {
    log_info "安装系统依赖..."
    
    case "$OS" in
        "linux")
            case "$PKG_MANAGER" in
                "apt")
                    sudo apt-get update
                    sudo apt-get install -y build-essential git curl wget \
                        autoconf automake libtool pkg-config \
                        libssl-dev zlib1g-dev libreadline-dev \
                        libsqlite3-dev libmysqlclient-dev \
                        redis-server
                    ;;
                "yum")
                    sudo yum update -y
                    sudo yum install -y gcc gcc-c++ make git curl wget \
                        autoconf automake libtool pkgconfig \
                        openssl-devel zlib-devel readline-devel \
                        sqlite-devel mysql-devel \
                        redis
                    ;;
            esac
            ;;
        "macos")
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                brew update
                brew install git curl wget autoconf automake libtool \
                    pkg-config openssl readline sqlite mysql-client \
                    redis
            else
                log_warn "请先安装 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            fi
            ;;
    esac
    
    log_success "系统依赖安装完成"
}

# 安装开发工具
install_dev_tools() {
    log_info "安装开发工具..."
    
    # 检查并安装 LuaJIT
    if ! command -v luajit &> /dev/null; then
        log_info "安装 LuaJIT..."
        
        if [[ "$PKG_MANAGER" == "brew" ]]; then
            brew install luajit
        else
            # 从源码编译 LuaJIT
            cd /tmp
            wget https://luajit.org/download/LuaJIT-2.0.5.tar.gz
            tar -xzf LuaJIT-2.0.5.tar.gz
            cd LuaJIT-2.0.5
            make && sudo make install
            cd -
        fi
        log_success "LuaJIT 安装完成"
    else
        log_success "LuaJIT 已安装 ($(luajit -v | head -1))"
    fi
    
    # 检查并安装 LuaRocks
    if ! command -v luarocks &> /dev/null; then
        log_info "安装 LuaRocks..."
        
        if [[ "$PKG_MANAGER" == "brew" ]]; then
            brew install luarocks
        else
            # 从源码编译 LuaRocks
            cd /tmp
            wget https://luarocks.org/releases/luarocks-3.9.1.tar.gz
            tar -xzf luarocks-3.9.1.tar.gz
            cd luarocks-3.9.1
            ./configure --with-lua-include=/usr/local/include/luajit-2.0
            make && sudo make install
            cd -
        fi
        log_success "LuaRocks 安装完成"
    else
        log_success "LuaRocks 已安装 ($(luarocks --version | head -1))"
    fi
    
    # 安装其他开发工具
    local tools=("jq" "tree" "htop" "ncdu")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_info "安装 $tool..."
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                brew install "$tool"
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                sudo apt-get install -y "$tool"
            elif [[ "$PKG_MANAGER" == "yum" ]]; then
                sudo yum install -y "$tool"
            fi
        else
            log_success "$tool 已安装"
        fi
    done
    
    log_success "开发工具安装完成"
}

# 安装 Lua 依赖
install_lua_deps() {
    log_info "安装 Lua 依赖..."
    
    local lua_deps=(
        "lua-cjson"
        "luasocket"
        "lua-llthreads2"
        "lzmq"
        "penlight"
        "inspect"
        "busted"
    )
    
    for dep in "${lua_deps[@]}"; do
        if ! luarocks list | grep -q "$dep"; then
            log_info "安装 Lua 依赖: $dep"
            luarocks install "$dep" --local || {
                log_warn "$dep 安装失败，尝试使用sudo"
                sudo luarocks install "$dep" || {
                    log_error "$dep 安装失败"
                    return 1
                }
            }
            log_success "$dep 安装完成"
        else
            log_success "$dep 已安装"
        fi
    done
    
    log_success "Lua 依赖安装完成"
}

# 配置开发环境
setup_dev_config() {
    log_info "配置开发环境..."
    
    # 创建开发环境配置文件
    if [[ ! -f "conf/dev.env" ]]; then
        cat > "conf/dev.env" << EOF
# Stock-TSDB 开发环境配置

# 数据存储路径
DATA_DIR="\$(pwd)/data/dev"

# Redis 配置
REDIS_HOST="127.0.0.1"
REDIS_PORT=6379

# Web 服务器端口
METADATA_PORT=8080
BUSINESS_PORT=8081

# 开发模式设置
DEV_MODE=true
DEBUG=true
LOG_LEVEL="debug"

# 性能调优（开发环境使用较小值）
BATCH_SIZE=100
CACHE_SIZE=1000

# 测试数据设置
TEST_DATA_ENABLED=true
EOF
        log_success "开发环境配置文件创建完成"
    else
        log_success "开发环境配置文件已存在"
    fi
    
    # 创建必要的目录
    local dirs=("data/dev" "logs/dev" "tmp" "build")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_success "目录创建: $dir"
        else
            log_success "目录已存在: $dir"
        fi
    done
    
    # 设置脚本执行权限
    chmod +x scripts/*.sh
    chmod +x scripts/install/*.sh
    
    log_success "开发环境配置完成"
}

# 构建项目
build_project() {
    log_info "构建项目..."
    
    if make build; then
        log_success "项目构建成功"
    else
        log_error "项目构建失败"
        return 1
    fi
}

# 运行测试
run_tests() {
    log_info "运行测试..."
    
    if make test-quick; then
        log_success "快速测试通过"
    else
        log_warn "快速测试失败，请检查"
    fi
    
    # 运行开发环境测试
    if make dev-test-quick; then
        log_success "开发环境测试通过"
    else
        log_warn "开发环境测试失败"
    fi
}

# 检查环境状态
check_environment() {
    log_info "检查开发环境状态..."
    
    local checks_passed=0
    local checks_failed=0
    
    # 检查工具
    local tools=("luajit" "luarocks" "make" "curl" "git")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool 已安装"
            ((checks_passed++))
        else
            log_error "$tool 未安装"
            ((checks_failed++))
        fi
    done
    
    # 检查 Lua 依赖
    local lua_deps=("lua-cjson" "luasocket" "busted")
    for dep in "${lua_deps[@]}"; do
        if luarocks list | grep -q "$dep"; then
            log_success "Lua 依赖 $dep 已安装"
            ((checks_passed++))
        else
            log_error "Lua 依赖 $dep 未安装"
            ((checks_failed++))
        fi
    done
    
    # 检查项目文件
    local project_files=("Makefile" "README.md" "src" "conf")
    for file in "${project_files[@]}"; do
        if [[ -e "$file" ]]; then
            log_success "项目文件 $file 存在"
            ((checks_passed++))
        else
            log_error "项目文件 $file 缺失"
            ((checks_failed++))
        fi
    done
    
    # 输出检查结果
    echo ""
    echo "=== 环境检查结果 ==="
    echo "通过检查: $checks_passed"
    echo "失败检查: $checks_failed"
    
    if [[ $checks_failed -eq 0 ]]; then
        log_success "开发环境检查全部通过！"
        return 0
    else
        log_error "开发环境检查发现 $checks_failed 个问题"
        return 1
    fi
}

# 显示开发环境信息
show_dev_info() {
    log_info "开发环境信息:"
    
    echo ""
    echo "=== 项目信息 ==="
    echo "项目路径: $(pwd)"
    echo "项目版本: $(git describe --tags 2>/dev/null || echo '未知')"
    
    echo ""
    echo "=== 服务信息 ==="
    echo "Redis 服务器: localhost:6379"
    echo "元数据服务器: localhost:8080"
    echo "业务数据服务器: localhost:8081"
    
    echo ""
    echo "=== 开发命令 ==="
    echo "启动开发环境: make dev-start"
    echo "停止开发环境: make dev-stop"
    echo "运行测试: make test-quick"
    echo "健康检查: make health-check"
    
    echo ""
    echo "=== 文档链接 ==="
    echo "快速开始: docs/guides/QUICK_START.md"
    echo "API 参考: docs/API_REFERENCE.md"
    echo "开发指南: docs/guides/DEVELOPMENT_GUIDE.md"
}

# 主函数
main() {
    log_info "Stock-TSDB 开发环境设置开始"
    log_info "设置类型: $SETUP_TYPE"
    
    # 检查操作系统
    check_os
    
    case "$SETUP_TYPE" in
        "check")
            check_environment
            ;;
        "deps")
            install_system_deps
            install_lua_deps
            ;;
        "tools")
            install_dev_tools
            ;;
        "basic")
            install_system_deps
            install_dev_tools
            install_lua_deps
            setup_dev_config
            build_project
            run_tests
            ;;
        "full")
            install_system_deps
            install_dev_tools
            install_lua_deps
            setup_dev_config
            build_project
            run_tests
            ;;
    esac
    
    # 显示最终信息
    if [[ "$SETUP_TYPE" != "check" ]]; then
        show_dev_info
        log_success "开发环境设置完成！"
        
        echo ""
        log_info "下一步操作:"
        echo "1. 启动开发环境: make dev-start"
        echo "2. 验证安装: make health-check"
        echo "3. 查看文档: cat docs/guides/QUICK_START.md"
    fi
}

# 运行主函数
main "$@"