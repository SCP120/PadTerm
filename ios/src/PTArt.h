#import <UIKit/UIKit.h>
#include "pt_launch.h"

/* Light-mode colours measured from real iOS 6.1.3 captures of this iPad (build/ipad/ref/settings.png and calendar.png).
 * The sample points are listed in docs/design/ios6-nostalgia-ui.md section 2. */
#define PT_SLATE 0x385487        /* settings.png: value text ("Not Connected") */
#define PT_SLATE_HEAD 0x4C566C   /* settings.png: grouped section header text */
#define PT_TITLE_GREY 0x717880   /* settings.png: bar title text, darkest pixel of "General" */
#define PT_GREY_TEXT 0x8C8C8C    /* calendar.png: "No Events" */
#define PT_SEL_TOP 0x058AF1      /* settings.png: selected row gradient, top */
#define PT_SEL_BOTTOM 0x015DE6   /* settings.png: selected row gradient, bottom */
#define PT_DOT_BLUE 0x1879F2     /* calendar.png: today marker; the unread dot of the session rows */
#define PT_DETAIL_BG_TOP 0xE2E5EA /* settings.png: detail background under the bar, x = 700 */
#define PT_MASTER_BG 0xDADCE2    /* settings.png: master row, x = 301 */
#define PT_CLAUDE 0xD97757       /* the Claude brand orange; the app's own, not from iOS */

/* Dark-mode colours: chosen, not measured. Sources of the look: Photos, Videos and iBooks night (black chrome, grey text),
 * Final Cut Pro X and Aperture (charcoal panels). Contrast against the row body: text 13:1, secondary 5:1, value 5.5:1. */
#define PT_DK_BG 0x1E1F22        /* behind grouped rows */
#define PT_DK_PLAIN 0x2B2C30     /* plain table rows (the master list) */
#define PT_DK_ROW_TOP 0x3A3C40
#define PT_DK_ROW_BOTTOM 0x303236
#define PT_DK_ROW_EDGE 0x111214
#define PT_DK_ROW_HI 0x54575E
#define PT_DK_TEXT 0xF2F2F2
#define PT_DK_TEXT2 0xA6AAB2
#define PT_DK_VALUE 0x7FB0F5
#define PT_DK_HEAD 0xA2A6AE
#define PT_DK_SEP 0x1B1C1F

typedef enum { PTLedGreen, PTLedAmber, PTLedRed, PTLedOff } PTLed;
typedef enum { PTKeyNormal, PTKeyPressed, PTKeyArmed } PTKeyStyle;
typedef enum { PTRowSingle, PTRowTop, PTRowMiddle, PTRowBottom } PTRowPosition;

/* Every image is drawn once with CoreGraphics (the recipes sit at the top of PTArt.m) and cached. Main thread only. */
@interface PTArt : NSObject
+ (UIColor *)hex:(uint32_t)rgb;
+ (UIColor *)hex:(uint32_t)rgb alpha:(CGFloat)alpha;
+ (UIFont *)bold:(CGFloat)size;            /* the system font: Helvetica on iOS 6, as the stock cells use */
+ (UIFont *)regular:(CGFloat)size;
+ (UIImage *)agentIcon:(pt_agent)agent size:(CGFloat)size; /* glossy rounded icon with the mascot, or the Shell glyph */
+ (UIImage *)serverIcon:(CGFloat)size;                     /* the same icon family, for a server row */
+ (UIImage *)key:(PTKeyStyle)style dark:(BOOL)dark;        /* resizable, 44 pt */
+ (UIImage *)keyBarBackgroundDark:(BOOL)dark;              /* 50 pt, the keyboard's own gradient */
+ (UIImage *)led:(PTLed)led;
+ (UIImage *)dot;                          /* 12x12 blue "running" dot */
+ (UIImage *)hud;
+ (UIImage *)gear;                         /* 20x20 alpha mask: the bar draws it in the bar's own style */
+ (UIImage *)emptyIcon;
+ (UIImage *)rowBackground:(PTRowPosition)position;        /* dark grouped row, resizable */
+ (UIImage *)selectedRow:(PTRowPosition)position;          /* the classic blue gradient in the same shape, resizable */
@end
