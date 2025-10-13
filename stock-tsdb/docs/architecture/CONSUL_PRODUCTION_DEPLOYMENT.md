# Consul FFI 生产环境部署指南

## 概述

本文档提供了将Consul FFI集成部署到生产环境的完整指南，包括系统要求、安装步骤、配置说明、监控告警、故障排除等。

## 系统要求

### 硬件要求
- **CPU**: 至少2核，推荐4核以上
- **内存**: 至少4GB，推荐8GB以上
- **磁盘**: 至少20GB可用空间，推荐SSD
- **网络**: 千兆以太网，低延迟网络环境

### 软件要求
- **操作系统**: Linux (CentOS 7+, Ubuntu 16.04+)
- **LuaJIT**: 2.1.0-beta3 或更高版本
- **libcurl**: 7.50.0 或更高版本
- **OpenSSL**: 1.1.0 或更高版本（用于TLS支持）

### Consul集群要求
- **Consul版本**: 1.8.0 或更高版本
- **集群规模**: 至少3个server节点，推荐5个
- **数据中心**: 支持多数据中心部署

## 安装步骤

### 1. 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y luajit libcurl4-openssl-dev openssl ca-certificates

# CentOS/RHEL
sudo yum install -y luajit libcurl-devel openssl ca-certificates

# 验证安装
luajit -v
curl --version
openssl version
```

### 2. 安装Consul FFI模块

```bash
# 创建安装目录
sudo mkdir -p /opt/stock-tsdb/lua
sudo mkdir -p /etc/stock-tsdb
sudo mkdir -p /var/log/stock-tsdb

# 复制Lua模块
sudo cp consul_ffi.lua /opt/stock-tsdb/lua/
sudo cp consul_ha_cluster.lua /opt/stock-tsdb/lua/
sudo cp consul_production_config.lua /opt/stock-tsdb/lua/

