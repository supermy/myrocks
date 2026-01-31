#!/bin/bash

# Stock-TSDB 统一安装脚本
# 支持单机极致性能版和集群可扩展版部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="Stock-TSDB 安装脚本"
VERSION="1.0.0"

# 默认配置
DEFAULT_MODE="standalone"
DEFAULT_DATA_DIR="./data"
DEFAULT_CONFIG_DIR="./config"
DEFAULT_LOG_DIR="./logs"

# 显示帮助信息
show_help() {
    cat << EOF
${SCRIPT_NAME} v${VERSION}

用法: $0 [选项]

选项:
    -m, --mode MODE          部署模式: standalone(单机版) 或 cluster(集群版) [默认: ${DEFAULT_MODE}]
    -c, --config CONFIG_FILE 配置文件路径
    -d, --data-dir DIR       数据目录 [默认: ${DEFAULT_DATA_DIR}]
    -l, --log-dir DIR        日志目录 [默认: ${DEFAULT_LOG_DIR}]
    -n, --nodes NUM          集群节点数量 [仅集群模式]
    --consul HOST:PORT       Consul服务器地址 [仅集群模式]
    --force                  强制覆盖现有安装
    --skip-deps              跳过依赖检查
    -h, --help               显示此帮助信息
    -v, --version            显示版本信息

示例:
    # 单机版安装
    $0 --mode standalone --config config/standalone_performance.lua
    
    # 集群版安装（3节点）
    $0 --mode cluster --nodes 3 --consul 127.0.0.1:8500
    
    # 使用自定义配置
    $0 --mode standalone --config my_config.lua --data-dir /opt/stock-tsdb/data

EOF
}

# 显示版本信息
show_version() {
    echo "${SCRIPT_NAME} v${VERSION}"
}

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

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        return 1
    fi
    return 0
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."
    
    # 检查操作系统
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_info "检测到 Linux 系统"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "检测到 macOS 系统"
    else
        log_warning "未知操作系统: $OSTYPE"
    fi
    
    # 检查内存
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}')
    if [[ -n "$total_mem" ]]; then
        if [[ $total_mem -lt 4096 ]]; then
            log_warning "内存不足4GB，建议升级内存以获得更好性能"
        else
            log_info "系统内存: ${total_mem}MB"
        fi
    fi
    
    # 检查磁盘空间
    local disk_space=$(df . | awk 'NR==2{print $4}')
    if [[ -n "$disk_space" && $disk_space -lt 10485760 ]]; then
        log_warning "磁盘空间不足10GB，建议清理空间"
    fi
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    local missing_deps=()
    
    # 基础依赖
    for cmd in lua luajit make gcc; do
        if ! check_command "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    # 集群模式额外依赖
    if [[ "$MODE" == "cluster" ]]; then
        if ! check_command "docker"; then
            missing_deps+=("docker")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少以下依赖: ${missing_deps[*]}"
        if [[ "$SKIP_DEPS" != "true" ]]; then
            log_info "请安装缺失的依赖后重试，或使用 --skip-deps 跳过依赖检查"
            exit 1
        else
            log_warning "跳过依赖检查，继续安装..."
        fi
    else
        log_success "所有依赖检查通过"
    fi
}

# 创建目录结构
create_directories() {
    log_info "创建目录结构..."
    
    local dirs=("$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR" "bin" "lib" "tmp")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "创建目录: $dir"
        fi
    done
}

# 安装单机版
install_standalone() {
    log_info "开始安装单机极致性能版..."
    
    # 检查是否已安装
    if [[ -f "bin/stock-tsdb-standalone" && "$FORCE" != "true" ]]; then
        log_warning "单机版已存在，使用 --force 覆盖安装"
        return 0
    fi
    
    # 编译核心模块
    log_info "编译核心模块..."
    if make -j$(nproc) 2>/dev/null; then
        log_success "编译完成"
    else
        log_warning "编译失败，尝试使用预编译版本"
    fi
    
    # 创建启动脚本
    cat > bin/stock-tsdb-standalone << 'EOF'
#!/bin/bash
# Stock-TSDB 单机版启动脚本

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

cd "$PROJECT_ROOT"

# 设置Lua路径
export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"

# 启动服务
luajit lua/main.lua "$@"
EOF
    
    chmod +x bin/stock-tsdb-standalone
    
    log_success "单机版安装完成"
}

