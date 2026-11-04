#include "pt_keys.h"
#include "pt_error.h"
#include <vterm.h>

int pt_keys_send(pt_term *term, pt_key key) {
    switch (key) {
    case PT_KEY_ESC: pt_term_key(term, VTERM_KEY_ESCAPE, VTERM_MOD_NONE); break;
    case PT_KEY_TAB: pt_term_key(term, VTERM_KEY_TAB, VTERM_MOD_NONE); break;
    case PT_KEY_BACKTAB: pt_term_key(term, VTERM_KEY_TAB, VTERM_MOD_SHIFT); break;
    case PT_KEY_ENTER: pt_term_key(term, VTERM_KEY_ENTER, VTERM_MOD_NONE); break;
    case PT_KEY_UP: pt_term_key(term, VTERM_KEY_UP, VTERM_MOD_NONE); break;
    case PT_KEY_DOWN: pt_term_key(term, VTERM_KEY_DOWN, VTERM_MOD_NONE); break;
    case PT_KEY_LEFT: pt_term_key(term, VTERM_KEY_LEFT, VTERM_MOD_NONE); break;
    case PT_KEY_RIGHT: pt_term_key(term, VTERM_KEY_RIGHT, VTERM_MOD_NONE); break;
    case PT_KEY_PAGEUP: pt_term_key(term, VTERM_KEY_PAGEUP, VTERM_MOD_NONE); break;
    case PT_KEY_PAGEDOWN: pt_term_key(term, VTERM_KEY_PAGEDOWN, VTERM_MOD_NONE); break;
    case PT_KEY_CTRL_C: pt_term_char(term, 'c', VTERM_MOD_CTRL); break;
    default: return PT_ERR_INVALID;
    }
    return PT_OK;
}

int pt_keys_send_char(pt_term *term, unsigned int codepoint, int ctrl) {
    if (codepoint == 0 || codepoint > 0x10FFFF) return PT_ERR_INVALID;
    if (ctrl && codepoint >= 'A' && codepoint <= 'Z') codepoint += 'a' - 'A';
    /* Ctrl + letter or @[\]^_ : the traditional C0 byte. libvterm would send CSI u for i, j, m and [,
     * which Claude Code and Codex do not read as Tab, Ctrl+J and Esc. */
    if (ctrl && ((codepoint >= 'a' && codepoint <= 'z') || (codepoint >= '@' && codepoint <= '_'))) {
        char b = (char)(codepoint & 0x1f);
        pt_term_send_bytes(term, &b, 1);
        return PT_OK;
    }
    pt_term_char(term, codepoint, ctrl ? VTERM_MOD_CTRL : VTERM_MOD_NONE);
    return PT_OK;
}
