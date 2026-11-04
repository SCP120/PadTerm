#import "PTTheme.h"
#import "PTArt.h"
#import "PTSettings.h"
#import <objc/runtime.h>

NSString *const PTAppearanceDidChangeNotification = @"PTAppearanceDidChange";
static NSString *const PTDarkKey = @"PTDarkAppearance";
static char kDarkTable;

/* Black glass popover (dark mode). Colours chosen, not measured; the arrow follows UIPopoverBackgroundView's contract. */
@interface PTPopoverBackgroundView : UIPopoverBackgroundView
@end
@implementation PTPopoverBackgroundView
@synthesize arrowOffset = _arrowOffset, arrowDirection = _arrowDirection;

+ (CGFloat)arrowHeight { return 13; }
+ (CGFloat)arrowBase { return 28; }
+ (UIEdgeInsets)contentViewInsets { return UIEdgeInsetsMake(8, 8, 8, 8); }
+ (BOOL)wantsDefaultContentAppearance { return NO; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.55;
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 4);
    }
    return self;
}
- (void)setArrowOffset:(CGFloat)o { _arrowOffset = o; [self setNeedsDisplay]; }
- (void)setArrowDirection:(UIPopoverArrowDirection)d { _arrowDirection = d; [self setNeedsDisplay]; }

/* The body is the view minus the arrow's strip; the arrow is drawn pointing up, then the whole path is rotated for the
 * other directions. */
- (void)drawRect:(CGRect)rect {
    CGFloat ah = [[self class] arrowHeight], ab = [[self class] arrowBase];
    BOOL vertical = _arrowDirection == UIPopoverArrowDirectionUp || _arrowDirection == UIPopoverArrowDirectionDown;
    CGFloat w = vertical ? self.bounds.size.width : self.bounds.size.height, h = vertical ? self.bounds.size.height : self.bounds.size.width;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    switch (_arrowDirection) {
    case UIPopoverArrowDirectionDown: CGContextTranslateCTM(c, w, h); CGContextRotateCTM(c, M_PI); break;
    case UIPopoverArrowDirectionLeft: CGContextTranslateCTM(c, 0, h); CGContextRotateCTM(c, -M_PI_2); break;
    case UIPopoverArrowDirectionRight: CGContextTranslateCTM(c, w, 0); CGContextRotateCTM(c, M_PI_2); break;
    default: break;
    }
    CGFloat off = (_arrowDirection == UIPopoverArrowDirectionDown || _arrowDirection == UIPopoverArrowDirectionRight) ? -_arrowOffset : _arrowOffset;
    CGFloat ax = floor(w / 2 + off), k = 10;
    CGRect body = CGRectMake(0.5, ah + 0.5, w - 1, h - ah - 1);
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, CGRectGetMinX(body) + k, CGRectGetMinY(body)); /* CGPathAddRoundedRect is iOS 7 */
    CGPathAddArcToPoint(p, NULL, CGRectGetMaxX(body), CGRectGetMinY(body), CGRectGetMaxX(body), CGRectGetMaxY(body), k);
    CGPathAddArcToPoint(p, NULL, CGRectGetMaxX(body), CGRectGetMaxY(body), CGRectGetMinX(body), CGRectGetMaxY(body), k);
    CGPathAddArcToPoint(p, NULL, CGRectGetMinX(body), CGRectGetMaxY(body), CGRectGetMinX(body), CGRectGetMinY(body), k);
    CGPathAddArcToPoint(p, NULL, CGRectGetMinX(body), CGRectGetMinY(body), CGRectGetMaxX(body), CGRectGetMinY(body), k);
    CGPathCloseSubpath(p);
    CGPathMoveToPoint(p, NULL, ax - ab / 2, ah + 0.5);
    CGPathAddLineToPoint(p, NULL, ax, 0.5);
    CGPathAddLineToPoint(p, NULL, ax + ab / 2, ah + 0.5);
    CGPathCloseSubpath(p);
    CGContextAddPath(c, p);
    CGContextSaveGState(c);
    CGContextClip(c);
    CGFloat comp[8] = {0x3E / 255.0, 0x40 / 255.0, 0x45 / 255.0, 0.97, 0x1A / 255.0, 0x1B / 255.0, 0x1E / 255.0, 0.97}, loc[2] = {0, 1};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comp, loc, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, h), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    CGContextRestoreGState(c);
    CGContextAddPath(c, p);
    CGContextSetLineWidth(c, 1);
    CGContextSetStrokeColorWithColor(c, [PTArt hex:0x000000 alpha:0.9].CGColor);
    CGContextStrokePath(c);
    CGContextSetStrokeColorWithColor(c, [PTArt hex:0xFFFFFF alpha:0.16].CGColor);
    CGContextMoveToPoint(c, k, ah + 1.5);
    CGContextAddLineToPoint(c, ax - ab / 2 - 4, ah + 1.5);
    CGContextMoveToPoint(c, ax + ab / 2 + 4, ah + 1.5);
    CGContextAddLineToPoint(c, w - k, ah + 1.5);
    CGContextStrokePath(c);
    CGPathRelease(p);
    CGContextRestoreGState(c);
}
@end

