# libev 事件循环生命周期深度分析

## 1. 事件循环整体架构

### 1.1 生命周期设计理念
libev采用状态机驱动的事件循环生命周期管理，通过明确的初始化、运行、暂停、恢复和销毁阶段，确保资源的正确管理和系统的稳定运行。整个生命周期围绕ev_loop结构体展开。

### 1.2 核心生命周期状态
```c
/* ev_vars.h - 事件循环状态定义 */
enum {
    LOOP_UNINITIALIZED = 0,  /* 未初始化状态 */
    LOOP_INITIALIZED   = 1,  /* 已初始化状态 */
    LOOP_RUNNING       = 2,  /* 运行状态 */
    LOOP_PAUSED        = 3,  /* 暂停状态 */
    LOOP_STOPPING      = 4,  /* 停止中状态 */
    LOOP_DESTROYED     = 5   /* 已销毁状态 */
};

/* 生命周期相关变量 */
VAR(int, loop_state, , , LOOP_UNINITIALIZED)
VAR(int, loop_depth, , , 0)        /* 嵌套调用深度 */
VAR(int, loop_count, , , 0)        /* 循环迭代次数 */
VAR(int, loop_done, , , 0)         /* 循环结束标志 */
VAR(ev_tstamp, loop_start_time, , , 0.)  /* 循环启动时间 */
```

## 2. 初始化阶段分析

### 2.1 事件循环创建流程
```c
/* ev.c - 事件循环创建主流程 */
struct ev_loop *
ev_loop_new (unsigned int flags)
{
  /* 1. 分配loop结构体内存 */
  struct ev_loop *loop = (struct ev_loop *)ev_malloc (sizeof (struct ev_loop));
  if (!loop)
    return 0;
    
  /* 2. 初始化loop状态 */
  loop->loop_state = LOOP_UNINITIALIZED;
  loop->loop_depth = 0;
  loop->loop_count = 0;
  loop->loop_done = 0;
  
  /* 3. 执行平台特定初始化 */
  if (!backend_init (EV_A_ flags))
    {
      ev_free (loop);
      return 0;
    }
    
  /* 4. 初始化核心组件 */
  loop_init (EV_A_ flags);
  
  /* 5. 设置初始状态 */
  loop->loop_state = LOOP_INITIALIZED;
  loop->loop_start_time = ev_time ();
  
  return loop;
}

/* 平台初始化 */
static int
backend_init (EV_P_ unsigned int flags)
{
  /* 按优先级选择backend */
  static const struct {
    int flag;
    void (*init_func)(EV_P_ int);
  } backends[] = {
#ifdef EV_USE_EPOLL
    { EVFLAG_AUTO, epoll_init },
#endif
#ifdef EV_USE_KQUEUE
    { EVFLAG_AUTO, kqueue_init },
#endif
    { 0, select_init }  /* fallback */
  };
  
  /* 尝试初始化各个backend */
  for (int i = 0; i < sizeof(backends)/sizeof(backends[0]); ++i)
    {
      if (flags & backends[i].flag)
        {
          backends[i].init_func (EV_A_ flags);
          if (backend_fd >= 0)
            return 1;  /* 初始化成功 */
        }
    }
    
  return 0;  /* 所有backend初始化失败 */
}
```

### 2.2 核心组件初始化
```c
/* ev.c - 核心组件初始化 */
static void
loop_init (EV_P_ unsigned int flags)
{
  /* 1. 初始化时间管理 */
  time_init (EV_A);
  
  /* 2. 初始化fd管理 */
  fd_init (EV_A);
  
  /* 3. 初始化定时器管理 */
  timers_init (EV_A);
  
  /* 4. 初始化信号管理 */
  signals_init (EV_A);
  
  /* 5. 初始化异步通知 */
  asyncs_init (EV_A);
  
  /* 6. 初始化prepare/check/idle watcher */
  prepares_init (EV_A);
  checks_init (EV_A);
  idles_init (EV_A);
  
  /* 7. 初始化pending队列 */
  pending_init (EV_A);
  
  /* 8. 设置默认配置 */
  loop_configure_defaults (EV_A_ flags);
}

/* 时间管理初始化 */
static void
time_init (EV_P)
{
#if EV_USE_MONOTONIC
  /* 尝试使用单调时钟 */
  struct timespec ts;
  if (!clock_gettime (CLOCK_MONOTONIC, &ts))
    {
      have_monotonic = 1;
      mn_now = ts.tv_sec + ts.tv_nsec * 1e-9;
    }
#endif

  /* 初始化实时时间 */
  ev_rt_now = ev_time ();
  now_floor = ev_rt_now;
}

/* fd管理初始化 */
static void
fd_init (EV_P)
{
  /* 初始化anfds数组 */
  anfdmax = 64;
  anfds = (ev_watcher_list *)ev_malloc (sizeof (ev_watcher_list) * anfdmax);
  
  /* 初始化fd变更队列 */
  fdchangemax = 64;
  fdchanges = (int *)ev_malloc (sizeof (int) * fdchangemax);
  fdchangecnt = 0;
}
```

