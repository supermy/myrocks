#!/bin/bash

# Stock-TSDB 集群可扩展版部署脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本信息
SCRIPT_NAME="集群可扩展版部署脚本"

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

# 显示帮助信息
show_help() {
    cat << EOF
${SCRIPT_NAME}

专为生产环境设计的集群部署脚本，支持水平扩展和高可用性。

用法: $0 [选项]

选项:
    -n, --nodes NUM            集群节点数量 [默认: 3]
    --consul HOST:PORT         Consul服务器地址 [默认: 127.0.0.1:8500]
    --start-port PORT          起始端口号 [默认: 6379]
    --data-dir DIR             数据目录前缀 [默认: ./data/cluster]
    --config CONFIG_FILE       配置文件路径
    --force                    强制重新部署
    --skip-consul             跳过Consul部署
    -h, --help                显示此帮助信息

示例:
    # 部署3节点集群
    $0 --nodes 3
    
    # 部署5节点集群，使用外部Consul
    $0 --nodes 5 --consul consul.company.com:8500
    
    # 自定义端口和数据目录
    $0 --nodes 3 --start-port 7000 --data-dir /data/stock-tsdb

集群特性:
    • 水平扩展能力
    • 自动数据分片
    • 负载均衡
    • 故障自动恢复
    • 服务发现
    • 监控告警

EOF
}

# 检查集群依赖
check_cluster_dependencies() {
    log_info "检查集群依赖..."
    
    # 检查Docker（用于Consul）
    if ! command -v docker &> /dev/null && [[ "$SKIP_CONSUL" != "true" ]]; then
        log_warning "Docker未安装，将跳过Consul部署"
        SKIP_CONSUL="true"
    fi
    
    # 检查网络工具
    for cmd in curl nc; do
        if ! command -v "$cmd" &> /dev/null; then
            log_warning "命令 '$cmd' 未找到，部分功能可能受限"
        fi
    done
}

# 部署Consul集群
deploy_consul() {
    if [[ "$SKIP_CONSUL" == "true" ]]; then
        log_info "跳过Consul部署"
        return 0
    fi
    
    log_info "部署Consul服务发现集群..."
    
    # 检查Consul是否已运行
    if docker ps | grep -q consul; then
        log_info "Consul容器已在运行"
        return 0
    fi
    
    # 停止可能存在的旧容器
    docker rm -f stock-tsdb-consul 2>/dev/null || true
    
    # 启动Consul容器
    docker run -d \
        --name=stock-tsdb-consul \
        -p 8500:8500 \
        -p 8600:8600/udp \
        consul:latest agent -server -bootstrap-expect=1 -client=0.0.0.0
    
    # 等待Consul启动
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s http://127.0.0.1:8500/v1/status/leader > /dev/null; then
            log_success "Consul启动成功"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_warning "Consul启动超时，但继续部署..."
            break
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
}

# 生成集群配置
generate_cluster_config() {
    log_info "生成集群配置..."
    
    mkdir -p "config" "scripts"
    
    # 生成主集群配置
    cat > "$CONFIG_FILE" << EOF
-- 集群可扩展版配置
return {
    cluster = {
        enabled = true,
        mode = "distributed",
        
        -- 服务发现配置
        service_discovery = {
            provider = "consul",
            servers = {"$CONSUL_SERVER"},
            health_check_interval = 30,
            service_name = "stock-tsdb",
            tags = {"v3", "cluster"}
        },
        
        -- 数据分片配置
        sharding = {
            enabled = true,
            strategy = "consistent_hashing",
            virtual_nodes = 1000,
            replication_factor = 2,
            auto_rebalance = true
        },
        
        -- 负载均衡配置
        load_balancing = {
            strategy = "round_robin",
            health_check = true,
            failover_timeout = 30
        },
        
        -- 故障容忍配置
        fault_tolerance = {
            enabled = true,
            heartbeat_interval = 10,
            election_timeout = 3000,
            max_retries = 3
        }
    },
    
    -- 存储配置
    storage = {
        engine = "v3_integrated",
        data_dir = "$DATA_DIR_PREFIX/node-\$NODE_ID",
        block_size = 30,
        enable_compression = true,
        compression_type = "lz4"
    },
    
    -- 网络配置
    network = {
        bind_address = "0.0.0.0",
        port = \$PORT,
        max_connections = 10000,
        cluster_port = \$((PORT + 1000))
    },
    
    -- 性能配置
    performance = {
        enable_luajit_optimization = true,
        memory_pool_size = "1GB",
        batch_size = 1000,
        enable_prefetch = true
    },
    
    -- 监控配置
    monitoring = {
        enabled = true,
        prometheus_port = \$((PORT + 2000)),
        metrics_path = "/metrics",
        health_check_interval = 30
    },
    
    -- 日志配置
    logging = {
        level = "info",
        file = "$LOG_DIR_PREFIX/node-\$NODE_ID.log",
        max_size = "100MB",
        backup_count = 5
    }
}
EOF
    
    # 生成节点配置模板
    for ((i=1; i<=NODES; i++)); do
        local node_port=$((START_PORT + i - 1))
        local node_config="config/cluster_node_$i.lua"
        
        cat > "$node_config" << EOF
-- 节点 $i 配置
local config = require("$(basename "$CONFIG_FILE" .lua)")

-- 设置节点特定配置
config.cluster.node_id = "node-$i"
config.storage.data_dir = "$DATA_DIR_PREFIX/node-$i"
config.network.port = $node_port
config.network.cluster_port = $((node_port + 1000))
config.monitoring.prometheus_port = $((node_port + 2000))
config.logging.file = "$LOG_DIR_PREFIX/node-$i.log"

return config
EOF
        
        log_info "生成节点配置: $node_config"
    done
}

