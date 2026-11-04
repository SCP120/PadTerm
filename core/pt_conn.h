#ifndef PT_CONN_H
#define PT_CONN_H
#include <stddef.h>

typedef struct pt_conn pt_conn;

typedef enum {
    PT_CONN_EV_HOSTKEY,   /* text = fingerprint; the callback returns 1 to accept, 0 to refuse */
    PT_CONN_EV_CONNECTED, /* channel is open */
    PT_CONN_EV_DATA,      /* data/len = bytes from the server */
    PT_CONN_EV_CLOSED     /* status = PT_OK (user close), PT_ERR_CLOSED, or an error */
} pt_conn_event;

/* Called on the IO thread. Return value used only for PT_CONN_EV_HOSTKEY. */
typedef int (*pt_conn_fn)(pt_conn_event ev, int status, const char *data, size_t len, void *user);

typedef struct {
    const char *host;
    int port;
    const char *user;
    const char *private_key; /* OpenSSH format, copied */
    size_t private_key_len;
    const char *pinned_fingerprint; /* NULL or "" = ask via PT_CONN_EV_HOSTKEY */
    const char *command;
    int cols, rows;
    int connect_timeout_ms;
    int keepalive_s;
} pt_conn_params;

/* Start the IO thread. All strings are copied. */
int pt_conn_start(const pt_conn_params *p, pt_conn_fn fn, void *user, pt_conn **out);

/* Thread-safe. Tell the IO thread that the caller has processed len bytes of PT_CONN_EV_DATA.
 * The IO thread stops reading while more than one SSH window of data is not yet acknowledged, so a fast
 * server cannot fill the memory of a slow client; the server then waits (SSH flow control). Every caller
 * must acknowledge every DATA event, or the session stops after that much output. */
int pt_conn_ack(pt_conn *c, size_t len);

/* Thread-safe; queue bytes / a resize for the IO thread. */
int pt_conn_write(pt_conn *c, const char *bytes, size_t len);
int pt_conn_resize(pt_conn *c, int cols, int rows);

/* Ask the IO thread to close (PT_CONN_EV_CLOSED with PT_OK follows), wait for it, free. A connect, handshake,
 * auth or shell setup in progress stops at once; only a name lookup (getaddrinfo) cannot be stopped. */
void pt_conn_close(pt_conn *c);

#endif