## 3. 运行阶段分析

### 3.1 事件循环主流程
```c
/* ev.c - 事件循环主函数 */
int
ev_run (EV_P_ int flags)
{
  /* 1. 状态检查和准备 */
  if (ecb_expect_false (loop_state != LOOP_INITIALIZED && 
                        loop_state != LOOP_PAUSED))
    return 0;
    
  /* 2. 设置运行状态 */
  loop_state = LOOP_RUNNING;
  loop_done = 0;
  ++loop_depth;
  
  /* 3. 主循环 */
  while (ecb_expect_true (activecnt && !loop_done))
    {
      /* 执行prepare watcher */
      prepares_invoke (EV_A);
      
      /* 计算阻塞时间 */
      ev_tstamp timeout = block_expiry (EV_A);
      
      /* 执行backend轮询 */
      backend_poll (EV_A_ timeout);
      
      /* 处理定时器 */
      timers_reify (EV_A);
      
      /* 处理信号 */
      signals_process (EV_A);
      
      /* 处理异步事件 */
      asyncs_process (EV_A);
      
      /* 执行check watcher */
      checks_invoke (EV_A);
      
      /* 处理pending事件 */
      ev_invoke_pending (EV_A);
      
      /* 更新循环计数 */
      ++loop_count;
      
      /* 检查运行标志 */
      if (flags & EVRUN_ONCE)
        break;
        
      EV_FREQUENT_CHECK;
    }
    
  /* 4. 清理和状态恢复 */
  --loop_depth;
  
  if (loop_depth == 0)
    loop_state = LOOP_INITIALIZED;
    
  return activecnt;
}

/* 阻塞时间计算 */
static ev_tstamp
block_expiry (EV_P)
{
  ev_tstamp timeout = MAX_BLOCKING_INTERVAL;
  
  /* 检查最近的定时器 */
  if (timercnt[LOW] && ANHE_at (timerv[LOW][HEAP0]) < ev_rt_now + timeout)
    {
      timeout = ANHE_at (timerv[LOW][HEAP0]) - ev_rt_now;
      if (timeout < MIN_BLOCKING_INTERVAL)
        timeout = MIN_BLOCKING_INTERVAL;
    }
    
  /* 检查其他优先级定时器 */
  for (int pri = MEDIUM; pri < NUMPRI; ++pri)
    {
      if (timercnt[pri] && ANHE_at (timerv[pri][HEAP0]) < ev_rt_now + timeout)
        timeout = ANHE_at (timerv[pri][HEAP0]) - ev_rt_now;
    }
    
  return timeout;
}
```

### 3.2 嵌套事件循环处理
```c
/* ev.c - 嵌套循环支持 */
int
ev_run_nested (EV_P_ int flags)
{
  int old_depth = loop_depth;
  int old_state = loop_state;
  
  /* 保存当前状态 */
  ++loop_depth;
  loop_state = LOOP_RUNNING;
  
  /* 执行嵌套循环 */
  int result = ev_run (EV_A_ flags);
  
  /* 恢复状态 */
  --loop_depth;
  if (loop_depth == old_depth - 1)
    loop_state = old_state;
    
  return result;
}

/* 嵌套循环检测 */
static void
detect_nested_loops (EV_P)
{
  if (ecb_expect_false (loop_depth > MAX_NESTED_LOOPS))
    {
      fprintf (stderr, "Too many nested event loops (%d)\n", loop_depth);
      ev_break (EV_A_ EVBREAK_ALL);
    }
}
```

## 4. 暂停与恢复机制

