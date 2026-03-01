# libev 与外部线程交互方式深度分析

## 1. 线程交互整体架构

### 1.1 设计理念
libev通过异步通知机制实现与外部线程的安全交互，采用ev_async watcher作为线程间通信的核心组件，确保在多线程环境下事件循环能够正确响应来自其他线程的事件通知。

### 1.2 核心线程交互数据结构
```c
/* ev.h - 异步通知相关定义 */
typedef struct ev_async
{
  EV_WATCHER (ev_async)
  sig_atomic_t sent;     /* 通知发送标志 */
} ev_async;

/* 线程交互相关全局变量 */
VAR(ev_async *, asyncs, , , 0)         /* 异步watcher数组 */
VAR(int, async_count, , , 0)           /* 异步watcher数量 */
VAR(sig_atomic_t, async_pending, , , 0) /* 异步事件待处理标志 */
VAR(int, async_write, , , -1)          /* 写端文件描述符 */
VAR(int, async_read, , , -1)           /* 读端文件描述符 */
```

## 2. 异步通知机制实现

### 2.1 ev_async初始化与配置
```c
/* ev.c - 异步通知初始化 */
void
ev_async_init (ev_async *w, void (*cb)(EV_P_ ev_async *w, int revents))
{
  /* 初始化基础watcher字段 */
  EV_WATCHER_INIT (w, cb);
  
  /* 初始化发送标志 */
  w->sent = 0;
}

/* 异步通知系统初始化 */
static void
asyncs_init (EV_P)
{
#if EV_USE_EVENTFD
  /* 优先使用eventfd (Linux) */
  async_write = async_read = eventfd (0, EFD_CLOEXEC | EFD_NONBLOCK);
  if (async_write < 0)
#endif
    {
      /* fallback到pipe */
      int fds[2];
      
#if HAVE_PIPE2
      if (pipe2 (fds, O_CLOEXEC | O_NONBLOCK))
#endif
        {
          if (pipe (fds))
            return;
            
          fd_intern (fds[0]);
          fd_intern (fds[1]);
          fcntl (fds[0], F_SETFL, O_NONBLOCK);
          fcntl (fds[1], F_SETFL, O_NONBLOCK);
          fcntl (fds[0], F_SETFD, FD_CLOEXEC);
          fcntl (fds[1], F_SETFD, FD_CLOEXEC);
        }
        
      async_read = fds[0];
      async_write = fds[1];
    }
    
  /* 注册读端到事件循环 */
  if (async_read >= 0)
    {
      fd_intern (async_read);
      ev_io_init (&async_io, async_io_cb, async_read, EV_READ);
      ev_io_start (EV_A_ &async_io);
    }
}

/* 异步IO回调处理 */
static void
async_io_cb (EV_P_ ev_io *w, int revents)
{
  /* 读取通知数据 */
#if EV_USE_EVENTFD
  uint64_t counter;
  read (async_read, &counter, sizeof (uint64_t));
#else
  char dummy[128];
  read (async_read, dummy, sizeof (dummy));
#endif

  /* 处理所有待处理的异步事件 */
  asyncs_process (EV_A);
}
```

### 2.2 异步事件发送机制
```c
/* ev.c - 异步事件发送 */
void
ev_async_send (EV_P_ ev_async *w)
{
  /* 原子设置发送标志 */
  w->sent = 1;
  
  /* 原子设置全局pending标志 */
  async_pending = 1;
  
  /* 发送通知信号 */
  if (async_write >= 0)
    {
#if EV_USE_EVENTFD
      uint64_t counter = 1;
      write (async_write, &counter, sizeof (uint64_t));
#else
      write (async_write, "x", 1);
#endif
    }
    
#if EV_USE_SIGNALFD || EV_USE_EVENTFD
  /* 在支持signalfd/eventfd的平台上唤醒事件循环 */
  if (backend_fd >= 0)
    {
      /* 通过写入backend fd来唤醒轮询 */
      char dummy = 0;
      write (backend_fd, &dummy, 1);
    }
#endif
}

/* 批量异步事件发送 */
void
ev_async_send_batch (EV_P_ ev_async **watchers, int count)
{
  /* 批量设置发送标志 */
  for (int i = 0; i < count; ++i)
    {
      watchers[i]->sent = 1;
    }
    
  /* 设置全局标志 */
  async_pending = 1;
  
  /* 发送一次通知 */
  if (async_write >= 0)
    {
#if EV_USE_EVENTFD
      uint64_t counter = count;
      write (async_write, &counter, sizeof (uint64_t));
#else
      for (int i = 0; i < count; ++i)
        write (async_write, "x", 1);
#endif
    }
}
```