# 部署集群节点
deploy_cluster_nodes() {
    log_info "部署集群节点..."
    
    mkdir -p "bin" "scripts"
    
    # 创建集群启动脚本
    cat > bin/start-cluster << 'EOF'
#!/bin/bash
# Stock-TSDB 集群启动脚本

set -e

cd "$(dirname "\$(dirname "\$0")")"

# 设置Lua路径
export LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua;$LUA_PATH"

# 启动集群服务
luajit lua/cluster.lua "$@"
EOF
    
    chmod +x bin/start-cluster
    
    # 创建节点管理脚本
    cat > scripts/manage-nodes << EOF
#!/bin/bash
# 集群节点管理脚本

NODES=$NODES
START_PORT=$START_PORT

case "\$1" in
    start-all)
        for ((i=1; i<=NODES; i++)); do
            local port=\$((START_PORT + i - 1))
            local config="config/cluster_node_\$i.lua"
            
            echo "启动节点 \$i (端口: \$port)"
            LUA_PATH="./lua/?.lua;./?.lua;./lua/?/init.lua:\$LUA_PATH" \
            luajit lua/cluster.lua --config "\$config" &
            echo \$! > "/tmp/stock-tsdb-node-\$i.pid"
        done
        echo "所有节点启动完成"
        ;;
    
    stop-all)
        for ((i=1; i<=NODES; i++)); do
            if [[ -f "/tmp/stock-tsdb-node-\$i.pid" ]]; then
                local pid=\$(cat "/tmp/stock-tsdb-node-\$i.pid")
                kill "\$pid" 2>/dev/null || true
                rm -f "/tmp/stock-tsdb-node-\$i.pid"
                echo "停止节点 \$i"
            fi
        done
        echo "所有节点已停止"
        ;;
    
    status)
        echo "=== 集群节点状态 ==="
        for ((i=1; i<=NODES; i++)); do
            local port=\$((START_PORT + i - 1))
            if curl -s http://localhost:\$((port + 2000))/health > /dev/null; then
                echo "节点 \$i: ✅ 运行中 (端口: \$port)"
            else
                echo "节点 \$i: ❌ 未运行 (端口: \$port)"
            fi
        done
        ;;
    
    restart-all)
        \$0 stop-all
        sleep 2
        \$0 start-all
        ;;
    
    *)
        echo "用法: manage-nodes {start-all|stop-all|restart-all|status}"
        ;;
esac
EOF
    
    chmod +x scripts/manage-nodes
}

# 创建负载均衡配置
create_load_balancer_config() {
    log_info "创建负载均衡配置..."
    
    # 生成HAProxy配置
    cat > config/haproxy.cfg << EOF
# Stock-TSDB 集群负载均衡配置

global
    daemon
    maxconn 10000

defaults
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s
    timeout check 10s

# 监控界面
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /haproxy?stats
    stats refresh 30s
    stats auth admin:admin123

# 主服务
frontend tsdb_frontend
    bind *:$START_PORT
    default_backend tsdb_backend

backend tsdb_backend
    balance roundrobin
    option tcp-check
    
EOF
    
    # 添加节点配置
    for ((i=1; i<=NODES; i++)); do
        local port=$((START_PORT + i - 1))
        echo "    server node-$i 127.0.0.1:$port check" >> config/haproxy.cfg
    done
    
    log_info "HAProxy配置已生成: config/haproxy.cfg"
}