### 4.1 循环暂停实现
```c
/* ev.c - 事件循环暂停 */
void
ev_pause (EV_P)
{
  if (ecb_expect_false (loop_state != LOOP_RUNNING))
    return;
    
  /* 设置暂停状态 */
  loop_state = LOOP_PAUSED;
  
  /* 保存当前状态 */
  paused_loop_count = loop_count;
  paused_time = ev_time ();
  
  /* 停止backend轮询 */
  if (backend_modify)
    backend_modify (EV_A_ -1, 0, 0);
}

/* 暂停状态检查 */
static int
is_loop_paused (EV_P)
{
  return loop_state == LOOP_PAUSED;
}

/* 暂停期间的后台处理 */
static void
background_processing_while_paused (EV_P)
{
  /* 在暂停期间执行轻量级维护任务 */
  if (timercnt[LOW] > 0)
    {
      /* 处理即将到期的定时器 */
      process_nearby_timers (EV_A);
    }
    
  /* 处理异步通知 */
  if (async_pending)
    {
      asyncs_process (EV_A);
    }
}
```

### 4.2 循环恢复机制
```c
/* ev.c - 事件循环恢复 */
void
ev_resume (EV_P)
{
  if (ecb_expect_false (loop_state != LOOP_PAUSED))
    return;
    
  /* 恢复运行状态 */
  loop_state = LOOP_RUNNING;
  
  /* 更新时间以补偿暂停期间的时间流逝 */
  ev_tstamp pause_duration = ev_time () - paused_time;
  ev_rt_now += pause_duration;
  now_floor += pause_duration;
  
  /* 重新初始化backend */
  if (backend_modify)
    {
      backend_destroy (EV_A);
      backend_init (EV_A_ 0);
    }
    
  /* 处理暂停期间积累的事件 */
  process_accumulated_events (EV_A);
}

/* 时间补偿处理 */
static void
compensate_for_pause_time (EV_P)
{
  ev_tstamp current_time = ev_time ();
  ev_tstamp actual_elapsed = current_time - paused_time;
  ev_tstamp expected_elapsed = current_time - ev_rt_now;
  
  /* 如果时间差异较大，需要调整 */
  if (fabs (actual_elapsed - expected_elapsed) > 1.0)
    {
      ev_rt_now = current_time;
      now_floor = current_time;
      timers_reschedule (EV_A);
    }
}
```

## 5. 停止与销毁机制

### 5.1 循环停止流程
```c
/* ev.c - 事件循环停止 */
void
ev_break (EV_P_ int how)
{
  switch (how)
    {
    case EVBREAK_CANCEL:
      /* 取消停止请求 */
      loop_done = 0;
      break;
      
    case EVBREAK_ONE:
      /* 停止当前迭代 */
      loop_done = 1;
      break;
      
    case EVBREAK_ALL:
      /* 完全停止循环 */
      loop_done = 2;
      /* 停止所有活跃watcher */
      stop_all_watchers (EV_A);
      break;
    }
}

/* 停止所有watcher */
static void
stop_all_watchers (EV_P)
{
  /* 按类型停止所有watcher */
  for (int i = 0; i < activecnt; ++i)
    {
      ev_watcher *w = active[i];
      if (ev_is_active (w))
        {
          switch (ev_type (w))
            {
            case EV_IO:     ev_io_stop (EV_A_ (ev_io *)w); break;
            case EV_TIMER:  ev_timer_stop (EV_A_ (ev_timer *)w); break;
            case EV_SIGNAL: ev_signal_stop (EV_A_ (ev_signal *)w); break;
            /* ... 其他类型 ... */
            }
        }
    }
}
```

