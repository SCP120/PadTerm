#include "pt_test.h"
#include <stdarg.h>
#include <stdlib.h>
#include <sys/time.h>

#define PT_MAX_TESTS 256
static struct { const char *name, *ids; pt_test_fn fn; } g_tests[PT_MAX_TESTS];
static int g_count;
static char g_msg[1024];
static int g_failed;
#define PT_MAX_DEFER 16
static struct { void (*fn)(void *); void *arg; } g_defer[PT_MAX_DEFER];
static int g_ndefer;

void pt_test_defer(void (*fn)(void *), void *arg) {
    if (g_ndefer >= PT_MAX_DEFER) { fprintf(stderr, "too many deferred cleanups\n"); exit(2); }
    g_defer[g_ndefer].fn = fn; g_defer[g_ndefer].arg = arg; g_ndefer++;
}

void pt_test_register(const char *name, const char *ids, pt_test_fn fn) {
    if (g_count >= PT_MAX_TESTS) { fprintf(stderr, "too many tests\n"); exit(2); }
    g_tests[g_count].name = name; g_tests[g_count].ids = ids; g_tests[g_count].fn = fn; g_count++;
}

void pt_test_fail(const char *file, int line, const char *fmt, ...) {
    if (g_failed) return; /* keep the first failure */
    g_failed = 1;
    int n = snprintf(g_msg, sizeof g_msg, "%s:%d: ", file, line);
    va_list ap; va_start(ap, fmt); vsnprintf(g_msg + n, sizeof g_msg - (size_t)n, fmt, ap); va_end(ap);
}

int pt_test_failed_now(void) { return g_failed; }

static void json_str(FILE *f, const char *s) {
    fputc('"', f);
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c == '"' || c == '\\') fprintf(f, "\\%c", c);
        else if (c < 0x20) fprintf(f, "\\u%04x", c);
        else fputc(c, f);
    }
    fputc('"', f);
}

static double now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0; }

/* usage: <binary> <suite> <out.jsonl> [name-filter] */
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s suite out.jsonl [filter]\n", argv[0]); return 2; }
    FILE *out = fopen(argv[2], "a");
    if (!out) { perror(argv[2]); return 2; }
    int fails = 0, ran = 0;
    for (int i = 0; i < g_count; i++) {
        if (argc > 3 && !strstr(g_tests[i].name, argv[3])) continue;
        g_failed = 0; g_msg[0] = 0;
        double t0 = now_ms();
        g_tests[i].fn();
        while (g_ndefer > 0) { g_ndefer--; g_defer[g_ndefer].fn(g_defer[g_ndefer].arg); }
        double dt = now_ms() - t0;
        ran++; fails += g_failed;
        printf("%s %s (%.0f ms)%s%s\n", g_failed ? "FAIL" : "ok  ", g_tests[i].name, dt, g_failed ? "\n     " : "", g_msg);
        fprintf(out, "{\"suite\":"); json_str(out, argv[1]);
        fprintf(out, ",\"name\":"); json_str(out, g_tests[i].name);
        fprintf(out, ",\"ids\":"); json_str(out, g_tests[i].ids);
        fprintf(out, ",\"status\":\"%s\",\"duration_ms\":%.0f,\"message\":", g_failed ? "failed" : "passed", dt);
        json_str(out, g_msg); fprintf(out, "}\n");
        fflush(out); fflush(stdout); /* keep results if a later test crashes */
    }
    fclose(out);
    printf("%s: %d run, %d failed\n", argv[1], ran, fails);
    return fails ? 1 : 0;
}
