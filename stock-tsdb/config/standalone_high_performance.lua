-- 单机极致性能版配置模板
-- 适用于追求最高性能的单机部署场景

return {
    -- 部署模式
    deployment = {
        mode = "standalone",
        version = "high_performance",
        description = "单机极致性能版"
    },
    
    -- 存储引擎配置
    storage = {
        engine = "v3_integrated",
        data_dir = "./data/standalone",
        
        -- 性能优化配置
        performance = {
            enable_luajit_optimization = true,
            memory_pool_size = "2GB",
            batch_size = 2000,
            enable_prefetch = true,
            compression_type = "lz4",
            block_size = 64
        },
        
        -- 缓存配置
        cache = {
            enabled = true,
            size = "512MB",
            ttl = 3600
        }
    },
    
    -- 网络配置
    network = {
        bind_address = "0.0.0.0",
        port = 6379,
        max_connections = 5000,
        
        -- 连接优化
        connection = {
            keepalive = 300,
            timeout = 30,
            backlog = 1024
        }
    },
    
    -- 数据处理配置
    data_processing = {
        -- CSV数据处理
        csv = {
            batch_size = 1000,
            validation = {
                enabled = true,
                strict_mode = true
            },
            encoding = "utf8"
        },
        
        -- RowKey编码优化
        rowkey = {
            encoding_type = "binary_compact",
            enable_cache = true,
            cache_size = "256MB"
        }
    },
    
    -- 监控配置
    monitoring = {
        enabled = true,
        prometheus_port = 9090,
        metrics_path = "/metrics",
        
        -- 性能指标
        metrics = {
            enable_latency_metrics = true,
            enable_memory_metrics = true,
            enable_throughput_metrics = true
        }
    },
    
    -- 日志配置
    logging = {
        level = "info",
        file = "./logs/standalone.log",
        max_size = "100MB",
        backup_count = 10,
        
        -- 性能日志
        performance_log = {
            enabled = true,
            file = "./logs/performance.log"
        }
    },
    
    -- 安全配置
    security = {
        -- 访问控制
        access_control = {
            enabled = false,  -- 单机版默认关闭
            users = {
                -- 可配置用户权限
            }
        }
    },
    
    -- 高级优化配置
    advanced = {
        -- JIT编译优化
        jit = {
            enabled = true,
            optimization_level = 2
        },
        
        -- 内存管理
        memory = {
            gc_strategy = "generational",
            gc_threshold = 200
        },
        
        -- I/O优化
        io = {
            buffer_size = "64KB",
            direct_io = false
        }
    }
}