# libev Watcher类型源码总览

## 1. Watcher基础架构

### 1.1 核心设计思想
Watcher是libev中观察和响应事件的基本单元，采用继承式的结构设计，通过宏定义实现代码复用和类型安全。

### 1.2 基础宏定义系统

#### EV_WATCHER宏 - 基础字段
```c
/* ev.h - Watcher基础结构宏 */
#define EV_WATCHER(type)                        \
  int active;     /* active状态: 0=未激活, 1+=优先级+1 */ \
  int pending;    /* pending计数: 0=无pending, 1+=pending队列位置 */ \
  int priority;   /* 优先级: 0=最高, NUMPRI-1=最低 */ \
  void *data;     /* 用户自定义数据指针 */ \
  struct ev_watcher *next; /* 双向链表指针 */ \
  struct ev_watcher *prev;

/* 时间相关扩展宏 */
#define EV_WATCHER_TIME(type)                   \
  EV_WATCHER(type)                              \
  ev_tstamp at;     /* 绝对超时时间 */
```

#### 类型安全的强制转换
```c
/* Watcher类型转换宏 */
#define ev_watcher  EV_WATCHER(ev_watcher)
#define ev_watcher_time  EV_WATCHER_TIME(ev_watcher_time)

/* 实际使用示例 */
ev_io *io_watcher = (ev_io *)malloc(sizeof(ev_io));
ev_watcher *base = (ev_watcher *)io_watcher;  /* 安全向上转换 */
```

## 2. 核心Watcher类型详解

### 2.1 ev_io - IO事件Watcher

#### 数据结构定义
```c
typedef struct
{
  EV_WATCHER(ev_io)
  int fd;           /* 文件描述符 */
  int events;       /* 监听事件类型(POLLIN|POLLOUT|...) */
} ev_io;
```

#### 核心实现源码 (ev.c)
```c
/* IO事件初始化 */
void
ev_io_init (ev_io *w, void (*cb)(EV_P_ ev_io *w, int revents), int fd, int events)
{
  EV_WATCHER_INIT(w, cb);
  w->fd = fd;
  w->events = events;
}

/* IO事件启动 */
void
ev_io_start (EV_P_ ev_io *w)
{
  if (ecb_expect_false (ev_is_active (w)))
    return;

  /* 注册到fd映射表 */
  fd_change (EV_A_ w->fd, w->events);
  
  /* 加入活跃队列 */
  ev_start (EV_A_ (ev_watcher *)w, 1);
  array_add (anfds [w->fd].head, (ev_watcher_list *)w);
}

/* IO事件停止 */
void
ev_io_stop (EV_P_ ev_io *w)
{
  clear_pending (EV_A_ (ev_watcher *)w);
  
  if (ecb_expect_false (!ev_is_active (w)))
    return;

  /* 从fd映射表移除 */
  array_del (anfds [w->fd].head, (ev_watcher_list *)w);
  fd_change (EV_A_ w->fd, 0);
  
  ev_stop (EV_A_ (ev_watcher *)w);
}
```

### 2.2 ev_timer - 定时器Watcher

#### 数据结构定义
```c
typedef struct
{
  EV_WATCHER_TIME(ev_timer)
  ev_tstamp repeat; /* 重复间隔(0表示一次性定时器) */
} ev_timer;
```

