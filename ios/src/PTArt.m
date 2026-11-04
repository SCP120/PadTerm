/* Code-drawn art (docs/design/ios6-nostalgia-ui.md). The recipes are plain CoreGraphics C with a top-left origin, so
 * tools/make_art.c compiles this file with -DPT_ART_HOST to draw the launch images and a preview sheet from the same code.
 * The UIKit wrappers at the bottom cache one UIImage per recipe. */
#ifdef PT_ART_HOST
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <sys/param.h>
#else
#import "PTArt.h"
#endif

typedef struct { uint32_t hex; CGFloat a, at; } stop;
#define COUNT(a) ((int)(sizeof(a) / sizeof((a)[0])))

static void fill(CGContextRef c, uint32_t h, CGFloat a) {
    CGContextSetRGBFillColor(c, ((h >> 16) & 255) / 255.0, ((h >> 8) & 255) / 255.0, (h & 255) / 255.0, a);
}
static void ink(CGContextRef c, uint32_t h, CGFloat a) {
    CGContextSetRGBStrokeColor(c, ((h >> 16) & 255) / 255.0, ((h >> 8) & 255) / 255.0, (h & 255) / 255.0, a);
}
static uint32_t mix(uint32_t a, uint32_t b, CGFloat t) {
    uint32_t out = 0;
    for (int s = 16; s >= 0; s -= 8) out |= (uint32_t)(((a >> s) & 255) * (1 - t) + ((b >> s) & 255) * t) << s;
    return out;
}
static void rect(CGContextRef c, uint32_t h, CGFloat a, CGFloat x, CGFloat y, CGFloat w, CGFloat ht) {
    fill(c, h, a);
    CGContextFillRect(c, CGRectMake(x, y, w, ht));
}
/* Rounded rectangle with the top and/or bottom corners rounded. */
static void rrect2(CGContextRef c, CGRect r, CGFloat k, int top, int bottom) {
    CGFloat x0 = CGRectGetMinX(r), y0 = CGRectGetMinY(r), x1 = CGRectGetMaxX(r), y1 = CGRectGetMaxY(r);
    CGFloat kt = top ? k : 0, kb = bottom ? k : 0;
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, x0 + kt, y0);
    CGContextAddArcToPoint(c, x1, y0, x1, y1, kt);
    CGContextAddArcToPoint(c, x1, y1, x0, y1, kb);
    CGContextAddArcToPoint(c, x0, y1, x0, y0, kb);
    CGContextAddArcToPoint(c, x0, y0, x1, y0, kt);
    CGContextClosePath(c);
}
static void rrect(CGContextRef c, CGRect r, CGFloat k) { rrect2(c, r, k, 1, 1); }
/* Vertical gradient over r; the caller clips to a shape first. */
static void vgrad(CGContextRef c, CGRect r, const stop *s, int n) {
    CGFloat comp[12 * 4], loc[12];
    for (int i = 0; i < n; i++) {
        comp[i * 4] = ((s[i].hex >> 16) & 255) / 255.0;
        comp[i * 4 + 1] = ((s[i].hex >> 8) & 255) / 255.0;
        comp[i * 4 + 2] = (s[i].hex & 255) / 255.0;
        comp[i * 4 + 3] = s[i].a;
        loc[i] = s[i].at;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comp, loc, (size_t)n);
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, r.origin.y), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

/* The stock iPad navigation bar, 44 rows, row-averaged from settings.png column x = 450, y = 20 + row:
 * 0 #FFFFFF, 3 #F4F5F7, 12 #F0F1F3, 18 #E6E7EB, 24 #D8DAE0, 30 #C7CAD3, 36 #B3B7C2, 42 #A8ACB9, 43 #797F90. Used for the launch images only. */
void pt_art_silver_bar(CGContextRef c, CGFloat w) {
    static const stop s[] = {{0xFFFFFF, 1, 0}, {0xF4F5F7, 1, 3.0 / 44}, {0xF0F1F3, 1, 12.0 / 44}, {0xE6E7EB, 1, 18.0 / 44},
                             {0xD8DAE0, 1, 24.0 / 44}, {0xC7CAD3, 1, 30.0 / 44}, {0xB3B7C2, 1, 36.0 / 44}, {0xA8ACB9, 1, 42.0 / 44},
                             {0x797F90, 1, 43.0 / 44}, {0x797F90, 1, 1}};
    vgrad(c, CGRectMake(0, 0, w, 44), s, COUNT(s));
    /* Below the bar, settings.png y = 64 to 67: #BABDC1 #CFD1D6 #DCDFE4 #E2E5EA. */
    rect(c, 0xBABDC1, 1, 0, 44, w, 1);
    rect(c, 0xCFD1D6, 1, 0, 45, w, 1);
    rect(c, 0xDCDFE4, 1, 0, 46, w, 1);
}
/* Launch-image panes. The master of the home screen is a plain white table; the detail is the stock grouped background
 * (settings.png x = 700: #E2E5EA at y = 90, #D3D5DB at y = 900). */
