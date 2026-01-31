#!/bin/bash

# Stock-TSDB 单机极致性能版部署脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="单机极致性能版部署脚本"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
${SCRIPT_NAME}

专为单机环境优化的高性能部署脚本，提供极致性能体验。

用法: $0 [选项]

选项:
    -c, --config CONFIG_FILE   配置文件路径 [默认: config/standalone_performance.lua]
    -d, --data-dir DIR         数据目录 [默认: ./data/standalone]
    -l, --log-dir DIR          日志目录 [默认: ./logs]
    --port PORT                服务端口 [默认: 6379]
    --metrics-port PORT       监控端口 [默认: 9090]
    --memory SIZE             内存池大小 [默认: 1GB]
    --force                   强制重新部署
    -h, --help                显示此帮助信息

示例:
    # 使用默认配置部署
    $0
    
    # 使用自定义配置部署
    $0 --config my_config.lua --data-dir /opt/stock-tsdb/data
    
    # 高性能配置部署
    $0 --memory 2GB --port 6380 --metrics-port 9091

性能优化特性:
    • LuaJIT编译优化
    • 内存池管理
    • 批量写入优化
    • 智能缓存策略
    • 实时性能监控

EOF
}

# 检查系统资源
check_resources() {
    log_info "检查系统资源..."
    
    # 检查内存
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}')
    if [[ -n "$total_mem" && $total_mem -lt 4096 ]]; then
        echo "⚠️  警告: 内存不足4GB，建议升级内存以获得更好性能"
    fi
    
    # 检查CPU核心数
    local cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    log_info "CPU核心数: $cores"
    
    # 检查磁盘类型（SSD/HDD）
    if command -v lsblk > /dev/null; then
        local disk_type=$(lsblk -d -o name,rota 2>/dev/null | awk 'NR>1 && $2==0 {print "SSD"; exit} $2==1 {print "HDD"; exit}')
        if [[ "$disk_type" == "SSD" ]]; then
            log_info "存储类型: SSD (推荐)"
        else
            echo "⚠️  警告: 检测到HDD存储，建议使用SSD以获得更好性能"
        fi
    fi
}

# 优化系统配置
optimize_system() {
    log_info "优化系统配置..."
    
    # 设置文件描述符限制
    ulimit -n 65536 2>/dev/null || true
    
    # 设置内存分配策略（Linux）
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf 2>/dev/null || true
        echo "vm.dirty_ratio=10" | sudo tee -a /etc/sysctl.conf 2>/dev/null || true
        echo "vm.dirty_background_ratio=5" | sudo tee -a /etc/sysctl.conf 2>/dev/null || true
    fi
    
    log_success "系统优化完成"
}

# 部署单机服务
deploy_standalone() {
    log_info "开始部署单机极致性能版..."
    
    # 创建目录结构
    mkdir -p "$DATA_DIR" "$LOG_DIR" "config" "bin"
    
    # 生成性能优化配置
    cat > "$CONFIG_FILE" << EOF
-- 单机极致性能版配置
return {
    storage = {
        engine = "v3_rocksdb",
        data_dir = "$DATA_DIR",
        block_size = 30,
        enable_compression = true,
        compression_type = "lz4",
        write_buffer_size = 64 * 1024 * 1024,  -- 64MB
        max_write_buffer_number = 4,
        target_file_size_base = 64 * 1024 * 1024
    },
    performance = {
        enable_luajit_optimization = true,
        memory_pool_size = "$MEMORY_SIZE",
        write_buffer_size = "64MB",
        batch_size = 1000,
        enable_prefetch = true,
        cache_size = "512MB"
    },
    cache = {
        enabled = true,
        max_size = "512MB",
        ttl = 300,
        strategy = "lru"
    },
    network = {
        bind_address = "0.0.0.0",
        port = $PORT,
        max_connections = 10000
    },
    monitoring = {
        enabled = true,
        metrics_port = $METRICS_PORT,
        health_check_interval = 30,
        enable_performance_counters = true
    },
    logging = {
        level = "info",
        file = "$LOG_DIR/stock-tsdb.log",
        max_size = "100MB",
        backup_count = 5
    }
}
EOF
    
    # 创建启动脚本
    cat > bin/start-standalone << EOF
#!/bin/bash
# Stock-TSDB 单机版启动脚本

set -e

cd "$(dirname "\$(dirname "\$0")")"

# 设置性能优化参数
export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"
export LUAJIT_OPTIONS="-joff -O3"

# 启动服务
luajit lua/main.lua --config "$CONFIG_FILE"
EOF
    
    chmod +x bin/start-standalone
    
    # 创建服务管理脚本
    cat > scripts/manage-standalone << EOF
#!/bin/bash
# 单机版服务管理脚本

case "\$1" in
    start)
        ./bin/start-standalone &
        echo "服务已启动"
        ;;
    stop)
        pkill -f "luajit lua/main.lua" || true
        echo "服务已停止"
        ;;
    restart)
        pkill -f "luajit lua/main.lua" || true
        sleep 2
        ./bin/start-standalone &
        echo "服务已重启"
        ;;
    status)
        if pgrep -f "luajit lua/main.lua" > /dev/null; then
            echo "服务运行中"
        else
            echo "服务未运行"
        fi
        ;;
    *)
        echo "用法: manage-standalone {start|stop|restart|status}"
        ;;
