-- 集群可扩展版配置模板
-- 适用于需要水平扩展和高可用性的生产环境

return {
    -- 部署模式
    deployment = {
        mode = "cluster",
        version = "scalable",
        description = "集群可扩展版"
    },
    
    -- 集群配置
    cluster = {
        enabled = true,
        mode = "distributed",
        
        -- 服务发现配置
        service_discovery = {
            provider = "consul",
            servers = {"127.0.0.1:8500"},
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
    
    -- 存储引擎配置
    storage = {
        engine = "v3_integrated",
        data_dir = "./data/cluster/node-${NODE_ID}",
        
        -- 集群优化配置
        performance = {
            enable_luajit_optimization = true,
            memory_pool_size = "1GB",
            batch_size = 1000,
            enable_prefetch = true,
            compression_type = "lz4",
            block_size = 30
        }
    },
    
    -- 网络配置
    network = {
        bind_address = "0.0.0.0",
        port = 6379,
        max_connections = 10000,
        
        -- 集群通信端口
        cluster_port = 7379,
        
        -- 连接优化
        connection = {
            keepalive = 600,
            timeout = 60,
            backlog = 2048
        }
    },
    
    -- 数据处理配置
    data_processing = {
        -- CSV数据处理
        csv = {
            batch_size = 500,
            validation = {
                enabled = true,
                strict_mode = false  -- 集群版放宽验证
            },
            encoding = "utf8"
        },
        
        -- RowKey编码优化
        rowkey = {
            encoding_type = "binary_compact",
            enable_cache = true,
            cache_size = "128MB"
        }
    },
    
    -- 监控配置
    monitoring = {
        enabled = true,
        prometheus_port = 9090,
        metrics_path = "/metrics",
        
        -- 集群监控
        cluster_metrics = {
            enable_node_metrics = true,
            enable_shard_metrics = true,
            enable_replication_metrics = true
        }
    },
    
    -- 日志配置
    logging = {
        level = "info",
        file = "./logs/cluster-node-${NODE_ID}.log",
        max_size = "100MB",
        backup_count = 5,
        
        -- 集群日志
        cluster_log = {
            enabled = true,
            file = "./logs/cluster.log"
        }
    },
    
    -- 安全配置
    security = {
        -- 访问控制
        access_control = {
            enabled = true,
            users = {
                admin = {
                    password = "admin123",
                    permissions = {"read", "write", "admin"}
                },
                user = {
                    password = "user123",
                    permissions = {"read", "write"}
                }
            }
        },
        
        -- 集群安全
        cluster_security = {
            enable_tls = false,
            certificate_dir = "./certs"
        }
    },
    
    -- 高级集群配置
    advanced = {
        -- 数据同步
        replication = {
            sync_mode = "async",
            sync_interval = 1000,
            max_lag = 5000
        },
        
        -- 故障恢复
        recovery = {
            auto_recovery = true,
            recovery_timeout = 30000
        },
        
        -- 扩展性配置
        scalability = {
            max_nodes = 100,
            auto_scaling = false
        }
    }
}