void pt_art_launch_body(CGContextRef c, CGFloat w, CGFloat h) {
    static const stop detail[] = {{0xE2E5EA, 1, 0}, {0xD3D5DB, 1, 1}};
    vgrad(c, CGRectMake(320, 0, w - 320, h), detail, 2);
    rect(c, 0xFFFFFF, 1, 0, 0, 320, h);
}

/* iOS 6 icon family: dark or coloured tile with the gloss cap and a dark rim. 80 pt design size; scaled by the caller. */
static void tile_body(CGContextRef c, const stop *body, int n) {
    CGContextSaveGState(c);
    rrect(c, CGRectMake(0, 0, 80, 80), 15);
    CGContextClip(c);
    vgrad(c, CGRectMake(0, 0, 80, 80), body, n);
    CGContextRestoreGState(c);
}
void pt_art_icon_gloss(CGContextRef c) {
    static const stop gloss[] = {{0xFFFFFF, 0.34, 0}, {0xFFFFFF, 0.10, 1}};
    CGContextSaveGState(c);
    rrect(c, CGRectMake(0.5, 0.5, 79, 79), 14.5);
    CGContextClip(c);
    CGContextAddEllipseInRect(c, CGRectMake(-30, -56, 140, 100));
    CGContextClip(c);
    vgrad(c, CGRectMake(0, 0, 80, 44), gloss, 2);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 1);
    ink(c, 0x000000, 0.5);
    rrect(c, CGRectMake(0.5, 0.5, 79, 79), 14.5);
    CGContextStrokePath(c);
}
/* agent: 0 Claude, 1 Codex, 2 Shell (pt_agent). Shell gets `>_`. The others get the cat from pt_art_agent_glyph on their own colour. */
void pt_art_agent_tile(CGContextRef c, int agent) {
    static const stop dark[] = {{0x2C2C31, 1, 0}, {0x151518, 1, 1}};
    static const stop plum[] = {{0xB98CF5, 1, 0}, {0x5A1E9C, 1, 1}};
    static const stop cool[] = {{0x5FD0F7, 1, 0}, {0x1259B8, 1, 1}};
    tile_body(c, agent == 0 ? plum : agent == 1 ? cool : dark, 2);
    if (agent != 2) return;
    CGContextSetLineWidth(c, 5);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    ink(c, 0xF1E8D8, 1);
    CGContextMoveToPoint(c, 20, 26);
    CGContextAddLineToPoint(c, 38, 40);
    CGContextAddLineToPoint(c, 20, 54);
    CGContextMoveToPoint(c, 44, 56);
    CGContextAddLineToPoint(c, 62, 56);
    CGContextStrokePath(c);
}
/* PadTerm's one mascot: an orange tabby with terminal-green eyes, peeking over an old iPad. Style from the iPhone games and apps
 * of 2010 to 2012: one glossy cartoon character, huge eyes, a dark ink line, a loud background. Canvas: 100 x 100. */
