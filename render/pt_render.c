#include "pt_render.h"
#include <dispatch/dispatch.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* Fallback fonts for characters that DejaVu Sans Mono does not have; small direct-mapped cache. */
enum { FALLBACK_SLOTS = 64 };

struct pt_render {
    CTFontRef regular, bold;
    double cw, ch, ascent, top_pad;
    struct { uint32_t cp; CTFontRef font; } fallback[FALLBACK_SLOTS];
};

static CTFontRef font_from_data(const void *data, size_t len, double size) {
    CFDataRef d = CFDataCreate(NULL, data, (CFIndex)len); /* copy: the caller may free its buffer */
    CGDataProviderRef p = CGDataProviderCreateWithCFData(d);
    CGFontRef g = CGFontCreateWithDataProvider(p);
    CTFontRef f = g ? CTFontCreateWithGraphicsFont(g, size, NULL, NULL) : NULL;
    if (g) CGFontRelease(g);
    CGDataProviderRelease(p);
    CFRelease(d);
    return f;
}

pt_render *pt_render_new(const void *regular, size_t regular_len, const void *bold, size_t bold_len, double point_size) {
    if (!regular || !bold || point_size <= 0) return NULL;
    pt_render *r = calloc(1, sizeof *r);
    if (!r) return NULL;
    r->regular = font_from_data(regular, regular_len, point_size);
    r->bold = font_from_data(bold, bold_len, point_size);
    if (!r->regular || !r->bold) { pt_render_free(r); return NULL; }
    UniChar m = 'M';
    CGGlyph g;
    CTFontGetGlyphsForCharacters(r->regular, &m, &g, 1);
    CGSize adv;
    CTFontGetAdvancesForGlyphs(r->regular, kCTFontOrientationHorizontal, &g, &adv, 1);
    double asc = CTFontGetAscent(r->regular), desc = CTFontGetDescent(r->regular), lead = CTFontGetLeading(r->regular);
    r->cw = ceil(adv.width);
    r->ch = ceil(asc + desc + lead);
    r->ascent = asc;
    r->top_pad = floor((r->ch - (asc + desc)) / 2);
    return r;
}

void pt_render_free(pt_render *r) {
    if (!r) return;
    if (r->regular) CFRelease(r->regular);
    if (r->bold) CFRelease(r->bold);
    for (int i = 0; i < FALLBACK_SLOTS; i++) if (r->fallback[i].font) CFRelease(r->fallback[i].font);
    free(r);
}

void pt_render_cell_size(const pt_render *r, double *w, double *h) { *w = r->cw; *h = r->ch; }

/* ---------------- shapes ---------------- */

/* Box drawing: weight of the up/right/down/left arm. 0 none, 1 light, 2 heavy, 3 double. */
typedef struct { uint16_t cp; uint8_t u, r, d, l; } box_def;
static const box_def BOX[] = {
    {0x2500, 0, 1, 0, 1}, {0x2501, 0, 2, 0, 2}, {0x2502, 1, 0, 1, 0}, {0x2503, 2, 0, 2, 0},
    {0x2504, 0, 1, 0, 1}, {0x2505, 0, 2, 0, 2}, {0x2506, 1, 0, 1, 0}, {0x2507, 2, 0, 2, 0},
    {0x2508, 0, 1, 0, 1}, {0x2509, 0, 2, 0, 2}, {0x250A, 1, 0, 1, 0}, {0x250B, 2, 0, 2, 0},
    {0x250C, 0, 1, 1, 0}, {0x250F, 0, 2, 2, 0}, {0x2510, 0, 0, 1, 1}, {0x2513, 0, 0, 2, 2},
    {0x2514, 1, 1, 0, 0}, {0x2517, 2, 2, 0, 0}, {0x2518, 1, 0, 0, 1}, {0x251B, 2, 0, 0, 2},
    {0x251C, 1, 1, 1, 0}, {0x2523, 2, 2, 2, 0}, {0x2524, 1, 0, 1, 1}, {0x252B, 2, 0, 2, 2},
    {0x252C, 0, 1, 1, 1}, {0x2533, 0, 2, 2, 2}, {0x2534, 1, 1, 0, 1}, {0x253B, 2, 2, 0, 2},
    {0x253C, 1, 1, 1, 1}, {0x254B, 2, 2, 2, 2},
    {0x254C, 0, 1, 0, 1}, {0x254D, 0, 2, 0, 2}, {0x254E, 1, 0, 1, 0}, {0x254F, 2, 0, 2, 0},
    {0x2550, 0, 3, 0, 3}, {0x2551, 3, 0, 3, 0}, {0x2554, 0, 3, 3, 0}, {0x2557, 0, 0, 3, 3},
    {0x255A, 3, 3, 0, 0}, {0x255D, 3, 0, 0, 3}, {0x2560, 3, 3, 3, 0}, {0x2563, 3, 0, 3, 3},
    {0x2566, 0, 3, 3, 3}, {0x2569, 3, 3, 0, 3}, {0x256C, 3, 3, 3, 3},
    {0x2574, 0, 0, 0, 1}, {0x2575, 1, 0, 0, 0}, {0x2576, 0, 1, 0, 0}, {0x2577, 0, 0, 1, 0},
    {0x2578, 0, 0, 0, 2}, {0x2579, 2, 0, 0, 0}, {0x257A, 0, 2, 0, 0}, {0x257B, 0, 0, 2, 0},
    /* Not box characters, but drawn the same way so they join their neighbours. */
    {0x23BF, 1, 1, 0, 0}, /* ⎿ (Claude Code tool-result line) */
    {0x23AF, 0, 1, 0, 1}, /* ⎯ */
};

