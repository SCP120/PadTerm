#include "pt_term.h"
#include "pt_error.h"
#include <stdlib.h>
#include <string.h>
#include <vterm.h>

struct pt_term {
    VTerm *vt;
    VTermScreen *screen;
    VTermState *state;
    pt_term_output_fn out;
    void *user;
    int damage;
    int dmg_top, dmg_bottom; /* changed rows [top, bottom) while damage == 1 */
    int mouse;
    pt_cursor cursor;
    char title[512]; /* longer titles are cut: the bar shows far fewer characters */
    size_t title_len;
    int title_new;
};

static void on_output(const char *s, size_t len, void *user) {
    pt_term *t = user;
    if (t->out) t->out(s, len, t->user);
}

static void mark_rows(pt_term *t, int top, int bottom) {
    if (!t->damage) { t->dmg_top = top; t->dmg_bottom = bottom; t->damage = 1; return; }
    if (top < t->dmg_top) t->dmg_top = top;
    if (bottom > t->dmg_bottom) t->dmg_bottom = bottom;
}

static void mark_all(pt_term *t) {
    int rows, cols;
    vterm_get_size(t->vt, &rows, &cols);
    mark_rows(t, 0, rows);
}

static int on_damage(VTermRect rect, void *user) {
    mark_rows(user, rect.start_row, rect.end_row);
    return 1;
}

static int on_moverect(VTermRect dest, VTermRect src, void *user) {
    mark_rows(user, dest.start_row < src.start_row ? dest.start_row : src.start_row,
              dest.end_row > src.end_row ? dest.end_row : src.end_row);
    return 1;
}

static int on_movecursor(VTermPos pos, VTermPos oldpos, int visible, void *user) {
    (void)visible;
    pt_term *t = user;
    mark_rows(t, oldpos.row, oldpos.row + 1); /* the cursor is drawn: both rows change */
    mark_rows(t, pos.row, pos.row + 1);
    t->cursor.row = pos.row;
    t->cursor.col = pos.col;
    return 1;
}

static int on_settermprop(VTermProp prop, VTermValue *val, void *user) {
    pt_term *t = user;
    switch (prop) {
    case VTERM_PROP_CURSORVISIBLE: t->cursor.visible = val->boolean; break;
    case VTERM_PROP_CURSORSHAPE: t->cursor.shape = val->number; break;
    case VTERM_PROP_MOUSE: t->mouse = val->number; break;
    case VTERM_PROP_ICONNAME: return 1; /* OSC 0 sets it with the title: a spinner frame must not repaint the screen */
    case VTERM_PROP_TITLE: { /* arrives in fragments; a title never touches the screen */
        VTermStringFragment f = val->string;
        if (f.initial) t->title_len = 0;
        size_t room = sizeof t->title - 1 - t->title_len, n = f.len < room ? f.len : room;
        memcpy(t->title + t->title_len, f.str, n);
        t->title_len += n;
        if (f.final) { t->title[t->title_len] = 0; t->title_new = 1; }
        return 1;
    }
    default: break;
    }
    mark_all(t);
    return 1;
}

static const VTermScreenCallbacks CALLBACKS = {
    .damage = on_damage,
    .moverect = on_moverect,
    .movecursor = on_movecursor,
    .settermprop = on_settermprop,
};

pt_term *pt_term_new(int rows, int cols, pt_term_output_fn out, void *user) {
    if (rows <= 0 || cols <= 0) return NULL;
    pt_term *t = calloc(1, sizeof *t);
    if (!t) return NULL;
    t->vt = vterm_new(rows, cols);
    if (!t->vt) { free(t); return NULL; }
    t->out = out;
    t->user = user;
    t->cursor.visible = 1;
    t->cursor.shape = VTERM_PROP_CURSORSHAPE_BLOCK;
    vterm_set_utf8(t->vt, 1);
    vterm_output_set_callback(t->vt, on_output, t);
    t->screen = vterm_obtain_screen(t->vt);
    t->state = vterm_obtain_state(t->vt);
    vterm_screen_set_callbacks(t->screen, &CALLBACKS, t);
    vterm_screen_enable_altscreen(t->screen, 1);
    vterm_screen_reset(t->screen, 1);
    mark_all(t);
    return t;
}