static void rgrad(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat r, const stop *s, int n) {
    CGFloat comp[12 * 4], loc[12];
    for (int i = 0; i < n; i++) {
        comp[i * 4] = ((s[i].hex >> 16) & 255) / 255.0;
        comp[i * 4 + 1] = ((s[i].hex >> 8) & 255) / 255.0;
        comp[i * 4 + 2] = (s[i].hex & 255) / 255.0;
        comp[i * 4 + 3] = s[i].a;
        loc[i] = s[i].at;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comp, loc, (size_t)n);
    CGContextDrawRadialGradient(c, g, CGPointMake(cx, cy), 0, CGPointMake(cx, cy), r, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}
static const uint32_t kCatInk = 0x3A1A06;
static void cat_head_path(CGContextRef c) {
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 50, 14);
    CGContextAddCurveToPoint(c, 45, 14, 40, 15, 36, 17);
    CGContextAddLineToPoint(c, 17, 3);
    CGContextAddQuadCurveToPoint(c, 12, 0, 11, 6);
    CGContextAddLineToPoint(c, 9, 34);
    CGContextAddCurveToPoint(c, 6, 40, 5, 46, 6, 51);
    CGContextAddLineToPoint(c, 1, 57);
    CGContextAddLineToPoint(c, 8, 60);
    CGContextAddLineToPoint(c, 5, 67);
    CGContextAddLineToPoint(c, 15, 66);
    CGContextAddCurveToPoint(c, 24, 75, 38, 79, 50, 79);
    CGContextAddCurveToPoint(c, 62, 79, 76, 75, 85, 66);
    CGContextAddLineToPoint(c, 95, 67);
    CGContextAddLineToPoint(c, 92, 60);
    CGContextAddLineToPoint(c, 99, 57);
    CGContextAddLineToPoint(c, 94, 51);
    CGContextAddCurveToPoint(c, 95, 46, 94, 40, 91, 34);
    CGContextAddLineToPoint(c, 89, 6);
    CGContextAddQuadCurveToPoint(c, 88, 0, 83, 3);
    CGContextAddLineToPoint(c, 64, 17);
    CGContextAddCurveToPoint(c, 60, 15, 55, 14, 50, 14);
    CGContextClosePath(c);
}
static void cat_ear(CGContextRef c, CGFloat m) { /* m = 1 left, -1 right: x mirrors around 50 */
    static const stop pink[] = {{0xFFD0D8, 1, 0}, {0xF0849C, 1, 1}};
    CGContextSaveGState(c);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 50 + m * (18 - 50), 12);
    CGContextAddLineToPoint(c, 50 + m * (15 - 50), 31);
    CGContextAddLineToPoint(c, 50 + m * (31 - 50), 21);
    CGContextClosePath(c);
    CGContextClip(c);
    vgrad(c, CGRectMake(0, 10, 100, 22), pink, 2);
    CGContextRestoreGState(c);
}
static void cat_eye(CGContextRef c, CGFloat x, CGFloat lid) {
    static const stop iris[] = {{0xE8FF8A, 1, 0}, {0x7BEA4C, 1, 0.5}, {0x12A63C, 1, 1}};
    CGRect e = CGRectMake(x - 15, 24, 30, 32);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, e);
    CGContextClip(c);
    rgrad(c, x, 46, 22, iris, 3);
    fill(c, 0x0B0806, 1); /* the wide pupil of a cat that is up to something */
    CGContextFillEllipseInRect(c, CGRectMake(x - 8.5, 28, 17, 26));
    /* the upper lid, slanted to the middle */
    fill(c, 0xD97A14, 1);
    CGContextMoveToPoint(c, x - 18, 20);
    CGContextAddLineToPoint(c, x + 18, 20);
    CGContextAddLineToPoint(c, x + 18, 29 + lid * 3);
    CGContextAddLineToPoint(c, x - 18, 29 - lid * 3);
    CGContextClosePath(c);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 2.2);
    ink(c, kCatInk, 1);
    CGContextStrokeEllipseInRect(c, e);
    fill(c, 0xFFFFFF, 1);
    CGContextFillEllipseInRect(c, CGRectMake(x - 7, 31, 8, 9));
    fill(c, 0xFFFFFF, 0.85);
    CGContextFillEllipseInRect(c, CGRectMake(x + 2.5, 45, 3.6, 3.6));
}
static void cat_paw(CGContextRef c, CGFloat cx) {
    static const stop fur[] = {{0xFFFFFF, 1, 0}, {0xD8DCE6, 1, 1}};
    CGRect r = CGRectMake(cx - 12, 62, 24, 17);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, r);
    CGContextClip(c);
    vgrad(c, r, fur, 2);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 2.2);
    ink(c, kCatInk, 1);
    CGContextStrokeEllipseInRect(c, r);
    CGContextSetLineWidth(c, 1.5);
    for (int i = -1; i <= 1; i += 2) {
        CGContextMoveToPoint(c, cx + i * 4, 72);
        CGContextAddLineToPoint(c, cx + i * 4, 78);
    }
    CGContextStrokePath(c);
}
void pt_art_mascot(CGContextRef c) {
    static const stop coat[] = {{0xFFC877, 1, 0}, {0xF7941F, 1, 0.5}, {0xCB5C0D, 1, 1}};
    static const stop muzzle[] = {{0xFFFFFF, 1, 0}, {0xE2E5EE, 1, 1}};
    static const stop silver[] = {{0xF4F5F7, 1, 0}, {0xB6BAC2, 1, 1}};
    static const stop screen[] = {{0x1B2730, 1, 0}, {0x070B0F, 1, 1}};
    CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineWidth(c, 3);
    ink(c, kCatInk, 1);
    cat_head_path(c);
    CGContextStrokePath(c);
    CGContextSaveGState(c);
    cat_head_path(c);
    CGContextClip(c);
    rgrad(c, 40, 14, 74, coat, 3);
    /* tabby stripes: three on the forehead, three on each cheek */
    CGContextSetLineWidth(c, 3.4);
    ink(c, 0xA8480A, 0.95);
    CGContextMoveToPoint(c, 50, 15);
    CGContextAddLineToPoint(c, 50, 25);
    CGContextMoveToPoint(c, 41, 16);
    CGContextAddLineToPoint(c, 43, 24);
    CGContextMoveToPoint(c, 59, 16);
    CGContextAddLineToPoint(c, 57, 24);
    for (int i = 0; i < 3; i++) {
        CGContextMoveToPoint(c, 4, 46 + i * 7);
        CGContextAddLineToPoint(c, 14, 48 + i * 6.5);
        CGContextMoveToPoint(c, 96, 46 + i * 7);
        CGContextAddLineToPoint(c, 86, 48 + i * 6.5);
    }
    CGContextStrokePath(c);
    CGContextSaveGState(c);
    /* the white blaze and muzzle */
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 50, 30);
    CGContextAddLineToPoint(c, 57, 50);
    CGContextAddCurveToPoint(c, 76, 52, 76, 79, 50, 80);
    CGContextAddCurveToPoint(c, 24, 79, 24, 52, 43, 50);
    CGContextClosePath(c);
    CGContextClip(c);
    vgrad(c, CGRectMake(20, 30, 60, 50), muzzle, 2);
    CGContextRestoreGState(c);
    CGContextRestoreGState(c);
    cat_ear(c, 1);
    cat_ear(c, -1);
    /* shine on the head */
    static const stop shine[] = {{0xFFFFFF, 0.34, 0}, {0xFFFFFF, 0, 1}};
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(30, 14.5, 40, 12));
    CGContextClip(c);
    vgrad(c, CGRectMake(30, 14.5, 40, 12), shine, 2);
    CGContextRestoreGState(c);
    cat_eye(c, 27, 1);
    cat_eye(c, 73, -1);
    /* nose, mouth, one fang */
    fill(c, 0xFF6F91, 1);
    CGContextMoveToPoint(c, 45, 52);
    CGContextAddLineToPoint(c, 55, 52);
    CGContextAddLineToPoint(c, 50, 58);
    CGContextClosePath(c);
    CGContextFillPath(c);
    CGContextSetLineWidth(c, 1.9);
    ink(c, kCatInk, 1);
    CGContextMoveToPoint(c, 50, 58);
    CGContextAddLineToPoint(c, 50, 61);
    CGContextMoveToPoint(c, 38, 60);
    CGContextAddQuadCurveToPoint(c, 44, 66, 50, 61);
    CGContextAddQuadCurveToPoint(c, 56, 66, 62, 60);
    CGContextStrokePath(c);
    fill(c, 0xFFFFFF, 1);
    CGContextMoveToPoint(c, 41, 63.4);
    CGContextAddLineToPoint(c, 46, 63.6);
    CGContextAddLineToPoint(c, 43.2, 68);
    CGContextClosePath(c);
    CGContextDrawPath(c, kCGPathFillStroke);
    /* whiskers */
    CGContextSetLineWidth(c, 1.3);
    ink(c, 0xFFFFFF, 0.9);
    for (int i = 0; i < 3; i++) {
        CGContextMoveToPoint(c, 25, 57 + i * 3.4);
        CGContextAddLineToPoint(c, 2, 53 + i * 7);
        CGContextMoveToPoint(c, 75, 57 + i * 3.4);
        CGContextAddLineToPoint(c, 98, 53 + i * 7);
    }
    CGContextStrokePath(c);
    /* the old iPad, held in both paws */
    CGRect pad = CGRectMake(12, 68, 76, 31);
    CGContextSaveGState(c);
    rrect(c, pad, 6);
    CGContextClip(c);
    vgrad(c, pad, silver, 2);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 2.8);
    ink(c, kCatInk, 1);
    rrect(c, pad, 6);
    CGContextStrokePath(c);
    CGRect tv = CGRectMake(18, 74, 64, 20);
    CGContextSaveGState(c);
    rrect(c, tv, 2);
    CGContextClip(c);
    vgrad(c, tv, screen, 2);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 2.8);
    ink(c, 0x45F06A, 1);
    CGContextMoveToPoint(c, 40, 79);
    CGContextAddLineToPoint(c, 46, 84);
    CGContextAddLineToPoint(c, 40, 89);
    CGContextMoveToPoint(c, 50, 89.5);
    CGContextAddLineToPoint(c, 60, 89.5);
    CGContextStrokePath(c);
    cat_paw(c, 25);
    cat_paw(c, 75);
}
void pt_art_agent_glyph(CGContextRef c, int agent) {
    if (agent != 0 && agent != 1) return;
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 6, 7);
    CGContextScaleCTM(c, 0.68, 0.68);
    pt_art_mascot(c);
    CGContextRestoreGState(c);
}
/* Sun rays behind a character: the loud background of the casual games of that time. */
static void rays(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat r, int n, CGFloat alpha) {
    fill(c, 0xFFFFFF, alpha);
    for (int i = 0; i < n; i++) {
        CGFloat a0 = i * 2 * M_PI / n, a1 = a0 + M_PI / n;
        CGContextMoveToPoint(c, cx, cy);
        CGContextAddLineToPoint(c, cx + r * cos(a0), cy + r * sin(a0));
        CGContextAddLineToPoint(c, cx + r * cos(a1), cy + r * sin(a1));
        CGContextClosePath(c);
    }
    CGContextFillPath(c);
}
/* The app icon, square: iOS rounds it, and iOS 6 adds its shine. The cat fills it, as the characters of that time do. */
void pt_art_app_icon(CGContextRef c) {
    static const stop sky[] = {{0xB8F4FF, 1, 0}, {0x37B8F4, 1, 0.55}, {0x0B5FB5, 1, 1}};
    CGContextSaveGState(c);
    CGContextClipToRect(c, CGRectMake(0, 0, 80, 80));
    rgrad(c, 40, 36, 66, sky, 3);
    rays(c, 40, 36, 80, 12, 0.16);
    CGContextTranslateCTM(c, 3, 4);
    CGContextScaleCTM(c, 0.74, 0.74);
    pt_art_mascot(c);
    CGContextRestoreGState(c);
}
/* Two stacked rack units on the blue of the Settings icons (the app's own tint). */
void pt_art_server_tile(CGContextRef c) {
    static const stop body[] = {{0x86A3CE, 1, 0}, {0x4569A6, 1, 1}};
    tile_body(c, body, 2);
    for (int i = 0; i < 2; i++) {
        CGRect u = CGRectMake(14, 18 + i * 25, 52, 20);
        fill(c, 0xFFFFFF, 0.95);
        rrect(c, u, 4);
        CGContextFillPath(c);
        fill(c, 0x4569A6, 1);
        CGContextFillEllipseInRect(c, CGRectMake(20, u.origin.y + 7, 6, 6));
        rect(c, 0x4569A6, 0.55, 32, u.origin.y + 8, 26, 4);
    }
}

