#include "pt_conn.h"
#include "pt_error.h"
#include "pt_ssh.h"
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/time.h>
#include <unistd.h>

/* A link is dead after this many keep-alive intervals with no inbound bytes: the OpenSSH default of
 * ServerAliveCountMax (ssh_config(5)). */
enum { DEAD_AFTER_KEEPALIVES = 3 };
/* One channel read: LIBSSH2_CHANNEL_PACKET_DEFAULT (libssh2.h), the largest data packet libssh2 asks for. */
enum { READ_CHUNK = 32768 };
/* Most unacknowledged DATA bytes: LIBSSH2_CHANNEL_WINDOW_DEFAULT (libssh2.h, 2 MiB), one SSH window. */
enum { MAX_UNACKED = 2 * 1024 * 1024 };
/* A loop pass that comes this many keep-alive intervals after the last one means the process was
 * suspended (iOS background); the silence was ours, not the server's. */
enum { SUSPEND_GAP_KEEPALIVES = 2 };

struct pt_conn {
    pthread_t thread;
    pthread_mutex_t mu;
    int wake[2];   /* a byte = "look at the queue" */
    int cancel[2]; /* a byte = "close now"; separate, so key presses during setup do not cancel it */
    pt_conn_fn fn;
    void *user;
    /* copied params */
    char *host, *user_name, *key, *pin, *command;
    size_t key_len;
    int port, cols, rows, timeout_ms, keepalive_s;
    /* guarded by mu */
    char *out;
    size_t out_len, out_cap;
    int resize_cols, resize_rows; /* 0 = none pending */
    int close_req;
    size_t unacked;
};

static char *dup_str(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *d = malloc(n);
    if (d) memcpy(d, s, n);
    return d;
}

static double now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

static void wake(pt_conn *c) {
    char b = 1;
    ssize_t r = write(c->wake[1], &b, 1);
    (void)r; /* a full pipe already means "wake up" */
}

static void drain_wake(pt_conn *c) {
    char b[64];
    while (read(c->wake[0], b, sizeof b) > 0) {}
}

/* Write what the socket takes now. Returns PT_OK or PT_ERR_IO. Caller holds mu. */
static int flush_out(pt_conn *c, pt_ssh *s) {
    size_t done = 0;
    while (done < c->out_len) {
        int n = pt_ssh_write(s, c->out + done, c->out_len - done);
        if (n < 0) return PT_ERR_IO;
        if (n == 0) break;
        done += (size_t)n;
    }
    if (done) {
        memmove(c->out, c->out + done, c->out_len - done);
        c->out_len -= done;
    }
    return PT_OK;
}

static int session(pt_conn *c, pt_ssh **sp) {
    int st = pt_ssh_connect(c->host, c->port, c->timeout_ms, c->cancel[0], sp);
    if (st != PT_OK) return st;
    pt_ssh *s = *sp;
    char fp[128];
    st = pt_ssh_host_fingerprint(s, fp, sizeof fp);
    if (st != PT_OK) return st;
    if (c->pin && *c->pin) {
        if (strcmp(fp, c->pin) != 0) return PT_ERR_HOSTKEY_MISMATCH;
    } else if (!c->fn(PT_CONN_EV_HOSTKEY, PT_OK, fp, strlen(fp), c->user)) {
        return PT_ERR_HOSTKEY_MISMATCH;
    }
    st = pt_ssh_auth_key(s, c->user_name, c->key, c->key_len);
    if (st != PT_OK) return st;
    st = pt_ssh_open_shell(s, c->command, c->cols, c->rows);
    if (st != PT_OK) return st;
    if (c->keepalive_s > 0) pt_ssh_keepalive_config(s, c->keepalive_s);
    return PT_OK;
}

