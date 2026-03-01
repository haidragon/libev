# libev 源码目录结构说明

## 项目根目录结构

```
libev-4.33/
├── README                           # 项目介绍和基本使用说明
├── autogen.sh                       # 自动生成configure脚本
├── ltmain.sh                        # libtool主脚本
├── Makefile.am                      # automake配置文件
├── Makefile.in                      # configure生成的Makefile模板
├── configure.ac                     # autoconf配置脚本
├── config.h.in                      # 配置头文件模板
├── ev.h                             # 核心API声明和基础数据结构
├── ev.c                             # 核心实现和主事件循环逻辑
├── ev_vars.h                        # 全局变量声明宏定义
├── ev_wrap.h                        # 多实例支持包装器
├── ev++.h                           # C++绑定接口
├── event.h                          # libevent兼容API
├── ev_select.c                      # select后端实现
├── ev_poll.c                        # poll后端实现
├── ev_epoll.c                       # epoll后端实现 (Linux)
├── ev_kqueue.c                      # kqueue后端实现 (BSD)
├── ev_port.c                        # event ports后端实现 (Solaris)
├── ev_win32.c                       # Windows平台实现
├── ev_iouring.c                     # Linux io_uring后端实现
├── ev_linuxaio.c                    # Linux AIO后端实现
├── event.c                          # libevent兼容层实现
├── build_debug.sh                   # 标准debug编译脚本
├── build_simple.sh                  # 简化编译脚本
├── build_minimal.sh                 # 最小化编译脚本
├── run_example.sh                   # 测试程序运行脚本
├── example_usage.c                  # libev使用案例演示程序
├── test_simple.c                    # 简单测试程序
├── README_DEBUG.md                  # Debug编译使用指南
├── SUMMARY.md                       # 项目完整总结
├── LIBEV_DESIGN_ANALYSIS.md         # 设计思想与架构分析
├── LIBEV_SOURCE_CODE_ANALYSIS.md    # 源码深度解析
├── LIBEV_SYSTEM_ARCHITECTURE.md     # 系统架构全景图
├── build_simple/                    # 简化编译构建目录
│   ├── config.h                     # 生成的配置文件
│   ├── libev.a                      # 编译生成的静态库
│   └── *.h                          # 复制的头文件
├── build_minimal/                   # 最小化编译构建目录
│   ├── config.h                     # 生成的配置文件
│   ├── libev.a                      # 编译生成的静态库
│   └── *.h                          # 复制的头文件
└── build_debug/                     # 标准debug编译构建目录
    ├── config.log                   # configure日志
    ├── config.status                # configure状态
    ├── Makefile                     # 生成的Makefile
    └── *.o                          # 编译目标文件
```

## 核心源码文件功能分类

### 核心API层
- **ev.h**: 核心API声明、数据结构定义、宏定义
- **ev++.h**: C++绑定接口，提供面向对象的使用方式
- **event.h**: libevent兼容API，便于迁移现有代码

### 核心实现层
- **ev.c**: 事件循环核心逻辑、watcher管理、时间处理
- **ev_vars.h**: 全局变量声明的宏定义系统
- **ev_wrap.h**: 多事件循环实例支持的包装器

### 平台后端层
- **ev_select.c**: select系统调用后端实现
- **ev_poll.c**: poll系统调用后端实现
- **ev_epoll.c**: Linux epoll后端实现（高性能）
- **ev_kqueue.c**: BSD kqueue后端实现（功能丰富）
- **ev_port.c**: Solaris event ports后端实现
- **ev_win32.c**: Windows平台后端实现
- **ev_iouring.c**: Linux io_uring异步IO后端
- **ev_linuxaio.c**: Linux异步IO后端实现

### 兼容层
- **event.c**: libevent API兼容层实现

## 构建相关文件

### 自动化构建
- **autogen.sh**: 生成configure脚本的自动化工具
- **configure.ac**: autoconf配置脚本源文件
- **Makefile.am**: automake配置文件
- **ltmain.sh**: libtool主脚本文件

### 自定义构建脚本
- **build_debug.sh**: 标准debug编译脚本（使用autoconf）
- **build_simple.sh**: 简化编译脚本（直接编译源码）
- **build_minimal.sh**: 最小化编译脚本（推荐使用）
- **run_example.sh**: 测试程序编译运行脚本

## 示例和文档

### 示例程序
- **example_usage.c**: 完整功能演示程序
- **test_simple.c**: 简单功能测试程序

### 技术文档
- **README_DEBUG.md**: Debug编译和使用指南
- **SUMMARY.md**: 项目完整总结和快速入门
- **LIBEV_DESIGN_ANALYSIS.md**: 设计思想和架构模式分析
- **LIBEV_SOURCE_CODE_ANALYSIS.md**: 源码深度解析
- **LIBEV_SYSTEM_ARCHITECTURE.md**: 系统架构全景图

## 编译产物目录

### build_simple/
简化编译生成的构建目录，包含：
- config.h: 自动生成的配置文件
- libev.a: 静态库文件
- 相关头文件副本

### build_minimal/  
最小化编译生成的构建目录，包含：
- config.h: 自动生成的配置文件
- libev.a: 静态库文件
- 相关头文件副本

### build_debug/
标准autoconf编译生成的构建目录，包含：
- configure生成的各种文件
- 编译目标文件(.o)
- 最终库文件

---
**文档版本**: v1.0  
**适用版本**: libev 4.33  
**更新时间**: 2026年3月1日