/* The keyboard-matched keys. Light: the iOS 6 iPad keyboard modifier key (claude.png shift key column): white row,
 * body #D6D6D8 to #B2B2B7, left edge #4A4A4F, bottom rim #7C7C7F then #000000. Dark: chosen, not measured, to sit
 * next to UIKeyboardAppearanceAlert. style: 0 normal, 1 pressed, 2 armed (Ctrl, selection blue). */
void pt_art_key(CGContextRef c, CGFloat w, CGFloat h, int style, int dark) {
    static const stop n[] = {{0xD6D6D8, 1, 0}, {0xCACACC, 1, 0.5}, {0xB2B2B7, 1, 1}};
    static const stop p[] = {{0xA9A9AB, 1, 0}, {0x9D9D9F, 1, 0.5}, {0x8A8A8F, 1, 1}};
    static const stop dn[] = {{0x5E6065, 1, 0}, {0x505257, 1, 0.5}, {0x44464B, 1, 1}};
    static const stop dp[] = {{0x2A2B2F, 1, 0}, {0x303236, 1, 0.5}, {0x3A3C40, 1, 1}};
    static const stop a[] = {{0x058AF1, 1, 0}, {0x0377F0, 1, 0.5}, {0x015DE6, 1, 1}};
    const stop *s = style == 2 ? a : dark ? (style == 1 ? dp : dn) : (style == 1 ? p : n);
    fill(c, dark ? 0x0B0B0C : 0x000000, 1);
    rrect(c, CGRectMake(0, 1, w, h - 1), 5);
    CGContextFillPath(c);
    CGContextSaveGState(c);
    rrect(c, CGRectMake(0, 0, w, h - 2), 5);
    CGContextClip(c);
    vgrad(c, CGRectMake(0, 0, w, h - 2), s, 3);
    rect(c, 0xFFFFFF, style == 2 ? 0.35 : dark ? (style == 1 ? 0.08 : 0.28) : (style == 1 ? 0.3 : 1), 2, 1, w - 4, 1);
    rect(c, style == 2 ? 0x01316F : dark ? 0x1B1C1F : 0x7C7C7F, 1, 0, h - 3, w, 1);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 1);
    ink(c, style == 2 ? 0x01316F : dark ? 0x141517 : 0x4A4A4F, 1);
    rrect(c, CGRectMake(0.5, 0.5, w - 1, h - 3), 4.5);
    CGContextStrokePath(c);
}

