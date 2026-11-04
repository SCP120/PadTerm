/* E2E tests against the private sshd of scripts/test_sshd.sh (127.0.0.1:2222) with the real tmux, claude, codex.
 * No prompt is ever sent to an agent (no Enter after text), so the tests use no model tokens. */
#include "../host/pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_ssh.h"
#include "../../core/pt_conn.h"
#include "../../core/pt_term.h"
#include "../../core/pt_keys.h"
#include "../../core/pt_launch.h"
#include "../../core/pt_backoff.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define SSHD_DIR "build/e2e-sshd"
#define SSHD_PORT 2222

static double now_ms(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0; }
static void sleep_ms(int ms) { usleep((useconds_t)ms * 1000); }

static char *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)n + 1); size_t got = fread(b, 1, (size_t)n, f); b[got] = 0; fclose(f);
    if (len) *len = got;
    return b;
}
static char *expected_fp(void) {
    char *s = slurp(SSHD_DIR "/expected_fingerprint", NULL);
    if (s) s[strcspn(s, "\r\n")] = 0;
    return s;
}
static const char *user(void) { return getenv("USER"); }
static int local_tmux(const char *args) {
    char cmd[512];
    snprintf(cmd, sizeof cmd, "TMUX_TMPDIR=%s/tmux tmux -L padterm %s >/dev/null 2>&1", SSHD_DIR, args);
    return system(cmd);
}
static int count_in_log(const char *needle) {
    char *log = slurp(SSHD_DIR "/sshd.log", NULL); if (!log) return -1;
    int n = 0; for (char *p = log; (p = strstr(p, needle)); p++) n++;
    free(log); return n;
}

/* ---- a session = pt_conn + pt_term, events applied under a mutex ---- */
typedef struct {
    pthread_mutex_t mu;
    pt_term *term;
    pt_conn *conn;
    int connected, closed, close_status, hostkey_calls, accept_hostkey;
    int no_ack;      /* test of backpressure: do not acknowledge DATA */
    size_t received; /* DATA bytes seen */
    char hostkey_seen[128];
} sess;

static void term_out(const char *b, size_t n, void *u) { sess *s = u; if (s->conn) pt_conn_write(s->conn, b, n); }

static int on_event(pt_conn_event ev, int status, const char *data, size_t len, void *u) {
    sess *s = u;
    pthread_mutex_lock(&s->mu);
    int ret = 0;
    switch (ev) {
    case PT_CONN_EV_HOSTKEY:
        s->hostkey_calls++;
        snprintf(s->hostkey_seen, sizeof s->hostkey_seen, "%.*s", (int)len, data);
        ret = s->accept_hostkey;
        break;
    case PT_CONN_EV_CONNECTED: s->connected = 1; break;
    case PT_CONN_EV_DATA:
        pt_term_feed(s->term, data, len);
        s->received += len;
        if (!s->no_ack) pt_conn_ack(s->conn, len);
        break;
    case PT_CONN_EV_CLOSED: s->closed = 1; s->close_status = status; break;
    }
    pthread_mutex_unlock(&s->mu);
    return ret;
}

typedef struct { const char *key_path; const char *pin; int port; int keepalive_s; int cols, rows; int no_ack; int timeout_ms; } sess_opts;

static void sess_stop(sess *s) {
    if (!s) return;
    if (s->conn) { pt_conn_close(s->conn); s->conn = NULL; }
    if (s->term) { pt_term_free(s->term); s->term = NULL; }
}
static void sess_free(void *p) { sess *s = p; sess_stop(s); pthread_mutex_destroy(&s->mu); free(s); }