#ifdef PT_SELFTEST
static UIAlertView *g_lastAlert;
#endif

@implementation PTTheme {
    NSString *_name;
    uint8_t _fg[3], _bg[3];
}

- (instancetype)initName:(NSString *)name fg:(uint32_t)fg bg:(uint32_t)bg {
    if ((self = [super init])) {
        _name = name;
        for (int i = 0; i < 3; i++) { _fg[i] = (fg >> (16 - 8 * i)) & 255; _bg[i] = (bg >> (16 - 8 * i)) & 255; }
    }
    return self;
}
- (NSString *)name { return _name; }
- (const uint8_t *)fg { return _fg; }
- (const uint8_t *)bg { return _bg; }
- (UIColor *)fgColor { return [PTArt hex:(_fg[0] << 16) | (_fg[1] << 8) | _fg[2]]; }
- (UIColor *)bgColor { return [PTArt hex:(_bg[0] << 16) | (_bg[1] << 8) | _bg[2]]; }

+ (NSArray *)all {
    static NSArray *all;
    if (!all) all = @[
        [[PTTheme alloc] initName:@"classic" fg:0xF2F2F2 bg:0x18181B],
        [[PTTheme alloc] initName:@"light" fg:0x1E1E1E bg:0xFAFAFA],
        [[PTTheme alloc] initName:@"amber" fg:0xFFB000 bg:0x140C00],
        [[PTTheme alloc] initName:@"green" fg:0x3DFF70 bg:0x001407],
    ];
    return all;
}

+ (PTTheme *)current {
    NSString *n = [[NSUserDefaults standardUserDefaults] stringForKey:PTThemeKey];
    for (PTTheme *t in [self all]) if ([t.name isEqualToString:n]) return t;
    return [self all][0];
}
+ (void)select:(PTTheme *)theme { [[NSUserDefaults standardUserDefaults] setObject:theme.name forKey:PTThemeKey]; }

/* ---------------- appearance ---------------- */

+ (BOOL)isDarkAppearance { return [[NSUserDefaults standardUserDefaults] boolForKey:PTDarkKey]; }

+ (void)setDarkAppearance:(BOOL)dark {
    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:PTDarkKey];
    [self select:[self all][dark ? 0 : 1]];
    [self applyAppearance];
    [[NSNotificationCenter defaultCenter] postNotificationName:PTAppearanceDidChangeNotification object:nil];
}

/* Only the app's own window: the keyboard's overlay window spans the screen, and a colour on it hides the app. */
+ (void)applyAppearance {
    UIWindow *w = [[UIApplication sharedApplication].delegate respondsToSelector:@selector(window)]
        ? [UIApplication sharedApplication].delegate.window : nil;
    if (w) [self applyToWindow:w];
}

/* iOS 13 and later would otherwise follow the system setting: the window is pinned to the chosen mode. KVC keeps the call
 * out of the iOS 6 build (1 = light, 2 = dark in UIUserInterfaceStyle). */
+ (void)applyToWindow:(UIWindow *)w {
    BOOL dark = [self isDarkAppearance];
    w.backgroundColor = dark ? [UIColor blackColor] : [UIColor whiteColor];
    if ([w respondsToSelector:NSSelectorFromString(@"setOverrideUserInterfaceStyle:")])
        [w setValue:@(dark ? 2 : 1) forKey:@"overrideUserInterfaceStyle"];
}

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    bar.barStyle = [self isDarkAppearance] ? UIBarStyleBlack : UIBarStyleDefault;
}

+ (UIColor *)textColor { return [self isDarkAppearance] ? [PTArt hex:PT_DK_TEXT] : [UIColor blackColor]; }
+ (UIColor *)secondaryColor { return [PTArt hex:[self isDarkAppearance] ? PT_DK_TEXT2 : PT_GREY_TEXT]; }
+ (UIColor *)valueColor { return [PTArt hex:[self isDarkAppearance] ? PT_DK_VALUE : PT_SLATE]; }
+ (UIColor *)timeColor { return [PTArt hex:[self isDarkAppearance] ? 0x6CA8FF : PT_SEL_BOTTOM]; }
+ (UIColor *)surfaceColor { return [self isDarkAppearance] ? [PTArt hex:PT_DK_BG] : [UIColor groupTableViewBackgroundColor]; }

/* ---------------- tables ---------------- */