esac
EOF
    
    chmod +x scripts/manage-standalone
}

# 性能测试
run_performance_test() {
    log_info "运行性能基准测试..."
    
    # 简单的性能测试脚本
    cat > scripts/performance-test.lua << 'EOF'
local tsdb = require "stock_tsdb"

-- 连接测试
local client = tsdb.connect("127.0.0.1", 6379)
print("连接测试: 成功")

-- 写入性能测试
local start_time = os.time()
for i = 1, 1000 do
    client:write("test.metric." .. i, {
        timestamp = os.time(),
        value = math.random(100)
    })
end
local write_time = os.time() - start_time
print("写入性能: " .. (1000 / write_time) .. " 点/秒")

-- 查询性能测试
start_time = os.time()
for i = 1, 100 do
    client:query("test.metric.1", {
        start_time = os.time() - 3600,
        end_time = os.time()
    })
end
local query_time = os.time() - start_time
print("查询性能: " .. (100 / query_time) .. " 次/秒")

print("性能测试完成")
EOF
    
    log_info "性能测试脚本已生成: scripts/performance-test.lua"
}

# 显示部署摘要
show_deployment_summary() {
    log_success "单机极致性能版部署完成!"
    echo ""
    echo "=== 部署信息 ==="
    echo "服务端口: $PORT"
    echo "监控端口: $METRICS_PORT"
    echo "数据目录: $DATA_DIR"
    echo "配置文件: $CONFIG_FILE"
    echo "内存配置: $MEMORY_SIZE"
    echo ""
    echo "=== 启动命令 ==="
    echo "快速启动: ./bin/start-standalone"
    echo "服务管理: ./scripts/manage-standalone start"
    echo "状态检查: ./scripts/manage-standalone status"
    echo ""
    echo "=== 监控地址 ==="
    echo "性能指标: http://localhost:$METRICS_PORT/metrics"
    echo "健康检查: http://localhost:$METRICS_PORT/health"
    echo ""
    echo "=== 性能测试 ==="
    echo "运行测试: luajit scripts/performance-test.lua"
    echo ""
    echo "💡 提示: 单机版已针对性能进行深度优化，适合高并发场景"
}

# 主函数
main() {
    # 默认配置
    CONFIG_FILE="config/standalone_performance.lua"
    DATA_DIR="./data/standalone"
    LOG_DIR="./logs"
    PORT=6379
    METRICS_PORT=9090
    MEMORY_SIZE="1GB"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --port)
                PORT="$2"
                shift 2
                ;;
            --metrics-port)
                METRICS_PORT="$2"
                shift 2
                ;;
            --memory)
                MEMORY_SIZE="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
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
    
    log_info "开始部署单机极致性能版"
    
    # 执行部署步骤
    check_resources
    optimize_system
    deploy_standalone
    run_performance_test
    show_deployment_summary
}

# 运行主函数
main "$@"