### 5.2 资源清理与销毁
```c
/* ev.c - 事件循环销毁 */
void
ev_loop_destroy (EV_P)
{
  if (ecb_expect_false (!loop || loop_state == LOOP_DESTROYED))
    return;
    
  /* 1. 设置销毁状态 */
  loop_state = LOOP_DESTROYED;
  
  /* 2. 停止所有活动 */
  if (loop_state == LOOP_RUNNING)
    ev_break (EV_A_ EVBREAK_ALL);
    
  /* 3. 清理所有watcher */
  cleanup_all_watchers (EV_A);
  
  /* 4. 销毁backend */
  if (backend_destroy)
    backend_destroy (EV_A);
    
  /* 5. 释放核心资源 */
  release_core_resources (EV_A);
  
  /* 6. 释放loop结构体 */
  ev_free (loop);
  loop = 0;
}

/* 清理所有watcher */
static void
cleanup_all_watchers (EV_P)
{
  /* 按相反顺序清理，确保依赖关系正确 */
  static const int cleanup_order[] = {
    EV_CHILD, EV_STAT, EV_FORK, EV_ASYNC,
    EV_SIGNAL, EV_TIMER, EV_IO
  };
  
  for (int i = 0; i < sizeof(cleanup_order)/sizeof(cleanup_order[0]); ++i)
    {
      cleanup_watcher_type (EV_A_ cleanup_order[i]);
    }
}

/* 释放核心资源 */
static void
release_core_resources (EV_P)
{
  /* 释放fd相关资源 */
  if (anfds)
    {
      ev_free (anfds);
      anfds = 0;
    }
    
  /* 释放pending队列 */
  for (int pri = 0; pri < NUMPRI; ++pri)
    {
      if (pendings[pri])
        {
          ev_free (pendings[pri]);
          pendings[pri] = 0;
        }
    }
    
  /* 释放定时器堆 */
  for (int pri = 0; pri < TIMERS; ++pri)
    {
      if (timerv[pri])
        {
          ev_free (timerv[pri]);
          timerv[pri] = 0;
        }
    }
    
  /* 释放其他动态分配的资源 */
  release_dynamic_resources (EV_A);
}
```

## 6. 生命周期状态监控

### 6.1 状态转换监控
```c
#if EV_DEBUG
/* ev.c - 生命周期状态监控 */
VAR(unsigned long, state_transitions, [6][6], , 0)  /* 状态转换计数 */
VAR(ev_tstamp, state_durations, [6], , 0.)          /* 状态持续时间 */

/* 状态转换记录 */
static void
record_state_transition (EV_P_ int from_state, int to_state)
{
  state_transitions[from_state][to_state]++;
  
  /* 记录状态持续时间 */
  if (from_state < 6)
    state_durations[from_state] += ev_time () - state_enter_time[from_state];
    
  /* 记录进入新状态的时间 */
  state_enter_time[to_state] = ev_time ();
}

/* 状态监控包装 */
#define TRANSITION_STATE(from, to) \
  do { \
    if (loop_state == (from)) { \
      record_state_transition (EV_A_ (from), (to)); \
      loop_state = (to); \
    } \
  } while (0)
#endif

/* 生命周期状态报告 */
void
ev_dump_loop_lifecycle (EV_P)
{
#if EV_DEBUG
  fprintf (stderr, "Event Loop Lifecycle Status:\n");
  fprintf (stderr, "  Current State: %s\n", state_names[loop_state]);
  fprintf (stderr, "  Loop Depth: %d\n", loop_depth);
  fprintf (stderr, "  Iteration Count: %lu\n", loop_count);
  fprintf (stderr, "  Uptime: %.3fs\n", ev_time () - loop_start_time);
  
  /* 状态转换统计 */
  fprintf (stderr, "\nState Transitions:\n");
  for (int from = 0; from < 6; ++from)
    {
      for (int to = 0; to < 6; ++to)
        {
          if (state_transitions[from][to] > 0)
            {
              fprintf (stderr, "  %s -> %s: %lu times\n",
                       state_names[from], state_names[to],
                       state_transitions[from][to]);
            }
        }
    }
    
  /* 状态持续时间 */
  fprintf (stderr, "\nState Durations:\n");
  for (int state = 0; state < 6; ++state)
    {
      fprintf (stderr, "  %s: %.3fs\n", 
               state_names[state], state_durations[state]);
    }
#endif
}
```

### 6.2 生命周期健康检查
```c
/* ev.c - 生命周期健康检查 */
static void
check_lifecycle_health (EV_P)
{
  /* 检查状态一致性 */
  if (loop_state == LOOP_RUNNING && loop_depth == 0)
    {
      fprintf (stderr, "Error: Running state with zero depth\n");
    }
    
  if (loop_state == LOOP_UNINITIALIZED && activecnt > 0)
    {
      fprintf (stderr, "Error: Uninitialized loop with active watchers\n");
    }
    
  /* 检查资源泄漏 */
  if (loop_count > 1000000)
    {
      fprintf (stderr, "Warning: High iteration count (%lu)\n", loop_count);
    }
    
  /* 检查时间一致性 */
  ev_tstamp current_time = ev_time ();
  if (current_time < ev_rt_now || current_time - ev_rt_now > 3600)
    {
      fprintf (stderr, "Warning: Time inconsistency detected\n");
      time_resynchronize (EV_A);
    }
}

/* 时间重新同步 */
static void
time_resynchronize (EV_P)
{
  ev_rt_now = ev_time ();
  now_floor = ev_rt_now;
  
  /* 重新安排定时器 */
  timers_reschedule (EV_A);
}
```

