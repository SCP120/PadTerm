#include "pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_term.h"
#include "../../core/pt_keys.h"

static char g_out[512];
static size_t g_out_len;
static void capture(const char *b, size_t n, void *u) {
    (void)u;
    if (g_out_len + n <= sizeof g_out) { memcpy(g_out + g_out_len, b, n); g_out_len += n; }
}
static pt_term *mk(int rows, int cols) { g_out_len = 0; return pt_term_new(rows, cols, capture, NULL); }
static void feeds(pt_term *t, const char *s) { pt_term_feed(t, s, strlen(s)); }

PT_TEST(term_colors_16_256_rgb, "AC-SCREEN-1") {
    pt_term *t = mk(5, 20);
    const uint8_t fg[3] = {220, 220, 220}, bg[3] = {20, 20, 20};
    uint8_t ansi[16][3] = {{0}};
    ansi[1][0] = 200; ansi[1][1] = 10; ansi[1][2] = 10;
    pt_term_set_colors(t, fg, bg, (const uint8_t (*)[3])ansi);
    feeds(t, "A\x1b[31mB\x1b[38;5;196mC\x1b[38;5;244mD\x1b[38;2;1;2;3;48;2;4;5;6mE\x1b[0m\x1b[38;5;208mF\x1b[38;5;67mG");
    pt_cell c;
    CHECK_INT(pt_term_cell(t, 0, 0, &c), PT_OK);
    CHECK(c.fg_default && c.bg_default); CHECK_INT(c.fg[0], 220); CHECK_INT(c.bg[2], 20);
    pt_term_cell(t, 0, 1, &c); CHECK(!c.fg_default); CHECK_INT(c.fg[0], 200); CHECK_INT(c.fg[1], 10);
    pt_term_cell(t, 0, 2, &c); CHECK_INT(c.fg[0], 255); CHECK_INT(c.fg[1], 0); CHECK_INT(c.fg[2], 0);
    pt_term_cell(t, 0, 3, &c); CHECK_INT(c.fg[0], 128); CHECK_INT(c.fg[1], 128); CHECK_INT(c.fg[2], 128);
    pt_term_cell(t, 0, 4, &c); CHECK_INT(c.fg[0], 1); CHECK_INT(c.fg[1], 2); CHECK_INT(c.fg[2], 3);
    CHECK(!c.bg_default); CHECK_INT(c.bg[0], 4); CHECK_INT(c.bg[1], 5); CHECK_INT(c.bg[2], 6);
    /* xterm 256colres.h: 208 = cube(5,2,0) = 255,135,0; 67 = cube(1,2,3) = 95,135,175 */
    pt_term_cell(t, 0, 5, &c); CHECK_INT(c.fg[0], 255); CHECK_INT(c.fg[1], 135); CHECK_INT(c.fg[2], 0);
    pt_term_cell(t, 0, 6, &c); CHECK_INT(c.fg[0], 95); CHECK_INT(c.fg[1], 135); CHECK_INT(c.fg[2], 175);
    pt_term_free(t);
}

PT_TEST(term_attributes_and_dim, "AC-SCREEN-1") {
    pt_term *t = mk(5, 20);
    feeds(t, "\x1b[1;2;3;4;7;9mX\x1b[22mY\x1b[0mZ");
    pt_cell c;
    pt_term_cell(t, 0, 0, &c);
    CHECK(c.bold); CHECK(c.dim); CHECK(c.italic); CHECK_INT(c.underline, 1); CHECK(c.reverse); CHECK(c.strike);
    pt_term_cell(t, 0, 1, &c);
    CHECK(!c.bold); CHECK(!c.dim); CHECK(c.italic);
    pt_term_cell(t, 0, 2, &c);
    CHECK(!c.italic); CHECK(!c.reverse); CHECK_INT(c.underline, 0);
    pt_term_free(t);
}

