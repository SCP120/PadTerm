#ifndef PT_KEYS_H
#define PT_KEYS_H

#include "pt_term.h"

/* Keys on the key bar (AC-INPUT-1). Ctrl is a one-shot modifier kept by the UI, not a key here. */
typedef enum {
    PT_KEY_ESC, PT_KEY_TAB, PT_KEY_BACKTAB, PT_KEY_ENTER,
    PT_KEY_UP, PT_KEY_DOWN, PT_KEY_LEFT, PT_KEY_RIGHT,
    PT_KEY_PAGEUP, PT_KEY_PAGEDOWN, PT_KEY_CTRL_C,
    PT_KEY_COUNT
} pt_key;

/* Send a key-bar key through the terminal (so cursor-key mode applies). */
int pt_keys_send(pt_term *term, pt_key key);

/* Send one typed character; ctrl = the one-shot Ctrl modifier was active. */
int pt_keys_send_char(pt_term *term, unsigned int codepoint, int ctrl);

#endif