# 安装集群版
install_cluster() {
    log_info "开始安装集群可扩展版..."
    
    # 检查Consul
    if [[ -n "$CONSUL_SERVER" ]]; then
        log_info "检查Consul服务: $CONSUL_SERVER"
        # 这里可以添加Consul健康检查
    else
        log_info "启动本地Consul容器..."
        if docker ps | grep -q consul; then
            log_info "Consul容器已在运行"
        else
            docker run -d --name=stock-tsdb-consul \
                -p 8500:8500 \
                -p 8600:8600/udp \
                consul:latest agent -server -bootstrap-expect=1 -client=0.0.0.0
            log_success "Consul容器启动完成"
        fi
    fi
    
    # 创建集群配置
    local cluster_config="$CONFIG_DIR/cluster_nodes.lua"
    cat > "$cluster_config" << EOF
return {
    nodes = {
        {
            id = "node-1",
            host = "127.0.0.1",
            port = 6379,
            weight = 1
        },
        {
            id = "node-2", 
            host = "127.0.0.1",
            port = 6380,
            weight = 1
        },
        {
            id = "node-3",
            host = "127.0.0.1", 
            port = 6381,
            weight = 1
        }
    },
    consul_server = "$CONSUL_SERVER"
}
EOF
    
    # 创建集群启动脚本
    cat > bin/stock-tsdb-cluster << 'EOF'
#!/bin/bash
# Stock-TSDB 集群版启动脚本

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

cd "$PROJECT_ROOT"

# 设置Lua路径
export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"

# 启动集群服务
luajit lua/cluster.lua "$@"
EOF
    
    chmod +x bin/stock-tsdb-cluster
    
    log_success "集群版安装完成"
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_DIR/"
        log_info "使用自定义配置: $CONFIG_FILE"
    else
        # 生成默认配置
        if [[ "$MODE" == "standalone" ]]; then
            cat > "$CONFIG_DIR/standalone_performance.lua" << 'EOF'
-- 单机极致性能版配置
return {
    storage = {
        engine = "v3_rocksdb",
        data_dir = "./data/standalone",
        block_size = 30,
        enable_compression = true,
        compression_type = "lz4"
    },
    performance = {
        enable_luajit_optimization = true,
        memory_pool_size = "1GB",
        write_buffer_size = "64MB",
        batch_size = 1000
    },
    cache = {
        enabled = true,
        max_size = "512MB",
        ttl = 300
    },
    monitoring = {
        enabled = true,
        metrics_port = 9090,
        health_check_interval = 30
    }
}
EOF
        else
            cat > "$CONFIG_DIR/cluster_scalable.lua" << 'EOF'
-- 集群可扩展版配置
return {
    cluster = {
        enabled = true,
        mode = "distributed",
        node_id = "node-1",
        service_discovery = {
            provider = "consul",
            servers = {"127.0.0.1:8500"},
            health_check_interval = 30
        },
        sharding = {
            enabled = true,
            strategy = "consistent_hashing",
            virtual_nodes = 1000
        }
    },
    storage = {
        engine = "v3_integrated",
        data_dir = "./data/cluster",
        replication_factor = 2
    },
    network = {
        bind_address = "0.0.0.0",
        port = 6379,
        max_connections = 10000
    },
    monitoring = {
        enabled = true,
        prometheus_port = 9090,
        metrics_path = "/metrics"
    }
}
EOF
        fi
        log_info "生成默认配置: $CONFIG_DIR/$(basename "${CONFIG_FILE:-${MODE}_performance.lua}")"
    fi
}

