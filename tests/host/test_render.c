#include "pt_test.h"
#include "../../core/pt_error.h"
#include "../../core/pt_term.h"
#include "../../render/pt_render.h"
#include <stdlib.h>
#include <ImageIO/ImageIO.h>

static void *slurp(const char *path, size_t *len) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    void *b = malloc((size_t)n); if (fread(b, 1, (size_t)n, f) != (size_t)n) { free(b); b = NULL; }
    fclose(f); *len = (size_t)n; return b;
}

static pt_render *mk_render(double pt) {
    size_t rl, bl;
    void *r = slurp("assets/fonts/DejaVuSansMono.ttf", &rl), *b = slurp("assets/fonts/DejaVuSansMono-Bold.ttf", &bl);
    if (!r || !b) return NULL;
    pt_render *re = pt_render_new(r, rl, b, bl, pt);
    free(r); free(b);
    return re;
}

/* Characters seen in Claude Code 2.x and Codex 0.16x screens (captured 2026-11-03) plus the status set. */
static const uint32_t AGENT_CHARS[] = {
    0x25CF, 0x23BF, 0x276F, 0x273B, 0x23F5, 0x23FA, 0x2736, 0x2733, 0x2722, 0x00B7, 0x2713, 0x2717, 0x2718,
    0x2193, 0x2191, 0x2192, 0x2190, 0x26A0, 0x23AF, 0x25AA, 0x25B8, 0x25B6, 0x25C6, 0x25C7, 0x25A0, 0x25A1,
    0x2590, 0x258C, 0x2580, 0x2584, 0x2588, 0x2591, 0x2592, 0x2593, 0x256D, 0x256E, 0x256F, 0x2570, 0x2500,
    0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524, 0x252C, 0x2534, 0x253C, 0x2501, 0x2503, 0x2550,
    0x2551, 0x2022, 0x203A, 0x23F8, 0x23F9, 0x29C9, 0x23CE};
/* Not in DejaVu Sans Mono 2.37 (checked with CTFontGetGlyphsForCharacters on 2026-11-03). */
static const uint32_t SHAPE_ONLY[] = {0x23BF, 0x23F5, 0x23FA, 0x23AF, 0x23F8, 0x23F9, 0x29C9};

PT_TEST(render_agent_glyph_coverage, "AC-SCREEN-4") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    for (size_t i = 0; i < sizeof AGENT_CHARS / sizeof *AGENT_CHARS; i++) {
        if (pt_render_coverage(r, AGENT_CHARS[i]) == 0) { pt_test_fail(__FILE__, __LINE__, "no glyph for U+%04X", AGENT_CHARS[i]); break; }
    }
    for (size_t i = 0; i < sizeof SHAPE_ONLY / sizeof *SHAPE_ONLY; i++)
        if (pt_render_coverage(r, SHAPE_ONLY[i]) != 2) { pt_test_fail(__FILE__, __LINE__, "U+%04X must be a shape", SHAPE_ONLY[i]); break; }
    CHECK_INT(pt_render_coverage(r, 'A'), 1);
    CHECK_INT(pt_render_coverage(r, 0x2500), 2);
    CHECK_INT(pt_render_coverage(r, 0x2588), 2);
    pt_render_free(r);
}

PT_TEST(render_cell_size_whole_points, "AC-SCREEN-7") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    double w, h; pt_render_cell_size(r, &w, &h);
    CHECK(w >= 6 && w <= 10); CHECK(h >= 13 && h <= 20);
    CHECK(w == (double)(long)w); CHECK(h == (double)(long)h);
    pt_render_free(r);
    r = mk_render(20); double w2, h2; pt_render_cell_size(r, &w2, &h2);
    CHECK(w2 > w); CHECK(h2 > h);
    pt_render_free(r);
}

typedef struct { int W, H, cw, ch; uint8_t *px; } shot;

