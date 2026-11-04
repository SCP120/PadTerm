#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include "pt_metrics.h"

enum { RING = 4096 };
typedef struct { double v[RING]; int n; double total; double max; } series;

static series g_echo, g_draw, g_stall, g_feed;
static double g_key_at, g_last_beat, g_last_report, g_last_cpu;
static unsigned long long g_bytes, g_events, g_draws_full, g_connects_total, g_keys;
static char g_out[1024];

static void add(series *s, double x) {
    if (s->n < RING) s->v[s->n++] = x;
    s->total += x;
    if (x > s->max) s->max = x;
}
static int cmp(const void *a, const void *b) { double d = *(const double *)a - *(const double *)b; return d < 0 ? -1 : d > 0; }
static double pct(series *s, double p) {
    if (!s->n) return 0;
    qsort(s->v, (size_t)s->n, sizeof(double), cmp);
    return s->v[(int)((s->n - 1) * p)];
}
double ptm_now_ms(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec * 1000.0 + t.tv_usec / 1000.0; }
void ptm_key(void) { if (!g_key_at) g_key_at = ptm_now_ms(); g_keys++; }
void ptm_data(size_t n, double feed_ms) {
    g_bytes += n; g_events++;
    add(&g_feed, feed_ms);
    if (g_key_at) { add(&g_echo, ptm_now_ms() - g_key_at); g_key_at = 0; }
}
void ptm_draw(double ms, double h) { add(&g_draw, ms); if (h > 400) g_draws_full++; }
void ptm_connect(void) { g_connects_total++; }
void ptm_heartbeat(void) {
    double now = ptm_now_ms();
    if (g_last_beat) add(&g_stall, now - g_last_beat - 100); /* the timer interval is 100 ms */
    g_last_beat = now;
}
const char *ptm_report(void) {
    double now = ptm_now_ms();
    struct rusage ru; getrusage(RUSAGE_SELF, &ru);
    double cpu = ru.ru_utime.tv_sec * 1000.0 + ru.ru_utime.tv_usec / 1000.0 + ru.ru_stime.tv_sec * 1000.0 + ru.ru_stime.tv_usec / 1000.0;
    double wall = g_last_report ? now - g_last_report : 0;
    struct task_basic_info ti; mach_msg_type_number_t c = TASK_BASIC_INFO_COUNT;
    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&ti, &c);
    vm_statistics_data_t vm; mach_msg_type_number_t vc = HOST_VM_INFO_COUNT;
    host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vm, &vc);
    vm_size_t page; host_page_size(mach_host_self(), &page);
    UIDevice *d = [UIDevice currentDevice];
    d.batteryMonitoringEnabled = YES;
    snprintf(g_out, sizeof g_out,
             "{\"wall_ms\":%.0f,\"cpu_pct\":%.1f,\"rss_mb\":%.1f,\"free_mb\":%.1f,\"battery\":%.2f,\"bat_state\":%d,"
             "\"keys\":%llu,\"echo_n\":%d,\"echo_p50\":%.0f,\"echo_p95\":%.0f,\"echo_max\":%.0f,"
             "\"draw_n\":%d,\"draw_p50\":%.1f,\"draw_p95\":%.1f,\"draw_max\":%.1f,\"draw_total_ms\":%.0f,\"draws_full\":%llu,"
             "\"stall_p95\":%.0f,\"stall_max\":%.0f,\"bytes\":%llu,\"events\":%llu,\"feed_total_ms\":%.0f,\"feed_max\":%.1f,\"connects\":%llu}",
             wall, wall > 0 ? (cpu - g_last_cpu) * 100 / wall : 0, ti.resident_size / 1048576.0,
             vm.free_count * (double)page / 1048576.0, d.batteryLevel, (int)d.batteryState,
             g_keys, g_echo.n, pct(&g_echo, .5), pct(&g_echo, .95), g_echo.max,
             g_draw.n, pct(&g_draw, .5), pct(&g_draw, .95), g_draw.max, g_draw.total, g_draws_full,
             pct(&g_stall, .95), g_stall.max, g_bytes, g_events, g_feed.total, g_feed.max, g_connects_total);
    memset(&g_echo, 0, sizeof g_echo); memset(&g_draw, 0, sizeof g_draw);
    memset(&g_stall, 0, sizeof g_stall); memset(&g_feed, 0, sizeof g_feed);
    g_bytes = g_events = g_draws_full = g_keys = 0;
    g_last_report = now; g_last_cpu = cpu;
    return g_out;
}
