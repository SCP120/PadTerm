#include "pt_ssh.h"
#include "pt_error.h"
#include <errno.h>
#include <fcntl.h>
#include <libssh2.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

struct pt_ssh {
    int fd;
    LIBSSH2_SESSION *session;
    LIBSSH2_CHANNEL *channel;
    int timeout_ms; /* bound for each blocking-style step (handshake, auth, channel setup) */
    int cancel_fd;  /* -1 or readable = stop the current setup step */
};

/* Preferred algorithms. Each list also has the classic fallbacks of OpenSSH >= 6.5 servers.
 * chacha20 first: the A5 has no AES instructions and OpenSSL is built with no-asm for armv7,
 * where ChaCha20 in C is faster than AES in C. */
static const char KEX[] = "curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,"
                          "diffie-hellman-group14-sha256,diffie-hellman-group16-sha512";
static const char HOSTKEYS[] = "ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256";
static const char CIPHERS[] = "chacha20-poly1305@openssh.com,aes128-gcm@openssh.com,aes256-gcm@openssh.com,"
                              "aes128-ctr,aes256-ctr";

int pt_ssh_global_init(void) { return libssh2_init(0) == 0 ? PT_OK : PT_ERR_NOMEM; }

static double now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

/* select() on fd (read and/or write) and the cancel fd until ready or the deadline. */
static int wait_fd(int fd, int want_read, int want_write, int cancel_fd, double deadline) {
    for (;;) {
        double left = deadline - now_ms();
        if (left <= 0) return PT_ERR_TIMEOUT;
        fd_set rs, ws;
        FD_ZERO(&rs); FD_ZERO(&ws);
        if (want_read) FD_SET(fd, &rs);
        if (want_write) FD_SET(fd, &ws);
        if (cancel_fd >= 0) FD_SET(cancel_fd, &rs);
        struct timeval tv = {(long)(left / 1000), (int)((long)left % 1000) * 1000};
        int r = select((fd > cancel_fd ? fd : cancel_fd) + 1, &rs, &ws, NULL, &tv);
        /* On error select leaves the sets as they were: test them only after a real result. */
        if (r < 0) {
            if (errno == EINTR) continue; /* a signal is not a cancel */
            return PT_ERR_IO;
        }
        if (cancel_fd >= 0 && FD_ISSET(cancel_fd, &rs)) return PT_ERR_CANCELLED;
        return r == 0 ? PT_ERR_TIMEOUT : PT_OK;
    }
}

/* Wait until the socket is ready in the direction libssh2 needs, the deadline, or a cancel. */
static int wait_socket(pt_ssh *s, double deadline) {
    int dir = libssh2_session_block_directions(s->session);
    return wait_fd(s->fd, dir & LIBSSH2_SESSION_BLOCK_INBOUND || dir == 0, dir & LIBSSH2_SESSION_BLOCK_OUTBOUND,
                   s->cancel_fd, deadline);
}

/* Repeat a libssh2 call while it says EAGAIN; on a wait failure rc = that pt_status. */
#define RETRY(s, deadline, rc, call)                                         \
    do {                                                                     \
        while (((rc) = (call)) == LIBSSH2_ERROR_EAGAIN) {                    \
            int _w = wait_socket((s), (deadline));                           \
            if (_w != PT_OK) { (rc) = RETRY_BASE + _w; break; }              \
        }                                                                    \
    } while (0)
/* Wait failures are reported as RETRY_BASE + pt_status: far below every libssh2 error code (-1 .. -50). */
#define RETRY_BASE -1000
#define RETRY_STATUS(rc) ((rc) <= RETRY_BASE + 0 && (rc) > RETRY_BASE - 100 ? (rc) - RETRY_BASE : 0)

static int tcp_connect(const char *host, int port, double deadline, int cancel_fd, int *out_fd) {
    char portstr[16];
    snprintf(portstr, sizeof portstr, "%d", port);
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) return PT_ERR_RESOLVE;
    int status = PT_ERR_CONNECT;
    for (struct addrinfo *a = res; a; a = a->ai_next) {
        int fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one); /* key presses go out at once */
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
        int r = connect(fd, a->ai_addr, a->ai_addrlen);
        if (r != 0 && errno == EINPROGRESS) {
            int w = wait_fd(fd, 0, 1, cancel_fd, deadline);
            if (w == PT_ERR_TIMEOUT || w == PT_ERR_CANCELLED) { close(fd); status = w; break; }
            int err = 0; socklen_t el = sizeof err;
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el);
            r = (w == PT_OK && err == 0) ? 0 : -1;
        }
        if (r == 0) { *out_fd = fd; status = PT_OK; break; }
        close(fd);
    }
    freeaddrinfo(res);
    return status;
}