## 7. 异常处理与恢复

### 7.1 异常状态恢复
```c
/* ev.c - 异常处理机制 */
static jmp_buf loop_exception_jmp;
static int loop_exception_occurred = 0;

/* 异常保护的循环执行 */
int
ev_run_protected (EV_P_ int flags)
{
  if (setjmp (loop_exception_jmp) == 0)
    {
      return ev_run (EV_A_ flags);
    }
  else
    {
      /* 发生异常，执行恢复 */
      return handle_loop_exception (EV_A_ flags);
    }
}

/* 异常处理 */
static int
handle_loop_exception (EV_P_ int flags)
{
  fprintf (stderr, "Event loop exception occurred\n");
  
  /* 清理异常状态 */
  loop_exception_occurred = 0;
  
  /* 尝试恢复 */
  if (attempt_loop_recovery (EV_A))
    {
      /* 恢复成功，继续执行 */
      return ev_run (EV_A_ flags);
    }
  else
    {
      /* 无法恢复，安全退出 */
      ev_break (EV_A_ EVBREAK_ALL);
      return 0;
    }
}

/* 循环恢复尝试 */
static int
attempt_loop_recovery (EV_P)
{
  /* 重置关键状态 */
  loop_done = 0;
  invoke_depth = 0;
  
  /* 重新初始化时间 */
  time_init (EV_A);
  
  /* 清理损坏的pending队列 */
  reset_pending_queues (EV_A);
  
  /* 重新初始化backend */
  if (backend_destroy)
    backend_destroy (EV_A);
  if (!backend_init (EV_A_ 0))
    return 0;
    
  return 1;
}
```

### 7.2 资源泄漏防护
```c
/* ev.c - 资源泄漏检测 */
#if EV_DEBUG
static unsigned long allocation_counter = 0;
static unsigned long deallocation_counter = 0;

/* 内存分配监控 */
void *
ev_malloc_tracked (size_t size)
{
  void *ptr = malloc (size);
  if (ptr)
    allocation_counter++;
  return ptr;
}

void
ev_free_tracked (void *ptr)
{
  if (ptr)
    {
      deallocation_counter++;
      free (ptr);
    }
}

/* 泄漏检查 */
static void
check_for_memory_leaks (EV_P)
{
  if (allocation_counter != deallocation_counter)
    {
      fprintf (stderr, "Memory leak detected: allocated=%lu, freed=%lu\n",
               allocation_counter, deallocation_counter);
    }
}
#endif
```

## 8. 性能优化与调优

### 8.1 生命周期性能监控
```c
#if EV_STATS
/* ev.c - 性能统计 */
VAR(unsigned long, loop_iterations, , , 0)        /* 循环迭代次数 */
VAR(ev_tstamp, total_loop_time, , , 0.)           /* 总运行时间 */
VAR(ev_tstamp, max_iteration_time, , , 0.)        /* 最大单次迭代时间 */
VAR(unsigned long, state_transition_count, , , 0) /* 状态转换次数 */

/* 性能监控包装 */
int
ev_run_monitored (EV_P_ int flags)
{
  ev_tstamp start_time = ev_time ();
  
  int result = ev_run (EV_A_ flags);
  
  ev_tstamp iteration_time = ev_time () - start_time;
  total_loop_time += iteration_time;
  loop_iterations++;
  
  if (iteration_time > max_iteration_time)
    max_iteration_time = iteration_time;
    
  return result;
}
#endif

/* 性能报告 */
void
ev_dump_performance_stats (EV_P)
{
#if EV_STATS
  fprintf (stderr, "Performance Statistics:\n");
  fprintf (stderr, "  Total Iterations: %lu\n", loop_iterations);
  fprintf (stderr, "  Average Iteration Time: %.6fs\n", 
           loop_iterations > 0 ? total_loop_time / loop_iterations : 0);
  fprintf (stderr, "  Maximum Iteration Time: %.6fs\n", max_iteration_time);
  fprintf (stderr, "  Total Loop Time: %.3fs\n", total_loop_time);
  fprintf (stderr, "  State Transitions: %lu\n", state_transition_count);
#endif
}
```