static const box_def *find_box(uint32_t cp) {
    for (size_t i = 0; i < sizeof BOX / sizeof *BOX; i++) if (BOX[i].cp == cp) return &BOX[i];
    return NULL;
}

static int is_rounded(uint32_t cp) { return cp >= 0x256D && cp <= 0x2570; }
static int is_block(uint32_t cp) { return cp >= 0x2580 && cp <= 0x259F; }
static int is_symbol_shape(uint32_t cp) {
    return cp == 0x23F5 || cp == 0x23FA || cp == 0x23F8 || cp == 0x23F9 || cp == 0x29C9;
}

static int is_shape(uint32_t cp) { return find_box(cp) || is_rounded(cp) || is_block(cp) || is_symbol_shape(cp); }

int pt_render_coverage(const pt_render *r, uint32_t cp) {
    if (is_shape(cp)) return 2;
    UniChar u[2];
    int n = 1;
    if (cp >= 0x10000) {
        uint32_t v = cp - 0x10000;
        u[0] = (UniChar)(0xD800 + (v >> 10)); u[1] = (UniChar)(0xDC00 + (v & 0x3FF)); n = 2;
    } else {
        u[0] = (UniChar)cp;
    }
    CGGlyph g[2] = {0, 0};
    return CTFontGetGlyphsForCharacters(r->regular, u, g, n) && g[0] ? 1 : 0;
}

static void fill(CGContextRef ctx, double x, double y, double w, double h) { CGContextFillRect(ctx, CGRectMake(x, y, w, h)); }

/* Line thickness: 1/8 of the cell width, at least 1 point (1 px at the default 13 pt, cell 8x16). */
static double light_width(const pt_render *r) { double w = floor(r->cw / 8); return w < 1 ? 1 : w; }

static void draw_box(const pt_render *r, CGContextRef ctx, const box_def *b, double x, double y) {
    double lw = light_width(r), cw = r->cw, ch = r->ch;
    for (int arm = 0; arm < 4; arm++) {
        int wgt = arm == 0 ? b->u : arm == 1 ? b->r : arm == 2 ? b->d : b->l;
        if (!wgt) continue;
        double t = wgt == 2 ? 2 * lw : lw;
        double mx = x + floor((cw - t) / 2), my = y + floor((ch - t) / 2);
        int lines = wgt == 3 ? 2 : 1;
        for (int k = 0; k < lines; k++) {
            double off = lines == 2 ? (k == 0 ? -lw : lw) : 0;
            switch (arm) {
            case 0: fill(ctx, mx + off, y, t, my - y + t); break;                /* up: top edge to centre */
            case 1: fill(ctx, mx, my + off, x + cw - mx, t); break;              /* right: centre to right edge */
            case 2: fill(ctx, mx + off, my, t, y + ch - my); break;              /* down */
            case 3: fill(ctx, x, my + off, mx - x + t, t); break;                /* left */
            }
        }
    }
}