## 3. 线程交互处理流程

### 3.1 异步事件处理主流程
```c
/* ev.c - 异步事件处理 */
static void
asyncs_process (EV_P)
{
  /* 重置全局pending标志 */
  async_pending = 0;
  
  /* 处理所有标记为sent的异步watcher */
  for (int i = 0; i < async_count; ++i)
    {
      ev_async *w = asyncs[i];
      
      if (w->sent)
        {
          /* 清除发送标志 */
          w->sent = 0;
          
          /* 设置pending状态 */
          w->pending = 1;
          pendings[ABSPRI (w)][w->pending - 1].w = (ev_watcher *)w;
          pendings[ABSPRI (w)][w->pending - 1].events = EV_ASYNC;
          pendingpri = NUMPRI;  /* force recalculation */
        }
    }
}

/* 异步watcher回调执行 */
static void
ev_async_callback_executor (EV_P_ ev_async *w, int revents)
{
  /* 执行用户定义的回调 */
  if (ev_cb (w))
    ev_cb (w) (EV_A_ w, revents);
    
  /* 清除pending状态 */
  w->pending = 0;
}
```

### 3.2 线程安全的状态检查
```c
/* ev.c - 线程安全的状态检查 */
int
ev_async_pending (ev_async *w)
{
  /* 原子读取发送标志 */
  return w->sent;
}

/* 线程安全的循环状态检查 */
int
ev_loop_alive (EV_P)
{
  /* 检查事件循环是否仍在运行 */
  return loop_state == LOOP_RUNNING && activecnt > 0;
}

/* 线程安全的watcher状态检查 */
int
ev_is_active_safe (ev_watcher *w)
{
  /* 使用原子操作检查活跃状态 */
  return __sync_fetch_and_or (&w->active, 0) != 0;
}
```

## 4. 多线程使用模式

### 4.1 生产者-消费者模式
```c
/* 1. 生产者线程 - 发送异步通知 */
typedef struct
{
  ev_async async_watcher;
  struct work_queue *queue;
  pthread_mutex_t queue_mutex;
} producer_data_t;

static void
producer_callback (EV_P_ ev_async *w, int revents)
{
  producer_data_t *data = (producer_data_t *)w->data;
  
  /* 处理队列中的工作任务 */
  pthread_mutex_lock (&data->queue_mutex);
  while (!queue_empty (data->queue))
    {
      work_item_t *item = queue_pop (data->queue);
      process_work_item (item);
    }
  pthread_mutex_unlock (&data->queue_mutex);
}

/* 生产者线程函数 */
static void *
producer_thread_func (void *arg)
{
  producer_data_t *data = (producer_data_t *)arg;
  
  while (running)
    {
      /* 生成工作任务 */
      work_item_t *item = create_work_item ();
      
      /* 添加到队列 */
      pthread_mutex_lock (&data->queue_mutex);
      queue_push (data->queue, item);
      pthread_mutex_unlock (&data->queue_mutex);
      
      /* 发送异步通知 */
      ev_async_send (main_loop, &data->async_watcher);
      
      /* 控制生产速率 */
      usleep (1000);  /* 1ms间隔 */
    }
    
  return NULL;
}
```

