#!/bin/bash

# 测试运行脚本
# 用于Makefile调用运行所有测试

echo "=== 运行股票时序数据库测试 ==="
echo ""

# 切换到脚本所在目录
cd "$(dirname "$0")"

# 检查LuaJIT是否可用
if ! command -v luajit &> /dev/null; then
    echo "错误: 未找到LuaJIT，请先安装"
    exit 1
fi

# 运行综合测试运行器
echo "运行所有测试..."
luajit run_all_tests.lua

# 保存退出码
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✓ 所有测试通过"
else
    echo ""
    echo "✗ 部分测试失败"
fi

exit $EXIT_CODE