static void draw_rounded(const pt_render *r, CGContextRef ctx, uint32_t cp, double x, double y) {
    double lw = light_width(r), cw = r->cw, ch = r->ch;
    double cx = x + floor((cw - lw) / 2) + lw / 2, cy = y + floor((ch - lw) / 2) + lw / 2;
    double rad = (cw < ch ? cw : ch) / 2;
    CGContextSetLineWidth(ctx, lw);
    CGContextBeginPath(ctx);
    switch (cp) {
    case 0x256D: CGContextMoveToPoint(ctx, cx, y + ch); CGContextAddArcToPoint(ctx, cx, cy, x + cw, cy, rad); CGContextAddLineToPoint(ctx, x + cw, cy); break; /* ╭ */
    case 0x256E: CGContextMoveToPoint(ctx, cx, y + ch); CGContextAddArcToPoint(ctx, cx, cy, x, cy, rad); CGContextAddLineToPoint(ctx, x, cy); break;           /* ╮ */
    case 0x256F: CGContextMoveToPoint(ctx, cx, y); CGContextAddArcToPoint(ctx, cx, cy, x, cy, rad); CGContextAddLineToPoint(ctx, x, cy); break;                /* ╯ */
    case 0x2570: CGContextMoveToPoint(ctx, cx, y); CGContextAddArcToPoint(ctx, cx, cy, x + cw, cy, rad); CGContextAddLineToPoint(ctx, x + cw, cy); break;      /* ╰ */
    }
    CGContextStrokePath(ctx);
}

static void draw_block(const pt_render *r, CGContextRef ctx, uint32_t cp, double x, double y,
                       const double fg[3], const double bg[3]) {
    double cw = r->cw, ch = r->ch, hw = floor(cw / 2), hh = floor(ch / 2);
    if (cp == 0x2580) { fill(ctx, x, y, cw, hh); return; }                                 /* ▀ */
    if (cp >= 0x2581 && cp <= 0x2588) { double h = round(ch * (cp - 0x2580) / 8.0); fill(ctx, x, y + ch - h, cw, h); return; } /* ▁..█ */
    if (cp >= 0x2589 && cp <= 0x258F) { double w = round(cw * (0x2590 - cp) / 8.0); fill(ctx, x, y, w, ch); return; }          /* ▉..▏ */
    if (cp == 0x2590) { fill(ctx, x + hw, y, cw - hw, ch); return; }                       /* ▐ */
    if (cp >= 0x2591 && cp <= 0x2593) {                                                    /* ░ ▒ ▓: 1/4, 2/4, 3/4 */
        double a = (cp - 0x2590) / 4.0;
        CGContextSetRGBFillColor(ctx, bg[0] + (fg[0] - bg[0]) * a, bg[1] + (fg[1] - bg[1]) * a, bg[2] + (fg[2] - bg[2]) * a, 1);
        fill(ctx, x, y, cw, ch);
        return;
    }
    if (cp == 0x2594) { fill(ctx, x, y, cw, round(ch / 8.0)); return; }                    /* ▔ */
    if (cp == 0x2595) { double w = round(cw / 8.0); fill(ctx, x + cw - w, y, w, ch); return; } /* ▕ */
    /* Quadrants U+2596..U+259F: bit 0 upper-left, 1 upper-right, 2 lower-left, 3 lower-right. */
    static const uint8_t Q[] = {4, 8, 1, 1 | 4 | 8, 1 | 8, 1 | 2 | 4, 1 | 2 | 8, 2, 2 | 4, 2 | 4 | 8};
    uint8_t q = Q[cp - 0x2596];
    if (q & 1) fill(ctx, x, y, hw, hh);
    if (q & 2) fill(ctx, x + hw, y, cw - hw, hh);
    if (q & 4) fill(ctx, x, y + hh, hw, ch - hh);
    if (q & 8) fill(ctx, x + hw, y + hh, cw - hw, ch - hh);
}