### 4.2 工作线程池模式
```c
/* 2. 工作线程池 - 处理异步任务 */
typedef struct
{
  ev_async async_watcher;
  struct task_queue *task_queue;
  pthread_cond_t worker_cond;
  pthread_mutex_t queue_mutex;
  int worker_count;
  int shutdown;
} thread_pool_t;

static void
thread_pool_callback (EV_P_ ev_async *w, int revents)
{
  thread_pool_t *pool = (thread_pool_t *)w->data;
  
  pthread_mutex_lock (&pool->queue_mutex);
  
  /* 唤醒等待的工作线程 */
  pthread_cond_broadcast (&pool->worker_cond);
  
  pthread_mutex_unlock (&pool->queue_mutex);
}

/* 工作线程函数 */
static void *
worker_thread_func (void *arg)
{
  thread_pool_t *pool = (thread_pool_t *)arg;
  
  while (1)
    {
      pthread_mutex_lock (&pool->queue_mutex);
      
      /* 等待任务或关闭信号 */
      while (queue_empty (pool->task_queue) && !pool->shutdown)
        {
          pthread_cond_wait (&pool->worker_cond, &pool->queue_mutex);
        }
        
      /* 检查关闭信号 */
      if (pool->shutdown)
        {
          pthread_mutex_unlock (&pool->queue_mutex);
          break;
        }
        
      /* 获取并处理任务 */
      task_t *task = queue_pop (pool->task_queue);
      pthread_mutex_unlock (&pool->queue_mutex);
      
      /* 执行任务 */
      execute_task (task);
      
      /* 清理任务 */
      destroy_task (task);
    }
    
  return NULL;
}

/* 初始化线程池 */
thread_pool_t *
create_thread_pool (int num_workers)
{
  thread_pool_t *pool = malloc (sizeof(thread_pool_t));
  
  /* 初始化数据结构 */
  ev_async_init (&pool->async_watcher, thread_pool_callback);
  pool->task_queue = create_task_queue ();
  pthread_cond_init (&pool->worker_cond, NULL);
  pthread_mutex_init (&pool->queue_mutex, NULL);
  pool->worker_count = num_workers;
  pool->shutdown = 0;
  
  /* 启动工作线程 */
  for (int i = 0; i < num_workers; ++i)
    {
      pthread_t worker_thread;
      pthread_create (&worker_thread, NULL, worker_thread_func, pool);
    }
    
  return pool;
}
```

## 5. 线程交互性能优化

### 5.1 批处理优化
```c
/* ev.c - 批量异步处理优化 */
static void
asyncs_process_batch (EV_P)
{
  /* 预先收集所有需要处理的watcher */
  ev_async *pending_watchers[256];
  int pending_count = 0;
  
  for (int i = 0; i < async_count && pending_count < 256; ++i)
    {
      if (asyncs[i]->sent)
        {
          pending_watchers[pending_count++] = asyncs[i];
          asyncs[i]->sent = 0;
        }
    }
    
  /* 批量设置pending状态 */
  for (int i = 0; i < pending_count; ++i)
    {
      ev_async *w = pending_watchers[i];
      w->pending = 1;
      pendings[ABSPRI (w)][w->pending - 1].w = (ev_watcher *)w;
      pendings[ABSPRI (w)][w->pending - 1].events = EV_ASYNC;
    }
    
  /* 更新优先级 */
  pendingpri = NUMPRI;
  async_pending = 0;
}

/* 智能批处理阈值 */
#define ASYNC_BATCH_THRESHOLD 8

void
ev_async_send_smart (EV_P_ ev_async *w)
{
  static int send_count = 0;
  
  w->sent = 1;
  async_pending = 1;
  
  /* 达到阈值时批量发送 */
  if (++send_count >= ASYNC_BATCH_THRESHOLD)
    {
      ev_async_send_batch_actual (EV_A);
      send_count = 0;
    }
  else
    {
      /* 延迟发送，允许批处理 */
      ev_once (EV_A_ -1, 0, 0.001, delayed_async_send, w);
    }
}

static void
delayed_async_send (EV_P_ ev_once *once, int revents)
{
  /* 执行实际的异步发送 */
  if (async_write >= 0)
    {
      char signal = 1;
      write (async_write, &signal, 1);
    }
}
```

### 5.2 内存屏障优化
```c
/* ev.c - 内存屏障优化 */
static inline void
async_barrier_acquire (void)
{
  /* 读内存屏障，确保之前的读操作完成 */
  __asm__ __volatile__ ("" ::: "memory");
}

static inline void
async_barrier_release (void)
{
  /* 写内存屏障，确保之后的写操作可见 */
  __asm__ __volatile__ ("" ::: "memory");
}

/* 优化的异步发送 */
void
ev_async_send_optimized (EV_P_ ev_async *w)
{
  /* 使用内存屏障确保原子性 */
  __sync_synchronize ();
  w->sent = 1;
  async_barrier_release ();
  
  /* 原子设置全局标志 */
  __sync_or_and_fetch (&async_pending, 1);
  
  /* 发送通知 */
  if (async_write >= 0)
    {
      char signal = 1;
      write (async_write, &signal, 1);
    }
}

/* 优化的异步检查 */
int
ev_async_pending_optimized (ev_async *w)
{
  async_barrier_acquire ();
  return w->sent;
}
```

## 6. 错误处理与异常恢复