#### 核心算法实现
```c
/* 定时器初始化 */
void
ev_timer_init (ev_timer *w, void (*cb)(EV_P_ ev_timer *w, int revents), 
               ev_tstamp after, ev_tstamp repeat)
{
  EV_WATCHER_INIT(w, cb);
  w->repeat = repeat;
  ev_timer_set (w, after, repeat);
}

/* 定时器启动 - 时间堆操作 */
void
ev_timer_start (EV_P_ ev_timer *w)
{
  if (ecb_expect_false (ev_is_active (w)))
    {
      ev_timer_stop (EV_A_ w);
      ev_timer_start (EV_A_ w);
      return;
    }

  /* 计算绝对超时时间 */
  ev_at (w) += ev_rt_now;
  
  /* 插入时间堆 */
  ANHE *heap = timerv [ABSPRI (w)];
  int cnt = timercnt [ABSPRI (w)];
  
  heap [cnt] = *(ANHE *)w;
  upheap (heap, ABSPRI (w), cnt);
  timercnt [ABSPRI (w)] = cnt + 1;
  
  ev_start (EV_A_ (ev_watcher *)w, cnt + 1);
}
```

### 2.3 ev_signal - 信号Watcher

#### 数据结构定义
```c
typedef struct
{
  EV_WATCHER(ev_signal)
  int signum;       /* 信号编号 */
} ev_signal;
```

#### 信号处理机制
```c
/* 信号Watcher初始化 */
void
ev_signal_init (ev_signal *w, void (*cb)(EV_P_ ev_signal *w, int revents), int signum)
{
  EV_WATCHER_INIT(w, cb);
  w->signum = signum;
}

/* 信号处理核心逻辑 */
static void
ev_feed_signal_event (EV_P_ int signum)
{
  /* 遍历所有监听该信号的watcher */
  for (ev_signal *w = signals [signum].head; w; w = (ev_signal *)((ev_watcher *)w)->next)
    {
      if (ecb_expect_false (ev_cb (w) == SIG_IGN || ev_cb (w) == SIG_DFL))
        continue;
        
      /* 设置pending状态 */
      w->pending = 1;
      pendings [ABSPRI (w)][w->pending - 1].w = (ev_watcher *)w;
      pendingpri = NUMPRI; /* force recalculation */
    }
}
```

## 3. 高级Watcher类型

### 3.1 ev_child - 子进程状态Watcher

#### 数据结构实现
```c
typedef struct
{
  EV_WATCHER(ev_child)
  int pid;          /* 进程ID */
  int rpid;         /* 实际退出的进程ID */
  int rstatus;      /* 退出状态 */
} ev_child;
```

#### 进程监控机制
```c
/* 子进程Watcher启动 */
void
ev_child_start (EV_P_ ev_child *w)
{
  if (ecb_expect_false (ev_is_active (w)))
    return;

#if EV_CHILD_ENABLE
  /* 注册到子进程监控表 */
  array_add (childs [w->pid], (ev_watcher_list *)w);
  childcb (EV_A_ 0, 0);  /* 更新backend */
#endif

  ev_start (EV_A_ (ev_watcher *)w, 1);
}
```

### 3.2 ev_stat - 文件状态Watcher

#### 数据结构设计
```c
typedef struct
{
  EV_WATCHER(ev_stat)
  ev_tstamp interval;   /* 检查间隔 */
  ev_tstamp at;         /* 下次检查时间 */
  const char *path;     /* 监控路径 */
  struct stat attr;     /* 当前文件属性 */
  struct stat prev;     /* 上次文件属性 */
} ev_stat;
```

#### 文件监控实现
```c
/* 文件状态检查 */
static void
stat_timer_cb (EV_P_ ev_timer *w_, int revents)
{
  ev_stat *w = (ev_stat *)(((char *)w_) - offsetof (ev_stat, timer));

  struct stat buf;
  if (!stat (w->path, &buf))  /* 文件存在 */
    {
      if (memcmp (&buf, &w->attr, sizeof (buf)))  /* 文件发生变化 */
        {
          w->prev = w->attr;
          w->attr = buf;
          ev_feed_event (EV_A_ (ev_watcher *)w, EV_STAT);
        }
    }
  else  /* 文件不存在 */
    {
      if (w->attr.st_mtime)  /* 之前存在，现在不存在 */
        {
          w->prev = w->attr;
          memset (&w->attr, 0, sizeof (w->attr));
          ev_feed_event (EV_A_ (ev_watcher *)w, EV_STAT);
        }
    }
}
```

