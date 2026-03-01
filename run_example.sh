#!/bin/bash

# libev 测试程序编译和运行脚本 (使用最小化编译版本)
# 作者: Lingma
# 功能: 编译并运行libev使用案例

set -e

echo "=== libev 测试程序 ==="

# 检查是否已经编译了最小化版本
if [ ! -d "build_minimal" ] || [ ! -f "build_minimal/libev.a" ]; then
    echo "未找到最小化编译产物，正在编译..."
    ./build_minimal.sh
fi

# 编译测试程序
echo "编译测试程序..."
gcc -g -O0 -DDEBUG -Wall -Wextra \
    -Ibuild_minimal \
    example_usage.c \
    build_minimal/libev.a \
    -o example_usage \
    -lm

echo "✅ 测试程序编译成功"

# 显示程序信息
echo "程序大小:"
ls -lh example_usage

# 运行测试程序
echo "🚀 启动测试程序..."
echo "程序功能说明:"
echo "- 定时器: 每2秒触发一次，共5次"
echo "- TCP服务器: 监听8080端口，可接收连接"
echo "- 信号处理: 按Ctrl+C可优雅退出"
echo "- 周期事件: 每60秒显示当前时间"
echo ""
echo "测试方法:"
echo "1. 程序运行后会自动启动各种事件监听"
echo "2. 可以用浏览器访问 http://localhost:8080 测试IO事件"
echo "3. 或者用telnet连接: telnet localhost 8080"
echo "4. 按Ctrl+C退出程序"
echo ""
echo "=========================="
echo ""

# 运行程序
./example_usage

echo ""
echo "=== 测试完成 ==="