void pt_term_free(pt_term *t) {
    if (!t) return;
    vterm_free(t->vt);
    free(t);
}

void pt_term_feed(pt_term *t, const char *bytes, size_t len) {
    vterm_input_write(t->vt, bytes, len);
    vterm_screen_flush_damage(t->screen);
}

const char *pt_term_take_title(pt_term *t) {
    if (!t->title_new) return NULL;
    t->title_new = 0;
    return t->title;
}

void pt_term_resize(pt_term *t, int rows, int cols) {
    if (rows <= 0 || cols <= 0) return;
    vterm_set_size(t->vt, rows, cols);
    vterm_screen_flush_damage(t->screen);
    mark_all(t);
}

void pt_term_size(const pt_term *t, int *rows, int *cols) { vterm_get_size(t->vt, rows, cols); }

static void to_rgb(const pt_term *t, VTermColor c, uint8_t out[3]) {
    vterm_screen_convert_color_to_rgb(t->screen, &c);
    out[0] = c.rgb.red; out[1] = c.rgb.green; out[2] = c.rgb.blue;
}

int pt_term_cell(const pt_term *t, int row, int col, pt_cell *cell) {
    int rows, cols;
    vterm_get_size(t->vt, &rows, &cols);
    if (row < 0 || col < 0 || row >= rows || col >= cols) return PT_ERR_INVALID;
    VTermScreenCell vc;
    if (!vterm_screen_get_cell(t->screen, (VTermPos){row, col}, &vc)) return PT_ERR_INVALID;
    memset(cell, 0, sizeof *cell);
    if (vc.chars[0] == (uint32_t)-1) {
        cell->width = 0; /* right half of a wide character */
    } else {
        for (int i = 0; i < PT_CELL_MAX_CHARS && i < VTERM_MAX_CHARS_PER_CELL && vc.chars[i]; i++) cell->chars[i] = vc.chars[i];
        cell->width = vc.width;
    }
    cell->fg_default = VTERM_COLOR_IS_DEFAULT_FG(&vc.fg) ? 1 : 0;
    cell->bg_default = VTERM_COLOR_IS_DEFAULT_BG(&vc.bg) ? 1 : 0;
    to_rgb(t, vc.fg, cell->fg);
    to_rgb(t, vc.bg, cell->bg);
    cell->bold = vc.attrs.bold;
    cell->dim = vc.attrs.dim;
    cell->italic = vc.attrs.italic;
    cell->underline = vc.attrs.underline;
    cell->reverse = vc.attrs.reverse;
    cell->strike = vc.attrs.strike;
    return PT_OK;
}

void pt_term_cursor(const pt_term *t, pt_cursor *cursor) { *cursor = t->cursor; }

static int utf8_put(uint32_t c, char *o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xC0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3F)); return 2; }
    if (c < 0x10000) {
        o[0] = (char)(0xE0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3F)); o[2] = (char)(0x80 | (c & 0x3F));
        return 3;
    }
    o[0] = (char)(0xF0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3F));
    o[2] = (char)(0x80 | ((c >> 6) & 0x3F)); o[3] = (char)(0x80 | (c & 0x3F));
    return 4;
}