int pt_ssh_connect(const char *host, int port, int timeout_ms, int cancel_fd, pt_ssh **out) {
    *out = NULL;
    if (!host || !*host || port <= 0 || port > 65535 || timeout_ms <= 0) return PT_ERR_INVALID;
    double deadline = now_ms() + timeout_ms;
    pt_ssh *s = calloc(1, sizeof *s);
    if (!s) return PT_ERR_NOMEM;
    s->fd = -1;
    s->timeout_ms = timeout_ms;
    s->cancel_fd = cancel_fd;
    int st = tcp_connect(host, port, deadline, cancel_fd, &s->fd);
    if (st != PT_OK) { free(s); return st; }
    s->session = libssh2_session_init();
    if (!s->session) { pt_ssh_close(s); return PT_ERR_NOMEM; }
    libssh2_session_method_pref(s->session, LIBSSH2_METHOD_KEX, KEX);
    libssh2_session_method_pref(s->session, LIBSSH2_METHOD_HOSTKEY, HOSTKEYS);
    libssh2_session_method_pref(s->session, LIBSSH2_METHOD_CRYPT_CS, CIPHERS);
    libssh2_session_method_pref(s->session, LIBSSH2_METHOD_CRYPT_SC, CIPHERS);
    libssh2_session_set_blocking(s->session, 0);
    int rc;
    RETRY(s, deadline, rc, libssh2_session_handshake(s->session, s->fd));
    if (rc != 0) {
        pt_ssh_close(s);
        return RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_HANDSHAKE;
    }
    *out = s;
    return PT_OK;
}

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int pt_ssh_host_fingerprint(pt_ssh *s, char *out, size_t outlen) {
    const unsigned char *h = (const unsigned char *)libssh2_hostkey_hash(s->session, LIBSSH2_HOSTKEY_HASH_SHA256);
    if (!h) return PT_ERR_HANDSHAKE;
    /* SHA-256 = 32 bytes -> 43 base64 characters without padding, as `ssh-keygen -l` prints. */
    char b[64];
    size_t n = 0;
    for (int i = 0; i < 32; i += 3) {
        unsigned v = (unsigned)h[i] << 16 | (i + 1 < 32 ? (unsigned)h[i + 1] << 8 : 0) | (i + 2 < 32 ? h[i + 2] : 0);
        b[n++] = B64[(v >> 18) & 63];
        b[n++] = B64[(v >> 12) & 63];
        if (i + 1 < 32) b[n++] = B64[(v >> 6) & 63];
        if (i + 2 < 32) b[n++] = B64[v & 63];
    }
    b[n] = 0;
    if ((size_t)snprintf(out, outlen, "SHA256:%s", b) >= outlen) return PT_ERR_NOSPACE;
    return PT_OK;
}

const char *pt_ssh_host_key_type(pt_ssh *s) {
    size_t len;
    int type;
    if (!libssh2_session_hostkey(s->session, &len, &type)) return "unknown";
    switch (type) {
    case LIBSSH2_HOSTKEY_TYPE_ED25519: return "ssh-ed25519";
    case LIBSSH2_HOSTKEY_TYPE_ECDSA_256: return "ecdsa-sha2-nistp256";
    case LIBSSH2_HOSTKEY_TYPE_RSA: return "ssh-rsa";
    default: return "unknown";
    }
}

/* ---- OpenSSH private key check (PROTOCOL.key): unencrypted, one ssh-ed25519 key ---- */

static int b64val(int c) {
    const char *p = c ? strchr(B64, c) : NULL;
    return p ? (int)(p - B64) : -1;
}

static int read_u32(const unsigned char **p, const unsigned char *end, unsigned *v) {
    if (end - *p < 4) return 0;
    *v = (unsigned)(*p)[0] << 24 | (unsigned)(*p)[1] << 16 | (unsigned)(*p)[2] << 8 | (*p)[3];
    *p += 4;
    return 1;
}

static int read_str(const unsigned char **p, const unsigned char *end, const unsigned char **s, unsigned *len) {
    if (!read_u32(p, end, len) || (size_t)(end - *p) < *len) return 0;
    *s = *p;
    *p += *len;
    return 1;
}

static int str_is(const unsigned char *s, unsigned len, const char *want) {
    return len == strlen(want) && memcmp(s, want, len) == 0;
}