static int pump(pt_conn *c, pt_ssh *s) {
    char *buf = malloc(READ_CHUNK);
    if (!buf) return PT_ERR_NOMEM;
    double last_rx = now_ms(), last_pass = last_rx;
    int status = PT_OK;
    for (;;) {
        double now = now_ms();
        if (c->keepalive_s > 0 && now - last_pass > (double)SUSPEND_GAP_KEEPALIVES * c->keepalive_s * 1000)
            last_rx = now; /* we were suspended: give the link a fresh dead-link period */
        last_pass = now;
        pthread_mutex_lock(&c->mu);
        int close_req = c->close_req;
        int rc = c->resize_cols, rr = c->resize_rows;
        c->resize_cols = c->resize_rows = 0;
        int paused = c->unacked > MAX_UNACKED;
        pthread_mutex_unlock(&c->mu);
        if (close_req) break;
        if (rc) {
            int rs = pt_ssh_resize(s, rc, rr);
            if (rs != PT_OK) { status = rs == PT_ERR_CANCELLED ? PT_OK : PT_ERR_IO; break; } /* cancel = user close */
        }

        pthread_mutex_lock(&c->mu);
        int w = flush_out(c, s);
        pthread_mutex_unlock(&c->mu);
        if (w != PT_OK) { status = w; break; }

        int n = 0;
        while (!paused && (n = pt_ssh_read(s, buf, READ_CHUNK)) > 0) {
            pthread_mutex_lock(&c->mu);
            c->unacked += (size_t)n;
            paused = c->unacked > MAX_UNACKED;
            pthread_mutex_unlock(&c->mu);
            c->fn(PT_CONN_EV_DATA, PT_OK, buf, (size_t)n, c->user);
        }
        if (n < 0) { status = n; break; }
        if (paused) last_rx = now_ms(); /* we do not read the socket now: its silence says nothing */

        int next_s = 0;
        if (c->keepalive_s > 0) {
            if (pt_ssh_keepalive_tick(s, &next_s) != PT_OK) { status = PT_ERR_IO; break; }
            if (now_ms() - last_rx > (double)DEAD_AFTER_KEEPALIVES * c->keepalive_s * 1000) { status = PT_ERR_TIMEOUT; break; }
        }

        int fd = pt_ssh_socket(s);
        fd_set rs, ws;
        FD_ZERO(&rs); FD_ZERO(&ws);
        if (!paused) FD_SET(fd, &rs);
        FD_SET(c->wake[0], &rs);
        /* Only what libssh2 waits for: with a full channel window it waits for inbound data (a window
         * adjust), and a socket in the write set would make select return at once, in a busy loop. */
        if (pt_ssh_block_directions(s) & 2) FD_SET(fd, &ws);
        struct timeval tv = {next_s > 0 ? next_s : c->keepalive_s, 0};
        int maxfd = fd > c->wake[0] ? fd : c->wake[0];
        int r = select(maxfd + 1, &rs, &ws, NULL, c->keepalive_s > 0 ? &tv : NULL);
        if (r < 0 && errno != EINTR) { status = PT_ERR_IO; break; }
        if (r > 0 && FD_ISSET(fd, &rs)) last_rx = now_ms();
        if (r > 0 && FD_ISSET(c->wake[0], &rs)) drain_wake(c);
    }
    free(buf);
    return status;
}

static void *io_main(void *arg) {
    pt_conn *c = arg;
    pt_ssh *s = NULL;
    int status = session(c, &s);
    if (status == PT_OK) {
        c->fn(PT_CONN_EV_CONNECTED, PT_OK, NULL, 0, c->user);
        status = pump(c, s);
    } else if (status == PT_ERR_CANCELLED) {
        status = PT_OK; /* the caller closed during setup: a user close */
    }
    pt_ssh_close(s);
    c->fn(PT_CONN_EV_CLOSED, status, NULL, 0, c->user);
    return NULL;
}

static void free_conn(pt_conn *c) {
    for (int i = 0; i < 2; i++) {
        if (c->wake[i] >= 0) close(c->wake[i]);
        if (c->cancel[i] >= 0) close(c->cancel[i]);
    }
    if (c->key) { memset(c->key, 0, c->key_len); free(c->key); } /* BR-CONNECT-3: no key copy left */
    free(c->host); free(c->user_name); free(c->pin); free(c->command); free(c->out);
    pthread_mutex_destroy(&c->mu);
    free(c);
}