# 创建集群监控脚本
create_monitoring_scripts() {
    log_info "创建集群监控脚本..."
    
    # 集群健康检查脚本
    cat > scripts/cluster-health.sh << 'EOF'
#!/bin/bash
# 集群健康检查脚本

set -e

CONSUL_SERVER="127.0.0.1:8500"

# 检查Consul健康
if curl -s "http://$CONSUL_SERVER/v1/status/leader" > /dev/null; then
    echo "✅ Consul服务正常"
else
    echo "❌ Consul服务异常"
    exit 1
fi

# 检查服务注册
services=$(curl -s "http://$CONSUL_SERVER/v1/catalog/service/stock-tsdb" | jq length 2>/dev/null || echo "0")
if [[ "$services" -gt 0 ]]; then
    echo "✅ 发现 $services 个服务实例"
else
    echo "⚠️  未发现服务实例"
fi

# 检查节点健康
for port in 6379 6380 6381; do
    if curl -s "http://localhost:$((port + 2000))/health" > /dev/null; then
        echo "✅ 节点端口 $port 健康"
    else
        echo "❌ 节点端口 $port 异常"
    fi
done

echo "=== 集群状态检查完成 ==="
EOF
    
    chmod +x scripts/cluster-health.sh
    
    # 集群性能监控脚本
    cat > scripts/cluster-metrics.sh << 'EOF'
#!/bin/bash
# 集群性能监控脚本

echo "=== 集群性能指标 ==="

for port in 6379 6380 6381; do
    metrics_port=$((port + 2000))
    echo "\n节点端口 $port:"
    
    # 获取基础指标
    curl -s "http://localhost:$metrics_port/metrics" 2>/dev/null | \
        grep -E "(tsdb_requests_total|tsdb_latency_seconds|tsdb_memory_bytes)" | \
        head -5 || echo "   指标获取失败"
done

echo ""
echo "💡 提示: 使用Prometheus进行详细监控"
EOF
    
    chmod +x scripts/cluster-metrics.sh
}

# 显示集群部署摘要
show_cluster_summary() {
    log_success "集群可扩展版部署完成!"
    echo ""
    echo "=== 集群信息 ==="
    echo "节点数量: $NODES"
    echo "起始端口: $START_PORT"
    echo "Consul服务: $CONSUL_SERVER"
    echo "数据目录: $DATA_DIR_PREFIX"
    echo ""
    echo "=== 节点端口分配 ==="
    for ((i=1; i<=NODES; i++)); do
        local port=$((START_PORT + i - 1))
        echo "节点 $i: 服务端口=$port, 集群端口=$((port + 1000)), 监控端口=$((port + 2000))"
    done
    echo ""
    echo "=== 启动命令 ==="
    echo "启动所有节点: ./scripts/manage-nodes start-all"
    echo "停止所有节点: ./scripts/manage-nodes stop-all"
    echo "集群状态检查: ./scripts/manage-nodes status"
    echo "健康检查: ./scripts/cluster-health.sh"
    echo ""
    echo "=== 监控地址 ==="
    echo "Consul UI: http://$CONSUL_SERVER/ui"
    echo "负载均衡监控: http://localhost:8404/haproxy?stats"
    echo "节点监控: http://localhost:$((START_PORT + 2000))/metrics"
    echo ""
    echo "=== 扩展操作 ==="
    echo "添加节点: 修改NODES变量后重新运行部署脚本"
    echo "数据迁移: 使用Consul进行服务发现和负载均衡"
    echo "备份恢复: 每个节点独立备份数据目录"
    echo ""
    echo "💡 提示: 集群版支持动态扩展，可根据业务需求调整节点数量"
}

# 主函数
main() {
    # 默认配置
    NODES=3
    CONSUL_SERVER="127.0.0.1:8500"
    START_PORT=6379
    DATA_DIR_PREFIX="./data/cluster"
    LOG_DIR_PREFIX="./logs"
    CONFIG_FILE="config/cluster_scalable.lua"
    SKIP_CONSUL="false"
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nodes)
                NODES="$2"
                shift 2
                ;;
            --consul)
                CONSUL_SERVER="$2"
                shift 2
                ;;
            --start-port)
                START_PORT="$2"
                shift 2
                ;;
            --data-dir)
                DATA_DIR_PREFIX="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --force)
                FORCE="true"
                shift
                ;;
            --skip-consul)
                SKIP_CONSUL="true"
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
    
    log_info "开始部署集群可扩展版"
    
    # 验证参数
    if [[ $NODES -lt 1 ]]; then
        log_warning "节点数量必须大于0，使用默认值3"
        NODES=3
    fi
    
    # 执行部署步骤
    check_cluster_dependencies
    deploy_consul
    generate_cluster_config
    deploy_cluster_nodes
    create_load_balancer_config
    create_monitoring_scripts
    show_cluster_summary
}

# 运行主函数
main "$@"