int pt_ssh_key_valid(const char *key, size_t len) {
    static const char BEGIN[] = "-----BEGIN OPENSSH PRIVATE KEY-----", END[] = "-----END OPENSSH PRIVATE KEY-----";
    const char *kend = key + len;
    const char *b = NULL;
    for (const char *p = key; p + sizeof BEGIN - 1 <= kend; p++)
        if (memcmp(p, BEGIN, sizeof BEGIN - 1) == 0) { b = p + sizeof BEGIN - 1; break; }
    if (!b) return 0;
    const char *e = NULL;
    for (const char *p = b; p + sizeof END - 1 <= kend; p++)
        if (memcmp(p, END, sizeof END - 1) == 0) { e = p; break; }
    if (!e) return 0;
    unsigned char *bin = malloc((size_t)(e - b));
    if (!bin) return 0;
    size_t n = 0;
    unsigned acc = 0;
    int bits = 0;
    for (const char *p = b; p < e; p++) {
        if (*p == '=' ) break;
        int v = b64val(*p);
        if (v < 0) continue; /* line breaks */
        acc = acc << 6 | (unsigned)v;
        bits += 6;
        if (bits >= 8) { bits -= 8; bin[n++] = (unsigned char)(acc >> bits); }
    }
    static const char MAGIC[] = "openssh-key-v1"; /* followed by NUL */
    int ok = 0;
    const unsigned char *p = bin, *end = bin + n, *s;
    unsigned sl, nkeys;
    if (n > sizeof MAGIC && memcmp(p, MAGIC, sizeof MAGIC) == 0) {
        p += sizeof MAGIC;
        ok = read_str(&p, end, &s, &sl) && str_is(s, sl, "none")   /* cipher: no passphrase */
             && read_str(&p, end, &s, &sl) && str_is(s, sl, "none") /* kdf */
             && read_str(&p, end, &s, &sl)                          /* kdf options */
             && read_u32(&p, end, &nkeys) && nkeys == 1;
        const unsigned char *pub;
        unsigned pl;
        if (ok && read_str(&p, end, &pub, &pl)) {
            const unsigned char *q = pub;
            ok = read_str(&q, pub + pl, &s, &sl) && str_is(s, sl, "ssh-ed25519");
        } else {
            ok = 0;
        }
    }
    memset(bin, 0, n); /* BR-CONNECT-3: no copy of key material left in freed memory */
    free(bin);
    return ok;
}

int pt_ssh_auth_key(pt_ssh *s, const char *user, const char *private_key, size_t key_len) {
    if (!user || !*user || !private_key) return PT_ERR_INVALID;
    if (!pt_ssh_key_valid(private_key, key_len)) return PT_ERR_KEY_INVALID;
    double deadline = now_ms() + s->timeout_ms;
    int rc;
    RETRY(s, deadline, rc, libssh2_userauth_publickey_frommemory(s->session, user, strlen(user), NULL, 0,
                                                                 private_key, key_len, NULL));
    if (rc == 0) return PT_OK;
    if (RETRY_STATUS(rc)) return RETRY_STATUS(rc);
    if (rc == LIBSSH2_ERROR_AUTHENTICATION_FAILED || rc == LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED) return PT_ERR_AUTH;
    if (rc == LIBSSH2_ERROR_FILE || rc == LIBSSH2_ERROR_METHOD_NOT_SUPPORTED) return PT_ERR_KEY_INVALID;
    if (rc == LIBSSH2_ERROR_SOCKET_DISCONNECT || rc == LIBSSH2_ERROR_SOCKET_RECV || rc == LIBSSH2_ERROR_SOCKET_SEND)
        return PT_ERR_IO;
    return PT_ERR_AUTH;
}

int pt_ssh_open_shell(pt_ssh *s, const char *command, int cols, int rows) {
    if (!command || cols <= 0 || rows <= 0) return PT_ERR_INVALID;
    double deadline = now_ms() + s->timeout_ms;
    LIBSSH2_CHANNEL *ch;
    while (!(ch = libssh2_channel_open_session(s->session))) {
        if (libssh2_session_last_errno(s->session) != LIBSSH2_ERROR_EAGAIN) return PT_ERR_CHANNEL;
        int w = wait_socket(s, deadline);
        if (w != PT_OK) return w;
    }
    s->channel = ch;
    static const char TERM[] = "xterm-256color";
    int rc;
    RETRY(s, deadline, rc, libssh2_channel_request_pty_ex(ch, TERM, sizeof TERM - 1, NULL, 0, cols, rows, 0, 0));
    if (rc != 0) return RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_CHANNEL;
    RETRY(s, deadline, rc, libssh2_channel_exec(ch, command));
    if (rc != 0) return RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_CHANNEL;
    return PT_OK;
}