int pt_conn_start(const pt_conn_params *p, pt_conn_fn fn, void *user, pt_conn **out) {
    *out = NULL;
    if (!p || !fn || !p->host || !p->user || !p->private_key || !p->command || p->cols <= 0 || p->rows <= 0 ||
        p->connect_timeout_ms <= 0 || p->keepalive_s < 0)
        return PT_ERR_INVALID;
    pt_conn *c = calloc(1, sizeof *c);
    if (!c) return PT_ERR_NOMEM;
    c->wake[0] = c->wake[1] = c->cancel[0] = c->cancel[1] = -1;
    pthread_mutex_init(&c->mu, NULL);
    c->fn = fn;
    c->user = user;
    c->host = dup_str(p->host);
    c->user_name = dup_str(p->user);
    c->pin = dup_str(p->pinned_fingerprint ? p->pinned_fingerprint : "");
    c->command = dup_str(p->command);
    c->key = malloc(p->private_key_len + 1);
    if (!c->host || !c->user_name || !c->pin || !c->command || !c->key || pipe(c->wake) != 0 || pipe(c->cancel) != 0) {
        free_conn(c);
        return PT_ERR_NOMEM;
    }
    memcpy(c->key, p->private_key, p->private_key_len);
    c->key[p->private_key_len] = 0;
    c->key_len = p->private_key_len;
    c->port = p->port;
    c->cols = p->cols;
    c->rows = p->rows;
    c->timeout_ms = p->connect_timeout_ms;
    c->keepalive_s = p->keepalive_s;
    fcntl(c->wake[0], F_SETFL, O_NONBLOCK);
    fcntl(c->wake[1], F_SETFL, O_NONBLOCK);
    if (pthread_create(&c->thread, NULL, io_main, c) != 0) { free_conn(c); return PT_ERR_NOMEM; }
    *out = c;
    return PT_OK;
}

int pt_conn_write(pt_conn *c, const char *bytes, size_t len) {
    if (!c || !bytes) return PT_ERR_INVALID;
    if (!len) return PT_OK;
    pthread_mutex_lock(&c->mu);
    if (c->out_len + len > c->out_cap) {
        size_t cap = c->out_cap ? c->out_cap : 1024;
        while (cap < c->out_len + len) cap *= 2;
        char *n = realloc(c->out, cap);
        if (!n) { pthread_mutex_unlock(&c->mu); return PT_ERR_NOMEM; }
        c->out = n;
        c->out_cap = cap;
    }
    memcpy(c->out + c->out_len, bytes, len);
    c->out_len += len;
    pthread_mutex_unlock(&c->mu);
    wake(c);
    return PT_OK;
}

int pt_conn_ack(pt_conn *c, size_t len) {
    if (!c) return PT_ERR_INVALID;
    pthread_mutex_lock(&c->mu);
    int was_paused = c->unacked > MAX_UNACKED;
    c->unacked = len > c->unacked ? 0 : c->unacked - len;
    int resume = was_paused && c->unacked <= MAX_UNACKED;
    pthread_mutex_unlock(&c->mu);
    if (resume) wake(c);
    return PT_OK;
}

int pt_conn_resize(pt_conn *c, int cols, int rows) {
    if (!c || cols <= 0 || rows <= 0) return PT_ERR_INVALID;
    pthread_mutex_lock(&c->mu);
    c->resize_cols = cols;
    c->resize_rows = rows;
    pthread_mutex_unlock(&c->mu);
    wake(c);
    return PT_OK;
}

void pt_conn_close(pt_conn *c) {
    if (!c) return;
    pthread_mutex_lock(&c->mu);
    c->close_req = 1;
    pthread_mutex_unlock(&c->mu);
    char b = 1;
    ssize_t r = write(c->cancel[1], &b, 1); /* stops a setup step that waits in select */
    (void)r;
    wake(c);
    pthread_join(c->thread, NULL);
    free_conn(c);
}