static shot draw(pt_render *r, pt_term *t, const uint8_t bg[3]) {
    double w, h; pt_render_cell_size(r, &w, &h);
    int rows, cols; pt_term_size(t, &rows, &cols);
    shot s = {cols * (int)w, rows * (int)h, (int)w, (int)h, NULL};
    s.px = calloc((size_t)s.W * s.H, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(s.px, s.W, s.H, 8, s.W * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(ctx, 0, s.H); CGContextScaleCTM(ctx, 1, -1);
    pt_render_draw(r, ctx, t, bg);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return s;
}
static const uint8_t *P(shot *s, int x, int y) { return s->px + ((size_t)y * s->W + x) * 4; }
static int is(shot *s, int x, int y, const uint8_t c[3]) { const uint8_t *p = P(s, x, y); return p[0] == c[0] && p[1] == c[1] && p[2] == c[2]; }
static int cell_all(shot *s, int row, int col, const uint8_t c[3]) {
    for (int y = row * s->ch; y < (row + 1) * s->ch; y++)
        for (int x = col * s->cw; x < (col + 1) * s->cw; x++) if (!is(s, x, y, c)) return 0;
    return 1;
}
static int cell_any_not(shot *s, int row, int col, const uint8_t c[3]) { return !cell_all(s, row, col, c); }
/* A pixel row y with every pixel fg across cells [col0, col1]. */
static int has_full_row(shot *s, int row, int col0, int col1, const uint8_t c[3]) {
    for (int y = row * s->ch; y < (row + 1) * s->ch; y++) {
        int ok = 1;
        for (int x = col0 * s->cw; x < (col1 + 1) * s->cw && ok; x++) ok = is(s, x, y, c);
        if (ok) return 1;
    }
    return 0;
}
static int has_full_col(shot *s, int col, int row0, int row1, const uint8_t c[3]) {
    for (int x = col * s->cw; x < (col + 1) * s->cw; x++) {
        int ok = 1;
        for (int y = row0 * s->ch; y < (row1 + 1) * s->ch && ok; y++) ok = is(s, x, y, c);
        if (ok) return 1;
    }
    return 0;
}

static const uint8_t BLACK[3] = {0, 0, 0}, WHITE[3] = {255, 255, 255}, RED[3] = {200, 0, 0}, GREEN[3] = {0, 200, 0};

static pt_term *themed(int rows, int cols) {
    pt_term *t = pt_term_new(rows, cols, NULL, NULL);
    uint8_t ansi[16][3] = {{0}};
    memcpy(ansi[1], RED, 3); memcpy(ansi[2], GREEN, 3);
    pt_term_set_colors(t, WHITE, BLACK, (const uint8_t (*)[3])ansi);
    return t;
}

PT_TEST(render_backgrounds_blocks_reverse, "AC-SCREEN-1 AC-SCREEN-5") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = themed(2, 6);
    /* col0: red bg space, col1: green full block, col2: plain space, col3: reverse space, col4: 'A' */
    const char *s = "\x1b[41m \x1b[0m\x1b[32m\xE2\x96\x88\x1b[0m \x1b[7m \x1b[0mA";
    pt_term_feed(t, s, strlen(s));
    pt_term_feed(t, "\x1b[?25l", 6); /* hide the cursor so it does not paint a cell */
    shot sh = draw(r, t, BLACK);
    CHECK(cell_all(&sh, 0, 0, RED));
    CHECK(cell_all(&sh, 0, 1, GREEN));
    CHECK(cell_all(&sh, 0, 2, BLACK));
    CHECK(cell_all(&sh, 0, 3, WHITE));
    CHECK(cell_any_not(&sh, 0, 4, BLACK));
    free(sh.px); pt_term_free(t); pt_render_free(r);
}

PT_TEST(render_box_lines_connect, "AC-SCREEN-5") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = themed(3, 6);
    /* row0: ╭──╮  row1: │  │  row2: ╰──╯ */
    const char *s = "\xE2\x95\xAD\xE2\x94\x80\xE2\x94\x80\xE2\x95\xAE\r\n"
                    "\xE2\x94\x82  \xE2\x94\x82\r\n"
                    "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80\xE2\x95\xAF\x1b[?25l";
    pt_term_feed(t, s, strlen(s));
    shot sh = draw(r, t, BLACK);
    CHECK(has_full_row(&sh, 0, 1, 2, WHITE));  /* ── joins across the cell edge */
    CHECK(has_full_row(&sh, 2, 1, 2, WHITE));
    CHECK(has_full_col(&sh, 0, 1, 1, WHITE));  /* │ spans the full cell height */
    CHECK(has_full_col(&sh, 3, 1, 1, WHITE));
    for (int x = sh.cw; x < 3 * sh.cw; x++) CHECK(is(&sh, x, 0, BLACK)); /* top pixel row of ─ is background */
    CHECK(cell_all(&sh, 1, 1, BLACK));
    free(sh.px); pt_term_free(t); pt_render_free(r);
}

PT_TEST(render_shape_glyphs_visible, "AC-SCREEN-4") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = themed(1, 8);
    const char *s = "\xE2\x8E\xBF\xE2\x8F\xB5\xE2\x8F\xBA\xE2\x8E\xAF\xE2\x8F\xB8\xE2\x8F\xB9\xE2\xA7\x89\x1b[?25l";
    pt_term_feed(t, s, strlen(s));
    shot sh = draw(r, t, BLACK);
    for (int col = 0; col < 7; col++) if (!cell_any_not(&sh, 0, col, BLACK)) { pt_test_fail(__FILE__, __LINE__, "shape cell %d is empty", col); break; }
    CHECK(cell_all(&sh, 0, 7, BLACK));
    free(sh.px); pt_term_free(t); pt_render_free(r);
}