/* Light: the keyboard's gradient between its keys (claude.png column x = 4): y 761 #9E9DA7, 770 #908F9A, 782 #83828C,
 * 794 #807F88, 806 #7C7B84, 818 #787881, and a 1 px #BDBDBD line on top. Dark: chosen, not measured. */
void pt_art_key_bar_bg(CGContextRef c, CGFloat w, CGFloat h, int dark) {
    static const stop l[] = {{0x9E9DA7, 1, 0}, {0x908F9A, 1, 0.18}, {0x83828C, 1, 0.42}, {0x807F88, 1, 0.66}, {0x7C7B84, 1, 0.9}, {0x787881, 1, 1}};
    static const stop d[] = {{0x3A3C41, 1, 0}, {0x2D2F33, 1, 0.4}, {0x232427, 1, 1}};
    if (dark) vgrad(c, CGRectMake(0, 0, w, h), d, COUNT(d));
    else vgrad(c, CGRectMake(0, 0, w, h), l, COUNT(l));
    rect(c, dark ? 0x5A5D63 : 0xBDBDBD, 1, 0, 0, w, 1);
}

/* 24x24, disc 10 pt. An off LED has no glow. */
void pt_art_led(CGContextRef c, uint32_t hex, int glow) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat r = ((hex >> 16) & 255) / 255.0, g = ((hex >> 8) & 255) / 255.0, b = (hex & 255) / 255.0;
    if (glow) {
        CGFloat comp[8] = {r, g, b, 0.45, r, g, b, 0}, loc[2] = {0, 1};
        CGGradientRef gl = CGGradientCreateWithColorComponents(cs, comp, loc, 2);
        CGContextDrawRadialGradient(c, gl, CGPointMake(12, 12), 0, CGPointMake(12, 12), 12, 0);
        CGGradientRelease(gl);
    }
    uint32_t hi = mix(hex, 0xFFFFFF, 0.6), lo = mix(hex, 0, 0.3);
    CGFloat comp[12] = {((hi >> 16) & 255) / 255.0, ((hi >> 8) & 255) / 255.0, (hi & 255) / 255.0, 1, r, g, b, 1,
                        ((lo >> 16) & 255) / 255.0, ((lo >> 8) & 255) / 255.0, (lo & 255) / 255.0, 1};
    CGFloat loc[3] = {0, 0.5, 1};
    CGGradientRef disc = CGGradientCreateWithColorComponents(cs, comp, loc, 3);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(7, 7, 10, 10));
    CGContextClip(c);
    CGContextDrawRadialGradient(c, disc, CGPointMake(10, 10), 0, CGPointMake(12, 12), 7, kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(c);
    CGGradientRelease(disc);
    CGColorSpaceRelease(cs);
    CGContextSetLineWidth(c, 1);
    ink(c, 0x000000, 0.5);
    CGContextStrokeEllipseInRect(c, CGRectMake(6.5, 6.5, 11, 11));
    fill(c, 0xFFFFFF, 0.6);
    CGContextFillEllipseInRect(c, CGRectMake(8.5, 8.5, 3, 3));
}