/* Media-control symbols: the glyph box is 3/5 of the cell width, centred (close to DejaVu's ● size). */
static void draw_symbol(const pt_render *r, CGContextRef ctx, uint32_t cp, double x, double y) {
    double s = round(r->cw * 3 / 5), lw = light_width(r);
    double sx = x + floor((r->cw - s) / 2), sy = y + floor((r->ch - s) / 2);
    switch (cp) {
    case 0x23F5: /* ⏵ */
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, sx, sy); CGContextAddLineToPoint(ctx, sx + s, sy + s / 2); CGContextAddLineToPoint(ctx, sx, sy + s);
        CGContextClosePath(ctx); CGContextFillPath(ctx); break;
    case 0x23FA: CGContextFillEllipseInRect(ctx, CGRectMake(sx, sy, s, s)); break; /* ⏺ */
    case 0x23F9: fill(ctx, sx, sy, s, s); break;                                  /* ⏹ */
    case 0x23F8: { double b = floor(s / 3); fill(ctx, sx, sy, b, s); fill(ctx, sx + s - b, sy, b, s); break; } /* ⏸ */
    case 0x29C9: /* ⧉ two joined squares */
        CGContextSetLineWidth(ctx, lw);
        CGContextStrokeRect(ctx, CGRectMake(sx + lw / 2, sy + s / 3 + lw / 2, s * 2 / 3 - lw, s * 2 / 3 - lw));
        CGContextStrokeRect(ctx, CGRectMake(sx + s / 3 + lw / 2, sy + lw / 2, s * 2 / 3 - lw, s * 2 / 3 - lw));
        break;
    }
}

/* ---------------- glyphs ---------------- */

static CTFontRef font_for(pt_render *r, uint32_t cp, int bold, CGGlyph *glyph) {
    UniChar u[2];
    int n = 1;
    if (cp >= 0x10000) {
        uint32_t v = cp - 0x10000;
        u[0] = (UniChar)(0xD800 + (v >> 10)); u[1] = (UniChar)(0xDC00 + (v & 0x3FF)); n = 2;
    } else {
        u[0] = (UniChar)cp;
    }
    CGGlyph g[2] = {0, 0};
    CTFontRef base = bold ? r->bold : r->regular;
    if (CTFontGetGlyphsForCharacters(base, u, g, n) && g[0]) { *glyph = g[0]; return base; }
    int slot = (int)(cp % FALLBACK_SLOTS);
    if (r->fallback[slot].font && r->fallback[slot].cp == cp) {
        CTFontGetGlyphsForCharacters(r->fallback[slot].font, u, g, n);
        *glyph = g[0];
        return g[0] ? r->fallback[slot].font : NULL;
    }
    CFStringRef str = CFStringCreateWithCharacters(NULL, u, n);
    CTFontRef f = CTFontCreateForString(r->regular, str, CFRangeMake(0, n));
    CFRelease(str);
    if (!f) return NULL;
    if (r->fallback[slot].font) CFRelease(r->fallback[slot].font);
    r->fallback[slot].cp = cp;
    r->fallback[slot].font = f;
    if (!CTFontGetGlyphsForCharacters(f, u, g, n) || !g[0]) return NULL;
    *glyph = g[0];
    return f;
}

void pt_render_prewarm_font_search(pt_render *r) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CTFontRef base = (CTFontRef)CFRetain(r->regular); /* the renderer may be freed first */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            /* U+1F9EA is newer than any font on iOS 6: it forces the full search. */
            static const UniChar none[2] = {0xD83E, 0xDDEA};
            CFStringRef str = CFStringCreateWithCharacters(NULL, none, 2);
            CTFontRef f = CTFontCreateForString(base, str, CFRangeMake(0, 2));
            if (f) CFRelease(f);
            CFRelease(str);
            CFRelease(base);
        });
    });
}

static void draw_glyph(pt_render *r, CGContextRef ctx, uint32_t cp, int bold, int italic, double x, double y) {
    CGGlyph g;
    CTFontRef f = font_for(r, cp, bold, &g);
    if (!f) return;
    /* ctx is y-down: flip the text matrix; italic = 0.2 shear, the slant of DejaVu Sans Mono Oblique (11°).
     * Glyph positions are in text space, so the baseline point goes into the matrix and the glyph is drawn
     * at (0, 0); a position given to CTFontDrawGlyphs would be flipped off the image too. */
    CGAffineTransform m = CGAffineTransformMake(1, 0, italic ? -0.2 : 0, -1, x, y + r->top_pad + r->ascent);
    CGContextSetTextMatrix(ctx, m);
    CGPoint pos = CGPointZero;
    CTFontDrawGlyphs(f, &g, &pos, 1, ctx);
}

