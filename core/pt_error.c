#include "pt_error.h"

const char *pt_status_text(int status) {
    switch (status) {
    case PT_OK: return "ok";
    case PT_ERR_INVALID: return "invalid input";
    case PT_ERR_NOSPACE: return "buffer too small";
    case PT_ERR_RESOLVE: return "host not found";
    case PT_ERR_TIMEOUT: return "connection timed out";
    case PT_ERR_CONNECT: return "connection refused";
    case PT_ERR_HANDSHAKE: return "SSH handshake failed";
    case PT_ERR_HOSTKEY_MISMATCH: return "host key does not match the pinned key";
    case PT_ERR_KEY_INVALID: return "invalid key";
    case PT_ERR_AUTH: return "authentication failed";
    case PT_ERR_CHANNEL: return "server refused the terminal";
    case PT_ERR_IO: return "connection lost";
    case PT_ERR_CLOSED: return "server closed the session";
    case PT_ERR_NOMEM: return "out of memory";
    case PT_ERR_CANCELLED: return "cancelled";
    default: return "unknown error";
    }
}
