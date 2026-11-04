#include "pt_backoff.h"
#include "pt_error.h"

enum { BACKOFF_FIRST_MS = 1000, BACKOFF_MAX_MS = 30000 }; /* see pt_backoff.h */

void pt_backoff_reset(pt_backoff *b) { b->next_ms = BACKOFF_FIRST_MS; }

int pt_backoff_next(pt_backoff *b) {
    int now = b->next_ms;
    b->next_ms = now * 2 > BACKOFF_MAX_MS ? BACKOFF_MAX_MS : now * 2;
    return now;
}

int pt_should_reconnect(int status) {
    switch (status) {
    case PT_ERR_IO: case PT_ERR_TIMEOUT: case PT_ERR_CONNECT:
    case PT_ERR_RESOLVE: case PT_ERR_HANDSHAKE:
        return 1;
    default:
        return 0;
    }
}