int pt_term_row_text(const pt_term *t, int row, char *out, size_t outlen) {
    int rows, cols;
    vterm_get_size(t->vt, &rows, &cols);
    if (row < 0 || row >= rows || outlen == 0) return PT_ERR_INVALID;
    size_t n = 0, keep = 0; /* keep = length without trailing spaces */
    for (int col = 0; col < cols; col++) {
        pt_cell c;
        pt_term_cell(t, row, col, &c);
        if (c.width == 0) continue;
        char tmp[4 * PT_CELL_MAX_CHARS];
        int k = 0;
        if (!c.chars[0]) tmp[k++] = ' ';
        for (int i = 0; i < PT_CELL_MAX_CHARS && c.chars[i]; i++) k += utf8_put(c.chars[i], tmp + k);
        if (n + (size_t)k >= outlen) return PT_ERR_NOSPACE;
        memcpy(out + n, tmp, (size_t)k);
        n += (size_t)k;
        if (!(k == 1 && tmp[0] == ' ')) keep = n;
    }
    out[keep] = 0;
    return (int)keep;
}

int pt_term_take_damage(pt_term *t, int *top, int *bottom) {
    int d = t->damage;
    if (top) *top = d ? t->dmg_top : 0;
    if (bottom) *bottom = d ? t->dmg_bottom : 0;
    t->damage = 0;
    return d;
}

static VTermColor rgb(const uint8_t c[3]) {
    VTermColor v;
    vterm_color_rgb(&v, c[0], c[1], c[2]);
    return v;
}

void pt_term_set_colors(pt_term *t, const uint8_t fg[3], const uint8_t bg[3], const uint8_t ansi16[16][3]) {
    VTermColor f = rgb(fg), b = rgb(bg);
    vterm_screen_set_default_colors(t->screen, &f, &b);
    if (ansi16)
        for (int i = 0; i < 16; i++) {
            VTermColor c = rgb(ansi16[i]);
            vterm_state_set_palette_color(t->state, i, &c);
        }
    mark_all(t);
}

void pt_term_key(pt_term *t, int vterm_key, int mods) { vterm_keyboard_key(t->vt, (VTermKey)vterm_key, (VTermModifier)mods); }

void pt_term_char(pt_term *t, uint32_t codepoint, int mods) {
    if (codepoint == '\n' || codepoint == '\r') { vterm_keyboard_key(t->vt, VTERM_KEY_ENTER, (VTermModifier)mods); return; }
    vterm_keyboard_unichar(t->vt, codepoint, (VTermModifier)mods);
}

void pt_term_paste(pt_term *t, const char *utf8, size_t len) {
    vterm_keyboard_start_paste(t->vt);
    /* A terminal sends CR for a line end (CRLF and LF both become one CR). ESC is dropped: a pasted
     * "ESC [201~" would end the bracketed paste early and the rest would act as typed keys. */
    char buf[256];
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        char c = utf8[i];
        if (c == 0x1b) continue;
        if (c == '\r' && i + 1 < len && utf8[i + 1] == '\n') continue;
        if (c == '\n') c = '\r';
        buf[n++] = c;
        if (n == sizeof buf) { on_output(buf, n, t); n = 0; }
    }
    if (n) on_output(buf, n, t);
    vterm_keyboard_end_paste(t->vt);
}

int pt_term_mouse_mode(const pt_term *t) { return t->mouse != VTERM_PROP_MOUSE_NONE; }

void pt_term_mouse_click(pt_term *t, int row, int col) {
    if (!pt_term_mouse_mode(t)) return;
    vterm_mouse_move(t->vt, row, col, VTERM_MOD_NONE);
    vterm_mouse_button(t->vt, 1, true, VTERM_MOD_NONE);
    vterm_mouse_button(t->vt, 1, false, VTERM_MOD_NONE);
}

void pt_term_mouse_wheel(pt_term *t, int row, int col, int lines_up) {
    if (!pt_term_mouse_mode(t) || lines_up == 0) return;
    vterm_mouse_move(t->vt, row, col, VTERM_MOD_NONE);
    int button = lines_up > 0 ? 4 : 5; /* xterm: buttons 4/5 = wheel up/down */
    int n = lines_up > 0 ? lines_up : -lines_up;
    for (int i = 0; i < n; i++) vterm_mouse_button(t->vt, button, true, VTERM_MOD_NONE);
}

void pt_term_send_bytes(pt_term *t, const char *bytes, size_t len) { on_output(bytes, len, t); }
