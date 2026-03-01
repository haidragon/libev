# libev 调试编译和使用指南

## 项目概述

本项目包含了libev库的debug编译脚本和使用案例，帮助开发者更好地理解和使用libev高性能事件库。

## 文件说明

### 编译相关文件
- `build_debug.sh` - Debug模式编译脚本
- `run_example.sh` - 测试程序运行脚本

### 示例代码
- `example_usage.c` - libev使用案例演示程序

### 原始文件
- `ev.h`, `ev.c` - libev核心头文件和源码
- `ev_*.c` - 各平台事件后端实现
- `README` - 官方说明文档

## 编译步骤

### 1. Debug编译
```bash
./build_debug.sh
```

该脚本会：
- 创建`build_debug`目录
- 运行`autogen.sh`生成配置文件
- 使用以下调试选项配置编译：
  - `-g`: 包含调试信息
  - `-O0`: 关闭优化便于调试
  - `-DDEBUG`: 启用调试宏
  - `-Wall -Wextra`: 启用所有警告

### 2. 运行测试
```bash
./run_example.sh
```

该脚本会：
- 自动检测并编译debug版本（如果不存在）
- 编译测试程序
- 启动演示程序

## 使用案例功能说明

测试程序 `example_usage.c` 演示了以下libev功能：

### 1. 定时器事件
- 每2秒触发一次回调函数
- 共触发5次后自动停止
- 显示触发计数和当前时间

### 2. IO事件处理
- 创建TCP服务器监听8080端口
- 处理客户端连接和数据读写
- 支持回显功能

### 3. 信号处理
- 监听SIGINT和SIGTERM信号
- 支持优雅退出程序

### 4. 周期性事件
- 每60秒触发一次
- 显示系统当前时间

## 测试方法

### 方法一：Web浏览器测试
```bash
# 程序运行后，在浏览器中访问
http://localhost:8080
```

### 方法二：Telnet测试
```bash
# 在另一个终端中执行
telnet localhost 8080
# 然后输入任意文本测试回显功能
```

### 方法三：Netcat测试
```bash
echo "Hello libev!" | nc localhost 8080
```

## 调试技巧

### 1. 查看调试输出
程序会在控制台显示详细的事件触发信息：
```
[定时器] 第1次触发 (时间: 1.000000秒)
[IO事件] 文件描述符 3 触发事件
[信号] 收到信号 2
```

### 2. 使用GDB调试
```bash
gdb ./example_usage
(gdb) run
# 程序运行时按Ctrl+C中断
(gdb) bt  # 查看调用栈
```

### 3. 内存检查
```bash
valgrind --leak-check=full ./example_usage
```

## API使用要点

### 核心概念
1. **Event Loop**: 事件循环是libev的核心
2. **Watcher**: 各种事件监视器（定时器、IO、信号等）
3. **Callback**: 事件触发时的回调函数

### 基本使用流程
1. 创建事件循环 `EV_DEFAULT`
2. 初始化watcher `ev_TYPE_init()`
3. 注册回调函数
4. 启动watcher `ev_TYPE_start()`
5. 运行事件循环 `ev_run()`
6. 清理资源

### 常用API
```c
// 事件循环管理
struct ev_loop *loop = EV_DEFAULT;
ev_run(loop, 0);

// 定时器
ev_timer timer_watcher;
ev_timer_init(&timer_watcher, callback, delay, repeat);
ev_timer_start(loop, &timer_watcher);

// IO事件
ev_io io_watcher;
ev_io_init(&io_watcher, callback, fd, events);
ev_io_start(loop, &io_watcher);

// 信号处理
ev_signal signal_watcher;
ev_signal_init(&signal_watcher, callback, signum);
ev_signal_start(loop, &signal_watcher);
```

## 性能特点

libev相比其他事件库的优势：
- 更高的性能和更低的内存占用
- 支持多种事件后端（epoll/kqueue等）
- 完整的fork支持
- 线程安全的设计
- 丰富的事件类型支持

## 注意事项

1. **资源清理**: 程序退出前要停止所有watcher并销毁事件循环
2. **错误处理**: 检查系统调用返回值，正确处理错误情况
3. **非阻塞IO**: 网络编程时要设置socket为非阻塞模式
4. **信号安全**: 信号处理函数中避免复杂操作

## 参考资料

- 官方文档: http://pod.tst.eu/http://cvs.schmorp.de/libev/ev.pod
- 项目主页: http://software.schmorp.de/pkg/libev
- GitHub: https://github.com/enki/libev
