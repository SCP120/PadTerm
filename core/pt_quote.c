#include "pt_quote.h"
#include "pt_error.h"
#include <string.h>

static int has_control(const char *s) {
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s;
        if (c < 0x20 || c == 0x7f) return 1;
    }
    return 0;
}

int pt_shell_quote(const char *in, char *out, size_t outlen) {
    if (!in || !out || has_control(in)) return PT_ERR_INVALID;
    size_t n = 0;
#define PUT(ch) do { if (n + 1 >= outlen) return PT_ERR_NOSPACE; out[n++] = (ch); } while (0)
    PUT('\'');
    for (const char *p = in; *p; p++) {
        if (*p == '\'') { PUT('\''); PUT('\\'); PUT('\''); PUT('\''); }
        else PUT(*p);
    }
    PUT('\'');
#undef PUT
    out[n] = 0;
    return (int)n;
}

int pt_quote_dir(const char *dir, char *out, size_t outlen) {
    static const char HOME[] = "\"$HOME\"";
    if (!dir || !out || has_control(dir)) return PT_ERR_INVALID;
    if (dir[0] == '~' && dir[1] != 0 && dir[1] != '/') return PT_ERR_INVALID; /* ~user */
    const char *rest = NULL;
    if (dir[0] == 0 || strcmp(dir, "~") == 0) rest = "";
    else if (dir[0] == '~') rest = dir + 2;
    if (!rest) return pt_shell_quote(dir, out, outlen);
    if (outlen < sizeof HOME) return PT_ERR_NOSPACE;
    memcpy(out, HOME, sizeof HOME);
    if (!*rest) return (int)(sizeof HOME - 1);
    if (outlen < sizeof HOME + 1) return PT_ERR_NOSPACE;
    out[sizeof HOME - 1] = '/';
    int q = pt_shell_quote(rest, out + sizeof HOME, outlen - sizeof HOME);
    if (q < 0) return q;
    return (int)sizeof HOME + q;
}