PT_TEST(term_utf8_split_across_feeds, "AC-SCREEN-2") {
    pt_term *t = mk(5, 20);
    pt_term_feed(t, "\xC3", 1); pt_term_feed(t, "\xA9", 1);         /* é */
    pt_term_feed(t, "\xE2", 1); pt_term_feed(t, "\x8E\xBF", 2);     /* ⎿ U+23BF */
    pt_term_feed(t, "\xF0\x9F", 2); pt_term_feed(t, "\x98\x80", 2); /* 😀 U+1F600 */
    pt_cell c;
    pt_term_cell(t, 0, 0, &c); CHECK_INT(c.chars[0], 0xE9);
    pt_term_cell(t, 0, 1, &c); CHECK_INT(c.chars[0], 0x23BF);
    pt_term_cell(t, 0, 2, &c); CHECK_INT(c.chars[0], 0x1F600);
    char row[64];
    CHECK(pt_term_row_text(t, 0, row, sizeof row) > 0);
    CHECK_STR(row, "\xC3\xA9\xE2\x8E\xBF\xF0\x9F\x98\x80");
    pt_term_free(t);
}

PT_TEST(term_wide_chars, "AC-SCREEN-3") {
    pt_term *t = mk(5, 20);
    feeds(t, "\xE4\xB8\xADx"); /* 中x */
    pt_cell c;
    pt_term_cell(t, 0, 0, &c); CHECK_INT(c.chars[0], 0x4E2D); CHECK_INT(c.width, 2);
    pt_term_cell(t, 0, 1, &c); CHECK_INT(c.width, 0);
    pt_term_cell(t, 0, 2, &c); CHECK_INT(c.chars[0], 'x'); CHECK_INT(c.width, 1);
    char row[64]; pt_term_row_text(t, 0, row, sizeof row); CHECK_STR(row, "\xE4\xB8\xADx");
    pt_term_free(t);
}

PT_TEST(term_row_text_and_damage, "AC-SCREEN-1") {
    pt_term *t = mk(3, 10);
    pt_term_take_damage(t, NULL, NULL);
    feeds(t, "hello   \r\n  two");
    CHECK_INT(pt_term_take_damage(t, NULL, NULL), 1);
    CHECK_INT(pt_term_take_damage(t, NULL, NULL), 0);
    char row[32];
    pt_term_row_text(t, 0, row, sizeof row); CHECK_STR(row, "hello");
    pt_term_row_text(t, 1, row, sizeof row); CHECK_STR(row, "  two");
    pt_term_row_text(t, 2, row, sizeof row); CHECK_STR(row, "");
    char small[3]; CHECK_INT(pt_term_row_text(t, 0, small, sizeof small), PT_ERR_NOSPACE);
    CHECK_INT(pt_term_cell(t, 5, 0, &(pt_cell){0}), PT_ERR_INVALID);
    pt_term_free(t);
}

PT_TEST(term_replies_to_queries, "AC-SCREEN-6") {
    pt_term *t = mk(10, 20);
    feeds(t, "\x1b[c");
    CHECK(g_out_len >= 4); CHECK(memcmp(g_out, "\x1b[?", 3) == 0); CHECK_INT(g_out[g_out_len - 1], 'c');
    g_out_len = 0;
    feeds(t, "\x1b[3;5H\x1b[6n");
    CHECK_MEM(g_out, g_out_len, "\x1b[3;5R");
    pt_term_free(t);
}

PT_TEST(term_resize, "AC-SCREEN-7") {
    pt_term *t = mk(24, 80);
    int r, c; pt_term_size(t, &r, &c); CHECK_INT(r, 24); CHECK_INT(c, 80);
    pt_term_resize(t, 40, 128); pt_term_size(t, &r, &c); CHECK_INT(r, 40); CHECK_INT(c, 128);
    pt_term_free(t);
}

PT_TEST(term_cursor, "AC-SCREEN-1") {
    pt_term *t = mk(10, 20);
    feeds(t, "\x1b[4;7H");
    pt_cursor cur; pt_term_cursor(t, &cur);
    CHECK_INT(cur.row, 3); CHECK_INT(cur.col, 6); CHECK(cur.visible);
    feeds(t, "\x1b[?25l"); pt_term_cursor(t, &cur); CHECK(!cur.visible);
    pt_term_free(t);
}

