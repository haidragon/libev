/*
 * libev 使用案例 - 基础事件循环演示
 * 作者: Lingma
 * 功能: 演示libev的基本使用方法，包括定时器、IO事件等
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>

// 包含libev头文件
#include "ev.h"

// 全局变量用于演示
static int timer_count = 0;
static int io_event_count = 0;

/**
 * 定时器回调函数
 * @param loop 事件循环指针
 * @param w 定时器watcher
 * @param revents 事件类型
 */
static void timer_callback(EV_P_ ev_timer *w, int revents) {
    printf("[定时器] 第%d次触发 (时间: %f秒)\n", ++timer_count, ev_now(EV_A));
    
    // 演示条件停止
    if (timer_count >= 5) {
        printf("[定时器] 达到最大次数，停止定时器\n");
        ev_timer_stop(EV_A_ w);
        
        // 也可以停止整个事件循环
        // ev_break(EV_A_ EVBREAK_ALL);
    }
}

/**
 * IO事件回调函数
 * @param loop 事件循环指针
 * @param w IO watcher
 * @param revents 事件类型
 */
static void io_callback(EV_P_ ev_io *w, int revents) {
    char buffer[1024];
    ssize_t bytes_read;
    
    printf("[IO事件] 文件描述符 %d 触发事件 (revents: %d)\n", w->fd, revents);
    
    if (revents & EV_READ) {
        // 读取数据
        bytes_read = read(w->fd, buffer, sizeof(buffer) - 1);
        if (bytes_read > 0) {
            buffer[bytes_read] = '\0';
            printf("[IO事件] 读取到数据: %s", buffer);
            io_event_count++;
            
            // 回显数据
            write(w->fd, buffer, bytes_read);
        } else if (bytes_read == 0) {
            printf("[IO事件] 连接关闭\n");
            ev_io_stop(EV_A_ w);
            close(w->fd);
        } else {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                perror("[IO事件] 读取错误");
                ev_io_stop(EV_A_ w);
                close(w->fd);
            }
        }
    }
}

/**
 * 信号处理回调函数
 * @param loop 事件循环指针
 * @param w 信号watcher
 * @param revents 事件类型
 */
static void signal_callback(EV_P_ ev_signal *w, int revents) {
    printf("[信号] 收到信号 %d\n", w->signum);
    
    if (w->signum == SIGINT || w->signum == SIGTERM) {
        printf("[信号] 收到终止信号，准备退出...\n");
        ev_break(EV_A_ EVBREAK_ALL);
    }
}

/**
 * 周期性回调函数
 * @param loop 事件循环指针
 * @param w 周期watcher
 * @param revents 事件类型
 */
static void periodic_callback(EV_P_ ev_periodic *w, int revents) {
    printf("[周期事件] 当前时间: %f\n", ev_now(EV_A));
}

/**
 * 创建TCP服务器socket
 * @return socket文件描述符
 */
static int create_server_socket(int port) {
    int sockfd;
    struct sockaddr_in server_addr;
    
    // 创建socket
    sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("socket创建失败");
        return -1;
    }
    
    // 设置socket选项
    int opt = 1;
    if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt失败");
        close(sockfd);
        return -1;
    }
    
    // 绑定地址
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(port);
    
    if (bind(sockfd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind失败");
        close(sockfd);
        return -1;
    }
    
    // 监听连接
    if (listen(sockfd, 5) < 0) {
        perror("listen失败");
        close(sockfd);
        return -1;
    }
    
    // 设置为非阻塞模式
    int flags = fcntl(sockfd, F_GETFL, 0);
    fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);
    
    printf("TCP服务器启动在端口 %d\n", port);
    return sockfd;
}

/**
 * 主函数 - 演示libev的各种功能
 */
int main() {
    printf("=== libev 使用案例演示 ===\n");
    
    // 创建默认事件循环
    struct ev_loop *loop = EV_DEFAULT;
    if (!loop) {
        fprintf(stderr, "创建事件循环失败\n");
        return 1;
    }
    
    printf("事件循环创建成功\n");
    
    // 1. 创建定时器watcher
    ev_timer timer_watcher;
    ev_timer_init(&timer_watcher, timer_callback, 1.0, 2.0); // 1秒后启动，每2秒触发一次
    ev_timer_start(loop, &timer_watcher);
    printf("定时器已启动: 1秒延迟，2秒间隔\n");
    
    // 2. 创建信号watcher
    ev_signal sigint_watcher, sigterm_watcher;
    ev_signal_init(&sigint_watcher, signal_callback, SIGINT);
    ev_signal_init(&sigterm_watcher, signal_callback, SIGTERM);
    ev_signal_start(loop, &sigint_watcher);
    ev_signal_start(loop, &sigterm_watcher);
    printf("信号监听已启动: SIGINT, SIGTERM\n");
    
    // 3. 创建周期事件watcher (每分钟触发)
    ev_periodic periodic_watcher;
    ev_periodic_init(&periodic_watcher, periodic_callback, 0., 60., 0);
    ev_periodic_start(loop, &periodic_watcher);
    printf("周期事件已启动: 每60秒触发\n");
    
    // 4. 创建TCP服务器
    int server_fd = create_server_socket(8080);
    if (server_fd < 0) {
        fprintf(stderr, "服务器创建失败\n");
        ev_loop_destroy(loop);
        return 1;
    }
    
    // 5. 创建IO watcher监听服务器socket
    ev_io server_io_watcher;
    ev_io_init(&server_io_watcher, io_callback, server_fd, EV_READ);
    ev_io_start(loop, &server_io_watcher);
    printf("服务器IO监听已启动\n");
    
    printf("\n=== 开始事件循环 ===\n");
    printf("请访问 http://localhost:8080 测试IO事件\n");
    printf("按 Ctrl+C 退出程序\n");
    printf("==================\n\n");
    
    // 启动事件循环
    ev_run(loop, 0);
    
    // 清理资源
    printf("\n=== 清理资源 ===\n");
    ev_timer_stop(loop, &timer_watcher);
    ev_signal_stop(loop, &sigint_watcher);
    ev_signal_stop(loop, &sigterm_watcher);
    ev_periodic_stop(loop, &periodic_watcher);
    ev_io_stop(loop, &server_io_watcher);
    close(server_fd);
    
    ev_loop_destroy(loop);
    printf("程序正常退出\n");
    
    return 0;
}
