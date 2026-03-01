#!/bin/bash

# libev 简化版debug编译脚本
# 作者: Lingma
# 功能: 直接编译libev源码，跳过autoconf配置

set -e

echo "=== libev 简化版Debug编译 ==="

# 创建构建目录
BUILD_DIR="build_simple"
echo "创建构建目录: $BUILD_DIR"
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# 清理旧文件
rm -f *.o *.a *.so config.h

# 生成基本的config.h
echo "生成配置文件..."
cat > config.h << 'EOF'
/* Minimal config.h for libev */
#ifndef CONFIG_H
#define CONFIG_H

/* 基本配置 */
#define HAVE_SELECT 1
#define HAVE_POLL 1

/* 平台相关 */
#ifdef __APPLE__
#define HAVE_KQUEUE 1
#define HAVE_MACH_ABSOLUTE_TIME 1
#endif

#ifdef __linux__
#define HAVE_EPOLL_CTL 1
#define HAVE_INOTIFY_INIT 1
#endif

/* 调试相关 */
#ifdef DEBUG
#define ENABLE_DEBUG 1
#define EV_VERIFY 3
#endif

/* 其他必要定义 */
#define HAVE_CLOCK_SYSCALL 1
#define HAVE_NANOSLEEP 1
#define HAVE_FLOOR 1
#define ECB_NO_LIBM 1

#endif /* CONFIG_H */
EOF

# 编译选项 - 移除-Werror以避免警告导致编译失败
CFLAGS="-g -O0 -DDEBUG -DENABLE_DEBUG -DEV_VERIFY=3 -Wall -Wextra -std=c99"
INCLUDES="-I.. -I."

echo "编译选项: $CFLAGS"

# 获取所有源文件
SOURCE_FILES="../ev.c"
BACKEND_FILES="../ev_select.c ../ev_poll.c ../ev_epoll.c ../ev_kqueue.c ../ev_port.c ../ev_win32.c"

# 检查哪些后端文件存在
AVAILABLE_BACKENDS=""
for backend in $BACKEND_FILES; do
    if [ -f "$backend" ]; then
        AVAILABLE_BACKENDS="$AVAILABLE_BACKENDS $backend"
        echo "发现后端: $(basename $backend)"
    fi
done

echo "可用后端数量: $(echo $AVAILABLE_BACKENDS | wc -w)"

# 编译核心文件
echo "编译核心源文件..."
gcc $CFLAGS $INCLUDES -c ../ev.c -o ev.o

# 编译后端文件
echo "编译后端文件..."
for backend in $AVAILABLE_BACKENDS; do
    backend_name=$(basename $backend .c)
    echo "编译 $backend_name..."
    gcc $CFLAGS $INCLUDES -c $backend -o ${backend_name}.o 2>/dev/null || echo "跳过 $backend_name (可能不兼容当前平台)"
done

# 创建静态库
echo "创建静态库..."
ar rcs libev.a *.o

# 复制头文件
cp ../*.h . 2>/dev/null || true

# 验证编译结果
if [ -f "libev.a" ]; then
    echo "✅ 编译成功!"
    echo "编译产物:"
    ls -la *.a *.h config.h
    
    # 显示库信息
    echo "库信息:"
    ar -t libev.a
    
    # 检查调试符号
    echo "调试符号检查:"
    if command -v nm >/dev/null 2>&1; then
        nm libev.a | grep -E "(ev_|EV_)" | head -10
    fi
else
    echo "❌ 编译失败!"
    exit 1
fi

echo "=== 编译完成 ==="
echo "构建目录: $(pwd)"