static int key_bytes(pt_term *t, pt_key k, const char *expected) {
    g_out_len = 0;
    if (pt_keys_send(t, k) != PT_OK) return 0;
    return g_out_len == strlen(expected) && memcmp(g_out, expected, g_out_len) == 0;
}

PT_TEST(keys_key_bar_bytes, "AC-INPUT-1") {
    pt_term *t = mk(10, 20);
    CHECK(key_bytes(t, PT_KEY_ESC, "\x1b"));
    CHECK(key_bytes(t, PT_KEY_TAB, "\t"));
    CHECK(key_bytes(t, PT_KEY_BACKTAB, "\x1b[Z"));
    CHECK(key_bytes(t, PT_KEY_ENTER, "\r"));
    CHECK(key_bytes(t, PT_KEY_UP, "\x1b[A"));
    CHECK(key_bytes(t, PT_KEY_DOWN, "\x1b[B"));
    CHECK(key_bytes(t, PT_KEY_RIGHT, "\x1b[C"));
    CHECK(key_bytes(t, PT_KEY_LEFT, "\x1b[D"));
    CHECK(key_bytes(t, PT_KEY_PAGEUP, "\x1b[5~"));
    CHECK(key_bytes(t, PT_KEY_PAGEDOWN, "\x1b[6~"));
    CHECK(key_bytes(t, PT_KEY_CTRL_C, "\x03"));
    CHECK_INT(pt_keys_send(t, PT_KEY_COUNT), PT_ERR_INVALID);
    pt_term_free(t);
}

PT_TEST(keys_follow_cursor_key_mode, "AC-INPUT-2") {
    pt_term *t = mk(10, 20);
    feeds(t, "\x1b[?1h"); /* DECCKM on: application cursor keys */
    CHECK(key_bytes(t, PT_KEY_UP, "\x1bOA"));
    CHECK(key_bytes(t, PT_KEY_LEFT, "\x1bOD"));
    feeds(t, "\x1b[?1l");
    CHECK(key_bytes(t, PT_KEY_UP, "\x1b[A"));
    pt_term_free(t);
}

PT_TEST(keys_text_utf8_and_ctrl, "AC-INPUT-3 AC-INPUT-1") {
    pt_term *t = mk(10, 20);
    g_out_len = 0; CHECK_INT(pt_keys_send_char(t, 'a', 0), PT_OK); CHECK_MEM(g_out, g_out_len, "a");
    g_out_len = 0; pt_keys_send_char(t, 0xE9, 0); CHECK_MEM(g_out, g_out_len, "\xC3\xA9");
    g_out_len = 0; pt_keys_send_char(t, 0x276F, 0); CHECK_MEM(g_out, g_out_len, "\xE2\x9D\xAF");
    g_out_len = 0; pt_keys_send_char(t, 'a', 1); CHECK_MEM(g_out, g_out_len, "\x01");
    g_out_len = 0; pt_keys_send_char(t, 'C', 1); CHECK_MEM(g_out, g_out_len, "\x03");
    g_out_len = 0; pt_keys_send_char(t, 'j', 1); CHECK_MEM(g_out, g_out_len, "\n");
    g_out_len = 0; pt_keys_send_char(t, '[', 1); CHECK_MEM(g_out, g_out_len, "\x1b");
    g_out_len = 0; pt_keys_send_char(t, 'i', 1); CHECK_MEM(g_out, g_out_len, "\t");
    g_out_len = 0; pt_keys_send_char(t, '\n', 0); CHECK_MEM(g_out, g_out_len, "\r");
    pt_term_free(t);
}

PT_TEST(paste_bracketed_only_when_asked, "AC-INPUT-4") {
    pt_term *t = mk(10, 20);
    g_out_len = 0; pt_term_paste(t, "hi", 2); CHECK_MEM(g_out, g_out_len, "hi");
    feeds(t, "\x1b[?2004h");
    g_out_len = 0; pt_term_paste(t, "hi", 2); CHECK_MEM(g_out, g_out_len, "\x1b[200~hi\x1b[201~");
    pt_term_free(t);
}

