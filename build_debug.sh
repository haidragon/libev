#!/bin/bash

# libev debug编译脚本
# 作者: Lingma
# 功能: 编译带有调试信息的libev库

set -e  # 遇到错误立即退出

echo "=== libev Debug编译脚本 ==="
echo "开始编译带调试信息的libev库..."

# 创建构建目录
BUILD_DIR="build_debug"
echo "创建构建目录: $BUILD_DIR"
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# 清理之前的构建文件
echo "清理之前的构建文件..."
rm -f *.o *.a *.so config.log config.status

# 运行autogen.sh生成configure脚本
echo "运行autogen.sh生成configure脚本..."
cd ..
./autogen.sh

# 返回构建目录
cd $BUILD_DIR

# 配置编译选项 - 启用调试模式
echo "配置编译选项..."
../configure \
    --enable-debug \
    --disable-shared \
    --enable-static \
    CFLAGS="-g -O0 -DDEBUG -Wall -Wextra -Werror" \
    CPPFLAGS="-DDEBUG_OUTPUT"

# 编译
echo "开始编译..."
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# 检查编译结果
if [ -f "libev.a" ] || [ -f ".libs/libev.a" ]; then
    echo "✅ 编译成功!"
    
    # 复制必要的头文件到构建目录
    echo "复制头文件..."
    cp ../*.h . 2>/dev/null || true
    
    # 显示编译产物
    echo "编译产物:"
    ls -la *.a *.h 2>/dev/null || ls -la .libs/*.a 2>/dev/null
    
    # 显示调试信息
    echo "调试信息检查:"
    if command -v objdump >/dev/null 2>&1; then
        echo "检查符号表..."
        objdump -t libev.a 2>/dev/null | head -20
    fi
    
else
    echo "❌ 编译失败!"
    exit 1
fi

echo "=== 编译完成 ==="
echo "构建目录: $(pwd)"
echo "可以运行测试程序验证功能"
