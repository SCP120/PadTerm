/* Test-only metrics (SELFTEST=1). Called on the main thread. */
#ifndef PT_METRICS_H
#define PT_METRICS_H
#include <stddef.h>
void ptm_key(void);                 /* a key went to the terminal */
void ptm_data(size_t n, double feed_ms);
void ptm_draw(double ms, double height_points);
void ptm_connect(void);
void ptm_heartbeat(void);
double ptm_now_ms(void);
/* One JSON object with the window since the last call. */
const char *ptm_report(void);
#endif