PT_TEST(render_dim_is_65_percent, "AC-SCREEN-1") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = themed(1, 3);
    const char *s = "\x1b[2m\xE2\x96\x88\x1b[0m\x1b[?25l"; /* a dim full block on black: 255 * 0.65 = 165.75 */
    pt_term_feed(t, s, strlen(s));
    shot sh = draw(r, t, BLACK);
    const uint8_t *p = P(&sh, sh.cw / 2, sh.ch / 2);
    CHECK(p[0] >= 165 && p[0] <= 166);
    free(sh.px); pt_term_free(t); pt_render_free(r);
}

PT_TEST(render_only_clipped_rows, "AC-SCREEN-1") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = themed(3, 4);
    pt_term_feed(t, "\x1b[?25l", 6);
    double w, h; pt_render_cell_size(r, &w, &h);
    int W = 4 * (int)w, H = 3 * (int)h;
    uint8_t *px = malloc((size_t)W * H * 4);
    for (int i = 0; i < W * H; i++) { px[i * 4] = 1; px[i * 4 + 1] = 2; px[i * 4 + 2] = 3; px[i * 4 + 3] = 255; } /* marker */
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(ctx, 0, H); CGContextScaleCTM(ctx, 1, -1);
    CGContextClipToRect(ctx, CGRectMake(0, h, W, h)); /* row 1 only */
    pt_render_draw(r, ctx, t, BLACK);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    shot sh = {W, H, (int)w, (int)h, px};
    static const uint8_t MARK[3] = {1, 2, 3};
    CHECK(cell_all(&sh, 0, 0, MARK)); CHECK(cell_all(&sh, 2, 3, MARK)); /* rows 0 and 2 not touched */
    CHECK(cell_all(&sh, 1, 0, BLACK)); CHECK(cell_all(&sh, 1, 3, BLACK));
    free(px); pt_term_free(t); pt_render_free(r);
}

/* Writes tests/artifacts/render_sample.png for a human look; checks only that it was written. */
PT_TEST(render_sample_png, "AC-SCREEN-1 AC-SCREEN-4") {
    pt_render *r = mk_render(13); CHECK(r != NULL);
    pt_term *t = pt_term_new(12, 64, NULL, NULL);
    const char *s =
        "\x1b[38;2;215;119;87m\xE2\x97\x8F\x1b[0m Read(\x1b[1msrc/app.ts\x1b[0m)\r\n"
        "  \xE2\x8E\xBF  Read \x1b[1m42\x1b[0m lines \x1b[2m(ctrl+o to expand)\x1b[0m\r\n"
        "\x1b[32m+ added line\x1b[0m  \x1b[31m- removed line\x1b[0m  \x1b[3mitalic\x1b[0m \x1b[4munder\x1b[0m\r\n"
        "\xE2\x95\xAD\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x95\xAE\r\n"
        "\xE2\x94\x82 \xE2\x9D\xAF hi   \xE2\x94\x82  \xE2\x8F\xB5\xE2\x8F\xB5 accept edits  \xE2\x9C\xBB Thinking\xE2\x80\xA6\r\n"
        "\xE2\x95\xB0\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x94\x80\xE2\x95\xAF\r\n"
        "\xE2\x80\xBA 1. Update now   \xE2\x80\xA2 codex   \xE2\x8F\xBA \xE2\x8F\xB8 \xE2\x8F\xB9 \xE2\xA7\x89 \xE2\x8E\xAF\xE2\x8E\xAF\r\n"
        "\x1b[48;5;236m 256 bg \x1b[0m \x1b[38;5;208morange\x1b[0m \xE4\xB8\xAD\xE6\x96\x87 \xC3\xA9 \xE2\x96\x80\xE2\x96\x84\xE2\x96\x88\xE2\x96\x91\xE2\x96\x92\xE2\x96\x93\r\n";
    pt_term_feed(t, s, strlen(s));
    static const uint8_t bg[3] = {30, 30, 30};
    shot sh = draw(r, t, bg);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(sh.px, sh.W, sh.H, 8, sh.W * 4, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, CFSTR("tests/artifacts/render_sample.png"), kCFURLPOSIXPathStyle, false);
    CGImageDestinationRef d = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    CHECK(d != NULL);
    CGImageDestinationAddImage(d, img, NULL);
    CHECK(CGImageDestinationFinalize(d));
    CFRelease(d); CFRelease(url); CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
    free(sh.px); pt_term_free(t); pt_render_free(r);
}
