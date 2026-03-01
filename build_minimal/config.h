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