/* New session on the heap; freed after the test, also when a CHECK fails (the IO thread must never outlive it). */
static sess *sess_start(const char *command, sess_opts o, int *rc) {
    sess *s = calloc(1, sizeof *s);
    pthread_mutex_init(&s->mu, NULL);
    pt_test_defer(sess_free, s);
    s->term = pt_term_new(o.rows ? o.rows : 30, o.cols ? o.cols : 100, term_out, s);
    s->no_ack = o.no_ack;
    size_t klen; char *key = slurp(o.key_path ? o.key_path : SSHD_DIR "/client_ed25519", &klen);
    if (!key) { *rc = PT_ERR_INVALID; return s; }
    char *fp = expected_fp();
    pt_conn_params p = {
        .host = "127.0.0.1", .port = o.port ? o.port : SSHD_PORT, .user = user(),
        .private_key = key, .private_key_len = klen,
        .pinned_fingerprint = o.pin ? o.pin : fp, .command = command,
        .cols = o.cols ? o.cols : 100, .rows = o.rows ? o.rows : 30,
        .connect_timeout_ms = o.timeout_ms ? o.timeout_ms : 5000, .keepalive_s = o.keepalive_s ? o.keepalive_s : 30};
    pthread_mutex_lock(&s->mu); /* conn must be set before the first event can reach term_out */
    *rc = pt_conn_start(&p, on_event, s, &s->conn);
    pthread_mutex_unlock(&s->mu);
    free(key); free(fp);
    return s;
}
/* Wait until some row contains needle. Returns 1 on success. */
static int wait_text(sess *s, const char *needle, int timeout_ms) {
    double end = now_ms() + timeout_ms;
    while (now_ms() < end) {
        pthread_mutex_lock(&s->mu);
        int rows, cols, found = 0; pt_term_size(s->term, &rows, &cols);
        char row[2048];
        for (int r = 0; r < rows && !found; r++)
            if (pt_term_row_text(s->term, r, row, sizeof row) >= 0 && strstr(row, needle)) found = 1;
        int closed = s->closed;
        pthread_mutex_unlock(&s->mu);
        if (found) return 1;
        if (closed) return 0;
        sleep_ms(50);
    }
    return 0;
}
/* Wait until any of the NULL-terminated needles shows. */
static int wait_any(sess *s, const char **needles, int timeout_ms) {
    double end = now_ms() + timeout_ms;
    while (now_ms() < end) {
        for (const char **n = needles; *n; n++) if (wait_text(s, *n, 1)) return 1;
        pthread_mutex_lock(&s->mu); int closed = s->closed; pthread_mutex_unlock(&s->mu);
        if (closed) return 0;
        sleep_ms(100);
    }
    return 0;
}
static int wait_closed(sess *s, int timeout_ms) {
    double end = now_ms() + timeout_ms;
    while (now_ms() < end) { pthread_mutex_lock(&s->mu); int c = s->closed; pthread_mutex_unlock(&s->mu); if (c) return 1; sleep_ms(20); }
    return 0;
}
/* Text of the first row that contains marker, or "" */
static void marker_row(sess *s, const char *marker, char *out, size_t outlen) {
    out[0] = 0;
    pthread_mutex_lock(&s->mu);
    int rows, cols; pt_term_size(s->term, &rows, &cols);
    char row[2048];
    for (int r = 0; r < rows; r++)
        if (pt_term_row_text(s->term, r, row, sizeof row) >= 0 && strstr(row, marker)) { snprintf(out, outlen, "%s", row); break; }
    pthread_mutex_unlock(&s->mu);
}
static void dump_screen(sess *s) {
    pthread_mutex_lock(&s->mu);
    int rows, cols; pt_term_size(s->term, &rows, &cols); char row[2048];
    for (int r = 0; r < rows; r++) if (pt_term_row_text(s->term, r, row, sizeof row) > 0) printf("     | %s\n", row);
    pthread_mutex_unlock(&s->mu);
}
static void type(sess *s, const char *text) {
    pthread_mutex_lock(&s->mu);
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) pt_keys_send_char(s->term, *p, 0);
    pthread_mutex_unlock(&s->mu);
}
static void key(sess *s, pt_key k) { pthread_mutex_lock(&s->mu); pt_keys_send(s->term, k); pthread_mutex_unlock(&s->mu); }
static int status_of(sess *s) { pthread_mutex_lock(&s->mu); int st = s->close_status; pthread_mutex_unlock(&s->mu); return st; }