### 8.2 生命周期调优建议
```c
/* ev.c - 生命周期调优接口 */
void
ev_tune_lifecycle_parameters (EV_P_ struct lifecycle_config *config)
{
  /* 调整最大嵌套深度 */
  if (config->max_nesting_depth > 0)
    MAX_NESTED_LOOPS = config->max_nesting_depth;
    
  /* 调整状态检查频率 */
  if (config->health_check_interval > 0)
    HEALTH_CHECK_INTERVAL = config->health_check_interval;
    
  /* 配置异常处理策略 */
  exception_handling_enabled = config->enable_exception_handling;
  
  /* 设置性能监控阈值 */
  if (config->slow_iteration_threshold > 0)
    SLOW_ITERATION_THRESHOLD = config->slow_iteration_threshold;
}

/* 生命周期配置结构 */
struct lifecycle_config
{
  int max_nesting_depth;          /* 最大嵌套深度 */
  int health_check_interval;      /* 健康检查间隔 */
  int enable_exception_handling;  /* 是否启用异常处理 */
  ev_tstamp slow_iteration_threshold;  /* 慢迭代阈值 */
  ev_tstamp max_pause_duration;   /* 最大暂停时间 */
};
```

## 9. 最佳实践与使用建议

### 9.1 生命周期管理最佳实践
```c
/* 1. 正确的生命周期管理 */
void
proper_lifecycle_management (void)
{
  /* 创建事件循环 */
  struct ev_loop *loop = ev_loop_new (EVFLAG_AUTO);
  if (!loop)
    {
      fprintf (stderr, "Failed to create event loop\n");
      return;
    }
    
  /* 注册必要的watcher */
  setup_application_watchers (EV_A);
  
  /* 运行事件循环 */
  int result = ev_run (EV_A_ 0);
  
  /* 清理资源 */
  ev_loop_destroy (EV_A);
}

/* 2. 优雅关闭处理 */
void
graceful_shutdown_handler (int sig)
{
  /* 设置停止标志 */
  ev_break (main_loop, EVBREAK_ALL);
  
  /* 执行清理工作 */
  cleanup_application_resources ();
}

/* 3. 错误恢复机制 */
void
setup_error_recovery (EV_P)
{
  /* 注册信号处理 */
  signal (SIGTERM, graceful_shutdown_handler);
  signal (SIGINT, graceful_shutdown_handler);
  
  /* 启用异常处理 */
#if EV_DEBUG
  exception_handling_enabled = 1;
#endif
}
```

### 9.2 监控和调试配置
```c
/* 1. 生产环境配置 */
void
configure_for_production (EV_P)
{
  /* 禁用调试功能 */
  ev_set_debug (EV_A_ 0);
  
  /* 启用基本统计 */
  ev_set_stats (EV_A_ 1);
  
  /* 设置合理的超时 */
  MAX_BLOCKING_INTERVAL = 1.0;  /* 1秒最大阻塞 */
  
  /* 配置健康检查 */
  HEALTH_CHECK_INTERVAL = 1000;  /* 每1000次迭代检查一次 */
}

/* 2. 开发调试配置 */
void
configure_for_development (EV_P)
{
  /* 启用完整调试 */
  ev_set_debug (EV_A_ 1);
  
  /* 启用详细统计 */
  ev_set_stats (EV_A_ 1);
  
  /* 启用生命周期追踪 */
  ev_enable_lifecycle_tracing (EV_A_ 1);
  
  /* 设置严格的健康检查 */
  HEALTH_CHECK_INTERVAL = 100;
}

/* 3. 性能测试配置 */
void
configure_for_performance_testing (EV_P)
{
  /* 最小化开销配置 */
  ev_set_debug (EV_A_ 0);
  ev_set_stats (EV_A_ 0);
  
  /* 优化批处理 */
  CALLBACK_BATCH_THRESHOLD = 1000;
  
  /* 减少状态检查频率 */
  HEALTH_CHECK_INTERVAL = 10000;
}
```

---
**分析版本**: v1.0  
**源码版本**: libev 4.33  
**更新时间**: 2026年3月1日