### 6.1 线程交互异常处理
```c
/* ev.c - 线程交互异常处理 */
static void
handle_async_error (EV_P_ int error_code)
{
  switch (error_code)
    {
    case EBADF:
      /* 文件描述符无效，重新初始化 */
      asyncs_reinit (EV_A);
      break;
    case EAGAIN:
      /* 资源暂时不可用，稍后重试 */
      ev_once (EV_A_ -1, 0, 0.001, retry_async_operation, NULL);
      break;
    case EPIPE:
      /* 管道破裂，可能是接收端关闭 */
      fprintf (stderr, "Async pipe broken, reinitializing\n");
      asyncs_reinit (EV_A);
      break;
    }
}

/* 异步系统重新初始化 */
static void
asyncs_reinit (EV_P)
{
  /* 清理旧资源 */
  if (async_read >= 0)
    {
      close (async_read);
      async_read = -1;
    }
  if (async_write >= 0 && async_write != async_read)
    {
      close (async_write);
      async_write = -1;
    }
    
  /* 重新初始化 */
  asyncs_init (EV_A);
  
  /* 重新注册所有异步watcher */
  for (int i = 0; i < async_count; ++i)
    {
      if (ev_is_active (asyncs[i]))
        {
          ev_async_start (EV_A_ asyncs[i]);
        }
    }
}

/* 异步操作重试 */
static void
retry_async_operation (EV_P_ ev_once *once, int revents)
{
  /* 重试失败的异步操作 */
  for (int i = 0; i < async_count; ++i)
    {
      if (asyncs[i]->sent && !asyncs[i]->pending)
        {
          ev_async_send (EV_A_ asyncs[i]);
        }
    }
}
```

### 6.2 死锁预防机制
```c
/* ev.c - 死锁预防 */
static pthread_mutex_t async_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned long async_send_count = 0;

void
ev_async_send_safe (EV_P_ ev_async *w)
{
  /* 使用超时锁防止死锁 */
  struct timespec timeout;
  clock_gettime (CLOCK_REALTIME, &timeout);
  timeout.tv_sec += 1;  /* 1秒超时 */
  
  if (pthread_mutex_timedlock (&async_mutex, &timeout) != 0)
    {
      fprintf (stderr, "Warning: Async mutex timeout, possible deadlock\n");
      return;
    }
    
  /* 执行异步发送 */
  w->sent = 1;
  async_pending = 1;
  
  if (async_write >= 0)
    {
      char signal = 1;
      write (async_write, &signal, 1);
    }
    
  pthread_mutex_unlock (&async_mutex);
  
  /* 统计发送次数 */
  __sync_add_and_fetch (&async_send_count, 1);
}

/* 死锁检测 */
static void
detect_async_deadlock (EV_P)
{
  static unsigned long last_send_count = 0;
  static ev_tstamp last_check_time = 0;
  
  ev_tstamp current_time = ev_time ();
  
  if (current_time - last_check_time > 10.0)  /* 每10秒检查一次 */
    {
      unsigned long current_count = async_send_count;
      
      if (current_count == last_send_count && async_pending)
        {
          fprintf (stderr, "Potential async deadlock detected\n");
          /* 采取恢复措施 */
          force_async_processing (EV_A);
        }
        
      last_send_count = current_count;
      last_check_time = current_time;
    }
}

/* 强制异步处理 */
static void
force_async_processing (EV_P)
{
  /* 强制处理积压的异步事件 */
  if (async_write >= 0)
    {
      char force_signal = 1;
      write (async_write, &force_signal, 1);
    }
    
  /* 直接调用处理函数 */
  asyncs_process (EV_A);
}
```

## 7. 调试与监控机制