+ (NSString *)reuseId:(NSString *)base { return [base stringByAppendingString:[self isDarkAppearance] ? @"-dark" : @"-light"]; }

+ (void)styleTable:(UITableView *)t {
    BOOL grouped = t.style == UITableViewStyleGrouped;
    if ([self isDarkAppearance]) {
        UIView *bg = [[UIView alloc] init];
        bg.backgroundColor = [PTArt hex:grouped ? PT_DK_BG : PT_DK_PLAIN];
        t.backgroundView = bg;
        t.separatorColor = [PTArt hex:PT_DK_SEP];
        objc_setAssociatedObject(t, &kDarkTable, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(t, &kDarkTable)) { /* back to the stock look it had */
        UITableView *stock = [[UITableView alloc] initWithFrame:CGRectZero style:t.style];
        t.backgroundView = nil;
        t.backgroundColor = grouped ? [UIColor groupTableViewBackgroundColor] : [UIColor whiteColor];
        t.separatorColor = stock.separatorColor;
        objc_setAssociatedObject(t, &kDarkTable, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

+ (void)styleCell:(UITableViewCell *)c in:(UITableView *)t at:(NSIndexPath *)ip {
    /* Modern UIKit draws selected text in the blue of the selection itself, so the row's name disappears. iOS 6 already uses white. */
    c.textLabel.highlightedTextColor = [UIColor whiteColor];
    c.detailTextLabel.highlightedTextColor = [UIColor whiteColor];
    if (![self isDarkAppearance]) return;
    PTRowPosition pos = PTRowMiddle;
    if (t.style == UITableViewStyleGrouped) {
        NSInteger n = [t numberOfRowsInSection:ip.section];
        pos = n == 1 ? PTRowSingle : ip.row == 0 ? PTRowTop : ip.row == n - 1 ? PTRowBottom : PTRowMiddle;
        c.backgroundView = [[UIImageView alloc] initWithImage:[PTArt rowBackground:pos]];
    } else {
        UIView *flat = [[UIView alloc] init];
        flat.backgroundColor = [PTArt hex:PT_DK_PLAIN];
        c.backgroundView = flat;
    }
    c.selectedBackgroundView = [[UIImageView alloc] initWithImage:[PTArt selectedRow:pos]];
    c.backgroundColor = [UIColor clearColor];
    c.textLabel.backgroundColor = [UIColor clearColor];
    c.textLabel.textColor = [self textColor];
    c.detailTextLabel.backgroundColor = [UIColor clearColor];
    c.detailTextLabel.textColor = [self secondaryColor];
}

static UILabel *firstLabel(UIView *v) {
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UILabel class]]) return (UILabel *)s;
        UILabel *l = firstLabel(s);
        if (l) return l;
    }
    return nil;
}
+ (void)styleHeaderFooter:(UIView *)v {
    BOOL dark = [self isDarkAppearance];
    UILabel *l = [v respondsToSelector:@selector(textLabel)] ? [(id)v textLabel] : nil;
    if (![l isKindOfClass:[UILabel class]]) l = firstLabel(v);
    /* UIKit reuses these views: the light path must also undo the dark colours. */
    l.textColor = [PTArt hex:dark ? PT_DK_HEAD : PT_SLATE_HEAD]; /* settings.png: group header */
    l.shadowColor = dark ? [PTArt hex:0 alpha:0.8] : [PTArt hex:0xFFFFFF alpha:0.8];
    l.shadowOffset = CGSizeMake(0, dark ? -1 : 1);
    l.backgroundColor = [UIColor clearColor];
}

+ (Class)popoverBackgroundClass { return [self isDarkAppearance] ? [PTPopoverBackgroundView class] : nil; }
+ (UIKeyboardAppearance)keyboardAppearance { return [self isDarkAppearance] ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; }

+ (UILabel *)emptyLabel:(NSString *)text size:(CGFloat)size {
    BOOL dark = [self isDarkAppearance];
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [PTArt bold:size];
    l.textColor = [self secondaryColor];
    l.shadowColor = dark ? [PTArt hex:0 alpha:0.8] : [PTArt hex:0xFFFFFF alpha:0.9];
    l.shadowOffset = CGSizeMake(0, dark ? -1 : 1);
    l.backgroundColor = [UIColor clearColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

+ (void)showMessage:(NSString *)text title:(NSString *)title from:(UIViewController *)vc {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability" /* guarded by the class check; @available does not link on armv7 */
    if (NSClassFromString(@"UIAlertController")) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
        return;
    }
#pragma clang diagnostic pop
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
#ifdef PT_SELFTEST
    g_lastAlert = alert;
#endif
    [alert show];
}
#ifdef PT_SELFTEST
+ (UIAlertView *)testLastAlert { return g_lastAlert; }
#endif
@end
