/* Draws the app's art on the Mac from the same recipes as the app (ios/src/PTArt.m, compiled with PT_ART_HOST).
 * usage: make_art launch <out-dir>   writes Default-Portrait~ipad.png (768x1004) and Default-Landscape~ipad.png (1024x748)
 *        make_art icon <out.png> <px>   the app icon at one size
 *        make_art sheet <out.png>    one preview sheet of every recipe, 2x, to check the art by eye */
#define PT_ART_HOST 1
#include "../ios/src/PTArt.m"
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static CGContextRef bitmap(int w, int h) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(c, 0, h); /* top-left origin, as in UIKit */
    CGContextScaleCTM(c, 1, -1);
    return c;
}
static int save(CGContextRef c, const char *path) {
    CGImageRef img = CGBitmapContextCreateImage(c);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(d, img, NULL);
    return CGImageDestinationFinalize(d) ? 0 : 1;
}
static void at(CGContextRef c, CGFloat x, CGFloat y, void (^fn)(void)) {
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, x, y);
    fn();
    CGContextRestoreGState(c);
}

/* The empty chrome of the first screen in light mode: the stock silver bar over a white master and the grouped
 * background, split at the 320 pt master width. The status bar is not in the image. */
static int launch(const char *dir, int w, int h, const char *name) {
    CGContextRef c = bitmap(w, h);
    pt_art_launch_body(c, w, h);
    pt_art_silver_bar(c, w);
    rect(c, 0x000000, 1, 320, 0, 1, h); /* settings.png x = 300: the divider is 1 px black, bar included */
    char path[1024];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    return save(c, path);
}

int main(int argc, char **argv) {
    if (argc == 4 && !strcmp(argv[1], "icon")) {
        int px = atoi(argv[3]);
        CGContextRef ic = bitmap(px, px);
        CGContextScaleCTM(ic, px / 80.0, px / 80.0);
        pt_art_app_icon(ic);
        return save(ic, argv[2]);
    }
    if (argc == 4 && !strcmp(argv[1], "mascot")) { /* transparent, for the README */
        int px = atoi(argv[3]);
        CGContextRef mc = bitmap(px, px);
        CGContextScaleCTM(mc, px / 100.0, px / 100.0);
        pt_art_mascot(mc);
        return save(mc, argv[2]);
    }
    if (argc != 3) return 2;
    if (!strcmp(argv[1], "launch"))
        return launch(argv[2], 768, 1004, "Default-Portrait~ipad.png") || launch(argv[2], 1024, 748, "Default-Landscape~ipad.png");
    CGContextRef c = bitmap(960, 640);
    CGContextScaleCTM(c, 2, 2);
    rect(c, 0xFFFFFF, 1, 0, 0, 480, 320);
    at(c, 10, 10, ^{ pt_art_silver_bar(c, 240); });
    at(c, 260, 10, ^{ pt_art_gear(c); });
    at(c, 10, 80, ^{ pt_art_key_bar_bg(c, 230, 50, 0); });
    for (int i = 0; i < 3; i++) at(c, 16 + i * 60, 83, ^{ pt_art_key(c, 52, 44, i, 0); });
    at(c, 250, 80, ^{ pt_art_key_bar_bg(c, 230, 50, 1); });
    for (int i = 0; i < 3; i++) at(c, 256 + i * 60, 83, ^{ pt_art_key(c, 52, 44, i, 1); });
    for (int i = 0; i < 4; i++) at(c, 280 + i * 26, 10, ^{ pt_art_led(c, (uint32_t[]){0x3CE05A, 0xFFB000, 0xE5392B, 0x55524C}[i], i < 3); });
    at(c, 400, 20, ^{ pt_art_dot(c); });
    for (int i = 0; i < 3; i++) at(c, 10 + i * 90, 140, ^{ CGContextScaleCTM(c, 29.0 / 80, 29.0 / 80); pt_art_agent_tile(c, i); pt_art_icon_gloss(c); pt_art_agent_glyph(c, i); });
    at(c, 110, 140, ^{ CGContextScaleCTM(c, 29.0 / 80, 29.0 / 80); pt_art_server_tile(c); pt_art_icon_gloss(c); });
    at(c, 10, 200, ^{ CGContextScaleCTM(c, 40.0 / 80, 40.0 / 80); pt_art_server_tile(c); pt_art_icon_gloss(c); });
    rect(c, 0x1E1F22, 1, 0, 240, 480, 80);
    for (int i = 0; i < 4; i++) at(c, 20, 245 + i * 17, ^{ pt_art_row(c, 200, 18, i == 0 ? 1 : i == 3 ? 3 : 2, 0); });
    for (int i = 0; i < 3; i++) at(c, 240, 245 + i * 17, ^{ pt_art_row(c, 200, 18, i == 0 ? 1 : i == 2 ? 3 : 2, i == 1); });
    at(c, 400, 100, ^{ pt_art_hud(c, 60, 60); });
    return save(c, argv[2]);
}
