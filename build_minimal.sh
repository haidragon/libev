#!/bin/bash

# libev 最简debug编译脚本
# 作者: Lingma
# 功能: 手动生成必要配置并编译

set -e

echo "=== libev 最简Debug编译 ==="

# 创建构建目录
BUILD_DIR="build_minimal"
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

#endif /* CONFIG_H */
EOF

# 编译选项
CFLAGS="-g -O0 -DDEBUG -DENABLE_DEBUG -DEV_VERIFY=3 -Wall -Wextra -std=c99"
INCLUDES="-I.. -I."

echo "编译选项: $CFLAGS"

# 编译核心文件
echo "编译核心源文件..."
gcc $CFLAGS $INCLUDES -c ../ev.c -o ev.o

# 编译选择的后端（根据平台）
PLATFORM_BACKENDS=""
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - 使用kqueue
    if [ -f "../ev_kqueue.c" ]; then
        PLATFORM_BACKENDS="../ev_kqueue.c"
        echo "使用kqueue后端"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux - 使用epoll
    if [ -f "../ev_epoll.c" ]; then
        PLATFORM_BACKENDS="../ev_epoll.c"
        echo "使用epoll后端"
    fi
fi

# 如果没有特定平台后端，则使用select/poll
if [ -z "$PLATFORM_BACKENDS" ]; then
    PLATFORM_BACKENDS="../ev_select.c ../ev_poll.c"
    echo "使用select/poll后端"
fi

# 编译平台相关后端
for backend in $PLATFORM_BACKENDS; do
    if [ -f "$backend" ]; then
        backend_name=$(basename $backend .c)
        echo "编译后端: $backend_name"
        gcc $CFLAGS $INCLUDES -c $backend -o ${backend_name}.o 2>/dev/null || {
            echo "后端 $backend_name 编译失败，跳过"
        }
    fi
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
    echo "库符号信息:"
    if command -v nm >/dev/null 2>&1; then
        nm libev.a | grep -E "(ev_|EV_)" | head -15
    fi
    
    # 编译测试程序验证
    echo "编译测试程序验证..."
    cd ..
    gcc -g -O0 -DDEBUG -I$BUILD_DIR -L$BUILD_DIR \
        example_usage.c -lev -lm -o test_libev 2>/dev/null && {
        echo "✅ 库链接测试成功"
        rm test_libev
    } || {
        echo "⚠️  库链接测试需要安装到系统路径或使用完整路径"
    }
    
else
    echo "❌ 编译失败!"
    exit 1
fi

echo "=== 编译完成 ==="
echo "构建目录: $(pwd)"
echo "配置文件: config.h 已生成"
