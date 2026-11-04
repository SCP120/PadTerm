#ifndef PT_TERM_H
#define PT_TERM_H
#include <stddef.h>
#include <stdint.h>

typedef struct pt_term pt_term;

/* Bytes the terminal sends to the host: key presses, paste, mouse, replies to queries. */
typedef void (*pt_term_output_fn)(const char *bytes, size_t len, void *user);

#define PT_CELL_MAX_CHARS 6

typedef struct {
    uint32_t chars[PT_CELL_MAX_CHARS]; /* base + combining; chars[0] == 0: empty cell */
    int width;                         /* 1, or 2 for a wide character (next cell is a spacer) */
    uint8_t fg[3], bg[3];              /* RGB after palette lookup; reverse NOT applied */
    unsigned fg_default : 1, bg_default : 1;
    unsigned bold : 1, dim : 1, italic : 1, underline : 2, reverse : 1, strike : 1;
} pt_cell;

typedef struct {
    int row, col;
    int visible;
    int shape; /* 1 block, 2 underline, 3 bar (libvterm VTERM_PROP_CURSORSHAPE_*) */
} pt_cursor;

pt_term *pt_term_new(int rows, int cols, pt_term_output_fn out, void *user);
void pt_term_free(pt_term *t);

void pt_term_feed(pt_term *t, const char *bytes, size_t len);
/* The terminal title if it changed since the last call (OSC 0 / 2), else NULL. Valid until the next feed. */
const char *pt_term_take_title(pt_term *t);
void pt_term_resize(pt_term *t, int rows, int cols);
void pt_term_size(const pt_term *t, int *rows, int *cols);

int pt_term_cell(const pt_term *t, int row, int col, pt_cell *cell);
void pt_term_cursor(const pt_term *t, pt_cursor *cursor);

/* Row text as UTF-8, trailing spaces removed. Returns length or PT_ERR_NOSPACE. */
int pt_term_row_text(const pt_term *t, int row, char *out, size_t outlen);

/* Damage since the last call: 1 = something changed. top/bottom (may be NULL) get the changed rows
 * [top, bottom), so the UI redraws only those rows. */
int pt_term_take_damage(pt_term *t, int *top, int *bottom);

/* Theme: default colours and the 16 ANSI colours (rgb[16][3]). */
void pt_term_set_colors(pt_term *t, const uint8_t fg[3], const uint8_t bg[3], const uint8_t ansi16[16][3]);

/* Input. mods: bit 0 shift, bit 1 alt, bit 2 ctrl (libvterm VTermModifier). */
void pt_term_key(pt_term *t, int vterm_key, int mods);
void pt_term_char(pt_term *t, uint32_t codepoint, int mods);
void pt_term_paste(pt_term *t, const char *utf8, size_t len); /* bracketed when the program asked */
/* Raw bytes to the host through the output callback (e.g. traditional control codes). */
void pt_term_send_bytes(pt_term *t, const char *bytes, size_t len);

/* Mouse: only sent when the program turned mouse mode on. Returns 1 if sent. */
int pt_term_mouse_mode(const pt_term *t);
void pt_term_mouse_click(pt_term *t, int row, int col);
void pt_term_mouse_wheel(pt_term *t, int row, int col, int lines_up); /* >0 up, <0 down */

#endif