/* ---------------- screen ---------------- */

static void rgbd(const uint8_t c[3], double o[3]) { o[0] = c[0] / 255.0; o[1] = c[1] / 255.0; o[2] = c[2] / 255.0; }

void pt_render_draw(pt_render *r, CGContextRef ctx, const pt_term *t, const uint8_t bg[3]) {
    int rows, cols;
    pt_term_size(t, &rows, &cols);
    double cw = r->cw, ch = r->ch, bgd[3];
    rgbd(bg, bgd);
    /* Draw only the rows inside the clip: the view asks for the changed rows (setNeedsDisplayInRect). */
    CGRect clip = CGContextGetClipBoundingBox(ctx);
    int row0 = (int)floor(CGRectGetMinY(clip) / ch), row1 = (int)ceil(CGRectGetMaxY(clip) / ch);
    if (row0 < 0) row0 = 0;
    if (row1 > rows) row1 = rows;
    CGContextSetRGBFillColor(ctx, bgd[0], bgd[1], bgd[2], 1);
    fill(ctx, 0, row0 * ch, cols * cw, (row1 - row0) * ch);
    pt_cursor cur;
    pt_term_cursor(t, &cur);
    for (int row = row0; row < row1; row++) {
        for (int col = 0; col < cols; col++) {
            pt_cell c;
            if (pt_term_cell(t, row, col, &c) != 0 || c.width == 0) continue;
            double x = col * cw, y = row * ch, w = cw * (c.width > 1 ? c.width : 1);
            double fg[3], cb[3];
            rgbd(c.fg, fg);
            if (c.bg_default) memcpy(cb, bgd, sizeof cb); else rgbd(c.bg, cb);
            int inverse = c.reverse;
            int is_cursor = cur.visible && cur.row == row && cur.col == col && cur.shape == 1;
            if (is_cursor) inverse = !inverse;
            if (inverse) { double tmp[3]; memcpy(tmp, fg, sizeof tmp); memcpy(fg, cb, sizeof fg); memcpy(cb, tmp, sizeof cb); }
            if (c.dim) /* faint: 65% of the way from background to foreground; 50% was hard to read on this 163 ppi screen */
                for (int i = 0; i < 3; i++) fg[i] = cb[i] + (fg[i] - cb[i]) * 0.65;
            if (inverse || !c.bg_default) {
                CGContextSetRGBFillColor(ctx, cb[0], cb[1], cb[2], 1);
                fill(ctx, x, y, w, ch);
            }
            uint32_t cp = c.chars[0];
            CGContextSetRGBFillColor(ctx, fg[0], fg[1], fg[2], 1);
            CGContextSetRGBStrokeColor(ctx, fg[0], fg[1], fg[2], 1);
            if (cp && cp != ' ') {
                const box_def *b = find_box(cp);
                if (b || is_block(cp)) {
                    CGContextSetShouldAntialias(ctx, false); /* whole-pixel fills so lines join exactly */
                    if (b) draw_box(r, ctx, b, x, y); else draw_block(r, ctx, cp, x, y, fg, cb);
                    CGContextSetShouldAntialias(ctx, true);
                } else if (is_rounded(cp)) {
                    draw_rounded(r, ctx, cp, x, y);
                } else if (is_symbol_shape(cp)) {
                    draw_symbol(r, ctx, cp, x, y);
                } else {
                    for (int i = 0; i < PT_CELL_MAX_CHARS && c.chars[i]; i++) draw_glyph(r, ctx, c.chars[i], c.bold, c.italic, x, y);
                }
            }
            double lw = light_width(r);
            if (c.underline) fill(ctx, x, y + r->top_pad + r->ascent + lw, w, lw);
            if (c.strike) fill(ctx, x, y + floor(ch / 2), w, lw);
            if (cur.visible && cur.row == row && cur.col == col && cur.shape != 1) {
                rgbd(c.fg, fg);
                CGContextSetRGBFillColor(ctx, fg[0], fg[1], fg[2], 1);
                if (cur.shape == 2) fill(ctx, x, y + ch - 2 * lw, cw, 2 * lw); /* underline cursor */
                else fill(ctx, x, y, 2 * lw, ch);                              /* bar cursor */
            }
        }
    }
}
