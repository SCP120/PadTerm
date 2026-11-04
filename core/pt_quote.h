#ifndef PT_QUOTE_H
#define PT_QUOTE_H
#include <stddef.h>

/* POSIX sh single-quote: abc -> 'abc', it's -> 'it'\''s'.
 * Returns the length written (without NUL) or PT_ERR_INVALID / PT_ERR_NOSPACE.
 * Refuses control characters (0x00-0x1f, 0x7f): a newline would end the command. */
int pt_shell_quote(const char *in, char *out, size_t outlen);

/* Directory for `cd`/`-c`: "" or "~" -> "$HOME", "~/x" -> "$HOME"/'x', other -> quoted.
 * "~user/..." is refused (PT_ERR_INVALID): the server shell would not expand it inside quotes. */
int pt_quote_dir(const char *dir, char *out, size_t outlen);

#endif
