#!/bin/bash

# Prometheus监控启动脚本
# 用于启动Prometheus服务来监控Stock-TSDB系统

echo "启动Prometheus监控服务..."

# 检查是否安装了Docker
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装，请先安装Docker"
    exit 1
fi

# 检查Prometheus配置文件是否存在
if [ ! -f "conf/prometheus.yml" ]; then
    echo "错误: Prometheus配置文件不存在: conf/prometheus.yml"
    echo "请先创建Prometheus配置文件"
    exit 1
fi

# 停止已运行的Prometheus容器
echo "停止已运行的Prometheus容器..."
docker stop stock-tsdb-prometheus 2>/dev/null || true
docker rm stock-tsdb-prometheus 2>/dev/null || true

# 启动Prometheus容器
echo "启动Prometheus容器..."
docker run -d \
    --name stock-tsdb-prometheus \
    -p 9090:9090 \
    -v $(pwd)/conf/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus:latest

# 检查容器是否成功启动
sleep 3
if docker ps | grep -q stock-tsdb-prometheus; then
    echo "✅ Prometheus监控服务启动成功"
    echo "📊 Prometheus UI: http://localhost:9090"
    echo "📈 监控指标端点: http://localhost:8080/metrics"
    echo ""
    echo "可用监控目标:"
    echo "- Stock-TSDB应用指标: http://localhost:8080/metrics"
    echo "- Prometheus自身监控: http://localhost:9090/metrics"
else
    echo "❌ Prometheus监控服务启动失败"
    docker logs stock-tsdb-prometheus
fi