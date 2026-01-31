#!/bin/bash

# 监控状态检查脚本
# 用于检查Prometheus监控系统的运行状态

echo "🔍 检查监控系统状态..."
echo ""

# 检查元数据Web服务器状态
echo "📊 Stock-TSDB元数据Web服务器状态:"
if curl -s http://localhost:8080/api/auth/check > /dev/null 2>&1; then
    echo "✅ 元数据Web服务器运行正常 (端口: 8080)"
    
    # 检查Prometheus指标端点
    echo "📈 检查Prometheus指标端点..."
    metrics_response=$(curl -s http://localhost:8080/metrics | head -5)
    if [[ $metrics_response == *"HELP"* ]]; then
        echo "✅ Prometheus指标端点正常"
        echo "   指标数量: $(curl -s http://localhost:8080/metrics | grep -c '^[^#]')"
    else
        echo "❌ Prometheus指标端点异常"
    fi
else
    echo "❌ 元数据Web服务器未运行"
fi

echo ""

# 检查Prometheus服务状态
echo "📊 Prometheus服务状态:"
if docker ps | grep -q stock-tsdb-prometheus; then
    echo "✅ Prometheus服务运行正常 (端口: 9090)"
    
    # 检查Prometheus自身状态
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        echo "✅ Prometheus健康检查通过"
        
        # 检查监控目标状态
        echo "🎯 检查监控目标状态..."
        targets_status=$(curl -s http://localhost:9090/api/v1/targets)
        if [[ $targets_status == *"up"* ]]; then
            echo "✅ 监控目标连接正常"
        else
            echo "⚠️  监控目标连接异常"
        fi
    else
        echo "❌ Prometheus健康检查失败"
    fi
else
    echo "❌ Prometheus服务未运行"
    echo "   启动命令: ./scripts/start_prometheus.sh"
fi

echo ""

# 检查Redis集群状态
echo "📊 Redis集群状态:"
redis_processes=$(ps aux | grep redis | grep -v grep | wc -l)
if [ $redis_processes -gt 0 ]; then
    echo "✅ Redis集群运行中 (进程数: $redis_processes)"
else
    echo "❌ Redis集群未运行"
fi

echo ""

# 检查主数据库服务状态
echo "📊 主数据库服务状态:"
if ps aux | grep -q "stock-tsdb"; then
    echo "✅ 主数据库服务运行中"
else
    echo "❌ 主数据库服务未运行"
fi

echo ""
echo "📋 监控系统总结:"
echo "   - 元数据Web服务器: http://localhost:8080"
echo "   - Prometheus监控: http://localhost:9090"
echo "   - 指标端点: http://localhost:8080/metrics"
echo ""
echo "🚀 快速启动监控系统:"
echo "   1. 启动元数据Web服务器: luajit web/start_metadata_web.lua"
echo "   2. 启动Prometheus: ./scripts/start_prometheus.sh"
echo "   3. 访问监控界面: http://localhost:9090"