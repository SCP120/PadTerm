/* Minimal test harness: tests register with PT_TEST(name, "AC-X-1 BR-Y-2"), results go to a JSON-lines file
 * (one object per test) that scripts/run_tests.sh merges into tests/artifacts/test_results.json. */
#ifndef PT_TEST_H
#define PT_TEST_H
#include <stdio.h>
#include <string.h>

typedef void (*pt_test_fn)(void);
void pt_test_register(const char *name, const char *ids, pt_test_fn fn);
void pt_test_fail(const char *file, int line, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
int pt_test_failed_now(void);
/* Run fn(arg) after the current test ends, also when a CHECK failed (reverse order). */
void pt_test_defer(void (*fn)(void *), void *arg);

#define PT_TEST(fn, ids)                                                         \
    static void fn(void);                                                        \
    __attribute__((constructor)) static void fn##_reg(void) { pt_test_register(#fn, ids, fn); } \
    static void fn(void)

#define CHECK(cond) do { if (!(cond)) { pt_test_fail(__FILE__, __LINE__, "CHECK(%s)", #cond); return; } } while (0)
#define CHECK_INT(a, b) do { long long _a = (long long)(a), _b = (long long)(b); \
    if (_a != _b) { pt_test_fail(__FILE__, __LINE__, "%s == %lld, expected %lld", #a, _a, _b); return; } } while (0)
#define CHECK_STR(a, b) do { const char *_a = (a), *_b = (b); \
    if (!_a || strcmp(_a, _b) != 0) { pt_test_fail(__FILE__, __LINE__, "%s == \"%s\", expected \"%s\"", #a, _a ? _a : "(null)", _b); return; } } while (0)
#define CHECK_MEM(a, alen, b) do { size_t _l = (size_t)(alen); const char *_b = (b); \
    if (_l != strlen(_b) || memcmp((a), _b, _l) != 0) { pt_test_fail(__FILE__, __LINE__, "bytes of %s differ (len %zu, expected %zu)", #a, _l, strlen(_b)); return; } } while (0)

#endif