## 4. 特殊用途Watcher

### 4.1 ev_idle - 空闲Watcher
```c
typedef struct
{
  EV_WATCHER(ev_idle)
} ev_idle;

/* 空闲时触发，在每次事件循环迭代中都会检查 */
void
ev_idle_start (EV_P_ ev_idle *w)
{
  if (ecb_expect_false (ev_is_active (w)))
    return;
    
  ev_start (EV_A_ (ev_watcher *)w, ++idleall);
  array_add (idles [ABSPRI (w)], (ev_watcher_list *)w);
}
```

### 4.2 ev_prepare/ev_check - 循环钩子
```c
typedef struct { EV_WATCHER(ev_prepare) } ev_prepare;
typedef struct { EV_WATCHER(ev_check) } ev_check;

/* prepare在每次事件循环开始前执行 */
/* check在每次事件循环结束后执行 */
```

### 4.3 ev_fork - fork事件Watcher
```c
typedef struct
{
  EV_WATCHER(ev_fork)
} ev_fork;

/* 在进程fork后自动触发，用于重新初始化backend */
```

## 5. Watcher管理机制

### 5.1 状态转换管理
```c
/* Watcher状态机 */
enum {
    INACTIVE = 0,    /* 未激活状态 */
    ACTIVE = 1,      /* 已激活状态 */
    PENDING = 2      /* 待处理状态 */
};

/* 状态转换函数 */
static void
ev_start (EV_P_ ev_watcher *w, int active)
{
  w->active = active;
  ++activecnt;
}

static void
ev_stop (EV_P_ ev_watcher *w)
{
  w->active = 0;
  --activecnt;
}
```

### 5.2 优先级管理
```c
/* 优先级范围: 0 (最高) 到 NUMPRI-1 (最低) */
#define NUMPRI 5

/* 优先级计算 */
#define ABSPRI(w) ((w)->priority)

/* pending队列按优先级分组 */
VAR(ev_watcher *, pending, [NUMPRI], , 0)
VAR(int, pendingcnt, [NUMPRI], , 0)
```

### 5.3 批量事件处理
```c
/* pending事件批量处理 */
static void
ev_invoke_pending (EV_P)
{
  pendingpri = NUMPRI;
  
  while (pendingpri)  /* 从最高优先级开始 */
    {
      --pendingpri;
      
      while (pendings [pendingpri])
        {
          ANPENDING *p = pendings [pendingpri];
          
          /* 移除pending状态 */
          p->w->pending = 0;
          array_del (pendings [pendingpri], p);
          
          /* 执行回调 */
          ev_invoke (EV_A_ p->w, p->events);
        }
    }
}
```

## 6. 内存管理策略

### 6.1 对象池机制
```c
/* 预分配的watcher类型 */
struct ev_walk
{
  int type;           /* watcher类型标识 */
  int size;           /* 对象大小 */
  void *mem;          /* 内存块指针 */
  struct ev_walk *next;
};

/* 支持的对象池 */
static struct ev_walk mempool[] = {
  { EV_IO, sizeof(ev_io), 0, 0 },
  { EV_TIMER, sizeof(ev_timer), 0, 0 },
  { EV_SIGNAL, sizeof(ev_signal), 0, 0 },
  /* ... 其他类型 */
};
```

### 6.2 动态内存分配
```c
/* watcher内存分配 */
#define ev_malloc(size) malloc(size)
#define ev_free(ptr) free(ptr)

/* 大对象特殊处理 */
#if EV_LARGE_ROOT
  /* 使用更大的根表以支持更多fd */
#endif
```

## 7. 平台适配实现

