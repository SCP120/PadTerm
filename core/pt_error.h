#ifndef PT_ERROR_H
#define PT_ERROR_H

/* Every PadTerm function that can fail returns one of these (0 = success). */
typedef enum {
    PT_OK = 0,
    PT_ERR_INVALID = -1,          /* bad argument, e.g. control character in a directory */
    PT_ERR_NOSPACE = -2,          /* output buffer too small */
    PT_ERR_RESOLVE = -3,          /* host name not found */
    PT_ERR_TIMEOUT = -4,          /* connect or handshake did not finish in time */
    PT_ERR_CONNECT = -5,          /* TCP connect refused or failed */
    PT_ERR_HANDSHAKE = -6,        /* SSH key exchange failed */
    PT_ERR_HOSTKEY_MISMATCH = -7, /* host key differs from the pin */
    PT_ERR_KEY_INVALID = -8,      /* private key is not a valid OpenSSH Ed25519 key */
    PT_ERR_AUTH = -9,             /* server did not accept the key */
    PT_ERR_CHANNEL = -10,         /* PTY or exec request refused */
    PT_ERR_IO = -11,              /* socket or channel read/write failed */
    PT_ERR_CLOSED = -12,          /* server closed the channel */
    PT_ERR_NOMEM = -13,
    PT_ERR_CANCELLED = -14        /* the caller closed the connection while it was being set up */
} pt_status;

/* Short English text for the UI, e.g. "authentication failed". Never NULL. */
const char *pt_status_text(int status);

#endif
