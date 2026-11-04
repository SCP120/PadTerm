#ifndef PT_SSH_H
#define PT_SSH_H
#include <stddef.h>

typedef struct pt_ssh pt_ssh;

/* Call once per process before any other pt_ssh function. */
int pt_ssh_global_init(void);

/* TCP connect + SSH handshake. timeout_ms bounds connect and handshake together; it also bounds each later
 * setup step (auth, shell). cancel_fd: -1, or a fd that becomes readable to stop any setup step at once
 * with PT_ERR_CANCELLED. Name lookup (getaddrinfo) cannot be cancelled. */
int pt_ssh_connect(const char *host, int port, int timeout_ms, int cancel_fd, pt_ssh **out);

/* OpenSSH-style fingerprint "SHA256:<base64 without padding>" of the server host key. */
int pt_ssh_host_fingerprint(pt_ssh *s, char *out, size_t outlen);
/* Host key type name, e.g. "ssh-ed25519". */
const char *pt_ssh_host_key_type(pt_ssh *s);

/* 1 if key is an unencrypted OpenSSH private key with one ssh-ed25519 key (EF-CONNECT-3), else 0. */
int pt_ssh_key_valid(const char *key, size_t len);

/* Key auth with an OpenSSH private key in memory (no passphrase). */
int pt_ssh_auth_key(pt_ssh *s, const char *user, const char *private_key, size_t key_len);

/* Open session channel, PTY xterm-256color (cols x rows), exec command. Switches to non-blocking. */
int pt_ssh_open_shell(pt_ssh *s, const char *command, int cols, int rows);

/* Run one command on a new channel with no PTY and collect its stdout (at most cap bytes). The connection stays
 * open for the next command. PT_ERR_NOSPACE if the output is larger. */
int pt_ssh_exec_capture(pt_ssh *s, const char *command, char *out, size_t cap, size_t *len);

/* Non-blocking IO after pt_ssh_open_shell. read: >0 bytes, 0 = nothing now, <0 error/closed. */
int pt_ssh_read(pt_ssh *s, char *buf, size_t len);
/* write: >=0 bytes accepted (may be less than len), <0 error. */
int pt_ssh_write(pt_ssh *s, const char *buf, size_t len);
int pt_ssh_resize(pt_ssh *s, int cols, int rows);

/* Keep-alive: configure interval; tick returns seconds until the next one is due. */
void pt_ssh_keepalive_config(pt_ssh *s, int interval_s);
int pt_ssh_keepalive_tick(pt_ssh *s, int *next_s);

/* Socket for select(); and which direction libssh2 waits on (bit 0 read, bit 1 write). */
int pt_ssh_socket(pt_ssh *s);
int pt_ssh_block_directions(pt_ssh *s);

/* Close channel + session + socket. Safe with NULL. */
void pt_ssh_close(pt_ssh *s);

#endif
