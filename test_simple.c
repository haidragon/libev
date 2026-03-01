/*
 * libev 简单测试程序
 * 用于验证build_simple.sh编译的库是否正常工作
 */

#include <stdio.h>
#include <ev.h>

// 简单的定时器回调
static void timeout_cb(EV_P_ ev_timer *w, int revents) {
    printf("定时器触发! 时间: %f\n", ev_now(EV_A));
    ev_break(EV_A_ EVBREAK_ALL);
}

int main() {
    printf("=== libev 简单测试 ===\n");
    
    // 创建事件循环
    struct ev_loop *loop = EV_DEFAULT;
    if (!loop) {
        fprintf(stderr, "创建事件循环失败\n");
        return 1;
    }
    
    printf("事件循环创建成功\n");
    
    // 创建定时器
    ev_timer timeout_watcher;
    ev_timer_init(&timeout_watcher, timeout_cb, 1.0, 0.);
    ev_timer_start(loop, &timeout_watcher);
    
    printf("定时器已启动，1秒后触发\n");
    
    // 运行事件循环
    printf("开始事件循环...\n");
    ev_run(loop, 0);
    
    // 清理
    ev_timer_stop(loop, &timeout_watcher);
    ev_loop_destroy(loop);
    
    printf("测试完成!\n");
    return 0;
}