/* ---- TCP relay that the test can cut, to act as a lost mobile link ---- */
typedef struct { int lfd, port, a, b, stop; long up_bytes; pthread_mutex_t mu; pthread_t th; } relay;
static void *relay_main(void *u) {
    relay *r = u;
    int a = accept(r->lfd, NULL, NULL); if (a < 0) return NULL;
    int b = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = htons(SSHD_PORT)};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    if (connect(b, (struct sockaddr *)&sa, sizeof sa) != 0) { close(a); close(b); return NULL; }
    pthread_mutex_lock(&r->mu); r->a = a; r->b = b; pthread_mutex_unlock(&r->mu);
    char buf[16384];
    for (;;) {
        pthread_mutex_lock(&r->mu); int stop = r->stop; pthread_mutex_unlock(&r->mu);
        if (stop) break;
        fd_set rs; FD_ZERO(&rs); FD_SET(a, &rs); FD_SET(b, &rs);
        struct timeval tv = {0, 50000};
        if (select((a > b ? a : b) + 1, &rs, NULL, NULL, &tv) < 0) break;
        if (FD_ISSET(a, &rs)) { ssize_t n = read(a, buf, sizeof buf); if (n <= 0 || write(b, buf, (size_t)n) != n) break;
            pthread_mutex_lock(&r->mu); r->up_bytes += n; pthread_mutex_unlock(&r->mu); }
        if (FD_ISSET(b, &rs)) { ssize_t n = read(b, buf, sizeof buf); if (n <= 0 || write(a, buf, (size_t)n) != n) break; }
    }
    close(a); close(b);
    return NULL;
}
static int relay_start(relay *r) {
    memset(r, 0, sizeof *r); pthread_mutex_init(&r->mu, NULL);
    r->lfd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = 0};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    if (bind(r->lfd, (struct sockaddr *)&sa, sizeof sa) != 0 || listen(r->lfd, 1) != 0) return -1;
    socklen_t sl = sizeof sa; getsockname(r->lfd, (struct sockaddr *)&sa, &sl); r->port = ntohs(sa.sin_port);
    return pthread_create(&r->th, NULL, relay_main, r);
}
static long relay_up(relay *r) { pthread_mutex_lock(&r->mu); long n = r->up_bytes; pthread_mutex_unlock(&r->mu); return n; }
/* Cut: no FIN/RST from the server side is sent to the client in order; both sockets just go away. */
static void relay_cut(relay *r) {
    pthread_mutex_lock(&r->mu); r->stop = 1;
    if (r->a) shutdown(r->a, SHUT_RDWR);
    if (r->b) shutdown(r->b, SHUT_RDWR);
    pthread_mutex_unlock(&r->mu);
    pthread_join(r->th, NULL); close(r->lfd);
}

/* ---------------- tests ---------------- */

PT_TEST(e2e_00_clean_tmux, "NFR-4") {
    local_tmux("kill-server");
    CHECK(local_tmux("has-session") != 0);
}

PT_TEST(e2e_connect_key_auth_fingerprint, "AC-CONNECT-1 BR-CONNECT-1") {
    char *fp = expected_fp(); CHECK(fp != NULL); CHECK(strncmp(fp, "SHA256:", 7) == 0);
    pt_ssh *s = NULL;
    CHECK_INT(pt_ssh_connect("127.0.0.1", SSHD_PORT, 5000, -1, &s), PT_OK);
    char got[128];
    CHECK_INT(pt_ssh_host_fingerprint(s, got, sizeof got), PT_OK);
    CHECK_STR(got, fp);
    CHECK_STR(pt_ssh_host_key_type(s), "ssh-ed25519");
    size_t kl; char *k = slurp(SSHD_DIR "/client_ed25519", &kl);
    CHECK_INT(pt_ssh_auth_key(s, user(), k, kl), PT_OK);
    pt_ssh_close(s); free(k); free(fp);
}

PT_TEST(e2e_pty_term_and_size, "AC-CONNECT-2") {
    pt_ssh *s = NULL;
    CHECK_INT(pt_ssh_connect("127.0.0.1", SSHD_PORT, 5000, -1, &s), PT_OK);
    size_t kl; char *k = slurp(SSHD_DIR "/client_ed25519", &kl);
    CHECK_INT(pt_ssh_auth_key(s, user(), k, kl), PT_OK);
    CHECK_INT(pt_ssh_open_shell(s, "printf 'T=%s S=' \"$TERM\"; stty size", 100, 30), PT_OK);
    char out[512]; size_t n = 0; double end = now_ms() + 5000;
    while (now_ms() < end && n < sizeof out - 1) {
        int r = pt_ssh_read(s, out + n, sizeof out - 1 - n);
        if (r > 0) n += (size_t)r; else if (r < 0) break; else sleep_ms(10);
    }
    out[n] = 0;
    CHECK(strstr(out, "T=xterm-256color S=30 100") != NULL);
    pt_ssh_close(s); free(k);
}