### 7.1 不同平台的特殊处理
```c
/* Unix平台信号处理 */
#ifdef _WIN32
  /* Windows使用不同的信号机制 */
#else
  static sigset_t full_sigset;
  static struct sigaction sigchld_action;
#endif

/* 文件系统监控 */
#if EV_USE_INOTIFY
  /* Linux inotify支持 */
#elif EV_USE_KQUEUE
  /* BSD kqueue文件监控 */
#else
  /* 轮询方式监控 */
#endif
```

### 7.2 条件编译配置
```c
/* 功能开关 */
#define EV_CHILD_ENABLE 1      /* 子进程监控 */
#define EV_STAT_ENABLE 1       /* 文件状态监控 */
#define EV_IDLE_ENABLE 1       /* 空闲事件 */

/* 平台特定优化 */
#if __linux
  #define EV_USE_EPOLL 1
#elif __FreeBSD__ || __OpenBSD__
  #define EV_USE_KQUEUE 1
#endif
```

## 8. 性能优化技术

### 8.1 缓存友好的设计
```c
/* 连续内存访问优化 */
static inline void
array_add (ev_watcher_list *head, ev_watcher_list *item)
{
  item->next = head->next;
  item->prev = head;
  head->next->prev = item;
  head->next = item;
}

/* 减少缓存未命中 */
static inline void
clear_pending (EV_P_ ev_watcher *w)
{
  if (ecb_expect_false (w->pending))
    {
      array_del (pendings [ABSPRI (w)], (ANPENDING *)w);
      w->pending = 0;
    }
}
```

### 8.2 分支预测优化
```c
/* 热点路径优化 */
if (ecb_expect_true (activecnt > 0))
  {
    /* 常见情况: 有活跃watcher */
    ev_run (EV_A_ 0);
  }
else
  {
    /* 罕见情况: 无活跃watcher */
    ev_break (EV_A_ EVBREAK_ALL);
  }
```

## 9. 调试和验证机制

### 9.1 类型安全检查
```c
/* 编译时类型检查 */
#define EV_WATCHER_INIT(w, cb_)                 \
  (w)->active = 0;                              \
  (w)->pending = 0;                             \
  (w)->priority = 0;                            \
  (w)->data = 0;                                \
  (w)->cb = (void (*)(EV_P_ ev_watcher *, int))cb_;

/* 运行时验证 */
static void
verify_watcher (EV_P_ ev_watcher *w)
{
  assert (("invalid watcher", w->active >= 0));
  assert (("corrupted watcher list", w->next->prev == w));
  assert (("priority out of range", w->priority >= 0 && w->priority < NUMPRI));
}
```

### 9.2 内存泄漏检测
```c
/* 调试模式下的内存跟踪 */
#if EV_DEBUG
static int watcher_count = 0;

static void *
debug_malloc (size_t size)
{
  ++watcher_count;
  return malloc (size);
}

static void
debug_free (void *ptr)
{
  --watcher_count;
  free (ptr);
}
#endif
```

## 10. 扩展和定制

### 10.1 自定义Watcher类型
```c
/* 扩展机制 */
typedef struct
{
  EV_WATCHER(my_custom_watcher)
  /* 自定义字段 */
  int custom_field1;
  void *custom_data;
} my_custom_watcher;

/* 自定义初始化 */
void
my_custom_init (my_custom_watcher *w, void (*cb)(EV_P_ my_custom_watcher *w, int revents))
{
  EV_WATCHER_INIT(w, cb);
  w->custom_field1 = 0;
  w->custom_data = 0;
}
```

### 10.2 插件化架构
```c
/* watcher类型注册系统 */
typedef struct {
    const char *name;
    size_t size;
    void (*init)(EV_P_ ev_watcher *w);
    void (*start)(EV_P_ ev_watcher *w);
    void (*stop)(EV_P_ ev_watcher *w);
} ev_watcher_type;

static ev_watcher_type *registered_types[256];  /* 类型注册表 */
```

---
**文档版本**: v1.0  
**源码版本**: libev 4.33  
**更新时间**: 2026年3月1日