/* 12x12: the blue "running" dot, in the colour of calendar.png's today marker; Mail's unread dot is the same kind of dot. */
void pt_art_dot(CGContextRef c) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    uint32_t hi = mix(0x1879F2, 0xFFFFFF, 0.55), lo = mix(0x1879F2, 0, 0.35);
    CGFloat comp[12] = {((hi >> 16) & 255) / 255.0, ((hi >> 8) & 255) / 255.0, (hi & 255) / 255.0, 1,
                        0x18 / 255.0, 0x79 / 255.0, 0xF2 / 255.0, 1,
                        ((lo >> 16) & 255) / 255.0, ((lo >> 8) & 255) / 255.0, (lo & 255) / 255.0, 1};
    CGFloat loc[3] = {0, 0.5, 1};
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comp, loc, 3);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(1, 1, 10, 10));
    CGContextClip(c);
    CGContextDrawRadialGradient(c, g, CGPointMake(4.5, 4.5), 0, CGPointMake(6, 6), 6.5, kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    CGContextSetLineWidth(c, 1);
    ink(c, 0x0A3E8F, 0.7);
    CGContextStrokeEllipseInRect(c, CGRectMake(1.5, 1.5, 9, 9));
}

void pt_art_hud(CGContextRef c, CGFloat w, CGFloat h) {
    fill(c, 0x000000, 0.75);
    rrect(c, CGRectMake(0, 0, w, h), 14);
    CGContextFillPath(c);
}