PT_TEST(mouse_only_in_mouse_mode, "AC-INPUT-5") {
    pt_term *t = mk(10, 20);
    CHECK_INT(pt_term_mouse_mode(t), 0);
    g_out_len = 0; pt_term_mouse_click(t, 2, 3); CHECK_INT(g_out_len, 0);
    feeds(t, "\x1b[?1000h\x1b[?1006h");
    CHECK_INT(pt_term_mouse_mode(t), 1);
    g_out_len = 0; pt_term_mouse_click(t, 2, 3); CHECK_MEM(g_out, g_out_len, "\x1b[<0;4;3M\x1b[<0;4;3m");
    g_out_len = 0; pt_term_mouse_wheel(t, 2, 3, 1); CHECK_MEM(g_out, g_out_len, "\x1b[<64;4;3M");
    g_out_len = 0; pt_term_mouse_wheel(t, 2, 3, -2); CHECK_MEM(g_out, g_out_len, "\x1b[<65;4;3M\x1b[<65;4;3M");
    pt_term_free(t);
}

PT_TEST(term_damage_rows, "AC-SCREEN-1") {
    pt_term *t = mk(10, 20);
    int top, bottom;
    feeds(t, "\x1b[3;1H");                 /* cursor to row 2 */
    pt_term_take_damage(t, NULL, NULL);
    feeds(t, "\x1b[5;1Hx");                /* cursor row 2 -> 4, write on row 4 */
    CHECK_INT(pt_term_take_damage(t, &top, &bottom), 1);
    CHECK_INT(top, 2); CHECK_INT(bottom, 5); /* old cursor row .. new row; rows 0-1 and 5-9 untouched */
    CHECK_INT(pt_term_take_damage(t, &top, &bottom), 0);
    pt_term_resize(t, 12, 20);
    CHECK_INT(pt_term_take_damage(t, &top, &bottom), 1);
    CHECK_INT(top, 0); CHECK_INT(bottom, 12);
    pt_term_free(t);
}

PT_TEST(paste_line_ends_and_escape, "AC-INPUT-4") {
    pt_term *t = mk(10, 20);
    g_out_len = 0; pt_term_paste(t, "a\r\nb\nc", 6); CHECK_MEM(g_out, g_out_len, "a\rb\rc");
    feeds(t, "\x1b[?2004h");
    g_out_len = 0; pt_term_paste(t, "x\x1b[201~y", 8);
    CHECK_MEM(g_out, g_out_len, "\x1b[200~x[201~y\x1b[201~"); /* the pasted ESC is gone; one real end marker */
    pt_term_free(t);
}

/* Malicious or odd server output must not hang or corrupt the terminal (review findings 1 and 2). */
PT_TEST(rep_without_previous_char_does_not_hang, "AC-SCREEN-1") {
    pt_term *t = mk(5, 10);
    feeds(t, "\x1b[b");          /* REP with nothing printed yet: was an endless loop */
    feeds(t, "ok");
    char row[64]; pt_term_row_text(t, 0, row, sizeof row); CHECK_STR(row, "ok");
    feeds(t, "\r\nA\x1b[3b");   /* normal REP still repeats */
    pt_term_row_text(t, 1, row, sizeof row); CHECK_STR(row, "AAAA");
    pt_term_free(t);
}

PT_TEST(rep_wide_char_at_last_column_stays_in_row, "AC-SCREEN-3") {
    pt_term *t = mk(3, 10);
    feeds(t, "\xE4\xB8\xAD\x1b[1;10H\x1b[b"); /* 中, cursor to last column, repeat: does not fit */
    pt_cell c;
    pt_term_cell(t, 1, 0, &c); CHECK_INT(c.width, 1); CHECK_INT(c.chars[0], 0); /* next row untouched */
    feeds(t, "\x1b[3;9H\xE4\xB8\xAD\x1b[3;10H\x1b[2b"); /* last row: nothing written past the screen */
    pt_term_cell(t, 2, 8, &c); CHECK_INT(c.chars[0], 0x4E2D);
    pt_term_free(t);
}