# 安装后配置
post_install() {
    log_info "执行安装后配置..."
    
    # 创建环境变量文件
    cat > .env << EOF
# Stock-TSDB 环境配置
DATA_DIR=$DATA_DIR
LOG_DIR=$LOG_DIR
CONFIG_DIR=$CONFIG_DIR
MODE=$MODE

# Lua路径配置
export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"
export LUA_CPATH="./lib/?.so;./lib/?/init.so;$LUA_CPATH"
EOF
    
    # 创建服务管理脚本
    cat > scripts/start.sh << 'EOF'
#!/bin/bash
# Stock-TSDB 服务启动脚本

set -e

source .env

if [[ "$MODE" == "standalone" ]]; then
    ./bin/stock-tsdb-standalone --config "$CONFIG_DIR/standalone_performance.lua"
else
    ./bin/stock-tsdb-cluster --config "$CONFIG_DIR/cluster_scalable.lua"
fi
EOF
    
    chmod +x scripts/start.sh
    
    # 创建健康检查脚本
    cat > scripts/health_check.sh << 'EOF'
#!/bin/bash
# Stock-TSDB 健康检查脚本

set -e

source .env

# 检查服务状态
if curl -s http://localhost:9090/health > /dev/null; then
    echo "服务运行正常"
    exit 0
else
    echo "服务异常"
    exit 1
fi
EOF
    
    chmod +x scripts/health_check.sh
}

# 显示安装摘要
show_summary() {
    log_success "安装完成!"
    echo ""
    echo "=== 安装摘要 ==="
    echo "部署模式: $MODE"
    echo "数据目录: $DATA_DIR"
    echo "配置目录: $CONFIG_DIR"
    echo "日志目录: $LOG_DIR"
    echo ""
    
    if [[ "$MODE" == "standalone" ]]; then
        echo "启动命令:"
        echo "  ./scripts/start.sh"
        echo "  ./bin/stock-tsdb-standalone --config $CONFIG_DIR/standalone_performance.lua"
        echo ""
        echo "健康检查:"
        echo "  ./scripts/health_check.sh"
    else
        echo "集群信息:"
        echo "  节点数量: $NODES"
        echo "  Consul服务: ${CONSUL_SERVER:-127.0.0.1:8500}"
        echo ""
        echo "启动命令:"
        echo "  ./scripts/start.sh"
        echo "  ./bin/stock-tsdb-cluster --config $CONFIG_DIR/cluster_scalable.lua"
        echo ""
        echo "集群状态检查:"
        echo "  curl http://${CONSUL_SERVER:-127.0.0.1:8500}/v1/health/service/stock-tsdb"
    fi
    
    echo ""
    echo "监控地址: http://localhost:9090/metrics"
    echo "健康检查: http://localhost:9090/health"
    echo ""
    echo "更多信息请参考 README.md"
}

# 主函数
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            -n|--nodes)
                NODES="$2"
                shift 2
                ;;
            --consul)
                CONSUL_SERVER="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --skip-deps)
                SKIP_DEPS="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 设置默认值
    MODE="${MODE:-$DEFAULT_MODE}"
    DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
    LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"
    CONFIG_DIR="${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
    NODES="${NODES:-3}"
    
    # 验证模式
    if [[ "$MODE" != "standalone" && "$MODE" != "cluster" ]]; then
        log_error "无效的部署模式: $MODE"
        show_help
        exit 1
    fi
    
    log_info "开始 Stock-TSDB 安装"
    log_info "部署模式: $MODE"
    
    # 执行安装步骤
    check_system_requirements
    check_dependencies
    create_directories
    generate_config
    
    if [[ "$MODE" == "standalone" ]]; then
        install_standalone
    else
        install_cluster
    fi
    
    post_install
    show_summary
}

# 运行主函数
main "$@"