### 7.1 线程交互状态监控
```c
#if EV_STATS
/* ev.c - 异步交互统计 */
VAR(unsigned long, async_send_count, , , 0)      /* 异步发送次数 */
VAR(unsigned long, async_receive_count, , , 0)   /* 异步接收次数 */
VAR(unsigned long, async_process_count, , , 0)   /* 异步处理次数 */
VAR(ev_tstamp, async_max_latency, , , 0.)        /* 最大延迟时间 */
VAR(unsigned long, async_error_count, , , 0)     /* 异步错误次数 */
#endif

/* 性能监控的异步发送 */
void
ev_async_send_monitored (EV_P_ ev_async *w)
{
#if EV_STATS
  ev_tstamp send_time = ev_time ();
#endif

  ev_async_send (EV_A_ w);

#if EV_STATS
  ev_tstamp receive_time = ev_time ();
  ev_tstamp latency = receive_time - send_time;
  
  __sync_add_and_fetch (&async_send_count, 1);
  
  if (latency > async_max_latency)
    async_max_latency = latency;
    
  if (latency > 0.001)  /* 超过1ms的延迟 */
    {
      fprintf (stderr, "High async latency: %.3fms\n", latency * 1000);
    }
#endif
}

/* 异步交互状态报告 */
void
ev_dump_async_statistics (EV_P)
{
#if EV_STATS
  fprintf (stderr, "Async Interaction Statistics:\n");
  fprintf (stderr, "  Send Count: %lu\n", async_send_count);
  fprintf (stderr, "  Receive Count: %lu\n", async_receive_count);
  fprintf (stderr, "  Process Count: %lu\n", async_process_count);
  fprintf (stderr, "  Error Count: %lu\n", async_error_count);
  fprintf (stderr, "  Max Latency: %.3fms\n", async_max_latency * 1000);
  fprintf (stderr, "  Current Pending: %d\n", async_pending);
  
  /* 计算成功率 */
  if (async_send_count > 0)
    {
      double success_rate = (double)async_receive_count / async_send_count * 100;
      fprintf (stderr, "  Success Rate: %.2f%%\n", success_rate);
    }
#endif
}
```

### 7.2 调试追踪机制
```c
#if EV_DEBUG
/* ev.c - 异步交互调试追踪 */
VAR(unsigned long, async_trace_id, , , 0)
VAR(struct async_trace_entry, async_trace_buffer, [1024], , 0)
VAR(int, async_trace_index, , , 0)

struct async_trace_entry
{
  unsigned long id;
  ev_async *watcher;
  const char *sender_thread;
  ev_tstamp timestamp;
  const char *operation;
  int thread_id;
};

/* 异步操作追踪 */
#define TRACE_ASYNC_OP(op, w) \
  trace_async_operation (__FUNCTION__, op, EV_A_ w)

static void
trace_async_operation (const char *func, const char *op, EV_P_ ev_async *w)
{
  struct async_trace_entry *entry = &async_trace_buffer[async_trace_index];
  
  entry->id = ++async_trace_id;
  entry->watcher = w;
  entry->sender_thread = func;
  entry->timestamp = ev_time ();
  entry->operation = op;
  entry->thread_id = get_current_thread_id ();
  
  async_trace_index = (async_trace_index + 1) % 1024;
}

/* 异步追踪信息打印 */
void
ev_dump_async_trace (EV_P)
{
  fprintf (stderr, "Async Operation Trace:\n");
  
  int start = async_trace_index;
  for (int i = 0; i < 1024; ++i)
    {
      int idx = (start + i) % 1024;
      struct async_trace_entry *entry = &async_trace_buffer[idx];
      
      if (entry->id > 0)
        {
          fprintf (stderr, "[%lu] %s - %s on watcher %p (thread %d) at %.6f\n",
                   entry->id,
                   entry->sender_thread,
                   entry->operation,
                   entry->watcher,
                   entry->thread_id,
                   entry->timestamp);
        }
    }
}
#endif
```

## 8. 最佳实践与使用建议