/* A grouped row of the dark style. position: 0 single, 1 top, 2 middle, 3 bottom. selected: the blue selection gradient
 * (settings.png: #058AF1 to #015DE6) in the same shape. Corner radius 10 as the iOS 6 grouped table. */
void pt_art_row(CGContextRef c, CGFloat w, CGFloat h, int position, int selected) {
    static const stop body[] = {{0x3A3C40, 1, 0}, {0x303236, 1, 1}};
    static const stop sel[] = {{0x058AF1, 1, 0}, {0x0377F0, 1, 0.5}, {0x015DE6, 1, 1}};
    int top = position == 0 || position == 1, bottom = position == 0 || position == 3;
    CGFloat k = 10;
    CGContextSaveGState(c);
    rrect2(c, CGRectMake(0, 0, w, h), k, top, bottom);
    CGContextClip(c);
    vgrad(c, CGRectMake(0, 0, w, h), selected ? sel : body, selected ? 3 : 2);
    if (top) rect(c, selected ? 0xFFFFFF : 0x54575E, selected ? 0.3 : 0.7, k, 1, w - 2 * k, 1);
    CGContextRestoreGState(c);
    CGContextSetLineWidth(c, 1);
    ink(c, selected ? 0x01316F : 0x111214, 1);
    /* Outer edge only: the top and bottom edges of a middle row belong to its neighbours. */
    CGRect e = CGRectMake(0.5, top ? 0.5 : -1, w - 1, h - (top ? 0.5 : -1) - (bottom ? 0.5 : -1));
    rrect2(c, e, k - 0.5, top, bottom);
    CGContextStrokePath(c);
}

/* 20x20 black gear: an alpha mask. The bar button draws it white on the bar button body (iOS 6) or tinted (iOS 7). */
static void gear_shape(CGContextRef c) {
    for (int i = 0; i < 8; i++) {
        CGContextSaveGState(c);
        CGContextRotateCTM(c, i * M_PI / 4);
        CGContextFillRect(c, CGRectMake(-1.6, -9.5, 3.2, 4.5));
        CGContextRestoreGState(c);
    }
    CGContextFillEllipseInRect(c, CGRectMake(-6.2, -6.2, 12.4, 12.4));
}
void pt_art_gear(CGContextRef c) {
    CGContextTranslateCTM(c, 10, 10);
    CGContextAddRect(c, CGRectMake(-11, -11, 22, 22));
    CGContextAddEllipseInRect(c, CGRectMake(-2.6, -2.6, 5.2, 5.2));
    CGContextEOClip(c);
    fill(c, 0x000000, 1);
    gear_shape(c);
}

/* 160x160: two glossy rack units; the upper one has three LEDs (green, amber, off). */
void pt_art_empty_icon(CGContextRef c) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, 4, 6);
    CGContextScaleCTM(c, 1.52, 1.52);
    pt_art_mascot(c);
    CGContextRestoreGState(c);
}

#ifndef PT_ART_HOST
/* ---------------- UIKit side ---------------- */

@implementation PTArt

static NSMutableDictionary *g_cache;
static UIImage *cached(NSString *key, UIImage *(^make)(void)) {
    if (!g_cache) g_cache = [NSMutableDictionary dictionary];
    UIImage *i = g_cache[key];
    if (!i) g_cache[key] = i = make();
    return i;
}
/* Scale 0 = the screen's scale: 1 on the iPad mini. */
static UIImage *draw(CGFloat w, CGFloat h, BOOL opaque, void (^fn)(CGContextRef c)) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(w, h), opaque, 0);
    fn(UIGraphicsGetCurrentContext());
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

