#ifndef PT_BACKOFF_H
#define PT_BACKOFF_H

/* Reconnect delay: 1 s, doubled after each failure, at most 30 s.
 * 30 s = the keep-alive interval, so a retry never waits longer than the dead-link detection. */
typedef struct { int next_ms; } pt_backoff;

void pt_backoff_reset(pt_backoff *b);
int pt_backoff_next(pt_backoff *b); /* delay to wait now, then advances */

/* 1 if the UI must reconnect after a close with this status: a lost link yes; a user close, a session end on the server, a refused
 * host key or key, or bad input no (BR-RECONNECT-1). */
int pt_should_reconnect(int status);

#endif