### 8.1 线程交互设计模式
```c
/* 1. 推荐的线程交互模式 */
typedef struct
{
  ev_async async_watcher;
  struct circular_buffer *message_buffer;
  pthread_mutex_t buffer_mutex;
  size_t buffer_size;
} thread_communicator_t;

/* 初始化线程通信器 */
thread_communicator_t *
create_thread_communicator (size_t buffer_size)
{
  thread_communicator_t *comm = malloc (sizeof(thread_communicator_t));
  
  ev_async_init (&comm->async_watcher, message_receiver_callback);
  comm->message_buffer = create_circular_buffer (buffer_size);
  pthread_mutex_init (&comm->buffer_mutex, NULL);
  comm->buffer_size = buffer_size;
  
  return comm;
}

/* 消息发送函数 */
int
send_message_to_loop (EV_P_ thread_communicator_t *comm, void *message, size_t size)
{
  pthread_mutex_lock (&comm->buffer_mutex);
  
  /* 检查缓冲区空间 */
  if (circular_buffer_free_space (comm->message_buffer) < size + sizeof(size_t))
    {
      pthread_mutex_unlock (&comm->buffer_mutex);
      return -1;  /* 缓冲区满 */
    }
    
  /* 写入消息长度和内容 */
  circular_buffer_write (comm->message_buffer, &size, sizeof(size_t));
  circular_buffer_write (comm->message_buffer, message, size);
  
  pthread_mutex_unlock (&comm->buffer_mutex);
  
  /* 发送异步通知 */
  ev_async_send (EV_A_ &comm->async_watcher);
  
  return 0;
}

/* 消息接收回调 */
static void
message_receiver_callback (EV_P_ ev_async *w, int revents)
{
  thread_communicator_t *comm = (thread_communicator_t *)w->data;
  
  pthread_mutex_lock (&comm->buffer_mutex);
  
  /* 处理所有缓冲的消息 */
  while (circular_buffer_used_space (comm->message_buffer) > sizeof(size_t))
    {
      size_t message_size;
      circular_buffer_peek (comm->message_buffer, &message_size, sizeof(size_t));
      
      if (circular_buffer_used_space (comm->message_buffer) >= sizeof(size_t) + message_size)
        {
          /* 跳过长度字段 */
          circular_buffer_skip (comm->message_buffer, sizeof(size_t));
          
          /* 读取消息 */
          char *message = malloc (message_size);
          circular_buffer_read (comm->message_buffer, message, message_size);
          
          /* 处理消息 */
          process_incoming_message (message, message_size);
          
          free (message);
        }
      else
        {
          break;  /* 不完整的消息 */
        }
    }
    
  pthread_mutex_unlock (&comm->buffer_mutex);
}
```

### 8.2 性能调优建议
```c
/* 1. 异步交互性能调优 */
void
optimize_async_performance (EV_P)
{
  /* 调整批处理阈值 */
  ASYNC_BATCH_THRESHOLD = determine_optimal_batch_size ();
  
  /* 优化缓冲区大小 */
  if (async_read >= 0)
    {
      /* 增大接收缓冲区 */
      int buffer_size = 64 * 1024;  /* 64KB */
      setsockopt (async_read, SOL_SOCKET, SO_RCVBUF, &buffer_size, sizeof(buffer_size));
    }
    
  /* 启用低延迟模式 */
  if (async_write >= 0)
    {
      int low_latency = 1;
      setsockopt (async_write, IPPROTO_TCP, TCP_NODELAY, &low_latency, sizeof(low_latency));
    }
}

/* 2. 内存使用优化 */
void
optimize_async_memory_usage (EV_P_ int memory_constraint)
{
  switch (memory_constraint)
    {
    case MEMORY_CONSTRAINT_SEVERE:
      /* 严格内存限制 */
      async_trace_buffer_size = 64;
      async_batch_threshold = 4;
      break;
    case MEMORY_CONSTRAINT_MODERATE:
      /* 中等内存限制 */
      async_trace_buffer_size = 256;
      async_batch_threshold = 8;
      break;
    case MEMORY_CONSTRAINT_NONE:
      /* 无内存限制 */
      async_trace_buffer_size = 1024;
      async_batch_threshold = 16;
      break;
    }
}

/* 3. 监控告警配置 */
void
setup_async_monitoring_alerts (EV_P)
{
  /* 设置性能阈值 */
  struct async_alert_config {
    ev_tstamp latency_threshold;
    unsigned long error_rate_threshold;
    unsigned long throughput_threshold;
  } config = {
    .latency_threshold = 0.005,      /* 5ms延迟阈值 */
    .error_rate_threshold = 5,       /* 5%错误率阈值 */
    .throughput_threshold = 1000     /* 1000 ops/sec吞吐量阈值 */
  };
  
  /* 注册监控回调 */
  ev_set_async_alert_thresholds (EV_A_ &config, async_alert_callback);
}

/* 告警回调函数 */
static void
async_alert_callback (EV_P_ const char *alert_type, const char *message)
{
  fprintf (stderr, "ASYNC ALERT [%s]: %s\n", alert_type, message);
  
  /* 根据告警类型采取相应措施 */
  if (strcmp (alert_type, "HIGH_LATENCY") == 0)
    {
      optimize_async_performance (EV_A);
    }
  else if (strcmp (alert_type, "HIGH_ERROR_RATE") == 0)
    {
      restart_async_subsystem (EV_A);
    }
}
```

---
**分析版本**: v1.0  
**源码版本**: libev 4.33  
**更新时间**: 2026年3月1日