int pt_ssh_exec_capture(pt_ssh *s, const char *command, char *out, size_t cap, size_t *len) {
    if (!command || !out || !len) return PT_ERR_INVALID;
    *len = 0;
    double deadline = now_ms() + s->timeout_ms;
    LIBSSH2_CHANNEL *ch;
    while (!(ch = libssh2_channel_open_session(s->session))) {
        if (libssh2_session_last_errno(s->session) != LIBSSH2_ERROR_EAGAIN) return PT_ERR_CHANNEL;
        int w = wait_socket(s, deadline);
        if (w != PT_OK) return w;
    }
    int rc, st = PT_OK;
    /* A shell startup file that prints to stderr must not hold back the end of stdout: while an unread stderr packet
     * waits, libssh2_channel_eof says "not yet". */
    RETRY(s, deadline, rc, libssh2_channel_handle_extended_data2(ch, LIBSSH2_CHANNEL_EXTENDED_DATA_IGNORE));
    if (rc != 0) st = RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_CHANNEL;
    if (st == PT_OK) RETRY(s, deadline, rc, libssh2_channel_exec(ch, command));
    if (st == PT_OK && rc != 0) st = RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_CHANNEL;
    while (st == PT_OK) {
        if (*len == cap) { st = PT_ERR_NOSPACE; break; }
        ssize_t n = libssh2_channel_read(ch, out + *len, cap - *len);
        if (n > 0) { *len += (size_t)n; continue; }
        if (n == 0) { if (libssh2_channel_eof(ch)) break; }
        else if (n != LIBSSH2_ERROR_EAGAIN) { st = PT_ERR_IO; break; }
        int w = wait_socket(s, deadline);
        if (w != PT_OK) st = w;
    }
    double end = now_ms() + 1000; /* a closed channel needs no long wait: 1 s is a round trip with room */
    while ((rc = libssh2_channel_free(ch)) == LIBSSH2_ERROR_EAGAIN && wait_socket(s, end) == PT_OK) {}
    if (rc == LIBSSH2_ERROR_EAGAIN && st == PT_OK) st = PT_ERR_IO; /* half freed: the caller connects again */
    return st;
}

int pt_ssh_read(pt_ssh *s, char *buf, size_t len) {
    if (!s->channel) return PT_ERR_INVALID;
    ssize_t n = libssh2_channel_read(s->channel, buf, len);
    if (n > 0) return (int)n;
    if (n < 0 && n != LIBSSH2_ERROR_EAGAIN) return PT_ERR_IO;
    /* With a PTY stderr is empty, but drain it so its window never fills. */
    ssize_t e = libssh2_channel_read_stderr(s->channel, buf, len);
    if (e > 0) return (int)e;
    if (e < 0 && e != LIBSSH2_ERROR_EAGAIN) return PT_ERR_IO;
    return libssh2_channel_eof(s->channel) ? PT_ERR_CLOSED : 0;
}

int pt_ssh_write(pt_ssh *s, const char *buf, size_t len) {
    if (!s->channel) return PT_ERR_INVALID;
    ssize_t n = libssh2_channel_write(s->channel, buf, len);
    if (n == LIBSSH2_ERROR_EAGAIN) return 0;
    return n < 0 ? PT_ERR_IO : (int)n;
}

int pt_ssh_resize(pt_ssh *s, int cols, int rows) {
    if (!s->channel || cols <= 0 || rows <= 0) return PT_ERR_INVALID;
    double deadline = now_ms() + s->timeout_ms;
    int rc;
    RETRY(s, deadline, rc, libssh2_channel_request_pty_size(s->channel, cols, rows));
    if (rc == 0) return PT_OK;
    return RETRY_STATUS(rc) ? RETRY_STATUS(rc) : PT_ERR_IO;
}

void pt_ssh_keepalive_config(pt_ssh *s, int interval_s) {
    libssh2_keepalive_config(s->session, 1 /* want_reply: the server answers, so a live link has inbound traffic */,
                             (unsigned)interval_s);
}

int pt_ssh_keepalive_tick(pt_ssh *s, int *next_s) {
    int rc = libssh2_keepalive_send(s->session, next_s);
    if (rc == 0 || rc == LIBSSH2_ERROR_EAGAIN) return PT_OK;
    return PT_ERR_IO;
}

int pt_ssh_socket(pt_ssh *s) { return s->fd; }

int pt_ssh_block_directions(pt_ssh *s) {
    int d = libssh2_session_block_directions(s->session);
    return (d & LIBSSH2_SESSION_BLOCK_INBOUND ? 1 : 0) | (d & LIBSSH2_SESSION_BLOCK_OUTBOUND ? 2 : 0);
}

void pt_ssh_close(pt_ssh *s) {
    if (!s) return;
    if (s->session) {
        /* One non-blocking try each, so a dead link cannot hold the close. */
        if (s->channel) libssh2_channel_close(s->channel);
        libssh2_session_disconnect(s->session, "bye");
        /* After shutdown every libssh2 call fails at once; in blocking mode the frees then cannot
         * return EAGAIN and leak. */
        if (s->fd >= 0) shutdown(s->fd, SHUT_RDWR);
        libssh2_session_set_blocking(s->session, 1);
        if (s->channel) libssh2_channel_free(s->channel);
        libssh2_session_free(s->session);
    }
    if (s->fd >= 0) close(s->fd);
    free(s);
}