+ (UIColor *)hex:(uint32_t)rgb { return [self hex:rgb alpha:1]; }
+ (UIColor *)hex:(uint32_t)rgb alpha:(CGFloat)a {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:a];
}
+ (UIFont *)bold:(CGFloat)size { return [UIFont boldSystemFontOfSize:size]; }
+ (UIFont *)regular:(CGFloat)size { return [UIFont systemFontOfSize:size]; }

+ (UIImage *)agentIcon:(pt_agent)agent size:(CGFloat)size {
    return cached([NSString stringWithFormat:@"icon%d_%g", agent, size], ^{
        return draw(size, size, NO, ^(CGContextRef c) {
            CGContextScaleCTM(c, size / 80, size / 80);
            pt_art_agent_tile(c, agent);
            pt_art_icon_gloss(c); /* under the cat: the shine must not grey its eyes */
            pt_art_agent_glyph(c, agent);
        });
    });
}
+ (UIImage *)serverIcon:(CGFloat)size {
    return cached([NSString stringWithFormat:@"server_%g", size], ^{
        return draw(size, size, NO, ^(CGContextRef c) {
            CGContextScaleCTM(c, size / 80, size / 80);
            pt_art_server_tile(c);
            pt_art_icon_gloss(c);
        });
    });
}
+ (UIImage *)key:(PTKeyStyle)style dark:(BOOL)dark {
    return cached([NSString stringWithFormat:@"key%d%d", style, dark], ^{
        return [draw(12, 44, NO, ^(CGContextRef c) { pt_art_key(c, 12, 44, style, dark); }) resizableImageWithCapInsets:UIEdgeInsetsMake(0, 5, 0, 5)];
    });
}
+ (UIImage *)keyBarBackgroundDark:(BOOL)dark {
    return cached([NSString stringWithFormat:@"keybarbg%d", dark], ^{
        return [draw(4, 50, YES, ^(CGContextRef c) { pt_art_key_bar_bg(c, 4, 50, dark); }) resizableImageWithCapInsets:UIEdgeInsetsZero];
    });
}
+ (UIImage *)led:(PTLed)led {
    static const uint32_t hex[] = {0x3CE05A, 0xFFB000, 0xE5392B, 0x55524C};
    return cached([NSString stringWithFormat:@"led%d", led], ^{
        return draw(24, 24, NO, ^(CGContextRef c) { pt_art_led(c, hex[led], led != PTLedOff); });
    });
}
+ (UIImage *)dot { return cached(@"dot", ^{ return draw(12, 12, NO, ^(CGContextRef c) { pt_art_dot(c); }); }); }
+ (UIImage *)hud {
    return cached(@"hud", ^{
        return [draw(40, 40, NO, ^(CGContextRef c) { pt_art_hud(c, 40, 40); }) resizableImageWithCapInsets:UIEdgeInsetsMake(14, 14, 14, 14)];
    });
}
+ (UIImage *)gear { return cached(@"gear", ^{ return draw(20, 20, NO, ^(CGContextRef c) { pt_art_gear(c); }); }); }
+ (UIImage *)emptyIcon { return cached(@"empty", ^{ return draw(160, 160, NO, ^(CGContextRef c) { pt_art_empty_icon(c); }); }); }

static UIImage *row(PTRowPosition p, BOOL selected) {
    return cached([NSString stringWithFormat:@"row%d%d", p, selected], ^{
        /* 40 x 44: corners 12 pt, so the stretched middle is never a corner. A middle row has no vertical cap. */
        UIEdgeInsets caps = p == PTRowSingle ? UIEdgeInsetsMake(12, 12, 12, 12) : p == PTRowTop ? UIEdgeInsetsMake(12, 12, 1, 12)
                          : p == PTRowBottom ? UIEdgeInsetsMake(1, 12, 12, 12) : UIEdgeInsetsMake(0, 12, 0, 12);
        return [draw(40, 44, NO, ^(CGContextRef c) { pt_art_row(c, 40, 44, p, selected); }) resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch]; /* a tiled gradient shows stripes in a tall row */
    });
}
+ (UIImage *)rowBackground:(PTRowPosition)position { return row(position, NO); }
+ (UIImage *)selectedRow:(PTRowPosition)position { return row(position, YES); }
@end
#endif