PT_TEST(e2e_hostkey_mismatch_refused_before_auth, "BR-CONNECT-2") {
    int accepted_before = count_in_log("Accepted publickey");
    int rc_s; sess *s = sess_start("true", (sess_opts){.pin = "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    CHECK(wait_closed(s, 8000));
    CHECK_INT(status_of(s), PT_ERR_HOSTKEY_MISMATCH);
    CHECK_INT(s->connected, 0);
    sess_stop(s);
    sleep_ms(300);
    CHECK_INT(count_in_log("Accepted publickey"), accepted_before);
}

PT_TEST(e2e_hostkey_first_use_asks, "BR-CONNECT-1") {
    char *fp = expected_fp();
    int rc_s; sess *s = sess_start("true", (sess_opts){.pin = ""}, &rc_s);
    CHECK_INT(rc_s, PT_OK); /* no pin: ask */
    CHECK(wait_closed(s, 8000));
    CHECK_INT(s->hostkey_calls, 1);
    CHECK_STR(s->hostkey_seen, fp);
    CHECK_INT(status_of(s), PT_ERR_HOSTKEY_MISMATCH); /* accept_hostkey == 0: refused */
    sess_stop(s); free(fp);
}

PT_TEST(e2e_wrong_key_auth_failed, "EF-CONNECT-1") {
    pt_ssh *s = NULL;
    CHECK_INT(pt_ssh_connect("127.0.0.1", SSHD_PORT, 5000, -1, &s), PT_OK);
    size_t kl; char *k = slurp(SSHD_DIR "/other_ed25519", &kl);
    CHECK_INT(pt_ssh_auth_key(s, user(), k, kl), PT_ERR_AUTH);
    pt_ssh_close(s); free(k);
}

PT_TEST(e2e_connect_timeout, "EF-CONNECT-2") {
    /* The kernel accepts the TCP connection (listen backlog) but nobody ever sends an SSH banner. */
    int l = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = 0};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    CHECK(bind(l, (struct sockaddr *)&sa, sizeof sa) == 0 && listen(l, 4) == 0);
    socklen_t sl = sizeof sa; getsockname(l, (struct sockaddr *)&sa, &sl);
    pt_ssh *s = NULL;
    double t0 = now_ms();
    int rc = pt_ssh_connect("127.0.0.1", ntohs(sa.sin_port), 1500, -1, &s);
    double dt = now_ms() - t0;
    close(l);
    CHECK_INT(rc, PT_ERR_TIMEOUT);
    CHECK(s == NULL);
    CHECK(dt >= 1400 && dt <= 3000);
}

PT_TEST(e2e_invalid_key, "EF-CONNECT-3") {
    pt_ssh *s = NULL;
    CHECK_INT(pt_ssh_connect("127.0.0.1", SSHD_PORT, 5000, -1, &s), PT_OK);
    const char *junk = "not a key";
    CHECK_INT(pt_ssh_auth_key(s, user(), junk, strlen(junk)), PT_ERR_KEY_INVALID);
    const char *bad = "-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\n";
    CHECK_INT(pt_ssh_auth_key(s, user(), bad, strlen(bad)), PT_ERR_KEY_INVALID);
    size_t kl; char *good = slurp(SSHD_DIR "/client_ed25519", &kl);
    CHECK_INT(pt_ssh_key_valid(good, kl), 1);
    CHECK_INT(pt_ssh_key_valid(junk, strlen(junk)), 0);
    CHECK_INT(pt_ssh_key_valid(bad, strlen(bad)), 0);
    free(good);
    pt_ssh_close(s);
}

PT_TEST(e2e_shell_launch_attach_resize, "AC-LAUNCH-1 AC-LAUNCH-2 AC-LAUNCH-3 AC-SCREEN-7 BR-RECONNECT-1") {
    char cmd[2048]; CHECK(pt_launch_command(PT_AGENT_SHELL, "~", cmd, sizeof cmd) > 0);
    int rc_s; sess *s = sess_start(cmd, (sess_opts){0}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    CHECK(wait_text(s, "%", 15000) || wait_text(s, "$", 1000)); /* a shell prompt */
    type(s, "export PTMARK=7; echo PT-$((40+2))\r");
    if (!wait_text(s, "PT-42", 8000)) { dump_screen(s); CHECK(!"no PT-42"); }
    CHECK_INT(local_tmux("has-session -t =shell"), 0);
    /* AC-SCREEN-7: a resize reaches the server */
    pthread_mutex_lock(&s->mu); pt_term_resize(s->term, 20, 90); pthread_mutex_unlock(&s->mu);
    CHECK_INT(pt_conn_resize(s->conn, 90, 20), PT_OK);
    sleep_ms(300);
    type(s, "stty size\r");
    if (!wait_text(s, "20 90", 5000)) { dump_screen(s); CHECK(!"no 20 90"); }
    pt_conn_close(s->conn); s->conn = NULL;
    CHECK(s->closed); CHECK_INT(status_of(s), PT_OK);
    CHECK_INT(pt_should_reconnect(status_of(s)), 0);
    sess_stop(s);
    /* attach again: the same shell, not a new one */
    int rc_s2; sess *s2 = sess_start(cmd, (sess_opts){0}, &rc_s2);
    CHECK_INT(rc_s2, PT_OK);
    sleep_ms(1500);
    type(s2, "echo M$PTMARK-X\r");
    if (!wait_text(s2, "M7-X", 8000)) { dump_screen(s2); CHECK(!"no M7-X"); }
    sess_stop(s2);
    local_tmux("kill-session -t =shell");
}

PT_TEST(e2e_keepalive_and_reconnect_after_lost_link, "AC-RECONNECT-1 AC-RECONNECT-2") {
    char cmd[2048]; CHECK(pt_launch_command(PT_AGENT_SHELL, "~", cmd, sizeof cmd) > 0);
    relay r; CHECK(relay_start(&r) == 0);
    int rc_s; sess *s = sess_start(cmd, (sess_opts){.port = r.port, .keepalive_s = 1}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    CHECK(wait_text(s, "%", 15000) || wait_text(s, "$", 1000));
    type(s, "export PTR=9; echo READY-$((1+1))\r");
    CHECK(wait_text(s, "READY-2", 8000));
    sleep_ms(500);
    long up0 = relay_up(&r);
    sleep_ms(2500); /* idle: only keep-alive packets go up */
    CHECK(relay_up(&r) > up0);
    relay_cut(&r);
    CHECK(wait_closed(s, 8000));
    int st = status_of(s);
    CHECK(st != PT_OK);
    CHECK_INT(pt_should_reconnect(st), 1);
    sess_stop(s);
    pt_backoff bo; pt_backoff_reset(&bo); sleep_ms(pt_backoff_next(&bo));
    int rc_s2; sess *s2 = sess_start(cmd, (sess_opts){0}, &rc_s2);
    CHECK_INT(rc_s2, PT_OK);
    sleep_ms(1500);
    type(s2, "echo R$PTR-Y\r");
    if (!wait_text(s2, "R9-Y", 8000)) { dump_screen(s2); CHECK(!"no R9-Y"); }
    sess_stop(s2);
    local_tmux("kill-session -t =shell");
}

static size_t received(sess *s) { pthread_mutex_lock(&s->mu); size_t n = s->received; pthread_mutex_unlock(&s->mu); return n; }

PT_TEST(e2e_close_during_connect_is_fast, "BR-RECONNECT-1 AC-RECONNECT-2") {
    /* A server that accepts TCP but never sends a banner; the user leaves the screen mid-connect. */
    int l = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = {.sin_family = AF_INET, .sin_port = 0};
    inet_pton(AF_INET, "127.0.0.1", &sa.sin_addr);
    CHECK(bind(l, (struct sockaddr *)&sa, sizeof sa) == 0 && listen(l, 4) == 0);
    socklen_t sl = sizeof sa; getsockname(l, (struct sockaddr *)&sa, &sl);
    int rc; sess *s = sess_start("true", (sess_opts){.port = ntohs(sa.sin_port), .timeout_ms = 10000}, &rc);
    CHECK_INT(rc, PT_OK);
    sleep_ms(300);
    double t0 = now_ms();
    pt_conn_close(s->conn); s->conn = NULL;
    double dt = now_ms() - t0;
    close(l);
    CHECK(dt < 500);                    /* was: until the 10 s handshake deadline */
    CHECK(s->closed); CHECK_INT(status_of(s), PT_OK);
}

PT_TEST(e2e_backpressure_until_ack, "AC-SCREEN-2 NFR-4") {
    /* 6 MB of output; the client does not acknowledge: reading must stop near one SSH window (2 MiB). */
    int rc; sess *s = sess_start("head -c 6000000 /dev/zero | tr '\\0' 'x'", (sess_opts){.no_ack = 1}, &rc);
    CHECK_INT(rc, PT_OK);
    sleep_ms(2000);
    size_t n1 = received(s);
    sleep_ms(500);
    size_t n2 = received(s);
    printf("     unacknowledged: %zu bytes, after 0.5 s more: %zu\n", n1, n2);
    CHECK(n1 > 2 * 1024 * 1024);                     /* it read up to the limit */
    CHECK(n2 <= 2 * 1024 * 1024 + 32768);            /* then stopped: limit + at most one read chunk */
    CHECK_INT(n2, n1);
    pthread_mutex_lock(&s->mu); s->no_ack = 0; pthread_mutex_unlock(&s->mu);
    pt_conn_ack(s->conn, n2);                        /* release: the rest arrives */
    double end = now_ms() + 10000;
    while (received(s) < 6000000 && now_ms() < end) sleep_ms(50);
    CHECK_INT(received(s) >= 6000000, 1);
}

/* A row's first cell whose text starts with needle, or -1. */
static int find_col(pt_term *t, int row, char ch) {
    int rows, cols; pt_term_size(t, &rows, &cols);
    for (int c = 0; c < cols; c++) { pt_cell x; pt_term_cell(t, row, c, &x); if (x.chars[0] == (uint32_t)ch) return c; }
    return -1;
}

/* Seen on the iPad: through tmux, italic came out as reverse and 24-bit colour as the nearest 256 colour. */
PT_TEST(e2e_italic_and_rgb_through_tmux, "AC-SCREEN-1 BR-LAUNCH-1") {
    char cmd[2048]; CHECK(pt_launch_command(PT_AGENT_SHELL, "~", cmd, sizeof cmd) > 0);
    local_tmux("kill-server");
    int rc_s; sess *s = sess_start(cmd, (sess_opts){0}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    CHECK(wait_text(s, "%", 15000) || wait_text(s, "$", 1000));
    type(s, "clear; printf '\\033[3mQ\\033[0m \\033[38;2;1;2;3mZ\\033[0m MARK-%d\\n' $((1+1))\r");
    if (!wait_text(s, "MARK-2", 8000)) { dump_screen(s); CHECK(!"no MARK-2"); }
    sleep_ms(300);
    pthread_mutex_lock(&s->mu);
    int rows, cols, row = -1; pt_term_size(s->term, &rows, &cols);
    char text[2048];
    for (int r = 0; r < rows && row < 0; r++)
        if (pt_term_row_text(s->term, r, text, sizeof text) >= 0 && strncmp(text, "Q Z MARK-2", 10) == 0) row = r;
    pt_cell q = {0}, z = {0};
    if (row >= 0) { pt_term_cell(s->term, row, find_col(s->term, row, 'Q'), &q); pt_term_cell(s->term, row, find_col(s->term, row, 'Z'), &z); }
    pthread_mutex_unlock(&s->mu);
    CHECK(row >= 0);
    CHECK(q.italic); CHECK(!q.reverse);
    CHECK_INT(z.fg[0], 1); CHECK_INT(z.fg[1], 2); CHECK_INT(z.fg[2], 3);
    sess_stop(s);
    local_tmux("kill-server");
}

static char *make_workdir(const char *tag) {
    static char path[512];
    snprintf(path, sizeof path, "%s/build/e2e-work/%s-XXXXXX", getenv("PWD"), tag);
    system("mkdir -p build/e2e-work");
    return mkdtemp(path);
}

/* Move the selection marker with ↓ and check that the marked row changes; if the screen has no menu,
 * type text without Enter and check it shows. Either way the key path through the agent TUI works. */
static int menu_or_type(sess *s, const char *marker, const char *tag) {
    char before[2048], after[2048];
    marker_row(s, marker, before, sizeof before);
    if (before[0]) {
        key(s, PT_KEY_DOWN);
        double end = now_ms() + 5000;
        while (now_ms() < end) {
            marker_row(s, marker, after, sizeof after);
            if (after[0] && strcmp(after, before) != 0) { printf("     %s: menu marker moved: [%s] -> [%s]\n", tag, before, after); return 1; }
            sleep_ms(50);
        }
    }
    type(s, "zqx");
    if (wait_text(s, "zqx", 5000)) { printf("     %s: typed text shows at the prompt\n", tag); return 1; }
    dump_screen(s);
    return 0;
}

PT_TEST(e2e_claude_starts_and_takes_keys, "AC-LAUNCH-2 AC-INPUT-2 AC-SCREEN-2 NFR-4") {
    char *dir = make_workdir("wa"); CHECK(dir != NULL);
    char cmd[2048]; CHECK(pt_launch_command(PT_AGENT_CLAUDE, dir, cmd, sizeof cmd) > 0);
    int rc_s; sess *s = sess_start(cmd, (sess_opts){.cols = 100, .rows = 30}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    /* Only Claude Code's own screen has these (the work dir name has no "claude" in it). */
    int up = wait_any(s, (const char *[]){"trust this folder", "Claude Code", "Welcome to Claude", NULL}, 40000);
    if (!up) { dump_screen(s); CHECK(!"claude screen did not show"); }
    CHECK(menu_or_type(s, "\xE2\x9D\xAF", "claude")); /* ❯ */
    sess_stop(s);
    local_tmux("kill-session -t =claude");
}

PT_TEST(e2e_codex_starts_and_takes_keys, "AC-LAUNCH-2 AC-INPUT-2 AC-SCREEN-2 NFR-4") {
    char *dir = make_workdir("wb"); CHECK(dir != NULL);
    char cmd[2048]; CHECK(pt_launch_command(PT_AGENT_CODEX, dir, cmd, sizeof cmd) > 0);
    int rc_s; sess *s = sess_start(cmd, (sess_opts){.cols = 100, .rows = 30}, &rc_s);
    CHECK_INT(rc_s, PT_OK);
    /* Only Codex's own screen has these (the work dir name has no "codex" in it). */
    int up = wait_any(s, (const char *[]){"OpenAI Codex", "Update available", "trust the", "Codex", NULL}, 40000);
    if (!up) { dump_screen(s); CHECK(!"codex screen did not show"); }
    sleep_ms(1500); /* let the first frame finish */
    CHECK(menu_or_type(s, "\xE2\x80\xBA", "codex")); /* › */
    sess_stop(s);
    local_tmux("kill-session -t =codex");
}

PT_TEST(e2e_zz_clean_tmux, "NFR-4") {
    local_tmux("kill-server");
    CHECK(local_tmux("has-session") != 0);
}

PT_TEST(e2e_exec_capture_with_stderr_and_cap, "EF-SESSION-1 AC-SESSION-2") {
    pt_ssh *s = NULL;
    size_t kl; char *k = slurp(SSHD_DIR "/client_ed25519", &kl);
    CHECK_INT(pt_ssh_connect("127.0.0.1", SSHD_PORT, 5000, -1, &s), PT_OK);
    CHECK_INT(pt_ssh_auth_key(s, user(), k, kl), PT_OK);
    char out[64];
    size_t len = 0;
    /* A startup file that prints to stderr: the read must end at once, with only stdout. */
    CHECK_INT(pt_ssh_exec_capture(s, "echo noise >&2; echo noise >&2; echo out", out, sizeof out, &len), PT_OK);
    CHECK_MEM(out, len, "out\n");
    /* The connection serves the next command. */
    CHECK_INT(pt_ssh_exec_capture(s, "printf second", out, sizeof out, &len), PT_OK);
    CHECK_MEM(out, len, "second");
    CHECK_INT(pt_ssh_exec_capture(s, "head -c 500 /dev/zero", out, sizeof out, &len), PT_ERR_NOSPACE);
    pt_ssh_close(s);
    free(k);
}