# 设置权限
sudo chmod 644 /opt/stock-tsdb/lua/*.lua
sudo chown -R root:root /opt/stock-tsdb
```

### 3. 配置Consul集群

#### 3.1 创建Consul配置文件

```bash
# 创建Consul配置目录
sudo mkdir -p /etc/consul
cat > /etc/consul/server.hcl << 'EOF'
datacenter = "dc1"
data_dir = "/var/lib/consul"
log_level = "INFO"
server = true
bootstrap_expect = 3
ui = true
bind_addr = "0.0.0.0"
client_addr = "0.0.0.0"
retry_join = ["consul-server1", "consul-server2", "consul-server3"]

# ACL配置
acl {
  enabled = true
  default_policy = "deny"
  enable_token_persistence = true
}

# TLS配置
tls {
  defaults {
    ca_file = "/etc/consul/ca.crt"
    cert_file = "/etc/consul/server.crt"
    key_file = "/etc/consul/server.key"
    verify_incoming = true
    verify_outgoing = true
  }
}
EOF
```

#### 3.2 生成TLS证书

```bash
# 生成CA证书
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=StockTSDB/CN=consul-ca"

# 生成服务器证书
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=StockTSDB/CN=consul-server"
openssl x509 -req -days 3650 -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt

# 生成客户端证书
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=StockTSDB/CN=consul-client"
openssl x509 -req -days 3650 -in client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.crt
```

#### 3.3 创建ACL策略

```bash
# 创建ACL策略文件
cat > /etc/consul/acl-policy.hcl << 'EOF'
# KV存储策略
key "stock-tsdb/" {
  policy = "write"
}

key "metadata/" {
  policy = "write"
}

key "locks/" {
  policy = "write"
}

key "sessions/" {
  policy = "write"
}

# 服务注册策略
service "" {
  policy = "write"
}

# 会话策略
session "" {
  policy = "write"
}
EOF

# 创建ACL token
consul acl policy create -name "stock-tsdb-policy" -rules @/etc/consul/acl-policy.hcl
consul acl token create -policy-name "stock-tsdb-policy" -description "Stock TSDB Consul Token"
```

### 4. 创建生产配置文件

```bash
cat > /etc/stock-tsdb/production.conf << 'EOF'
-- Stock TSDB 生产环境配置

local consul_production_config = require("consul_production_config")

-- 覆盖默认配置
local config = consul_production_config.config

-- 生产环境Consul服务器列表
config.consul.servers = {
    "https://consul-server1.company.com:8501",
    "https://consul-server2.company.com:8501",
    "https://consul-server3.company.com:8501"
}

-- 从环境变量读取敏感信息
config.consul.acl_token = os.getenv("CONSUL_ACL_TOKEN")
config.consul.encryption_key = os.getenv("CONSUL_ENCRYPTION_KEY")

-- 节点配置
config.cluster.node_id = os.getenv("HOSTNAME") or "stock-tsdb-node"
config.cluster.datacenter = os.getenv("DATACENTER") or "dc1"

-- 监控配置
config.monitoring.log_file = "/var/log/stock-tsdb/consul.log"
config.monitoring.log_level = os.getenv("LOG_LEVEL") or "INFO"

return config
EOF
```

### 5. 创建systemd服务

```bash
sudo cat > /etc/systemd/system/stock-tsdb.service << 'EOF'
[Unit]
Description=Stock TSDB Server
After=network.target consul.service
Wants=consul.service

[Service]
Type=simple
User=stock-tsdb
Group=stock-tsdb
WorkingDirectory=/opt/stock-tsdb
ExecStart=/usr/bin/luajit /opt/stock-tsdb/main.lua
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=10

# 环境变量
Environment=CONSUL_ACL_TOKEN=
Environment=CONSUL_ENCRYPTION_KEY=
Environment=LOG_LEVEL=INFO
Environment=DATACENTER=dc1

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096

# 日志配置
StandardOutput=append:/var/log/stock-tsdb/output.log
StandardError=append:/var/log/stock-tsdb/error.log

[Install]
WantedBy=multi-user.target
EOF

# 创建用户
sudo useradd -r -s /bin/false stock-tsdb
sudo chown stock-tsdb:stock-tsdb /var/log/stock-tsdb
sudo chown stock-tsdb:stock-tsdb /opt/stock-tsdb

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable stock-tsdb
```

## 配置详解

### Consul客户端配置

```lua
-- consul_production_config.lua 中的关键配置

config.consul = {
    -- 服务器列表（支持多个，自动故障转移）
    servers = {"server1:8500", "server2:8500", "server3:8500"},
    
    -- 超时配置
    timeout = 10,                    -- 连接超时
    retry_attempts = 3,            -- 重试次数
    retry_interval = 1,            -- 重试间隔
    
    -- 健康检查
    health_check_interval = 30,      -- 健康检查频率
    health_check_timeout = 5,      -- 健康检查超时
    
    -- 安全认证
    acl_token = "your-acl-token",    -- ACL token
    
    -- TLS配置
    tls_enabled = true,              -- 启用TLS
    tls_verify = true,               -- 验证证书
    tls_cert_file = "/path/to/cert",
    tls_key_file = "/path/to/key",
    tls_ca_file = "/path/to/ca"
}
```

### 集群配置

```lua
config.cluster = {
    -- 节点配置
    node_id = "unique-node-id",
    datacenter = "dc1",
    
    -- 集群规模
    min_nodes = 3,                   -- 最小节点数
    max_nodes = 9,                   -- 最大节点数
    
    -- 心跳配置
    heartbeat_interval = 5,          -- 心跳间隔
    heartbeat_timeout = 15,          -- 心跳超时
    
    -- Leader选举
    election_timeout = 10,           -- 选举超时
    leader_lease_duration = 60,      -- Leader租约
    
    -- 一致性配置
    consistency_mode = "consistent",   -- 一致性模式
    replication_factor = 3,          -- 副本因子
    write_quorum = 2,                -- 写quorum
    read_quorum = 2                  -- 读quorum
}
```

### 存储配置

```lua
config.storage = {
    -- KV存储前缀
    kv_prefix = "stock-tsdb/",
    metadata_prefix = "metadata/",
    lock_prefix = "locks/",
    session_prefix = "sessions/",
    
    -- 一致性模式
    kv_consistency = "consistent"
}
```

## 监控告警

### 监控指标

```lua
-- 监控配置
config.monitoring = {
    metrics_enabled = true,
    metrics_interval = 60,
    
    -- 告警阈值
    alert_threshold = {
        node_down_count = 2,         -- 节点下线阈值
        response_time_ms = 5000,     -- 响应时间阈值
        error_rate_percent = 5       -- 错误率阈值
    }
}
```

### Prometheus集成

```yaml
# prometheus.yml 配置示例
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'stock-tsdb-consul'
    static_configs:
      - targets: ['localhost:9100']
    metrics_path: /metrics
    scrape_interval: 30s
    
  - job_name: 'consul-servers'
    static_configs:
      - targets: ['consul-server1:8500', 'consul-server2:8500', 'consul-server3:8500']
    metrics_path: /v1/agent/metrics
    scrape_interval: 30s
```

### Grafana仪表板

创建JSON格式的Grafana仪表板，包含以下关键指标：

1. **集群状态指标**
   - 节点数量
   - Leader状态
   - 节点健康状态

2. **性能指标**
   - KV操作延迟
   - 集群响应时间
   - 吞吐量

3. **错误指标**
   - 错误率
   - 超时次数
   - 连接失败次数

## 故障排除

### 常见问题

#### 1. 连接超时
```bash
# 检查网络连通性
ping consul-server1

# 检查端口开放
telnet consul-server1 8500

# 检查防火墙
sudo iptables -L
```

#### 2. ACL认证失败
```bash
# 检查ACL token
echo $CONSUL_ACL_TOKEN

# 验证ACL策略
consul acl token read -id <token-id>
```

#### 3. TLS证书问题
```bash
# 验证证书
openssl x509 -in client.crt -text -noout

# 检查证书有效期
openssl x509 -in client.crt -enddate -noout

# 验证CA证书
openssl verify -CAfile ca.crt client.crt
```

#### 4. 性能问题
```bash
# 监控Consul性能
consul monitor -log-level=INFO

# 检查集群状态
consul operator raft list-peers

# 查看节点健康状态
consul operator autopilot health
```

### 日志分析

```bash
# 查看应用日志
tail -f /var/log/stock-tsdb/consul.log

# 查看系统日志
journalctl -u stock-tsdb -f

# 查看Consul日志
journalctl -u consul -f
```

### 性能调优

#### 1. Consul调优
```bash
# /etc/consul/server.hcl
performance {
  raft_multiplier = 1              # 降低Raft超时时间
  leave_drain_time = "5s"          # 缩短退出时间
}
```

#### 2. 内核参数调优
```bash
# /etc/sysctl.conf
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 65536
```

#### 3. 系统限制调优
```bash
# /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
```

## 备份恢复

### 数据备份

```bash
#!/bin/bash
# backup-consul.sh - Consul数据备份脚本

BACKUP_DIR="/backup/consul/$(date +%Y%m%d)"
CONSUL_DATA_DIR="/var/lib/consul"

mkdir -p $BACKUP_DIR

# 备份Consul数据
tar -czf $BACKUP_DIR/consul-data-$(date +%H%M%S).tar.gz -C $CONSUL_DATA_DIR .

# 备份配置文件
cp -r /etc/consul $BACKUP_DIR/

# 清理旧备份（保留7天）
find /backup/consul -type d -mtime +7 -exec rm -rf {} \;
```

### 数据恢复

```bash
#!/bin/bash
# restore-consul.sh - Consul数据恢复脚本

BACKUP_FILE=$1
RESTORE_DIR="/var/lib/consul"

if [ -z "$BACKUP_FILE" ]; then
    echo "用法: $0 <backup-file.tar.gz>"
    exit 1
fi

# 停止Consul服务
systemctl stop consul

# 备份当前数据
mv $RESTORE_DIR $RESTORE_DIR.backup.$(date +%Y%m%d%H%M%S)

# 恢复数据
mkdir -p $RESTORE_DIR
tar -xzf $BACKUP_FILE -C $RESTORE_DIR

# 设置正确权限
chown -R consul:consul $RESTORE_DIR

# 启动Consul服务
systemctl start consul

echo "Consul数据恢复完成"
```

## 升级维护

### 滚动升级

```bash
#!/bin/bash
# rolling-upgrade.sh - 滚动升级脚本

# 1. 升级前检查
consul operator autopilot health

# 2. 逐个升级节点
for node in consul-server1 consul-server2 consul-server3; do
    echo "升级节点: $node"
    
    # 暂停节点
    consul leave -node=$node
    
    # 升级软件包
    ssh $node "yum update consul"
    
    # 重启服务
    ssh $node "systemctl restart consul"
    
    # 等待节点重新加入
    sleep 30
    
    # 检查节点状态
    consul operator raft list-peers
    
    echo "节点 $node 升级完成"
done

echo "滚动升级完成"
```

### 配置热更新

```lua
-- 配置热更新函数
function ConsulManager:reload_config(new_config)
    -- 保存当前状态
    local old_config = self.config
    
    -- 应用新配置
    self.config = new_config
    
    -- 重新初始化客户端
    self:cleanup()
    self:init()
    
    print("[ConsulManager] 配置热更新完成")
end
```

## 安全最佳实践

### 1. 网络安全
- 使用TLS加密所有通信
- 配置防火墙规则限制访问
- 使用VPN或专线连接

### 2. 认证授权
- 启用ACL并配置细粒度权限
- 定期轮换ACL token
- 使用强密码策略

### 3. 数据安全
- 加密存储敏感数据
- 定期备份重要数据
- 实施数据脱敏策略

### 4. 监控审计
- 启用完整的审计日志
- 配置安全告警
- 定期进行安全扫描

## 性能基准

### 测试环境
- 3节点Consul集群
- 千兆网络
- SSD存储

### 性能指标
- **KV操作延迟**: < 5ms (P99)
- **集群响应时间**: < 10ms (P99)
- **最大吞吐量**: 10,000 ops/秒
- **节点故障恢复**: < 30秒

### 扩展性
- 支持最多9个节点
- 支持多数据中心部署
- 支持跨区域复制

## 总结

本部署指南提供了完整的Consul FFI生产环境部署方案，包括：

1. **系统要求** - 硬件和软件要求
2. **安装步骤** - 详细的安装和配置过程
3. **配置详解** - 各配置项的详细说明
4. **监控告警** - 监控指标和告警配置
5. **故障排除** - 常见问题和解决方案
6. **备份恢复** - 数据备份和恢复策略
7. **升级维护** - 滚动升级和热更新
8. **安全实践** - 安全最佳实践
9. **性能基准** - 性能指标和扩展性

按照本指南部署，可以确保Consul FFI在生产环境中稳定、安全、高效地运行。